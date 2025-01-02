# ACLI sub-module
package AcliPm::ExitHandlers;
our $Version = "1.02";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(dieHandler quit connectionPeerCPError connectionError);
}
use Term::ReadKey;
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::ChangeMode;
use AcliPm::DebugMessage;
use AcliPm::GlobalConstants;
use AcliPm::GlobalDefaults;
use AcliPm::Print;
use AcliPm::Socket;


sub dieHandler { # We trap die to this function
	die @_ unless defined $^S; # Prevents handler being called when "parsing" eval EXPR (bug7); See http://perldoc.perl.org/perlvar.html#%24^S
	die @_ if $^S; # Prevents handler being called when "executing" eval BLOCK; See http://perldoc.perl.org/functions/die.html
	# So we exit only if $^S is true(1)
	my $errmsg = shift;
	print "\nDIE handler:\n============\n";
	print $errmsg if defined $errmsg;
	print "\n";	# Extra newline..
	system("pause");
	exit 1;
}


sub quit { # Quit ACLI
	my ($retval, $quitmsg, $db) = @_;
	my $host_io = $db->[3] if $db;
	my $script_io = $db->[4] if $db;

	printOut($script_io, join('',"\n$ScriptName: ",$quitmsg,"\n")) if defined $quitmsg;
	# Clean up and exit
	ReadMode('restore') if $script_io->{TermModeSet};
	$| = 0; # Revert to line buffered mode
	if ($script_io && defined $script_io->{LogFH}) {
		printf { $script_io->{LogFH} } "\n=~=~=~=~=~=~=~=~=~=~= %s log %s =~=~=~=~=~=~=~=~=~=~=\n", $ScriptName, scalar localtime;
		close $script_io->{LogFH};
	}
	close $script_io->{CmdLogFH} if $script_io && defined $script_io->{CmdLogFH};
	close $DebugLogFH if $DebugLogFH;
	if (defined $host_io->{CLI}) { # For a serial connection, we might have failed to reconnect (constructor) if COM port no longer exists
		close $host_io->{CLI}->input_log if $host_io->{InputLog};
		close $host_io->{CLI}->output_log if $host_io->{OutputLog};
		close $host_io->{CLI}->dump_log if $host_io->{DumpLog};
		close $host_io->{CLI}->parent->option_log if $host_io->{TelOptLog} && $host_io->{ComPort} eq 'TELNET';
	}
	if ($^O eq "MSWin32") { # If used in Console2, we don't want script to quit immediately
		if (defined $quitmsg && $Win32PauseOnQuit) { # ..or else we don't see the quit/error message
			print "\n";	# Extra newline..
			system("pause");
		}
	}
	else {
		print "\n";	# Extra newline on unix systems
	}
	exit $retval;
}


sub connectionPeerCPError { # Handle connetion loss to peer CPU
	my ($db, $errmsg) = @_;
	my $mode = $db->[0];
	my $peercp_io = $db->[5];

	my (undef, $file, $line) = caller;
	debugMsg(1, "Peer CPU Connection error: Caller is $file @ line number $line\n");
	debugMsg(1, "Peer CPU Connection error: $errmsg\n") if length $errmsg;
	$peercp_io->{Connected} = 0;
	$peercp_io->{ConnectionError} = 1;
	$peercp_io->{Connect_IP} = undef;
	$peercp_io->{Connect_OOB} = undef;
	return;
}


sub connectionError { # Handle connection loss to host
	my ($db, $errmsg) = @_;
	my $mode = $db->[0];
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $socket_io = $db->[6];

	my (undef, $file, $line) = caller;
	debugMsg(1, "Connection error: Caller is $file @ line number $line\n");
	if (length $errmsg) {
		debugMsg(1, "Connection error: $errmsg\n");
		printOut($script_io, "\n" . $errmsg . "\n");
	}
	# Socket handling
	if ($term_io->{SocketEnable}) {
		if ($socket_io->{Tie}) { # If tied..
			wipeEchoBuffers($socket_io); # .. wipe buffers and read no more
		}
		elsif ($socket_io->{ListenEchoMode}) { # Send disconnect echo message
			socketEchoBufferDisconnect($host_io, $socket_io);
			handleSocketIO($db);	# Now (we have possible quits below)
		}
	}
	# Cmd Ooutput logging
	close $script_io->{CmdLogFH} if defined $script_io->{CmdLogFH};
	$script_io->{CmdLogFH} = $script_io->{CmdLogFile} = $script_io->{CmdLogOnly} = $script_io->{CmdLogFlag} = undef;
	# Variables to reset
	$host_io->{Login} = 0;
	$host_io->{Connected} = 0;
	$host_io->{Discovery} = undef;
	$host_io->{ConnectionError} = 1;
	$mode->{connect_stage} = 0;
	# For both ACLI mode and normal connection mode, check for SSH auth error and if so clear stored password
	$host_io->{Password} = undef if defined $errmsg && $errmsg =~ /SSH unable to password authenticate/;
	if ($script_io->{ConnectFailMode} == 2) { # Return to ACLI> mode
		if (!$host_io->{Connected}) {
			print "\nConnection failed\n", $ACLI_Prompt;
		}
		elsif ($host_io->{CLI}->eof) {
			print "\nConnection closed\n", $ACLI_Prompt;
		}
		else {
			print "\nConnection error: ", $errmsg, "\n", $ACLI_Prompt;
		}
		$script_io->{AcliControl} = 1;
		changeMode($mode, {term_in => 'tm', dev_inp => 'ds', buf_out => 'ds'}, '#EH1');
	}
	else { # In normal connection mode we...
		if ($script_io->{QuitOnDisc}) { # ...quit
			quit(1, "Connection closed", $db) if $host_io->{Connected} && $host_io->{CLI}->eof;
			quit(1, "Connection failed", $db) if $host_io->{CLI}->eof;
			quit(1, "Connection error: $errmsg", $db);
		}
		elsif ($script_io->{ConnectFailMode} == 0) { # ... we offer to reconnect
			print "\n------> Connection closed: SPACE to re-connect / Q to quit <------\n";
			changeMode($mode, {term_in => 'qs', dev_inp => 'ds', dev_del => 'ds', dev_fct => 'ds', dev_cch => 'ds', dev_out => 'ub', buf_out => 'ds'}, '#EH2');
		}
#		elsif (!defined $host_io->{Connected}) {	(bug8)
		else { # $script_io->{ConnectFailMode} == 1
			print "\n------> Connection failed: SPACE to re-try / Q to quit <------\n";
			changeMode($mode, {term_in => 'qs', dev_inp => 'ds', dev_del => 'ds', dev_fct => 'ds', dev_cch => 'ds', dev_out => 'ub', buf_out => 'ds'}, '#EH3');
		}
	}
	return;
}

1;
