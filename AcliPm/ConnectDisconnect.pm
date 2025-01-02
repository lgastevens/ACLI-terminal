# ACLI sub-module
package AcliPm::ConnectDisconnect;
our $Version = "1.05";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(disconnectPeerCP disconnect connectToPeerCP connectToHost enablePseudoTerm);
}
use Cwd;
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::DebugMessage;
use AcliPm::ExitHandlers;
use AcliPm::GlobalDefaults;
use AcliPm::GlobalDeviceSettings;
use AcliPm::Logging;
use AcliPm::Print;
use AcliPm::Prompt;
use AcliPm::Socket;
use AcliPm::Sourcing;
use AcliPm::Variables;


sub disconnectPeerCP { # Disconnect from peer CPU
	my $db = shift;
	my $peercp_io = $db->[5];

	$peercp_io->{CLI}->disconnect;
	$peercp_io->{Connected} = 0;
	$peercp_io->{OOB_IP} = undef;
	$peercp_io->{Connect_IP} = undef;
	$peercp_io->{Connect_OOB} = undef;
}


sub disconnect { # Disconnect from host
	my ($db, $keepSockets) = @_;
	my $mode = $db->[0];
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $peercp_io = $db->[5];
	my $socket_io = $db->[6];
	my $prompt = $db->[7];

	return unless $host_io->{Connected};
	$host_io->{CLI}->disconnect;
	$host_io->{Connected} = 0;
	$host_io->{Type} = $host_io->{Model} = $host_io->{VarsFile} = '';
	$host_io->{CapabilityMode} = $host_io->{Discovery} = undef;
	$prompt->{Match} = $prompt->{Regex} = $prompt->{More} = undef;
	$term_io->{AcliType} = undef;
	$term_io->{Mode} = 'transparent';
	$host_io->{Login} = 0;
	disconnectPeerCP($db) if $peercp_io->{Connected}; # Tear down connection to peer CPU
	$mode->{connect_stage} = 0;
	$mode->{peer_cp_stage} = 0;
	$term_io->{TermTypeNotNego} = $term_io->{TermWinSNotNego} = undef;
	unless ($keepSockets) { # Clear sockets if any were active
		untieSocket($socket_io);
		closeSockets($socket_io, 1);
		setPromptSuffix($db);
	}
}


sub connectToPeerCP { # Connect to peer CPU
	my ($db, $blocking) = @_;
	my $mode = $db->[0];
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $peercp_io = $db->[5];
	my ($cli_debug, $cli_errmode);

	$cli_debug |= $::Debug & 8 ? $DebugCLIExtreme : 0;
	$cli_debug |= $::Debug & 16 ? $DebugCLIExtremeSerial : 0;
	if ($::Debug & 64) {
		$cli_errmode = 'die';
	}
	elsif ($::Debug & 32) {
		$cli_errmode = 'croak';
	}
	else {
		$cli_errmode = [\&connectionPeerCPError, $db];
	}

	$peercp_io->{CLI} = new Control::CLI::Extreme (
		Use			=>	$host_io->{ComPort},
		Timeout			=>	$peercp_io->{Timeout},
		Blocking		=>	$blocking ? 1 : 0,
		Binmode			=>	1,
		Errmode			=>	$cli_errmode,
		Errmsg_format		=>	$::Debug ? 'verbose' : 'terse',
		Return_reference	=>	1,
		Prompt_credentials	=>	0,
		Output_record_separator	=>	$term_io->{Newline},
		Terminal_type		=>	$term_io->{TerminalType},
		Window_size		=>	$term_io->{WindowSize},
		Debug			=>	$cli_debug,
	) or return;

	if ($::Debug) {
		my $filePrefix = $host_io->{Name} =~ /^serial:/ ? $host_io->{ComPort} : $host_io->{Name};
		$filePrefix =~ s/:/_/g;	# Produce a suitable filename for serial ports & IPv6 addresses
		$filePrefix =~ s/[\/\\]/-/g;	# Produce a suitable filename for serial ports (on unix systems)
		$peercp_io->{InputLog} = $filePrefix . '-peercp' . $DebugInFile;
		$peercp_io->{OutputLog} = $filePrefix . '-peercp' . $DebugOutFile;
		$peercp_io->{DumpLog} = $filePrefix . '-peercp' . $DebugDumpFile;
		$peercp_io->{TelOptLog} = $filePrefix . '-peercp' . $DebugTelOptFile if $host_io->{ComPort} eq 'TELNET';
		$peercp_io->{CLI}->input_log($host_io->{DebugFilePath} .'/'. $peercp_io->{InputLog});
		$peercp_io->{CLI}->output_log($host_io->{DebugFilePath} .'/'. $peercp_io->{OutputLog});
		$peercp_io->{CLI}->dump_log($host_io->{DebugFilePath} .'/'. $peercp_io->{DumpLog});
		$peercp_io->{CLI}->parent->option_log($host_io->{DebugFilePath} .'/'. $peercp_io->{TelOptLog}) if $host_io->{ComPort} eq 'TELNET';
		my $debugLog = $host_io->{DebugFilePath} .'/'. $filePrefix . '-peercp' . $DebugFile;
		$peercp_io->{CLI}->debug_file($debugLog);
	}

	printOut($script_io, "Connecting to peer CPU ") unless $blocking;

	$peercp_io->{ConnectionError} = 0;
	$mode->{peer_cp_stage} = defined $host_io->{OOBconnected} ? 3 : 1; # Initiate peer CP connection
	return 1;
}


sub connectToHost { # Connect to host
	my $db = shift;
	my $mode = $db->[0];
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my ($cli_debug, $cli_errmode, $openlog);

	debugMsg(1,"Connect: COM Port = $host_io->{ComPort}\n") if $host_io->{ComPort};

	debugMsg(1,"Connect: Relay Host = $host_io->{RelayHost}\n") if $host_io->{RelayHost};
	debugMsg(1,"Connect: Relay TCP Port = $host_io->{RelayTcpPort}\n") if $host_io->{RelayTcpPort};
	debugMsg(1,"Connect: Relay Username = $host_io->{RelayUsername}\n") if $host_io->{RelayUsername};
	debugMsg(1,"Connect: Relay Password = $host_io->{RelayPassword}\n") if $host_io->{RelayPassword};
	debugMsg(1,"Connect: Relay Baudrate = $host_io->{RelayBaudrate}\n") if $host_io->{RelayBaudrate};
	debugMsg(1,"Connect: Relay Command = '$host_io->{RelayCommand}'\n") if $host_io->{RelayCommand};

	debugMsg(1,"Connect: Host = $host_io->{Name}\n") if $host_io->{Name};
	debugMsg(1,"Connect: TCP Port = $host_io->{TcpPort}\n") if $host_io->{TcpPort};
	debugMsg(1,"Connect: Username = $host_io->{Username}\n") if $host_io->{Username};
	debugMsg(1,"Connect: Password = $host_io->{Password}\n") if defined $host_io->{Password};
	debugMsg(1,"Connect: Baudrate = $host_io->{Baudrate}\n") if $host_io->{Baudrate};
	debugMsg(1,"Connect: SSH Public Key = $host_io->{SshPublicKey}\n") if $host_io->{SshPublicKey};
	debugMsg(1,"Connect: SSH Private Key = $host_io->{SshPrivateKey}\n") if $host_io->{SshPrivateKey};
	debugMsg(1,"Connect: Terminal Server Flag is set\n") if $host_io->{TerminalSrv};

	debugMsg(1,"Connect: Outfile = $script_io->{OverWrite} $script_io->{LogFile}\n") if $script_io->{LogFile};

	# Empty output buffers, in case there was still some pending output in them
	$host_io->{OutBuffer} = '';
	$host_io->{OutCache} = '';
	$host_io->{GrepBuffer} = '';
	$host_io->{GrepCache} = '';
	$host_io->{PacedSentChars} = '';
	$host_io->{UnrecogLogins} = $UnrecognizedLogins;
	$term_io->{PageLineCount} = $term_io->{MorePageLines};
	@{$term_io->{CharBuffer}} = (); # Empty the char buffer
	#%{$term_io->{InputBuffer}} = (); # We no longer do this in order to let StartScriptOnTm work
	%{$term_io->{SourceActive}} = ();
	saveInputBuffer($term_io); # Will clear InputBuffQueue if set
	$host_io->{LoopbackConnect} = undef;
	$host_io->{SessionUpTime} = time + $host_io->{SessionTimeout}*60;	# Reset session inactivity timer
	$host_io->{KeepAliveUpTime} = time + $host_io->{KeepAliveTimer}*60;	# Reset keepalive timer
	$mode->{connect_stage} = 0;
	$term_io->{Mode} = 'transparent';

	if ($host_io->{ComPort} !~ /^(?:TELNET|SSH)$/) {
		$host_io->{Console} = 1;
		$host_io->{RemoteAnnex} = 0;
	}
	elsif ($host_io->{ComPort} =~ /^(?:TELNET|SSH)$/ && $host_io->{TerminalSrv}) {
		$host_io->{RemoteAnnex} = $host_io->{Console} = 1;
	}
	else {
		$host_io->{RemoteAnnex} = $host_io->{Console} = 0;
	}

	$cli_debug |= $::Debug & 8 ? $DebugCLIExtreme : 0;
	$cli_debug |= $::Debug & 16 ? $DebugCLIExtremeSerial : 0;
	if ($::Debug & 64) {
		$cli_errmode = 'die';
	}
	elsif ($::Debug & 32) {
		$cli_errmode = 'croak';
	}
	else {
		$cli_errmode = [\&connectionError, $db];
	}

	$host_io->{CLI} = new Control::CLI::Extreme (
		Use			=>	$host_io->{ComPort},
		Timeout			=>	$host_io->{Timeout},
		Blocking		=>	0,
		Binmode			=>	1,
		Errmode			=>	$cli_errmode,
		Errmsg_format		=>	$::Debug ? 'verbose' : 'terse',
		Return_reference	=>	1,
		Prompt_credentials	=>	0,
		Output_record_separator	=>	$term_io->{Newline},
		Wake_console		=>	"\n", # We always want \n here (default anyway); not \r which $term_io->{Newline} might be set to
		Terminal_type		=>	$term_io->{TerminalType},
		Window_size		=>	$term_io->{WindowSize},
		Report_query_status	=>	1,
		Debug			=>	$cli_debug,
	) or return;

	if ($host_io->{ComPort} eq 'SSH') { # Set the SSH banner to reflect this script
		$host_io->{CLI}->parent->banner($ScriptName);
	}

	# Start logging, if necessary
	$openlog = openLogFile($db);
	if ($openlog) {
		print "Logging to file: ", $script_io->{LogFullPath}, "\n"; # Don't use printOut here or it will go to the newly opened log file
	}
	elsif (!defined $openlog) {
		printOut($script_io, "\nCannot open logging file: $script_io->{LogFullPath}\nReason: $!\n\n");
	}

	if ($::Debug) {
		my $filePrefix = $host_io->{Name} =~ /^serial:/ ? $host_io->{ComPort} : $host_io->{Name};
		$filePrefix =~ s/:/_/g;	# Produce a suitable filename for serial ports & IPv6 addresses
		$filePrefix =~ s/[\/\\]/-/g;	# Produce a suitable filename for serial ports (on unix systems)
		$host_io->{DebugFilePath} = File::Spec->rel2abs(cwd) unless $host_io->{DebugFilePath};
		$host_io->{InputLog} = $filePrefix . $DebugInFile;
		$host_io->{OutputLog} = $filePrefix . $DebugOutFile;
		$host_io->{DumpLog} = $filePrefix . $DebugDumpFile;
		$host_io->{TelOptLog} = $filePrefix . $DebugTelOptFile if $host_io->{ComPort} eq 'TELNET';
		$DebugLog = $filePrefix . $DebugFile;
		$host_io->{CLI}->input_log($host_io->{DebugFilePath} .'/'. $host_io->{InputLog});
		$host_io->{CLI}->output_log($host_io->{DebugFilePath} .'/'. $host_io->{OutputLog});
		$host_io->{CLI}->dump_log($host_io->{DebugFilePath} .'/'. $host_io->{DumpLog});
		$host_io->{CLI}->parent->option_log($host_io->{DebugFilePath} .'/'. $host_io->{TelOptLog}) if $host_io->{ComPort} eq 'TELNET';
		unless ($DebugLogFH) {
			if ( open($DebugLogFH, '>', $DebugLog) ) {
				$host_io->{CLI}->debug_file($DebugLogFH);
			}
			else {
				undef $DebugLogFH;
				print "Unable to open debug file $DebugLog : $!\n";
			}
		}
	}

	if (!defined $host_io->{Password} && $term_io->{AutoLogin} && $host_io->{Username}) { # AutoLogin (-p) for SSH
		$host_io->{Password} = 'rwa' if $host_io->{Username} eq 'rwa';
		$host_io->{Password} = 'setup' if $host_io->{Username} eq 'admin';
		debugMsg(1,"SSH AutoLogin setting Password\n");
	}

	printOut($script_io, "Escape character is '$term_io->{CtrlEscapePrn}'.\n");

	$host_io->{ConnectionError} = 0;
	return 1;
}


sub enablePseudoTerm { # Set up Pseudo Terminal mode
	my ($db, $name) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $prompt = $db->[7];

	# Set default prompt
	my $defprompt;
	if ($name =~ /^\d\d?$/ || $name eq '100') {
		$defprompt = $Default{pseudo_prompt_str};
		$defprompt =~ s/#$/$name#/ if $name < 100; # Insert number if one was set
	}
	else { # Use the name provided
		$defprompt = $name;
	}
	$host_io->{Prompt} = $prompt->{Match} = $defprompt;
	$prompt->{Regex} = qr/($prompt->{Match})/;

	# Set debug
	if ($::Debug) {
		if (defined $term_io->{PseudoTermName} && $term_io->{PseudoTermName} ne $name) {
			close $DebugLogFH if $DebugLogFH;
			undef $DebugLogFH;
		}
		my $filePrefix = 'pseudo.' . $name;
		$host_io->{DebugFilePath} = File::Spec->rel2abs(cwd);
		$DebugLog = $filePrefix . $DebugFile;
		unless ($DebugLogFH) {
			open($DebugLogFH, '>', $DebugLog) or do {
				undef $DebugLogFH;
				print "Unable to open debug file $DebugLog : $!\n";
			};
		}
	}

	# Set PseudoTerm and try and load VarFile (this may set prompt again)
	$term_io->{PseudoTerm} = 1;
	$term_io->{PseudoTermName} = $name;
	%{$term_io->{PseudoAttribs}} = (); #Empty it first
	unless (loadVarFile($db)) { # If no profile was loaded..
		$host_io->{Type} = $PseudoSelectionAttributes{$PseudoDefaultSelection}{family_type};
		$term_io->{AcliType} = $PseudoSelectionAttributes{$PseudoDefaultSelection}{is_acli};
		for my $key (keys %{$PseudoSelectionAttributes{$PseudoDefaultSelection}}) {
			$term_io->{PseudoAttribs}->{$key} = $PseudoSelectionAttributes{$PseudoDefaultSelection}{$key};
		}
	}

	# Final settings
	$term_io->{Mode} = 'interact';
	$host_io->{ConnectionError} = 0; # (bug20)

	# Start logging
	$script_io->{AutoLog} = 0;	# We don't allow auto-logging in pseudo mode
	my $openlog = openLogFile($db);
	if ($openlog) {
		print "Logging to file: ", $script_io->{LogFullPath}, "\n"; # Don't use printOut here or it will go to the newly opened log file
	}
	elsif (!defined $openlog) {
		printOut($script_io, "\nCannot open logging file: $script_io->{LogFullPath}\nReason: $!\n\n");
	}
}


1;
