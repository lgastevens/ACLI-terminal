# ACLI sub-module
package AcliPm::HandleTerminalInput;
our $Version = "1.10";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(handleTerminalInput);
}
use Term::ReadKey;
use Time::HiRes;
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::Alias;
use AcliPm::CacheFeedInputs;
use AcliPm::ChangeMode;
use AcliPm::CommandProcessing;
use AcliPm::CommandStructures;
use AcliPm::ConnectDisconnect;
use AcliPm::DebugMessage;
use AcliPm::Dictionary;
use AcliPm::ExitHandlers;
use AcliPm::GlobalConstants;
use AcliPm::GlobalDefaults;
use AcliPm::GlobalDeviceSettings;
use AcliPm::InputProcessing;
use AcliPm::MaskUnmaskChars;
use AcliPm::ParseCommand;
use AcliPm::Print;
use AcliPm::Prompt;
use AcliPm::QuotesRemove;
use AcliPm::ReadKey;
use AcliPm::Sed;
use AcliPm::SerialPort;
use AcliPm::Socket;
use AcliPm::Sourcing;
use AcliPm::TabExpand;
use AcliPm::TerminalServer;
use AcliPm::Variables;


sub toggleMore { # CTRL-MorePaging Toggle; can be triggered from local keyboard read or from driving terminal
	my $db = shift;
	my $mode = $db->[0];
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $termbuf = $db->[8];

	$term_io->{MorePaging} = !$term_io->{MorePaging};
	if ($mode->{term_in} eq 'tm') { # Display confirmation message
		my $output = "\n$ScriptName: terminal more paging " . ($term_io->{MorePaging} ? "on" : "off") . "\n";
		printOut($script_io, $output, join ('', $termbuf->{Linebuf1}, $termbuf->{Linebuf2}));
		$host_io->{CLI}->device_more_paging(
			Enable		=> $term_io->{MorePaging},
			Blocking	=> 1,
		) if defined $host_io->{SyncMorePaging};
		return if $host_io->{ConnectionError};
		printOut($script_io, appendPrompt($host_io, $term_io));
		$output = join ('', $termbuf->{Linebuf1}, $termbuf->{Linebuf2}, $termbuf->{Bufback2});
		print $output;
	}
	elsif (defined $host_io->{SyncMorePaging}) { # If currently displaying output & need to sync paging on host device
		$host_io->{SyncMorePaging} = 1;	# Sync more paging at next prompt detection
	}
	if ($term_io->{MorePaging}) { # More paging has been enabled above
		if ($mode->{buf_out} eq 'eb') { # If already in Buffered Output mode
			$term_io->{PageLineCount} = 1;	# Kick in asap
		}
		else { # In any other mode
			$term_io->{PageLineCount} = $term_io->{MorePageLines}; # Reset counter to max
		}
	}
}


sub enterACLImode { # Action when entering ACLI> prompt
	my $db = shift;
	my $mode = $db->[0];
	my $cacheMode = $db->[1];
	my $term_io = $db->[2];
	my $script_io = $db->[4];
	my $socket_io = $db->[6];
	my $termbuf = $db->[8];
	my $history = $db->[9];

	$script_io->{AcliControl} = 1;
	$history->{Current} = $history->{ACLI};
	$history->{Index} = -1;
	$termbuf->{Linebuf1} = $termbuf->{Linebuf2} = $termbuf->{Bufback1} = $termbuf->{Bufback2} = '';
	if ($mode->{term_in} eq 'qs') { # Clear sockets if any were kept active after session timeout, but user has now hit CTRL-]
		untieSocket($socket_io);
		closeSockets($socket_io, 1);
		setPromptSuffix($db);
	}
	%$cacheMode = %$mode;	# Cache mode settings
	changeMode($mode, {term_in => 'tm', dev_inp => 'ds', buf_out => 'ds'}, '#HTI1');
	print "\n", $ACLI_Prompt;
	saveInputBuffer($term_io);
	$term_io->{SourceNoHist} = 0;
	$term_io->{SourceNoAlias} = 0;
	while (readKeyPress) {} # Read and trash any further queued input
}


sub historyAdd { # Add command to history
	my ($history, $command) = @_;

	unless ($command =~ /^\s*$/) { # Do nothing for blank lines
		# Update history recall array
		unless (@{$history->{Current}} && $history->{Current}[$#{$history->{Current}}] eq $command) {
			@{$history->{Current}} = grep {$_ ne $command} @{$history->{Current}}; # Weed out previous occurrencies of same command
			push(@{$history->{Current}}, $command);
		}
		# Update history of actual commands (only for host; not in ACLI mode)
		if ($history->{Current} == $history->{HostRecall}) {
			push(@{$history->{UserEntered}}, $command);
		}
	}
	$history->{Index} = -1;

	# For debug dump recall history there and then
	if ($::Debug & 128 && @{$history->{HostRecall}}) {
		print "\n";
		for my $i (0 .. $#{$history->{HostRecall}}) {
			printf "%5s : %s\n", $i+1, $history->{HostRecall}[$i];
		}
	}
}


sub handleTerminalInput { # Handle user or sourced input to terminal
	my $db = shift;
	my $mode = $db->[0];
	my $cacheMode = $db->[1];
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $socket_io = $db->[6];
	my $prompt = $db->[7];
	my $termbuf = $db->[8];
	my $history = $db->[9];
	my $grep = $db->[10];
	my $alias = $db->[11];
	my $vars = $db->[12];
	my $dictionary = $db->[16];

	return if $mode->{term_in} eq 'ds';

	my ($key, $delta, $command, $quit, $singleChar, $keyReadFlag, $specialChar, $pastedInput);

	if ($host_io->{SyntaxError} && ($mode->{term_in} eq 'tm' || $mode->{term_in} eq 'ps') && !$term_io->{BuffersCleared}) {
		if (Time::HiRes::time < $term_io->{QuietInputDelay}) {
			debugMsg(4,"=AbortingInputBufferDueToSyntaxError-QuietInputDelay not expired; time = ", \Time::HiRes::time, " < $term_io->{QuietInputDelay}\n") if $term_io->{DelayCharProcDF};
			$term_io->{DelayCharProcDF} = 0;
			return;
		}
		debugMsg(4,"=AbortingInputBufferDueToSyntaxError-QuietInputDelay EXPIRED; time = ", \Time::HiRes::time, " > $term_io->{QuietInputDelay}\n");
		debugMsg(4,"=AbortingInputBufferDueToSyntaxError!!!\n");
		$term_io->{BuffersCleared} = 1; # Assume we are going to clear the input buffers...
		while ( defined ($key = readKeyPress) ) { # ... but if there is more input comming...
			# Copy of sections below; process CTRL-Q and the escape char at least
			quit(0, undef, $db) if $key eq $term_io->{CtrlQuitChr};
			if ($key eq $term_io->{CtrlEscapeChr}) { # Enter ACLI> command line
				enterACLImode($db);
				return;
			}
			$term_io->{BuffersCleared} = 0;   # ... ensure we come back here at next cycle
			debugMsg(4,"=AbortingInputBufferDueToSyntaxError-drainingMoreInput!!!\n");
			if ($key eq $Return) { # Return key indicates a complete line
				my $line = join('', @{$term_io->{CharBuffer}});
				appendInputBuffer($db, 'paste', [$line]) if defined $line;
				@{$term_io->{CharBuffer}} = ();
				debugMsg(4,"=InputBufferPushLine-afterSyntaxError: /", \$line, "/\n");
			}
			else { # Push keystroke onto input array buffer
				push(@{$term_io->{CharBuffer}}, $key);
				debugMsg(4,"=InputBufferPushChar-afterSyntaxError: /", \$key, "/\n");
			}
		}
		# Push into cache and clear input buffer if we have an error on previous command sent
		saveInputBuffer($term_io);
		$term_io->{SourceNoHist} = 0;
		$term_io->{SourceNoAlias} = 0;
		return;
	}

	##########################################
	# Read keyboard until input buffer empty #
	##########################################

	$term_io->{Key} = '';
	while ( defined ($key = readKeyPress) ) {

		quit(0, undef, $db) if $key eq $term_io->{CtrlQuitChr};

		# Key strokes always processed (all term_in modes)
		if ($key eq $term_io->{CtrlEscapeChr}) { # Enter ACLI> command line
			return if $script_io->{AcliControl} == 1;
			enterACLImode($db);
			return;
		}
		if ($key eq $term_io->{CtrlBrkChr}) { # Break signal to send
			return if $script_io->{AcliControl} || !$host_io->{Connected};
			$host_io->{CLI}->break; # Send the break signal
			debugMsg(2,"=Break signal sent !\n");
			return;
		}
		if ($key eq $term_io->{CtrlClsChr}) { # Clear the screen
			my $cmd = $^O eq "MSWin32" ? 'cls' : 'clear';
			system($cmd);
			ReadMode('raw'); # Must re-activate raw mode after a cls, otherwise CTRL-C will kill the script!
			if ($script_io->{AcliControl} == 1) {
				print "\n", $ACLI_Prompt;
				return;
			}
			else { # Make it as if user had hit return after clearing the screen
				$key = $Return;
			}
			debugMsg(2,"=Screen clearedt !\n");
		}
		if ($::Debug && $key eq $term_io->{CtrlDebugChr}) {
			return Debug::run($db) if $DebugPackage;
			print "\nNo Debug.pm loaded\n";
			return;
		}
		if ($mode->{term_in} eq 'qs') { # No further Key strokes processed in read key mode 'qs'
			quit(0, undef, $db) if $key =~ /^[qQ]$/;
			if ($key eq $Space) {
				print "\n";
				$script_io->{ConnectFailMode} = 1;
				connectToHost($db) or return;
				if ($term_io->{AutoDetect}) {
					changeMode($mode, {term_in => 'rk', dev_inp => 'ct', dev_del => 'ds', dev_fct => 'ds', dev_out => 'ub', buf_out => 'ds'}, '#HTI2');
				}
				else {
					changeMode($mode, {term_in => 'sh', dev_inp => 'ct', dev_del => 'ds', dev_fct => 'ds', dev_out => 'ub', buf_out => 'ds'}, '#HTI3');
				}
			}
			return;
		}
		$key eq $term_io->{CtrlMoreChr} && $term_io->{Mode} eq 'interact' && do { # CTRL-MorePaging Toggle
			toggleMore($db);
			unless ($mode->{term_in} eq 'rk') { # In which case we need to process if ($mode->{term_in} eq 'rk') below
				socketBufferPack($socket_io, $key, 0) if $term_io->{SocketEnable};
				return;
			}
		};
		$key eq $term_io->{CtrlInteractChr} && !$script_io->{AcliControl} && do { # OutputSinceSend was preveting CTRL-T from unlocking stuck state in some conditions
			return if $term_io->{PseudoTerm}; # Otherwise we crash!
			# CTRL-Interact Toggle to transparent mode
			if ($term_io->{Mode} eq 'interact') {
				printOut($script_io, "\n$ScriptName: Using terminal transparent mode\n");
				$term_io->{Mode} = 'transparent';
				if (defined $script_io->{CmdLogFH}) {
					close $script_io->{CmdLogFH};
					$script_io->{CmdLogFH} = $script_io->{CmdLogFile} = $script_io->{CmdLogOnly} = $script_io->{CmdLogFlag} = undef;
				}
				$host_io->{OutBuffer} = ''; # Flush BufferedOutput buffer, in case it's not empty
				$host_io->{SendBuffer} .= $term_io->{Newline};	# Send a carriage return to host
				$host_io->{CLI}->poll_reset; # Safety, make sure any Control::CLI polling methods are reset
				$mode->{connect_stage} = 0; # As above, in case we hit CTRL-T in the middle of handleDeviceConnect
				changeMode($mode, {term_in => 'sh', dev_inp => 'rd', dev_del => 'ds', dev_fct => 'ds', dev_out => 'ub', buf_out => 'ds'}, '#HTI4');
			}
			elsif ($host_io->{Discovery}) { # Transparent mode; try to do a fast switch to interact mode
				$term_io->{Mode} = $host_io->{CapabilityMode};
				$host_io->{SendBuffer} .= $term_io->{Newline};
				$term_io->{InteractRestore} = 2;
				debugMsg(2,"Attempting to fast switch back to interact mode\n");
			}
			else { # Transparent mode; switch to interact mode the slow way
				printOut($script_io, "\n");
				$host_io->{SendBuffer} .= $term_io->{Newline} unless $host_io->{Console}; # On console we automatically send wake_console (bug22)
				$term_io->{AutoDetect} = 1 if $host_io->{ComPort} =~ /^(?:TELNET|SSH)$/; # In case of re-connect go back into interact mode, but not on serial port
				changeMode($mode, {term_in => 'rk', dev_inp => 'lg'}, '#HTI5');

			}
			while (readKeyPress) {} # Read and trash any further queued input
			return;
		};

		if ($mode->{term_in} eq 'rk') { # No further Key strokes processed in read key mode 'rk'
			$term_io->{Key} = $key;
			# If we have sockets enabled, set the key here; it will be sent if we have a tied socket
			socketBufferPack($socket_io, $key, 0) if $term_io->{SocketEnable};
			return;
		}
		if (defined $singleChar) {
			$singleChar = 0; # Reset to zero on 2nd and subsequent character reads
		}
		else {
			$singleChar = 1; # Set to 1 first time we read a character
		}

		if ($key eq $Return && !$singleChar && !$specialChar && $mode->{term_in} eq 'tm') { # Return key indicates a complete line
			my $line = join('', @{$term_io->{CharBuffer}});
			appendInputBuffer($db, 'paste', [$line]) if defined $line;
			@{$term_io->{CharBuffer}} = ();
			# Clear out the save buffers
			$term_io->{SaveCharBuffer} = $term_io->{SaveCharPBuffer} = '';
			$term_io->{SaveSourceActive} = {};
			$term_io->{SaveEchoMode} = [];
			$term_io->{SaveSedDynPats} = [];
			debugMsg(4,"=InputBufferPushLine: /", \$line, "/ <==RETURN\n\n");
			$pastedInput = 1;
		}
		else { # Push keystroke onto input array buffer
			push(@{$term_io->{CharBuffer}}, $key);
			debugMsg(4,"=InputBufferPushChar: /", \$key, "/\n");
			$specialChar = 1 if ord($key) < 32 && $key ne $Tab && $key ne $Return; # If we see special chars, then we disable above appendInputBuffer (bug23)
		}
		$keyReadFlag = 1;
	}
	if ($pastedInput && @{$term_io->{CharBuffer}}) { # Incomplete line following complete line(s) accepted into paste buffer
		$term_io->{CharPBuffer} = join('', @{$term_io->{CharBuffer}});
		@{$term_io->{CharBuffer}} = ();
		debugMsg(4,"=InputBuffer move CharBuffer to CharPBuffer: /", \$term_io->{CharPBuffer}, "/\n");
	}
	# Reset singleChar IF it was set AND we did read from keyboard at previous cycle
	# Basically, we only want singleChar set, if a single character is read, after a quiet period
	$singleChar = 0 if $singleChar && $term_io->{TermReadFlag};

	# Now, update flag which keeps track of whether we read anything from keyboard; needed on line above at next cycle
	if ($keyReadFlag) {
		$term_io->{TermReadFlag} = 1;
		$socket_io->{ListenEchoMode} = undef; # On keyboard input, undefine this
		delete($vars->{'%'}) unless $socket_io->{Tie};
	}
	else {
		debugMsg(2,"==================================\nKEYBOARD: NO INPUT\n") if $term_io->{TermReadFlag};
		$term_io->{TermReadFlag} = 0;
	}

	toggleMore($db) if defined $term_io->{SingleChar} && $term_io->{SingleChar} eq $term_io->{CtrlMoreChr} && $term_io->{Mode} eq 'interact'; # From Tied term

	if ($singleChar || defined $term_io->{SingleChar}) {
		debugMsg(4,"=singleChar input processing\n") if $singleChar;
		debugMsg(4,"=term_io->{SingleChar} input processing\n") if defined $term_io->{SingleChar};
		$term_io->{SourceNoHist} = 0;
		$term_io->{SourceNoAlias} = 0;
		if ($mode->{term_in} eq 'ps' && $mode->{buf_out} eq 'eb' && 
			( (defined $term_io->{SingleChar} && $term_io->{SingleChar} =~ /^[qQ]$/) ||
			  ($singleChar && $term_io->{CharBuffer}[$#{$term_io->{CharBuffer}}] =~ /^[qQ]$/) ) ) {
			# Come out of paging before getting a local more prompt
			$term_io->{BufMoreAction} = 'q';
			debugMsg(4,"=ComeOutOfMorePagingBeforeGettingLocalMorePrompt\n");
			socketBufferPack($socket_io, '', 0) if $term_io->{SocketEnable};
			return;
		}
		if ($term_io->{InputBuffQueue}->[0]) { # Safety escape from repeatCmd, loopCmd and other buffers
			$key = shift @{$term_io->{CharBuffer}} unless defined $term_io->{SingleChar}; # Recover key which got us here if not from controlling socket terminal
			saveInputBuffer($term_io, 1);
			unless (defined $term_io->{SingleChar} || $key eq $Space) { # Re-add it, if not a space
				push(@{$term_io->{CharBuffer}}, $key);
				debugMsg(4,"=SingleCharEscape-InputBuffer-RE-PushChar: /", \$key, "/\n");
			}
#			printOut($script_io, appendPrompt($host_io, $term_io)) if $mode->{term_in} eq 'tm';
			debugMsg(4,"=SafetyEscapeQueueRelatedCommands\n");
			socketBufferPack($socket_io, '', 0) if $term_io->{SocketEnable};
		}
		$term_io->{SingleChar} = undef;
	}
	return if $mode->{term_in} eq 'rk' || $mode->{term_in} eq 'ib' || $mode->{term_in} eq 'qs';
	my $queue = $term_io->{InputBuffQueue}->[0];

	#########################################
	# Processing commands from queue        #
	#########################################
	if ($queue && $mode->{term_in} ne 'ps' && $mode->{dev_del} ne 'kp') {
		# $mode->{dev_del} eq 'kp' - Keepalive in progress; wait until settled
		# $mode->{term_in} eq 'ps' - Paced sending; we only send when we have a prompt
		debugMsg(4,"=handleTerminalInput queue: /", \$queue, "/\n") if $queue;

		#########################################
		# Fetch repeated command if set         #
		#########################################
		if ($queue eq 'RepeatCmd') {
			return if $term_io->{RepeatUpTime} > time;
			$command = $term_io->{RepeatCmd};
			$term_io->{RepeatUpTime} = time + $term_io->{RepeatDelay};
			$term_io->{SourceNoHist} = 1;	# Disable history
			$term_io->{YnPrompt} = 'y';
			debugMsg(4,"=RepeatedCommandInjecting: /", \$command, "/\n");
		}
		elsif ($queue eq 'SleepCmd') {
			return if $term_io->{SleepUpTime} > time;
			$host_io->{OutBuffer} .= $host_io->{Prompt};
			shiftInputBuffer($db);
			debugMsg(4,"=\@Sleep completed\n");
		}

		#########################################
		# Fetch loop command if set             #
		#########################################
		elsif ($queue eq 'ForLoopCmd') {
			my @list;
			my ($i, $l) = (0, 0); # Indexes to traverse ranges ($i) and lists ($l)
			foreach my $type (@{$term_io->{ForLoopVarType}}) { # traverse vars types
				if ($type) { # List type
					push(@list, shift @{$term_io->{ForLoopVarList}[$l++]});
				}
				else { # Range type
					$term_io->{ForLoopVar}[$i] += $term_io->{ForLoopVarStep}[$i]; # Increase variable 1st
					push(@list, $term_io->{ForLoopVar}[$i++]);
				}
			}

			# Obtain command for this iteration
			if ($term_io->{ForLoopVarN}) { # Multiply ranges
				push(@list, $list[0]) for (2 .. $term_io->{ForLoopVarN});
			}
			$command = doubleQuoteUnmask( sprintf($term_io->{ForLoopCmd}, @list), '%');
			debugMsg(4,"=ForLoopCommandInjecting: /", \$command, "/\n");

			# Reduce iteration count
			--$term_io->{ForLoopCycles};
			# Check on hitting zero is now done above (bug12)
			if ($term_io->{ForLoopCycles} == 0) {
				$term_io->{ForLoopCmd} = undef;
				shiftInputBuffer($db);
			}
			if ($term_io->{EchoOff}) {
				$host_io->{CommandCache} .= $command;
				debugMsg(4,"=adding to CommandCache:\n>",\$host_io->{CommandCache}, "<\n");
			}
			else {
				print $command;
			}
			$term_io->{SourceNoHist} = 1;	# Disable history
			$term_io->{YnPrompt} = 'y';
		}

		#########################################
		# Fetch first line of buffer if present #
		#########################################
		elsif ($queue) { # 'paste' or 'source' or 'semiclnfrg'
			do {
				$command = shiftInputBuffer($db);
			} while $queue eq 'source' && defined $command && $command =~ /^\s*#/; # Skip comments starting with # when sourcing
			if (defined $command) { # It could be that last line was a comment, and hence we have no command to process..
				$term_io->{SourceNoHist} = $queue eq 'paste' ? 0 : 1;	# Disable history, except for paste buffer
				if ($mode->{term_in} eq 'pw') { # ----------> Password Entry <--------------
					(my $blankpwd = $command) =~ s/./*/g;
					print $blankpwd;
					debugMsg(4,"=InputBufferExtractingPwd: /", \$blankpwd, "/\n");
				}
				elsif ($mode->{term_in} eq 'sh') { # Transparent mode pasting
					debugMsg(4,"=InputBufferExtractingLineTransparentMode: /", \$command, "/\n");
					$command .= "\n";	# Re-add carriage return
				}
				else { # Interactive mode
					$command =~ s/\t+/ /g;	# Remove Tab characters and replace with space
					if ($term_io->{EchoOff}) {
						$host_io->{CommandCache} .= $command;
						debugMsg(4,"=adding to CommandCache:\n>",\$host_io->{CommandCache}, "<\n");
					}
					elsif ($term_io->{HlEnteredCmd} && $queue eq 'paste') {
						my ($hon, $hoff) = returnHLstrings({bright => 1});
						print $hon, $command, $hoff;
					}
					else {
						print $command;
					}
					$term_io->{YnPrompt} = 'y';
					debugMsg(4,"=InputBufferExtractingLineInteractMode: /", \$command, "/\n");
				}
				if ($termbuf->{Linebuf1} || $termbuf->{Linebuf2}) { # Append to existing buffer, if present
					$command = join('', $termbuf->{Linebuf1}, $termbuf->{Linebuf2}, $command);
					$termbuf->{Linebuf1} = $termbuf->{Linebuf2} = $termbuf->{Bufback1} = $termbuf->{Bufback2} = '';
				}
			}
		}
		if (!$term_io->{InputBuffQueue}->[0] && length $term_io->{CharPBuffer}) { # Release the Char Paste Buffer, once the input queues are empty
			unshift(@{$term_io->{CharBuffer}}, split(//, $term_io->{CharPBuffer}) );
			debugMsg(4,"=InputBuffer CharBuffer inserting CharPBuffer: >", \$term_io->{CharPBuffer}, "<\n");
			$term_io->{CharPBuffer} = '';
		}
	}

	#########################################
	# If not, process character buffer      #
	#########################################
	else { # Only if nothing in the buffer...

		# Delay sequences
		if ($mode->{term_in} eq 'tm' && !$script_io->{AcliControl} && Time::HiRes::time < $term_io->{DelayCharProcTm} && length $host_io->{PacedSentChars}) {
			debugMsg(4,"=DelayCharProcessing-in-tm-mode not expired; time = ", \Time::HiRes::time, " < $term_io->{DelayCharProcTm}\n") if $term_io->{DelayCharProcDF};
			$term_io->{DelayCharProcDF} = 0;
			return;
		}
		elsif ($mode->{term_in} eq 'ps' && Time::HiRes::time < $term_io->{DelayCharProcPs}) {
			unless (defined $term_io->{CharBuffer}[0] && $term_io->{CharBuffer}[0] eq $Return) { # Not if next char is CR
				debugMsg(4,"=DelayCharProcessing-in-ps-mode not expired; time = ", \Time::HiRes::time, " < $term_io->{DelayCharProcPs}\n") if $term_io->{DelayCharProcDF};
				$term_io->{DelayCharProcDF} = 0;
				return;
			}
		}

		my $keyBuf;
		while ( length ( $key = shift @{$term_io->{CharBuffer}} ) ) { # Process all characters in array buffer
			debugMsg(4,"=ProcessKey /", \$key, "/\n");
			unless (defined $singleChar) {
				if (!@{$term_io->{CharBuffer}}) {
					# There was no key read at this cycle - $singleChar undefined
					# && we just removed the only character which was held in @{$term_io->{CharBuffer}}
					$singleChar = 1;
					debugMsg(4,"=SingleChar override input processing\n");
				}
				else {
					$singleChar = 0;
				}
			}

			#########################################################################
			# Key strokes processed in send-to-host 'sh' & paced-sending 'ps' modes #
			#########################################################################

			if ($mode->{term_in} eq 'sh' || $mode->{term_in} eq 'ps') { # ------------> Send to Host mode <-------------
				$host_io->{SendBuffer} .= $key eq $Return ? $term_io->{Newline} : $key;

				# If we have sockets enabled, put in buffer; it will be sent if we have a tied socket
				$keyBuf .= $key if $term_io->{SocketEnable};

				if ($mode->{term_in} eq 'ps') { # Keep track of what we send to host in 'ps' mode
					$host_io->{PacedSentChars} .= $key;
					if ($key eq $Return) { # If CR
						$host_io->{PacedSentChars} = ''; # Wipe it clean
						# $term_io->{DelayCharProcPs} = Time::HiRes::time + $DelayCharProcPs; # Delay term input after CR, in ps mode (bug1)
						# line below effectively disables line above; but $DelayCharProcPs functionality still works after command initially sent to host
						# basically if user starts interacting with output then assume we have to go into unbuffered mode
						changeMode($mode, {term_in => 'sh', dev_out => 'ub'}, '#HTI6'); # Switch to unbuffered mode
						debugMsg(1,"-> Switching to unbuffered output as RETURN key hit in ps mode!\n");
						# If socket tied, we might be holding on to a prompt; so flush that too
						$term_io->{DelayPrompt} = 0 if defined $term_io->{DelayPrompt};
						if (length $host_io->{OutBuffer}) { # If switching from dev_out 'bf' we might have stuff in this buffer
							# If so we need to get it infront of new data once we are in 'ub' mode
							debugMsg(1,"-> Empty OutBuffer back onto OutCache: >", \$host_io->{OutBuffer}, "<\n");
							$host_io->{OutCache} = $host_io->{OutBuffer} . $host_io->{OutCache};
							$host_io->{OutBuffer} = '';
						}
						last; # In this case come out; if more chars we process at next cycle (as we may want to DelayCharProcPs)
					}
					debugMsg(4,"=PacedSentChars /", \$host_io->{PacedSentChars}, "/\n");
				}
				next;
			}

			#######################################################
			# Key strokes processed in local term modes: tm,us,pw #
			#######################################################

			if ($mode->{term_in} eq 'pw') { # ----------> Password Entry <--------------
				#
				# Keys we ignore during password entry
				#
				($key eq $Delete || $key eq $CTRL_D) && return; # Delete
				($key eq $CrsrLeft || $key eq $CTRL_B) && return; # Cursor <-
				($key eq $CrsrRight || $key eq $CTRL_F) && return; # Cursor ->
				$key eq $CTRL_A && return; # CTRL-A, go to beginning of line
				$key eq $CTRL_E && return; # CTRL-E, go to end of line
			}

			if ($mode->{term_in} eq 'us' || $mode->{term_in} eq 'pw') { # ------> Username OR Password entry <-----
				#
				# So we handle backspace for username/password entry (req from Ronald)
				#
				($key eq $BackSpace || $key eq $CTRL_H) && do { # Backspace
					return unless length $termbuf->{Linebuf1};
					chop $termbuf->{Linebuf1};
					chop $termbuf->{Bufback1};
					print $BackSpace, $Space, $BackSpace;
					return;
				};
				#
				# Keys we ignore during username OR password entry
				#
				($key eq $CrsrUp || $key eq $CrsrDown ||
				 $key eq $CTRL_P || $key eq $CTRL_N) && return; # Cursor up/down
				$key eq $Tab && return; # Tab key
				($key eq $CTRL_C || $key eq $CTRL_U) && return; # CTRL sequence: delete/abort line
				($key eq $CTRL_K || $key eq $CTRL_R) && return; # CTRL sequence: redisplay line
				$key eq $CTRL_W && return; # CTRL-W, delete word left of cursor
				$key eq $CTRL_X && return; # CTRL-X, delete all chars left of cursor
			}

			if ($mode->{term_in} eq 'tm') { # ----------> Local Term mode <--------------
				#
				# Keys we process in regular local term mode
				#
				($key eq $BackSpace || $key eq $CTRL_H) && do { # Backspace
					return unless length $termbuf->{Linebuf1};
					chop $termbuf->{Linebuf1};
					chop $termbuf->{Bufback1};
					print $BackSpace, $termbuf->{Linebuf2}, $Space, $BackSpace, $termbuf->{Bufback2};
					return;
				};
				($key eq $Delete || $key eq $CTRL_D) && do { # Delete
					return unless length $termbuf->{Linebuf2};
					substr($termbuf->{Linebuf2}, 0, 1, '');
					print $termbuf->{Linebuf2}, $Space, $termbuf->{Bufback2};
					chop($termbuf->{Bufback2});
					return;
				};
				($key eq $CrsrLeft || $key eq $CTRL_B) && do { # Cursor <-
					return unless length $termbuf->{Linebuf1};
					print $BackSpace;
					$termbuf->{Linebuf2} = chop($termbuf->{Linebuf1}) . $termbuf->{Linebuf2};
					$termbuf->{Bufback2} .= chop($termbuf->{Bufback1});
					return;			
				};
				($key eq $CrsrRight || $key eq $CTRL_F) && do { # Cursor ->
					return unless length $termbuf->{Linebuf2};
					my $char = substr($termbuf->{Linebuf2}, 0, 1, '');
					print $char;
					$termbuf->{Linebuf1} .= $char;
					$termbuf->{Bufback1} .= chop($termbuf->{Bufback2});
					return;
				};
				$key eq $CTRL_A && do { # CTRL-A, go to beginning of line
					print $termbuf->{Bufback1};
					$termbuf->{Linebuf2} = $termbuf->{Linebuf1} . $termbuf->{Linebuf2};
					$termbuf->{Bufback2} = $termbuf->{Bufback1} . $termbuf->{Bufback2};
					$termbuf->{Linebuf1} = $termbuf->{Bufback1} = '';
					return;
				};
				$key eq $CTRL_E && do { # CTRL-E, go to end of line
					print $termbuf->{Linebuf2};
					$termbuf->{Linebuf1} = $termbuf->{Linebuf1} . $termbuf->{Linebuf2};
					$termbuf->{Bufback1} = $termbuf->{Bufback1} . $termbuf->{Bufback2};
					$termbuf->{Linebuf2} = $termbuf->{Bufback2} = '';
					return;
				};
				($key eq $CTRL_C || $key eq $CTRL_U) && do { # CTRL sequence: delete/abort line
					$termbuf->{Linebuf1} =~ s/./ /g; # Replace with spaces
					$termbuf->{Linebuf2} =~ s/./ /g; # Replace with spaces
					print $termbuf->{Bufback1}, $termbuf->{Linebuf1}, $termbuf->{Linebuf2}, $termbuf->{Bufback2}, $termbuf->{Bufback1};
					$termbuf->{Linebuf1} = $termbuf->{Linebuf2} = $termbuf->{Bufback1} = $termbuf->{Bufback2} = '';
					$history->{Index} = -1;
					if ($key eq $CTRL_C) {
						if ($script_io->{AcliControl} & 8) { # Break out of @vars prompt
							$script_io->{AcliControl} = 0;
							printOut($script_io, "\n");
							$host_io->{OutBuffer} .= $host_io->{Prompt};
							changeMode($mode, {term_in => 'ps', dev_out => 'bf', buf_out => 'eb'}, '#HTI7');
						}
						else { # For CTRL-C get a fresh prompt from host
							$host_io->{SendBuffer} .= $term_io->{Newline};
						}
					}
					return;
				};
				($key eq $CTRL_K || $key eq $CTRL_R) && do { # CTRL sequence: redisplay line
					return if $script_io->{AcliControl}; # Not ACLI, control menus, or in @vars prompt
					my $output = $host_io->{Prompt} . ($term_io->{LtPrompt} ? $term_io->{LtPromptSuffix} : '');
					$output .= join ('', $termbuf->{Linebuf1}, $termbuf->{Linebuf2}, $termbuf->{Bufback2});
					print "\n", $output;
					return;
				};
				$key eq $CTRL_W && do { # CTRL-W, delete word left of cursor
					$termbuf->{Linebuf1} =~ s/(\S+\s*)$//;
					return unless $1;
					(my $pad = $1) =~ s/./ /g;
					(my $padback = $pad) =~ s/./\cH/g;
					print $termbuf->{Bufback1}, $termbuf->{Linebuf1}, $termbuf->{Linebuf2}, $pad, $padback, $termbuf->{Bufback2};
					($termbuf->{Bufback1} = $termbuf->{Linebuf1}) =~ s/./\cH/g;
					return;
				};
				$key eq $CTRL_X && do { # CTRL-X, delete all chars left of cursor
					$termbuf->{Linebuf1} =~ s/./ /g;
					print $termbuf->{Bufback1}, $termbuf->{Linebuf2}, $termbuf->{Linebuf1}, $termbuf->{Bufback1}, $termbuf->{Bufback2};
					($termbuf->{Linebuf1}, $termbuf->{Bufback1}) = ('', '');
					return;
				};
				($key eq $CrsrUp || $key eq $CrsrDown ||
				 $key eq $CTRL_P || $key eq $CTRL_N) && do { # Cursor up/down
					return if $script_io->{AcliControl} & 14; # Not in control menus, or in @vars prompt
					return unless @{$history->{Current}};
					if ($key eq $CrsrUp || $key eq $CTRL_P) {
						if    ($history->{Index} == 0) { $history->{Index} = -1 }
						elsif ($history->{Index} == -1) { $history->{Index} = $#{$history->{Current}} }
						else  { $history->{Index}-- }
					} else { #  $CrsrDown or CTRL-N
						if    ($history->{Index} == $#{$history->{Current}}) { $history->{Index} = -1 }
						elsif ($history->{Index} == -1) { $history->{Index} = 0 }
						else  { $history->{Index}++ }
					}
					$command = $history->{Index} == -1 ? '' : $history->{Current}[$history->{Index}];
					print $termbuf->{Bufback1}, $command;
					if (($delta = length("$termbuf->{Linebuf1}$termbuf->{Linebuf2}") - length($command)) > 0) {
						$termbuf->{Linebuf2} = $termbuf->{Bufback2} = '';
						for (1 .. $delta) {
							$termbuf->{Linebuf2} .= $Space;
							$termbuf->{Bufback2} .= $BackSpace;
						}
						print $termbuf->{Linebuf2}, $termbuf->{Bufback2};
					}
					$termbuf->{Linebuf1} = $command;
					$termbuf->{Bufback1} = $termbuf->{Linebuf2} = $termbuf->{Bufback2} = '';
					for (1 .. length($command) ) { $termbuf->{Bufback1} .= $BackSpace }
					return;
				};
				$key eq $Tab && $singleChar && do { # Tab key
					return unless length $termbuf->{Linebuf1} || length $termbuf->{Linebuf2};
					if ($script_io->{AcliControl}) { # Control ACLI interface
						if ( $command = tabExpand($ControlCmds, "$termbuf->{Linebuf1}$termbuf->{Linebuf2}") ) {
							debugMsg(1,"-> AcliControl-command-tab-expansion = $command\n");
							print $termbuf->{Bufback1}, $command;
							$termbuf->{Linebuf1} = $command;
							($termbuf->{Bufback1} = $command) =~ s/./\cH/g;
							$termbuf->{Linebuf2} = $termbuf->{Bufback2} = '';
						}
						else {
							print $Bell;	# Beep if no expansion found
						}
					}
					else { # Normal mode, talking to host device
						$command = $termbuf->{Linebuf1} . $termbuf->{Linebuf2};
						# First see if we have an embedded or dictionary command we recognize
						if ( my $embCommand = tabExpand($EmbeddedCmds, $command, undef, 1) ) {
							debugMsg(1,"-> Embedded-command-tab-expansion = $command\n");
							print $termbuf->{Bufback1}, $embCommand;
							$termbuf->{Linebuf1} = $embCommand;
							($termbuf->{Bufback1} = $embCommand) =~ s/./\cH/g;
							$termbuf->{Linebuf2} = $termbuf->{Bufback2} = '';
						}
						elsif ( defined $term_io->{Dictionary} && (my $dictCommand = (dictionaryMatch($db, $dictionary->{input}, $command))[0]) ) {
							debugMsg(1,"-> Dictionary-command-tab-expansion = $command\n");
							print $termbuf->{Bufback1}, $dictCommand;
							$termbuf->{Linebuf1} = $dictCommand;
							($termbuf->{Bufback1} = $dictCommand) =~ s/./\cH/g;
							$termbuf->{Linebuf2} = $termbuf->{Bufback2} = '';
						}
						elsif (!$term_io->{PseudoTerm}) {
							# If not, we submit the buffer + Tab to host and see what he comes back with
							my $cmdParsed = parseCommand($command);
							($termbuf->{TabOptions} = $cmdParsed->{thiscmd}) =~ s/^\Q$cmdParsed->{command}->{str}\E//;
							$termbuf->{TabBefoVar} = $cmdParsed->{command}->{str};
							derefVariables($db, $cmdParsed, $cmdParsed->{'command'}, 1); # Deref vars, if any
							$termbuf->{TabCmdSent} = $cmdParsed->{command}->{str};
							$termbuf->{TabBefoVar} = undef if $termbuf->{TabBefoVar} eq $termbuf->{TabCmdSent};
							if ($command =~ /\\/) { # Remove all and any backslashes
								$termbuf->{TabCmdSent} =~ s/(^|[^\\])\\/$1/g;
								debugMsg(4,"=TabRemovingBackslashes: /", \$termbuf->{TabCmdSent}, "/\n");
							}
							$termbuf->{SedInputApplied} = undef;
							if (%{$term_io->{SedInputPats}}) {
								sedPatternReplace($host_io, $term_io->{SedInputPats}, \$termbuf->{TabCmdSent});
								$termbuf->{SedInputApplied} = 1;
							}
							$host_io->{SendBuffer} .= $termbuf->{TabCmdSent};
							$host_io->{SendBufferDelay} = $Tab;
							debugMsg(4,"=Tab: /", \$termbuf->{TabCmdSent}, "/\n");
							$termbuf->{TabMatchTail} = undef;
							if ($TabSynMode{$host_io->{Type}}[$term_io->{AcliType}] & 2) {
								# This does not apply to any of SecureRouter, WLAN2300, WLAN9100
								$termbuf->{TabMatchTail} = quotemeta(substr($termbuf->{TabCmdSent}, -10));
								debugMsg(4,"=TabMatchTail-set-to: /", \$termbuf->{TabMatchTail}, "/\n");
							}
							changeMode($mode, {dev_del => 'ft'}, '#HTI8') if $TabSynMode{$host_io->{Type}}[$term_io->{AcliType}] & 4;
							changeMode($mode, {dev_del => 'te'}, '#HTI9') if $TabSynMode{$host_io->{Type}}[$term_io->{AcliType}] & 8;
							$termbuf->{TabMatchSent} = quotemeta($termbuf->{TabCmdSent});
							changeMode($mode, {term_in => 'ib', dev_fct => 'tb'}, '#HTI10');
							debugMsg(4,"=Tab-PromptMatch-was-originally-set-to: /", \$prompt->{Match}, "/\n");
						}
					}
					return;
				};
				$key eq $Tab && do { # Tab key but part of pasting or sourcing
					$key = $Space;
				};
				$key eq '?' && $singleChar && $term_io->{SyntaxAcliMode} && do { # ? key, ACLI way
					if ($termbuf->{Linebuf1} =~ /\\$/) { # ? was backslashed
						print $BackSpace;	# delete the backslash, it will be replaced by ? below
						chop $termbuf->{Linebuf1};
						chop $termbuf->{Bufback1};
					}
					else { # ? was not backslashed
						$command = $termbuf->{Linebuf1} . $termbuf->{Linebuf2};
						$term_io->{SourceNoHist} = 1; # So that embedded commands? don't get sent to tied socket
						$history->{Index} = -1;	# As we are not going to call historyAdd, reset history index now (bug17)
						my $pseudoFlag;
						if ( length $command && !$script_io->{AcliControl}) {
							# Command to request syntax for is present, and not an ACLI>cmd and not PseudoTerm
							my $cmdParsed = parseCommand("$command?"); # We append '?' otherwise spaces before '?' would get removed by parseCommand
							$command = $cmdParsed->{command}->{str}; # Make sure we have space re-formatted original; needed for comparison to TabCmdSent below
							chop $command if $command =~ /\?$/; # Without the '?'
							my $aliasOk = $term_io->{AliasEnable} ? deAlias($db, $cmdParsed, undef, 1) : 0;
							return if $host_io->{ConnectionError};
							if (defined $aliasOk && $aliasOk == 0 && !$cmdParsed->{command}->{emb}) { # Make sure we don't have an alias or embedded cmd
								printOut($script_io, '?', $command);
								# We want dictionary syntax to happen before sending same syntax to connected device
								if (defined $term_io->{Dictionary} && dictionaryLookup($db, $cmdParsed, 1)) {
									$termbuf->{SynBellSilent} = 1;
									return if $term_io->{PseudoTerm};
								}
								else {
									$termbuf->{SynBellSilent} = undef;
								}
								if ($term_io->{PseudoTerm}) { # Fall through if pseudo term and no dictionary syntax was valid
									$pseudoFlag = 1;
								}
								else {
									derefVariables($db, $cmdParsed, $cmdParsed->{'command'}, 1); # Deref vars, if any
									my $syntaxSend = $cmdParsed->{command}->{str};
									chop $syntaxSend if $syntaxSend =~ /\?$/; # We remove the '?' we fed into parseCommand above
									$termbuf->{SedInputApplied} = undef;
									if (%{$term_io->{SedInputPats}}) {
										sedPatternReplace($host_io, $term_io->{SedInputPats}, \$syntaxSend);
										$termbuf->{SedInputApplied} = 1;
									}
									if ($syntaxSend =~ /\\/) { # Remove all and any backslashes
										$syntaxSend =~ s/(^|[^\\])\\/$1/g;
										debugMsg(4,"=SynRemovingBackslashes: /", \$syntaxSend, "/\n");
									}
									debugMsg(4,"=Syntax?: /", \$syntaxSend, "/\n");
									$termbuf->{SynCmdMatch} = '';
									if ($TabSynMode{$host_io->{Type}}[$term_io->{AcliType}] & 2) {
										$termbuf->{SynCmdMatch} = quotemeta(substr($syntaxSend, -10));
										debugMsg(4,"=SynCmdMatch-set-to: /", \$termbuf->{SynCmdMatch}, "/\n");
									}
									if ($TabSynMode{$host_io->{Type}}[$term_io->{AcliType}] & 16) {
										$host_io->{SendBuffer} .= $syntaxSend . '?' . $term_io->{Newline};
									}
									else {
										$host_io->{SendBuffer} .= $syntaxSend;
										$host_io->{SendBufferDelay} = '?';
									}
									$termbuf->{TabCmdSent} = $syntaxSend;	# We also need this for syntax
									$termbuf->{TabBefoVar} = $termbuf->{TabCmdSent} ne $command ? $command : undef; # Same here
									$termbuf->{SynMatchSent} = quotemeta($termbuf->{TabCmdSent});
									$termbuf->{Linebuf1} = $command;	# Pre-load buffers with what we already had
									($termbuf->{Bufback1} = $termbuf->{Linebuf1}) =~ s/./\cH/g;
									$termbuf->{Linebuf2} = $termbuf->{Bufback2} = '';
									changeMode($mode, {term_in => 'ib', dev_del => 'fl', dev_fct => 'sx', dev_out => 'bf', buf_out => 'eb'}, '#HTI11');
									return; 
								}
							}
						}
						# If no partial command, i.e. ? alone, or @?, or an alias, then fallback as if ?\n
						$termbuf->{Linebuf2} .= '?';
						$key = $Return	# Fall into next section below
					}
				};
			}
			$key eq $Return && do { # Return key
				$command = $termbuf->{Linebuf1} . $termbuf->{Linebuf2};
				if ($term_io->{HlEnteredCmd} && length $command) { # Make bright commands user typed
					my ($hon, $hoff) = returnHLstrings({bright => 1});
					if ($mode->{term_in} eq 'pw') { # ----------> Password Entry <--------------
						(my $password = $command) =~ s/./*/g;
						print $termbuf->{Bufback1}, $hon, $password, $hoff;
					}
					else {
						print $termbuf->{Bufback1}, $hon, $command, $hoff;
					}
				}
				$termbuf->{Linebuf1} = $termbuf->{Linebuf2} = $termbuf->{Bufback1} = $termbuf->{Bufback2} = '';
				# Below used to be in handleBufferedOutput; but we don't want to reset it if script coming in from socket (tunimx)
				# Instead we want to reset it if user actually interacts with terminal directly
				if ($term_io->{EchoReset}) { # Automatically reset @echo modes on exiting sourcing mode
					$term_io->{EchoOff} = $term_io->{EchoOutputOff} = $term_io->{EchoReset} = 0;
					debugMsg(4,"=entered Return key / disabling EchoOff + deleting CommandCache:\n>", \$host_io->{CommandCache}, "<\n");
					$host_io->{CommandCache} = '';
				}
				last;
			};
			# If none of the special cases above, normal char processing occurs here
			if ($mode->{term_in} eq 'pw') { # ----------> Password Entry <--------------
				print '*';
			}
			else {
				print $key, $termbuf->{Linebuf2}, $termbuf->{Bufback2};
			}
			$termbuf->{Linebuf1} .= $key;
			$termbuf->{Bufback1} .= $BackSpace;
		}
		socketBufferPack($socket_io, $keyBuf, 1) if length $keyBuf; # In 'ps' & 'sh' mode
	}
	return unless defined $command;

	##########################################
	# We have a command line, process it now #
	##########################################
	debugMsg(4,"=LineToProcess: /", \$command, "/\n");
	if ($mode->{term_in} eq 'us' || $mode->{term_in} eq 'pw') { # ------> Username OR Password entry <-----
		$host_io->{Username} = $command if $mode->{term_in} eq 'us';
		$host_io->{Password} = $command if $mode->{term_in} eq 'pw';
		changeMode($mode, {term_in => 'rk', dev_inp => 'lg'}, '#HTI12');
		$host_io->{SendBuffer} = $term_io->{Newline} unless length $command; # If no username or password was entered, feed a carriage return
		return;
	}
	elsif ($mode->{term_in} eq 'tm') { # ----------> Local Term mode <--------------
		if ($script_io->{AcliControl} == 1) {
			historyAdd($history, $command) unless $term_io->{SourceNoHist};
			$term_io->{SourceNoHist} = 0;
			$script_io->{ConnectFailMode} = 2;
			if (processControlCommand($db, $command)) {
				if ($term_io->{PseudoTerm}) { # Pseudo terminal mode
					changeMode($mode, {term_in => 'tm', dev_inp => 'ds', dev_del => 'ds', dev_fct => 'ds', dev_out => 'ub', buf_out => 'ds'}, '#HTI13');
				}
				elsif (!$host_io->{Connected}) { # if reconnect or open command was executed
					print "\n";
					connectToHost($db) or return;
					if ($term_io->{AutoDetect}) {
						changeMode($mode, {term_in => 'rk', dev_inp => 'ct', dev_del => 'ds', dev_fct => 'ds', dev_out => 'ub', buf_out => 'ds'}, '#HTI14');
					}
					else {
						changeMode($mode, {term_in => 'sh', dev_inp => 'ct', dev_del => 'ds', dev_fct => 'ds', dev_out => 'ub', buf_out => 'ds'}, '#HTI15');
					}
				}
				else {
					changeMode($mode, $cacheMode, '#HTI16');	# Restore mode settings
				}
				$script_io->{AcliControl} = 0;
				$script_io->{ConnectFailMode} = 0;
				$history->{Current} = $history->{HostRecall};
				if ($mode->{term_in} eq 'tm') { # Re-display last prompt
					my $output = appendPrompt($host_io, $term_io);
					printOut($script_io, $output, "\n");
				}
			}
			if ($command ne '?' && $command =~ s/\?$//) { # So that we get the command reloaded, without ?, in buffer at next prompt
				print $command;
				$termbuf->{Linebuf1} = $command;
				($termbuf->{Bufback1} = $termbuf->{Linebuf1}) =~ s/./\cH/g;
			}
			return if $host_io->{ConnectionError};
		}
		elsif ($script_io->{AcliControl} & 6) { # Process Annex/Serial selection
			my $retVal;
			$retVal = processTrmSrvSelection($db, $command) if $script_io->{AcliControl} & 2;
			$retVal = processSerialSelection($db, $command) if $script_io->{AcliControl} & 4;
			if ($retVal) {
				$script_io->{ConnectFailMode} = 1;
				connectToHost($db) or return; # No need to check; automatically handled by connectionError
				if ($term_io->{AutoDetect}) {
					changeMode($mode, {term_in => 'rk', dev_inp => 'ct', dev_del => 'ds', dev_fct => 'ds', dev_out => 'ub', buf_out => 'ds'}, '#HTI17');
				}
				else {
					changeMode($mode, {term_in => 'sh', dev_inp => 'ct', dev_del => 'ds', dev_fct => 'ds', dev_out => 'ub', buf_out => 'ds'}, '#HTI18');
				}
				$script_io->{AcliControl} = 0;
				$history->{Current} = $history->{HostRecall};
			}
		}
		elsif ($script_io->{AcliControl} & 8) { # Process @vars prompt
			if (length $command) { # User entered some input
				assignVar($db, $term_io->{VarPromptType}, $term_io->{VarPrompt}, '=', quotesRemove($command), $term_io->{VarPromptKoi});
				releaseInputBuffer($term_io); # In case we were sourcing
			}
			elsif ($term_io->{VarPromptOpt}) { # User hit enter with no input and we accept optional input
				assignVar($db, $term_io->{VarPromptType}, $term_io->{VarPrompt}, '=', '', $term_io->{VarPromptKoi});
				releaseInputBuffer($term_io); # In case we were sourcing
			}
			$term_io->{VarPrompt} = undef;
			$script_io->{AcliControl} = 0;
			printOut($script_io, "\n");
			$host_io->{OutBuffer} .= $host_io->{Prompt};
			changeMode($mode, {term_in => 'ps', dev_out => 'bf', buf_out => 'eb'}, '#HTI19');
		}
		else { # Normal connection mode
			printOut($script_io, undef, $command) unless $term_io->{EchoOff} && $term_io->{Sourcing}; # Send to log file, if logging
			if ($socket_io->{TieEchoMode}) { # Don't check for $socket_io->{Tie}, as socket ping can be done on listening terminals
				$socket_io->{GrepRecycle} = $socket_io->{SummaryCount} = 0; # Always reset these; embedded cmds which need them will set it themselves
				$socket_io->{EchoOutCounter} = undef;
			}
			if ($socket_io->{ListenEchoMode}) { # Reset storage keys which will be used to construct echo responses
				$socket_io->{LastLine} = '';
			}
			# Section where to reset variables needed for either device output or embedded commands
			$host_io->{SyntaxError} = 0;
			$host_io->{SendMasterCP} = 1; # Set these defaults; they might get changed in processLocalOptions() below
			$host_io->{SendBackupCP} = 0; # "
			$host_io->{GrepCache} = '';
			$term_io->{CmdOutputLines} = 0;
			$term_io->{RecordsMatched} = $term_io->{RecordCountFlag} = 0;
			$term_io->{BannerDetected} = 1;	# Set this for var capture processing on output
			($term_io->{BannerCacheLine}, $term_io->{BannerEmptyLine}) = ('', 0);
			$term_io->{DelayPrompt} = undef;
			$term_io->{HLgrep} = undef;
			if ($socket_io->{ListenEchoMode}) {
				$socket_io->{EchoSendFlag} = 1; # Next command will be the one sent by tied socket if ListenEchoMode set
				debugMsg(4,"=EchoSendFlag set\n");
			}

			if (length $command && $command !~ /^\s+$/) {
				my $cmdParsed = parseCommand($command);
				bangHistory($db, $cmdParsed) or return;
				debugMsg(4,"=Full Command after bangHistory: /", \$cmdParsed->{fullcmd}, "/\n");

				unless ($term_io->{SourceNoHist}) { # Only for commands actually entered by user
					# If we have sockets enabled, set the command here; it will be sent if we have a tied socket
					if ($term_io->{SocketEnable}) {
						socketBufferPack($socket_io, $cmdParsed->{fullcmd}."\n", $term_io->{YnPrompt} eq 'y' ? 3 : 2);
						# We use $cmdParsed->{fullcmd} and not $command, because if command was !!, we want the result of bangHistory to be used
					}
					# Add to history here
					historyAdd($history, $cmdParsed->{fullcmd});
					# We use $cmdParsed->{fullcmd} and not $command, because if command was !!, we want the result of bangHistory to be used
				}

				my %aliasTrail = (); # Init to empty hash; used to detect and prevent alias dereferencing loops
				my $dictionaryLookup; # Allow only a single dictionary lookup in below loop
				my $dictFlushed; # Keep track if pasted dictionary command was printed in @echo sent mode
				CMDPROC:{
					$cmdParsed->{command}->{str} = '' if $cmdParsed->{command}->{str} =~ /^\s*;/;	# Treat ';' as a local comment line, not sent to host
					unless (exists $cmdParsed->{semicln}) {
						processRepeatOptions($db, $cmdParsed) or return;
						debugMsg(4,"=Device Command after semicln processRepeatOptions: /", \$cmdParsed->{command}->{str}, "/\n");
					}
					semicolonFragment($db, $cmdParsed, $dictFlushed) or return;
					debugMsg(4,"=Device Command after semicolonFragment: /", \$cmdParsed->{command}->{str}, "/\n");
					# We should now continue with just the 1st command in the ; list

					processRepeatOptions($db, $cmdParsed) or return;
					debugMsg(4,"=Device Command after regular processRepeatOptions: /", \$cmdParsed->{command}->{str}, "/\n");

					if (inputBufferIsVoid($db)) { # This needs to be after processRepeatOptions
						$term_io->{SourceNoHist} = 0;
						$term_io->{SourceNoAlias} = 0;
					}

					derefVariables($db, $cmdParsed, $cmdParsed->{'command'}, 0, $cmdParsed->{'command'}->{emb} eq '@printf');
					debugMsg(4,"=Device Command after derefVariables: /", \$cmdParsed->{command}->{str}, "/\n");
					echoVarReplacement($db, $cmdParsed); # Display variable replacements

					if ($term_io->{AliasEnable} && !$term_io->{SourceNoAlias}) {
						my $ok = deAlias($db, $cmdParsed, \%aliasTrail);
						return unless defined $ok;
						if ($ok) { # An alias was resolved
							debugMsg(4,"=Full Command after deAlias (retval = 1): /", \$cmdParsed->{fullcmd}, "/\n");
							redo CMDPROC;
						}
					}
					if (defined $term_io->{Dictionary} && !$dictionaryLookup && !$term_io->{SourceActive}->{dict}) {
						my $ok = dictionaryLookup($db, $cmdParsed);
						if ($ok) { # A dictionary lookup was resolved
							debugMsg(4,"=Full Command after dictionaryLookup (retval = 1): /", \$cmdParsed->{fullcmd}, "/\n");
							$dictionaryLookup = 1; # Make sure we don't come back here
							if ($term_io->{EchoOff} == 2) { # Echo mode "sent"
								if (length $host_io->{CommandCache}) { # and dictionary command was pasted/sourced
									printOut($script_io, $host_io->{CommandCache});
									debugMsg(4,"=flushing CommandCache - echo sent - dict command:\n>", \$host_io->{CommandCache}, "<\n");
									$host_io->{CommandCache} = '';
									$dictFlushed = 1;
								}
							}
							redo CMDPROC;
						}
						return if defined $ok; # This only applies to &ignore
					}
				} # CMDPROC
				return if $host_io->{ConnectionError};

				processLocalOptions($db, $cmdParsed) or return;
				debugMsg(4,"=Command after processLocalOptions: /", \$cmdParsed->{command}->{str}, "/\n");

				echoVarReplacement($db, $cmdParsed); # Display variable replacements
				$command = $cmdParsed->{command}->{str}; # Copy over now

				applyFeedInputs($db, $command) unless $term_io->{FeedInputs}; # Restore FeedInputs if any were cached for the current command

				if (my $embCmd = processEmbeddedCommand($db, $command) ) {
					# Need to get locally generated output into delta buffer for socket echo modes
					$host_io->{DeltaBuffer} = $host_io->{OutBuffer} if $socket_io->{EchoSendFlag};
					if ($embCmd eq '@acli') { # @acli was the embedded command
						$history->{Current} = $history->{ACLI};
						$termbuf->{Linebuf1} = $termbuf->{Linebuf2} = $termbuf->{Bufback1} = $termbuf->{Bufback2} = '';
						%$cacheMode = %$mode;	# Cache mode settings
						changeMode($mode, {term_in => 'tm', dev_inp => 'ds', buf_out => 'ds'}, '#HTI20');
					}
					elsif ($embCmd eq '@rediscover') { # @rediscover was the embedded command
						$host_io->{SendBuffer} .= $term_io->{Newline} unless $host_io->{Console}; # On console we automatically send wake_console (bug22)
						changeMode($mode, {term_in => 'rk', dev_inp => 'lg'}, '#HTI21');
					}
					elsif ($embCmd eq '@varsprompt') { # @vars prompt was the embedded command
						$script_io->{AcliControl} = 8;
						$term_io->{VarPromptSrcing} = $term_io->{Sourcing}; # Cache sourcing mode, as it will get disabled in saveInputBuffer
						saveInputBuffer($term_io); # In case we were sourcing
					}
					elsif ($embCmd eq '@sleep') { # @sleep was the embedded command
						changeMode($mode, {dev_out => 'bf', buf_out => 'eb'}, '#HTI22');
					}
					elsif ($embCmd eq '@read') { # @read was the embedded command
						changeMode($mode, {term_in => 'ps', dev_inp => 'rd', dev_out => 'bf', buf_out => 'eb'}, '#HTI23');
					}
					elsif ($embCmd eq '@read unbuffer') { # @read was the embedded command
						changeMode($mode, {term_in => 'ps', dev_inp => 'rd', dev_out => 'ub', buf_out => 'ds'}, '#HTI24');
					}
					else { # Any other embedded command
						if ($command ne '@?' && $command =~ s/\?$//) { # So that we get the command reloaded, without ?, in buffer at next prompt
							if ($embCmd eq '@run') {
								$term_io->{RunSyntax} = $command;
							}
							else {
								$termbuf->{Linebuf1} = $command;
								($termbuf->{Bufback1} = $termbuf->{Linebuf1}) =~ s/./\cH/g;
							}
						}
						changeMode($mode, {term_in => 'ps', dev_out => 'bf', buf_out => 'eb'}, '#HTI25');
					}
					$term_io->{BannerDetected} = 0;	# No output banner processing for embedded commands
					undef $command;
				}
				return if $host_io->{ConnectionError};
				return unless defined $command;

				if ($term_io->{PseudoTerm} && $term_io->{Sourcing} && defined $term_io->{Dictionary} && !$term_io->{DictSourcing} && !($dictionaryLookup || $term_io->{SourceActive}->{dict})) {
					printOut($script_io, "\nPseudo mode sourcing with dictionary loaded, but command was not dictionary translated!\n");
					stopSourcing($db);
					printOut($script_io, "\n");
					$host_io->{OutBuffer} .= $host_io->{Prompt};
					debugMsg(4,"=Pseudo mode dictionary loaded; stopping source mode as not a dictionary command\n");
					changeMode($mode, {dev_out => 'bf', buf_out => 'eb'}, '#HTI26');
					return;
				}

				# SLX "do" processing; SLX is a pain in that it enforces no show commands in config mode, unless "do" appended to them
				# Other devices (e.g. ISW) are quite happy to process "do" even outside of config context; but SLX no, it won't
				if ($term_io->{AcliType} && $host_io->{Prompt} !~ /[\/\(]config/ && $command =~ /^\s*do +\S/) {
					$command =~ s/^(\s*)do +/$1/;
					debugMsg(4,"=Command after SLX 'do' remove processing: /", \$command, "/\n");
				}

				if ($term_io->{EchoOff} == 2 && length $host_io->{CommandCache}) { # Echo mode "sent"
					printOut($script_io, $host_io->{CommandCache});
					debugMsg(4,"=flushing CommandCache - echo sent - real command:\n>", \$host_io->{CommandCache}, "<\n");
					$host_io->{CommandCache} = '';
				}

				# This is where we apply sed input patterns; after all interactive input processing and just before sending
				sedPatternReplace($host_io, $term_io->{SedInputPats}, \$command) if %{$term_io->{SedInputPats}};

				# If we get here, $command is what will be sent to the host; add to history of device-sent commands
				push(@{$history->{DeviceSent}}, $command);
				push(@{$history->{DeviceSentNoErr}}, $command);
				$host_io->{LastCommand} = (split ' ', $command)[0] || ''; # Store 1st command
				$host_io->{LastCommand} = 'telnet' if $host_io->{LastCommand} =~ /^tel(?:n(?:et?)?)?$/;
				$host_io->{LastCommand} = 'ssh' if $host_io->{LastCommand} =~ /^ssh?$/;
				$host_io->{LastCommand} = 'peer' if $host_io->{LastCommand} =~ /^pe(?:er?)?$/;
			}
			if ($term_io->{PseudoTerm}) { # Special case of empty command in Pseudo Terminal mode
				printOut($script_io, "\nCommand = $command") if length $command && $term_io->{PseudoTermEcho};
				printOut($script_io, "\n") unless $term_io->{EchoOff} == 1 && $term_io->{Sourcing};
				$host_io->{OutBuffer} .= $host_io->{Prompt};
				changeMode($mode, {dev_out => 'bf', buf_out => 'eb'}, '#HTI27');
				return;
			}
			# Else we send the command to the host
			unless ($term_io->{AcliType} && $command =~ /^.*\?$/) { # Add carriage return unless a '?' in ACLI mode
				$command .= $term_io->{Newline};
			}
			# Section where to reset variables handling device output
			$host_io->{SendBuffer} .= $command;
			$host_io->{OutputSinceCmd} = 0;
			($term_io->{DelayCharProcPs}, $term_io->{DelayCharProcDF}) = (Time::HiRes::time + $DelayCharProcPs, 1);
			debugMsg(4,"=Set DelayCharProcPs expiry time = ", \$term_io->{DelayCharProcPs}, "\n");
			$term_io->{BufMoreAction} = defined $MoreSkipWithin{$host_io->{Type}} && !$host_io->{Console} ? $MoreSkipWithin{$host_io->{Type}} : $Space;
			$host_io->{LastCmdError} = $host_io->{LastCmdErrorRaw} = undef; # Clear $@ variable
			debugMsg(4,"=Command Final: /", \$command, "/\n");
			if( 	defined $ChangePromptCmds{$host_io->{Type}} &&
				(	$host_io->{Type} eq 'WLAN2300' || $host_io->{Type} eq 'Series200' || # On these is set in PrivExec mode
					($term_io->{AcliType} && $host_io->{Prompt} =~ /[\/\(]conf/) || # On ISWmarvell the config prompt is (conf), not (config)
					(!$term_io->{AcliType} && ($host_io->{Prompt} =~ /[\/\(]config/ || $command =~ /^\s*con/i))
				) && ( $command =~ /$ChangePromptCmds{$host_io->{Type}}/i ) ) {

				# This command will change the device prompt
				changeMode($mode, {term_in => 'rk', dev_inp => 'cp'}, '#HTI28');
			}
			else { # No prompt change expected
				changeMode($mode, {term_in => 'ps', dev_inp => 'rd', dev_del => 'fl', dev_out => 'bf', buf_out => 'eb'}, '#HTI29');
			}
			changeMode($mode, {dev_fct => 'yp'}, '#HTI30') if $term_io->{YnPrompt};
		}
	}
	elsif ($mode->{term_in} eq 'sh') { # ------------> Send to Host mode <-------------
		# We get here during transparent mode pasting ... I think
		$host_io->{SendBuffer} .= $command;

		# If we have sockets enabled, set the command here; it will be sent if we have a tied socket
		socketBufferPack($socket_io, $command, 4) if $term_io->{SocketEnable};
	}
	else {
		quit(1, "ERROR: unexpected term_in mode: ".$mode->{term_in}, $db);
	}
}

1;
