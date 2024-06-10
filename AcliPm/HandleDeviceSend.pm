# ACLI sub-module
package AcliPm::HandleDeviceSend;
our $Version = "1.02";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(handleDeviceSend);
}
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::ChangeMode;
use AcliPm::ConnectDisconnect;
use AcliPm::DebugMessage;
use AcliPm::ExitHandlers;
use AcliPm::GlobalDefaults;
use AcliPm::HandleDeviceOutput;
use AcliPm::Print;


sub handleDeviceSend { # Handles transmission to connected device
	my $db = shift;
	my $mode = $db->[0];
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $peercp_io = $db->[5];

	return unless $host_io->{Connected};						# If no active connection, come out

	if (length $host_io->{SendBuffer}) { # We have data to send
		if ($host_io->{SendBackupCP}) {	# Send command to Standby CPU
			return if $mode->{peer_cp_stage}; # While connecting to PeerCPU
			unless ($peercp_io->{SendBuffer}) { # If not already done
				$peercp_io->{SendBuffer} = $host_io->{SendBuffer};
				chomp $peercp_io->{SendBuffer};		# We are going to use the cmd() method on peer CPU
				printOut($script_io, "\n");		# New line on local term
				if ($peercp_io->{Connected}) {		# If a connection is already in place
					$mode->{peer_cp_stage} = 20;	# Send the command via handleDevicePeerCP
				}
				else {					# If we don't already have a connection to other CPU...
					connectToPeerCP($db);
				}
				return;
			}
			$peercp_io->{SendBuffer} = '';			# We are done
			$host_io->{SendBackupCP} = 0;			# Make sure we don't get back in here
			changeMode($mode, {dev_del => 'ft'}, '#HDS1');	# Do not print \n when removing first line on master
			if ($host_io->{SendMasterCP}) { # There will be output from active CP as well..
				appendOutDeltaBuffers($db, \"\nOutput from Master CPU:\n"); #"
			}
			else { # If we are only sending to Peer CP, then issue just a carriage return on active CP
				$host_io->{CLI}->print;
				return if $host_io->{ConnectionError};
			}
		}
		if ($host_io->{SendMasterCP}) {				# Send command to Master CPU
			$host_io->{CLI}->put($host_io->{SendBuffer});	# Send it
			return if $host_io->{ConnectionError};
		}
		$host_io->{SendBuffer} = '';				# Clear buffer
		$host_io->{OutputSinceSend} = 0;
		$host_io->{KeepAliveUpTime} = time + $host_io->{KeepAliveTimer}*60;	# Reset keepalive timer
		$host_io->{SessionUpTime} = time + $host_io->{SessionTimeout}*60;	# Reset session inactivity timer
		return;
	}
	if (length $host_io->{SendBufferDelay}) { # We have delayed data to send at next cycle
		$host_io->{SendBuffer} = $host_io->{SendBufferDelay};
		$host_io->{SendBufferDelay} = '';
	}

	return if $term_io->{Mode} eq 'transparent' && !$host_io->{TranspKeepAlive};	# No timers in transparent mode if mode is unset

	# Nothing to send & nothing received at last read
	if ($host_io->{SessionTimeout} && time > $host_io->{SessionUpTime}) { # If session timer expired
		disconnect($db, 1);
		printOut($script_io, "\n$ScriptName: Session Timeout\n");
		connectionError($db, 'Session Timeout');
		# We get here from connectionError if QuitOnDisconnect is not true
		return;
	}
	if ($host_io->{KeepAliveTimer} && time > $host_io->{KeepAliveUpTime}) { # If timer expired
		$host_io->{CLI}->put($KeepAliveSequence);			# Send keepalive
		return if $host_io->{ConnectionError};
		$host_io->{KeepAliveUpTime} = time + $host_io->{KeepAliveTimer}*60;	# Reset keepalive timer
		debugMsg(2,"KeepAliveSent!\n");
		return if $script_io->{AcliControl} & 7;
		$mode->{term_in_cache} = $mode->{term_in};
		changeMode($mode, {term_in => 'ib', dev_del => 'kp'}, '#HDS2') unless $term_io->{Mode} eq 'transparent';
	}
}

1;
