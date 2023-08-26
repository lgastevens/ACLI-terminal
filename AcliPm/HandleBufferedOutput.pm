# ACLI sub-module
package AcliPm::HandleBufferedOutput;
our $Version = "1.09";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(handleBufferedOutput);
}
use Control::CLI::Extreme qw(stripLastLine);
use Time::HiRes;
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::CacheFeedInputs;
use AcliPm::ChangeMode;
use AcliPm::DebugMessage;
use AcliPm::Error;
use AcliPm::ExitHandlers;
use AcliPm::GeneratePortListRange;
use AcliPm::GlobalDefaults;
use AcliPm::GlobalDeviceSettings;
use AcliPm::GlobalMatchingPatterns;
use AcliPm::Print;
use AcliPm::Prompt;
use AcliPm::Sed;
use AcliPm::Socket;
use AcliPm::Sourcing;
use AcliPm::Variables;


sub deltaPatternCheck { # Checks grep line for delta patterns and if found updates grep regex
	my ($db, $g, $line) = @_;
	my $host_io = $db->[3];
	my $grep = $db->[10];

	if ($grep->{Instance}[$g] && defined $Grep{DeltaPattern}{$host_io->{Type}}{$grep->{Instance}[$g]}) {
		foreach my $pat (@{$Grep{DeltaPattern}{$host_io->{Type}}{$grep->{Instance}[$g]}}) {
			if ($line =~ /$pat->[0]/) {
				my $delta = $1;
				debugMsg(2,"[$g]GrepDeltaPatternCaptured: ", \$delta, "\n");
				$grep->{Regex}[$g] =~ s/\)$/|$pat->[1]\Q$delta\E$pat->[2])/; # Append to grep regex pattern being used
				debugMsg(2,"[$g]GrepDeltaPatternContextAddingtoRegex: ", \$grep->{Regex}[$g], "\n");
			}
		}
	}
}


sub matchline { # Does port and vlan range expansion if necessary, and then does the match against grep string
	my ($host_io, $grep, $line, $g) = @_;
	if ($grep->{Instance}[$g] && $grep->{Instance}[$g] eq 'Port' && $line =~ /(?:\d\-\d|\d\/ALL)/) {
		debugMsg(2,"[$g]GrepPortLine-NeedingExpansion:\n>", \$line, "<\n");
		#1 /(\s)((?:\d{1,2}\/\d{1,2}(?:\-\d{1,2}\/\d{1,2})?,)*  \d{1,2}\/\d{1,2}-\d{1,2}\/\d{1,2} (?:,\d{1,2}\/\d{1,2}(?:\-\d{1,2}\/\d{1,2})?)*)(\s|$)/  = modular
		#1b/(\s)((?:\d{1,2}\/\d{1,2}(?:\/\d{1,2})?(?:\-\d{1,2}\/\d{1,2}(?:\/\d{1,2})?)?,)*  \d{1,2}\/\d{1,2}(?:\/\d{1,2})?-\d{1,2}\/\d{1,2}(?:\/\d{1,2})? (?:,\d{1,2}\/\d{1,2}(?:\/\d{1,2})?(?:\-\d{1,2}\/\d{1,2}(?:\/\d{1,2})?)?)*)(\s|$)/  = modular (channelized support)
		#2 /(\s)((?:\d{1,2}\/(?:ALL|\d{1,2}(?:\-\d{1,2}  )?),)* \d{1,2}\/(?:ALL|\d{1,2}-\d{1,2})  (?:,\d{1,2}\/(?:ALL|\d{1,2}(?:\-\d{1,2}  )?))*)(\s|$)/ = stackable
		#3 /(\s)((?:\d{1,2}: (?:\d{1,2}(?:\-\d{1,2}      )?),)* \d{1,2}: (?:\d{1,2}-\d{1,2})      (?:,\d{1,2}: (?:\d{1,2}(?:\-\d{1,2}      )?))*)(\s|$)/ = XOS stack/chassis
		#4 /(\s)((?:\d{1,2}           (?:\-\d{1,2}       )?, )* \d{1,2}\        -\d{1,2}          (?:,\d{1,2}         (?:\-\d{1,2}         )?) *)(\s|$)/  = standalone

		#1b
		if ($line =~ s/\s\K((?:\d{1,2}\/\d{1,2}(?:\/\d{1,2})?(?:\-\d{1,2}\/\d{1,2}(?:\/\d{1,2})?)?,)*\d{1,2}\/\d{1,2}(?:\/\d{1,2})?-\d{1,2}\/\d{1,2}(?:\/\d{1,2})?(?:,\d{1,2}\/\d{1,2}(?:\/\d{1,2})?(?:\-\d{1,2}\/\d{1,2}(?:\/\d{1,2})?)?)*)(?=\s|$)/generatePortList($host_io, $1, $grep->{RangeList}[$g])/e) {
			debugMsg(2,"[$g]GrepPortLine#1-FedToGeneratePortList:>", \$2, "<\n");
			debugMsg(2,"[$g]GrepPortLine#1-ExpandedLineToMatch:\n>", \$line, "<\n");
		}
		#2
		elsif ($line =~ s/\s\K((?:\d{1,2}\/(?:ALL|\d{1,2}(?:\-\d{1,2})?),)*\d{1,2}\/(?:ALL|\d{1,2}-\d{1,2})(?:,\d{1,2}\/(?:ALL|\d{1,2}(?:\-\d{1,2})?))*)(?=\s|$)/generatePortList($host_io, $1, $grep->{RangeList}[$g])/e) {
			debugMsg(2,"[$g]GrepPortLine#2-FedToGeneratePortList:>", \$2, "<\n");
			debugMsg(2,"[$g]GrepPortLine#2-ExpandedLineToMatch:\n>", \$line, "<\n");
		}
		#3
		elsif ($line =~ s/\s\K((?:\d{1,2}:(?:\d{1,2}(?:\-\d{1,2})?),)*\d{1,2}:(?:\d{1,2}-\d{1,2})(?:,\d{1,2}:(?:\d{1,2}(?:\-\d{1,2})?))*)(?=\s|$)/generatePortList($host_io, $1, $grep->{RangeList}[$g])/e) {
			debugMsg(2,"[$g]GrepPortLine#2-FedToGeneratePortList:>", \$2, "<\n");
			debugMsg(2,"[$g]GrepPortLine#2-ExpandedLineToMatch:\n>", \$line, "<\n");
		}
		#4
		elsif ($line =~ s/\s\K((?:\d{1,2}(?:\-\d{1,2})?,)*\d{1,2}\-\d{1,2}(?:,\d{1,2}(?:\-\d{1,2})?)*)(?=\s|$)/generatePortList($host_io, $1, $grep->{RangeList}[$g])/e ) {
			debugMsg(2,"[$g]GrepPortLine#3-FedToGeneratePortList:>", \$2, "<\n");
			debugMsg(2,"[$g]GrepPortLine#3-ExpandedLineToMatch:\n>", \$line, "<\n");
		}
		else {
			debugMsg(2,"[$g]GrepPortLine-NO_EXPANSION_PERFORMED!\n");
		}
	}
	if ($grep->{Instance}[$g] && $grep->{Instance}[$g] eq 'Vlan' && $grep->{RangeList}[$g] && $line =~ /vlan/i && $line =~ /\d\-\d/) {
		debugMsg(2,"[$g]GrepVlanLine-NeedingExpansion:\n>", \$line, "<\n");
		if ($line =~ s/\s\K((?:\d{1,4}(?:\-\d{1,4})?,)*\d{1,4}\-\d{1,4}(?:,\d{1,4}(?:\-\d{1,4})?)*)(?=\s|$)/generateVlanList($1, 0, $grep->{RangeList}[$g])/e ) {
			debugMsg(2,"[$g]GrepVlanLine#3-FedToGenerateVlanList:>", \$2, "<\n");
			debugMsg(2,"[$g]GrepVlanLine#3-ExpandedLineToMatch:\n>", \$line, "<\n");
		}
		else {
			debugMsg(2,"[$g]GrepVlanLine-NO_EXPANSION_PERFORMED!\n");
		}
	}
	if ($grep->{Mode}[$g] eq '^') {
		return $line =~ /$grep->{Regex}[$g]/ ? $line : undef;
	}
	return ($grep->{Mode}[$g] =~ /^\|/ && $line =~ /$grep->{Regex}[$g]/) ||
	       ($grep->{Mode}[$g] =~ /^\!/ && $line !~ /$grep->{Regex}[$g]/);
}


sub grepOutput { # Perform grep processing from output buffer into grep output buffer
	my $db = shift;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $socket_io = $db->[6];
	my $prompt = $db->[7];
	my $grep = $db->[10];

	my ($grepBuffer, $eol, $lastLine, @buffer, @grepbf, $lastRecord, $indentLevel, $indentNewline);
	my (@grepDisable, @enableSeen, @configSeen, @endSeen);

	# Use local buffer
	($grepBuffer, $host_io->{OutBuffer}, $host_io->{DeltaBuffer}) = ($host_io->{OutBuffer}, '', '');
	# Pre-pend grep cache if any
	if ($host_io->{GrepCache}) {
		$host_io->{GrepCache} =~ s/$CompleteLineMarker$//;
		($grepBuffer, $host_io->{GrepCache}) = ($host_io->{GrepCache} . $grepBuffer, '');
	}
	# Check grep buffer threshold
	if ($grep->{BufferThreshold} && !$grep->{CompleteOutput} && !checkForPrompt($host_io, \$grepBuffer, $prompt) && length $grepBuffer < $GrepBufferThreshold) {
		# No prompt in buffer, and the buffer size is below the threshold before we can safely start grepping
		$host_io->{GrepCache} = $host_io->{GrepCache} . $grepBuffer;
		debugMsg(2,"GrepBufferBelowThreshold:\n>", \$host_io->{GrepCache}, "<\n");
		return;
	}
	if ($grep->{BufferThreshold} && $host_io->{ErrorDetect} && errorDetected($db, \$grepBuffer) ) {
		debugMsg(2,"Detected Error at start of Grep Buffer - disabling grep\n");
		$host_io->{GrepBuffer} .= $grepBuffer;
		$host_io->{DeltaBuffer} = $grepBuffer if $socket_io->{EchoSendFlag};
		$grep->{String} = 0;
		return;
	}
	$grep->{BufferThreshold} = 0; # Ensure we don't apply GrepThreshold anymore
	debugMsg(2,"GrepBufferToProcess:\n>", \$grepBuffer, "<\n") unless defined $term_io->{DelayPrompt} && !$term_io->{DelayPromptDF};

	my $nestedStartLevel = $grep->{CfgContextLvl}; # Record context level to be used for each and every grep pattern
	GREPPAT: for my $g ( 0 .. $#{$grep->{Regex}} ) { # For every grep string
		#
		# Grep multiline processing (show commands with data entry displayed over more than 1 line)
		#
		if ( $grep->{MultiLine}[$g] || (!defined $grep->{MultiLine}[$g] && $grep->{Advanced}[$g] &&
		     exists $Grep{MultilineBanner}{$host_io->{Type}} && $grepBuffer =~ /($Grep{MultilineBanner}{$host_io->{Type}})/mg) ) {  # A show banner
		   	my $matchPos = pos $grepBuffer; # Record match position
			debugMsg(2,"[$g]GrepMultilineBannerDetected:\n>", \$1, "<\n") unless $grep->{MultiLine}[$g];
	
			# Some show commands are multiline, but do not have empty lines between records; so ensure they are separated by empty lines
			if (exists $Grep{MultilineApply}{$host_io->{Type}} && $grepBuffer =~ s/($Grep{MultilineApply}{$host_io->{Type}})/$1\n/g) {
				debugMsg(2,"[$g]GrepMultilineApply-Applied:\n>", \$grepBuffer , "<\n");
			}
			pos $grepBuffer = $matchPos; # Restore match position
			if ($grep->{MultiLine}[$g] || ( exists $Grep{MultilineRecord}{$host_io->{Type}} && $grepBuffer =~ /($Grep{MultilineRecord}{$host_io->{Type}})/ ) ) {
			   	# An entry over more than one line
				debugMsg(2,"[$g]GrepMultilineRecordsDetected:\n>", \$1, "<\n") unless $grep->{MultiLine}[$g];
				$grep->{MultiLine}[$g] = 1;
				if ($g == 0 && !$grep->{CompleteOutput}) {
					$lastRecord = '';
					if ($grepBuffer =~ s/([\n-]\n)((?:.+\n)?.+\n*)$/$1/) { # Take off last line/record
						$lastRecord = $2;
					}
					elsif ($grepBuffer =~ s/((?:.+\n)?.+\n*)$//) { # Take off last line/record; only last record left
						$lastRecord = $1;
					}
					debugMsg(2,"[$g]GrepMultiLine-LastRecord:\n>", \$lastRecord, "<\n");
				}
				@buffer = split( /[\n-]\n/, $grepBuffer); # Split the buffer into line-bundles in an array
				@grepbf = ();
				debugMsg(2,"[$g]GrepRegex:>", \$grep->{Regex}[$g], "<\n");
				debugMsg(2,"[$g]GrepMode:>", \$grep->{Mode}[$g], "<\n");
				foreach my $line (@buffer) {
					debugMsg(2,"[$g]GrepMultiLine:\n>", \$line, "<\n");
					if ($line eq '') { # Preserve empty lines
						push(@grepbf, $line);
						next;
					}
					# Stop greping on error messages
					if ( $host_io->{ErrorDetect} && errorDetected($db, \$line) ) {
						$grepDisable[$g] = 1;
					}
					# Restore \n or - removed during split
					if  ($line =~ /-$/) { # A banner section
						$line .= "-";	# Re-add a '-' char which was stripped off by split
					}
					else { # A regular multiline with displayed data
						$line .= "\n";	# Re-add one carriage return, also stripped off by split
					}
					if ( $grepDisable[$g] ) { # Accept all lines if grep gets disabled
						push(@grepbf, $line);
						next;
					}
					# Summary check & update
					if ($g == $#{$grep->{Regex}} && exists $Grep{SummaryPatterns}{$host_io->{Type}} && $line =~ /$Grep{SummaryPatterns}{$host_io->{Type}}/i) {
						# Summary lines are no longer updated in grep code but in handleBufferedOutput
						push(@grepbf, $line);
						next;
					}
					# Banner processing
					$grep->{BannerDetected}[$g] = 1 unless defined $grep->{BannerDetected}[$g]; # Prime it set, first time in here
					if (exists $Grep{BannerHardPatterns}{$host_io->{Type}} && $line =~ /$Grep{BannerHardPatterns}{$host_io->{Type}}/) { # Hard banner processing
						$grep->{BannerDetected}[$g] = 1;
						debugMsg(2,"[$g]MultiLine-BannerHardDetected; Banner Flag: on\n");
						push(@grepbf, $line) if $grep->{KeepBanner};
						next;
					}
					elsif ($grep->{BannerDetected}[$g]) { # Soft banner processing
						if ( ( exists $Grep{BannerSoftPatterns}{$host_io->{Type}} && $line =~ /$Grep{BannerSoftPatterns}{$host_io->{Type}}/ )
						  && !( exists $Grep{BannerExceptions}{$host_io->{Type}} && $line =~ /$Grep{BannerExceptions}{$host_io->{Type}}/ ) ) {
							debugMsg(2,"[$g]MultiLine-BannerSoftDetected\n");
							push(@grepbf, $line) if $grep->{KeepBanner};
							next;
						}
						else {
							$grep->{BannerDetected}[$g] = 0;
							debugMsg(2,"[$g]MultiLine-Clearing BannerFlag: off\n");
						}
					}
					# Record processing
					if (matchline($host_io, $grep, $line, $g)) {
						push(@grepbf, $line);
					}
				}
				$grepBuffer = join("\n", @grepbf); # Reconstruct the buffer
				$grepBuffer .= "\n" if length $grepBuffer;
				debugMsg(2,"[$g]AfterGrepMultiLineParse:\n>", \$grepBuffer, "<\n");
			} # if ( $grep->{MultiLine}[$g] ...||... $grepBuffer =~ /($Grep{MultilineRecord}
			# Reverse the adding of empty lines between records for MultilineApply
			if (exists $Grep{MultilineApply}{$host_io->{Type}} && $grepBuffer =~ s/($Grep{MultilineApply}{$host_io->{Type}})\n/$1/g) {
				debugMsg(2,"[$g]GrepMultilineApply-Removed:\n>", \$grepBuffer , "<\n");
			}
		} # if ( $grep->{MultiLine}[$g] ...||... $grepBuffer =~ /($Grep{MultilineBanner}...

		# If no banner or banner+multiline detected, then we are in single line procesing from now on
		$grep->{MultiLine}[$g] = 0 unless $grep->{MultiLine}[$g];

		#
		# Grep single line processing (all other show commands as well as show config)
		#
		if ($grep->{MultiLine}[$g] == 0) {
			if ($g == 0 && !$grep->{CompleteOutput}) {
				debugMsg(2,"BeforeGrepLastLineCheck:\n>", \$grepBuffer, "<\n");
				$lastLine = '';
				unless (chomp $grepBuffer) { # Remove last line, if it did not end with \n; we don't grep these
					$grepBuffer =~ s/\n?(.+)$//;
					$lastLine = $1;
					debugMsg(2,"[$g]Grep-lastLine:>", \$lastLine, "<\n");
				}
			}
			else { # Need buffer not to end with \n before we split, whether $g is 0 or not
				chomp $grepBuffer; # Needed if there are empty trailing fields in split below
			}
			debugMsg(2,"[$g]BeforeGrepInitialParse:\n>", \$grepBuffer, "<\n");
			@buffer = split( /[\n\x0d]/, $grepBuffer, -1); # Split the buffer into lines in an array; check \x0d as well for grep streaming files
			@grepbf = ();
			debugMsg(2,"[$g]GrepRegex:>", \$grep->{Regex}[$g], "<\n");
			debugMsg(2,"[$g]GrepMode:>", \$grep->{Mode}[$g], "<\n");
			my $nestedLevel = $nestedStartLevel;
			debugMsg(2,"[$g]Resuming-CfgContextLvl:>", \$nestedLevel, "<\n") if $g == 0;
			for my $i ( 0 .. $#buffer ) {
				my $line = $buffer[$i];
				debugMsg(2,"[$g]LINE:>", \$line, "<\n");
				$grep->{EmptyLineSupres}[$g] = $grep->{NoEmptyLineLast}[$g] = undef if $grep->{NoEmptyLineLast}[$g]; # Reset it
				if ($line eq '') { # Empty line processing done here
					if ( ($grep->{KeepBanner} && $grep->{Advanced}[$g] && !$grep->{ShowCommand}[$g]) || $grep->{Mode}[$g] eq '!' || $grep->{Mode}[$g] eq '^') { # Preserve empty lines
						push(@grepbf, $line);
						debugMsg(2,"[$g]PUSH-Empty:>", \$line, "<\n");
					}
					else {
						$grep->{EmptyLineSupres}[$g] = 1;
					}
					next;
				}
				else {
					$grep->{NoEmptyLineLast}[$g] = 1;
				}
				$grepDisable[$g] = 1 if $host_io->{ErrorDetect} && errorDetected($db, \$line);
				if ($grepDisable[$g]) { # Grep disabled, preserve all lines
					push(@grepbf, $line);
					next;
				}
				elsif ($grep->{Mode}[$g] eq '!nul') {
					# Empty lines already suppressed above
					push(@grepbf, $line);
					next;
				}
				elsif ($grep->{Mode}[$g] eq '^') {
					my $expLine = matchline($host_io, $grep, $line, $g);
					$line = $expLine if defined $expLine && $line !~ /$grep->{Regex}[$g]/;
					push(@grepbf, $line);
					next;
				}
				elsif ($grep->{Mode}[$g] eq '|' || $grep->{Mode}[$g] eq '!') {
					push(@grepbf, $line) if matchline($host_io, $grep, $line, $g);
					next;
				}
				# If we get here, $grep->{Advanced}[$g] is true
				#
				if ($line =~ /$Grep{SocketEchoBanner}/) { # Handle socket echo banners
					push(@grepbf, $line);
					debugMsg(2,"Grep-Socket-Echo-Banner detected; resetting all Grep Transient keys\n");
					resetGrepStructure($grep, 1);
					next;
				}
				# Stackable wide wrapped line processing
				if ($host_io->{Type} eq 'BaystackERS' && length($line) == $TermWidth) {
					# Maybe we need to unwrap this line
					debugMsg(2,"GrepUnwrap-Check\n");
					if ($i == $#buffer) { # Last line in buffer
						push(@grepbf, $line); # Keep it, will be pushed onto next buffer
						debugMsg(2,"GrepUnwrap-PassToNextCycle\n");
						next;
					}
					my $thisCmd = (split($Space, $line))[0];         #1st word of this line
					debugMsg(2,"GrepUnwrap-ThisCmd:>", \$thisCmd, "<\n");
					my $nextCmd = $buffer[$i+1] =~ /^\s/ ? '' : (split($Space, $buffer[$i+1]))[0]; #1st word of next line
					$nextCmd = '' unless defined $nextCmd;
					debugMsg(2,"GrepUnwrap-NextCmd:>", \$nextCmd, "<\n");
					if ( ($thisCmd ne $nextCmd) && $nextCmd !~ /$Grep{UnwrapAnchors}/) {
						# We unwrap!
						$buffer[$i+1] = $line . $buffer[$i+1];
						debugMsg(2,"GrepUnwrap-UNWRAPPING!\n");
						next;
					}
					# We don't unwrap
				}
				# ISW log wrapped line processing
				if ($host_io->{Type} eq 'ISW' && (length($line)-27)%52 == 0 && $line =~ /^ {27}[A-Z-]+:.+$/) {
					debugMsg(2,"ISW LogUnwrap-Check\n");
					if ($i == $#buffer) { # Last line in buffer
						push(@grepbf, $line); # Keep it, will be pushed onto next buffer
						debugMsg(2,"ISW LogUnwrap-PassToNextCycle\n");
						next;
					}
					if ($buffer[$i+1] =~ /^ {27}(.+)$/) {
						$buffer[$i+1] = $line . $1;
						debugMsg(2,"ISW LogUnwrap-UNWRAPPING!\n");
						next;
					}
				}
				if ($DeviceCfgParse{$host_io->{Type}}) {
					# Config and privExec processing
					if ($line =~ /$Grep{PrivExec}/i && !defined $grep->{ConfigSeen} && !defined $configSeen[$g]) {
						unless ($grep->{EnableSeen} || $enableSeen[$g]) {
							push(@grepbf, $line);
							$enableSeen[$g] = 1;
							debugMsg(2,"[$g]GrepConfigMode: enable\n");
						}
						next;
					}
					if ($line =~ /$Grep{EnterConfig}/ || $line =~ /$Grep{EnterConfigTerm}/) {
						unless ($grep->{ConfigSeen} || $configSeen[$g]) {
							push(@grepbf, $line);
							$configSeen[$g] = 1;
							debugMsg(2,"[$g]GrepConfigMode: config\n");
							$grep->{ConfigTermSeen} = 1 if $line =~ /$Grep{EnterConfigTerm}/;
							$grep->{ConfigACLI} = 1;
						}
						next;
					}
					if ($line =~ /$Grep{EndConfig}/i) {
						unless ($grep->{EndSeen} || $endSeen[$g]) {
							push(@grepbf, $line);
							$endSeen[$g] = 1;
							debugMsg(2,"[$g]GrepConfigMode: end\n");
						}
						next;
					}
					# Config context processing
					my $context;
					if (defined $Grep{ContextPatterns}{$host_io->{Type}}[$nestedLevel] && $line =~ /$Grep{ContextPatterns}{$host_io->{Type}}[$nestedLevel]/i) {
						if ($g == 0 && defined $grep->{CfgContextTyp}->[0] && $grep->{CfgContextTyp}->[0] eq (split(' ', $line))[0]) { # Same context type nesting
							debugMsg(2,"DetectedSameInstanceTypeNested: ", \$grep->{CfgContextTyp}->[0], "\n");
						}
						else {
							$context = 1; # New context level
						}
					}
					if (!$context && $g == 0 && $nestedLevel > 0 && $line =~ /$Grep{ContextPatterns}{$host_io->{Type}}[$nestedLevel - 1]/i) {
						if (defined $Grep{ContextPatternsExcept}{$host_io->{Type}} && $line =~ /$Grep{ContextPatternsExcept}{$host_io->{Type}}/i) {
							debugMsg(2,"IgnoringLowerLevelContextMatch\n");
						}
						else {
							$context = 2; # New context, but from level below current level => we saw no exit
						}
					}
					if ($context) {
						if ($g == 0) { # Only record config contexts for 1st grep instance
							$grep->{ConfigACLI} = 1; # In grep streaming mode, config snippet may not start with "config term'; if we see a context set it here
							if ($context == 2) { # There was no 'exit' from previous level.. we add an exit to correct it
								my $exit = 'exit';
								$exit = $grep->{Indent} . $exit for 1 .. ($grep->{CfgContextLvl} - 1);
								push(@grepbf, $exit);
								debugMsg(2,"PreviousConfigContextNotClosed-pushing:>exit<'\n");
								shift(@{$grep->{CfgContextTyp}});
								$line = $grep->{Indent} . $line for 1 .. ($grep->{CfgContextLvl} - 1);
							}
							else { # Normal case
								$line = $grep->{Indent} . $line for 1 .. $grep->{CfgContextLvl};
								$grep->{CfgContextLvl}++;
							}
							unshift(@{$grep->{CfgContextTyp}}, (split(' ', $line))[0]); # 1st word of line
							debugMsg(2,"GrepInstance:>", \$line, "< ; ");
							debugMsg(2,"type = ", \$grep->{CfgContextTyp}->[0], " ; ");
							debugMsg(2,"nestingConfigContextLevel = ", \$grep->{CfgContextLvl}, "\n");
							# Set InsertIndent to apply indentation within a config instance
							$grep->{InsertIndent} = 1 if $grep->{Indent};
							$nestedLevel = $grep->{CfgContextLvl};
						}
						else {
							$nestedLevel++;
							debugMsg(2,"NonBaseRegex-NestingLevel = ", \$nestedLevel, "\n");
						}
						# Set KeepInstanceCfg to preserving lines within a matched config instance
						if ($grep->{Instance}[$g] && $line =~ /$Grep{InstanceContext}{$grep->{Instance}[$g]}/i) {
							if (matchline($host_io, $grep, $line, $g)) {
								if ($grep->{Mode}[$g] eq '||') {
									$grep->{KeepInstanceCfg}[$g] = $nestedLevel;
									debugMsg(2,"[$g]GrepInstanceMatch:on>", \$line, "<\n");
									# Context instances which create the instance, like route-map, need keeping if matched
									#  even if no inner lines are contained within; so we add a %%keep%% line
									if ($line =~ /$Grep{CreateContext}/i) {
										debugMsg(2,"[$g]GrepCreationInstanceMatch-within:adding %%keep%% marker\n");
										$line .= "\n%%keep%%";
									}
								}
							}
							elsif ($grep->{Mode}[$g] eq '!!') { # Negate context
								$grep->{DelInstanceCfg}[$g] = $nestedLevel;
								debugMsg(2,"[$g]GrepNegateInstanceMatch:on>", \$line, "<\n");
								next;
							}
						}
						elsif ($line =~ /$Grep{CreateContext}/i && matchline($host_io, $grep, $line, $g)) {
							# Context instances which create the instance, like route-map, need keeping if matched
							# (in this case even if matched by a grep string not associated to an instance)
							#  even if no inner lines are contained within; so we add a %%keep%% line
							debugMsg(2,"[$g]GrepCreationInstanceMatch-outside:adding %%keep%% marker\n");
							$line .= "\n%%keep%%";
						}
						unless ($grep->{DelInstanceCfg}[$g]) {
							push(@grepbf, $line);
							debugMsg(2,"[$g]PUSH-Context:>", \$line, "<\n");
						}
						next;
					}
					if ($line =~ /$Grep{ExitInstance}/i) {
						if ($g == 0) { # Only record config contexts for 1st grep instance
							# Clear record of a config context
							$grep->{CfgContextLvl}--;
							if ($grep->{CfgContextLvl} < 0) { # Usually if we don't recognize a context...
								# ...then the exit makes us go negative; output will be screwed
								debugMsg(2,"RevertingConfigContextLevelNEGATIVE!! = ", \$grep->{CfgContextLvl}, "\n");
								# This can also happen when we hit 'back' (PPCLI) or 'end' (ACLI); so commenting below
								# $line = $DeviceComment{$host_io->{Type}} . $line;
								$grep->{CfgContextLvl} = 0;	# Reset level to 0 and debug
								next; # We don't push this exit
							}
							shift(@{$grep->{CfgContextTyp}});
							$line = $grep->{Indent} . $line for 1 .. $grep->{CfgContextLvl};
							debugMsg(2,"RevertingConfigContextLevel = ", \$grep->{CfgContextLvl}, " ; ");
							debugMsg(2,"type = ", \$grep->{CfgContextTyp}->[0], "\n");
							# Reset InsertIndent to apply indentation within a config instance
							$grep->{InsertIndent} = 0 if $grep->{InsertIndent} && $grep->{CfgContextLvl} == 0;
							$nestedLevel = $grep->{CfgContextLvl};
						}
						else {
							$nestedLevel-- if $nestedLevel > 0;
							debugMsg(2,"NonBaseRegex-RevertingNestingLevel = ", \$nestedLevel, "\n");
						}
						# Reset KeepInstanceCfg to preserving lines within a matched config instance
						if ($grep->{KeepInstanceCfg}[$g] && $nestedLevel < $grep->{KeepInstanceCfg}[$g]) {
							$grep->{KeepInstanceCfg}[$g] = 0;
							debugMsg(2,"[$g]GrepInstance:off>", \$line, "<\n");
						}
						if ($grep->{DelInstanceCfg}[$g]) {
							next unless $nestedLevel < $grep->{DelInstanceCfg}[$g]; 
							$grep->{DelInstanceCfg}[$g] = 0;
							debugMsg(2,"[$g]GrepNegateInstance:off>", \$line, "<\n");
							next;
						}
						push(@grepbf, $line);
						debugMsg(2,"[$g]PUSH-ExitContext:>", \$line, "<\n");
						next;
					}
				}
				# Summary check & update
				if (exists $Grep{SummaryPatterns}{$host_io->{Type}} && $line =~ /$Grep{SummaryPatterns}{$host_io->{Type}}/i) {
					# Summary lines are no longer updated in grep code but in handleBufferedOutput
					push(@grepbf, '') if $grep->{EmptyLineSupres}[$g]; # Restore empty line before it
					push(@grepbf, $line);
					debugMsg(2,"[$g]PUSH-Summary:>", \$line, "<\n");
					next;
				}
				# Banner processing
				unless (defined $grep->{IndentParents}[$g] && $grep->{IndentLevel}[$g] > 0) { # Skip banner processing once we started caching indentParents
					$grep->{BannerDetected}[$g] = 1 if !defined $grep->{BannerDetected}[$g] && $line !~ /$Grep{SocketEchoBannerExc}/; # Prime it set, first time in here
					if (exists $Grep{BannerHardPatterns}{$host_io->{Type}} && $line =~ /$Grep{BannerHardPatterns}{$host_io->{Type}}/) { # Hard banner processing
						if ( exists $Grep{ConfigUncomment}{$host_io->{Type}} && $line =~ /$Grep{ConfigUncomment}{$host_io->{Type}}/ ) {
							$line =~ s/^$DeviceComment{$host_io->{Type}}\s*//; # Uncomment
							debugMsg(2,"[$g]ConfigUncommentDetected:>", \$line, "<\n");
							push(@grepbf, $line);
						}
						else {
							$grep->{BannerDetected}[$g] = 1;
							debugMsg(2,"[$g]BannerHardDetected; Banner Flag: on\n");
							if ($grep->{KeepBanner}) {
								push(@grepbf, '') if $grep->{EmptyLineSupres}[$g]; # Restore empty line before it
								push(@grepbf, $line);
								debugMsg(2,"[$g]PUSH-BannerHard:>", \$line, "<\n");
							}
						}
						next;
					}
					elsif ($grep->{BannerDetected}[$g]) { # Soft banner processing
						if ( ( exists $Grep{BannerSoftPatterns}{$host_io->{Type}} && $line =~ /$Grep{BannerSoftPatterns}{$host_io->{Type}}/ )
						  && !( exists $Grep{BannerExceptions}{$host_io->{Type}} && $line =~ /$Grep{BannerExceptions}{$host_io->{Type}}/ ) ) {
							debugMsg(2,"[$g]BannerSoftDetected\n");
							push(@grepbf, $line) if $grep->{KeepBanner};
							$grep->{ShowCommand}[$g] = 1;
							debugMsg(2,"[$g]PUSH-BannerSoft:>", \$line, "<\n");
							next;
						}
						elsif (length $line) { # Unless a blank line
							$grep->{BannerDetected}[$g] = 0;
							debugMsg(2,"[$g]Clearing BannerFlag: off\n");
						}
					}
				}
				# Show command processing; to set ShowCommand for show commands with no banner (like show sys-info)
				if (exists $Grep{BannerLessShowCommand}{$host_io->{Type}} && $line =~ /$Grep{BannerLessShowCommand}{$host_io->{Type}}/) { # Banner-less show command
						$grep->{ShowCommand}[$g] = 1;
						debugMsg(2,"[$g]Banner-less show command detected\n");
				}
				# Indentation processing
				unless ($grep->{ConfigACLI}) {
					if ($g == 0 && exists $Grep{IndentAdd}{$host_io->{Type}}) {
						my $match;
						foreach my $pat (@{$Grep{IndentAdd}{$host_io->{Type}}}) {
							if ($line =~ /$pat->[0]/) {
								if ($pat->[1] > 0) {
									$grep->{IndentAdd} = $Space x $pat->[1];
									debugMsg(2,"[$g]IndentAdd on >", \$grep->{IndentAdd}, "<\n");
								}
								else {
									debugMsg(2,"[$g]IndentAdd off\n") if defined $grep->{IndentAdd};
									$grep->{IndentAdd} = undef;
								}
								$match = 1;
								last;
							}
						}
						if (!$match && defined $grep->{IndentAdd}) {
							$line = $grep->{IndentAdd} . $line;
							debugMsg(2,"[$g]IndentAdd:>", \$line, "<\n");
						}
					}
					$indentNewline = undef;
					$indentLevel = 0;
					unless (exists $Grep{IndentSkip}{$host_io->{Type}} && $line =~ /$Grep{IndentSkip}{$host_io->{Type}}/) {
						$indentLevel = length $1 if $line =~ /^( +)/;		# Number of leading spaces
						$indentLevel = (length $1) * 8 if $line =~ /^(\t+)/;	# Tabs count as 8 spaces
					}
					debugMsg(2,"[$g]IndentLevel = ", \$indentLevel, "\n");
					if (exists $Grep{IndentAdjust}{$host_io->{Type}}) {
						foreach my $pat (@{$Grep{IndentAdjust}{$host_io->{Type}}}) {
							if ($line =~ /$pat->[0]/) {
								$indentLevel += $pat->[1];
								debugMsg(2,"[$g]IndentLevel-Adjusted = ", \$indentLevel, "\n");
								$indentNewline = $pat->[2];
								last; # We don't want a line to match more patterns
							}
						}
					}
					if (exists $Grep{IndentExit}{$host_io->{Type}} && $line =~ /$Grep{IndentExit}{$host_io->{Type}}/) {
						$grep->{IndentExit}[$g] = 1;
						debugMsg(2,"[$g]IndentExit detected\n");
					}
					else {
						$grep->{IndentExit}[$g] = 0;
					}
					if ($grep->{KeepIndented}[$g] || $grep->{DelIndented}[$g]) {
						if ($indentLevel <= $grep->{IndentLevel}[$g]) {
							$grep->{IndentLevel}[$g] = undef;
							debugMsg(2,"[$g]GrepIndentKeepSubIndents:off\n") if $grep->{KeepIndented}[$g];
							debugMsg(2,"[$g]GrepIndentNegateSubIndents:off\n") if $grep->{DelIndented}[$g];
							$grep->{KeepIndented}[$g] = $grep->{DelIndented}[$g] = 0;
							if (defined $Grep{IndentExit}{$host_io->{Type}}) {
								$grep->{IndentExitLevel}[$g] = $indentLevel + 1;
							}
						}
						next if $grep->{DelIndented}[$g];
					}
				}
				# Record processing
				if ($grep->{KeepInstanceCfg}[$g] || $grep->{DelInstanceCfg}[$g]) {
					if ($grep->{KeepInstanceCfg}[$g]) {
						if ($g == 0 && $line !~ /^\s/ && $grep->{InsertIndent}) {
							$line = $grep->{Indent} . $line for 1 .. $grep->{CfgContextLvl};
						}
						push(@grepbf, $line);
						debugMsg(2,"[$g]PUSH-KeepInstance:>", \$line, "<\n");
					}
					deltaPatternCheck($db, $g, $line);
				}
				elsif (!$grep->{ConfigACLI} && $grep->{KeepIndented}[$g]) {
					push(@grepbf, $line);
					debugMsg(2,"[$g]PUSH-KeepIndented:>", \$line, "<\n");
				}
				elsif ( matchline($host_io, $grep, $line, $g) ) {
					if ($g == 0 && $line !~ /^\s/ && $grep->{InsertIndent}) {
						$line = $grep->{Indent} . $line for 1 .. $grep->{CfgContextLvl};
					}
					if (!$grep->{ConfigACLI} && $grep->{Mode}[$g] eq '||') {
						$grep->{IndentNestMatch}[$g] = $indentLevel;
						$grep->{IndentExitLevel}[$g] = undef;
						# Print out indentParents with an indent level < than current line $indentLevel
						if (defined $grep->{IndentParents}[$g] && @{$grep->{IndentParents}[$g]}) { # Only if indentParents exist
							while (my $parent = shift @{$grep->{IndentParents}[$g]}) { # Here we empty indentParents array
								if ($parent->[0] < $indentLevel) { # Here we only keep parents with smaller indentation
									push(@grepbf, '') if $parent->[2]; # Insert empty line
									push(@grepbf, $parent->[1]);
									debugMsg(2,"[$g]GrepIndent-SubmitParentLine>", \$parent->[1], "<\n");
								}
							}
						}
						else {
							foreach my $pat (@{$Grep{IndentAdjust}{$host_io->{Type}}}) {
								if ($line =~ /$pat->[0]/ && $pat->[2]) {
									debugMsg(2,"[$g]GrepIndent-InsertEmptyLine\n");
									push(@grepbf, '');
									last;
								}
							}
						}
						$grep->{IndentLevel}[$g] = $indentLevel;
						$grep->{KeepIndented}[$g] = 1;
						debugMsg(2,"[$g]GrepIndentKeepSubIndents:on / MATCH IndentLevel =", \$indentLevel, "\n");
					}
					deltaPatternCheck($db, $g, $line);
					push(@grepbf, $line);
					debugMsg(2,"[$g]PUSH-Matchline:>", \$line, "<\n");
				}
				elsif (!$grep->{ConfigACLI} && $grep->{Mode}[$g] eq '!!') {
					$grep->{DelIndented}[$g] = 1;
					$grep->{IndentLevel}[$g] = $indentLevel;
					debugMsg(2,"[$g]GrepIndentNegateSubIndents:on / MATCH IndentLevel =", \$indentLevel, "<\n");
				}
				elsif (!$grep->{ConfigACLI}) { # Update indentation structure upon no match
					if ( $grep->{IndentExit}[$g] && ( # If the line is an exit
						(defined $grep->{IndentNestMatch}[$g] && $indentLevel == $grep->{IndentNestMatch}[$g]) || # We come in here 1st on this match
						(defined $grep->{IndentExitLevel}[$g] && $indentLevel < $grep->{IndentExitLevel}[$g])     # And then we come back on this match as many times as needed
					    ) ) {
					  	$grep->{IndentNestMatch}[$g] = undef;		# Make sure we invalidate 1st condition above
						$grep->{IndentExitLevel}[$g] = $indentLevel;	# Arm the second condition above to match all subsequent exits
						push(@grepbf, $line);
						debugMsg(2,"[$g]Preserve IndentExit : ", \$line, "\n");
					}
					elsif (!defined $grep->{IndentLevel}[$g]) {
						$grep->{IndentLevel}[$g] = $indentLevel;
						push(@{$grep->{IndentParents}[$g]}, [$indentLevel, $line, $indentNewline]);
						debugMsg(2,"[$g]Indent First Parent : ", \$line, "\n");
					}
					elsif ($indentLevel == $grep->{IndentLevel}[$g]) {
						pop @{$grep->{IndentParents}[$g]};
						push(@{$grep->{IndentParents}[$g]}, [$indentLevel, $line, $indentNewline]);
						debugMsg(2,"[$g]Indent Same level Parent replaced with : ", \$line, "\n");
					}
					elsif ($indentLevel > $grep->{IndentLevel}[$g]) {
						$grep->{IndentLevel}[$g] = $indentLevel;
						push(@{$grep->{IndentParents}[$g]}, [$indentLevel, $line, $indentNewline]);
						debugMsg(2,"[$g]Indent New child : ", \$line, "\n");
					}
					elsif ($indentLevel < $grep->{IndentLevel}[$g]) {
						my $parentList = $grep->{IndentParents}[$g];
						pop @$parentList while @$parentList && $parentList->[$#{$parentList}]->[0] >= $indentLevel;
						$grep->{IndentLevel}[$g] = $indentLevel;
						push(@{$grep->{IndentParents}[$g]}, [$indentLevel, $line, $indentNewline]);
						debugMsg(2,"[$g]Indent Backtracked Parent : ", \$line, "\n");
					}
					debugMsg(2,"[$g]Indent Parent Array size : ", \scalar @{$grep->{IndentParents}[$g]}, "\n");
				}
			} # for my $i ( 0 .. $#buffer )
			$grepBuffer = join("\n", @grepbf); # Reconstruct the buffer
			$grepBuffer .= "\n" if @grepbf;
			debugMsg(2,"[$g]AfterGrepInitialParse:\n>", \$grepBuffer, "<\n");
			#
			# Grep removing empty contexts in a show running-config output
			#
			if ($DeviceCfgParse{$host_io->{Type}} && length $grepBuffer && $grep->{Advanced}[$g]) {
				foreach my $pattern (@{$Grep{EmptyContexts}{$host_io->{Type}}}) {
					$grepBuffer =~ s/$pattern//mig;
				}
				debugMsg(2,"[$g]AfterRemovingEmptyContexts:\n>", \$grepBuffer, "<\n");
				# Remove any %%keep%% markers used to prevent above step from wiping away creation contexts e.g. route-map
				if ($grepBuffer =~ s/%%keep%%\n//mig) {
					debugMsg(2,"[$g]AfterRemoving%%keep%%Markers:\n>", \$grepBuffer, "<\n");
				}
				if (length $grep->{GrepStreamFile}) { # Grep Streaming + multiple files
					$grepBuffer =~ s/^conf(?:ig?)? term(?:i(?:n(?:al?)?)?)?\n\n?end\n//mig;
					debugMsg(2,"[$g]GrepStreaming-AfterRemovingEmptyConfigTerm:\n>", \$grepBuffer, "<\n");
				}
			}
		} # if ($grep->{MultiLine}[$g] == 0)
		last GREPPAT unless length $grepBuffer;
	} # for my $g ( 0 .. $#{$grep->{Regex}} )

	# If an error was found in the output disable whole grep function (this function will not be called for subsequent output)
	$grep->{String} = 0 if $grepDisable[0];

	# If enable or config were seen, set this after all grep strings processed on available buffer
	$grep->{EnableSeen} = 1 if $enableSeen[0];
	$grep->{ConfigSeen} = 1 if $configSeen[0];
	$grep->{EndSeen}    = 1 if $endSeen[0];

	#
	# Multiline last record processing
	#
	if (defined $lastRecord) {
		if (checkForPrompt($host_io, \$lastRecord, $prompt) || !$grep->{String}) { # If grep finished, re-append lastRecord
			$grep->{String} = 0;
			$grepBuffer .= $lastRecord;
		}
		else { # Grep ongoing, push last multiline onto grep cache, to be re-processed at next cycle
			$host_io->{GrepCache} = $lastRecord;
			debugMsg(2,"GrepMultiLinePushingOntoGrepCache:\n>", \$lastRecord, "<\n");
		}
	}

	#
	# Grep single line last line processing
	#
	if (defined $lastLine) { # Applies even if lastLine == ''
		if ($grep->{String} && $grepBuffer =~ /\n/ && $grepBuffer !~ /\n\n$/ && !checkForPrompt($host_io, \$lastLine, $prompt)) {
			# If we are not done with advanced grep, push last line onto grep cache...
			STRIPTOCACHE: while ($grepBuffer =~ s/(.*)\n$//) { # Remove last line (but does not work if line ends in /n/n; hence condition above)
				my $lastBufferLine = $1;
				debugMsg(2,"LastBufferLineRemovedToCheck:\n>", \$lastBufferLine, "<\n");
				if ($DeviceCfgParse{$host_io->{Type}} && $grep->{CfgContextLvl} > 0 && $lastBufferLine =~ /$Grep{ContextPatterns}{$host_io->{Type}}[$grep->{CfgContextLvl}-1]/i) { # if a context line
					$grep->{CfgContextLvl}--;
					shift(@{$grep->{CfgContextTyp}});
					$host_io->{GrepCache} = "$lastBufferLine\n" . $host_io->{GrepCache};
					debugMsg(2,"GrepLastBufferLinePushingOntoGrepCache-reasonConfigContext:\n>", \$host_io->{GrepCache}, "<\n");
					debugMsg(2,"LastBufferLine-RevertingConfigContextLevel = ", \$grep->{CfgContextLvl}, " ; ");
				}
				elsif ($host_io->{Type} eq 'BaystackERS' && length($lastBufferLine) == $TermWidth) {# or a long line
					$host_io->{GrepCache} = "$lastBufferLine\n" . $host_io->{GrepCache};
					debugMsg(2,"GrepLastBufferLinePushingOntoGrepCache-reasonBaystackLongLine:\n>", \$host_io->{GrepCache}, "<\n");
				}
				elsif ($host_io->{Type} eq 'ISW' && $lastBufferLine =~ /^ {27}[A-Z-]+:.+$/) {# or a long line
					$host_io->{GrepCache} = "$lastBufferLine\n" . $host_io->{GrepCache};
					debugMsg(2,"GrepLastBufferLinePushingOntoGrepCache-reasonISWLongLogLine:\n>", \$host_io->{GrepCache}, "<\n");
				}
				else { # else don't; slap it back on and come out
					$grepBuffer .= "$lastBufferLine\n";
					debugMsg(2,"AfterReAppendingLastBufferLine:\n>", \$grepBuffer, "<\n");
					last STRIPTOCACHE;
				}
			}
		}
		if (!$grep->{String} || checkForPrompt($host_io, \$lastLine, $prompt) || $grep->{CompleteOutput}) { # If grep finished, re-append lastRecord
			$grep->{String} = 0;
			$grepBuffer .= "end\n" if $grep->{ConfigTermSeen} && !$grep->{EndSeen}
						  && scalar @{$grep->{Advanced}} == scalar grep($_,  @{$grep->{Advanced}});#All advanced greps
			$grepBuffer .= "\n" if $grep->{EmptyLineSupres}[0];
			$grepBuffer .= $lastLine;
		}
		elsif (length $lastLine) { # Grep ongoing & we have a lastline, push it also onto grep cache, to be re-processed at next cycle
			$host_io->{GrepCache} .= $lastLine;
			debugMsg(2,"GrepLastIncompleteLinePushingOntoGrepCache:\n>", \$lastLine, "<\n");
		}
	}

	#
	# Grep Streaming handling
	#
	if (length $grep->{GrepStreamFile} && length $grepBuffer) { # Grep Streaming + multiple files & we have some output left
		$grepBuffer = join('', "\n\n", $grep->{GrepStreamFile}, ":\n". "=" x (length($grep->{GrepStreamFile})+1) . "\n", $grepBuffer);
		debugMsg(2,"GrepStreaming-AfterAddingFilename:\n>", \$grepBuffer, "<\n");
	}

	#
	# Append to Grep Buffer
	#
	$host_io->{GrepBuffer} .= $grepBuffer;
	$host_io->{DeltaBuffer} = $grepBuffer if $socket_io->{EchoSendFlag};
}


sub keepLastXLines { # Keeps at most the last X lines from provided buffer
	my ($host_io, $bufRef, $xMax) = @_;
	my ($tailCount, $tailBuffer);

	debugMsg(2,"keepLastXLines-StartBuf: \n>", $bufRef, "<\n");
	$tailBuffer = stripLastLine($bufRef);
	while ($$bufRef =~ s/(.*\n)$//) {
		$tailBuffer = $1 . $tailBuffer;
		last if ++$tailCount > $xMax;
	}
	$$bufRef = $tailBuffer;
	debugMsg(2,"keepLastXLines-endBuf:\n>", $bufRef, "<\n");
}


sub pruneBuffer { # In handleBufferedOutput 'mp' & 'qp' modes will prune the outbut buffer to include final prompt and any summary lines
	my ($host_io, $bufRef) = @_;
	my ($tailCount, $tailBuffer);

	debugMsg(2,"=pruneBuffer-StartBuf: \n>", $bufRef, "<\n");
	$tailBuffer = stripLastLine($bufRef);	# Get the prompt 1st
	if (exists $Grep{SummaryPatterns}{$host_io->{Type}}) {
		while ($$bufRef =~ s/(.*\n)$//) { # Then look at complete lines above it 
			my $line = $1;
			next if $line =~ /^\n+$/; # Skip empty lines
			debugMsg(2,"pruneBuffer-LINE: >", \$line, "<\n");
			if ($line =~ /$Grep{SummaryPatterns}{$host_io->{Type}}/i) {
				$tailBuffer = $line . $tailBuffer;	# A summary line; preserve it
				last;
			}
			last if ++$tailCount > $SummaryTailLinesLimit;
		}
	}
	debugMsg(2,"=pruneBuffer-EndBuf:\n>", \$tailBuffer, "<\n");
	return $tailBuffer;
}


sub handleBufferedOutput { # Handles how ACLI releases to screen buffered output from device
	my $db = shift;
	my $mode = $db->[0];
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $socket_io = $db->[6];
	my $prompt = $db->[7];
	my $termbuf = $db->[8];
	my $history = $db->[9];
	my $grep = $db->[10];
	my $vars = $db->[12];
	# With large amount of output we would stop reading keyboard; so time-limit this sub
	my $mainLoopTime = Time::HiRes::time + $MainloopTimer;

	return if $mode->{buf_out} eq 'ds';

	grepOutput($db) if $grep->{String} && length $host_io->{OutBuffer};

	socketEchoBuffer($db, $socket_io, $prompt) if $socket_io->{ListenEchoMode} && length $host_io->{DeltaBuffer};

	if ($mode->{buf_out} eq 'se') { # ----------------> Socket Echo Output Pause mode (se) <--------------
		return unless $term_io->{Key};
		return unless 	$term_io->{Key} =~ /^[qQ]$/	||
				$term_io->{Key} eq $Space	||
				$term_io->{Key} eq $Return;
		print $DeleteEchoPrompt;
		if ($term_io->{Key} =~ /^[qQ]$/) {
			wipeEchoBuffers($socket_io);
		}
		elsif ($term_io->{Key} eq $Return) {
			$host_io->{OutBuffer} = join('', $socket_io->{TieEchoBuffers}->{$socket_io->{TieEchoPartial}},
							 "\n\n<... missing output ...>\n\n", $host_io->{OutBuffer});
			delete($socket_io->{TieEchoBuffers}->{$socket_io->{TieEchoPartial}});
			delete($socket_io->{TieEchoSeqNumb}->{$socket_io->{TieEchoPartial}});
			$socket_io->{TieEchoPartial} = undef;
		}
		changeMode($mode, {term_in => $mode->{term_in_cache}, buf_out => 'eb'}, '#107');
		($term_io->{DelayCharProcPs}, $term_io->{DelayCharProcDF}) = (Time::HiRes::time + $DelayCharProcPs, 1);
	}
	elsif ($mode->{buf_out} eq 'mp') { # ----------------> More Pause mode (mp) <--------------
		return unless 	$term_io->{Key};
		return unless 	$term_io->{Key} =~ /^[qQ]/	|| # includes 'qs'
				$term_io->{Key} eq $Space	||
				$term_io->{Key} eq $Return	||
				$term_io->{Key} eq $term_io->{CtrlMoreChr};

		print $term_io->{DeleteMorePrompt};
		$term_io->{PageLineCount} = $term_io->{Key} eq $Return ? 1 : $term_io->{MorePageLines}; # Set it to 1 in case of Return key; in all other cases reset it
		if ($term_io->{Key} =~ /^[qQ]/) { # includes 'qs'
			my $gotPrompt;
			foreach my $bufRef (\$host_io->{GrepBuffer}, \$host_io->{OutBuffer}) {
				next unless length $$bufRef;
				if ( checkForPrompt($host_io, $bufRef, $prompt) ) { # Prompt in one of the buffers ?
					$host_io->{OutBuffer} = pruneBuffer($host_io, $bufRef);
					$gotPrompt = 1;
					last;
				}
			}
			$grep->{String} = 0; # Disable the grep functionality
			$host_io->{GrepBuffer} = $host_io->{GrepCache} = ''; # Wipe these buffer in all cases
			saveInputBuffer($term_io); # Stop sourcing if we quit output
			$term_io->{SourceNoHist} = 0;
			$term_io->{SourceNoAlias} = 0;
			wipeEchoBuffers($socket_io) if $socket_io->{Tie} && $socket_io->{TieEchoMode} && %{$socket_io->{TieEchoBuffers}};
			unless ($gotPrompt) {
				keepLastXLines($host_io, \$host_io->{OutBuffer}, $SummaryTailLinesLimit);
				$term_io->{BufMoreAction} = 'q';
				changeMode($mode, {term_in => 'sh', buf_out => 'qp'}, '#9');
				return;
			}
			if (defined $socket_io->{ListenEchoMode} && $term_io->{Key} eq 'qs') {	# Needed if command was received from listening socket...
				releaseInputBuffer($term_io);		# ... but this term was stuck in more prompt
			}
		}
		# Space, Return, CtrlMoreChr, or Q(with prompt already received)
		changeMode($mode, {term_in => $mode->{term_in_cache}, buf_out => 'eb'}, '#7');
		($term_io->{DelayCharProcPs}, $term_io->{DelayCharProcDF}) = (Time::HiRes::time + $DelayCharProcPs, 1);
	}
	elsif ($mode->{buf_out} eq 'qp') { # ---------------> Quit More Pause mode (qp) <----------
		if ($host_io->{DeviceReadFlag}) {
			if ( checkForPrompt($host_io, \$host_io->{OutBuffer}, $prompt) ) {
				$host_io->{OutBuffer} = pruneBuffer($host_io, \$host_io->{OutBuffer});
				changeMode($mode, {buf_out => 'eb'}, '#10');
				if (defined $socket_io->{ListenEchoMode}) {	# Needed if command was received from listening socket...
					releaseInputBuffer($term_io);		# ... but this term was stuck in more prompt
				}
			}
			else { # No prompt; purge the buffer to max performance on large dumps
				keepLastXLines($host_io, \$host_io->{OutBuffer}, $SummaryTailLinesLimit);
			}
		}
	}
	elsif ($mode->{buf_out} eq 'eb') { # ---------------> Empty Buffer mode (eb) <-------------
		return unless length $host_io->{OutBuffer} || length $host_io->{GrepBuffer};
		if (defined $socket_io->{PauseBuffLen}) { # If we are pausing last fragment, because of socket echo output
			return if length $host_io->{OutBuffer} <= $socket_io->{PauseBuffLen};
			$socket_io->{PauseBuffLen} = undef; # undef otherwise
		}
		#
		# Now print it out
		#
		BUFFER: foreach my $bufRef (\$host_io->{GrepBuffer}, \$host_io->{OutBuffer}) {
			next BUFFER unless length $$bufRef;
			debugMsg(2,"BufferToProcess:\n>", $bufRef, "<\n") unless defined $term_io->{DelayPrompt} && !$term_io->{DelayPromptDF};
			if ($$bufRef =~ /^((?:.*(?:\n|$)){1,7})/) {
				my $bufHead = $host_io->{FragmentCache} . $1;	# Fragment cache + 1st 7 lines of output (increased from 4 since new timestamp on VSP show commands)
				debugMsg(2,"Buffer Head to check for errors:\n>", \$bufHead, "<\n");
				if ( errorDetected($db, \$bufHead, 1) ) {
					if (length $host_io->{CommandCache}) {
						printOut($script_io, "\n" . $host_io->{CommandCache});
						debugMsg(4,"=flushing CommandCache - error detected:\n>", \$host_io->{CommandCache}, "<\n");
						$host_io->{CommandCache} = '';	# Ensure we don't do this twice
						debugMsg(2,"Releasing Error, FragmentCache was: >", \$host_io->{FragmentCache}, "<\n");
						if (length $host_io->{FragmentCache} && $host_io->{FragmentCache} !~ /^\s*^?$/) { # If so..
							# the line was queued and echo-output supressed at previous cycle
							debugMsg(2,"Releasing LastCmdErrorRaw >", \$host_io->{LastCmdErrorRaw}, "<\n");
							printOut($script_io, $host_io->{LastCmdErrorRaw});
						}
					}
					stopSourcing($db);
					debugMsg(2,"DetectedSyntaxErrorInOutputStream!!!\n");
					if ($script_io->{CmdLogFile}) { # If CmdLogging active shut it down
						if (defined $script_io->{CmdLogFH}) { # If filehandle was setup destroy it
							close $script_io->{CmdLogFH};
							undef $script_io->{CmdLogFH};
							printOut($script_io, "error\n") if $script_io->{CmdLogOnly};
						}
						$script_io->{CmdLogFile} = $script_io->{CmdLogOnly} = $script_io->{CmdLogFlag} = undef;
					}
					if (@{$term_io->{VarCapture}}) { # If variable capture, shut it down
						$term_io->{VarCapture} = [];
						$term_io->{VarCaptureVals} = {};
					}
					if (defined $term_io->{CacheInputCmd}) { # Don't cache any inputs if we got an error..
						$term_io->{CacheInputCmd} = $term_io->{CacheInputKey} = $term_io->{CacheFeedInputs} = undef;
					}
					if (@{$history->{DeviceSentNoErr}}) {
						my $erroredCmd = pop(@{$history->{DeviceSentNoErr}});
						debugMsg(2,"Popping command from no-error history: ", \$erroredCmd, "\n");
					}
				}
			}
			BUFFERLOOP: while ($$bufRef =~ s/^(.*\n|.+\n?)//) { # For every line in buffer
				my ($bohLine, $fragmentCache, $logLine, $noEmptyLineSuppress) = ($1, '', '', $term_io->{CompletLineMrkr});
				#debugMsg(2,"bohLine = >", \$bohLine, "<\n");
				$fragmentCache = $host_io->{FragmentCache}; # Cache this as it might get cleared in checkFragPrompt and we need it below
				$term_io->{CompletLineMrkr} = ($bohLine =~ s/$CompleteLineMarker$//);
				# Only if OutBuffer is empty (so we don't even check if emptying GrepBuffer)...
				if ( length $host_io->{OutBuffer} == 0 ) {
					if ( checkFragPrompt($db, \$bohLine) ) {
						# Last line is a prompt
						if (defined $script_io->{CmdLogFH}) {
							close $script_io->{CmdLogFH};
							$script_io->{CmdLogFH} = $script_io->{CmdLogFile} = $script_io->{CmdLogFlag} = undef;
							printOut($script_io, "done\n") if $script_io->{CmdLogOnly};
							printOut($script_io, "$ScriptName: Output saved to:\n$script_io->{CmdLogFullPath}\n\n");
							$script_io->{CmdLogOnly} = undef;
						}
						if ($script_io->{CmdLogFile}) { # Happens in psuedo mode; a command with no output (bug21)
							$script_io->{CmdLogFH} = $script_io->{CmdLogFile} = $script_io->{CmdLogOnly} = $script_io->{CmdLogFlag} = undef;
						}
						if ($socket_io->{Tie} && $socket_io->{TieEchoMode} && $socket_io->{TiedSentFlag}) { # Socket echo mode output processing
							unless (defined $term_io->{DelayPrompt}) {
								my $timer = $SocketDelayPrompt{$socket_io->{TieEchoMode}};
								$timer += $socket_io->{TimerOverride} if defined $socket_io->{TimerOverride}; # Override actually now adds to default timer
								($term_io->{DelayPrompt}, $term_io->{DelayPromptDF}) = (Time::HiRes::time + $timer, 1);
								$socket_io->{TimerOverride} = undef;
								debugMsg(4,"=Set Socket DelayPrompt timer = $timer / expiry time = ", \$term_io->{DelayPrompt}, "\n");
							}
							if (%{$socket_io->{TieEchoBuffers}}) { # If output in buffers..
								my $outputRecovered;
								if (defined $socket_io->{TieEchoPartial}) { # A partially emptied buffer exists
									if ($socket_io->{TieEchoSeqNumb}->{$socket_io->{TieEchoPartial}} == 0) {
										# Partially emptied buffer, is now complete
										$host_io->{OutBuffer} .= $socket_io->{TieEchoBuffers}->{$socket_io->{TieEchoPartial}};
										delete($socket_io->{TieEchoBuffers}->{$socket_io->{TieEchoPartial}});
										delete($socket_io->{TieEchoSeqNumb}->{$socket_io->{TieEchoPartial}});
										$outputRecovered = 1;
										$socket_io->{EchoOutCounter}++ if $socket_io->{SummaryCount};
										$socket_io->{TieEchoPartial} = undef;
										debugMsg(2,"SocketEchoPartialOutputNowComplete\n");
									}
								}
								else { # Look for a complete buffer only if we don't have a partially emptied buffer
									foreach my $echoBuffer (keys %{$socket_io->{TieEchoBuffers}}) {
										if ($socket_io->{TieEchoSeqNumb}->{$echoBuffer} == 0) { # A complete buffer
											$host_io->{OutBuffer} .= $socket_io->{TieEchoBuffers}->{$echoBuffer};
											delete($socket_io->{TieEchoBuffers}->{$echoBuffer});
											delete($socket_io->{TieEchoSeqNumb}->{$echoBuffer});
											$outputRecovered = 1;
											$socket_io->{EchoOutCounter}++ if $socket_io->{SummaryCount};
										}
										debugMsg(2,"SocketEchoCompleteOutputRecovered - $echoBuffer:\n>", \$host_io->{OutBuffer}, "<\n") if $outputRecovered;
									}
								}
								if ($outputRecovered) { # We got some output from above
									$host_io->{OutBuffer} .= $bohLine; # Re-add prompt to it..
									if ($socket_io->{GrepRecycle}){ # Allow output to be processed at next cycle (if it is to be grep-able)
										$grep->{String} = 1 if $grep->{Mode}; # Re-activate grep, if it was set
										return;
									}
									redo BUFFER; # Or else, display it right now
								}
								else { # We have incomplete buffers only
									if ($term_io->{DelayPrompt}) {
										if (Time::HiRes::time < $term_io->{DelayPrompt}) { # ... we wait if no complete socket buffers
											debugMsg(4,"Socket Echo Incomplete Buffers - Delay prompt not expired; time = ", \Time::HiRes::time, " < $term_io->{DelayPrompt}\n") if defined $term_io->{DelayPromptDF};
											$term_io->{DelayPromptDF} = undef;
											$host_io->{OutBuffer} .= $bohLine;	# Re-add prompt to buffer..
											return;					# and come out
										}
										else {
											debugMsg(4,"Socket Echo Incomplete Buffers - Delay prompt EXPIRED! time = ", \Time::HiRes::time, " > $term_io->{DelayPrompt}\n");
											$term_io->{DelayPrompt} = 0;
										}
									}
									# Take 1st buffer unless already set in previous iteration and empty what data it already has
									$socket_io->{TieEchoPartial} = (keys %{$socket_io->{TieEchoBuffers}})[0] unless defined $socket_io->{TieEchoPartial};
									my $lastLine = stripLastLine(\$socket_io->{TieEchoBuffers}->{$socket_io->{TieEchoPartial}}) || ''; # Strip last line if any..
									if (length $socket_io->{TieEchoBuffers}->{$socket_io->{TieEchoPartial}}) { # Buffer has data
										$host_io->{OutBuffer} .= $socket_io->{TieEchoBuffers}->{$socket_io->{TieEchoPartial}};
										$host_io->{OutBuffer} .= $bohLine; # Re-add prompt to it..
										$socket_io->{TieEchoBuffers}->{$socket_io->{TieEchoPartial}} = $lastLine;
										debugMsg(2,"SocketEchoINCOMPLETEOutputRecovered\n>", \$host_io->{OutBuffer}, "<\n");
										if ($socket_io->{GrepRecycle}){ # Allow output to be processed at next cycle (if it is to be grep-able)
											$grep->{String} = 1 if $grep->{Mode}; # Re-activate grep, if it was set
											return;
										}
										redo BUFFER; # Display it now
									}
									else { # There is no data in it... so we have to make a choice..
										print $EchoMorePrompt;
										$mode->{term_in_cache} = $mode->{term_in};
										changeMode($mode, {term_in => 'rk', buf_out => 'se'}, '#106');
										$socket_io->{TieEchoBuffers}->{$socket_io->{TieEchoPartial}} = $lastLine;
										$host_io->{OutBuffer} .= $bohLine; # Re-add prompt to it..
										return;
									}
								}
							}
							if ($socket_io->{SocketWait} || inputBufferIsVoid($db)) {
								# This checks whether inbutBuffers are truly empty (including if still set but holding \x00 markers)
								# We want to do this if we need to use the output from tied terminals for this current command
								# Which is the case of @socket ping/send and also if the echo mode is all
								# But if the echo mode is error, then we can go faster and fetch errors on next command, if input buffer is not empty
								if (Time::HiRes::time < $term_io->{DelayPrompt}) { # ... we wait if nothing in socket buffers
									debugMsg(4,"Socket Echo - Delay prompt not expired; time = ", \Time::HiRes::time, " < $term_io->{DelayPrompt}\n") if $term_io->{DelayPromptDF};
									$term_io->{DelayPromptDF} = 0;
									$host_io->{OutBuffer} .= $bohLine;	# Re-add prompt to buffer..
									return;					# and come out
								}
								elsif ($term_io->{DelayPrompt}) {
									debugMsg(4,"Socket Echo - Delay prompt EXPIRED! time = ", \Time::HiRes::time, " > $term_io->{DelayPrompt}\n");
									$term_io->{DelayPrompt} = 0;
								}
							}
							elsif ($term_io->{DelayPrompt}) { # if inputBuffers still present and not SocketWait
								debugMsg(4,"Socket Echo - Skipping Delay prompt - presence of inputBuffers\n");
								$term_io->{DelayPrompt} = 0;
							}
							# If we get here, we are done with processing output (if any) from tied sockets
							$socket_io->{SocketWait} = undef;
							if ($socket_io->{SummaryCount} && $socket_io->{EchoOutCounter}) {
								$host_io->{OutBuffer} .= join('', "Echo received from ", $socket_io->{EchoOutCounter}, " terminals\n");
								$host_io->{OutBuffer} .= $bohLine; # Re-add prompt to it..
								$socket_io->{SummaryCount} = 0; # Ensure we don't come back here for this command
								if ($socket_io->{GrepRecycle}){ # Allow output to be processed at next cycle (if it is to be grep-able)
									$grep->{String} = 1 if $grep->{Mode}; # Re-activate grep, if it was set
									return;
								}
								redo BUFFER; # Display it now
							}
							if ($socket_io->{UntieOnDone}) { # We need to close the one-off socket
								if ($socket_io->{CachedTieName}) { # We need to restore a cached socket which was tied before
									untieSocket($socket_io, 1);
									debugMsg(4,"Socket restoring cached socket: ", \$socket_io->{CachedTieName}, "\n");
									tieSocket($socket_io, $socket_io->{CachedTieName}, 1);
									$socket_io->{CachedTieName} = undef;
								}
								else {
									untieSocket($socket_io);
								}
								$socket_io->{UntieOnDone} = undef;
							}
							if ($socket_io->{ResetEchoMode}) { # Ping might need to reset this
								$socket_io->{TieEchoMode} = 0;
								debugMsg(4,"Socket restoring echo mode none after ping\n");
								tieSocketEcho($socket_io); # Reset the Echo mode RX socket
								$socket_io->{ResetEchoMode} = undef;
							}
						}
						$socket_io->{TiedSentFlag} = undef; # Clear it once prompt received
						if ($term_io->{Mode} eq 'interact') {
							if ($host_io->{SyncMorePaging}) {
								$host_io->{CLI}->device_more_paging(
										Enable		=> $term_io->{MorePaging},
										Blocking	=> 1,
								);
								return if $host_io->{ConnectionError};
								$host_io->{SyncMorePaging} = 0;
							}
							$bohLine =~ s/ *$/$term_io->{LtPromptSuffix}/ if $term_io->{LtPrompt};
							($term_io->{DelayCharProcTm}, $term_io->{DelayCharProcDF}) = (Time::HiRes::time + $DelayCharProcTm, 1);
							debugMsg(4,"=Set DelayCharProcTm expiry time = ", \$term_io->{DelayCharProcTm}, "\n");
							changeMode($mode, {term_in => 'tm', dev_fct => 'ds', dev_out => 'ub', buf_out => 'ds'}, '#8');
							if ($term_io->{PseudoTerm} && length $host_io->{PacedSentChars}) {
								$termbuf->{Linebuf1} .= $host_io->{PacedSentChars}; # Add to buffer
								($termbuf->{Bufback1} = $termbuf->{Linebuf1}) =~ s/./\cH/g;
								debugMsg(2,"Pseudo Paced Sent Chars - added to input buffer: >", \$host_io->{PacedSentChars}, "<\n");
								$host_io->{PacedSentChars} = '';
							}
						}
						else { 	changeMode($mode, {dev_out => 'ub', buf_out => 'ds'}, '#16') }
						if (defined $term_io->{CacheFeedInputs} && @{$term_io->{CacheFeedInputs}}) { # Complete FeedInput caching
							cacheFeedInputs($db, $term_io->{CacheInputCmd}, $term_io->{CacheInputKey}, $term_io->{CacheFeedInputs});
							$term_io->{CacheInputCmd} = $term_io->{CacheInputKey} = $term_io->{CacheFeedInputs} = undef;
						}
						if (@{$term_io->{VarCapture}}) { # Complete variable capture
							if ($term_io->{VarCaptureFlag}) { # If we captured something...
								variablesCaptureValues($db);
							}
							$term_io->{VarCapture} = [];
							$term_io->{VarCaptureVals} = {};
						}
						if (defined $socket_io->{ListenEchoMode} && defined $socket_io->{ListenErrMsg}) { # If a socket error
							printOut($script_io, $socket_io->{ListenErrMsg});
						}
#						unless ($term_io->{InputBuffQueue}->[0]) { # We are probably not falling in here anymore at end of sourcing buffer
#							# but we end here at every non sourced command .... looks like we can get rid of this..
#							$host_io->{CommandCache} = '';
#							debugMsg(4,"=clearing CommandCache - empty buffer\n");
#						}
						if ($term_io->{EchoOff} && $term_io->{Sourcing}) {
							$host_io->{CommandCache} = $script_io->{PrintFlag} ? $bohLine : '';
							debugMsg(4,"=setting CommandCache to:\n>",\$host_io->{CommandCache}, "<\n");
						}
						else {
							printOut($script_io, $bohLine) unless $term_io->{InputBuffQueue}->[0] eq 'RepeatCmd' && !$host_io->{SyntaxError};
						}
						print $termbuf->{Linebuf1} if $term_io->{Mode} eq 'interact'; # For $mode->{dev_fct} eq 'sx' and for PacedSentChars
						if (!$term_io->{CmdOutputLines} || inputBufferIsVoid($db) || $term_io->{InputBuffQueue}->[0] eq 'RepeatCmd') {
							# We reset more counter if this command generated no output, or we are not sourcing, or we are sourcing but it is RepeatCmd
							$term_io->{PageLineCount} = $term_io->{MorePageLines};
						}
						$term_io->{YnPrompt} = '';
						$term_io->{YnPromptForce} = 0;
						return;
					}
					elsif ( ( ($socket_io->{Tie} && $socket_io->{TieEchoMode}) || $socket_io->{ListenEchoMode}) && $socket_io->{HoldIncLines} &&
						 lastLine(\$bohLine) && length $bohLine < $MaxPromptLength ) {
						if ($bohLine =~ /.*$CmdConfirmPrompt/o || $bohLine =~ /.*$CmdInitiatedPrompt/o) { # If a yn prompt don't hold it
							$socket_io->{HoldIncLines} = 0;	 # And don't hold anymore characters which will follow
						}
						else {
							debugMsg(2,"SocketEcho lastline but not prompt; re-adding to buffer: >", \$bohLine, "<\n");
							$host_io->{OutBuffer} .= $bohLine;	# Re-add prompt to buffer..
							$host_io->{FragmentCache} =~ s/\Q$bohLine\E$//; # checkFragPrompt above will have added it, so we remove it
							$socket_io->{PauseBuffLen} = length $host_io->{OutBuffer};
							return;					# and come out
						}
					}
				}
				if ($bohLine =~ /\n$/ || $term_io->{CompletLineMrkr}) { # Line ends with \n -- processing BEFORE printing out
					$term_io->{CmdOutputLines} = 1;
					$host_io->{FragmentCache} = '';# unless $term_io->{CompletLineMrkr}; # We need to clear this; because checkFragPrompt does not get called for every line, but just when buffer is empty
					my $line = $fragmentCache . $bohLine; # Pre-pend fragment cache if set
					debugMsg(2,"Line with FragmentCache pre-pended:\n>", \$line, "<\n") if length $fragmentCache;
					# Banner detection and formatting
					my ($banner, $notBanner);
					if ($line =~ /$Grep{SocketEchoBanner}/) {
						debugMsg(2,"Socket Echo Banner detected:\n>", \$line, "<\n");
						$term_io->{BannerDetected} = 0;
						($term_io->{BannerCacheLine}, $term_io->{BannerEmptyLine}) = ('', 0);
						$banner = 1;
					}
					elsif ( $line =~ /^$ScriptName: / || # Embedded acli generated summary line, treat as banner
						(exists $Grep{BannerHardPatterns}{$host_io->{Type}} && $line =~ /$Grep{BannerHardPatterns}{$host_io->{Type}}/)) { # Hard banner processing
						debugMsg(2,"Show Command Hard banner line: >", \$line, "<\n");
						if ($bohLine eq $line) { # If not partially already printed
							if ($bohLine eq $term_io->{BannerCacheLine}) { # If not partially already printed, we suppress a duplicate banner line
								debugMsg(2,"Show Command Hard banner line suppression\n");
								next BUFFERLOOP;
							}
							elsif ($term_io->{HideTimeStamps} && exists $TimeStampBanner{$host_io->{Type}} && $bohLine =~ /$TimeStampBanner{$host_io->{Type}}/) {
								$term_io->{CompletLineMrkr} = 0 if $bohLine =~ /\n$/; # If deleting line with \n, the \n which will follow must be considered for empty line suppression
								($bohLine, $logLine) = ('', $bohLine);
								debugMsg(2,"Timestamp line - log only : >", \$logLine, "<\n");
							}
						}
						$term_io->{BannerDetected} = 1;
						($term_io->{BannerCacheLine}, $term_io->{BannerEmptyLine}) = ($line, 0);
						$banner = 1;
					}
					elsif ($term_io->{BannerDetected}) { # Soft banner processing
						if ( ( exists $Grep{BannerSoftPatterns}{$host_io->{Type}} && $line =~ /$Grep{BannerSoftPatterns}{$host_io->{Type}}/ )
						      && !( exists $Grep{BannerExceptions}{$host_io->{Type}} && $line =~ /$Grep{BannerExceptions}{$host_io->{Type}}/ ) ) {
							debugMsg(2,"Show Command Soft banner line: >", \$line, "<\n");
							($term_io->{BannerCacheLine}, $term_io->{BannerEmptyLine}) = ('', 0);
							$banner = 1;
						}
						elsif ($line eq "\n") {
							unless ($noEmptyLineSuppress) {
								$term_io->{BannerEmptyLine} = 1;
								debugMsg(2,"Show Command Banner empty line pre-suppression\n");
								next BUFFERLOOP; # Here we are considering to suppress this empty line inside the banner (provided we hit a further banner line next)
							}
						}
						else {
							$term_io->{BannerDetected} = 0;
							$notBanner = 1;
							debugMsg(2,"Outside of Show Command Banner now: >", \$line, "<\n");
							($term_io->{BannerCacheLine}, $term_io->{BannerEmptyLine}) = ('', 0);
						}
					}
					# A summaryPattern could also have been matched as a BannerSoftPatterns; this happens with ismd summary count
					if (exists $Grep{SummaryPatterns}{$host_io->{Type}} && !$term_io->{RecordCountFlag} && $line =~ /($Grep{SummaryPatterns}{$host_io->{Type}})/i) { # Since we modify, we need to use $bohLine not $line...
						my $summary = $1;
						debugMsg(2,"ShowSumaryLine-captured:\n>", \$summary, "<\n");
						my $nextBufferLine;
						if ($$bufRef =~ /^(?|(.*)\n|(.+)$CompleteLineMarker$)/) {
							$nextBufferLine = $1;
							debugMsg(2,"ShowSumaryLine-look ahead line:\n>", \$nextBufferLine, "<\n");
							if ($nextBufferLine =~ /($Grep{SummaryPatterns}{$host_io->{Type}})/i) {
								debugMsg(2,"ShowSumaryLine-look ahead line is another summary count; skipping insertion\n");
							}
							else {
								$nextBufferLine = undef;
							}
						}
						unless ($nextBufferLine) {
							# We no longer modify the line.. we add a new line to buffer
							$summary = "$ScriptName: Displayed Total Record Count = $term_io->{RecordsMatched}";
							debugMsg(2,"ShowSumaryLine-addingLineToOutput:\n>", \$summary, "<\n");
							if ($term_io->{CompletLineMrkr}) {
								$bohLine .= "\n";
								$$bufRef = $summary . $$bufRef; # $bufRef should be empty, still
							}
							else {
								$$bufRef = $summary . "\n" . $$bufRef;
							}
							$term_io->{RecordCountFlag} = 1;
						}
						$notBanner = 0;
					}
					elsif (!$banner) {
						$notBanner = 1;
						if ($term_io->{BannerEmptyLine}) { # In this case we did not hit a further banner line, so we restore the empty line
							$bohLine = "\n" . $bohLine;
							$term_io->{BannerEmptyLine} = 0;
							debugMsg(2,"Show Command Banner empty line restoring:\n>", \$bohLine, "<\n");
						}
						$term_io->{BannerCacheLine} = '' if $term_io->{BannerCacheLine};
					}
					$term_io->{RecordsMatched}++ if $notBanner && $line =~ /\S/ && (!exists $RecordCountSkip{$host_io->{Type}} || $line !~ /$RecordCountSkip{$host_io->{Type}}/); # Count non-banner non-empty lines

					if (@{$term_io->{VarCapture}}) { # We have a port list/range in the line, we capture it
						if ( $notBanner || grep(!$_, @{$grep->{Advanced}}) ) { # Not a banner line or simple grep exists
							variablesStoreValues($term_io, $line) unless $line =~ /$Grep{SocketEchoBanner}/ || $line =~ /^\cGError from \S+: Cannot process command /;
						}
					}
				}
				else {
					$term_io->{BannerCacheLine} = '';
				}
				unless ($term_io->{EchoOutputOff} && $term_io->{Sourcing}) {
					my @hlGrep;
					if ($term_io->{HLgrep}) { # Highlight is snipped before sedPatternReplace
						my $hlCount = 0;
						my $hlMarker = $HighlightMarker . chr($hlCount);
						while ($bohLine =~ s/$term_io->{HLgrep}/$hlMarker/) {
							push(@hlGrep, $&);
							$hlMarker = $HighlightMarker . chr(++$hlCount);
						}
					}
					# This is where we apply sed output colour patterns
					sedPatternReplace($host_io, $term_io->{SedColourPats}, \$bohLine) if %{$term_io->{SedColourPats}};
					if (@hlGrep) { # and after sedPatternReplace highlight replacement is made
						for my $i (0 .. $#hlGrep) {
							my $hlMarker = $HighlightMarker . chr($i);
							$bohLine =~ s/$hlMarker/$term_io->{HLon}$hlGrep[$i]$term_io->{HLoff}/
						}
					}
					printOut($script_io, $bohLine, $logLine);
					# debugMsg(2,"printedLine ==>", \$bohLine, "<\n");
					print "\e[49m\e[39m\e[0m" if $bohLine =~ /\e\[\d+m/; # Safety disable colouring, to ensure we don't have colouring run off..
					if ($bohLine =~ /\n$/) { # Line ends with \n -- processing AFTER printing out
						$socket_io->{HoldIncLines} = 1;
						if (!$script_io->{CmdLogOnly} && $term_io->{MorePaging} && --$term_io->{PageLineCount} <= 0) {
							print $term_io->{LocalMorePrompt};
							$mode->{term_in_cache} = $mode->{term_in};
							changeMode($mode, {term_in => 'rk', buf_out => 'mp'}, '#6');
							last BUFFER;
						}
					}
				}
				if (length $$bufRef && Time::HiRes::time > $mainLoopTime) { # If more in buffer, but time is up..
					debugMsg(2,"While buffer processing, mainLoopTime expired!\n");
					last BUFFERLOOP;
				}
			} # BUFFERLOOP
		} # BUFFER
	}
	elsif ($mode->{buf_out} eq 'so') { # ---------------> Print to STDOUT (so) <-------------
		sedPatternReplace($host_io, $term_io->{SedColourPats}, \$host_io->{GrepBuffer}) if %{$term_io->{SedColourPats}};
		printOut($script_io, $host_io->{GrepBuffer});
		$host_io->{GrepBuffer} = '';
		quit(0, undef, $db) unless $script_io->{GrepStream}; # We are done
	}
	else {
		quit(1, "ERROR: unexpected buf_out mode: ".$mode->{buf_out}, $db);
	}
}

1;
