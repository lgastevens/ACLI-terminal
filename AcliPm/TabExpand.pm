# ACLI sub-module
package AcliPm::TabExpand;
our $Version = "1.01";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(tabExpand tabExpandLite);
}
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::DebugMessage;
use AcliPm::GlobalConstants;
use AcliPm::MaskUnmaskChars;


sub matchCommand { # Matches a command entered by user with a list of available command options
	my $entered = shift;
	my @available = @_;
	my (@match, $regex);
	return ([]) unless $entered;
	# 1st see if we have an exact match
	$regex = qr/^\Q$entered\E$/;
	@match = grep(/$regex/, @available);
	return (\@match) if scalar @match == 1;
	# If not, then try a partial match
	$regex = qr/^\Q$entered\E/;
	@match = grep(/$regex/, @available);
	return (\@match) if @match; # Return the list, whatever it may be
	for my $avail (@available) {
		if ($avail =~ /^regex:(.+)$/) {
			$regex = $1;
			return ([$entered], $avail) if $entered =~ /^$regex$/;
		}
	}
	return ([]);
}


sub syntaxList{ # Produce an ordered list of syntax commands
	my @keys = grep(length $_, @_); # Filter out empty keys
	my $syntax;
	if (scalar grep(/^\d+$/, @keys) == scalar @keys) { # If all keys are numeric
		$syntax .= join('|', sort {$a <=> $b} @keys); # Do a numeric sort
	}
	else {
		$syntax .= join('|', sort {$a cmp $b} @keys); # Do an alphabetic sort
	}
	if (scalar @keys < scalar @_) { # There was empty key => optional format
		$syntax = '[' . $syntax . ']';
	}
	return $syntax;
}


sub tabExpandLite { # Reduced tabExpand which only returns 1st command keyword or empty string if none recognized, or just true/false in flagMode
	my ($cmdHash, $cliCmd, $flagMode) = @_;
	$cliCmd =~ s/^\s+//;		# Remove leading spaces
	$cliCmd =~ s/([^\s@])\?$/$1 ?/;	# If command ends with ? make sure space before ? (except for @?)
	$cliCmd =~ s/\s.+$//;		# Keep only 1st keyword; remove everything after 1st space (gets rid of ? if there)
	my ($cmdList) = matchCommand($cliCmd, keys %$cmdHash);
	debugMsg(256, join('', "tabExpandLite : number of matched commands = ", scalar @$cmdList, " / list = ", join(',', @$cmdList), "\n"));
	return $cmdList->[0] if @$cmdList && scalar @$cmdList == 1;
	return (@$cmdList ? 1 : 0) if $flagMode;
	return '';	# Otherwise
}


sub tabExpand { # Process a command for tab completion
		# If it's recognized it is expanded and returned with a trailing space; otherwise nothing is returned
		# If $checkSyntax set:
		# - in case of match, returned command is expanded but no trailing space is added
		# - if more than 1 command in tree matches and last char is ?, then a list is returned
		# - a check is performed on validity of arguments; if they don't match, expanded command is returned with trailing ?
	my ($cmdHash, $cliCmd, $checkSyntax, $tabExpand) = @_;

	debugMsg(256, "tabExpand : called with >$cliCmd< and checkSyntax: ", \$checkSyntax, "\n");
	# Process the input command to clean it up
	$cliCmd =~ s/\s+$//;			# Remove trailing spaces
	$cliCmd =~ s/^\s+//;			# Remove leading spaces
	$cliCmd =~ s/([^\s@])\?$/$1 ?/;		# If command ends with ? make sure space before ? (except for @?)
	$cliCmd = quoteCurlyMask($cliCmd, ' ');	# Mask spaces inside quotes
	$cliCmd =~ s/\s+/ /g;			# Replace multiple spaces with single space (except inside quotes)
	my @cliCmd = split($Space, $cliCmd);	# Split it into an array
	@cliCmd = map { quoteCurlyUnmask($_, ' ') } @cliCmd;	# Needs to re-assign, otherwise quoteCurlyUnmask won't work
	$cliCmd[0] = '' unless $cliCmd[0];	# First word must be defined
	debugMsg(256, "tabExpand : command split into array : ", \join(',', @cliCmd), "\n");

	my $cmdWord = shift @cliCmd;
	my $parsed = '';
	while (length $cmdWord && ref $cmdHash eq 'HASH') {
		my ($cmdList, $cmdNextHash) = matchCommand($cmdWord, keys %$cmdHash);
		debugMsg(256, join('', "tabExpand : number of matched commands = ", scalar @$cmdList, " / list = ", join(',', @$cmdList), "\n"));
		last unless @$cmdList; # No match, come out
		if (scalar @$cmdList == 1) { # Exact (single) command matched; continue while loop
			$cmdWord = $cmdList->[0];
			$parsed .= (length($parsed) ? ' ':'') . $cmdWord;
			$cmdHash = defined $cmdNextHash ? $cmdHash->{$cmdNextHash} : $cmdHash->{$cmdWord};
			$cmdWord = shift @cliCmd;
			$cmdWord = '' unless defined $cmdWord;
		}
		else { # More than one match; return the list
			if ($checkSyntax && $cliCmd =~ /\?$/) { # Only return list in check syntax mode and if trailing ?
				debugMsg(256, "tabExpand - more than 1 match : returning list\n");
				return ('', join($Space, @$cmdList));
			}
			elsif ($checkSyntax && $parsed) {
				my $syntax = "Syntax: $parsed " . syntaxList(keys %$cmdHash);
				debugMsg(256, "tabExpand - more than 1 match : returning syntax list : $syntax\n");
				return ('', $syntax);
			}
			if ($tabExpand) {
				my $offset = length $cmdWord;
				my $length = 1;
				my $common;
				do {
					$common = substr($cmdList->[0], $offset, $length++);
				} until scalar grep(/^\Q$cmdWord$common/, @$cmdList) < scalar @$cmdList;
				chop $common;
				$cliCmd .= $common;
				debugMsg(256, "tabExpand - more than 1 match - common substring expansion - returning : $cliCmd\n");
				return $cliCmd;
			}
			else {
				debugMsg(256, "tabExpand - more than 1 match : returning null string\n");
				return '';
			}
		}
	}
	debugMsg(256, "tabExpand : parsed command : >$parsed<\n");
	return '' unless length $parsed; # If no match come out
	debugMsg(256, "tabExpand : what cmd points to in hash structure(cmdHash) : >$cmdHash<\n");
	my $cliArgs = join(' ', $cmdWord, @cliCmd);
	debugMsg(256, "tabExpand : arguments left(cliArgs) : >$cliArgs<\n");
	$cliCmd = $parsed . (length($cliArgs) ? ' '.$cliArgs : '');
	debugMsg(256, "tabExpand : expanded cli command with args : >$cliCmd<\n");

	# If not checkSyntax
	#	cliArgs no match			-> return cmd (no space added)
	#	cliArgs is match			-> return cmd + space
	# Command is not complete
	#	regex:key				-> return parsed + '?'
	#	else					-> return syntax list (we don't care about arg)
	# Command is complete
	#	cliArgs is '?'
	#		hash keys exist
	#			arg pat set		-> return cmd (includes '?')
	#			arg pat not set		-> return syntax list
	#		no hash keys
	#			arg pat set		-> return cmd (includes '?')
	#			arg pat not set		-> return syntax without '?'
	#	argMatch is null && cliArgs is not null	-> return syntax list
	#	cliArgs is match			-> return cmd
	#	cliArgs no match			-> return parsed + '?'

	unless ($checkSyntax) { # If not checkSyntax -> return cmd + space
		if (length $cliArgs) {
			debugMsg(256, "tabExpand - no checkSyntax - returning : $cliCmd\n");
		}
		else {
			$cliCmd .= ' ';
			debugMsg(256, "tabExpand - no checkSyntax - append space - returning : $cliCmd\n");
		}
		return $cliCmd;
	}
	if (ref $cmdHash eq 'HASH' && !exists $cmdHash->{''}) { # Command is not complete -> return syntax list (we don't care about arg)
		if ( grep(/^regex:/, keys %$cmdHash) ) {
			$parsed .= ' ?';
			debugMsg(256, "tabExpand - checkSyntax - incomplete command - regex:key - returning : $parsed\n");
			return $parsed;
		}
		else {
			my $syntax = "Syntax: $parsed " . syntaxList(keys %$cmdHash);
			debugMsg(256, "tabExpand - checkSyntax - incomplete command - returning syntax list : $syntax\n");
			return ('', $syntax);
		}
	}
	if ($cliArgs eq '?') {
		if (ref $cmdHash eq 'HASH') {
			if (length $cmdHash->{''}) { # Command is complete & We have args & Arg is '?' & keys exist & arg pat set -> return cmd (includes '?')
				debugMsg(256, "tabExpand - checkSyntax - complete command - arg is ? - hash keys exist - arg pat set - returning : $cliCmd\n");
				return $cliCmd;
			}
			else { # Command is complete & We have args & Arg is '?' & keys exist & arg pat not set -> return syntax list
				my $syntax = "Syntax: $parsed " . syntaxList(keys %$cmdHash);
				debugMsg(256, "tabExpand - checkSyntax - complete command - arg is ? - hash keys exist - returning syntax list : $syntax\n");
				return ('', $syntax);
			}
		}
		else {
			if (length $cmdHash) { # Command is complete & We have args & Arg is '?' & no hash keys & arg pat set -> return cmd (includes '?')
				debugMsg(256, "tabExpand - checkSyntax - complete command - arg is ? - no hash keys - arg pat set - returning : $cliCmd\n");
				return $cliCmd;
			}
			else { # Command is complete & We have args & Arg is '?' & no hash keys & arg pat not set -> return syntax without '?'
				my $syntax = "Syntax: $parsed";
				debugMsg(256, "tabExpand - checkSyntax - complete command - arg is ? - no hash keys - returning syntax without ? : $syntax\n");
				return ('', $syntax);
			}
		}
	}

	my $argMatch = ref $cmdHash ne 'HASH' ? $cmdHash : $cmdHash->{''}; # If we get here, $cmdHash is either not a hash, or if it is there is a '' key
	debugMsg(256, "tabExpand : arguments pattern match to use : >$argMatch<\n");

	if ($argMatch eq '' && $cliArgs ne '') { # Command is complete & We have args & No args allowed
		my $syntax = "Syntax: $parsed " . ($cmdHash eq 'HASH' ? syntaxList(keys %$cmdHash) :'');
		debugMsg(256, "tabExpand - checkSyntax - complete command - arg is not null - arg is not allowed - returning syntax list : $syntax\n");
		return ('', $syntax);
	}
	elsif ($cliArgs =~ /^$argMatch$/) { # Command is complete & We have args & Arg is match -> return cmd
		debugMsg(256, "tabExpand - checkSyntax - complete command - arg is match - returning : $cliCmd\n");
		return $cliCmd;
	}
	else { # Command is complete & We have args & Arg is NO match -> return parsed + '?'
		$parsed .= ' ?';
		debugMsg(256, "tabExpand - checkSyntax - complete command - arg is NO match - returning : $parsed\n");
		return $parsed;
	}
}

1;
