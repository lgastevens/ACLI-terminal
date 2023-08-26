# ACLI sub-module
package AcliPm::HandleDevicePeerCP;
our $Version = "1.00";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(handleDevicePeerCP);
}
use Net::Ping::External qw(ping);
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::ConnectDisconnect;
use AcliPm::DebugMessage;
use AcliPm::GlobalMatchingPatterns;
use AcliPm::HandleDeviceOutput;
use AcliPm::Print;
use AcliPm::Ssh;


sub changePeerCPStage { # Change stage in handleDevicePeerCP
	my ($mode, $nextStage) = @_;

	debugMsg(1,"-> Connect Peer CPU Stage $mode->{peer_cp_stage} ==> $nextStage\n");
	$mode->{peer_cp_stage} = $nextStage;
}


sub handleDevicePeerCP { # Handles connection to device peer CPU
	my ($db, $blocking) = @_;
	my $mode = $db->[0];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $peercp_io = $db->[5];

	my ($ok, $outRef);

	if ($mode->{peer_cp_stage} == 1) { # 1

		($ok, $host_io->{OOBconnected}) = $host_io->{CLI}->attribute(
			Attribute	=>	'is_oob_connected',
			Blocking		=>	$blocking ? 1 : 0,
			Errmode		=>	'return',
		);
		if ($ok) { # We have the attribute set already, or blocking mode from ACLI>
			$peercp_io->{OOB_IP} = $host_io->{CLI}->attribute('oob_standby_ip');
			debugMsg(1,"-> OOBconnected = ", \$host_io->{OOBconnected}, "\n");
			debugMsg(1,"-> OOB_IP = ", \$peercp_io->{OOB_IP}, "\n");
			changePeerCPStage($mode, 3);
		}
		elsif (defined $ok) { # We have to poll for it
			printDot($script_io);
			changePeerCPStage($mode, 2);
			return;
		}
		else { # Catch error
			changePeerCPStage($mode, 3);
		}

	} # 1

	if ($mode->{peer_cp_stage} == 2) { # 2

		($ok, $host_io->{OOBconnected}) = $host_io->{CLI}->attribute_poll;
		printDot($script_io);
		if ($ok) { # We have the attribute set already
			changePeerCPStage($mode, 3);
			$peercp_io->{OOB_IP} = $host_io->{CLI}->attribute('oob_standby_ip');
			debugMsg(1,"-> OOBconnected = ", \$host_io->{OOBconnected}, "\n");
			debugMsg(1,"-> OOB_IP = ", \$peercp_io->{OOB_IP}, "\n");
		}
		elsif (defined $ok) { # We have to poll for it
			return;
		}
		else { # Catch error
			changePeerCPStage($mode, 3);
		}

	} # 2

	if ($mode->{peer_cp_stage} == 3) { # 3

		if ($host_io->{OOBconnected} && $peercp_io->{OOB_IP} && ping(host => $peercp_io->{OOB_IP}, timeout => 1) ) {
			$peercp_io->{Connect_IP} = $peercp_io->{OOB_IP};
			$peercp_io->{Connect_OOB} = 1;
		}
		else { # We create a 2nd connection to same CP and then do device_peer_cpu
			$peercp_io->{Connect_IP} = $host_io->{Name};
			$peercp_io->{Connect_OOB} = 0;
		}

		debugMsg(1,"-> Peer CPU Connect: Going directly to Peer CPU OOB IP\n") if $peercp_io->{Connect_OOB};
		debugMsg(1,"-> Peer CPU Connect: Connecting via shadow connection to Master CPU\n") unless $peercp_io->{Connect_OOB};
		debugMsg(1,"-> Peer CPU Connect: Host = $peercp_io->{Connect_IP}\n");
		debugMsg(1,"-> Peer CPU Connect: Username = $host_io->{Username}\n") if $host_io->{Username};
		debugMsg(1,"-> Peer CPU Connect: Password = $host_io->{Password}\n") if $host_io->{Password};
		debugMsg(1,"-> Peer CPU Connect: SSH Public Key = $host_io->{SshPublicKey}\n") if $host_io->{SshPublicKey};
		debugMsg(1,"-> Peer CPU Connect: SSH Private Key = $host_io->{SshPrivateKey}\n") if $host_io->{SshPrivateKey};
		debugMsg(1,"-> Peer CPU Connect: Relay Host = $host_io->{RelayHost}\n") if $host_io->{RelayHost};
		debugMsg(1,"-> Peer CPU Connect: Relay TCP Port = $host_io->{RelayTcpPort}\n") if $host_io->{RelayTcpPort};
		debugMsg(1,"-> Peer CPU Connect: Relay Username = $host_io->{RelayUsername}\n") if $host_io->{RelayUsername};
		debugMsg(1,"-> Peer CPU Connect: Relay Password = $host_io->{RelayPassword}\n") if $host_io->{RelayPassword};
		debugMsg(1,"-> Peer CPU Connect: Relay Command = '$host_io->{RelayCommand}'\n") if $host_io->{RelayCommand};

		if (!$peercp_io->{Connect_OOB} && $host_io->{RelayHost}) { # Connect via same Relay host
			$ok = $peercp_io->{CLI}->connect(
				Host			=>	$host_io->{RelayHost},			# Only Telnet
				Port			=>	$host_io->{RelayTcpPort},		# SSH or Telnet
				Username		=>	$host_io->{RelayUsername},		# Relay Username
				Password		=>	$host_io->{RelayPassword},		# Relay Password
				PublicKey		=>	$host_io->{SshPublicKey},		# Only for SSH
				PrivateKey		=>	$host_io->{SshPrivateKey},		# Only for SSH
				Prompt_credentials	=>	0,					# No
				Connection_timeout	=>	$host_io->{ConnectTimeout},
				Callback		=>	[\&verifySshHostKey, $db],
			);
		}
		else {
			$ok = $peercp_io->{CLI}->connect(
				Host			=>	$peercp_io->{Connect_IP},		# Peer CPU IP to use
				Username		=>	$host_io->{Username},			# Cached username
				Password		=>	$host_io->{Password},			# Cached password
				PublicKey		=>	$host_io->{SshPublicKey},		# Only for SSH
				PrivateKey		=>	$host_io->{SshPrivateKey},		# Only for SSH
				Prompt_credentials	=>	0,					# No
				Connection_timeout	=>	$host_io->{ConnectTimeout},
				Callback		=>	[\&verifySshHostKey, $db],
			);
		}
		if ($ok) { # Will be true in blocking mode
			changePeerCPStage($mode, 5);	# Skip Poll and move to next stage
		}
		elsif (defined $ok) { # Poll
			printDot($script_io);
			changePeerCPStage($mode, 4);	# Move to next stage
			return;
		}
		else { # Error
			changePeerCPStage($mode, 990);
		}

	} # 3

	if ($mode->{peer_cp_stage} == 4) { # 4

		$ok = $peercp_io->{CLI}->connect_poll;
		if ($ok) { # Will be true in blocking mode
			changePeerCPStage($mode, 5);	# Move to next stage
		}
		elsif (defined $ok) { # Poll
			printDot($script_io);
			return;
		}
		else { # Error
			changePeerCPStage($mode, 990);
		}

	} # 4
	
	if ($mode->{peer_cp_stage} == 5) { # 5

		if (!$peercp_io->{Connect_OOB} && $host_io->{RelayHost}) { # Connect via same Relay host
			$peercp_io->{CLI}->print($host_io->{RelayCommand});
			$ok = $peercp_io->{CLI}->login(
				Timeout		=>	$host_io->{LoginTimeout},
				Username	=>	$host_io->{Username},
				Password	=>	$host_io->{Password},
				Read_attempts	=>	0,
			);
			if ($ok) { # Will be true in blocking mode
				changePeerCPStage($mode, 7);	# Skip Poll and move to next stage
			}
			elsif (defined $ok) { # Poll
				printDot($script_io);
				changePeerCPStage($mode, 6);	# Move to next stage
				return;
			}
			else { # Error
				changePeerCPStage($mode, 990);
			}
		}
		else {
			changePeerCPStage($mode, 7);	# Move to next stage
		}

	} # 5

	if ($mode->{peer_cp_stage} == 6) { # 6

		$ok = $peercp_io->{CLI}->login_poll;
		if ($ok) { # Will be true in blocking mode
			changePeerCPStage($mode, 7);	# Move to next stage
		}
		elsif (defined $ok) { # Poll
			printDot($script_io);
			return;
		}
		else { # Error
			changePeerCPStage($mode, 990);
		}

	} # 6


	if ($mode->{peer_cp_stage} == 7) { # 7

		if (!$peercp_io->{Connect_OOB}) {
			$ok = $peercp_io->{CLI}->device_peer_cpu;
			if ($ok) { # Will be true in blocking mode
				changePeerCPStage($mode, 9);	# Skip Poll and move to next stage
			}
			elsif (defined $ok) { # Poll
				printDot($script_io);
				changePeerCPStage($mode, 8);	# Move to next stage
				return;
			}
			else { # Error
				changePeerCPStage($mode, 990);
			}
		}
		else {
			changePeerCPStage($mode, 9);	# Move to next stage
		}

	} # 7
	
	if ($mode->{peer_cp_stage} == 8) { # 8

		$ok = $peercp_io->{CLI}->device_peer_cpu_poll;
		if ($ok) { # Will be true in blocking mode
			changePeerCPStage($mode, 9);	# Move to next stage
		}
		elsif (defined $ok) { # Poll
			printDot($script_io);
			return;
		}
		else { # Error
			changePeerCPStage($mode, 990);
		}

	} # 8
	
	if ($mode->{peer_cp_stage} == 9) { # 9

		$ok = $peercp_io->{CLI}->enable;
		if ($ok) { # Will be true in blocking mode
			changePeerCPStage($mode, 19);	# Skip Poll and move to next stage
		}
		elsif (defined $ok) { # Poll
			printDot($script_io);
			changePeerCPStage($mode, 10);	# Move to next stage
			return;
		}
		else { # Error
			changePeerCPStage($mode, 990);
		}

	} # 9

	if ($mode->{peer_cp_stage} == 10) { # 10

		$ok = $peercp_io->{CLI}->enable_poll;
		if ($ok) { # Will be true in blocking mode
			changePeerCPStage($mode, 19);	# Move to next stage
		}
		elsif (defined $ok) { # Poll
			printDot($script_io);
			return;
		}
		else { # Error
			changePeerCPStage($mode, 990);
		}

	} # 10

	if ($mode->{peer_cp_stage} == 19) { # 19

		$peercp_io->{Connected} = 1;
		if (length $peercp_io->{SendBuffer}) {
			printOut($script_io, "\n");	# Next line after activity dots
			changePeerCPStage($mode, 20);	# Move to next stage
		}
		else { # Blocking mode from ACLI> peercp connect
			changePeerCPStage($mode, 0);	# We are complete
			$peercp_io->{CLI}->blocking(0);	# Put object in non-blocking mode
			return 1;
		}

	} # 19

	if ($mode->{peer_cp_stage} == 20) { # 20

		($ok, $outRef) = $peercp_io->{CLI}->cmd($peercp_io->{SendBuffer});
		changePeerCPStage($mode, 21);	# Move to next stage, in all cases
		$host_io->{OutBuffer} .= "\nOutput from Peer CPU:\n";
		if ($ok) { # Unlikely, as always non-blockingmode here
			appendOutDeltaBuffers($db, $outRef);
		}
		elsif (defined $ok) { # Poll
			appendOutDeltaBuffers($db, $outRef);
			return;
		}
		else { # Error
			changePeerCPStage($mode, 990);
		}

	} # 20

	if ($mode->{peer_cp_stage} == 21) { # 21

		($ok, $outRef) = $peercp_io->{CLI}->cmd_poll;
		if (defined $ok) { # Complete, or not ready
			appendOutDeltaBuffers($db, $outRef);
			if (!$peercp_io->{Connect_OOB} && $$outRef =~ /^$ReleaseConnectionPatterns/mo) { # We lost the peer telnet; shut it down
				changePeerCPStage($mode, 990);
			}
			else {
				changePeerCPStage($mode, 0) if $ok;	# We are complete
				return;
			}
		}
		else { # Error
			changePeerCPStage($mode, 990);
		}

	} # 21

	if ($mode->{peer_cp_stage} == 990) { # 990 - Exit Error

		disconnectPeerCP($db);
		$host_io->{OutBuffer} .= "\nConnection to Peer CPU lost\n";
		changePeerCPStage($mode, 0);	# Connection complete
		return;

	} # 990

	if ($mode->{peer_cp_stage} == 999) { # 999 - Exit success

		printOut($script_io, "\n");
		changePeerCPStage($mode, 0);	# Connection complete
		return;

	} # 999
}

1;
