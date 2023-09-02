# ACLI sub-module
package AcliPm::Alias;
our $Version = "1.05";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(loadDefaultAliasFiles loadAliasFile deAlias);
}
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::GlobalDefaults;
use AcliPm::GlobalMatchingPatterns;
use AcliPm::DebugMessage;
use AcliPm::ParseCommand;
use AcliPm::Print;
use AcliPm::Prompt;
use AcliPm::QuotesRemove;
use AcliPm::Sourcing;
use AcliPm::TabExpand;
use AcliPm::Variables;

sub loadDefaultAliasFiles { # Locates and reads in the default alias files
	my $db = shift;
	my $term_io = $db->[2];
	my $alias = $db->[11];
	my $aliasFile;

	# Determine which acli.alias file to work with
	foreach my $path (@AcliFilePath) {
		if (-e "$path/$AliasFileName") {
			$aliasFile = "$path/$AliasFileName";
			last;
		}
	}
	return unless defined $aliasFile;
	$term_io->{AliasFile} = File::Spec->canonpath($aliasFile);
	return unless loadAliasFile($db, $aliasFile);
	$aliasFile = undef;

	# Determine which merge.alias file to work with
	foreach my $path (@AcliMergeFilePath) {
		if (-e "$path/$AliasMergeFileName") {
			$aliasFile = "$path/$AliasMergeFileName";
			last;
		}
	}
	unless(defined $aliasFile) {
		$term_io->{AliasMergeFile} = '';
		return;
	}
	$term_io->{AliasMergeFile} = File::Spec->canonpath($aliasFile);
	return loadAliasFile($db, $aliasFile, 1);	# Merge it
}


sub loadAliasFile { # Reads an alias file into the alias data structure
	my ($db, $aliasFile, $merge) = @_;
	my $alias = $db->[11];

	%$alias = () unless $merge;	# Wipe alias structure clean except if merging

	#alias-hash = (
	#	'alias'	=> {
	#		DSC	=> <User provided description of alias>
	#		SYN	=> <User provided syntax of alias>
	#		MVR	=> <N of mandatory variables>,
	#		OVR	=> <N of optional variables>,
	#		VAR	=> {
	#			<var1_name>	=> <order in sequence of variables>,
	#			<var2_name>	=> <order in sequence of variables>,
	#		},
	#		SEL	=> [
	#			{
	#				CND	=> <condition_x>,
	#				CMD	=> <command to execute if condition_x true>,
	#			},
	#			{
	#				CND	=> <condition_y>,
	#				CMD	=> <command to execute if condition_y true>,
	#			},
	#			...
	#		],
	#		FLG	=> <Flag, set once the alias has a genuine CMD defined - not just &ones>
	#	},
	#);

	cmdMessage($db, ($merge ? 'Merging' : 'Loading') . " alias file: " . File::Spec->rel2abs($aliasFile) . "\n");
	my $lineNumber = 0;
	my ($name, $condition, $multcond);
	open(ALIAS, '<', $aliasFile) or do {
		cmdMessage($db, "Unable to open alias file " . File::Spec->canonpath($aliasFile) . "\n");
		return;
	};
	while (<ALIAS>) {
		chomp;
		$lineNumber++;
		next if /^\s*$/; # skip empty lines
		next if /^\s*#/; # skip comment lines
		next if /^\s*\$VERSION/i; # skip version line
		/^(\S+)\s+(?:~:(\"[^\"]+\"|\'[^\']+\')\s+)?=\s+(.+?)\s*$/ && do { # Simple alias
			($name, $condition) = ($1, 0);
			if (defined $alias->{$name}) {
				delete $alias->{$name};
				debugMsg(512,"WARNING: alias $name was already defined!\n");
			}
			$alias->{$name}{DSC} = quotesRemove($2) if defined $2;
			$alias->{$name}{MVR} = 0; # Store number of mandatory variables
			$alias->{$name}{OVR} = 0; # Store number of optional variables
			$alias->{$name}{SEL}[0]{CND} = '1';
			$alias->{$name}{SEL}[0]{CMD} = $3;
			$alias->{$name}{FLG} |= $alias->{$name}{SEL}[0]{CMD} !~ /^&/;
			debugMsg(512,"Alias: $name\n");
			debugMsg(512,"Alias: $name	CND0: $alias->{$name}{SEL}[0]{CND}\n");
			debugMsg(512,"Alias: $name	CMD0: $alias->{$name}{SEL}[0]{CMD}\n");
			$multcond = undef;
			next;
		};
		/^(\S+)((?:\s+(?:\$[\d\w\-_]+|\[\$[\d\w\-_]+\]))+)\s+(?:~:(\"[^\"]+\"|\'[^\']+\')\s+)?=\s+(.+?)\s*$/ && do { # Simple alias with optional/mandatory variables
			($name, $condition) = ($1, 0);
			if (defined $alias->{$name}) {
				delete $alias->{$name};
				debugMsg(512,"WARNING: alias $name was already defined!\n");
			}
			$alias->{$name}{DSC} = quotesRemove($3) if defined $3;
			$alias->{$name}{SEL}[0]{CND} = '1';
			$alias->{$name}{SEL}[0]{CMD} = $4;
			$alias->{$name}{FLG} |= $alias->{$name}{SEL}[0]{CMD} !~ /^&/;
			(my $varfield = $2) =~ s/\t/ /g; # Replacing tabs with spaces
			$alias->{$name}{MVR} = 0; # Reset number of mandatory variables
			$alias->{$name}{OVR} = 0; # Reset number of optional variables
			debugMsg(512,"Alias: $name\n");
			my $order = 1;
			debugMsg(512,"Alias: $name	variables to process:$varfield\n");
			foreach my $var (split($Space, $varfield)) {
				$var =~ s/\$//g; # delete $ char
				next unless length $var;
				if ($var =~ s/[\[\]]//g) { # delete all [,] chars
					$alias->{$name}{OVR}++; # Increase optional var count
					debugMsg(512,"Alias: $name	VAR$order optional : $var\n");
				}
				else {
					if ($alias->{$name}{OVR}) {
						print "- cannot have mandatory vars following optional ones; on line ", $lineNumber, "\n";
						print "Unable to read alias file!\n";
						close ALIAS;
						return;
					}
					$alias->{$name}{MVR}++; # Increase mandatory var count
					debugMsg(512,"Alias: $name	VAR$order mandatory: $var\n");
				}
				$alias->{$name}{VAR}{$var} = $order;
				$order++;
			}
			debugMsg(512,"Alias: $name	CND0: $alias->{$name}{SEL}[0]{CND}\n");
			debugMsg(512,"Alias: $name	CMD0: $alias->{$name}{SEL}[0]{CMD}\n");
			$multcond = undef;
			next;
		};
		/^(\S+)\s*$/ && do { # Multiple condition alias with no variables
			($name, $multcond, $condition) = ($1, 1, undef);
			if (defined $alias->{$name}) {
				delete $alias->{$name};
				debugMsg(512,"WARNING: alias $name was already defined!\n");
			}
			$alias->{$name}{MVR} = 0; # Store number of mandatory variables
			$alias->{$name}{OVR} = 0; # Store number of optional variables
			debugMsg(512,"Alias: $name\n");
			next;
		};
		/^(\S+)((?:\s+(?:\$[\d\w\-_]+|\[\$[\d\w\-_]+\]))+)\s*$/ && do { # Multiple condition alias with optional/mandatory variables
			($name, $multcond, $condition) = ($1, 1, undef);
			if (defined $alias->{$name}) {
				delete $alias->{$name};
				debugMsg(512,"WARNING: alias $name was already defined!\n");
			}
			(my $varfield = $2) =~ s/\t/ /g; # Replacing tabs with spaces
			$alias->{$name}{MVR} = 0; # Reset number of mandatory variables
			$alias->{$name}{OVR} = 0; # Reset number of optional variables
			debugMsg(512,"Alias: $name\n");
			my $order = 1;
			debugMsg(512,"Alias: $name	variables to process:$varfield\n");
			foreach my $var (split($Space, $varfield)) {
				$var =~ s/\$//g; # delete $ char
				next unless length $var;
				if ($var =~ s/[\[\]]//g) { # delete all [,] chars
					$alias->{$name}{OVR}++; # Increase optional var count
					debugMsg(512,"Alias: $name	VAR$order optional : $var\n");
				}
				else {
					if ($alias->{$name}{OVR}) {
						print "- cannot have mandatory vars following optional ones; on line ", $lineNumber, "\n";
						print "Unable to read alias file!\n";
						close ALIAS;
						return;
					}
					$alias->{$name}{MVR}++; # Increase mandatory var count
					debugMsg(512,"Alias: $name	VAR$order mandatory: $var\n");
				}
				$alias->{$name}{VAR}{$var} = $order;
				$order++;
			}
			next;
		};
		/^\s+\?:(.+)$/ && $name && do { # Syntax of current alias
			$alias->{$name}{SYN} = quotesRemove($1);
			$alias->{$name}{SYN} =~ s/\\n/\n/g; # Restore newlines
			$alias->{$name}{SYN} =~ s/\\t/\t/g; # Restore tabs
			$condition = undef;
			next;
		};
		/^\s+~:(.+)$/ && $name && do { # Description of current alias
			$alias->{$name}{DSC} = quotesRemove($1);
			$condition = undef;
			next;
		};
		/^\s+;\s*(.+?)\s*$/ && $name && defined $condition && do { # Semicolon fragmented commands on extra lines; moved up otherwise this will match below: "; $v = x" 
			$alias->{$name}{SEL}[$condition]{CMD} .= "; $1";
			debugMsg(512,"Alias: $name	CMD$condition: $alias->{$name}{SEL}[$condition]{CMD}\n");
			next;
		};
		/^\s+(.+?)\s+=\s+(.+?)\s*$/ && $multcond && do { # Conditions of current alias
			$condition = defined $condition ? $condition + 1 : 0;
			$alias->{$name}{SEL}[$condition]{CND} = $1;
			$alias->{$name}{SEL}[$condition]{CMD} = $2;
			$alias->{$name}{FLG} |= $alias->{$name}{SEL}[$condition]{CMD} !~ /^&/;
			debugMsg(512,"Alias: $name	CND$condition: $alias->{$name}{SEL}[$condition]{CND}\n");
			debugMsg(512,"Alias: $name	CMD$condition: $alias->{$name}{SEL}[$condition]{CMD}\n");
			next;
		};
		cmdMessage($db, "- syntax error on line $lineNumber\n");
		cmdMessage($db, "Unable to read alias file " . File::Spec->canonpath($aliasFile) . "\n");
		close ALIAS;
		return;
	}
	close ALIAS;
	return 1;
}


sub deRefAliasVar { # Replace alias variables
	my ($alias, $aliascmd, $valueList, $varField, $varName) = @_;
	my $varOrder = $alias->{$aliascmd}{VAR}{$varName};

	if (defined $varOrder) { # Variable is defined in structure
		my $varValue = $$valueList[$varOrder];
		if (defined $varValue) { # And a value was entered in the command line
			debugMsg(4,"=De-alias: $aliascmd / De-RefVar: \$$varName / >$varField< ");
			$varField =~ s/\$$varName/$varValue/;
			$varField =~ s/[\[\]]//g;
			debugMsg(4,"to >$varField<\n");
			return $varField;
		}
		elsif ($varField !~ /^\[.+\]$/) { # This is a mandatory variable
			return "££$varOrder££";
		}
		else { # This is an optional variable
			return '';
		}
	}
	# Else we leave it untouched; e.g. if cmd was: @vars prompt $var
	debugMsg(4,"=De-alias: $aliascmd / De-RefVar: $varName / not defined by alias / >$varField< preserving\n");
	return $varField;
}


sub replaceVar { # Replace alias variable
	my ($alias, $aliascmd, $valueList, $varName) = @_;
	my $varValue;
	$varValue = $$valueList[$alias->{$aliascmd}{VAR}{$varName}] if defined $alias->{$aliascmd}{VAR}{$varName};
	$varValue = '' unless defined $varValue;
	$varValue = "'".$varValue."'"; # in between single quotes
	return $varValue;
}


sub deAlias { # Dereference an alias command
	my ($db, $cmdParsed, $aliasTrail, $silent) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $alias = $db->[11];

	# If ending with ;, strip it off and come out of deAlias
	return 1 if $cmdParsed->{command}->{str} =~ s/\s*;$//;

	# Check whether we have a matching alias name
	return 0 unless length $cmdParsed->{command}->{str};
	my $command = $cmdParsed->{command}->{str}; # Make a copy before making mods
	$command =~ s/(\S)\?$/$1 ?/; # If command ends with ? make sure space before ?
	$command =~ s/\s+/ /g; # Replace consecutive spaces with single space or it will mess up split below
	my @command = split($Space, $command);
	my $aliascmd = tabExpand($alias, $command[0]);
	debugMsg(4,"=De-alias: - tabExpand returned: >$aliascmd<\n");
	return 0 unless $aliascmd;
	$aliascmd =~ s/\s+$//; # Remove trailing space
	debugMsg(4,"=De-alias:>$aliascmd<\n");

	# Prepare the prompt and alias echo header
	my $prompt = appendPrompt($host_io, $term_io);
	my $aliasEcho = echoPrompt($term_io, $prompt, 'alias');

	# Check for alias loops
	if ( (defined $aliasTrail && $aliasTrail->{$aliascmd}) || $term_io->{SourceActive}->{alias}->{$aliascmd}) { # Alias feedback loop...
		debugMsg(4,"=De-alias: - alias loop detected, refusing alias\n");
		#printOut($script_io, "\nAlias loop detected! Aborting command processing\n$prompt") unless $silent;
		#stopSourcing($db);
		#return;
		return 0;
	}

	# Check request for syntax '?'
	if ($#command == 1 && $command[1] eq '?') {
		return 0 if $command[0] =~/$AliasPreventSyntax/;
		if (defined $alias->{$aliascmd}{SYN}) { # We have syntax string for this alias
			printOut($script_io, "\n$alias->{$aliascmd}{SYN}\n$prompt") unless $silent;
			return;
		}
		if ($alias->{$aliascmd}{FLG}) { # We have no syntax string for it; so we build it based on what we have
			my $aliasSyntax = '';
			my $mvr = $alias->{$aliascmd}{MVR};
			my $ovr = $alias->{$aliascmd}{OVR};
			foreach my $var (sort {$alias->{$aliascmd}{VAR}{$a} <=> $alias->{$aliascmd}{VAR}{$b}} keys %{$alias->{$aliascmd}{VAR}}) {
				if    ($mvr) { $aliasSyntax .= " \$$var"; $mvr-- }
				elsif ($ovr) { $aliasSyntax .= " [\$$var]"; $ovr-- }
				else { $aliasSyntax .= " - Inconsistency: more vars than expected !: $var" }
			}
			printOut($script_io, "\n$aliasEcho$aliascmd$aliasSyntax\n$prompt") unless $silent;
			return;
		}
		return 0;	# No alias
	}
	return 0 if ($alias->{$aliascmd}{MVR} + $alias->{$aliascmd}{OVR}) < $#command; # We have more args than alias wants; come out

	# Now check it has been supplied with all mandatory variables
	if ($alias->{$aliascmd}{MVR} > $#command) { # We are missing some vars
		printOut($script_io, "\n$aliasEcho$aliascmd <requires $alias->{$aliascmd}{MVR} variables; only $#command provided>\n$prompt") unless $silent;
		stopSourcing($db);
		return;
	}

	# Now check its de-reference conditions
	my ($expression, $dealiascmd);
	CONDITIONS: for my $c (0 .. $#{$alias->{$aliascmd}{SEL}}) { # For every condition for alias
		$expression = $alias->{$aliascmd}{SEL}[$c]{CND};
		$expression =~ s/{([\w_]+)(?:\[(\d+)\])?}/replaceAttribute($db, $1, $2, 1)/ge;
		$expression =~ s/\$([\d\w\-_]+)/replaceVar($alias, $aliascmd, \@command, $1)/ge;
		debugMsg(4,"=De-alias: $aliascmd / expression to eval:>", \$expression, "<\n");
		{
			local $SIG{__WARN__} = sub { }; # Disable warnings for the eval below (bug7)
			if (eval $expression) {
				debugMsg(4,"=De-alias: $aliascmd / expression >", \$alias->{$aliascmd}{SEL}[$c]{CND}, "< is TRUE\n");
				$dealiascmd = $alias->{$aliascmd}{SEL}[$c]{CMD};
				last CONDITIONS;
			}
		}
	}
	unless ($dealiascmd) {
		printOut($script_io, "\n$aliasEcho$aliascmd <no conditions match>\n$prompt") unless $silent;
		return;
	}
	debugMsg(4,"=De-alias: $aliascmd / de-alias cmd: ", \$dealiascmd, "\n");

	# Check if command is just syntax output
	if ($dealiascmd =~ s/^&(\S+)\s*//) {
		my $aliasdo = $1;
		if ($aliasdo eq 'print') {
			$dealiascmd =~ s/"//g; # Remove " quotes
			$dealiascmd =~ s/\\n/\n/g; # Restore newlines
			$dealiascmd =~ s/\\t/\t/g; # Restore tabs
			printOut($script_io, "\n$dealiascmd\n$prompt") unless $silent;
			return;
		}
		elsif ($aliasdo eq 'noalias') { # Skip de-aliasing and send to host as is
			return 0;
		}
		else {
			printOut($script_io, "\n$aliasEcho$aliascmd <&$aliasdo is unrecognized>\n$prompt") unless $silent;
			stopSourcing($db);
			return;
		}
	}

	# Now de-reference any variables embedded in the de-referenced command
	$dealiascmd =~ s/\s*\K(\[[^\[\]]*?\$([\d\w\-_]+).*?\])/deRefAliasVar($alias, $aliascmd, \@command, $1, $2)/ge;	# Optional args
	$dealiascmd =~ s/\s*\K(\$([\d\w\-_]+))/deRefAliasVar($alias, $aliascmd, \@command, $1, $2)/ge;			# Mandatory args
	if ($dealiascmd =~ /££(\d+)££/) {
		printOut($script_io, "\n$aliasEcho$aliascmd <argument $1 is required>\n$prompt") unless $silent;
		stopSourcing($db);
		return;
	}
	$dealiascmd =~ s/£/\$/g; # Restore $ sign where it was not a variable
	$dealiascmd =~ s/\s*;$//;	# Ensure no trailing ;
	$dealiascmd =~ s/;\s*;/;/g;	# Ensure no empty sections between ';'
	debugMsg(4,"=De-alias: $aliascmd / replace with: ", \$dealiascmd, "\n");

	# Merge in and remember we are processing this alias, to prevent loops
	$aliasTrail->{$aliascmd} = 1 if defined $aliasTrail;
	mergeCommand($cmdParsed, $dealiascmd, "alias:$aliascmd");
	$term_io->{SourceActive}->{alias}->{$aliascmd} = 1;
	debugMsg(4,"=deAlias setting SourceActive: alias / ", \$aliascmd, "\n");

	# Show alias de-referencing on output
	if ($term_io->{AliasEcho} && !($silent || $term_io->{InputBuffQueue}->[0] eq 'RepeatCmd') ) {
		if ($term_io->{EchoOff} && $term_io->{Sourcing}) {
			$host_io->{CommandCache} .= "\n$aliasEcho" . $cmdParsed->{fullcmd};
			debugMsg(4,"=adding to CommandCache:\n>",\$host_io->{CommandCache}, "<\n");
		}
		else {
			printOut($script_io, "\n$aliasEcho" . $cmdParsed->{fullcmd});
			--$term_io->{PageLineCount};
		}
	}
	return 1;
}

1;
