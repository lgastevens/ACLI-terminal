# ACLI sub-module
package AcliPm::Socket;
our $Version = "1.06";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(multicastIp saveSocketNames loadSocketNames socketList openSockets closeSockets socketBufferPack
			 tieSocketEcho tieSocket untieSocket socketEchoBuffer socketEchoBufferDisconnect wipeEchoBuffers
			 handleSocketIO);
}
use Control::CLI::Extreme qw(stripLastLine);
use IO::Socket;
use IO::Socket::Multicast;
use IO::Select;
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::DebugMessage;
use AcliPm::Error;
use AcliPm::GlobalDefaults;
use AcliPm::Prompt;
use AcliPm::Sourcing;
use AcliPm::Variables;


sub multicastIp { # Checks whether IP address is a valid IP Multicast Group address
	my $ip = shift;
	return unless $ip =~ /^\d+\.\d+\.\d+\.\d+$/;
	my @byte = split('\.', $ip);
	return if $byte[0] < 224 || $byte[0] > 239;
	return if $byte[1] > 255;
	return if $byte[2] > 255;
	return if $byte[3] > 255;
	return if $byte[1] + $byte[2] + $byte[3] == 0;
	return 1;
}


sub saveSocketNames { # Save and update the socket file where names are mapped to numbers
	my $socket_io = shift;

	unless (-e $AcliFilePath[0] && -d $AcliFilePath[0]) { # Create base directory if not existing
		mkdir $AcliFilePath[0] or return;
		debugMsg(1, "SocketFileSave: Created directory: ", \$AcliFilePath[0], "\n");
	}
	my $socketFile = join('', $AcliFilePath[0], '/', $SocketFileName);
	$socket_io->{SocketFile} = File::Spec->canonpath($socketFile); # Update display path

	# We should have a socket file to work with now

	debugMsg(1, "SocketFileSave: Saving file:\n ", \$socketFile, "\n");

	open(SOCKFILE, '>', $socketFile) or return;
	flock(SOCKFILE, 2); # 2 = LOCK_EX; Put an exclusive lock on the file as we are modifying it
	my $timestamp = localtime;
	print SOCKFILE "# $ScriptName saved on $timestamp\n";
	foreach my $sock (sort { $socket_io->{Port}->{$a} <=> $socket_io->{Port}->{$b} } keys %{$socket_io->{Port}}) {
		printf SOCKFILE "%-10s	%s\n", $sock, $socket_io->{Port}->{$sock};
	}
	close SOCKFILE;
	return 1;
}


sub loadSocketNames { # Load socket file which maps names to numbers
	my $socket_io = shift;
	my $socketFile;

	$socket_io->{Port} = $Default{socket_names_val}; # Reset to defaults the socket name cache

	# Try and find a matching socket file in the paths available
	foreach my $path (@AcliFilePath) {
		if (-e "$path/$SocketFileName") {
			$socketFile = "$path/$SocketFileName";
			last;
		}
	}
	unless ($socketFile) {
		$socket_io->{SocketFile} = '';
		return;
	}

	$socket_io->{SocketFile} = File::Spec->canonpath($socketFile); # Update display path
	# We should have a socket file to work with now
	debugMsg(1, "SocketFileRead: Loading file: ", \$socketFile, "\n");

	# Read in socket names
	my $lineNumber = 0;
	open(SOCKFILE, '<', $socketFile) or return;
	flock(SOCKFILE, 1); # 1 = LOCK_SH; Put a shared lock on the file (wait to read if it's being changed)
	while (<SOCKFILE>) {
		chomp;
		$lineNumber++;
		next if /^\s*$/; # skip empty lines
		next if /^\s*#/; # skip comment lines
		/^\s*(\S+)\s+(\d+)\s*$/ && do {
			$socket_io->{Port}->{lc $1} = $2;
			next;
		};
		# We just skip lines we don't like!
	}
	close SOCKFILE;
	return 1;
}


sub allocateSocketNumber { # Allocate next available socket number for the supplied socket name
	my ($socket_io, $name) = @_;
	$name = lc $name; # Only use lowercase for socket names
	my $number;

	foreach my $n (sort {$a <=> $b } values %{$socket_io->{Port}}) {
		debugMsg(1,"AllocateSocketNumber for $name: iterating $n\n");
		unless (defined $number) { # Lock onto 1st number
			$number = $n;
			next;
		}
		if (++$number < $n) { # We found a gap in the numbers, we take it
			$socket_io->{Port}->{$name} = $number;
			debugMsg(1,"AllocateSocketNumber for $name: found unused $number\n");
			return $number;
		}
	}
	# No gap in already allocated numbers; so take next number
	$socket_io->{Port}->{$name} = ++$number;
	debugMsg(1,"AllocateSocketNumber for $name: next available $number\n");
	return $number;
}


sub socketLookup { # Return the numerical UDP port number corresponding to a socket name 
	my ($socket_io, $socketName) = @_;
	return $1 if $socketName =~ /^%(\d+)$/;	# If number preceded by "%" we use raw number
	return $socket_io->{Port}->{lc $socketName};
}


sub socketList { # Make a list of sockets with number in brackets if a name provided
	my ($socket_io, @inSocks) = @_;
	my $string = '';
	return $string unless @inSocks && defined $inSocks[0];

	foreach my $sock (sort {$a cmp $b} @inSocks) {
		next unless defined $sock;
		$string .= $sock;
		$string .= '(' . socketLookup($socket_io, $sock) . ')';
		$string .= ',';
	}
	chop $string; # Remove last comma
	return $string;
}


sub multipleSocketLookup { # Return the list of numerical UDP port numbers corresponding to a socket names
			   # For unknown socket names, new port numbers are allocated
	my ($socket_io, @socketNames) = @_;
	my (@socketNumbers, $socketFileLoaded, $socketNumbersAllocated, $number);

	foreach my $name (@socketNames) {
		if ($number = socketLookup($socket_io, $name)) { # Try if we have it already cached
			debugMsg(1,"MultipleSocketLookup: $name = $number\n");
			push(@socketNumbers, $number);
			next;
		}
		if (!$socketFileLoaded) { # If we haven't already loaded the socket file
			debugMsg(1,"MultipleSocketLookup: Try loading socket file\n");
			$socketFileLoaded = 1; # We only do this once
			loadSocketNames($socket_io);
			redo; # Repeat cycle again, whether or not we loaded the file
		}
		else { # We allocate a number our selves
			$number = allocateSocketNumber($socket_io, $name);
			debugMsg(1,"MultipleSocketLookup: Allocate socket $name = $number\n");
			$socketNumbersAllocated = 1;
			push(@socketNumbers, $number);
		}
	}
	if ($socketNumbersAllocated) { # If we did allocate some socket numbers, then a new socket file must be created
		saveSocketNames($socket_io) or return;	# Save the socket file
	}
	return @socketNumbers;
}


sub openSockets { # Open list of socket names so that this terminal can take user input from them
		  # Return values: 1 + empty list = ok; 1 + list = failed sockets; undef = unable to allocate socket numbers
	my ($socket_io, @sockNames) = @_;
	@sockNames = keys %{$socket_io->{ListenSockets}} unless @sockNames;
	my @sockNumbers = multipleSocketLookup($socket_io, @sockNames) or return;
	my @failedSockets = ();

	for my $i (0 .. $#sockNames) {
		next if defined $socket_io->{ListenSockets}->{$sockNames[$i]}; # If already open, skip it
		debugMsg(1,"OpenSockets: creating rx socket $sockNames[$i] - $sockNumbers[$i] - udp\n");
		my $sock = IO::Socket::Multicast->new(
			LocalAddr	=> $^O eq 'MSWin32' ? undef : $socket_io->{SendIP}, # On MACOS ensures source IP is 127.0.0.1
			LocalPort	=> $sockNumbers[$i],
			Proto		=> 'udp',
			ReuseAddr	=> 1,
		) or do {
			debugMsg(1,"OpenSockets: failed to create socket $sockNames[$i]\n");
			push(@failedSockets, $sockNames[$i]);
			next;
		};
		$sock->mcast_add($socket_io->{SendIP}, $socket_io->{BindLocalAddr}); # Join multicast IP + Bind to interface
		$socket_io->{ListenSockets}->{$sockNames[$i]} = $sock;
		debugMsg(1,"OpenSockets: created socket : ", \$sock, "\n");
	}
	$socket_io->{ListenSelect} = new IO::Select() unless defined $socket_io->{ListenSelect};
	$socket_io->{ListenSelect}->add(values %{$socket_io->{ListenSockets}});
	return (1, @failedSockets);
}


sub closeSockets { # Close all listening sockets or list provided
	my ($socket_io, $delete, @sockNames) = @_;
	@sockNames = keys %{$socket_io->{ListenSockets}} unless @sockNames;
	foreach my $sock (@sockNames) {
		if ($socket_io->{ListenSockets}->{$sock}) { # If the listening socket exists..
			debugMsg(1,"CloseSockets: destroying socket $sock\n");
			$socket_io->{ListenSelect}->remove($socket_io->{ListenSockets}->{$sock}); # (bug3) need to remove socket before shutting it down
			$socket_io->{ListenSockets}->{$sock}->shutdown(2); # I/we have stopped using this socket
			$socket_io->{ListenSockets}->{$sock}->close;	   # Close after shutdown, to clear the filehandle
			undef $socket_io->{ListenSockets}->{$sock};
			delete($socket_io->{ListenSockets}->{$sock}) if $delete;
		}
	}
	if (defined $socket_io->{ListenSelect} && !scalar $socket_io->{ListenSelect}->handles) { # If we closed them all
		debugMsg(1,"CloseSockets: undefining ListenSelect object\n");
		$socket_io->{ListenSelect} = undef;
		# Check for open echo sockets
		if ($socket_io->{EchoSocket}) { # An echo socket is open, close it
			debugMsg(1,"CloseSockets: destroying echo socket", \$socket_io->{EchoSocket}, "\n");
			$socket_io->{EchoSocket}->shutdown(2);    # I/we have stopped using this socket
			$socket_io->{EchoSocket}->close; # Close after shutdown, to clear the filehandle
			$socket_io->{EchoSocket} = $socket_io->{EchoDstPort} = $socket_io->{EchoDstIP} = undef;
		}
	}
}


sub socketBufferPack { # Packing of commands into datagrams
	my ($socket_io, $command, $mode) = @_;
	return unless $socket_io->{Tie};
	my $overhead = ($mode & 2) ? 3 : 1;
	$overhead += length($AcliUsername) + 1 if $socket_io->{SendUsername};
	if (length $command >= $SocketMaxMsgLen - $overhead) { # Won't fit in one datagram..
		$command = substr($command, 0, $SocketMaxMsgLen - $overhead, ''); # Take 1st 1024 bytes minus the overhead
		debugMsg(4,"=socketBufferPack: Giant command! Truncated to 1021 bytes!!\n");
	}
	$socket_io->{SendBuffer} = $command;
	if ($mode & 2) { # Modes 2 & 3 & 6 carry the EchoMode & SocketPort to use
		# If echo mode 'error' or 'all', pack the TieRxSocket port number into the message
		$socket_io->{SendBuffer} .= pack("n", $socket_io->{TieRxLocalPort}) if $socket_io->{TieEchoMode} && defined $socket_io->{TieRxLocalPort};
		$mode += $socket_io->{TieEchoMode} * 16; # Also include the Echo mode into the mode byte
	}
	if ($socket_io->{SendUsername}) { # We need to pack the username inside the datagram
		$socket_io->{SendBuffer} .= $AcliUsername;
		$socket_io->{SendBuffer} .= pack("C", length($AcliUsername)); # Also pack the username length as 1 byte
		$mode |= 128;
	}
	$socket_io->{SendBuffer} .= pack("C", $mode); # Pack the mode as last byte of message
	$socket_io->{TiedSentFlag} = 1;
	# Encoding of last byte, bits: UxEE xMMM
	# x = unused bits
	# U = Flag indicating username encoded
	# EE = Echo mode bits (values 0,1,2)
	# MMM = Data Mode bits (values 0-6)
}


sub socketBufferUnpack { # Unpacking of commands from datagrams
	my ($socket_io, $dataRef) = @_;
	my $lastByte = ord(chop($$dataRef)); # Strip the mode byte
	my $mode = $lastByte & 15;	# Last nibble is mode value
	if ($lastByte & 128) { # Username encoding is in MSB of last byte
		my $usernameLen = ord(chop($$dataRef));
		my $username = substr($$dataRef, -$usernameLen, $usernameLen, ''); # Remove last $usernameLen bytes
		debugMsg(4,"=socketBufferUnpack: Recovered username = ", \$username, "\n");
		if ($username ne $AcliUsername) {
			debugMsg(4,"=socketBufferUnpack: Username encoded and not matching: ", \$username, ". Not for us!\n");
			return;
		}
	}
	if ($mode & 2) { # Modes 2 & 3 & 6 carry the EchoMode & SocketPort to use
		$socket_io->{ListenEchoMode} = ($lastByte & 48) / 16; # Store echo mode
		debugMsg(4,"=socketBufferUnpack: Recovered Echo mode = ", \$socket_io->{ListenEchoMode}, "\n");
		if ($socket_io->{ListenEchoMode}) { # If echo mode 'error' or 'all', recover the TieRxSocket port number
			$socket_io->{ListenTieRxPort} = ord(chop($$dataRef)) + ord(chop($$dataRef))*256;
			debugMsg(4,"=socketBufferUnpack: Recovered Tie Rx Socket port = ", \$socket_io->{ListenTieRxPort}, "\n");
			# Reset storage keys which will be used to construct echo responses
			$socket_io->{EchoSeqNumb} = 0;
		}
	}
	return $mode; # Return mode value
}


sub tieSocketEcho { # Setup or tear down a receive socket on tied port, if echo mode requires it
	my $socket_io = shift;
	if ($socket_io->{TieEchoMode} && !defined $socket_io->{TieRxSocket}) { # Echo modes error & all, and socket not already in place
		# Socket is created only to receive but we want it to allocate next available socket port number
		$socket_io->{TieRxSocket} = IO::Socket::INET->new(
				LocalPort	=> 0, # Allocate a dynamic port: https://www.lifewire.com/port-0-in-tcp-and-udp-818145
				Proto		=> 'udp',
				LocalAddr	=> $socket_io->{BindLocalAddr},
			) or do {
				$socket_io->{TieEchoMode} = 0; # If we fail to set it up, set mode to none
				return;
			};
		$socket_io->{TieRxLocalPort} = $socket_io->{TieRxSocket}->sockport;
		debugMsg(1,"TieSocketEcho: created Tied Echo mode RX socket on port : ", \$socket_io->{TieRxLocalPort}, "\n");
		$socket_io->{TieRxSelect} = new IO::Select($socket_io->{TieRxSocket});
	}
	elsif (!$socket_io->{TieEchoMode} && defined $socket_io->{TieRxSocket}) { # No echo mode set, but a socket in place, tear it down
		debugMsg(1,"TieSocketEcho: destroying Tied Echo mode RX socket\n");
		$socket_io->{TieRxSocket}->shutdown(2);	# I/we have stopped using this socket
		$socket_io->{TieRxSocket}->close;	# Close after shutdown, to clear the filehandle
		$socket_io->{TieRxSocket} = $socket_io->{TieRxLocalPort} = $socket_io->{TieRxSelect} = undef;
	}
	return 1;
}


sub tieSocket { # Tie this terminal to a socket so that any terminal input from this instance is sent to other instances
	my ($socket_io, $sockName, $doNotLiven) = @_;
	my $sockNumber;
	$sockNumber = socketLookup($socket_io, $sockName) or do {
		debugMsg(1,"TieSocket: Try loading socket file\n");
		loadSocketNames($socket_io); # Try reloading the socket file
		$sockNumber = socketLookup($socket_io, $sockName) or do {
			debugMsg(1,"TieSocket: Unable to obtain socket number for name ", \$sockName, "\n");
			return;
		}
	};

	debugMsg(1,"TieSocket: creating tx socket $sockName - $sockNumber - $socket_io->{SendIP} - udp\n");
	$socket_io->{TieTxSocket} = IO::Socket::Multicast->new(
			PeerAddr	=> $socket_io->{SendIP} . ':' . $sockNumber,
			Proto		=> 'udp',
			LocalAddr	=> $socket_io->{BindLocalAddr},
		) or return;
	$socket_io->{TieTxSocket}->mcast_if($socket_io->{BindLocalAddr});
	$socket_io->{TieTxSocket}->mcast_ttl($socket_io->{IPTTL});

	$socket_io->{Tie} = $sockName;
	$socket_io->{TieTxLocalPort} = $socket_io->{TieTxSocket}->sockport;
	debugMsg(1,"TieSocket: local socket port number: ", \$socket_io->{TieTxLocalPort}, "\n");
	socketBufferPack($socket_io, "\n", 2) unless $doNotLiven; # Force immediately a new prompt on all listening terminals
	return 1;
}


sub untieSocketEcho { # Untie the echo mode sockets on the tied terminal
	my $socket_io = shift;
	if (defined $socket_io->{TieRxSocket}) { # Echo mode socket in place, tear it down
		$socket_io->{TieRxSocket}->shutdown(2);	# I/we have stopped using this socket
		$socket_io->{TieRxSocket}->close;	# Close after shutdown, to clear the filehandle
		$socket_io->{TieRxSocket} = $socket_io->{TieRxSelect} = undef;
	}
}


sub untieSocket { # Untie this terminal from any socket
	my ($socket_io, $keepEchoSock) = @_;
	return unless defined $socket_io->{Tie};
	debugMsg(1,"UntieSocket: destroying socket $socket_io->{Tie}\n");
	$socket_io->{TieTxSocket}->shutdown(2);    # I/we have stopped using this socket
	$socket_io->{TieTxSocket}->close; # Close after shutdown, to clear the filehandle
	$socket_io->{Tie} = $socket_io->{TieTxSocket} = $socket_io->{TieTxLocalPort} = undef;
	untieSocketEcho($socket_io) unless $keepEchoSock; # If echo mode socket in place, tear it down
}


sub socketEchoSetup { # Checks whether the listening socket echo is in place or needs setting up
	my $socket_io = shift;

	if ($socket_io->{EchoSocket}) { # An echo socket is already open
		if ($socket_io->{ListenTieRxPort} != $socket_io->{EchoDstPort} || $socket_io->{ListenSrcIP} ne $socket_io->{EchoDstIP}) {
			# The open socket is to a different tied terminal; close that socket
			debugMsg(1,"=socketEchoSetup: destroying old echo socket", \$socket_io->{EchoSocket}, "\n");
			$socket_io->{EchoSocket}->shutdown(2);    # I/we have stopped using this socket
			$socket_io->{EchoSocket}->close; # Close after shutdown, to clear the filehandle
			$socket_io->{EchoSocket} = $socket_io->{EchoDstPort} = $socket_io->{EchoDstIP} = undef;
		}
	}
	unless ($socket_io->{EchoSocket}) { # No echo socket open, we open it
		debugMsg(1,"=socketEchoSetup: creating tx socket - $socket_io->{ListenTieRxPort} - $socket_io->{ListenSrcIP} - udp\n");
		$socket_io->{EchoSocket} = IO::Socket::INET->new(
				PeerAddr	=> $socket_io->{ListenSrcIP},
				PeerPort	=> $socket_io->{ListenTieRxPort},
				Proto		=> 'udp',
			) or return;
		($socket_io->{EchoDstPort}, $socket_io->{EchoDstIP}) = ($socket_io->{ListenTieRxPort}, $socket_io->{ListenSrcIP});
		debugMsg(1,"=socketEchoSetup: echo socket opened: ", \$socket_io->{EchoSocket}, "\n");
	}
	return 1;
}


sub socketEchoBuffer { # Checks whether need to buffer some echo output
	my ($db, $socket_io, $prompt) = @_;
	my $host_io = $db->[3];

	if ($socket_io->{EchoSeqNumb} >= 128) { # Command was completed; send nothing further until next command from controlling terminal
		debugMsg(2,"SocketEchoBuffer-seq>128 = ", \$socket_io->{EchoSeqNumb}, " suppressing\n");
		$host_io->{DeltaBuffer} = '';	# Need to keep flushing this
		return;
	}

	$socket_io->{OutBuffer} .= $socket_io->{LastLine} . $host_io->{DeltaBuffer};
	$host_io->{DeltaBuffer} = '';
	debugMsg(2,"SocketEchoBuffer-outBuffer\n>", \$socket_io->{OutBuffer}, "<\n");

	$socket_io->{LastLine} = stripLastLine(\$socket_io->{OutBuffer}) || ''; # Strip last line if any..
	$socket_io->{CmdComplete} = checkForPrompt($host_io, \$socket_io->{LastLine}, $prompt); # If a prompt we have all the output now
	$socket_io->{LastLine} = '' if $socket_io->{CmdComplete}; # No need to keep it if it was a prompt
	debugMsg(2,"SocketEchoBuffer-CmdComplete\n") if $socket_io->{CmdComplete};
	debugMsg(2,"SocketEchoBuffer-LastLine: >", \$socket_io->{LastLine}, "<\n") if length $socket_io->{LastLine};

	return unless length $socket_io->{OutBuffer};	# No output to process

	if ($socket_io->{ListenEchoMode} == 1) { # In 'error' mode only
		if (!$host_io->{SyntaxError} && errorDetected($db, \$socket_io->{OutBuffer}, 1) ) {
			$host_io->{SyntaxError} = 1;
			debugMsg(2,"SocketEchoBuffer-errormode-seen Syntax Error\n");
			$socket_io->{OutBuffer} =~ s/$CTRL_G//go;# Strip all bell characters from output
		}
		unless ($host_io->{SyntaxError}) { # No error; reset the buffer and queue nothing
			$socket_io->{OutBuffer} = '';
			return;
		}
	}
	# If we get here, we are going to send something

	if ($socket_io->{EchoSeqNumb} == 0) { # This is the 1st datagram we send for this command
		# Pre-pend a line telling which switch the output belongs to
		$socket_io->{OutBuffer} = join('',
						"\n",
						$socket_io->{ListenEchoMode} == 1 ? "Error":"Output",
						" from ",
						switchname($host_io, 1),
						":\n",
						$socket_io->{OutBuffer});
	}
	# Packet fragmentation is now handled directly under socketEchoSend, as this gets called at every cycle
	# (whereas this sub is only called when new output is available)
	return;
}


sub socketEchoBufferDisconnect { # Sends an echo message to controlling terminal indicating that this terminal has lost the connection
	my ($host_io, $socket_io) = @_;

	$socket_io->{SendBuffer} = "\nConnection lost on " . switchname($host_io, 1) . "\n\n";
	# Set sequence number & final flag for datagram
	$socket_io->{EchoSeqNumb} = ++$socket_io->{EchoSeqNumb} & 127;	# Increase sequence number (on 7 bits 1-127)
	$socket_io->{EchoSeqNumb}++ if $socket_io->{EchoSeqNumb} == 0; # Skip 0 on roll over (otherwise we prepend again above)
	$socket_io->{EchoSeqNumb} |= 128;	# Set bit 8 on final datagram
	$socket_io->{SendBuffer} .= pack("C", $socket_io->{EchoSeqNumb});	# Append to message
	debugMsg(2,"SocketEchoBufferDisconnect-datagram length =", \length $socket_io->{SendBuffer}, " SeqNumb = $socket_io->{EchoSeqNumb}\n");
	debugMsg(2,"SocketEchoBufferDisconnect-datagram:\n>", \$socket_io->{SendBuffer}, "<\n");
}


sub socketEchoSend { # Sends an echo datagram; called at every cycle
	my $socket_io = shift;

	return unless length $socket_io->{OutBuffer} || ($socket_io->{CmdComplete} && $socket_io->{EchoSeqNumb} > 0);
	if ($socket_io->{EchoSeqNumb} >= 128 ) {
		debugMsg(2,"SocketEchoSend Error / SeqNumb = ", \$socket_io->{EchoSeqNumb}, " is > 128 !!\n");
		return;
	}

	# Do packet fragmentation if needed (we only send 1 datagram at each iteration)
	if (length $socket_io->{OutBuffer} >= $SocketMaxMsgLen - 1) { # Won't fit in one datagram..
		$socket_io->{SendBuffer} = substr($socket_io->{OutBuffer}, 0, $SocketMaxMsgLen - 1, ''); # Take 1st 1023 bytes
	}
	else {
		$socket_io->{SendBuffer} = $socket_io->{OutBuffer};	# Take it all
		$socket_io->{OutBuffer} = '';
	}

	# Set sequence number & final flag for datagram
	$socket_io->{EchoSeqNumb} = ++$socket_io->{EchoSeqNumb} & 127;	# Increase sequence number (on 7 bits 1-127)
	$socket_io->{EchoSeqNumb}++ if $socket_io->{EchoSeqNumb} == 0; # Skip 0 on roll over (otherwise we prepend again above)
	if (length $socket_io->{OutBuffer} == 0 && $socket_io->{CmdComplete}) { # End of output
		$socket_io->{EchoSeqNumb} |= 128;	# Set bit 8 on final datagram
		$socket_io->{CmdComplete} = 0;		# Make sure we don't come back
	}
	$socket_io->{SendBuffer} .= pack("C", $socket_io->{EchoSeqNumb});	# Append to message (now at most 1024 bytes long)
	debugMsg(2,"SocketEchoSend-datagram length =", \length $socket_io->{SendBuffer}, " SeqNumb = $socket_io->{EchoSeqNumb}\n");
	debugMsg(2,"SocketEchoSend-datagram:\n>", \$socket_io->{SendBuffer}, "<\n");
	debugMsg(2,"SocketEchoSend-toRetain:\n>", \$socket_io->{OutBuffer}, "<\n") if length $socket_io->{OutBuffer};

	# Echo output to send back to commanding terminal
	if ( socketEchoSetup($socket_io) ) {
		$socket_io->{EchoSocket}->send($socket_io->{SendBuffer});	# Send to socket
		debugMsg(4,"=Sent to echo socket: \n>", \$socket_io->{SendBuffer}, "<\n");
	}
	else { # We were not able to set it up...
		$socket_io->{ListenEchoMode} = 0; # Disable echo mode as we can't use it
		$socket_io->{ListenErrMsg} = "\n$ScriptName: unable to establish return echo socket\n"
	}
	$socket_io->{SendBuffer} = '';
}


sub socketEchoReceive { # Receives an echo datagram, checks sequence and last bit, populates receive hash
	my ($socket_io, $srcKey, $dataRef) = @_;

	my $lastByte = ord(chop($$dataRef)); # Strip the last byte (sequence number)
	debugMsg(4,"=socketEchoReceive sequence number = $lastByte\n");
	$socket_io->{TieEchoSeqNumb}->{$srcKey} = ++$socket_io->{TieEchoSeqNumb}->{$srcKey} & 127; # Increase expected seq number
	$socket_io->{TieEchoSeqNumb}->{$srcKey}++ if $socket_io->{TieEchoSeqNumb}->{$srcKey} == 0; # Skip 0 on roll over
	if ( $socket_io->{TieEchoSeqNumb}->{$srcKey} != ($lastByte & 127) ) { # Seq N mismatch
		$socket_io->{TieEchoBuffers}->{$srcKey} .= "\n\n<... missing output ...>\n\n";
		debugMsg(4,"=socketEchoReceive $srcKey sequence number mismatch\n");
		# We lost a fragment, give up on it, and re-align on the new sequence number
		$socket_io->{TieEchoBuffers}->{$srcKey} = $lastByte & 127;
	}
	$socket_io->{TieEchoBuffers}->{$srcKey} .= $$dataRef;
	if ($lastByte & 128) { # Last datagram!
		$socket_io->{TieEchoSeqNumb}->{$srcKey} = 0;
		debugMsg(4,"=socketEchoReceive $srcKey last datagram!\n");
	}
}


sub wipeEchoBuffers { # We no longer need these buffers, and we want to drain any future data for them
	my $socket_io = shift;

	foreach my $echoBuffer (keys %{$socket_io->{TieEchoBuffers}}) {
		delete($socket_io->{TieEchoBuffers}->{$echoBuffer});
		delete($socket_io->{TieEchoSeqNumb}->{$echoBuffer});
	}
	$socket_io->{TieEchoFlush} = 1;
	$socket_io->{TieEchoPartial} = undef;
}


sub handleSocketIO {	# Handle tied sockets (to which we echo keyboard input from this terminal)
			# and Listening sockets (from which we accept keyboard input from other terminal instances)
	my $db = shift;
	my $mode = $db->[0];
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $socket_io = $db->[6];
	my $termbuf = $db->[8];
	my $vars = $db->[12];

	if ($socket_io->{Tie}) { # We are tied
		if (length $socket_io->{SendBuffer}) { # We have data to send
			$socket_io->{TieTxSocket}->send($socket_io->{SendBuffer});	# Send to socket
			debugMsg(4,"=Sent to active socket: /", \$socket_io->{SendBuffer}, "/\n");
			$socket_io->{SendBuffer} = '';
			$socket_io->{TieEchoFlush} = 0;
		}
		if ($socket_io->{TieEchoMode} && defined $socket_io->{TieRxSocket}) { # For echo modes other than none
			while ($socket_io->{TieRxSelect}->can_read(0)) {# we have something to read
				my $data;
				my $source = $socket_io->{TieRxSocket}->recv($data, $SocketMaxMsgLen);
				unless (defined $source) {
					debugMsg(4,"=ReadTieRxSocket; error from socket->recv/\n");
					next;
				}
				if (length($source) == 32) { # On Vulcano Solaris, I'm getting AF_INET6 IPv4-mapped address and older Perl does not like it
					debugMsg(4,"=ReadListenSocket; Converting from AF_INET6 IPv4-mapped address to AF_INET\n");
					$source =~ s/^../\x00\x02/;
					$source =~ s/\x00{14}\xff{2}//;
				}
				my ($sourcePort, $sourceIP) = sockaddr_in($source);
				$sourceIP = sprintf("%vd", $sourceIP); # In ascii format
				unless (scalar grep {$_ eq $sourceIP} @{$socket_io->{AllowedSrcIPs}}) {
					# We received a packet from a non-allowed source
					debugMsg(4,"=ReadTieRxSocket-received from not-allowed IP $sourceIP\n");
					next;
				}
				my $sourcePortAddr = join('-', $sourceIP, $sourcePort);
				debugMsg(4,"=ReadTieRxSocket-from $sourcePortAddr: /", \$data, "/\n");
				next if $socket_io->{TieEchoFlush}; # We don't store it if in flush mode
				# We store the data; it will be displayed once output from local terminal is complete
				socketEchoReceive($socket_io, $sourcePortAddr, \$data);
			}
		}
	}
	if (%{$socket_io->{ListenSockets}}) { # We are listening
		# If we have anything in buffer send it now
		socketEchoSend($socket_io);

		# Cycle through all sockets we are listening to
		my $sockToRead = ($socket_io->{ListenSelect}->can_read(0))[0]; # Only pick next available socket with data ready to be read
		return unless defined $sockToRead;	# If nothing to read, come out
		debugMsg(4,"=Socket ready for read : ", \$sockToRead, "\n");
		my $data;
		my $source = $sockToRead->recv($data, $SocketMaxMsgLen);
		# Above we drain any sockets we might be listening to; in some cases, we don't want to process the data:
		unless (defined $source) {
			debugMsg(4,"=ReadListenSocket; error from socket->recv/\n");
			return;
		}
		if (length($source) == 32) { # On Vulcano Solaris, I'm getting AF_INET6 IPv4-mapped address and older Perl does not like it
			debugMsg(4,"=ReadListenSocket; Converting from AF_INET6 IPv4-mapped address to AF_INET\n");
			$source =~ s/^../\x00\x02/;
			$source =~ s/\x00{14}\xff{2}//;
		}
		my ($sourcePort, $sourceIP) = sockaddr_in($source);
		$sourceIP = sprintf("%vd", $sourceIP); # In ascii format
		debugMsg(4,"=ReadSocket-SourcePort = $sourcePort / SourceIP = $sourceIP\n");
		unless (scalar grep {$_ eq $sourceIP} @{$socket_io->{AllowedSrcIPs}}) {
			# We received a packet from a non-allowed source
			debugMsg(4,"=ReadSocket-received from not-allowed IP $sourceIP\n");
			return;
		}
		return if defined $socket_io->{TieTxLocalPort} && $socket_io->{TieTxLocalPort} == $sourcePort; # do not process own commands

		my $dataMode = socketBufferUnpack($socket_io, \$data);
		return unless defined $dataMode; # We could still reject the datagram, if the username does not match

		# If we get here, we have been tied
		setvar($db, '%' => ($host_io->{Prompt} =~ /\D(\d)(?::\d)?(?:\(.+?\)|(?:\/[\w\d-]+)+)?[>#]$/ ? $1 : 2), nosave => 1);

		# Cache the source IP from the tied terminal; needed if echo mode is 'error' or 'all'
		$socket_io->{ListenSrcIP} = $sourceIP;

		debugMsg(4,"=ReadSocket-dataMode = $dataMode / DataToProcess: /", \$data, "/\n");
			# Last char is a number representing the mode from sender / see socketBufferPack
			# 0 = single character read in 'rk' mode
			# 1 = single character read in 'sh' or 'ps' mode
			# 2 = single line ending with \n; YnPrompt not set
			# 3 = single line ending with \n; YnPrompt set
			# 4 = pasted command in transparent mode
			# 6 = socket ping

		if ($dataMode == 6) { # Socket ping, handle immediately and come out
			# Some of these conditions are the same as checked below for generating warning about not able to process the command
			return unless $host_io->{Connected} || $term_io->{PseudoTerm};				# Don't respond if no connection
			return if $script_io->{AcliControl}; 							# Don't respond if in ACLI> mode or in Annex/Serial Selection modes
			return if !defined $socket_io->{ListenEchoMode} && $term_io->{InputBuffQueue}->[0];	# Don't respond if we are currently processing local commands
			return unless $mode->{term_in} eq 'tm' || $mode->{buf_out} eq 'mp';			# Only reply if we have prompt and ready to take commands
			$socket_io->{OutBuffer} = "Response from " . switchname($host_io, 1);
			$socket_io->{OutBuffer} .= " [tied: " . $socket_io->{Tie} . "]" if $socket_io->{Tie};
			$socket_io->{OutBuffer} .= " [in midst of --more-- output paging]" if $mode->{buf_out} eq 'mp';
			$socket_io->{OutBuffer} .= "\n";
			debugMsg(2,"=socketPingResponse-datagram:\n>", \$socket_io->{OutBuffer}, "<\n");
			$socket_io->{CmdComplete} = 1;
			socketEchoSend($socket_io);
			return;
		}

		# Try and keep track of first message seen using dataMode == 3; we do checking below on these only, as in scripting mode, tied term will keep sending
		# commands while listening term toggles between 'ps' and 'tm' term_in mode as it executes them
		if ($dataMode == 3 && !defined $socket_io->{FirstDataMode3}) {
			$socket_io->{FirstDataMode3} = 1;
			debugMsg(2,"=socketFirstDataMode3 = ", \$socket_io->{FirstDataMode3}, "\n");
		}
		elsif ($dataMode == 3 && defined $socket_io->{FirstDataMode3}) {
			$socket_io->{FirstDataMode3} = 0;
		}
		else {
			$socket_io->{FirstDataMode3} = undef;
		}

		# Reasons why we might not be able to process the command; in which case we alert the driving terminal accordingly and come out
		# NOTE: all messages below need to comform to pattern '\n\cGError from \S+: Cannot process command ' in order for error detection to work on driving terminal
		unless ($host_io->{Connected} || $term_io->{PseudoTerm}) { # Don't process if no connection
			return unless defined $host_io->{Connected}; # If host never was connected, skip
			return if $data eq "\n";	# No warning for just a carriage return (used for initial tie)
			$socket_io->{OutBuffer} = "\n\cGError from " . switchname($host_io, 1) . ": Cannot process command as no connection\n";
			debugMsg(2,"=socketWarningUnableProcessCommand-noconnection: >", \$socket_io->{OutBuffer}, "<\n");
			$socket_io->{CmdComplete} = 1;
			socketEchoSend($socket_io);
			return;
		}
		if ($script_io->{AcliControl}) { # Don't process if in ACLI> mode or in Annex/Serial Selection modes
			return if $data eq "\n";	# No warning for just a carriage return (used for initial tie)
			$socket_io->{OutBuffer} = "\n\cGError from " . switchname($host_io, 1) . ": Cannot process command in ACLI control interface\n";
			debugMsg(2,"=socketWarningUnableProcessCommand-aclicontrol: >", \$socket_io->{OutBuffer}, "<\n");
			$socket_io->{CmdComplete} = 1;
			socketEchoSend($socket_io);
			return;
		}
		if (!defined $socket_io->{ListenEchoMode} && $term_io->{InputBuffQueue}->[0]) { # Don't process if we are currently processing local commands
			return if $data eq "\n";	# No warning for just a carriage return (used for initial tie)
			$socket_io->{OutBuffer} = "\n\cGError from " . switchname($host_io, 1) . ": Cannot process command as processing other local command\n";
			debugMsg(2,"=socketWarningUnableProcessCommand-localcommand: >", \$socket_io->{OutBuffer}, "<\n");
			$socket_io->{CmdComplete} = 1;
			socketEchoSend($socket_io);
			return;
		}
		if ( ($dataMode == 2 || $socket_io->{FirstDataMode3}) && $socket_io->{ListenEchoMode} && $mode->{term_in} ne 'tm' && $mode->{buf_out} ne 'mp') { # Terminal is not able to process; warn back
			return if $data eq "\n";	# No warning for just a carriage return (used for initial tie)
			$socket_io->{OutBuffer} = "\n\cGError from " . switchname($host_io, 1) . ": Cannot process command as prompt not ready\n";
			debugMsg(2,"=socketWarningUnableProcessCommand-notin-tm-mode: >", \$socket_io->{OutBuffer}, "<\n");
			$socket_io->{CmdComplete} = 1;
			socketEchoSend($socket_io);
			return;
		}

		# Beyond this point, we are going to accept the command

		if ($socket_io->{Tie}) { # If we are tied and we receive on an open socket, then we untie ourselves
			untieSocket($socket_io);
			setPromptSuffix($db);
		}

		# Now process the data we have read in
		if ($dataMode == 0) { # Single character read 'rk' mode
			if ($mode->{buf_out} eq 'mp' && !$term_io->{Key}) {
				$term_io->{Key} = $data;
				debugMsg(4,"=InputSocketPushMorePageChar-mode0: /", \$data, "/\n");
			}
			else {
				$term_io->{SingleChar} = $data;
				return;
			}
		}
		elsif ($dataMode == 1) { # Single character read 'sh' or 'ps' mode
			@{$term_io->{CharBuffer}} = split(//, $data); # Push everything onto CharBuffer
			debugMsg(4,"=InputSocketPushSingleChar-mode1: /", \$data, "/\n");
			$term_io->{Key} = 'q' if $data eq $Return; # Force a Quit (has power to stop sourcing and unblock more prompt)
		}
		elsif ($dataMode == 2) { # Single line command with YnPrompt not set
			saveInputBuffer($term_io) if $term_io->{InputBuffQueue}->[0];
			$socket_io->{EchoSendFlag} = undef;
			@{$term_io->{CharBuffer}} = split(//, $data); # Push everything onto CharBuffer
			debugMsg(4,"=InputSocketPushChar-mode2: /", \$data, "/\n");
			if ($mode->{term_in} eq 'tm' && (length $termbuf->{Linebuf1} || length length $termbuf->{Linebuf2}) ) {
				unshift(@{$term_io->{CharBuffer}}, $CTRL_U);	# Wipe partial line buffer if there was one
			}
		}
		else { # Other modes handled under multiple character processing
			$socket_io->{EchoSendFlag} = undef;
			my $lastLineComplete = chomp $data;	# Keep track if data ends with \n
			my @lines = split(/\n/, $data);
			unless ($lastLineComplete) { # Take last element and chop it into characters into CharBuffer
				if (scalar @lines > 1) {
					$term_io->{CharPBuffer} = $lines[$#lines];
					debugMsg(4,"=InputSocketPush to CharPBuffer: /", \$lines[$#lines], "/\n");
				}
				else {
					@{$term_io->{CharBuffer}} = split(//, $lines[$#lines]);
					debugMsg(4,"=InputSocketPushChar: /", \$lines[$#lines], "/\n");
				}
				$#lines--;	# Wipe last element now
			}
			# Push the rest onto InputBuffer
			if (@lines) {
				appendInputBuffer($db, 'paste', \@lines, undef, 0); # Avoid printing message "Warning: Entering source mode and @echo is off"
				debugMsg(4,"=InputSocketPushLines = /", \join("\n", @lines), "/\n\n");
			}
		}
		if ( ($dataMode == 2 || $dataMode == 3) && $mode->{buf_out} eq 'mp' && !$term_io->{Key}) { # If this terminal is paused in More prompt
			debugMsg(4,"=InputSocket-ReleaseMorePrompt\n");
			$term_io->{Key} = 'qs'; # Force a Quit (has power to unblock more prompt and start executing sourcing buffer)
		}
	}
}

1;
