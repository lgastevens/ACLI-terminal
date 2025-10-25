# ACLI sub-module
package AcliPm::ParseCommand;
our $Version = "1.14";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(parseCommand mergeCommand);
}
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::CommandStructures;
use AcliPm::DebugMessage;
use AcliPm::GlobalConstants;
use AcliPm::GlobalMatchingPatterns;
use AcliPm::MaskUnmaskChars;
use AcliPm::TabExpand;


sub opt2str { # Given a section, regenerates relevant -options into a string
	my $section = shift;
	my $appendString = '';
	if (exists $section->{opt}) {
		# Weed out the -options which are single character and have 0 value; as we can consolidate these, i.e. -bi vs. -i -b
		my @singleCharOptions = sort {$a cmp $b} grep {length($_) == 1 && $section->{opt}->{$_} == 0} keys %{$section->{opt}};
		$appendString .= ' -' . join('', @singleCharOptions) if scalar @singleCharOptions;
		# Then add the other options sequentially
		for my $opt (sort {$a cmp $b} keys %{$section->{opt}}) {
			next if length($opt) == 1 && $section->{opt}->{$opt} == 0; # Skip options already added
			$appendString .= ' -' . $opt . ($section->{opt}->{$opt} == 0 ? '' : $section->{opt}->{$opt});
		}
	}
	return $appendString;
}

sub sect2str { # Regenerate a section into a string, including options
	my $section = shift;
	my $appendString = " " . $section->{str} . opt2str($section);
	return $appendString;
}

sub grep2str { # Regenerates grepstr section, including options, into a string
	my $grepstr = shift;
	my $appendString; # Build a grepstring, including grep options
	for my $greplst (@{$grepstr->{lst}}) {
		$appendString .= sect2str($greplst);
	}
	return $appendString;
}

sub semiClnAppend { # Appends options to every command in semicln list
	my ($cmdParsed, $string) = @_;
	for my $semiclnCmd (@{$cmdParsed->{semicln}->{lst}}) {
		if ($semiclnCmd !~ /.*[^:]\/\/\s*.*?\s*$/) { # Append to everything except '//' feedarg
			$semiclnCmd .= $Space unless $semiclnCmd =~ /\s$/;
			$semiclnCmd .= $string;
		}
	}
}

sub parseCommand { # This function breaks up the entered command into its main components for subsequent parsing
	my ($command) = @_;
	debugMsg(4,"=parseCommand: Starting parse of >", \$command, "<\n");

	my $cmdParsed = { # Structure of hash returned by this function:
	#	fullcmd => 'full command after parsing',
	#	thiscmd => 'full 1st command', # Same as above, except if above is a semicolon fragmented command, in which case thiscmd is just the 1st fragment',
	#	varflag => 0,	# This flag is not set here; it is set in InputProcessing when a vraible is dereferenced but the update is not yet echoed on the terminal
	#	command	=> {
	#		str	=> 'command',
	#		var	=> [],
	#		opt	=> {},
	#		emb	=> '',	# Result of tabExpandLite
	#	},
	#	grepstr	=> {
	#		str	=> 'grep portion',	# Temp key; deleted on exit
	#		var	=> [],			# Temp key; deleted on exit
	#		opt	=> {},			# Temp key; deleted on exit
	#		lst	=> [
	#			{
	#				str	=> 'grep section',
	#				var	=> [],
	#				opt	=> {},
	#			},
	#		],
	#	},
	#	varcapt	=> {
	#		str	=> 'variable capture',
	#		var	=> [],
	#		opt	=> {},
	#	},
	#	filecap	=> {
	#		str	=> 'capture to file',
	#		var	=> [],
	#		opt	=> {},
	#	},
	#	srcfile	=> {
	#		str	=> 'source from file',
	#		var	=> [],
	#		opt	=> {},
	#	},
	#	feedarg	=> {
	#		str	=> 'feed arguments',
	#		var	=> [],
	#		opt	=> {},
	#	},
	#	forloop	=> {
	#		str	=> 'for loop arguments',
	#		var	=> [],
	#		opt	=> {},
	#	},
	#	rptloop	=> {
	#		str	=> 'repeat loop arguments',
	#		var	=> [],
	#		opt	=> {},
	#	},
	#	semicln	=> {
	#		str	=> '',			# Temp key; deleted on exit
	#		lst	=> [],
	#		opt	=> {},
	};

	$command =~ s/^\s+//;	# Remove all leading spaces
	$command =~ s/\s+$//;	# Remove all trailing spaces
	my $section = 'command';
	my $prevChar = '';
	my $space = '';
	my ($currChar, $block, $varSection, $thisCmdFlag);
	$cmdParsed->{command}->{str} = $cmdParsed->{fullcmd} = $cmdParsed->{thiscmd} = '';

	my $pushVarSection = sub { # Add the var section to the relevant section
		push(@{$cmdParsed->{$section}->{var}}, $varSection);
		debugMsg(4,"=parseCommand; Setting var section: ", \$varSection, "\n");
		undef $varSection;
	};

	my $pushGrepSection = sub { # Add the grep section to the lst key
		my $grepHash = {};
		($grepHash->{str} = $cmdParsed->{grepstr}->{str}) =~ s/\s+$//; # Trim trailing spaces at end of grep section
		delete $cmdParsed->{grepstr}->{str};
		if (exists $cmdParsed->{grepstr}->{var}) {
			$grepHash->{var} = $cmdParsed->{grepstr}->{var};
			delete $cmdParsed->{grepstr}->{var};
		}
		if (exists $cmdParsed->{grepstr}->{opt}) {
			$grepHash->{opt} = $cmdParsed->{grepstr}->{opt};
			delete $cmdParsed->{grepstr}->{opt};
		}
		push(@{$cmdParsed->{grepstr}->{lst}}, $grepHash);
		debugMsg(4,"=parseCommand: Pushed GrepStr section: >", \$grepHash->{str}, "<\n");
	};

	my $pushSemiClnSection = sub { # Add the semicln section to the lst key
		push(@{$cmdParsed->{semicln}->{lst}}, $cmdParsed->{semicln}->{str});
		debugMsg(4,"=parseCommand: Pushed SemiCln command: ", \$cmdParsed->{semicln}->{str}, "\n");
		delete $cmdParsed->{semicln}->{str};
	};

	my $appendThisFullCmd = sub { # Append string to both fullcmd/thiscmd
		my $string = shift;
		$cmdParsed->{fullcmd} .= $string;
		$cmdParsed->{thiscmd} .= $string unless $thisCmdFlag;
	};

	my $appendString = sub { # Append string to both section str and fullcmd/thiscmd; both need to be in synch in case of Var replacements
		my $string = shift;
		$cmdParsed->{$section}->{str} .= $string;
		&$appendThisFullCmd($string);
	};

	my $addToSectionStr = sub { # Sets/Appends currChar to section str
		my $extra = shift;
		if ($section eq 'semicln') { # Append
			&$appendString($space . $currChar . $extra);
		}
		else { # Reset
			$cmdParsed->{$section}->{str} = $currChar . $extra;
			&$appendThisFullCmd($space . $currChar . $extra);
		}
	};

	while ($command =~ s/^(.)//) { # Nibble away from the left
		$currChar = $1;
		debugMsg(4,"=parseCommand: currChar = >$currChar<  -  prevChar = >$prevChar< - section = >$section< - section str = >",
				# Code below uses exist to check keys; must not invoke the {str} section if it does not exist
				(exists $cmdParsed->{$section}->{str} ? \$cmdParsed->{$section}->{str} : \''), "<\n") if $::TestScript; #'
		if ($prevChar ne '\\') { # Except if backslashed
			unless ($cmdParsed->{command}->{emb} && $cmdParsed->{command}->{emb} =~ /^@(?:\$|if|elsif|while|until|for|next|last|exit)$/) {
				# Do not process these for certain embedded commands
				#
				# Process blocks enclosed in quotes or curlies or brackets
				#
				$currChar eq "'" && $command =~ s/^([^\']*[^\\])\'// && do { # Single quoted section ''
					&$pushVarSection if defined $varSection;
					$block = $1;
					unless ($section eq 'command') { # We strip the quotes only on command sections
						$block = $currChar . $block . "'";	  # This is a workaround to feeding passwords with ACLI reserved characters to the switch
					}						  # Simply enclose the password containing no spaces in single quotes
					debugMsg(4,"=parseCommand: Extracted '' block: ", \$block, "\n");
					&$appendString($space . $block);
					if ($section eq 'varcapt' && $command =~ s/^([a-z]+)$//) { # Options immediately after varcapt quoted regex
						debugMsg(4,"=parseCommand: Setting varcapt options \"\"$1\n");
						for my $optchar ( split(//, $1) ) {
							$cmdParsed->{$section}->{opt}->{$optchar} = 0;
						}
					}
					$prevChar = $space = '';
					next;
				};
				$currChar eq '"' && $command =~ s/^([^\"]*[^\\])\"// && do { # Double quoted section ""
					&$pushVarSection if defined $varSection;
					$block = $currChar . $1 . '"';
					debugMsg(4,"=parseCommand: Extracted \"\" block: ", \$block, "\n");
					&$appendString($space . $block);
					if ($section eq 'varcapt' && $command =~ s/^([a-z]+)$//) { # Options immediately after varcapt quoted regex
						debugMsg(4,"=parseCommand: Setting varcapt options \'\'$1\n");
						for my $optchar ( split(//, $1) ) {
							$cmdParsed->{$section}->{opt}->{$optchar} = 0;
						}
					}
					$prevChar = $space = '';
					$varSection = $block if $block =~ /(?:^|[^\\])[\$\{]/;
					&$pushVarSection if defined $varSection;
					next;
				};
			}
			unless ($cmdParsed->{command}->{emb} && $cmdParsed->{command}->{emb} =~ /^@(?:\$|if|elsif|while|until|next|last|exit)$/) { # @for allowed
				$currChar eq '{' && do { # Curly section {}
					&$pushVarSection if defined $varSection;
					$command =~ s/^(?:([^\}]*[^\\]))?\}//;
					$block = $currChar . (defined $1 ? $1 : '') . '}';
					debugMsg(4,"=parseCommand: Extracted {} block: ", \$block, "\n");
					&$appendString($space . $block);
					$prevChar = $space = '';
					push(@{$cmdParsed->{$section}->{var}}, $block);
					next;
				};
			}
			unless ($cmdParsed->{command}->{emb} && $cmdParsed->{command}->{emb} =~ /^@(?:\$|if|elsif|while|until|for|next|last|exit)$/) {
				$currChar eq '(' && do { # Bracket section ()
					&$pushVarSection if defined $varSection;
					$command =~ s/^([^\)]*[^\\])\)//;
					$block = $currChar . $1 . ')';
					debugMsg(4,"=parseCommand: Extracted () block: ", \$block, "\n");
					&$appendString($space . $block);
					$prevChar = $space = '';
					$varSection = $block if $block =~ /(?:^|[^\\])[\$\{]/;
					&$pushVarSection if defined $varSection;
					next;
				};
				#
				# Process boundary patters that change the command section type
				#
				$currChar eq '/' # FeedArg
						&& $section ne 'feedarg'
						&& $prevChar ne ':'
						&& $prevChar ne '/' # We need not to trigger on this XOS command: download url file:///usr/local/ext/test.xos
						&& $command =~ s/^(\/)//
						&& do {
					&$pushVarSection if defined $varSection;
					&$pushGrepSection if $section eq 'grepstr';
					unless ($section eq 'semicln') {
						debugMsg(4,"=parseCommand: Switching to FeedArg block: '//'\n");
						$section = 'feedarg';
					}
					&$addToSectionStr($1);
					$prevChar = $currChar;
					$space = '';
					next;
				};
				$currChar eq '<' && do { # SrcFile
					&$pushVarSection if defined $varSection;
					&$pushGrepSection if $section eq 'grepstr';
					unless ($section eq 'semicln') {
						debugMsg(4,"=parseCommand: Switching to SrcFile block: '<'\n");
						$section = 'srcfile';
					}
					&$addToSectionStr('');
					$prevChar = $currChar;
					$space = '';
					next;
				};
				$currChar eq '>' # VarCapt
						&& length($cmdParsed->{$section}->{str})
						&& $command =~ s/^(>?)(?= *\$(?:(?:$VarUser)(?:\[\d*\]|\{(?:$VarHashKey|\$(?:$VarAny)?|\%\d+)?\})?)?(?:[\s,\'\"]|$))//
						&& do {	# The final quotes in above regex are to match: > $v1,$v2'%1%3'
					# Should match all of: > $var / > $var,$var2
					&$pushVarSection if defined $varSection;
					&$pushGrepSection if $section eq 'grepstr';
					unless ($section eq 'semicln') {
						debugMsg(4,"=parseCommand: Switching to VarCapt block: '> \$'\n");
						$section = 'varcapt';
					}
					&$addToSectionStr($1);
					$prevChar = $currChar;
					$space = '';
					next;
				};
				$currChar eq '>' # FileCap
						&& length($cmdParsed->{$section}->{str})
						&& $command =~ s/^(>?)(?= *(?:[^\s\$]|\$[_\$\%\@\*\d]|\$(?:$VarUser)(?:\[\d*\]|\{(?:$VarHashKey|\$(?:$VarAny)?|\'\')?\})?([^\w_\d,])))//
						&& do {
					# Should match all of: > filename / > $$ / > $var.cfg
					&$pushVarSection if defined $varSection;
					&$pushGrepSection if $section eq 'grepstr';
					unless ($section eq 'semicln') {
						debugMsg(4,"=parseCommand: Switching to FileCap block: '>'\n");
						$section = 'filecap';
					}
					&$addToSectionStr($1);
					$prevChar = $currChar;
					$space = '';
					next;
				};
				length($cmdParsed->{command}->{str}) && $cmdParsed->{command}->{str} !~ /^!/ # GrepStr
						&& (
							($currChar =~ /[|!]/ && $prevChar !~ /[|!]/) ||
							($currChar eq '^' && ( # Need to allow ^ in grep regex at beginning of grep string or immediately after a ','
								(length($prevChar) && $prevChar !~ /[|!,]/) ||
								(!length($prevChar) && $cmdParsed->{$section}->{str} !~ /[|!,]\s*$/)
							))
						) && do {
					&$pushVarSection if defined $varSection;
					&$pushGrepSection if $section eq 'grepstr';
					unless ($section eq 'semicln') {
						debugMsg(4,"=parseCommand: Switching to Grep block: '|!^'\n") unless $section eq 'grepstr';
						$section = 'grepstr';
					}
					$command =~ s/^\s+//; # Remove spaces leading to next command
					&$addToSectionStr('');
					$prevChar = $currChar;
					$space = '';
					next;
				};
				$currChar =~ /&/ # ForLoop
						&& (
							($section eq 'semicln' && !exists $cmdParsed->{semicln}->{str}  ) || # cmd1; cmd2; &
							($section ne 'semicln' && length($cmdParsed->{$section}->{str}) )    # cmd &
						) && do {
					&$pushVarSection if defined $varSection;
					&$pushGrepSection if $section eq 'grepstr';
					undef $thisCmdFlag if $section eq 'semicln';
					debugMsg(4,"=parseCommand: Switching to ForLoop block: '&'\n");
					$section = 'forloop';
					# Reset command str and thiscmd
					$cmdParsed->{command}->{str} = $cmdParsed->{thiscmd} = $cmdParsed->{fullcmd};
					$cmdParsed->{command}->{str} =~ s/; *$//;
					$cmdParsed->{thiscmd} =~ s/ +$/ /;
					debugMsg(4,"=parseCommand: ForLoop block resetting command str from fullcmd to: ", \$cmdParsed->{command}->{str}, "\n");
					# Delete all sections, which might have been spun 1 so far (or for the 1st semicln fragment if we were in section semicln)
					for my $delSection ('semicln', 'grepstr', 'varcapt', 'filecap', 'srcfile', 'feedarg', 'forloop', 'rptloop') { # Sections to delete
						delete $cmdParsed->{$delSection};
					}
					&$addToSectionStr('');
					$prevChar = $currChar;
					$space = '';
					next;
				};
				$currChar =~ /@/ && $command =~ /^\d*$/ # RptLoop
						&& (
							($section eq 'semicln' && !exists $cmdParsed->{semicln}->{str}  ) || # cmd1; cmd2; @
							($section ne 'semicln' && length($cmdParsed->{$section}->{str}) )    # cmd @
						) && do {
					&$pushVarSection if defined $varSection;
					&$pushGrepSection if $section eq 'grepstr';
					undef $thisCmdFlag if $section eq 'semicln';
					debugMsg(4,"=parseCommand: Switching to RptLoop block: '\@'\n");
					$section = 'rptloop';
					# Reset command str and thiscmd
					$cmdParsed->{command}->{str} = $cmdParsed->{thiscmd} = $cmdParsed->{fullcmd};
					$cmdParsed->{command}->{str} =~ s/; *$//;
					$cmdParsed->{thiscmd} =~ s/ +$/ /;
					debugMsg(4,"=parseCommand: RptLoop block resetting command str from fullcmd to: ", \$cmdParsed->{command}->{str}, "\n");
					# Delete all sections, which might have been spun 1 so far (or for the 1st semicln fragment if we were in section semicln)
					for my $delSection ('semicln', 'grepstr', 'varcapt', 'filecap', 'srcfile', 'feedarg', 'forloop', 'rptloop') { # Sections to delete
						delete $cmdParsed->{$delSection};
					}
					&$addToSectionStr('');
					$prevChar = $currChar;
					$space = '';
					next;
				};
			}
			$currChar =~ /;/ # Semicolon fragment
					&& length($cmdParsed->{$section}->{str})
					&& do {
				&$pushVarSection if defined $varSection;
				&$pushGrepSection if $section eq 'grepstr';
				&$pushSemiClnSection if $section eq 'semicln';
				debugMsg(4,"=parseCommand: Switching to SemiCln for rest of command\n") unless $section eq 'semicln';
				$section = 'semicln';
				$thisCmdFlag = 1;
				$cmdParsed->{fullcmd} .= "$space$currChar";
				$cmdParsed->{fullcmd} .= $1 if $command =~ s/^(\s+)//; # Remove spaces leading to next command; preserve on fullcmd
				$prevChar = $space = '';
				next;
			};
			#
			# Process -options
			#
			if (!length($prevChar) && !($section eq 'semicln' && length($cmdParsed->{semicln}->{str})) && $currChar eq '-' && $command =~ /^$AcliMinusOptions\s*(?:[;<>|!\^&\@-]|\/\/|$)/) {
				# We expect a space (no prevChar before processing any options)
				# For semicln we only come in here if a -option is found to immediately follow a ';'; hence the use of semiClnAppend to append to all semicln list
				my ($opt, $val);
				$command =~ s/^(peer(?:c(?:pu?)?)?)// && do {
					my $opt = $1;
					debugMsg(4,"=parseCommand: Setting option -peercpu\n");
					semiClnAppend($cmdParsed, "-peercpu") if $section eq 'semicln';
					$cmdParsed->{$section eq 'semicln' ? 'command' : $section}->{opt}->{peercpu} = 0;
					&$appendThisFullCmd("$space-$opt");
					$prevChar = $space = '';
					next;
				};
				$command =~ s/^(both(?:c(?:p(?:us?)?)?)?)// && do {
					my $opt = $1;
					debugMsg(4,"=parseCommand: Setting option -bothcpus\n");
					semiClnAppend($cmdParsed, "-bothcpus") if $section eq 'semicln';
					$cmdParsed->{$section eq 'semicln' ? 'command' : $section}->{opt}->{bothcpus} = 0;
					&$appendThisFullCmd("$space-$opt");
					$prevChar = $space = '';
					next;
				};
				$command =~ s/^([a-z])(\d+)// && do {
					my ($opt, $val) = ($1, $2);
					debugMsg(4,"=parseCommand: Setting option -$opt$val\n");
					semiClnAppend($cmdParsed, "-$opt$val") if $section eq 'semicln';
					$cmdParsed->{$section eq 'semicln' ? 'command' : $section}->{opt}->{$opt} = $val;
					&$appendThisFullCmd("$space-$opt$val");
					$prevChar = $space = '';
					next;
				};
				$command =~ s/^([a-z]+)// && do {
					my $options = $1;
					debugMsg(4,"=parseCommand: Setting options -$options\n");
					semiClnAppend($cmdParsed, "-$options") if $section eq 'semicln';
					for my $opt ( split(//, $options) ) {
						$cmdParsed->{$section eq 'semicln' ? 'command' : $section}->{opt}->{$opt} = 0;
					}
					&$appendThisFullCmd("$space-$options");
					$prevChar = $space = '';
					next;
				};
			}
			#
			# Process $variables
			#
			unless ($section eq 'command' && (
					$cmdParsed->{command}->{str} eq '@' ||	# @$ embedded command
					$cmdParsed->{command}->{emb} && (
						$cmdParsed->{command}->{emb} =~ /^@(?:\$|if|elsif|while|until|next|last|exit)$/
						|| ($cmdParsed->{command}->{emb} eq '@vars' && ( 
							($cmdParsed->{command}->{str} =~ /^\@v\S* p/ && $cmdParsed->{command}->{str} !~ /\$/) ||  # @vars prompt .. $var; must skip $var
							($cmdParsed->{command}->{str} =~ /^\@v\S* [rs]/) # @vars raw|show
						    ))
						|| ($cmdParsed->{command}->{emb} eq '@for' && $cmdParsed->{command}->{str} !~ /&/) # @for, but only after seeing "&" character
					)
				)) {
				# Do not process $vars for certain embedded commands
				$currChar eq '$' && do {
					my $variable = $currChar;
					my $varIndex;
					if ($command =~ s/^([#\']?(?:$VarSlotAll))$VarDelim//) { # Extract reserved variables $1/ALL, $2:ALL, etc..
						$variable .= $1;
					}
					elsif ($command =~ s/^([#\']?(?:$VarAny)(?|\[\d*\]|\[(\$(?:$VarAny)?)\]|\{(?:$VarHashKey|\'\'|\%\d+)?\}|\{(\$(?:$VarAny)?)\})?)$VarDelim//) { # Extract full variable
						$variable .= $1;
						$varIndex = $2; # Must not include '{}' or '[]'
					}
					debugMsg(4,"=parseCommand: Extracted \$ variable : ", \$variable, "\n");
					if ($section eq 'command' && $cmdParsed->{$section}->{str} =~ /^(?:\@my)?$/ && $command =~ /^\s*(?:\.?=|$)/ && $varIndex) { # Case: $var{$key}/[$idx] = <value>
						$varSection = $varIndex;
						&$pushVarSection;
					}
					unless ( ( $section eq 'command' && (								# Not if any of these:
							$cmdParsed->{command}->{str} =~ /^\@my$/ ||					# @my $var / @my $var = value
							(!length ($cmdParsed->{command}->{str}) && $command =~ /^\s*(?:\.?=|$)/)	# $var     / $var = value
						   ))
						|| $section eq 'varcapt' ) { # No varSection in varcapt; only if in quoted regex
							# If we get here we start capturing a varSection, but we must be in synch with spaces as in command->str
							$varSection .= (length $varSection ? $space : '') . $variable;
							debugMsg(4,"=parseCommand: Start recording var section\n");
					}
					&$appendString($space . $variable);
					$prevChar = $space = '';
					next;
				};
				$currChar eq '%' && $command =~ /^$VarDelim/ && do { # Special case of $% variable in shorthand format %
					my $variable = $currChar;
					debugMsg(4,"=parseCommand: Extracted \% variable\n");
					$varSection .= $variable;
					debugMsg(4,"=parseCommand: Start recording var section\n");
					&$appendString($space . $variable);
					$prevChar = $space = '';
					next;
				};
			}
		}
		#
		# Process characters and append to current section type
		#
		if ($currChar =~ /^\h$/) { # Record spaces
			if ($section eq 'command' && !exists $cmdParsed->{command}->{emb}) { # Record embedded command
				$cmdParsed->{command}->{emb} = tabExpandLite($EmbeddedCmds, $cmdParsed->{command}->{str}, 1);
				debugMsg(4,"=parseCommand: Setting command block 'emb' key = ", \$cmdParsed->{command}->{emb}, "\n") if $cmdParsed->{command}->{emb};
			}
			if ($section eq 'grepstr') { # In grepstr section we preserve spaces
				$space .= $Space;
			}
			else { # Anywhere alse we suppress to just 1 space
				$space = $Space;
			}
			$prevChar = '';
			next;
		}
		# Suppression of backslash on command
		unless ($cmdParsed->{command}->{emb} && $cmdParsed->{command}->{emb} =~ /^@(?:\$|if|elsif|while|until|for|next|last|exit)$/) {
			if ($section =~ /^(?:command|feedarg)$/ && $prevChar eq '\\' && $currChar =~ /[\'\"\{\}\(\)\/<>|!^&\@;\$\-]/) {
				chop $cmdParsed->{$section}->{str};
			}
		}
		# Only add single space once next char is added
		&$appendString($space . $currChar);
		($varSection .= $space . $currChar) if defined $varSection;
		$prevChar = $currChar;
		$space = '';
	}
	&$pushVarSection if defined $varSection;
	unless (exists $cmdParsed->{command}->{emb}) { # Record embedded command if this did not happen in parsing loop
		$cmdParsed->{command}->{emb} = tabExpandLite($EmbeddedCmds, $cmdParsed->{command}->{str}, 1);
		debugMsg(4,"=parseCommand: Loop end - setting command block 'emb' key = ", \$cmdParsed->{command}->{emb}, "\n") if $cmdParsed->{command}->{emb};
	}
	if (exists $cmdParsed->{grepstr} && exists $cmdParsed->{grepstr}->{str}) { # A last semicolon fragmented command was being assembled
		&$pushGrepSection;
	}
	if (exists $cmdParsed->{semicln}->{str}) { # A last semicolon fragmented command was being assembled
		&$pushSemiClnSection;
	}
	elsif (!defined $cmdParsed->{semicln}->{lst}) { # No list of semicolon fragmented commands exists 
		debugMsg(4,"=parseCommand: Loop end - Deleting SemiCln key\n");
		delete $cmdParsed->{semicln};
	}
	debugMsg(4, "=parseCommand ", \Data::Dumper::Dumper($cmdParsed)) if $::Debug && !$::TestScript;
	return $cmdParsed;
}


sub mergeCommand { # Updates the parsed command hash with a new command update
	my ($cmdParsed, $updatedCmd, $semiClnMarker) = @_;
	$updatedCmd = $cmdParsed->{command}->{str} unless defined $updatedCmd; # Re-parse (case where: cmd1; cmd2; @|&)
	if ($semiClnMarker) { # If we have a marker, we add it here, will endup in semicln list
		$updatedCmd .= ";\x00".$semiClnMarker;
	}
	debugMsg(4,"=mergeCommand: Starting parse of >", \$updatedCmd, "<\n");

	# > (cmdParsed                     ) -o1 |pat1 > $var1
	
	#	A: cmdParsed = updateParsed -o2 |pat2 > $var2
	# > (updateParsed -o2 |pat2 > $var2) -o1 |pat1 > $var1
	# >  updateParsed -o1 -o2 |pat2 |pat1 > $var1
	
	#	B: cmdParsed = updateParsed -o2 |pat2 > $var2; updateParsed2 -o3 |pat3 > $var3
	# > (updateParsed -o2 |pat2 > $var2; updateParsed2 -o3 |pat3 > $var3) -o1 |pat1 > $var1
	# >  updateParsed -o1 -o2 |pat2 |pat1 > $var1; updateParsed2 -o1 -o3 |pat3 |pat1 >> $var1

	#	C: cmdParsed = updateParsed:; updateParsed2; updateParsed3:
	# > (updateParsed:; updateParsed2; updateParsed3:) -o1 |pat1 > $var1
	# >  updateParsed -o1 |pat1 > $var1; updateParsed2; updateParsed3 -o1 |pat1 >> $var1
	#
	#
	
	# Sections which concatenate              : opt, grepstr
	# Sections which overwrite (cmdParse wins): varcapt, filecap, srcfile, feedarg, forloop
	# Sections where '>' needs to become '>>' : varcapt, filecap
	# Sections which are NOT merged           : rptloop
	
	# - reset  $updateParsed->{thiscmd} to $updateParsed->{command}->{str}
	# - apply cmdParsed -options (these win)
	# - apply updateParsed -options (except if overridden by cmdParsed)
	# - apply updateParsed grepstr
	# - apply cmdParsed grepstr
	# - apply varcapt order: cmdParse('>' to '>>' applies), updateParsed(except if semicln list)
	# - apply filecap order: cmdParse('>' to '>>' applies), updateParsed(except if semicln list)
	# - apply srcfile order: cmdParse, updateParsed(except if semicln list)
	# - apply feedarg order: cmdParse, updateParsed(except if semicln list)
	# - apply forloop order: cmdParse, updateParsed(except if semicln list)

	my @updatedParsed;
	my @updatedCmdList = ('');
	if (length $updatedCmd) {
		$updatedCmd = quoteCurlyMask($updatedCmd, ';');	# Mask semi-colons inside quotes/brackets/etc..
		@updatedCmdList = map(quoteCurlyUnmask($_, ';'), split(/[^\\]\K;\s*/, $updatedCmd)); # Split the command into sections, if semicolon fragmented
	}
	my $colonMarkersExist = scalar @updatedCmdList && scalar grep {/:$/} @updatedCmdList;
	debugMsg(4,"=mergeCommand: colonMarkersExist\n") if $colonMarkersExist;
	my %turnIntoAppend;
	foreach my $cmd (@updatedCmdList) {
		if ($cmd =~ /^\x00/) { # Marker exception
			debugMsg(4,"=mergeCommand; processing marker : ", \$cmd, "\n");
			push(@updatedParsed, {thiscmd => $cmd});
			next;
		}
		debugMsg(4,"=mergeCommand; processing updated cmd : ", \$cmd, "\n");
		my $colonMarked = $cmd =~ s/:$//;
		my $applyFlag = $colonMarkersExist ? $colonMarked : 1;
		debugMsg(4,"=mergeCommand: applyFlag set for this cmd\n") if $applyFlag;
		my $newParsed = parseCommand($cmd);
		$newParsed->{thiscmd} = $newParsed->{command}->{str}; # We rebuild it below as we go
		debugMsg(4,"=mergeCommand; newParsed thiscmd: ", \$newParsed->{thiscmd}, "\n");

		# Apply cmdParsed command -options (these win) to struct
		if ($applyFlag && exists $cmdParsed->{command}->{opt}) {
			for my $opt (keys %{$cmdParsed->{command}->{opt}}) {
				$newParsed->{command}->{opt}->{$opt} = $cmdParsed->{command}->{opt}->{$opt};
				debugMsg(4,"=mergeCommand; newParsed command adding opt -", \$opt, "\n");
			}
		}
		# Append all the options to thiscmd
		$newParsed->{thiscmd} .= opt2str($newParsed->{command});
		debugMsg(4,"=mergeCommand; newParsed thiscmd after -options: ", \$newParsed->{thiscmd}, "\n");

		# Append newParsed grepstr to thiscmd (remains innermost)
		if (exists $newParsed->{grepstr}) {
			$newParsed->{thiscmd} .= grep2str($newParsed->{grepstr});
			debugMsg(4,"=mergeCommand; newParsed thiscmd after new grepstr: ", \$newParsed->{thiscmd}, "\n");
		}

		# Apply cmdParsed grepstr
		if ($applyFlag && exists $cmdParsed->{grepstr}) {
			for my $greplst (@{$cmdParsed->{grepstr}->{lst}}) {
				push(@{$newParsed->{grepstr}->{lst}}, $greplst); # Append to the newParsed
				debugMsg(4,"=mergeCommand; newParsed grepstr adding: ", \$greplst->{str}, "\n");
			}
			$newParsed->{thiscmd} .= grep2str($newParsed->{grepstr});
			debugMsg(4,"=mergeCommand; newParsed thiscmd after orig grepstr: ", \$newParsed->{thiscmd}, "\n");
		}

		# Apply all the other sections
		for my $section ('varcapt', 'filecap') { # Apply order: cmdParse, newParsed
			if ($applyFlag && exists $cmdParsed->{$section}) {
				$turnIntoAppend{$section} = defined $turnIntoAppend{$section} ? 1 : 0; # Only set on 2nd and subsequent cycles
				for my $key (keys %{$cmdParsed->{$section}}) { # Need to make a deep-er copy, as we might modify the section->str below
					$newParsed->{$section}->{$key} = $cmdParsed->{$section}->{$key};
				}
				if ($newParsed->{$section}->{str} !~ /^>>/ && $turnIntoAppend{$section}) {
					$newParsed->{$section}->{str} = '>' . $newParsed->{$section}->{str};
				}
				debugMsg(4,"=mergeCommand; newParsed $section adding: ", \$newParsed->{$section}->{str}, "\n");
			}
			if (exists $newParsed->{$section}) {
				$newParsed->{thiscmd} .= sect2str($newParsed->{$section});
				debugMsg(4,"=mergeCommand; newParsed thiscmd after $section: ", \$newParsed->{thiscmd}, "\n");
			}
		}
		for my $section ('srcfile', 'feedarg', 'forloop') { # Apply order: cmdParse, newParsed
			if ($applyFlag && exists $cmdParsed->{$section}) {
				$newParsed->{$section} = $cmdParsed->{$section};
				debugMsg(4,"=mergeCommand; newParsed $section adding: ", \$newParsed->{$section}->{str}, "\n");
			}
			if (exists $newParsed->{$section}) {
				$newParsed->{thiscmd} .= sect2str($newParsed->{$section});
				debugMsg(4,"=mergeCommand; newParsed thiscmd after $section: ", \$newParsed->{thiscmd}, "\n");
			}
		}

		# Push and keep each newParsed
		push(@updatedParsed, $newParsed);
	}

	# Now cmdParsed becomes the very 1st newParsed
	my $newCmdParsed = shift @updatedParsed;

	# Init fullcmd to thiscmd; we will add to it semicln list below if necessary
	$newCmdParsed->{fullcmd} = $newCmdParsed->{thiscmd};

	# After shifting 1st newParsed, if any remain they need to be made semicln list
	if (@updatedParsed) {
		for my $newParsed (@updatedParsed) {
			push(@{$newCmdParsed->{semicln}->{lst}}, $newParsed->{thiscmd});
			debugMsg(4,"=mergeCommand; pushing to semicln list: ", \$newParsed->{thiscmd}, "\n");
			$newCmdParsed->{fullcmd} .= "; " . $newParsed->{thiscmd} unless $newParsed->{thiscmd} =~ /^\x00/;
			debugMsg(4,"=mergeCommand; newParsed fullcmd: ", \$newParsed->{thiscmd}, "\n");
		}
	}

	# Now copy all keys across
	for my $key (keys %{$newCmdParsed}) {
		$cmdParsed->{$key} = $newCmdParsed->{$key};
	}
	# And remove any keys which need not be there
	for my $key (keys %{$cmdParsed}) {
		delete $cmdParsed->{$key} unless exists $newCmdParsed->{$key};
	}
	debugMsg(4, "=mergeCommand ", \Data::Dumper::Dumper($cmdParsed)) if $::Debug && !$::TestScript;
}

1;
