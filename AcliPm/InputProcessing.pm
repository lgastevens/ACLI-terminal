# ACLI sub-module
package AcliPm::InputProcessing;
our $Version = "1.11";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(bangHistory semicolonFragment processRepeatOptions prepGrepStructure processLocalOptions);
}
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::DebugMessage;
use AcliPm::GeneratePortListRange;
use AcliPm::GlobalConstants;
use AcliPm::GlobalDefaults;
use AcliPm::GlobalMatchingPatterns;
use AcliPm::MaskUnmaskChars;
use AcliPm::ParseCommand;
use AcliPm::Print;
use AcliPm::Prompt;
use AcliPm::QuotesRemove;
use AcliPm::Socket;
use AcliPm::Sourcing;
use AcliPm::Variables;


sub macRegex { # Create regex for MACs in format xx-xx-xx-xx-xx-xx | xx:xx:xx:xx:xx:xx | xxxxxxxxxxxx
	my $mac = shift;
	$mac =~ s/([a-f\d]{2})[:\-]/${1}\x00/ig;
	$mac =~ s/\x00/[:\\-]\?/g;
	return "(?^i:$mac)";
}


sub ipv6Regex { # Create regex for IPv6 addresses
	my $ipv6 = shift;
	$ipv6 =~ s/^::\\\/0$/0:0:0:0:0:0:0:0\\\/0/;
	$ipv6 =~ s/^::$/0:0:0:0:0:0:0:0/;
	$ipv6 =~ s/::/(?::0)+:?/g;
	return $ipv6;
}


sub resetGrepStructure { # Re-initialize all the grep state keys
	my ($grep, $onlyStateKeys) = @_;

	unless ($onlyStateKeys) {
		# Clear out the grep strings
		$grep->{String}			= 0;
		$grep->{Advanced}		= [];
		$grep->{KeepBanner}		= 1;
		$grep->{BannerDetected}		= [];
		$grep->{Indent}			= '';
		$grep->{Mode}			= [];
		$grep->{Instance}		= [];
		$grep->{RangeList}		= [];
		$grep->{Regex}			= [];
	}
	# Clear out the grep state keys
	$grep->{MultiLine}		= [];
	$grep->{KeepInstanceCfg}	= [];
	$grep->{DelInstanceCfg}		= [];
	$grep->{InsertIndent}		= 0;
	$grep->{EnableSeen}		= undef;
	$grep->{ConfigSeen}		= undef;
	$grep->{ConfigTermSeen}		= undef;
	$grep->{EndSeen}		= undef;
	$grep->{ConfigACLI}		= 0;
	$grep->{CfgContextLvl}		= 0;
	$grep->{CfgContextTyp}		= [];
	$grep->{BufferThreshold}	= 1;
	$grep->{KeepIndented}		= [];
	$grep->{DelIndented}		= [];
	$grep->{IndentAdd}		= undef;
	$grep->{IndentLevel}		= [];
	$grep->{IndentParents}		= [];
	$grep->{IndentNestMatch}	= [];
	$grep->{IndentExit}		= [];
	$grep->{IndentExitLevel}	= [];
	$grep->{ShowCommand}		= [];
	$grep->{CompleteOutput}		= undef;
	$grep->{EmptyLineSupres}	= [];
	$grep->{NoEmptyLineLast}	= [];
	$grep->{GrepStreamFile}		= undef;
}


sub bangHistory { # Recalls commands from history using '!'
	my ($db, $cmdParsed) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $history = $db->[9];

	# Come out immediately if not a bang command
	return 1 if $cmdParsed->{command}->{str} !~ /^\s*!(?:!|\d+)/;

	# Prepare the prompt and alias echo header
	my $prompt = appendPrompt($host_io, $term_io);
	my $historyEcho = echoPrompt($term_io, $prompt, 'history');

	# Check we have entries in history array
	unless (@{$history->{HostRecall}}) {
		printOut($script_io, "\n$historyEcho<no avilable history>\n$prompt");
		return;
	}

	# Get the command from history
	my $historyCmd;
	if ($cmdParsed->{command}->{str} =~ /^\s*!!\s*/ || $cmdParsed->{command}->{str} =~ /^\s*!0\s*/) { # Bang bang or !0
		$historyCmd = $history->{HostRecall}[$#{$history->{HostRecall}}];
	}
	elsif ($cmdParsed->{command}->{str} =~ /^\s*!(\d+)\s*/) { # Bang number
		if ($1 <= $#{$history->{HostRecall}}) {
			$historyCmd = $history->{HostRecall}[$1-1];
		}
		else {
			printOut($script_io, "\n$historyEcho<no !$1 command in history>\n$prompt");
			return;
		}
	}
	else {
		return 1;
	}
	debugMsg(4,"=History-cmd:>$historyCmd<\n");
	mergeCommand($cmdParsed, $historyCmd);

	# Show history replacement on output
	if ($term_io->{HistoryEcho}) {
		printOut($script_io, "\n$historyEcho$historyCmd");
		--$term_io->{PageLineCount};
	}
	return 1;
}


sub semicolonFragment { # Process lines if they have ; in them but only for certain devices
	my ($db, $cmdParsed, $dictFlushed) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $poppedConfigContext;

	if (exists $cmdParsed->{semicln}) {
		my @fragments = @{$cmdParsed->{semicln}->{lst}};
		if ($host_io->{Prompt} =~ /[\/\(]conf(?:ig|-)/) { # If switch already in config mode, alter 1st and last fragments to stay in config mode
			if ($cmdParsed->{command}->{str} =~ /^con(?:f(?:i(?:g(?:u(?:re?)?)?)?)?)? +t/) {
				my $endMarker = pop @fragments if $fragments[$#fragments] =~ /\x00/;
				$cmdParsed->{command}->{str} = shift @fragments;
				if ($cmdParsed->{command}->{str} =~ /^int/) {
					if ($fragments[$#fragments] =~ /^end?/) {
						$fragments[$#fragments] = 'exit';
					}
					elsif ($fragments[$#fragments] =~ /^exit?/) {
						pop @fragments;
					}
				}
				elsif (@fragments && ($fragments[$#fragments] =~ /^end?/ || $fragments[$#fragments] =~ /^exit?/)) {
					pop @fragments;
				}
				push(@fragments, $endMarker) if $endMarker;
				mergeCommand($cmdParsed); # Reparse
				$poppedConfigContext = 1;
			}
		}
		my $prompt = appendPrompt($host_io, $term_io);
		my $command = $cmdParsed->{thiscmd};
		unless (scalar @fragments == 1 && $fragments[0] =~ /\x00/ && !$poppedConfigContext) { # Don't echo if it was a single alias/dictionary command
			if ($term_io->{EchoOff} && $term_io->{Sourcing} && !$dictFlushed) {
				$host_io->{CommandCache} .= "\n";
			}
			else {
				printOut($script_io, "\n");
			}
		}
		appendInputBuffer($db, 'semiclnfrg', \@fragments, 1) if @fragments; # if it was 3 frags, and we shifted & popped all 3 above, then we have none left
		unless (scalar @fragments == 1 && $fragments[0] =~ /\x00/ && !$poppedConfigContext) { # Don't echo if it was a single alias/dictionary command
			if ($term_io->{EchoOff} && $term_io->{Sourcing}) {
				$host_io->{CommandCache} .= "$prompt$command";
				debugMsg(4,"=adding to CommandCache - semicolonFragment:\n>",\$host_io->{CommandCache}, "<\n");
			}
			else {
				printOut($script_io, "$prompt$command");
			}
		}
		$term_io->{SourceNoHist} = 1;		# Disable history
		$term_io->{SourceNoAlias} = 0;		# Disable alias
		delete $cmdParsed->{semicln};
	}
	return 1;
}


sub processRepeatOptions { # Process repeat command @<secs> or for loop command &<range>
	my ($db, $cmdParsed) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];

	# Do not process repeat options for any of these embedded commands
	return 1 if $cmdParsed->{command}->{emb} =~ /^\@(?:\$|if|elsif|while|until|for|next|last|exit)$/;

	my $prompt = appendPrompt($host_io, $term_io);
	my $repeatArgs;

	#
	# Repeat command processing "@"
	#
	if (exists $cmdParsed->{rptloop}) {
		debugMsg(4,"=Processing cmdParsed section 'rptloop': ", \$cmdParsed->{rptloop}->{str}, "\n");
		derefVariables($db, $cmdParsed, $cmdParsed->{'rptloop'});
		echoVarReplacement($db, $cmdParsed); # Display variable replacements
		if ($cmdParsed->{rptloop}->{str} =~ /^\@(\d+)?$/) {
			if ($term_io->{Sourcing} && defined $term_io->{RepeatCmd}) {
				printOut($script_io, "\n$ScriptName: Nested use of '\@' repeat is not supported\n\n$prompt");
				stopSourcing($db);
				return;
			}
			$term_io->{RepeatDelay} = $1 || 0;
			debugMsg(1,"=RepeatCommand delay = ", \$term_io->{RepeatDelay}, "\n");
			$term_io->{RepeatCmd} = $cmdParsed->{command}->{str};
			debugMsg(1,"=RepeatCommand command = ", \$term_io->{RepeatCmd}, "\n");
			$term_io->{RepeatUpTime} = time + $term_io->{RepeatDelay};
			$term_io->{SourceNoHist} = 1;	# Disable history
			appendInputBuffer($db, 'RepeatCmd', undef, undef, undef, 1);
			delete $cmdParsed->{rptloop}; # Delete before merge
			mergeCommand($cmdParsed); # Re-parse (case: cmd1; cmd2; @)
		}
		else { # Delete anyway
			delete $cmdParsed->{rptloop};
		}
	}

	#
	# Repeat command with variable interpolation "&"
	#
	if (exists $cmdParsed->{forloop}) {
		debugMsg(4,"=Processing cmdParsed section 'forloop': ", \$cmdParsed->{forloop}->{str}, "\n");
		derefVariables($db, $cmdParsed, $cmdParsed->{'forloop'});
		echoVarReplacement($db, $cmdParsed); # Display variable replacements
		if ($cmdParsed->{forloop}->{str} =~ /^&(\')?\s*([^&;]+)$/) { # Syntax &repeat
			if ($term_io->{Sourcing} && defined $term_io->{ForLoopCmd}) {
				printOut($script_io, "\n$ScriptName: Nested use of '&' repeat is not supported; use \@for loops instead\n\n$prompt");
				stopSourcing($db);
				return;
			}
			my $iterations;
			my $raw = $1;
			@{$term_io->{ForLoopVar}} = ();
			@{$term_io->{ForLoopVarStep}} = ();
			@{$term_io->{ForLoopVarList}} = ();
			@{$term_io->{ForLoopVarType}} = ();
			foreach my $range (split($Space, $2)) {
				my ($type, $cycles, $start, $end, $step, @list);
				if ($range =~ /^(\d+)\.\.(\d+)(?::(\d+))?$/) { # 0..10[:2] syntax
					$type = 0;
					($start, $end, $step) = ($1, $2, $3||1);
					if ($start == $end) {
						printOut($script_io, "\n$ScriptName: null range -> $range\n\n$prompt");
						stopSourcing($db);
						return;
					}
					$cycles = abs($end - $start) / $step;
					debugMsg(1,"=ForLoopCommand cycles =  $cycles\n");
					unless ($cycles == int $cycles) {
						printOut($script_io, "\n$ScriptName: end of range cannot be met with step provided -> $range\n\n$prompt");
						stopSourcing($db);
						return;
					}
					$step *= -1 if $start > $end; # Make step negative
					debugMsg(1,"=ForLoopCommand range: $start -> $end step $step\n");
				}
				else { # List syntax
					$type = 1;
					if ($raw) { # We only call generatePortList if in raw mode
						my $rawlist = generatePortList($host_io, $range); # we could have port ranges in there..
						$range = $rawlist if length $rawlist;
					}
					foreach my $element ( split(',', $range) ) {
						push(@list, $element);
					}
					$cycles = scalar @list - 1;
					debugMsg(1,"=ForLoopCommand List of values = cycles =  $cycles\n");
				}
				if (!defined $iterations) {
					$iterations = $cycles;
				}
				elsif ($cycles != $iterations) {
					printOut($script_io, "\n$ScriptName: multiple ranges must have same number of iterations\n\n$prompt");
					stopSourcing($db);
					return;
				}
				push(@{$term_io->{ForLoopVarType}}, $type);
				push(@{$term_io->{ForLoopVar}}, $start) if defined $start;
				push(@{$term_io->{ForLoopVarStep}}, $step) if defined $step;
				push(@{$term_io->{ForLoopVarList}}, \@list) if @list;
			}
			$term_io->{ForLoopCmd} = $cmdParsed->{command}->{str};
			debugMsg(1,"=ForLoopCommand command = ", \$term_io->{ForLoopCmd}, "\n");
			$term_io->{ForLoopCycles} = $iterations;
			debugMsg(1,"=ForLoopCommand iterations = $iterations\n");
			$term_io->{ForLoopVarN} = $#{$term_io->{ForLoopVarType}} ? 0 : $term_io->{ForLoopCmd} =~ tr/%/%/; # Store number of % in loop cmd
			debugMsg(4,"=ForLoopCommandVarN = ", \$term_io->{ForLoopVarN}, "\n");
	
			my @list;
			my ($i, $l) = (0, 0); # Indexes to traverse ranges ($i) and lists ($l)
			foreach my $type (@{$term_io->{ForLoopVarType}}) { # traverse vars types
				if ($type) { # List type
					push(@list, shift @{$term_io->{ForLoopVarList}[$l++]});
				}
				else { # Range type
					push(@list, $term_io->{ForLoopVar}[$i++]);
				}
			}
			# Obtain command for this iteration
			if ($term_io->{ForLoopVarN}) { # Multiply ranges
				push(@list, $list[0]) for (2 .. $term_io->{ForLoopVarN});
			}
			eval {
				local $SIG{__WARN__} = sub { die shift }; # Turn every warning into an exception
				$cmdParsed->{command}->{str} = sprintf($term_io->{ForLoopCmd}, @list);
			};
			if ($@) {
				(my $message = $@) =~s/;.*$//;
				$message =~ s/ at .+ line .+$//; # Delete file & line number info
				printOut($script_io, "\n$ScriptName: $message\n$prompt");
				$term_io->{ForLoopCmd} = undef;
				stopSourcing($db);
				return;
			}
			appendInputBuffer($db, 'ForLoopCmd', undef, undef, undef, 1) if $term_io->{ForLoopCycles} > 0;
			if ($term_io->{EchoOff}) {
				$host_io->{CommandCache} .= "\n$prompt$cmdParsed->{command}->{str}";
				debugMsg(4,"=adding to CommandCache - processRepeatOptions:\n>",\$host_io->{CommandCache}, "<\n");
			}
			else {
				printOut($script_io, "\n$prompt$cmdParsed->{command}->{str}");
			}
			$term_io->{SourceNoHist} = 1;	# Disable history
			$term_io->{YnPrompt} = 'y';
			delete $cmdParsed->{forloop}; # Delete before merge
			mergeCommand($cmdParsed); # Re-parse (case: cmd1; cmd2; &)
		}
		else { # Delete anyway
			delete $cmdParsed->{forloop};
		}
	}
	return 1;
}


sub prepGrepStructure { # Process grep string and setup grep structure accordingly
	my ($db, $cmdParsed, $grepStream, $grepStreamFile) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $grep = $db->[10];

	my $prompt = appendPrompt($host_io, $term_io);
	my ($grepMode, $grepString, $grepRegex, $grepOptions, $grepIndent, $grepAdv, $grepQuotes, $grepHighLight, $portList, $portHash);
	resetGrepStructure($grep);
	$grep->{CompleteOutput}	= $grepStream;
	$grep->{GrepStreamFile} = $grepStreamFile;

	# See if we have any options (without grep string)
	if (exists $cmdParsed->{command}->{opt}->{b} || exists $cmdParsed->{command}->{opt}->{i}) {
		$grep->{KeepBanner} = 0 if defined $cmdParsed->{command}->{opt}->{b};
		# option -i- indent ACLI config
		if ($cmdParsed->{command}->{opt}->{i} && !$grep->{Indent}) { # -i > 0
			$grepIndent = $cmdParsed->{command}->{opt}->{i};
		}
		elsif (defined $cmdParsed->{command}->{opt}->{i} && !$grep->{Indent}) {
			$grepIndent = $term_io->{GrepIndent};
		}
		else {
			$grepIndent = 0;
		}
		if ($grepIndent) {
			$grep->{Indent} .= $Space while $grepIndent--;
		}
		push(@{$grep->{Advanced}}, 1);
		push(@{$grep->{Mode}}, '||');
		debugMsg(1,"-> PseudoGrep-Mode : >||\n");
		push(@{$grep->{Instance}}, undef);
		push(@{$grep->{RangeList}}, undef);
		debugMsg(1,"-> PseudoGrep-Instance : undefined\n");
		$grepString = '.*'; # String which will match anything
		$grepRegex = qr/$grepString/;
		push(@{$grep->{Regex}}, $grepRegex);
		debugMsg(1,"-> PseudoGrep-Regex : >", \$grepRegex, "<\n");
		$grep->{String} = 1;
	}

	return 1 unless exists $cmdParsed->{grepstr}; # If no grep section go no further

	# See if we have any grep strings (with options)
	for my $grepstr (@{$cmdParsed->{grepstr}->{lst}}) {
		debugMsg(4,"=Processing cmdParsed section 'grepstr': ", \$grepstr->{str}, "\n");
		derefVariables($db, $cmdParsed, $grepstr);
		if ($grepstr->{str} =~ /^!$/) { # Trailing ! = filter empty lines
			debugMsg(1,"-> Grep-Mode : >!nul<\n");
			push(@{$grep->{Advanced}}, 0);
			push(@{$grep->{Mode}}, '!nul');
			push(@{$grep->{Instance}}, undef);
			push(@{$grep->{Regex}}, undef);
			$grep->{String} = 1; # Enough for prepping grep structure
			next;
		}
		elsif ($grepstr->{str} =~ /^(\^|\|{2}|!{2}|\||!)\s*(.+)$/) { # We no longer need complicated regex; parseCommand does it now
			($grepMode, $grepString) = ($1, $2);
		}
		else {
			printOut($script_io, "\n$ScriptName: Invalid grep pattern: $grepstr->{str}\n$prompt");
			return;
		}

		$grepAdv = $grepMode =~ /^..$/ ? 1 : 0;
		$grepQuotes = 0;

		# Set grep mode and advanced flag
		push(@{$grep->{Advanced}}, $grepAdv);
		push(@{$grep->{Mode}}, $grepMode);
		debugMsg(1,"-> Grep-Mode : >", \$grepMode, "<\n");

		# Format grep string (to be set as Regex)
		$grepString =~ s/^\s+//;		# Remove leading spaces
		$grepString =~ s/\s+$//;		# Remove trailing spaces
		$grepQuotes = listQuotesRemove(\$grepString); # Remove quotes encompassing entire $grepString, or comma separated portions; remember if quotes were removed
							      # (but not if: route-map "my text"); if quotes removed, $grepString comes back with quoteCurlyMask($grepString, ',')
		$grepString = quoteCurlyMask($grepString, ' ') unless $grepQuotes; # This will take care of route-map case
		debugMsg(1,"-> Grep-String-Initial : >", \$grepString, "<\n");
		if ($grepAdv && !$grepQuotes && $grepString =~ /^vlan(?:\s+(\S+))?$/i) { # Vlan list or range
			my $vlanidlist = $1;
			my $vlanListRef;
			push(@{$grep->{Instance}}, 'Vlan');
			$grepString =~ s/,$//; # No trailing comma
			debugMsg(1,"-> Grep-Instance : set to Vlan\n");
			if ($host_io->{Type} eq 'WLAN9100') {
				if (defined $vlanidlist) {
					if ($vlanidlist =~ /^[\d\-,]+$/) { # VLAN ids supplied
						$vlanListRef = generateVlanList($vlanidlist, 1);
						$grepString = '\s+add  "[^"]+"  number  (?:' . join(',', @$vlanListRef) . ')(?:[^\d]|$)';
					}
					else { # VLAN names
						$grepString = '(?:\s+add  "(?:' . $vlanidlist . ')"  number  \d+|vlan\s+"(?:' . $vlanidlist . ')")';
					}
					$grepString =~ s/,/|/g;
				}
			}
			else {
				# Allow Perl's metacharacters {}[]()^$.|*+?\ and backslash the rest
				$grepString =~ s/([\/])/\\$1/g;
				debugMsg(1,"-> Grep-String-after-backslashing : >", \$grepString, "<\n");
				$grepString =~ s/^vlan\s+/vlan /i;
				if (defined $vlanidlist && $vlanidlist !~ /^[\d\-,]+$/) { # VLAN names
					$grepString =~ s/[\'\"]//g;	# Remove all and any quotes
					if ($grepString =~ s/^vlan ((?:[\w-]+,)+[\w-]+)$/vlan \"?(?:$1)\"?(?:[^\\w]|\$)/i) {
						$grepString =~ s/,/|/g;
					}
					else {
						$grepString =~ s/^vlan ([\w-]+)$/vlan \"?(?:$1)\"?(?:[^\\w]|\$)/i;
					}
					$grepString =~ s/^vlan /vlan (?:create \\d+ name )?/i;
				}
				else { # VLAN ids or null
					if (defined $vlanidlist) {
						$vlanListRef = generateVlanList($vlanidlist, 1);
						$grepString =~ s/^(vlan )((?:\d+[,\-])*\d+)$/$1 . join(',', @$vlanListRef)/e;
					}
					if ($grepString =~ s/^vlan ((?:\d+,)+\d+)$/vlan (?:$1)(?:[^\\d\/:]|\$)/i) {
						$grepString =~ s/,/|/g;
					}
					elsif ($grepString =~ /^vlan \S/i) {
						$grepString .= '(?:[^\d/:]|$)';
					}
					elsif ($grepString =~ /^vlan$/i) {
						$grepString .= ' '; # Add space so it gets updated in s/// below
					}
					$grepString =~ s/^vlan /(?:(?:vlan(?:-id)?|vid ?) (?:(?:[\\w\\-]+ (?:remove|tag )?)?(?:[,\\d\\-]+?[,\\-])?)?|ip rsmlt peer-address [\\d\\.]+ [\\d\\w:]+ )/i;
				}
			}
			push(@{$grep->{RangeList}}, $vlanListRef);
			debugMsg(1,"-> Grep-RangeList - set to: ", \join(',', @$vlanListRef), "\n") if defined $vlanListRef;
			debugMsg(1,"-> Grep-String-Formatted : >", \$grepString, "<\n");
		}
		elsif ($grepAdv && !$grepQuotes && $grepString =~ /^mlt(?:\s+\S+)?$/i) { # Mlt
			push(@{$grep->{Instance}}, 'Mlt');
			push(@{$grep->{RangeList}}, undef);
			$grepString =~ s/,$//; # No trailing comma
			debugMsg(1,"-> Grep-Instance : set to Mlt\n");
			# Allow Perl's metacharacters {}[]()^$.|*+?\ and backslash the rest
			$grepString =~ s/([\/])/\\$1/g;
			debugMsg(1,"-> Grep-String-after-backslashing : >", \$grepString, "<\n");
			$grepString =~ s/^mlt\s+/mlt /i;
			$grepString =~ s/^mlt \K((?:\d+[,\-])*\d+)$/generateVlanList($1)/e;
			if ($grepString =~ s/^mlt ((?:\d+,)+\d+)$/(?:(?:^|[^n] )mlt (?:$1)|vlan mlt \\d+ (?:$1)|lacp key \\d+ mlt-id (?:$1)|mlt spanning-tree (?:$1)|Trunk:(?:$1))(?:[^\\d]|\$)/i) {
				$grepString =~ s/,/|/g;
			}
			else {
				$grepString =~ s/^mlt (\d+)$/(?:(?:^|[^n] )mlt $1|vlan mlt \\d+ $1|lacp key \\d+ mlt-id $1|mlt spanning-tree $1|Trunk:$1)(?:[^\\d]|\$)/i;
				$grepString =~ s/^mlt$/(?:(?:^|[^n] )mlt \\d+|vlan mlt \\d+ \\d+|lacp key \\d+ mlt-id \\d+|mlt spanning-tree \\d+)(?:[^\\d]|\$)/i;
			}
			debugMsg(1,"-> Grep-String-Formatted : >", \$grepString, "<\n");
		}
		elsif ($grepAdv && !$grepQuotes && $grepString =~ /^loopback(?:\s+\S+)?$/i) { # Loopback
			push(@{$grep->{Instance}}, 'Loopback');
			push(@{$grep->{RangeList}}, undef);
			$grepString =~ s/,$//; # No trailing comma
			debugMsg(1,"-> Grep-Instance : set to Loopback\n");
			# Allow Perl's metacharacters {}[]()^$.|*+?\ and backslash the rest
			$grepString =~ s/([\/])/\\$1/g;
			debugMsg(1,"-> Grep-String-after-backslashing : >", \$grepString, "<\n");
			$grepString =~ s/^loopback\s+/loopback /i;
			$grepString =~ s/^loopback \K((?:\d+[,\-])*\d+)$/generateVlanList($1)/e;
			if ($grepString =~ s/^loopback ((?:\d+,)+\d+)$/loopback (?:$1)(?:[^\\d]|\$)/i) {
				$grepString =~ s/,/|/g;
			}
			elsif ($grepString =~ /^loopback \d/i) {
				$grepString .= '(?:[^\d]|$)';
			}
			debugMsg(1,"-> Grep-String-Formatted : >", \$grepString, "<\n");
		}
		elsif ($grepAdv && !$grepQuotes && $grepString =~ /^vrf(?:\s+(?:\S+,)*\S+)?$/i) { # Vrf
			push(@{$grep->{Instance}}, 'Vrf');
			push(@{$grep->{RangeList}}, undef);
			debugMsg(1,"-> Grep-Instance : set to Vrf\n");
			# Allow Perl's metacharacters {}[]()^$.|*+?\ and backslash the rest
			$grepString =~ s/([\/])/\\$1/g;
			debugMsg(1,"-> Grep-String-after-backslashing : >", \$grepString, "<\n");
			$grepString =~ s/^vrf\s+/vrf /i;
			if ($grepString =~ s/^vrf ((?:[^,]+,)+[^,]+)$/vrf (?:$1)(?:\\s|\$)/i) {
				$grepString =~ s/,/|/g;
			}
			else {
				$grepString =~ s/^vrf (.*)/vrf $1(?:\\s|\$)/i;
			}
			debugMsg(1,"-> Grep-String-Formatted : >", \$grepString, "<\n");
		}
		elsif ($grepAdv && !$grepQuotes && $grepString =~ /^route-map(?:\s+((?:\S+,)*\S+))?$/i) { # Route-map
			push(@{$grep->{Instance}}, 'RouteMap');
			push(@{$grep->{RangeList}}, undef);
			debugMsg(1,"-> Grep-Instance : set to RouteMap\n");
			my $matchString = defined $1 ? quoteCurlyUnmask($1, ' ') : '';
			$matchString =~ s/[\'\"]//g;	# Remove all and any quotes
			$grepString =~ s/^route-map\s+/route-map /i;
			if ($grepString =~ s/^route-map (?:[^,]+,)+[^,]+$/route-map \.*?(?:$matchString)/i) {
				$grepString =~ s/,/|/g;
			}
			else {
				$grepString =~ s/^route-map .*$/route-map \.*?$matchString/i;
			}
			debugMsg(1,"-> Grep-String-Formatted : >", \$grepString, "<\n");
			# Allow Perl's metacharacters {}[]()^$.|*+?\ and backslash the rest - at the end so also applies to $matchString
			$grepString =~ s/([\/])/\\$1/g;
			debugMsg(1,"-> Grep-String-after-backslashing : >", \$grepString, "<\n");
		}
		elsif ($grepAdv && !$grepQuotes && ($grepString =~ /^router(?:\s+(?:\S+,)*\S+)?$/i ||
		       $grepString =~ /^(?:(?:ospf|rip|bgp|isis|bfd),)*(?:ospf|rip|bgp|isis|bfd)$/i ||
		       $grepString =~ /^router(?:\s+isis\s+remote)?$/i)) { # Router
			push(@{$grep->{Instance}}, 'Router');
			push(@{$grep->{RangeList}}, undef);
			debugMsg(1,"-> Grep-Instance : set to Router\n");
			# Allow Perl's metacharacters {}[]()^$.|*+?\ and backslash the rest
			$grepString =~ s/([\/])/\\$1/g;
			debugMsg(1,"-> Grep-String-after-backslashing : >", \$grepString, "<\n");
			$grepString =~ s/^router\s+/router /i;
			if ($grepString =~ s/^router ((?:\w+,)+\w+)$/router (?:$1)(?:\\s|\$)/i) {
				$grepString =~ s/,/|/g;
			}
			elsif ($grepString =~ /^router \w/i) {
				$grepString .= '(?:\s|$)';
			}
			elsif ($grepString =~ s/,/|/g) {
				$grepString = '(?:'.$grepString.')';
			}
			debugMsg(1,"-> Grep-String-Formatted : >", \$grepString, "<\n");
		}
		elsif ($grepAdv && !$grepQuotes && $grepString =~ /^i-?sid(?:\s+\S+)?$/i) { # I-sid (accept both i-sid & isid)
			push(@{$grep->{Instance}}, 'Isid');
			push(@{$grep->{RangeList}}, undef);
			$grepString =~ s/,$//; # No trailing comma
			debugMsg(1,"-> Grep-Instance : set to Isid\n");
			# Allow Perl's metacharacters {}[]()^$.|*+?\ and backslash the rest
			$grepString =~ s/([\/])/\\$1/g;
			debugMsg(1,"-> Grep-String-after-backslashing : >", \$grepString, "<\n");
			$grepString =~ s/^isid/i-sid/i;
			$grepString =~ s/^i-sid\s+/i-sid /i;
			$grepString =~ s/^i-sid \K((?:\d+[,\-])*\d+)$/generateVlanList($1)/e;
			if ($grepString =~ s/^i-sid ((?:\d+,)+\d+)$/i-sid (?:$1)(?:[^\\d]|\$)/i) {
				$grepString =~ s/,/|/g;
			}
			elsif ($grepString =~ /^i-sid \d/i) {
				$grepString .= '(?:[^\d]|$)';
			}
			$grepString =~ s/^i-sid /i-sid (?:\\d+ |"[^"]+" |\\S+ )?/i; #"# For both "vlan i-sid <vid> <isid>" and "ip isid-list <name> <isid>" 
			$grepString =~ s/^i-sid/(?:i-sid|isid-list)/i;
			debugMsg(1,"-> Grep-String-Formatted : >", \$grepString, "<\n");
		}
		elsif ($grepAdv && !$grepQuotes && $grepString =~ /^acl(?:\s+\S+)?$/i) { # Acl
			push(@{$grep->{Instance}}, undef);
			push(@{$grep->{RangeList}}, undef);
			$grepString =~ s/,$//; # No trailing comma
			debugMsg(1,"-> Grep-Instance : undefined (for ACL)\n");
			# Allow Perl's metacharacters {}[]()^$.|*+?\ and backslash the rest
			$grepString =~ s/([\/])/\\$1/g;
			debugMsg(1,"-> Grep-String-after-backslashing : >", \$grepString, "<\n");
			$grepString =~ s/^acl\s+/acl /i;
			$grepString =~ s/^acl \K((?:\d+[,\-])*\d+)$/generateVlanList($1)/e;
			if ($grepString =~ s/^acl ((?:\d+,)+\d+)$/acl (?:$1)(?:[^\\d]|\$)/i) {
				$grepString =~ s/,/|/g;
			}
			elsif ($grepString =~ /^acl \d/i) {
				$grepString .= '(?:[^\d]|$)';
			}
			$grepString =~ s/^acl /acl (?:[\\w\\-]+ |ace [\\w\\-]+ )?/i;
			debugMsg(1,"-> Grep-String-Formatted : >", \$grepString, "<\n");
		}
		elsif ($grepAdv && !$grepQuotes && $grepString =~ /^(?:logical-intf|lintf|lisis|isl)(?:\s+\S+)?$/i) { # logical-intf
			push(@{$grep->{Instance}}, 'LogicalIntf');
			push(@{$grep->{RangeList}}, undef);
			$grepString =~ s/,$//; # No trailing comma
			debugMsg(1,"-> Grep-Instance : set to LogicalIntf\n");
			# Allow Perl's metacharacters {}[]()^$.|*+?\ and backslash the rest
			$grepString =~ s/([\/])/\\$1/g;
			debugMsg(1,"-> Grep-String-after-backslashing : >", \$grepString, "<\n");
			$grepString =~ s/^(?:lintf|lisis|isl)/logical-intf/i;
			$grepString =~ s/^logical-intf\s+/logical-intf /i;
			$grepString =~ s/^logical-intf \K((?:\d+[,\-])*\d+)$/generateVlanList($1)/e;
			if ($grepString =~ s/^logical-intf ((?:\d+,)+\d+)$/logical-intf isis (?:$1)(?:[^\\d]|\$)/i) {
				$grepString =~ s/,/|/g;
			}
			elsif ($grepString =~ s/^logical-intf (\d+)$/logical-intf isis $1(?:[^\\d]|\$)/i) {
			}
			else {
				$grepString =~ s/^logical-intf (.+)$/logical-intf isis \\d+ (?:\\S+ )+name .*$1.*\$/i;
			}
			debugMsg(1,"-> Grep-String-Formatted : >", \$grepString, "<\n");
		}
		elsif ($grepAdv && !$grepQuotes && $grepString =~ /^mgmt(?:\s+\S+)?$/i) { # Mgmt
			push(@{$grep->{Instance}}, 'Mgmt');
			push(@{$grep->{RangeList}}, undef);
			$grepString =~ s/,$//; # No trailing comma
			debugMsg(1,"-> Grep-Instance : set to Mgmt\n");
			# Allow Perl's metacharacters {}[]()^$.|*+?\ and backslash the rest
			$grepString =~ s/([\/])/\\$1/g;
			debugMsg(1,"-> Grep-String-after-backslashing : >", \$grepString, "<\n");
			$grepString =~ s/^mgmt\s+/mgmt /i;
			$grepString =~ s/^mgmt \K((?:\d+[,\-])*\d+)$/generateVlanList($1)/e;
			if ($grepString =~ s/^mgmt ((?:\d+\\\/\d+,)?\d+\\\/\d+)$/interface mgmtEthernet (?:$1)(?:[^\\d]|\$)/i) {
				$grepString =~ s/,/|/g;
			}
			elsif ($grepString =~ s/^mgmt ((?:\d+,)+\d+)$/mgmt (?:$1)(?:[^\\d]|\$)/i) {
				$grepString =~ s/,/|/g;
			}
			else {
				$grepString =~ s/^mgmt$/(?:mgmt[ \-]|interface mgmtEthernet |router vrf MgmtRouter\$)/i;
			}
			debugMsg(1,"-> Grep-String-Formatted : >", \$grepString, "<\n");
		}
		elsif ($grepAdv && !$grepQuotes && $grepString =~ /^(?:dhcp-serv(?:er?)?|dhcp-?(?:s(?:[er][rv]?)?)?)(?:\s+((?:\S+,)*\S+))?$/i) { # DHCP Server
			push(@{$grep->{Instance}}, 'DhcpSrv');
			push(@{$grep->{RangeList}}, undef);
			debugMsg(1,"-> Grep-Instance : set to DhcpSrv\n");
			my $matchString = defined $1 ? quoteCurlyUnmask($1, ' ') : '';
			$matchString =~ s/[\'\"]//g;	# Remove all and any quotes
			$grepString =~ s/^(?:dhcp-serv(?:er?)?|dhcp-?s(?:[er][rv]?)?)/dhcp-server/i;
			$grepString =~ s/^dhcp-server\s+/dhcp-server /i;
			if ($grepString =~ s/^dhcp-server (?:[^,]+,)+[^,]+$/dhcp-server \.*?(?:$matchString)/i) {
				$grepString =~ s/,/|/g;
			}
			else {
				$grepString =~ s/^dhcp-server .*$/dhcp-server \.*?$matchString/i;
			}
			debugMsg(1,"-> Grep-String-Formatted : >", \$grepString, "<\n");
			# Allow Perl's metacharacters {}[]()^$.|*+?\ and backslash the rest - at the end so also applies to $matchString
			$grepString =~ s/([\/])/\\$1/g;
			debugMsg(1,"-> Grep-String-after-backslashing : >", \$grepString, "<\n");
		}
		elsif ($grepAdv && !$grepQuotes && $host_io->{Type} eq 'WLAN9100' && $grepString =~ /^ssid(?:\s+(\S+))?$/i) { # SSID list or range
			push(@{$grep->{Instance}}, 'Ssid');
			push(@{$grep->{RangeList}}, undef);
			debugMsg(1,"-> Grep-Instance : set to Ssid\n");
			my $ssidlist = $1;
			$ssidlist =~ s/,$//; # No trailing comma
			if (defined $ssidlist) {
				$grepString = '\s+(?:add |edit) "(?:' . $ssidlist . ')"$';
				$grepString =~ s/,/|/g;
			}
		}
		elsif ($grepAdv && !$grepQuotes && $grepString =~ /^ovsdb/i) { # OVSDB
			push(@{$grep->{Instance}}, 'Ovsdb');
			push(@{$grep->{RangeList}}, undef);
			debugMsg(1,"-> Grep-Instance : set to Ovsdb\n");
		}
		elsif ($grepAdv && !$grepQuotes && $grepString =~ /^app(?:l(?:i(?:c(?:a(?:t(?:i(?:on?)?)?)?)?)?)?)?$/i) { # Application
			push(@{$grep->{Instance}}, 'Application');
			push(@{$grep->{RangeList}}, undef);
			debugMsg(1,"-> Grep-Instance : set to Application\n");
		}
		elsif (!$grepQuotes && (($portList, $portHash) = generatePortList($host_io, $grepString)) && length $portList) { # Multiple or Single Ethernet ports / also single number
			push(@{$grep->{Instance}}, 'Port');
			push(@{$grep->{RangeList}}, $grepMode eq '^' ? undef : $portHash);
			debugMsg(1,"-> Grep-Instance : set to Port (single/multiple) / portList = ", \$portList, "\n");
			$grepString = $portList;
			if ($host_io->{Type} eq 'BaystackERS') {
				my $noSlots;
				$noSlots = 1 while $grepString =~ s/(^|,)(\d+(?:,|$))/$1(?:1\/)?$2/; # Ports/numbers without a slot, accept matches for 1/port
				1 while !$noSlots && $grepString =~ s/(^|,)((\d+)\/(\d+))(,|$)/$1(?:$2|Unit:$3 Port: ?$4)$5/; # Match '2/3' & 'Unit:2 Port: 3'
			}
			$grepString =~ s/,$//; # No trailing comma
			$grepString =~ s/,/|/g;
			$grepString = join('', '(?:[,\s\(\-t:m]|^)\K(?:', $grepString, ')(?=[,\s\)\(\e]|$)'); # Combined regex for '^' and other modes
			debugMsg(1,"-> Grep-String-Formatted : >", \$grepString, "<\n");
		}
		else {
			$grepString = quoteCurlyUnmask($grepString, ' ') unless $grepQuotes;
			if ($grepAdv && $grepString =~ /(?:^|,)(?:ospf|rip|bgp|isis)(?:,|$)/) {
				push(@{$grep->{Instance}}, 'Router');
				debugMsg(1,"-> Grep-Instance : set to Router (from free pattern)\n");
			}
			elsif ($grepAdv && $grepString =~ /(?:^|,)igmp(?:,|$)/) {
				push(@{$grep->{Instance}}, 'Igmp');
				debugMsg(1,"-> Grep-Instance : set to Igmp (from free pattern)\n");
			}
			else {
				push(@{$grep->{Instance}}, undef);
				debugMsg(1,"-> Grep-Instance : undefined\n");
			}
			push(@{$grep->{RangeList}}, undef);
			$grepString =~ s/,$//; # No trailing comma
			# Allow Perl's metacharacters {}[]()^$.|*+?\ and backslash the rest
			$grepString =~ s/([\/])/\\$1/g;
			debugMsg(1,"-> Grep-String-after-backslashing : >", \$grepString, "<\n");
			if ($grepAdv || $grepMode eq '^') {
				if ($grepString =~ s/((?:[a-f\d]{2}[:\-]?){3,5}[a-f\d]{2}[:\-]?)/macRegex($1)/ige) {
					debugMsg(1,"-> Grep-String-after-MAC-formatting : >", \$grepString, "<\n");
				}
				if ($grepString =~ s/((?:[a-f\d]{1,4}::?){0,7}(?:[a-f\d]{1,4})?|^::(?:\\\/0)?$)/ipv6Regex($1)/ige) {
					debugMsg(1,"-> Grep-String-after-IPv6-formatting : >", \$grepString, "<\n");
				}
			}
			$grepString = '(?:'.$grepString.')' if $grepString =~ s/,/\|/g;
			$grepString = quotesRemove(quoteCurlyUnmask('"'.$grepString.'"', ',')) if $grepQuotes;
			debugMsg(1,"-> Grep-String-Formatted : >", \$grepString, "<\n");
		}

		# Handle grep options
		# option -o- socket send override; simply move this option onto main command section, where it can be processed later
		$cmdParsed->{command}->{opt}->{o} = $grepstr->{opt}->{o} if defined $grepstr->{opt}->{o};
		# option -b- remove banner lines
		$grep->{KeepBanner} = 0 if defined $grepstr->{opt}->{b};
		# option -i- indent ACLI config
		if ($grepstr->{opt}->{i} && !$grep->{Indent}) { # -i > 0
			$grepIndent = $grepstr->{opt}->{i};
		}
		elsif (defined $grepstr->{opt}->{i} && !$grep->{Indent}) {
			$grepIndent = $term_io->{GrepIndent};
		}
		else {
			$grepIndent = 0;
		}
		if ($grepIndent) {
			$grep->{Indent} .= $Space while $grepIndent--;
		}
		
		# Set grep Regex
		# option -s- make grep case sensitive
		eval {
			local $SIG{__WARN__} = sub { die shift }; # Turn every warning into an exception
			$grepRegex = defined $grepstr->{opt}->{s} ? qr/$grepString/ : qr/$grepString/i;
		};
		if ($@) {
			(my $message = $@) =~s/;.*$//;
			$message =~ s/ at .+ line .+$//; # Delete file & line number info
			resetGrepStructure($grep);
			printOut($script_io, "\n$ScriptName: Invalid regular expression: $message\n$prompt");
			return;
		}
		push(@{$grep->{Regex}}, $grepRegex);
		debugMsg(1,"-> Grep-Regex : >", \$grepRegex, "<\n");
		$term_io->{HLgrep} = $grepRegex if $grepMode eq '^';

		# If we get here, we're all set for grep
		$grep->{String} = 1;
	}
	return 1;
}


sub processLocalOptions { # Process output '>' to variable/file, input '<' from file, grep, -o, -y, -cpus, feedargs
	my ($db, $cmdParsed) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $socket_io = $db->[6];
	my $grep = $db->[10];
	my $vars = $db->[12];

	my $prompt = appendPrompt($host_io, $term_io);

	return 1 if $cmdParsed->{command}->{emb} =~ /^\@(?:\$|if|elsif|while|until|for|next|last|exit)$/;

	#
	# Output processing ">" Variable capture
	#
	if (exists $cmdParsed->{varcapt}) {
		debugMsg(4,"=Processing cmdParsed section 'varcapt': ", \$cmdParsed->{varcapt}->{str}, "\n");
		derefVariables($db, $cmdParsed, $cmdParsed->{'varcapt'});
		if ($cmdParsed->{varcapt}->{str} =~ s/\s*(>>?)([^=].*)$//) { # Syntax >$var
			my ($mode, $destination) = ($1, $2);
			# Format destination string
			$destination =~ s/^\s+//;		# Remove leading spaces
			$destination =~ s/\s+$//;		# Remove trailing spaces
			my ($valuesToCapture, %columnToIndexMap);
			my ($ok, $columnRegex, $customRegex) = processVarCapInput($db, $prompt, $destination);
			return unless $ok;
			my $caseInsensitive = defined $cmdParsed->{varcapt}->{opt}->{i} ? 1 : 0;
			$term_io->{VarGRegex} = defined $cmdParsed->{varcapt}->{opt}->{g} ? 1 : 0;
			my $varsListed = scalar @{$term_io->{VarCapture}};
			# First process the regex
			if (defined $columnRegex) { # %<n> Regex supplied
				$columnRegex =~ s/(\d)([\$\%])/$1,$2/g;	# if syntax %1%2%3, convert to %1,%2,%3
				$columnRegex =~ s/[\$\%]//g;	# Now remove the % or $ chars; so we are just left with a list of numbers
				my ($i, $range);
				$columnRegex =~ s/(\d+)-(\d+)/$range = $1; for $i ($1+1..$2) { $range .= ",$i" }; $range/ge;
				$columnRegex =~ s/(\d+)-$/$range = $1; for $i ($1+1..$VarRangeUnboundMax) { $range .= ",$i" }; $range/ge;
				my @valuesToCap = split(',', $columnRegex);
				$valuesToCapture = scalar @valuesToCap; # In this case $valuesToCapture does not include hash keys (we add these further down)
				debugMsg(1,"-> Number of variables to capture calculated = ", \$valuesToCapture, "<\n");
				if ($varsListed > 1 && $varsListed ne $valuesToCapture) {
					printOut($script_io, "\n$ScriptName: supplied $varsListed variables but $valuesToCapture capture columns\n$prompt");
					$term_io->{VarCapture} = [];
					return;
				}
				if ($varsListed == $valuesToCapture) { # Map the relevant capture index to each variable
					for my $i (0 .. $#valuesToCap) {
						$term_io->{VarCapIndxVals}->{ $term_io->{VarCapture}->[$i] } = $valuesToCap[$i];
						debugMsg(1,"-> Variable \$$term_io->{VarCapture}->[$i] bound to column \%$valuesToCap[$i]\n");
					}
				}
				# Create the regex string (it needs to include the hask indexes if the variables are hashes)
				my ($counter, $relativeIndex, $first) = (1, 0, 1);
				$term_io->{VarRegex} = '^\s*';
				my %mergedList = map { $_ => 1 } (@valuesToCap, values %{$term_io->{VarCapHashKeys}}); # Merge both lists & remove duplicate (using a hash)
				foreach my $idx (sort {$a <=> $b} keys %mergedList) {
					# We should now have a sorted list of input %1,%2,etc and any hash index specified in $var{%n}, without duplicates
					unless ($counter == 1) { # Skip on 1st cycle
						$term_io->{VarRegex} .= $first ? '\s+' : '(?:\s+';
					}
					while ($counter++ < $idx) {
						$term_io->{VarRegex} .= $first ? '\S+\s+' : '\S+)?(?:\s+';
					}
					if ($first) { # 1st capture value is expected
						$term_io->{VarRegex} .= '(\S+)';
						$first = 0;
					}
					else {
						$term_io->{VarRegex} .= '(\S+))?';
					}
					$columnToIndexMap{$idx} = $relativeIndex++;
				}
				# Update both the hash key indexes and value indexes to be based on 0-based order of capture regex (and no longer on %<n> number)
				if ($varsListed == $valuesToCapture) { # Otherwise $term_io->{VarCapIndxVals}->{$variable} will be undefined below
					foreach my $variable (@{$term_io->{VarCapture}}) {
						if ($term_io->{VarCaptureType}->{$variable} eq 'hash' && !defined $term_io->{VarCaptureKoi}->{$variable}) { # Hash
							$term_io->{VarCapHashKeys}->{$variable} = $columnToIndexMap{ $term_io->{VarCapHashKeys}->{$variable} };
							debugMsg(1,"-> Updated variable \$$variable\{} hash index to ", \$term_io->{VarCapHashKeys}->{$variable}, "\n");
						}
						$term_io->{VarCapIndxVals}->{$variable} = $columnToIndexMap{ $term_io->{VarCapIndxVals}->{$variable} };
						debugMsg(1,"-> Updated variable \$$variable value index capture to ", \$term_io->{VarCapIndxVals}->{$variable}, "\n");
					}
				}
				$term_io->{VarCustomRegex} = 1;
				$term_io->{VarCaptureNumb} = scalar keys %mergedList;
				debugMsg(1,"-> Variable capture using \%<n> regex >", \$term_io->{VarRegex}, "<\n");
			}
			elsif (defined $customRegex) { # Custom Regex supplied
				$term_io->{VarRegex} = $customRegex;
				if ($term_io->{VarRegex} =~ /(?:^|[^\\])\(/ ) { # if regex has capturing bracket...
					my $varRegex = backslashMask($term_io->{VarRegex}, '(');
					my @captureBrackets = $varRegex =~ /\(/g;
					$valuesToCapture = scalar @captureBrackets; # In this case $valuesToCapture does include hash keys (we subtract these further down)
					debugMsg(1,"-> valuesToCapture is number of capture brackets seen in regex = ", \$valuesToCapture, "\n");
					$term_io->{VarRegex} = '(?i:'.$term_io->{VarRegex}.')' if $caseInsensitive;
				}
				else { # we have to add brackets
					if ($caseInsensitive) {
						$term_io->{VarRegex} = '(?i'.$term_io->{VarRegex}.')';
					}
					else {
						$term_io->{VarRegex} = '('.$term_io->{VarRegex}.')';
					}
					$valuesToCapture = 1;
				}
				eval {
					local $SIG{__WARN__} = sub { die shift }; # Turn every warning into an exception
					$term_io->{VarRegex} = qr/$term_io->{VarRegex}/;
				};
				if ($@) {
					(my $message = $@) =~s/;.*$//;
					$message =~ s/ at .+ line .+$//; # Delete file & line number info
					printOut($script_io, "\n$ScriptName: Invalid regular expression: $message\n$prompt");
					$term_io->{VarCapture} = [];
					return;
				}
				# Some error checking
				foreach my $variable (@{$term_io->{VarCapture}}) {
					if ($term_io->{VarCaptureType}->{$variable} eq 'hash') { # Hash
						if ($term_io->{VarCapHashKeys}->{$variable} > $valuesToCapture) {
							printOut($script_io, "\n$ScriptName: hash index %$term_io->{VarCapHashKeys}->{$variable} must refer to one of regex capturing brackets\n$prompt");
							$term_io->{VarCapture} = [];
							return;
						}
					}
				}
				# Make 0-based and calculate actual value capturing brackets (vs. hash key ones)
				foreach my $variable (@{$term_io->{VarCapture}}) { # Make 0-based
					if ($term_io->{VarCaptureType}->{$variable} eq 'hash') { # Hash
						$term_io->{VarCapHashKeys}->{$variable}--;
					}
				}
				my %keyIndexes = map { $_ => 1 } (values %{$term_io->{VarCapHashKeys}});	# Remove duplicates, by using hash keys
				my @keyIndexes = sort {$a <=> $b} keys %keyIndexes;				# Then sort into a list
				$term_io->{VarCaptureNumb} = $valuesToCapture;
				$valuesToCapture -= scalar @keyIndexes;		# Now it holds just the values to capture without the indexes
				# Some more error checking
				if (($varsListed > 1 && $varsListed ne $valuesToCapture) || $valuesToCapture < 1) {
					printOut($script_io, "\n$ScriptName: supplied $varsListed variables but $valuesToCapture capture regex\n$prompt");
					$term_io->{VarCapture} = [];
					return;
				}
				# Map the relevant capture index to each variable
				if ($varsListed == $valuesToCapture) {
					my $idx = 0;
					debugMsg(1,"-> Hash keys indexes to filter out (0-based) = ", \join(',', @keyIndexes), "\n");
					foreach my $variable (@{$term_io->{VarCapture}}) {
						while (@keyIndexes && $idx == $keyIndexes[0]) {
							$idx++;
							shift @keyIndexes;
						}
						$term_io->{VarCapIndxVals}->{$variable} = $idx++;
						debugMsg(1,"-> Variable \$$variable bound to regex (0-based): $idx\n");
					}
				}
				$term_io->{VarCustomRegex} = 2;
				debugMsg(1,"-> Variable capture using custom regex >", \$term_io->{VarRegex}, "<\n");
			}
			else {
				$term_io->{VarRegex} = $VarCapturePortRegex;
				$term_io->{VarCustomRegex} = 0;
				$term_io->{VarCaptureNumb} = 1;
				if ($varsListed > 1) {
					printOut($script_io, "\n$ScriptName: supplied $varsListed variables but default port capturing can only work for 1 variable\n$prompt");
					$term_io->{VarCapture} = [];
					return;
				}
				# Error checking
				foreach my $variable (@{$term_io->{VarCapture}}) {
					if ($term_io->{VarCaptureType}->{$variable} eq 'hash' && !defined $term_io->{VarCaptureKoi}->{$variable}) { # Hash
						printOut($script_io, "\n$ScriptName: capturing to a hash variable requires a custom regex\n$prompt");
						$term_io->{VarCapture} = [];
						return;
					}
				}
				$term_io->{VarCapIndxVals}->{ $term_io->{VarCapture}->[0] } = 0;
				debugMsg(1,"-> Variable capture using regular \$VarCapturePortRegex\n");
			}
			debugMsg(1,"-> Variable values to capture (including indexes) = ", \$term_io->{VarCaptureNumb}, "\n");

			$term_io->{VarCaptureFlag} = 0;	# Reset flag
			
			# Process capturing mode: > overwrite / >> append
			foreach my $variable (@{$term_io->{VarCapture}}) {
				if ($mode eq '>>' && defined $vars->{$variable}) { # Variable already exists and we are appending
					if ($vars->{$variable}->{type} eq 'list') {
						if (defined $term_io->{VarCaptureKoi}->{$variable}) { # List element
							$term_io->{VarCaptureVals}->{$variable} = [ split(',', $vars->{$variable}->{value}->[ $term_io->{VarCaptureKoi}->{$variable} ]) ];
						}
						else { # Full list
							@{$term_io->{VarCaptureVals}->{$variable}} = @{$vars->{$variable}->{value}};
						}
					}
					elsif ($vars->{$variable}->{type} eq 'hash') {
						if (defined $term_io->{VarCaptureKoi}->{$variable}) { # Hash element
							$term_io->{VarCaptureVals}->{$variable} = [ split(',', $vars->{$variable}->{value}->{ $term_io->{VarCaptureKoi}->{$variable} }) ];
						}
						else { # Full hash
							foreach my $key (keys %{$vars->{$variable}->{value}}) {
								$term_io->{VarCaptureVals}->{$variable}->{$key} = [ split(',', $vars->{$variable}->{value}->{$key}) ];
							}
						}
					}
					else {
						$term_io->{VarCaptureVals}->{$variable} = [ split(',', $vars->{$variable}->{value}) ];	# Load list with existing elements
					}
				}
				else { # Variable does not yet exist or we are not appending ($mode eq '>')
					if ($term_io->{VarCaptureType}->{$variable} eq 'hash' && !defined $term_io->{VarCaptureKoi}->{$variable}) {
						$term_io->{VarCaptureVals}->{$variable} = {};	# Only case where we use a hash
					}
					else {
						$term_io->{VarCaptureVals}->{$variable} = [];	# Start with an empty list
					}
					if (defined $vars->{$variable}) { # If variable already exists, delete it now
						assignVar($db, $term_io->{VarCaptureType}->{$variable}, $variable, '=', '', $term_io->{VarCaptureKoi}->{$variable});
					}
				}
			}
		}
		delete $cmdParsed->{varcapt};
	}

	#
	# Output processing ">" output to file
	#
	if (exists $cmdParsed->{filecap}) {
		debugMsg(4,"=Processing cmdParsed section 'filecap': ", \$cmdParsed->{filecap}->{str}, "\n");
		derefVariables($db, $cmdParsed, $cmdParsed->{'filecap'});
		if ($cmdParsed->{filecap}->{str} =~ s/\s*(>>?)([^=].*)$//) { # Syntax > file
			my ($mode, $destination) = ($1, $2);
			# Format destination string
			$destination =~ s/^\s+//;		# Remove leading spaces
			$destination =~ s/\s+$//;		# Remove trailing spaces
			$script_io->{CmdLogOnly} = defined $cmdParsed->{filecap}->{opt}->{e} ? 0 : 1;
			quotesRemove(\$destination);
			unless (length $destination) {
				printOut($script_io, "\n$ScriptName: null output filename provided\n$prompt");
				$script_io->{CmdLogOnly} = undef;
				return;
			}
			if ($destination =~ /^\.[\w\d]+$/) { # .xxx -> switchname.xxx
				$destination = switchname($host_io) . $destination;
			}
			debugMsg(1,"-> Command output to file $mode $destination with LogOnly = $script_io->{CmdLogOnly}\n");
			$script_io->{CmdLogMode} = $mode;
			$script_io->{CmdLogFile} = $destination;
			$script_io->{CmdLogFlag} = 0;
		}
		delete $cmdParsed->{filecap};
	}

	#
	# Input processing "<"
	#
	if (exists $cmdParsed->{srcfile}) {
		debugMsg(4,"=Processing cmdParsed section 'srcfile': ", \$cmdParsed->{srcfile}->{str}, "\n");
		derefVariables($db, $cmdParsed, $cmdParsed->{'srcfile'});
		if ($cmdParsed->{srcfile}->{str} =~ s/\s*<([^=].+)$//) {
			my ($ok, $err) = readSourceFile($db, $1);
			unless ($ok) {
				printOut($script_io, "\n$ScriptName: $err\n$prompt");
				$script_io->{CmdLogFile} = $script_io->{CmdLogOnly} = $script_io->{CmdLogFlag} = undef; # In case of command "vlan <vid> some setting"(bug15)
				return;
			}
		}
		delete $cmdParsed->{srcfile};
	}

	#
	# Grep processing (needs to happen before socket override send option)
	#
	prepGrepStructure($db, $cmdParsed) or return;

	#
	# Socket override send option
	#
	if (defined $cmdParsed->{command}->{opt}->{o} && $term_io->{Sourcing} && $term_io->{SocketEnable}) {
		# -o option appended to command; cleaner syntax; but we still support old syntax when added after grepstr (handled in prepGrepStructure)
		# We always want echoMode = 'all' with -o; so we cache it while we prep the socket send buffer
		my $socketEchoCache = $socket_io->{TieEchoMode};
		$socket_io->{TieEchoMode} = 2;
		my $command = $cmdParsed->{command}->{str};	# We need to build the command to send via socket; the base command...
		if (exists $cmdParsed->{grepstr}) {		# ... + only all the grepstr sections, which will have had variables dereferenced by now
			for my $grepstr (@{$cmdParsed->{grepstr}->{lst}}) {
				$command .= $grepstr->{str};
			}
		}
		debugMsg(4,"=socket override switch command to send = /", \$command, "/\n");
		socketBufferPack($socket_io, $command."\n", 3);
		$socket_io->{TieEchoMode} = $socketEchoCache;
		$socket_io->{SocketWait} = 1;
		$socket_io->{TimerOverride} = $cmdParsed->{command}->{opt}->{o} if $cmdParsed->{command}->{opt}->{o} > 0;
		debugMsg(4,"=socket override switch with timer = /", \$socket_io->{TimerOverride}, "/\n");
	}

	#
	# General option processing; these options cannot be combined
	#
	if (defined $cmdParsed->{command}->{opt}->{y}) {
		$term_io->{YnPrompt} = 'y';
		$term_io->{YnPromptForce} = 1;
		$cmdParsed->{command}->{str} .= ' -y' if defined $YflagCommands{$host_io->{Type}} && $cmdParsed->{command}->{str} =~ /$YflagCommands{$host_io->{Type}}/;
	}
	if (defined $cmdParsed->{command}->{opt}->{n}) {
		$term_io->{YnPrompt} = 'n';
		$term_io->{YnPromptForce} = 1;
	}

	#
	# Other option processing
	#
	if (defined $cmdParsed->{command}->{opt}->{peercpu}) {
		if (defined $cmdParsed->{command}->{opt}->{bothcpus}) {
			printOut($script_io, "\n$ScriptName: cannot have both -bothcpus & -peercpu options\n$prompt");
			return;
		}
		if ($host_io->{RemoteAnnex}) {
			printOut($script_io, "\n$ScriptName: option -peercpu cannot be used if connected via Terminal Server\n$prompt");
			return;
		}
		if ($host_io->{Console}) {
			printOut($script_io, "\n$ScriptName: option -peercpu cannot be used if connected via Serial Port\n$prompt");
			return;
		}
		if ($host_io->{DualCP}) {
			$host_io->{SendMasterCP} = 0;
			$host_io->{SendBackupCP} = 1;
		}
		else { # Make error if this option used on single CPU systems
			printOut($script_io, "\n$ScriptName: option -peercpu cannot be used on single CPU device\n$prompt");
			return;
		}
		$term_io->{YnPrompt} = 'y'; # Implicit -y
		$term_io->{YnPromptForce} = 1;
		$cmdParsed->{command}->{str} .= ' -y' if defined $YflagCommands{$host_io->{Type}} && $cmdParsed->{command}->{str} =~ /$YflagCommands{$host_io->{Type}}/; # And add -y on commands which take it..
	}
	if (defined $cmdParsed->{command}->{opt}->{bothcpus}) {
		if ($host_io->{RemoteAnnex}) {
			printOut($script_io, "\n$ScriptName: option -bothcpus cannot be used if connected via Terminal Server\n$prompt");
			return;
		}
		if ($host_io->{Console}) {
			printOut($script_io, "\n$ScriptName: option -bothcpus cannot be used if connected via Serial Port\n$prompt");
			return;
		}
		if ($host_io->{DualCP}) {
			$host_io->{SendMasterCP} = 1;
			$host_io->{SendBackupCP} = 1;
		}
		# Do not report an error if this option is used on single CPU systems; like to paste same command to many switches..

		$term_io->{YnPrompt} = 'y'; # Implicit -y
		$term_io->{YnPromptForce} = 1;
		$cmdParsed->{command}->{str} .= ' -y' if defined $YflagCommands{$host_io->{Type}} && $cmdParsed->{command}->{str} =~ /$YflagCommands{$host_io->{Type}}/; # And add -y on commands which take it..
	}

	#
	# Feed input for command processing
	#
	$term_io->{FeedInputs} = $term_io->{CacheInputCmd} = $term_io->{CacheInputKey} = $term_io->{CacheFeedInputs} = undef;
	if (exists $cmdParsed->{feedarg}) {
		debugMsg(4,"=Processing cmdParsed section 'feedarg': ", \$cmdParsed->{feedarg}->{str}, "\n");
		derefVariables($db, $cmdParsed, $cmdParsed->{'feedarg'});
		while ($cmdParsed->{feedarg}->{str} =~ s/.*\K\/\/\s*(.*?)\s*$//) { # This regex was tricky; $command =~ s/\s*\/\/(.*?)$// did not work as you always get a greedy match from the right hand side..
			my $feed = $1;
			$feed = '' unless defined $feed;
			push(@{$term_io->{FeedInputs}}, $feed);
			debugMsg(1,"-> Feed Input added :>", \$feed, "<\n");
		}
		printOut($script_io, "\n$ScriptName: Accepted feed inputs: // " . join(' // ', @{$term_io->{FeedInputs}}) . "\n" );
		if (defined $cmdParsed->{command}->{opt}->{h}) {
			($term_io->{CacheInputCmd}, $term_io->{CacheInputKey}) = ($cmdParsed->{command}->{str}, $host_io->{BaseMAC});
		}
		elsif (defined $cmdParsed->{command}->{opt}->{f}) {
			($term_io->{CacheInputCmd}, $term_io->{CacheInputKey}) = ($cmdParsed->{command}->{str}, $host_io->{Type});
		}
		delete $cmdParsed->{feedarg};
	}
	return 1;
}

1;
