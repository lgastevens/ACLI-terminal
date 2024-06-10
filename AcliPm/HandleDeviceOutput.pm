# ACLI sub-module
package AcliPm::HandleDeviceOutput;
our $Version = "1.13";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(handleDeviceOutput appendOutDeltaBuffers);
}
use Term::ReadKey;
use Control::CLI::Extreme qw(:prompt stripLastLine);
use Time::HiRes;
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::ChangeMode;
use AcliPm::ConnectDisconnect;
use AcliPm::DebugMessage;
use AcliPm::ExitHandlers;
use AcliPm::GlobalDefaults;
use AcliPm::GlobalDeviceSettings;
use AcliPm::GlobalMatchingPatterns;
use AcliPm::InputProcessing;
use AcliPm::Print;
use AcliPm::Prompt;
use AcliPm::Sed;
use AcliPm::Socket;
use AcliPm::Sourcing;
use AcliPm::Ssh;
use AcliPm::TerminalServer;
use AcliPm::Variables;


sub promptCredentials { # Basically just adds a \n to promptClear / promptHide
	my ($script_io, $privacy, $credential) = @_;
	my $input;
	printOut($script_io, "\n", "\nEnter $credential:");
	$input = promptClear($credential) if $privacy eq 'Clear';
	$input = promptHide($credential) if $privacy eq 'Hide';
	ReadMode('raw'); # Above methods will do a ReadMode('restore') and we want to stay in raw mode
	return $input;
}


sub changeStage { # Change stage in handleDeviceConnect
	my ($mode, $nextStage) = @_;

	debugMsg(1,"-> Connect Stage $mode->{connect_stage} ==> $nextStage\n");
	$mode->{connect_stage} = $nextStage;
}


sub handleDeviceConnect { # Handles connection to device
	my $db = shift;
	my $mode = $db->[0];
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $prompt = $db->[7];
	my $history = $db->[9];
	my $vars = $db->[12];

	my ($ok, $outRef);

	###########
	# CONNECT #
	###########

	if ($mode->{connect_stage} == 1) { # 1
		$host_io->{CLI}->errmsg('');	# Clear this as Control::CLI does not between connections
		if ($host_io->{RelayHost}) { # Connect via Relay host
			printOut($script_io, "Trying $host_io->{RelayHost} ");
			$ok = $host_io->{CLI}->connect(
				Host			=>	$host_io->{RelayHost},			# Only Telnet
				Port			=>	$host_io->{RelayTcpPort},		# SSH or Telnet
				Username		=>	$host_io->{RelayUsername},		# Relay Username
				Password		=>	$host_io->{RelayPassword},		# Relay Password
				PublicKey		=>	$host_io->{SshPublicKey},		# Only for SSH
				PrivateKey		=>	$host_io->{SshPrivateKey},		# Only for SSH
				BaudRate		=>	$host_io->{RelayBaudrate},		# Only for Serial
				Prompt_credentials	=>	[\&promptCredentials, $script_io],	# Prompt if we don't have them
				Connection_timeout	=>	$host_io->{ConnectTimeout},
				Callback		=>	[\&verifySshHostKey, $db],
			);
		}
		else { # Normal direct connection
			if (defined $host_io->{TcpPort}) {
				printOut($script_io, "Trying $host_io->{Name} port $host_io->{TcpPort} ");
			}
			else {
				printOut($script_io, "Trying $host_io->{Name} ");
			}
			$ok = $host_io->{CLI}->Control::CLI::connect(
				Host			=>	$host_io->{Name},			# SSH or Telnet
				Port			=>	$host_io->{TcpPort},			# SSH or Telnet
				Username		=>	$host_io->{Username},			# Here only set for SSH
				Password		=>	$host_io->{Password},			# Might be set for SSH, if -p flag was set
				PublicKey		=>	$host_io->{SshPublicKey},		# Only for SSH
				PrivateKey		=>	$host_io->{SshPrivateKey},		# Only for SSH
				BaudRate		=>	$host_io->{Baudrate},			# Only for Serial
				Prompt_credentials	=>	$host_io->{ComPort} eq 'SSH' ? [\&promptCredentials, $script_io] : 0, # Only for SSH
				Connection_timeout	=>	$host_io->{ConnectTimeout},
				Callback		=>	[\&verifySshHostKey, $db],
			);
			$host_io->{CLI}->console($host_io->{Console} ? 1 : 0);	# We called SUPER::conect above, so we need to set this after
		}
		if (defined $ok) {
			changeStage($mode, 2);	# Move to next stage
			return unless $ok;	# If $ok is true, go straight to next stage
		}
		else { # Cacth error
			changeStage($mode, 990);
		}

	} # 1

	if ($mode->{connect_stage} == 2) { # 2

		if ($host_io->{RelayHost}) { # Connect via Relay host
			$ok = $host_io->{CLI}->connect_poll;
		}
		else { # Normal direct connection
			$ok = $host_io->{CLI}->Control::CLI::connect_poll;
		}
		if ($ok) { # Done
			$host_io->{Connected} = 1;
			changeStage($mode, 3);	# Move to next stage
			printOut($script_io, "\n");
		}
		elsif (defined $ok) { # Not ready
			printDot($script_io);
			return;
		}
		else { # Error
			changeStage($mode, 990);
		}

	} # 2
	
	if ($mode->{connect_stage} == 3) { # 3

		if ($host_io->{RelayHost}) { # Connect via Relay host
			printOut($script_io, "Connected to Relay Host $host_io->{RelayHost} via $host_io->{ComPort}\n");
			$host_io->{CLI}->print($host_io->{RelayCommand});
			printOut($script_io, "Executing '$host_io->{RelayCommand}' ");
		}
		else { # Normal direct connection
			if (!defined $host_io->{Password} && defined $host_io->{CLI}->password) { # SSH connection when password is prompted by Control::Extreme
				$host_io->{Password} = $host_io->{CLI}->password; # Store that password for future connections
			}
			if ($host_io->{TcpPort}) {
				printOut($script_io, "Connected to $host_io->{Name} via $host_io->{ComPort} on tcp port $host_io->{TcpPort}\n");
			}
			elsif ($host_io->{ComPort} !~ /^(?:TELNET|SSH)$/ && defined $host_io->{Baudrate}) {
				printOut($script_io, "Connected to $host_io->{Name} via $host_io->{ComPort} at baudrate $host_io->{Baudrate}\n");
			}
			else {
				printOut($script_io, "Connected to $host_io->{Name} via $host_io->{ComPort}\n");
			}
		}
		if ($term_io->{AutoDetect} || ($mode->{dev_inp} eq 'ct' && defined $host_io->{Username} && defined $host_io->{Password}) ) { # Do login if in interact mode or if we have credentials
			changeStage($mode, 4);	# Move to next stage
		}
		else {
			changeStage($mode, 999); # Come out
		}

	} # 3
	
	if ($mode->{connect_stage} == 4) { # 4

		($ok, $outRef) = $host_io->{CLI}->login(
			Timeout			=> $host_io->{LoginTimeout},
			Username		=> $host_io->{Username},
			Password		=> $host_io->{Password},
			Read_attempts		=> $LoginReadAttempts[$host_io->{Login} ? 1 : 0],
			Wake_console		=> $mode->{dev_inp} eq 'cp' ? '' : undef,
			Data_with_error		=> 1,
			Non_recognized_login	=> $mode->{dev_inp} eq 'ct' && $host_io->{UnrecogLogins} ? 1 : 0,
			Generic_login		=> $mode->{dev_inp} eq 'ct' && !$term_io->{AutoDetect} ? 1 : 0,
			Errmode			=> 'return',
		);
		debugMsg(2,"==================================\nInitLoginRaw:\n>", $outRef, "<\n") if length $$outRef;
		changeStage($mode, 5);	# Move to next stage
		return ($outRef, 1, $ok);

	} # 4
	
	if ($mode->{connect_stage} == 5) { # 5
		$ok = $host_io->{CLI}->login_poll;
		if (defined $ok && $ok == 0) { # Not ready
			printOut($script_io, "$ScriptName: Performing login ") unless $host_io->{RelayHost} || $host_io->{Login};
		}
		changeStage($mode, 6);	# Move to next stage

	} # 5

	if ($mode->{connect_stage} == 6) { # 6
		$ok = $host_io->{CLI}->login_poll;
		if (defined $ok && $ok == 0) { # Not ready
			printDot($script_io) unless $host_io->{Login};
			return;
		}
		else { # Finished or Error
			$outRef = ($host_io->{CLI}->login_poll)[1]; # Retrieve output now
			if (length $$outRef) {
				debugMsg(2,"==================================\nInitLoginPollRaw:\n>", $outRef, "<\n");
				if ($host_io->{RelayHost} && $$outRef =~ /^$RelayAgentFailPatterns/mo) {
					debugMsg(2,"Detected relay agent failure to connect to target host\n");
					$ok = undef;	# Force a failure (even if login() did succeed to relay host
					$host_io->{CLI}->errmsg('Relay-Connection-Failure');
				}
			}

			if ($mode->{dev_inp} eq 'ct' && !$term_io->{AutoDetect}) { # We get here if in transparent mode but with both username & passwords supplied (from connect stage 3)
				printOut($script_io, "\n");
				changeStage($mode, 999);
				return $outRef;
			}
			elsif ($ok) { # Finished
				#
				# Auto-Detection of host type
				#
				$host_io->{Login} = 1;
				$host_io->{Type} = $host_io->{CLI}->attribute('family_type');
				debugMsg(1,"-> HostType detected = $host_io->{Type}\n");
				debugMsg(1,"-> CapabilityMode = ", \$host_io->{CapabilityMode}, "\n");
				unless (defined $host_io->{CapabilityMode}) { # Except if it was manually set in ACLI> (or was already set on console/annex and we rebooted the switch..)
					$host_io->{CapabilityMode} = $Default{family_type_interact_flg}{$host_io->{Type}} ? 'interact' : 'transparent';
					debugMsg(1,"-> New CapabilityMode = ", \$host_io->{CapabilityMode}, "\n");
				}
				$term_io->{Mode} = $host_io->{CapabilityMode};
				debugMsg(1,"-> Mode = $term_io->{Mode}\n");
	
				# Embed messages in output
				my $lastLinePrompt = stripLastLine($outRef);
				$$outRef .= "\n" unless length $$outRef; # Make sure we have at least 1 empty line, else InitLogin-cleanup1 below will remove our lines:
									 # "Not an Extreme Networks device" or "Detected an Extreme Networks device"
				if ($mode->{dev_inp} eq 'ct' || $mode->{dev_inp} eq 'lg' || $mode->{dev_inp} eq 'cp') {
					if ($host_io->{Type} eq 'generic') {
						$$outRef .= "$ScriptName: Not an Extreme Networks device" unless $mode->{dev_inp} eq 'cp';
						# Can happen that @rediscovery of device fails, and we detect generic, but CapabilityMode is still set to interact
						# and so $term_io->{Mode} will be set to the same..
						$term_io->{Mode} = 'transparent';	# We cannot be in interactive mode on a generic device, things go wrong..
						$host_io->{CapabilityMode} = undef;	# Undefine this, so that by doing CTRL-T we can have a 2nd shot and recover
						$host_io->{Discovery} = undef;	# Make sure we don't try any further fast switch backs to interact mode (bug22)
					}
					else {
						$$outRef .= "$ScriptName: Detected an Extreme Networks device" unless $mode->{dev_inp} eq 'cp';
					}
					# Disable auto-login, otheriwse if login credentials were not default, they will be overridden
					$term_io->{AutoLogin} = 0;
				}
				if ($term_io->{Mode} eq 'interact') {
					$$outRef .= " -> using terminal interactive mode\n" if $mode->{dev_inp} eq 'ct' || $mode->{dev_inp} eq 'lg';
					$prompt->{Match} = $host_io->{CLI}->prompt;
					$prompt->{Match} =~ s/^\\x0d\? \*\\x0d//; # Remove SecureRouter sequence prior to prompt..
					$prompt->{Regex} = qr/($prompt->{Match})/;
					chop($prompt->{Match});	# Chop off trailing $
					debugMsg(1,"-> HostPrompt = \"$prompt->{Match}\"\n");
					$prompt->{More} = $host_io->{CLI}->more_prompt;
					debugMsg(1,"-> HostMorePrompt = \"$prompt->{More}\"\n");
					$prompt->{MoreRegex} = $prompt->{More} ? qr/$prompt->{More}/ : undef; # Undef on Ipanema
					$term_io->{AcliType} = $host_io->{CLI}->attribute('is_acli');
		
					if ($mode->{dev_inp} eq 'cp') { # Come out if in 'cp' mode
						changeMode($mode, {dev_inp => 'rd'}, '#HDO1');	# Disable 'cp' mode
						changeStage($mode, 0);
					}
					else { # 'ct' or 'lg' or 'sb' modes
						changeStage($mode, 7);		# Move to next stage
					}
				}
				else { # Undefine them
					$$outRef .= " -> using terminal transparent mode\n" if $mode->{dev_inp} eq 'ct' || $mode->{dev_inp} eq 'lg';
					$term_io->{AcliType} = undef;
					$host_io->{Model} = $host_io->{Sysname} = '';
					($prompt->{Match}, $prompt->{Regex}, $prompt->{More}, $prompt->{MoreRegex}) = ();
					($host_io->{CpuSlot}, $host_io->{MasterCpu}, $host_io->{DualCP}, $host_io->{BaseMAC}) = (); 
					($host_io->{SwitchMode}, $host_io->{UnitNumber}, $host_io->{Slots}, $host_io->{Ports}) = ();
					changeStage($mode, 992);		# Move to next stage
				}
				$$outRef .= $lastLinePrompt;
				return ($outRef, 1, 1);
			}
			# Error
			changeStage($mode, 100);	# Login failed
		}

	} # 6

	#
	# Login succeeded
	#
	
	if ($mode->{connect_stage} == 7) { # 7

		# if $term_io->{Mode} eq 'interact' && $mode->{dev_inp} eq 'ct' or 'lg' or 'sb'
		#
		# Set default settings we want to push on the host device in interactive mode
		#
		if ($host_io->{Type} eq 'BaystackERS') { # Baystack terminal set
			($ok) = $host_io->{CLI}->cmd( # Max out terminal width
				Command		=>	"terminal width $TermWidth",
				Errmode		=>	'return',
			);
			if (defined $ok) { # no error
				changeStage($mode, 8);	# Move to next stage
				return unless $ok;	# If $ok is true, go straight to next stage
			}
			# catch error
			changeStage($mode, 992);	# Move to next stage
		}
		else {
			changeStage($mode, 9);		# Move to next stage
		}

	} # 7

	if ($mode->{connect_stage} == 8) { # 8

		($ok) = $host_io->{CLI}->cmd_poll;
		changeStage($mode, 992) unless defined $ok; # Catch error
		changeStage($mode, 9) if $ok;
		return if defined $ok && $ok == 0; # Not ready

	} # 8

	if ($mode->{connect_stage} == 9) { # 9

		if ($term_io->{AcliType} && $host_io->{CLI}->last_prompt =~ />$/) {
			# Automatically enter priv-exec mode if terminal type is ACLI/NNCLI
			$ok = $host_io->{CLI}->enable( Errmode => 'return' );
			changeStage($mode, 992) unless defined $ok; 	# Catch error
			changeStage($mode, 10) if defined $ok;		# Move to next stage
			$$outRef .= "enable";		# Print out enable, so that user sees what's happening
			return $outRef;
		}
		elsif ($mode->{dev_inp} eq 'sb') {
			changeStage($mode, 992);	# Move to next stage
		}
		else {
			changeStage($mode, 11);		# Move to next stage
		}

	} # 9

	if ($mode->{connect_stage} == 10) { # 10

		$ok = $host_io->{CLI}->enable_poll;
		changeStage($mode, 992) unless defined $ok; # Catch error
		changeStage($mode, 11) if $ok;
		return if defined $ok && $ok ==0; # Not ready
		changeStage($mode, 992) if $mode->{dev_inp} eq 'sb';

	} # 10

	if ($mode->{connect_stage} == 11) { # 11

		printOut($script_io, "\n$ScriptName: Detecting device ");
		if ($host_io->{Type} eq 'PassportERS') { # PassportERS attributes

			# Attributes which require no commands
			$host_io->{CpuSlot} = $host_io->{CLI}->attribute('cpu_slot');
			debugMsg(1,"-> CpuSlot = ", \$host_io->{CpuSlot}, "\n");
			$host_io->{MasterCpu} = $host_io->{CLI}->attribute('is_master_cpu');
			debugMsg(1,"-> Is Master = ", \$host_io->{MasterCpu}, "\n");
			# Attributes below require commands to be sent to device (introduces a login delay)
			# Order is important to make sure we get all info with minimum commands
			($ok) = $host_io->{CLI}->attribute(
				Attribute	=>	'is_dual_cpu',
				Errmode		=>	'return',
			);
			printDot($script_io);
			if (defined $ok) {
				changeStage($mode, 12);
				return unless $ok;	# If $ok is true, go straight to next stage
			}
			else { # Catch error
				changeStage($mode, 991);
			}
		}
		else {
			changeStage($mode, 13);
		}

	} # 11

	if ($mode->{connect_stage} == 12) { # 12

		($ok, $host_io->{DualCP}) = $host_io->{CLI}->attribute_poll;
		printDot($script_io);
		changeStage($mode, 991) unless defined $ok; # Catch error
		changeStage($mode, 13) if $ok;
		return if defined $ok && $ok == 0; # Not ready
		debugMsg(1,"-> DualCP = ", \$host_io->{DualCP}, "\n");

	} # 12

	if ($mode->{connect_stage} == 13) { # 13

		$host_io->{PreviousMAC} = $host_io->{BaseMAC} || '';
		($ok) = $host_io->{CLI}->attribute(
			Attribute	=>	'base_mac',
			Errmode		=>	'return',
		);
		printDot($script_io);
		if (defined $ok) {
			changeStage($mode, 14);
			return unless $ok;	# If $ok is true, go straight to next stage
		}
		else { # Catch error
			changeStage($mode, 991);
		}

	} # 13

	if ($mode->{connect_stage} == 14) { # 14

		($ok, $host_io->{BaseMAC}) = $host_io->{CLI}->attribute_poll;
		printDot($script_io);
		changeStage($mode, 991) unless defined $ok; # Catch error
		changeStage($mode, 15) if $ok;
		return if defined $ok && $ok == 0; # Not ready
		debugMsg(1,"-> BaseMAC = ", \$host_io->{BaseMAC}, "\n");

	} # 14

	if ($mode->{connect_stage} == 15) { # 15

		($ok) = $host_io->{CLI}->attribute( # model & sysname after dual_cpu...
			Attribute	=>	'model',
			Errmode		=>	'return',
		);
		printDot($script_io);
		if (defined $ok) {
			changeStage($mode, 16);
			return unless $ok;	# If $ok is true, go straight to next stage
		}
		else { # Catch error
			changeStage($mode, 991);
		}

	} # 15

	if ($mode->{connect_stage} == 16) { # 16

		($ok, $host_io->{Model}) = $host_io->{CLI}->attribute_poll;
		printDot($script_io);
		changeStage($mode, 991) unless defined $ok; # Catch error
		changeStage($mode, 17) if $ok;
		return if defined $ok && $ok == 0; # Not ready
		debugMsg(1,"-> Model detected = ", \$host_io->{Model}, "\n");

	} # 16

	if ($mode->{connect_stage} == 17) { # 17

		($ok) = $host_io->{CLI}->attribute( # ... otherwise 2 show sys on PassportERS
			Attribute	=>	'sysname',
			Errmode		=>	'return',
		);
		printDot($script_io);
		if (defined $ok) {
			changeStage($mode, 18);
			return unless $ok;	# If $ok is true, go straight to next stage
		}
		else { # Catch error
			changeStage($mode, 991);
		}

	} # 17

	if ($mode->{connect_stage} == 18) { # 18

		($ok, $host_io->{Sysname}) = $host_io->{CLI}->attribute_poll;
		printDot($script_io);
		changeStage($mode, 991) unless defined $ok; # Catch error
		changeStage($mode, 19) if $ok;
		return if defined $ok && $ok == 0; # Not ready
		unless (defined $host_io->{Sysname}) { # On Standby CPUs, use prompt to obtain system name
			$host_io->{CLI}->last_prompt =~ /$prompt->{Regex}/;
			if (defined $1) {
				$host_io->{Prompt} = $1; # Used to pass $1 directly as arg to switchname(), but changed it for XOS prompts 
				$host_io->{Sysname} = switchname($host_io, 1);
			}
			else {
				$host_io->{Sysname} = ''; # Give up
			}
		}
		debugMsg(1,"-> Sysname = ", \$host_io->{Sysname}, "\n");

	} # 18

	if ($mode->{connect_stage} == 19) { # 19

		($ok) = $host_io->{CLI}->attribute( # On a Master CPU, this would already be set and not require polling...
			Attribute	=>	'is_voss',
			Errmode		=>	'return',
		);
		printDot($script_io);
		if (defined $ok) {
			changeStage($mode, 20);
			return unless $ok;	# If $ok is true, go straight to next stage
		}
		else { # Catch error
			changeStage($mode, 991);
		}

	} # 19

	if ($mode->{connect_stage} == 20) { # 20

		($ok, $host_io->{VOSS}) = $host_io->{CLI}->attribute_poll;
		printDot($script_io);
		changeStage($mode, 991) unless defined $ok; # Catch error
		changeStage($mode, 21) if $ok;
		return if defined $ok && $ok == 0; # Not ready
		debugMsg(1,"-> VOSS = ", \$host_io->{VOSS}, "\n");

		# By this stage is_apls is already set
		$host_io->{APLS} = $host_io->{CLI}->attribute('is_apls');
		debugMsg(1,"-> APLS = ", \$host_io->{APLS}, "\n");

	} # 20

	if ($mode->{connect_stage} == 21) { # 21

		if ($host_io->{Type} eq 'BaystackERS' || $host_io->{Type} eq 'ExtremeXOS') { # BaystackERS & ExtremeXOS attributes

			($ok) = $host_io->{CLI}->attribute(
				Attribute	=>	'switch_mode',
				Errmode		=>	'return',
			);
			printDot($script_io);
			if (defined $ok) {
				changeStage($mode, 22);
				return unless $ok;	# If $ok is true, go straight to next stage
			}
			else { # Catch error
				changeStage($mode, 991);
			}
		}
		else {
			changeStage($mode, 25);
		}

	} # 21

	if ($mode->{connect_stage} == 22) { # 22

		($ok, $host_io->{SwitchMode}) = $host_io->{CLI}->attribute_poll;
		printDot($script_io);
		changeStage($mode, 991) unless defined $ok; # Catch error
		changeStage($mode, 23) if $ok;
		return if defined $ok && $ok == 0; # Not ready
		debugMsg(1,"-> SwitchMode = ", \$host_io->{SwitchMode}, "\n");

	} # 22

	if ($mode->{connect_stage} == 23) { # 23

		($ok) = $host_io->{CLI}->attribute(
			Attribute	=>	'unit_number',
			Errmode		=>	'return',
		);
		printDot($script_io);
		if (defined $ok) {
			changeStage($mode, 24);
			return unless $ok;	# If $ok is true, go straight to next stage
		}
		else { # Catch error
			changeStage($mode, 991);
		}

	} # 23

	if ($mode->{connect_stage} == 24) { # 24

		($ok, $host_io->{UnitNumber}) = $host_io->{CLI}->attribute_poll;
		printDot($script_io);
		changeStage($mode, 991) unless defined $ok; # Catch error
		changeStage($mode, 25) if $ok;
		return if defined $ok && $ok ==0; # Not ready
		debugMsg(1,"-> UnitNumber = ", \$host_io->{UnitNumber}, "\n");

	} # 24

	if ($mode->{connect_stage} == 25) { # 25

		if (defined $host_io->{Model}) {
			foreach my $model (@{$DeviceMorePaging{$host_io->{Type}}}) {
				unless (defined $model) { # Device not supporting configuration of more paging
					changeStage($mode, 27);			# Move to next stage
					last;
				}
				if ($host_io->{Model} =~ /$model->[0]/) {
					debugMsg(1,"-> More Paging $host_io->{Type} Model = \'$model->[0]\'; ");
					if ($model->[1+$host_io->{Console}] >= 2) { # Sync mode
						$host_io->{MorePagingInit} = undef;
						$host_io->{MorePaging} = $term_io->{MorePaging};
						$host_io->{SyncMorePaging} = 0;
						debugMsg(1,"use mode = sync\n");
					}
					else { #Static mode
						$host_io->{MorePaging} = $host_io->{MorePagingInit} = $model->[1+$host_io->{Console}];
						$host_io->{SyncMorePaging} = undef;
						debugMsg(1,"use mode = static($model->[1])\n");
					}
					# Record slot & port attributes before enabling more paging
					# so in all cases, start by disabling it
					$ok = $host_io->{CLI}->device_more_paging(
						Enable	=>	0,
						Errmode	=>	'return',
					);
					printDot($script_io);
					changeStage($mode, 991) unless defined $ok;	# Catch error
					changeStage($mode, 26) if defined $ok;		# Move to next stage
					last;
				}
			}
			return;
		}
		else {
			changeStage($mode, 33);		# Move to next stage
		}

	} # 25

	if ($mode->{connect_stage} == 26) { # 26

		$ok = $host_io->{CLI}->device_more_paging_poll;
		printDot($script_io);
		changeStage($mode, 991) unless defined $ok; # Catch error
		changeStage($mode, 27) if $ok;
		return if defined $ok && $ok ==0; # Not ready

	} # 26

	if ($mode->{connect_stage} == 27) { # 27

		($ok) = $host_io->{CLI}->attribute(
			Attribute	=>	'slots',
			Errmode		=>	'return',
		);
		printDot($script_io);
		if (defined $ok) {
			changeStage($mode, 28);
			return unless $ok;	# If $ok is true, go straight to next stage
		}
		else { # Catch error
			changeStage($mode, 991);
		}

	} # 27

	if ($mode->{connect_stage} == 28) { # 28

		($ok, $host_io->{Slots}) = $host_io->{CLI}->attribute_poll;
		printDot($script_io);
		changeStage($mode, 991) unless defined $ok; # Catch error
		changeStage($mode, 29) if $ok;
		return if defined $ok && $ok == 0; # Not ready
		debugMsg(1,"-> Slots detected = ", \$host_io->{Slots}, "\n");

	} # 28

	if ($mode->{connect_stage} == 29) { # 29

		($ok) = $host_io->{CLI}->attribute(
			Attribute	=>	'ports',
			Errmode		=>	'return',
		);
		printDot($script_io);
		if (defined $ok) {
			changeStage($mode, 30);
			return unless $ok;	# If $ok is true, go straight to next stage
		}
		else { # Catch error
			changeStage($mode, 991);
		}

	} # 29

	if ($mode->{connect_stage} == 30) { # 30

		($ok, $host_io->{Ports}) = $host_io->{CLI}->attribute_poll;
		printDot($script_io);
		changeStage($mode, 991) unless defined $ok; # Catch error
		changeStage($mode, 31) if $ok;
		return if defined $ok && $ok == 0; # Not ready
		debugMsg(1,"-> Ports detected = ", \$host_io->{Ports}, "\n");

	} # 30

	if ($mode->{connect_stage} == 31) { # 31

		if ($host_io->{MorePaging}) {
			$ok = $host_io->{CLI}->device_more_paging(
				Enable	=>	1,
				Errmode	=>	'return',
			);
			printDot($script_io);
			changeStage($mode, 991) unless defined $ok;	# Catch error
			changeStage($mode, 32) if defined $ok;		# Move to next stage
			return if defined $ok && $ok ==0;		# Not ready
		}
		else {
			changeStage($mode, 33);		# Move to next stage
		}

	} # 31

	if ($mode->{connect_stage} == 32) { # 32

		$ok = $host_io->{CLI}->device_more_paging_poll;
		printDot($script_io);
		changeStage($mode, 991) unless defined $ok; # Catch error
		changeStage($mode, 33) if $ok;
		return if defined $ok && $ok ==0; # Not ready

	} # 32

	if ($mode->{connect_stage} == 33) { # 33

		$$outRef .= "\n$ScriptName: Detected ";
		if (defined $host_io->{Model}) {
			$$outRef .= $host_io->{Model} . " ";
		}
		else {
			$$outRef .= "VOSS VSP " if $host_io->{Type} eq 'PassportERS' && $host_io->{VOSS};
			$$outRef .= "Modular ERS " if $host_io->{Type} eq 'PassportERS' && !$host_io->{VOSS};
			$$outRef .= "Stackable ES/ERS/VSP " if $host_io->{Type} eq 'BaystackERS';
			$$outRef .= "Extreme XOS " if $host_io->{Type} eq 'ExtremeXOS';
			$$outRef .= "Accelar " if $host_io->{Type} eq 'Accelar';
			$$outRef .= "Secure Router " if $host_io->{Type} eq 'SecureRouter';
			$$outRef .= "WLAN 2300 " if $host_io->{Type} eq 'WLAN2300';
			$$outRef .= "WLAN 9100 " if $host_io->{Type} eq 'WLAN9100';
		}
		if (defined $host_io->{BaseMAC}) {
			$$outRef .= "(";
			$$outRef .= $host_io->{BaseMAC};
			$$outRef .= ") ";
		}
		if (($host_io->{Type} eq 'BaystackERS' || $host_io->{Type} eq 'ExtremeXOS') && defined $host_io->{SwitchMode}) {
			$$outRef .= "Standalone " if $host_io->{SwitchMode} eq 'Switch';
			$$outRef .= $host_io->{SwitchMode};
			$$outRef .= " of " . scalar @{$host_io->{Slots}} . " units" if $host_io->{SwitchMode} eq 'Stack' && defined $host_io->{Slots};
		}
		elsif ( ($host_io->{Type} eq 'PassportERS' && $host_io->{MasterCpu}) || $host_io->{Type} eq 'Accelar') {
			if ($host_io->{DualCP}) {
				$$outRef .= "Dual CPU system, ";
				if (defined $host_io->{Slots}) {
					$$outRef .= scalar @{$host_io->{Slots}} . " slot";
					$$outRef .= "s" if $#{$host_io->{Slots}};
				}
			}
			else {
				$$outRef .= "Single CPU system, ";
				if (defined $host_io->{Slots}) {
					$$outRef .= scalar @{$host_io->{Slots}} . " slot";
					$$outRef .= "s" if $#{$host_io->{Slots}};
				}
			}
		}
		elsif ($host_io->{Type} eq 'PassportERS') {
			$$outRef .= "Standby CPU";
			if (defined $host_io->{Slots}) {
				$$outRef .= ", " . scalar @{$host_io->{Slots}} . " slot";
				$$outRef .= "s" if $#{$host_io->{Slots}};
			}
		}
		if (defined $host_io->{Slots}) { # If defined, attribute holds slot/port data
			my $portCount = 0;
			if (@{$host_io->{Slots}}) { # Slot/Port structure
				foreach my $slot (@{$host_io->{Slots}}) {
					if (ref $host_io->{Ports} eq 'HASH') {
						$portCount += scalar @{$host_io->{Ports}->{$slot}} if ref $host_io->{Ports}->{$slot};
					}
					else {
						$portCount += scalar @{$host_io->{Ports}->[$slot]} if ref $host_io->{Ports}->[$slot];
					}
				}
			}
			elsif (ref($host_io->{Ports}) eq 'ARRAY') { # Port structure (no slots) / with ISW might be a HASH
				$portCount += scalar @{$host_io->{Ports}};
			}
			$$outRef .= " $portCount ports";
		}
		$$outRef .= "\n";
		printOut($script_io, $$outRef);
		$host_io->{Discovery} = 1;

		if (!defined $host_io->{BaseMAC}) {
			%$vars = ();
		}
		loadVarFile($db, defined $host_io->{BaseMAC} && $host_io->{PreviousMAC} eq $host_io->{BaseMAC}); # Read in stored variables if a new device
		updateTrmSrvFile($db) if $host_io->{RemoteAnnex};
		printOut($script_io, "$ScriptName: Use '$term_io->{CtrlInteractPrn}' to toggle between interactive & transparent modes\n");
		changeStage($mode, 992);

	} # 33

	#
	# Login failed
	#

	if ($mode->{connect_stage} == 100) { # 100

		debugMsg(1,"-> login errmsg: " . $host_io->{CLI}->errmsg . "\n");
		# If a username/password is required then not an error for us as we handle this interactively
		if ($host_io->{CLI}->errmsg =~ /Non recognized login output/i) {
			debugMsg(2,"LoginErr-NonRecognizedLoginOutput\n");
			if ($host_io->{UnrecogLogins}-- > 0) {
				changeMode($mode, {term_in => 'sh', dev_inp => 'ld'}, '#HDO2');	# Let user send to host directly.
				changeStage($mode, 4);			# Come back to login()
				return ($outRef, 1, 0);
			}
			changeStage($mode, 999); # Come out
			return ($outRef, 1, 0);
		}
		elsif ($host_io->{CLI}->errmsg =~ /username required/i) {
			if ($term_io->{AutoLogin}) {
				my $matchedBanner;
				foreach my $type (keys %BannerPatterns) {
					if ($$outRef =~ /$BannerPatterns{$type}/) {
						debugMsg(1,"LoginErr-DetectedBanner of: ", \$type, "\n");
						$host_io->{Username} = $DefaultCredentials{Username}{$type};
						$host_io->{Password} = $DefaultCredentials{Password}{$type};
						$matchedBanner = 1;
						last;
					}
				}
				unless ($matchedBanner) { # If nothing matched, use the fallback passwords
					debugMsg(1,"LoginErr-NoBannerMatch-using fallback\n");
					$host_io->{Username} = $DefaultCredentials{Username}{fallback} unless defined $host_io->{Username};
					$host_io->{Password} = $DefaultCredentials{Password}{fallback} unless defined $host_io->{Password};
				}
			}
			if ($host_io->{Username}) {
				$$outRef .= $host_io->{Username};	# Add username to be printed on screen
			}
			else {
				changeMode($mode, {term_in => 'us', dev_inp => 'ds'}, '#HDO3');	# Username input
			}
			changeStage($mode, 4);			# Come back to login()
			$host_io->{Login} = 1;
			return ($outRef, 1, 0);
		}
		elsif ($host_io->{CLI}->errmsg =~ /password required/i) {
			changeMode($mode, {term_in => 'pw', dev_inp => 'ds'}, '#HDO4');	# Password input
			changeStage($mode, 4);			# Come back to login()
			$host_io->{Login} = 1;
			return ($outRef, 1, 0);
		}
		elsif ($host_io->{CLI}->errmsg =~ /incorrect username or password/i) {
			$host_io->{Username} = undef;
			$host_io->{Password} = undef;
			unless (@{$term_io->{ConnectHistory}}) { # Only if not telnet hopping
				printOut($script_io, "\nIncorrect Username or Password\n");
				printOut($script_io, "$ScriptName: Auto-login disabled\n") if $term_io->{AutoLogin};
				$host_io->{CLI}->disconnect;
				$term_io->{AutoLogin} = 0;
				connectionError($db, 'Login with incorrect username or password');
				# We get here from connectionError if QuitOnDisconnect is not true
				changeStage($mode, 0);
				return;
			}
			$$outRef =~ s/\*\x0d?\n/\*\nIncorrect Username or Password\n/; # Insert message in output
			$$outRef = "\nIncorrect Username or Password\n" unless length $$outRef; # Add message if no output
			debugMsg(2,"LoginErr:\n>", $outRef, "<\n");
			if ($$outRef =~ /(?i:username|login)[: ]+$/) { # We can try a new login...
				debugMsg(2,"LoginErr-NewLoginAttempting\n");
				changeMode($mode, {term_in => 'us', dev_inp => 'ds'}, '#HDO5');	# Username input
				changeStage($mode, 4);			# Come back to login()
				return ($outRef, 1, 0);
			}
			if ($$outRef =~ /(?i:password)[: ]+$/) { # We can try a new login...
				debugMsg(2,"LoginErr-NewLoginPasswordAttempting\n");
				changeMode($mode, {term_in => 'pw', dev_inp => 'ds'}, '#HDO6');	# Username input
				changeStage($mode, 4);			# Come back to login()
				return ($outRef, 1, 0);
			}
			changeStage($mode, 992);		# Move to next stage
			return;
		}
		elsif ($host_io->{CLI}->errmsg =~ /Failed reading login prompt/ && $host_io->{ComPort} =~ /^(?:TELNET|SSH)$/ && length $$outRef) {
			# Connecting to a remote annex box will land us here, as login() can't find a prompt
			debugMsg(2,"LoginErr-SendCarriageReturn\n");
			changeStage($mode, 992);
			return ($outRef, 1);
		}
		elsif ($host_io->{CLI}->errmsg =~ /Relay-Connection-Failure/) { # Exception for Relay Failure, primed in stage 6
			debugMsg(2,"LoginErr-RealyFailedToExecute\n");
			changeStage($mode, 899);
			return ($outRef, 1);
		}
		elsif (length $$outRef) {
			# On 8600, Telnet, before system up: "Sorry, System not up yet."
			# With Control::CLI 2.02 && Control::CLI::AvayaData 2.01 error is login_poll: No connection to login to
			debugMsg(2,"LoginErr-Timeout with Output\n");
			changeStage($mode, 999);
			return ($outRef, 1);
		}
		else { # Anything else (including Relay Failure), bomb out
			debugMsg(2,"LoginErr-Other error\n");
			$host_io->{CLI}->disconnect; # Added to make serial connection with nothing connected to cable behave correctly: acli-dev.pl serial:COM6
			connectionError($db, $host_io->{CLI}->errmsg); # Handling other login error
			# We get here from connectionError if QuitOnDisconnect is not true
			changeStage($mode, 0);
			return;
		}

	} # 100

	if ($mode->{connect_stage} == 899) { # 899 - Delayed disconnect, so that output could be printed first
		$host_io->{CLI}->disconnect;
		connectionError($db, 'Disconnect after relay conection failure');
		changeStage($mode, 0);
		return;
	} # 899

	if ($mode->{connect_stage} == 990) { # 990 - Exit connection failure
		changeStage($mode, 0);
		return;
	} # 990

	if ($mode->{connect_stage} == 991) { # 991 - Exit connect success but login/autodetect fail, print new line
		printOut($script_io, "\n");
		changeStage($mode, 992);
	} # 991

	if ($mode->{connect_stage} == 992) { # 992 - Exit connect & print new line
		$host_io->{SendBuffer} = $term_io->{Newline};	# Get a fresh new prompt
		changeStage($mode, 999);
	} # 992

	if ($mode->{connect_stage} == 999) { # 999 - Exit success

		changeStage($mode, 0);	# Connection complete
		changeMode($mode, {term_in => 'sh', dev_inp => 'rd'}, '#HDO7');	# Disable login
		$script_io->{ConnectFailMode} = 0;
		$history->{Current} = $history->{HostRecall};
		return;

	} # 999
}


sub handleDeviceOutput { # Handles reception of output from connectyed device
	my $db = shift;
	my $mode = $db->[0];
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $peercp_io = $db->[5];
	my $socket_io = $db->[6];
	my $prompt = $db->[7];
	my $termbuf = $db->[8];
	my $vars = $db->[12];

	my $outRef = \''; #'
	my ($loginSuccess, $readLogin, $doNotCacheLastLine);	# Keep track if output was read with login() or read()

	return if $mode->{dev_inp} eq 'ds';	# Come out if we are in disabled state

	if ( ($mode->{dev_inp} eq 'rd' || $mode->{connect_stage} > 6) && $host_io->{CLI}->eof) {
		connectionError($db, 'Connection lost (EOF)');
		# We get here from connectionError if QuitOnDisconnect is not true
		return;
	}

	###########
	# CONNECT #
	###########

	if ($mode->{dev_inp} eq 'ld') { # Login is delayed, allowing user to interact with non recognized login output
		$outRef = $host_io->{CLI}->read(Blocking => 0); # Read in data, if immediately available
		return if $host_io->{ConnectionError};
		return unless length $$outRef;	# Nothing to read, no change
		# If we get here, user interaction has resulted in new output; we may want to re-run login() on it..
		# Code below needs to be tested with EXOS configured with 'banner before-login & acknowledge'
		# and with VOSS8.5 after defaulting switch so that it does DHCP and asks for a new password on 1st login
		if ($$outRef =~ /\n/) {
			if ($$outRef =~ /$LoginDelayPatterns/) {
				debugMsg(1,"-> Login Delayed, pattern to hold login till next cycle: >", $outRef, "<\n");
				printOut($script_io, '', '', $outRef);
				return;
			}
		}
		elsif ($$outRef !~ /[: ]+$/) {
			debugMsg(1,"-> Login Delayed, single line, holding login till next cycle: >", $outRef, "<\n");
			printOut($script_io, '', '', $outRef);
			return;
		}
		# If we get here, we trigger a new login attempt
		printOut($script_io, "\n");
		$host_io->{CLI}->{BUFFER} = $$outRef; # Cheat! Shove it all back onto Control::CLI's internal buffer to read again
		changeMode($mode, {term_in => 'rk', dev_inp => 'lg'}, '#HDO8');	# Resume login
	}

	if ($mode->{dev_inp} eq 'ct' || $mode->{dev_inp} eq 'lg' || $mode->{dev_inp} eq 'cp' || $mode->{dev_inp} eq 'sb') {

		unless ($mode->{connect_stage}) { # Init stage
			if ($mode->{dev_inp} eq 'ct') {
				$mode->{connect_stage} = 1; # Connect
			}
			else {
				$mode->{connect_stage} = 4; # Modes 'lg', 'cp', 'sb': re-login or change prompt
			}
			debugMsg(1,"-> Init Connect Stage to ", \$mode->{connect_stage}, "<\n");
		}
		($outRef, $readLogin, $loginSuccess) = handleDeviceConnect($db);
		$outRef = \'' unless defined $outRef; #'
		debugMsg(2,"==================================\nDeviceConnect:\n>", $outRef, "<\n") if length $$outRef;
	}

	###########
	# READ    #
	###########

	elsif ($mode->{dev_inp} eq 'rd') {
		# Normal read, once connection established
		#
		$outRef = $host_io->{CLI}->read(Blocking => 0); # Read in data, if immediately available
		return if $host_io->{ConnectionError};
		debugMsg(2,"==================================\nDeviceReadRaw:\n>", $outRef, "<\n") if length $$outRef;
	}
	elsif ($mode->{dev_inp} eq 'si') {
		my ($file, $output, $done);
		if ($file = shift @{$script_io->{ConfigFileList}}) { # Read from file
			debugMsg(2,"Grep Streaming / ReadFile: $file\n");
			open(CONFIG, '<', $file) or quit(1, "Unable to open config file $file", $db);
			local $/;	# Read in file in one shot
			$output = <CONFIG>;
			close CONFIG;
			if ($output =~ /^\xff\xfe/) { # File is Unicode; see https://unicode.org/faq/utf_bom.html#bom1
				# Re-open again the file and read it as UTF-16 this time
				debugMsg(2,"Grep Streaming / ReadFile is UTF-16: $file\n");
				open(CONFIG, '<:encoding(UTF-16)', $file) or quit(1, "Unable to open (as UTF-16) config file $file", $db);
				local $/;	# Read in file in one shot
				$output = <CONFIG>;
				close CONFIG;
			}
			$done = 1 unless @{$script_io->{ConfigFileList}};
			$host_io->{Type} = undef unless $script_io->{GrepForceType}; # Force new detection at each file except if -f switch was used
		}
		else {	# Grep streaming mode - we just read from STDIN
			while (<STDIN>) {
				$done = s/\cZ$//;
				$output .= $_;
				last if $done;
			}
		}
		if (length $output) {
			unless ($host_io->{Type}) { # Simple detection
				if ($output =~ /^! Embedded ASCII Configuration Generator Script/m) { # Detect Stackable config
					$host_io->{Type} = 'BaystackERS';
				}
				else { # else assume PassportERS
					$host_io->{Type} = 'PassportERS';
				}
				debugMsg(2,"Grep Streaming / Using family_type: ", \$host_io->{Type}, "\n");
			}
			prepGrepStructure($db, $script_io->{GrepStrmParsed}, 1, $script_io->{GrepMultiple} ? $file : undef);
			sedPatternReplace($host_io, $term_io->{SedOutputPats}, \$output);
			$host_io->{OutBuffer} .= $output;
			debugMsg(2,"Grep Streaming / Appended to Output Buffer:\n>", \$output, "<\n");
		}
		if (!defined $output || $done) { # No more data to read..
			$script_io->{GrepStream} = ''; # ..we will exit after having printed this out
		}
		return;
	}
	else {
		quit(1, "ERROR: unexpected dev_inp mode: ".$mode->{dev_inp}, $db);
	}
	###########
	# PROCESS #
	###########
	if (length $$outRef) { # We have new output to process
		$host_io->{OutputSinceSend} = 1;
		$host_io->{DeviceReadFlag} = 1;
		$host_io->{KeepAliveUpTime} = time + $host_io->{KeepAliveTimer}*60;	# No keepalive while we are still RXing data
		#
		# Dot activity count
		#
		if ($mode->{dev_out} eq 'bf' && $$outRef =~ /^\.+$/) {
			++$host_io->{DotActivityCnt};
			debugMsg(2,"Dot Activity Count increased to ", \$host_io->{DotActivityCnt}, "\n");
		}
		else {
			$host_io->{DotActivityCnt} = 0;
		}
		#
		# Append output to cache, if any
		#
		if (length $host_io->{OutCache}) {
			($$outRef, $host_io->{OutCache}) = ($host_io->{OutCache} . $$outRef, '');
			debugMsg(2,"CachedAppended:\n>", $outRef, "<\n");
			changeMode($mode, {dev_cch => 'ds'}, '#HDO9');
		}
		($host_io->{CacheTimeout}, $host_io->{CacheTimeoutDF}) = (Time::HiRes::time + $OutputCacheTimeout, 1); # Reset cache timer (moved it out of if above  - bug14)
		debugMsg(4,"=Set CacheTimeout expiry time = ", \$host_io->{CacheTimeout}, "\n");
		#
		# Process Delete patterns here
		#
		unless ($mode->{dev_del} eq 'ds') {{ # No patterns to delete; do nothing
			if ($mode->{dev_del} eq 'fl' || $mode->{dev_del} eq 'ft') { # Remove 1st line of output (e.g. echoed output from switch)
				if ($$outRef =~ s/^.*\n//) {
					if ($mode->{dev_del} eq 'fl') {
						if ($term_io->{EchoOff} == 1 && $term_io->{Sourcing}) {
							$host_io->{CommandCache} .= "\n";
							debugMsg(4,"=adding to CommandCache:\n>",\$host_io->{CommandCache}, "<\n");
						}
						else {
							printOut($script_io, "\n");
							$script_io->{CmdLogFlag} = 1 if defined $script_io->{CmdLogFlag}; # Can start logging now
						}
					}
					debugMsg(2,"AfterFirstLineErase:\n>", $outRef, "<\n");
					changeMode($mode, {dev_del => 'fb'}, '#HDO10');
					redo;	# Try and process 'fb' below straight away
				}
				else { # Place on cache
					($host_io->{OutCache}, $$outRef) = ($$outRef, ''); # If not, place on cache and come out
					debugMsg(2,"NoFirstLine-ontoCache:\n>", \$host_io->{OutCache}, "<\n");
					return;
				}
			}
			elsif ($mode->{dev_del} eq 'fb') { # Remove 1st blank lines of output immediately following echoed command
				if ($$outRef =~ s/^[\x0d\n]*(.)/$1/) {
					debugMsg(2,"AfterFirstBlankLinesRemoved:\n>", $outRef, "<\n");
					changeMode($mode, {dev_del => 'ds'}, '#HDO11');
				}
				else { # Place on cache
					($host_io->{OutCache}, $$outRef) = ($$outRef, ''); # If not, place on cache and come out
					debugMsg(2,"NoFirstBlankLinePass-ontoCache:\n>", \$host_io->{OutCache}, "<\n");
					return;
				}
			}
			elsif ($mode->{dev_del} eq 'te') { # Remove 1st line of output followed by some sequence of chars
				if (
					$$outRef =~ s/^(?:(.*?)[\x0d\n]|\e\[m\s?\e\[\d+;D)\e\[K//s || # \e\[K - ExtremeXOS Tab expansion
					$$outRef =~ s/^(.*?)\e\[\d+D +\e\[\d+D//s ||	  # .[8D        .[8D - ISW exit 'te' if valid tab expansion
					$$outRef =~ s/^(.+)[\x0d\n]$prompt->{Match}//s	  # Everything before + prompt - ISW exit 'te' if no valid tab expansion
				) {
					print "\cG" if defined $1 && ($1 =~ /\cG/ || $1 =~ / +\^\x0d?\n%/);# Pass on bell character if we found one or if error seen
					debugMsg(2,"AfterFirstLineEscErase:\n>", $outRef, "<\n");
					changeMode($mode, {dev_del => 'ds'}, '#HDO12');
				}
				else {
					# Clensing patterns, required for below matches; moved up from SafetyEscape-from-FirstLineEscErase
					if ( defined $termbuf->{TabMatchSent} ) {
						if ( $$outRef =~ s/^$termbuf->{TabMatchSent}\x0d?\n// || $$outRef =~ s/^\cG?\s+^\x0d?\n%.+\x0d?\n?//) {
							# On XOS we sometimes get error message on tab expansion
							# if the entered cmd does not exist at all; this text will have multiple lines, and if there is no prompt yet
							# it will come out as safety escape below; so we test for it here and wipe it
							($host_io->{OutCache}, $$outRef) = ($$outRef, ''); # Place on cache and come out
							debugMsg(2,"Removing error message with no prompt, to prevent safety escape:\n>", $outRef, "<\n");
							return;
						}
						elsif ( $$outRef =~ s/^$termbuf->{TabMatchSent}(\cG)\x0d?\n//) {
							print "\cG" if $1;
							# On ISW we get syntax with show lo; we need this extra cycle to get the prompt, and come out from top 'te' if
							($host_io->{OutCache}, $$outRef) = ($$outRef, ''); # Place on cache and come out
							debugMsg(2,"Waiting for ISW prompt:\n>", $outRef, "<\n");
							return;
						}
					}
					if ($$outRef =~ /\n/) { # Safety escape pattern
						$$outRef =~ s/^(?:\x0d|\e|\[m|\[\d\d;D|\[K)//g if $host_io->{Type} eq 'ExtremeXOS'; # Try and remove these escape sequences anyway
						$$outRef =~ s/^\e\[\d+D\s+\e\[\d+D//g if $host_io->{Type} eq 'ISW'; # Try and remove these escape sequences anyway
						debugMsg(2,"SafetyEscape-from-FirstLineEscErase:\n>", $outRef, "<\n");
						changeMode($mode, {dev_del => 'ds'}, '#HDO13');
					}
					else { # Place on cache
						($host_io->{OutCache}, $$outRef) = ($$outRef, ''); # If not, place on cache and come out
						debugMsg(2,"NoFirstLineEsc-ontoCache:\n>", \$host_io->{OutCache}, "<\n");
						return;
					}
				}
			}
			elsif ($mode->{dev_del} eq 'bs' || $mode->{dev_del} eq 'bt' || $mode->{dev_del} eq 'bx') { # Remove space+backspace sequences; used by device to delete a line of output
				quit(1, "ERROR: backspace count not set in 'bs' dev_del mode", $db) unless $host_io->{BackspaceCount};
				my $keepOutput;
				if ($host_io->{Type} eq 'Ipanema' && $mode->{dev_del} eq 'bt') {
					if ($$outRef =~ s/^\cG?\x0d\e\[\d+C([^\x00\x0d\n\cH\e]+)/$1/) {
						# Ipanema: eth<tab>  get back bell + "-diag"; same for other ? commands
						print "\cG" unless length $1;
						debugMsg(2,"PreAdjustingTabExpansion-ipanema:>", $outRef, "<\n");
					}
					if ($$outRef =~ s/^[^\x00\x0d\n\cH\e]*([^\x00\x0d\n\cH\e])\K\x0d\g{1}//) {
						debugMsg(2,"PreAdjustingTabExpansion2-ipanema:>", $outRef, "<\n");
					}
				}
				print "\cG" if $$outRef =~ s/^\cG//; # Pass it on; PPCLI show sn<tab>
				if ($$outRef =~ s/^([^\x00\x0d\n\cH\e]+)([\cH\x0d\e]*)/$2/) {
					# The difference between bs & bt is that with bs BackspaceCount includes count of chars sent and not yet received; with bt it only includes what we received
					if ($mode->{dev_del} eq 'bs') {
						$host_io->{PacedSentPendng} -= length $1;	# Increase length of expected backspaces by as many chars
						debugMsg(2,"PacedSentPendng removed non backspace chars:>", \$1, "<\n");
						if ($host_io->{PacedSentPendng} < 0) {
							debugMsg(2,"PacedSentPendng gone negative : ", \$host_io->{PacedSentPendng}, " ; resetting to zero<\n");
							$host_io->{PacedSentPendng} = 0;
						}
						debugMsg(2,"PacedSentPendng now = ", \$host_io->{PacedSentPendng}, "\n");
					}
					elsif ($mode->{dev_del} eq 'bt' || $mode->{dev_del} eq 'bx') {
						$host_io->{BackspaceCount} += length $1;	# Increase length of expected backspaces by as many chars
						if ($mode->{dev_del} eq 'bt') { # Only for post tab processing
							print $1;					# Append to screen
							$termbuf->{Linebuf1} .= $1;			# Append to linebuffer
							($termbuf->{Bufback1} = $termbuf->{Linebuf1}) =~ s/./\cH/g;	# We update local term buffers
							debugMsg(2,"PostAdjustingTabExpansion-extra:>", \$termbuf->{Linebuf1}, "<\n");
						}
					}
				}
				elsif ($mode->{dev_del} eq 'bt' && $$outRef =~ s/^(\cH+)([^\x00\x0d\n\cH\e\s][^\x00\x0d\n\cH\e]*\s?)(\cH)/$3/) { # must match a non-space as 1st char after \cH
					# SLX test case: int<tab>; interface ether<tab>; interface Ethernet<?>
					# (bug27)   SLX: show log audi<tab>
					# VSP test case: (config) ip pre<tab>  then once expanded, two backspaces
					print "$1$2";
					$host_io->{BackspaceCount} += length($2) - length($1);	# Increase length of expected backspaces by as many chars
					$termbuf->{Linebuf1} = substr($termbuf->{Linebuf1}, 0, - length $1) . $2;
					($termbuf->{Bufback1} = $termbuf->{Linebuf1}) =~ s/./\cH/g;	# We update local term buffers
					debugMsg(2,"PostAdjustingTabExpansion-innerExpansion:>", \$termbuf->{Linebuf1}, "<\n");
				}
				unless (defined $term_io->{BackSpaceMode}) { # Detection patterns to enter BackSpaceMode
					if (	(
						$host_io->{Type} eq 'SLX' &&
							$$outRef =~ /^\nPossible completions:/ # show ip<tab>
						) || (
						$host_io->{Type} eq 'Wing' &&
							$$outRef =~ s/^\x0d?(\n(?:\w+\s+)+)\x0d?\n\x0d?\e\[K\e\[\d+C\x0d?/$1\n/ # co<tab>
						)
					) {
						$term_io->{BackSpaceMode} = 1; # True = keep output (syntax output)
					}
					elsif (	(
						$host_io->{Type} eq 'SLX' &&
							$$outRef =~ /^\n +\^\n%/ # show ip<tab> ; show vz
						) || (
						$host_io->{Type} eq 'Wing' &&
							$$outRef =~ s/^[\x0d\n]+\e\[K\e\[\d+C// # show vz
						) || (
						$host_io->{Type} eq 'WLAN9100' &&
							$$outRef =~ /^\x0d?(\n +\^)/
						)
					) {
						$term_io->{BackSpaceMode} = 0; # Defined but False = throw away output (error output)
						print "\cG"; # Emulate VSP/ERS which sound a bell for non existent command on tab espansion
					}
					debugMsg(2,"BackSpaceMode set = $term_io->{BackSpaceMode} :\n>", $outRef, "<\n") if defined $term_io->{BackSpaceMode};
				}
				if (defined $term_io->{BackSpaceMode}) { # Implement the add-on mode
					unless ($$outRef =~ s/^([^\x00\cH\e]+)(?=[\cH\e])//s) {
						($host_io->{OutCache}, $$outRef) = ($$outRef, ''); # If not, place on cache and come out
						debugMsg(2,"BackSpaceMode-noBackSpaces-ontoCache:\n>", \$host_io->{OutCache}, "<\n");
						return;
					}
					if ($term_io->{BackSpaceMode}) { # If true we keep the output
						$keepOutput = $1;
						debugMsg(2,"BackSpaceMode-keepOutput:\n>", \$keepOutput, "<\n");
					}
					debugMsg(2,"BackSpaceMode-OutputToCheckForBackspaces:\n>", $outRef, "<\n");
				}
				if ($host_io->{Type} eq 'Ipanema' && $mode->{dev_del} eq 'bt' && $$outRef =~ s/^\e\[A[^\x00\x0d\n\cH\e]+\e\[K\n//) {
					debugMsg(2,"AvoidSafetyEscape-ipanema:>", $outRef, "<\n");
				}
				debugMsg(2,"BackspaceExpectedCount = $host_io->{BackspaceCount}\n");
				my $bcntminus1 = $host_io->{BackspaceCount} - 1;
				if (	(
						($host_io->{Type} eq 'PassportERS' || $host_io->{Type} eq 'BaystackERS' || $host_io->{Type} eq 'SecureRouter') &&
						(	# Not sure which patterns below are which.. I no longer have any SecureRouters and rather not break it..
							$$outRef =~ s/^(?:\cH \cH){$host_io->{BackspaceCount}}// ||
							$$outRef =~ s/^\x0d[ \x00]{$host_io->{BackspaceCount}}\x0d// ||
							$$outRef =~ s/^\cH{$host_io->{BackspaceCount}} {$host_io->{BackspaceCount}} \cH{$host_io->{BackspaceCount}}\cH//
						)
					) || (
						$host_io->{Type} eq 'WLAN2300' &&
							$$outRef =~ s/^\x0d +\x0d$prompt->{Match}//	# WLAN2300
					) || (
						$host_io->{Type} eq 'WLAN9100' &&
						(
							$$outRef =~ s/^\x00?\cH{$host_io->{BackspaceCount}} {$bcntminus1,$host_io->{BackspaceCount}}\cH{$bcntminus1,$host_io->{BackspaceCount}}// || # WLAN9100 : hist<tab>
							$$outRef =~ s/^\x00?\x0d$prompt->{Match} {$bcntminus1}\cH{$bcntminus1}// ||			# WLAN9100 : show temp<tab>
							$$outRef =~ s/^\x00?\x0d$prompt->{Match} {$bcntminus1}\x0d$prompt->{Match}//			# WLAN9100 : show syst<tab>
						)
					) || (
						$host_io->{Type} eq 'ExtremeXOS' &&
						(
							$$outRef =~ s/^\cH{$host_io->{BackspaceCount}}\e\[J// ||	# Extreme XOS
							($host_io->{BackspaceCount} > 90 && $$outRef =~ s/^(?:\e\[C)+\e\[A(?:\e\[J)?//)	# Extreme XOS lines > 100 chars
						)
					) || (
						$host_io->{Type} eq 'ISW' &&
						(
							$$outRef =~ s/^(?:\e\[D \e\[D){$host_io->{BackspaceCount}}// ||	# ISW - more prompt delete
							$$outRef =~ s/^\e\[\d+D {$host_io->{BackspaceCount}}\e\[\d+D//	# ISW - tab expansion delete
						)
					) || (
						$host_io->{Type} eq 'ISWmarvell' &&
						(
							$$outRef =~ s/^\x0d\e\[K\x0d//	# ISWmarvell - more prompt delete
						)
					) || (
						$host_io->{Type} eq 'SLX' &&
						(
							$$outRef =~ s/^\cH{$host_io->{BackspaceCount}} {$host_io->{BackspaceCount}}\cH{$host_io->{BackspaceCount}}// ||
							$$outRef =~ s/^(?:\e\[\dD|\x08)*\x0d {$host_io->{BackspaceCount}}(?:\e\[\dD|\x08)*\x0d?// ||
							$$outRef =~ s/^(\e\[\d+D|\cH)+ {$host_io->{BackspaceCount}}(\e\[\d+D|\cH)+// ||
							$$outRef =~ s/^(?:\e\[[58]D|\x0d)?\e\[K// # This is get rid of (END) at end of paged output
						)
					) || (
						$host_io->{Type} eq 'Series200' &&
							$$outRef =~ s/^(?:\cH \cH){$host_io->{BackspaceCount}}//
					) || (
						$host_io->{Type} eq 'Wing' &&
						(
							$$outRef =~ s/^\e\[$host_io->{BackspaceCount}D(?:\e\[K)?// ||
							$$outRef =~ s/^\cH{$host_io->{BackspaceCount}}//
						)
					) || (
						$host_io->{Type} eq 'HiveOS' &&
						(
							$$outRef =~ s/^\cH{$host_io->{BackspaceCount}} {$host_io->{BackspaceCount}}\cH{$host_io->{BackspaceCount}}// ||	# sh<tab>
							$$outRef =~ s/^\x0d$prompt->{Match} {$host_io->{BackspaceCount}}\x0d$prompt->{Match}//				# show app<tab>
						)
					) || (
						$host_io->{Type} eq 'Ipanema' &&
						(
							$$outRef =~ s/^\x0d\e\[K\e\[A$prompt->{Match}// ||
							$$outRef =~ s/^\e\[$host_io->{BackspaceCount}D(?:\e\[K)?// ||
							$$outRef =~ s/^\x0d\e\[\d+C\e\[K\x00{3,}// ||
							$$outRef =~ s/^\cH{$host_io->{BackspaceCount}}\e\[K// ||
							$$outRef =~ s/^\x0d$prompt->{Match}\e\[K//
						)
					) || (
						$CleanPromptCtrl{$host_io->{Type}} eq $CTRL_C &&
						$$outRef =~ s/^\x0d?\n$prompt->{Match}$//
					)
				    ) {
					$host_io->{BackspaceCount} = 0;
					$$outRef .= $keepOutput if $keepOutput;
					debugMsg(2,"AfterBackSpaceErase:\n>", $outRef, "<\n");
					if ($term_io->{BackSpaceMode}) {
						changeMode($mode, {dev_del => 'ds', dev_fct => 'st'}, '#HDO14');	# Revert to local term mode and go to 'st' mode
					}
					elsif ($mode->{dev_del} eq 'bt') {
						changeMode($mode, {term_in => 'tm', dev_del => 'ds'}, '#HDO15');
					}
					else {
						changeMode($mode, {dev_del => 'ds'}, '#HDO16');
					}
					$term_io->{BackSpaceMode} = undef;
				}
				elsif ($$outRef =~ /\n/) { # Safety escape patterns (if we miss the new prompt)
					$host_io->{BackspaceCount} = 0;
					$term_io->{BackSpaceMode} = undef;
					$$outRef .= $keepOutput if $keepOutput;
					debugMsg(2,"SafetyEscape-from-RemoveBackspaces:\n>", $outRef, "<\n");
					changeMode($mode, {term_in => 'tm'}, '#HDO17') if $mode->{dev_del} eq 'bt';
					changeMode($mode, {dev_del => 'ds'}, '#HDO18');
				}
				else { # Place on cache
					$$outRef .= $keepOutput if $keepOutput;
					($host_io->{OutCache}, $$outRef) = ($$outRef, ''); # If not, place on cache and come out
					debugMsg(2,"NotSufficientBackSpaces-ontoCache:\n>", \$host_io->{OutCache}, "<\n");
					return;
				}
			}
			elsif ($mode->{dev_del} eq 'kp') { # Remove keepalive sequence; echoed by device after we send a keepalive
				if ($$outRef =~ s/^(?:\x0d*\n|\n\x0d*|\n\x0d *\x0d|\x0d\n\x0d)\@?$prompt->{Regex}//) {
					debugMsg(2,"AfterKeepAliveErase:\n>", $outRef, "<\n");
					changeMode($mode, {term_in => $mode->{term_in_cache}, dev_del => 'ds'}, '#HDO19');
				}
				elsif ($$outRef !~ /^\x0d*\n/ || $$outRef =~ /[^\x0d\n].+\n/) { # Safety escape patterns (if we miss the new prompt)
					debugMsg(2,"SafetyEscape-from-KeepAliveErase:\n>", $outRef, "<\n");
					changeMode($mode, {term_in => $mode->{term_in_cache}, dev_del => 'ds'}, '#HDO20');
				}
				else { # Place on cache
					($host_io->{OutCache}, $$outRef) = ($$outRef, ''); # If not, place on cache and come out
					debugMsg(2,"NoKeepAlive-ontoCache:\n>", \$host_io->{OutCache}, "<\n");
					return;
				}
			}
			elsif ($mode->{dev_del} eq 'yd') { # Remove echo-ed 'y' after yprompt
				if ($$outRef =~ s/(?:^|\n)(?:$term_io->{YnPrompt}|Yes|No)\x0d?(\n|$)/$1/) {
					debugMsg(2,"After-Y-ResponseErase:\n>", $outRef, "<\n");
				}
				changeMode($mode, {dev_del => 'ds'}, '#HDO21');
			}
			else {
				quit(1, "ERROR: unexpected dev_del mode: ".$mode->{dev_del}, $db);
			}
		}}
		return unless length $$outRef;	# Skip rest unless there is something left in $$outRef
		#
		# If we get output here and in local term mode, this is not valid...
		#
		if ($mode->{term_in} eq 'tm') { # We don't expect device output while in Local Term mode
			if ($$outRef !~ /\n/ && length $host_io->{PacedSentChars}) { # if no carriage returns and some outstanding chars
				my $recvString = quotemeta($$outRef);
				my $wipeDeviceBuffer;
				if ($host_io->{PacedSentChars} =~ s/^$recvString//) {
					($recvString = $$outRef) =~ s/^\s+// unless length $termbuf->{Linebuf1}; # Strip leading spaces if buffer empty
					print $recvString;
					$termbuf->{Linebuf1} .= $recvString; # Add to buffer
					($termbuf->{Bufback1} = $termbuf->{Linebuf1}) =~ s/./\cH/g;
					debugMsg(2,"Paced Sent Chars - added to input buffer: >", \$recvString, "<\n");
					$wipeDeviceBuffer = 1;
				}
				elsif ($host_io->{PacedSentChars} =~ /$Escape/) { # Cursor keys mess it up as they bring device history
					$host_io->{PacedSentChars} = '';
					debugMsg(2,"Paced Sent Chars - contained cursor keys\n");
					$wipeDeviceBuffer = 1;
				}
				if ($wipeDeviceBuffer) {
					$host_io->{BackspaceCount} = length $$outRef;	# Number of backspaces we expect, after CTRL-U
					debugMsg(2,"BackspaceCount:>", \$host_io->{BackspaceCount}, "<\n");
					$host_io->{SendBuffer} .= $CleanPromptCtrl{$host_io->{Type}}; # And remove it from device's buffer
					changeMode($mode, {dev_del => 'bs'}, '#HDO22') if $CleanPromptCtrl{$host_io->{Type}} eq $CTRL_U;
					$$outRef = '';
					return;
				}
			}
			if ($mode->{dev_inp} eq 'rd' && $$outRef !~ /$prompt->{Match}$/ && $$outRef !~ /$UnbufferPatterns{$host_io->{Type}}/o && $$outRef !~ /^$ReleaseConnectionPatterns/mo) {
				# In read mode (i.e. not during initial login..) and not a prompt, and not an UnbufferPattern
				# Ok, we are probably dealing with a console connection; we are going to resist this unsolicited output
				($host_io->{OutCache}, $$outRef) = ($$outRef, ''); # Place on cache and come out
				debugMsg(2,"Unsolicited Output in Term mode-ontoCache:\n>", \$host_io->{OutCache}, "<\n");
				return;
			}
			else { # We are doing the initial connect/login sequence; keep old behaviour here
				changeMode($mode, {term_in => 'sh'}, '#HDO23');	# Revert to transparent mode
			}
		}
		#
		# Do output clensing here
		#
		if ($readLogin) { # Output resulting from login sequence
			#
			# Handle any output resulting from the initial login
			#
			debugMsg(2,"InitLoginToProcess:\n>", $outRef, "<\n");
			my ($banner, $customBanner) = ('', '');
			#if ($$outRef =~ s/Enter Ctrl-Y to begin\.\s*//) { # Connection to a BaystackERS
			if ($$outRef =~ /^(.*)Enter Ctrl-Y to begin\.\s*(.*)$/s) { # Connection to a BaystackERS
				($customBanner, $banner) = ($1, $2);
				$$outRef =~ s/^[^\*]*//;	# Remove garbage before 1st '*' of banner
				debugMsg(2,"BaystackBanner-outRef-modified:\n>", $outRef, "<\n");
				$customBanner =~ s/^.*\e\[1;1H//s;		# Remove everything before 1st line of custom banner
				$customBanner =~ s/\n\e\[\d+;\dH(?:\e\[\dK)?/\n/g;	# Remove ESC sequences between banner lines, if newlines are there
				$customBanner =~ s/\e\[\d+;\dH(?:\e\[\dK)?/\n/g;	# Replace ESC sequences between banner lines with new lines, if newlines are not there
				$customBanner =~ s/^\s+\*/*/mg;				# Re-align banner left-most (some beta load banners are spaced)
				$customBanner =~ s/[\x0d\n]+$/\n/s;			# End with single carriage return
				debugMsg(2,"BaystackCustomBanner:\n>", \$customBanner, "<\n");
				$customBanner = '' if $customBanner =~ /^[\s#\n]+$/s;
				$customBanner = "\n" . $customBanner;
				debugMsg(2,"BaystackCustomBanner-ifNonDefault:\n>", \$customBanner, "<\n");
				$banner =~ s/^([^\*]*)//;	# Remove garbage before 1st '*' of banner
				my $garbage = $1 || '';
				my $buildInfo = "\n";
				$buildInfo .= "$1\n" if $garbage =~ /(Build Info: [^\e\n\r]+)/; # Build Info line is between CTRL-Y and banner
				debugMsg(2,"BuildInfo:\n>", \$buildInfo, "<\n");
				$banner =~ s/\[ ?\*+ ?\]//g;	# If telnet requires username/password remove this [ *************** ] from banner, or it will mess regex below
				$banner =~ s/\e\[\d+;\d+H\*([^\*])/$1/g; # Remove these from banner: Password: [14;42H*[24;1H[14;43H* ; or it will mess regex below
				$banner =~ s/\*([^\*]*)$/*\n/s; # Remove garbage after last '*' of banner
				$$outRef = $1 || '';
				my $lastLogin = '';
				$lastLogin .= $1 if $$outRef =~ s/(Last login: [^\e\n\r]+)//;
				$lastLogin .= " $1" if $$outRef =~ s/(from IP address [\d+\.:]+)//;
				$lastLogin .= "\n" if length $lastLogin;
				$lastLogin .= "$1\n" if $$outRef =~ s/(Failed retries since last login: [^\e\n\r]+)//;
				$lastLogin .= "\n$1\n" if $$outRef =~ s/(Download in progress. Please wait ...)//;
				debugMsg(2,"LastLogin:\n>", \$lastLogin, "<\n");
				debugMsg(2,"BaystackBanner1:\n>", \$banner, "<\n");
				$banner =~ s/\n\e\[\d+;\dH(?:\e\[\dK)?/\n/g;	# Remove ESC sequences between banner lines, if newlines are there
				$banner =~ s/\e\[\d+;\dH(?:\e\[\dK)?/\n/g;	# Replace ESC sequences between banner lines with new lines, if newlines are not there
				$banner =~ s/^\s+\*/*/mg;			# Re-align banner left-most (some beta load banners are spaced)
				debugMsg(2,"BaystackBanner2:\n>", \$banner, "<\n");
				$banner =~ s/\e\[0m//g;	# Remove some spurious ESC sequences
				debugMsg(2,"BaystackBanner3:\n>", \$banner, "<\n");
				$banner =~ /\n(\*{1,5})\s/g; 	# Banner Side (immediately after, not more than 5 *s)
				my $banSideLength = defined $1 ? length $1 : 3;
				debugMsg(2,"BannerSideLength = ", \$banSideLength, "\n");
				$banner =~ s/(\*+(?:[^\S\n].*?)?)\e\[\d+;(\d+)H/my $len = $2-$banSideLength; sprintf("%-${len}s", $1)/ge;
				$banner = $customBanner . $buildInfo . $banner . $lastLogin;	# Put an initial carriage return and re-add buildInfo
				debugMsg(2,"BaystackBanner4:\n>", \$banner, "<\n");
				$banner =~ s/\e\[\??\d+(?:;\d+)?\w//g;	# Safety, strip any remaining escape sequences, just in case
				debugMsg(2,"BaystackBanner5:\n>", \$banner, "<\n");
			}
			if (!$loginSuccess && $$outRef =~ /(Enter Username: )/) { # Handle login prompt
				$$outRef = $banner ? $banner . $1 : "\n" . $1;
			}
			elsif (!$loginSuccess && $$outRef =~ /(Enter Password: )[^\*]/) { # Handle login prompt
				$$outRef = $banner ? $banner . $1 : "\n" . $1;
			}
			else { # No login / password
				if (length $banner) { # Stackable banner
					while ($$outRef =~ /^.*?[\*\e]/) { # While we see '*' or ESC chars in 1st line
						$$outRef =~ s/^.+\n//;		# Nibble line away
					}
				}
				else { # Other devices
					$$outRef =~ s/^.+// unless $$outRef =~ /^.*(?:login|password)/;	# Remove everything before 1st carriage return
				}
				$$outRef = "\n" . $$outRef unless $$outRef =~ /^\n/;	# Add newline if not one to start with
				debugMsg(2,"InitLogin-cleanup1:\n>", $outRef, "<\n");
				# Remove new stackable failed retries banner
				$$outRef =~ s/^.*(Failed retries since last login:.*)$/$1/m;
				$$outRef =~ s/^.*Press ENTER to continue.*\n//m;
				$$outRef =~ s/^(?:\e\[\d+(?:;\d+)?\w)+.*//m; # mathes this: [2J[?25h[2J[23;1H
				# Re-add the banner
				$$outRef = $banner . $$outRef;
				$$outRef =~ s/\e\[\??\d+(?:;\d+)?\w//g;	# Strip any remaining escape sequences
				debugMsg(2,"InitLogin-cleanup2:\n>", $outRef, "<\n");
			}
			if ($loginSuccess) { # Remove output produced by wake_console sequence
				$$outRef =~ s/.*(?:\cG|\^Z).*[\n\x0d]+//mg;
			}
			if ($$outRef =~ /\n/) { # Apply these clensing steps only if the buffer contains at least 1 complete line
				# We do this otherwise when logging to file, the output is messed
				$$outRef =~ s/^\x0d+//mg;		# Remove spurious CarriageReturns at beginning of line
				$$outRef =~ s/\x0d+$//mg;		# Remove spurious CarriageReturns at end of each line
				$$outRef =~ s/^\x10?\x00//mg;		# WLAN9100, happens only with Telnet, not SSH
			}
			debugMsg(2,"InitLoginFormatted:\n>", $outRef, "<\n");
		}
		elsif ($term_io->{Mode} eq 'interact') { # Output resulting from normal read sequence AND we are in interactive mode
			#
			# Output Clensing in Interact mode
			#
			if ($$outRef =~ /\n/) { # Apply these clensing steps only if the buffer contains at least 1 complete line
				if ($host_io->{Type} eq 'BaystackERS') {
					# Remove trailing spaces from end of lines, a Baystack habit; Except on max length lines we might unwrap 
					$$outRef =~ s/.\{0,$TermWidth-1\}[ \t]+\n/\n/g;
				}
				elsif ($host_io->{Type} eq 'ExtremeXOS') {
					$$outRef =~ s/\e\[K\n/\n/g; # On XOS out put of "show ports utilization bandwidth" has these escape sequences
					$$outRef =~ s/[ \t]+\n/\n/g;
				}
				elsif ($host_io->{Type} eq 'SLX') {
					$$outRef =~ s/ ?\e\[\d+;\d+H//g; # SLX serial port has serious issues and spits these out all the time...
					$$outRef =~ s/[ \t]+\n/\n/g;
				}
				elsif ($host_io->{Type} eq 'SecureRouter') {
					$$outRef =~ s/^\x0d *\x0d//mg;		# Remove SecureRouter sequence prior ro prompt..
					$$outRef =~ s/[ \t]+\n/\n/g;
				}
				else {
					$$outRef =~ s/[ \t]+\n/\n/g;
				}
				# Do on all
				$$outRef =~ s/^\x0d+//mg;		# Remove spurious CarriageReturns at beginning of line
				$$outRef =~ s/\x0d+$//mg;		# Remove spurious CarriageReturns at end of each line
				debugMsg(2,"AfterOutputClensing:\n>", $outRef, "<\n");
			}
			if ($host_io->{Type} eq 'WLAN9100') { # Need this to happen even if single line (if \n was removed by FirstLineErase)
				$$outRef =~ s/\x10?\x00//g;		# Happens only with Telnet, not SSH
									# in some case even not at beginning of line..
			}
			elsif ($host_io->{Type} eq 'SLX') {
				$$outRef =~ s/\e\[m\x0f(?:\e\[7m)?//g; # SLX9850 is even worse on serial port
			}

			return unless length $$outRef;	# Skip rest unless there is something left in $$outRef
			#
			# Handling output in case of special functions like Tab key press or Syntax output
			#
			{ # For redo
			if ($mode->{dev_fct} eq 'ds') {} # No special functions to process
			elsif ($mode->{dev_fct} eq 'tb') { # Process tab expansion from host device
				print "\cG" if $$outRef =~ s/\cG//g;	# Pass on bell character and remove it
				if ($host_io->{Type} eq 'WLAN9100' && $$outRef =~ s/\x00//mg) { # Output gets peppered with \x00 which we need to remove
					debugMsg(2,"WLAN9100-tab-reformatting:\n>", $outRef, "<\n"); # Happens only with Telnet, not SSH
				}
				elsif ($host_io->{Type} eq 'Wing' && $$outRef =~ s/^\e\[K//) { # Output might get preceded with \e[K if tab expansion was used in previous command
					debugMsg(2,"Wing-tab-reformatting:\n>", $outRef, "<\n");
				}
				elsif ($host_io->{Type} eq 'Ipanema' && $$outRef =~ s/^[^\x00\x0d\n\cH\e]*([^\x00\x0d\n\cH\e])\K\x0d\g{1}//) {
					debugMsg(2,"Ipanema-tab-reformatting:\n>", $outRef, "<\n");
				}
				my $tabSynMode = $TabSynMode{$host_io->{Type}}[$term_io->{AcliType}]&3;
				debugMsg(2,"TabSynMode = ", \$tabSynMode, "\n");
				if ($tabSynMode == 3) { # Ensure we have a prompt in the output + tail match (ERS & VSP)
					unless ($$outRef =~ /^(?:\x0d(?:\e\[K)?)?$prompt->{Match}/m && $$outRef =~ /$termbuf->{TabMatchTail}/) {
						($host_io->{OutCache}, $$outRef) = ($$outRef, ''); # If not, place on cache and come out
						debugMsg(2,"IncompleteTabExpansion-ontoCache:\n>", \$host_io->{OutCache}, "<\n");
						return;
					}
				}
				elsif ($tabSynMode == 2) { # Tail match only (none)
					quit(1, "ERROR: unexpected TabSynMode & 3 == 2");
				}
				elsif ($tabSynMode == 1) { # Ensure we have a prompt in the output + match cmd sent (XOS)
					unless ($$outRef =~ /^(?:\x0d(?:\e\[K)?)?$prompt->{Match}/m && $$outRef =~ /$termbuf->{TabMatchSent}/i) {
						($host_io->{OutCache}, $$outRef) = ($$outRef, ''); # If not, place on cache and come out
						debugMsg(2,"IncompleteTab2Expansion-ontoCache:\n>", \$host_io->{OutCache}, "<\n");
						return;
					}
				}
				elsif ($tabSynMode == 0) { # Match cmd sent only (PPCLI, SR, ISW, S200, Wing, SLX, WLAN2300, WLAN9100)
					unless ($$outRef =~ /^$termbuf->{TabMatchSent}/i) { # Ensure our echoed buffer is in there
						($host_io->{OutCache}, $$outRef) = ($$outRef, ''); # If not, place on cache and come out
						debugMsg(2,"IncompleteTab3Expansion-ontoCache:\n>", \$host_io->{OutCache}, "<\n");
						return;
					}
				}
				$$outRef =~ s/^(?:.*\n)*\x0d?$prompt->{Match}//;  # We remove the prompt from it and keep the expanded command
					# On VOSS: "res<tab> results in line "% Unmatched quote detected at '^' marked." before the new prompt; hence delete of preceding lines
				if ($$outRef =~ s/^($termbuf->{TabMatchSent}.*)?(?|[\?\cG]?(\n)\x0d?|\cG())/$2/i) { # WLAN2300/WLAN9100/ExtremeXOS when tab can apply to two or more possible commands (test with show po<tab>)
					# We have output here; we switch to 'sx' mode and redo
					$termbuf->{Linebuf1} = $1;			# Pre-load Linebuf1 with the command
					($termbuf->{Bufback1} = $termbuf->{Linebuf1}) =~ s/./\cH/g;	# Update as the command might not be same length
					changeMode($mode, {dev_fct => 'sx'}, '#HDO24');	# Revert to local term mode
					$termbuf->{SynMatchSent} = $termbuf->{TabMatchSent};
					debugMsg(2,"ConvertingTab-to-Syntax with output:\n>", $outRef, "<\n");
					redo; # Fall through to 'sx' processing below
				}
				if ($host_io->{Type} eq 'ExtremeXOS' && $$outRef =~ s/\e.*$//) {
					# On XOS, long commands, we see a \eE appended : configure lldp ports all advertise vendor-specific med policy application voice vlan Default E
					debugMsg(2,"outRef after removing esc-E appended:\n>", $outRef, "<\n");
				}
				$host_io->{BackspaceCount} = length $$outRef;	# Number of backspaces we expect, after CTRL-U
				debugMsg(2,"TabBackspaceCount:>", \$host_io->{BackspaceCount}, "<\n");
				if ($$outRef =~ s/^\$//) {			# Line is shifted to fit in 80 columns; need to regenerate
					debugMsg(2,"ObtainedShiftedExpansion-tab:>\$", $outRef, "<\n");
					$$outRef = substr($termbuf->{TabCmdSent}, 0, index($termbuf->{TabCmdSent}, substr($$outRef, 0, 10))).$$outRef;
				}
				debugMsg(2,"RetainedExpansion-tb:>", $outRef, "<\n");
				if (defined $termbuf->{TabBefoVar} && $$outRef =~ s/$termbuf->{TabMatchSent}/$termbuf->{TabBefoVar}/i) {
					debugMsg(2,"RetainedExpansion-tb-after restoring vars:>", $outRef, "<\n");
				}
				sedPatternReplace($host_io, $term_io->{SedOutputPats}, $outRef) if $termbuf->{SedInputApplied} && %{$term_io->{SedOutputPats}};
				$termbuf->{Linebuf1} = $$outRef . $termbuf->{TabOptions};	# We update local term buffers
				$termbuf->{Linebuf2} = $termbuf->{Bufback2} = '';		# This was holding local grep or flags; clear it
				print $termbuf->{Bufback1}, $termbuf->{Linebuf1}; 		# We overwrite what we had with expanded version
				($termbuf->{Bufback1} = $termbuf->{Linebuf1}) =~ s/./\cH/g;	# We update local term buffers
				$host_io->{SendBuffer} .= $CleanPromptCtrl{$host_io->{Type}};	# We have to also delete the partial command from host's buffer
				changeMode($mode, {dev_del => 'bt', dev_fct => 'ds'}, '#HDO25');	# Revert to local term mode
				return;
			}
			elsif ($mode->{dev_fct} eq 'sx') { # Process syntax output from host device
				if (!defined $prompt->{MoreRegex} || $$outRef !~ /$prompt->{MoreRegex}$/) { # Only if no more prompt present
					unless ($$outRef =~ /$prompt->{Match}/ && $$outRef =~ /$termbuf->{SynCmdMatch}$/) { # Ensure the end of command is there
						($host_io->{OutCache}, $$outRef) = ($$outRef, ''); # If not, place on cache and come out
						debugMsg(2,"IncompleteSyntax-ontoCache:\n>", \$host_io->{OutCache}, "<\n");
						return;
					}
					if ($$outRef =~ s/(?:\e\[K)?($prompt->{Match})(.+)$/$1/) {	# Store & remove everything after the prompt
						# Line below; $prompt->{Match} does not embed () in WLAN2300; so needs to look at $2 there
						my $cmdBack = defined $3 ? $3 : $2;
						if ($cmdBack =~ s/\e.*$//) {
							# On XOS, long commands, we see a \eE appended : configure lldp ports all advertise vendor-specific med policy application voice vlan Default E
							debugMsg(2,"cmdBack after removing esc-E appended:\n>", \$cmdBack, "<\n");
						}
						$host_io->{BackspaceCount} = length $cmdBack; # Number of backspaces we expect, after CTRL-U
						debugMsg(2,"SynBackspaceCount:>", \$host_io->{BackspaceCount}, "<\n");
						if ($cmdBack =~ s/^\$//) {			# Line is shifted to fit in 80 columns; need to regenerate
							debugMsg(2,"ObtainedShiftedExpansion-syntax:>\$", \$cmdBack, "<\n");
							$cmdBack = substr($termbuf->{TabCmdSent}, 0, index($termbuf->{TabCmdSent}, substr($cmdBack, 0, 10))).$cmdBack;
						}
						if (defined $termbuf->{TabBefoVar} && $cmdBack =~ s/$termbuf->{SynMatchSent}/$termbuf->{TabBefoVar}/i) {
							debugMsg(2,"RetainedExpansion-sx-after restoring vars:>", \$cmdBack, "<\n");
						}
						$termbuf->{Linebuf1} = $cmdBack; # If we get into 'sx' mode from 'tb' via ConvertingTab-to-Syntax we might have an expanded cmd
						($termbuf->{Bufback1} = $termbuf->{Linebuf1}) =~ s/./\cH/g;	# We update local term buffers
						$$outRef =~ s/\cG//g if $termbuf->{SynBellSilent};
						debugMsg(2,"AfterSyntaxProcessing:\n>", $outRef, "<\n");
						sedPatternReplace($host_io, $term_io->{SedOutputPats}, $outRef) if $termbuf->{SedInputApplied} && %{$term_io->{SedOutputPats}};
						($termbuf->{Linebuf1}, $termbuf->{Bufback1}) = ('', '') unless $term_io->{SyntaxAcliMode};
						$host_io->{SendBuffer} .= $CleanPromptCtrl{$host_io->{Type}};	# We have to also delete the partial command from host's buffer
						$$outRef =~ s/\x0d?\n$prompt->{Match}$// if $CleanPromptCtrl{$host_io->{Type}} eq $CTRL_C;	# We get a new prompt anyway
						changeMode($mode, {dev_del => 'bx'}, '#HDO26') if $CleanPromptCtrl{$host_io->{Type}} eq $CTRL_U;	# For processing backspaces
						changeMode($mode, {dev_fct => 'ds'}, '#HDO27');	# Revert to local term mode
					}
				}
			}
			elsif ($mode->{dev_fct} eq 'st') { # Process syntax output after coming out of backspace delete
				if ($$outRef =~ s/(?:\e\[K)?($prompt->{Match})(.+)$/$1/) {	# Store & remove everything after the prompt
					debugMsg(2,"AfterSyntaxProcessing-st:\n>", $outRef, "<\n");
					sedPatternReplace($host_io, $term_io->{SedOutputPats}, $outRef) if $termbuf->{SedInputApplied} && %{$term_io->{SedOutputPats}};
					changeMode($mode, {dev_del => 'ds'}, '#HDO28');	# Revert to local term mode
				}
			}
			elsif ($mode->{dev_fct} eq 'yp') { # Automatically answer 'y' at y/n? prompts
				if ($$outRef =~ /(.*$CmdConfirmPrompt{$host_io->{Type}})/o) {
					my $confirmPrompt = $1;
					debugMsg(2,"Detected-YNPrompt:\n>", \$confirmPrompt, "<\n");
					if ($term_io->{YnPromptForce} || $confirmPrompt !~ /(?:reset|reboot)/) {
						$$outRef =~ s/.*$CmdConfirmPrompt{$host_io->{Type}}//o;
						$$outRef =~ s/$CTRL_G//go; # Strip bell characters from output, if any
						$$outRef =~ s/^.*(?:Are you sure|Do you want .*?) ?\?\n//mo; # Strip any preceding lines asking if sure
							# Are you sure?		: ISWmarvell -> event clear
							# Do you want ... ?	: VOSS 5420 -> software add
						debugMsg(2,"AfterAuto-Y-atYNPrompt:\n>", $outRef, "<\n");
						$host_io->{SendBuffer} .= $term_io->{YnPrompt}; # Send 'y' (or 'n') 
						$host_io->{SendBuffer} .= $term_io->{Newline} if $CmdConfirmSendY{$host_io->{Type}}; # + Enter
						changeMode($mode, {dev_del => 'yd'}, '#HDO29');
					}
					elsif (!$term_io->{YnPromptForce} && $confirmPrompt =~ /(?:reset|reboot)/) {
						saveInputBuffer($term_io);
					}
				}
			}
			else {
				quit(1, "ERROR: unexpected dev_fct mode: ".$mode->{dev_fct}, $db);
			}} # 2nd } is for redo
			#
			# Output Modifying in Interact mode
			#
			if (defined $prompt->{MoreRegex}) {
#				$$outRef =~ s/\e\[\??\d+(?:;\d+)?\w//g;	# Strip any remaining escape sequences ;; If this is uncommented, it will result in banner messed up when booting on serial connection
				$$outRef =~ s/(?:$prompt->{MoreRegex})[\cH\x0d][\cH\x0d \x00]*[\cH\x0d]([^\cH\x0d])/$1/g; # Remove embedded More prompts
				$$outRef =~ s/(?:$prompt->{MoreRegex})\e\[m\s+\x0d?\e\[K//g; # Remove embedded More prompts (EXOS)
				if ($host_io->{Type} eq 'ISW') {
					if ($$outRef =~ s/(?:$prompt->{MoreRegex})(?:\e\[D \e\[D){51}//g) { # Remove double --more-- prompt which is not used
						debugMsg(2,"ISW after purging double more prompt and esc seq:\n>", $outRef, "<\n");
					}
					elsif ($$outRef =~ s/((?:$prompt->{MoreRegex})(?:\e\[D \e\[D)+[\e\[D ]*?)$//) { # If connecting to ISW via VOSS relay, the esc sequence may get truncated between reads
						$host_io->{OutCache} = $1;
						$doNotCacheLastLine = 1;
						debugMsg(2,"ISW adding to cache incomplete more prompt and esc seq:\n>", \$host_io->{OutCache}, "<\n");
					}
				}
			}
			# Raw escape sequence removing must be done after, or will interfere with some of above
			$$outRef =~ s/\e\[\?25[lh]//g if $^O eq "MSWin32"; # Remove hide/show cursor ESCape sequences
			$$outRef =~ s/\e\x5b[\x41-\x44]//g;	# Remove cursor chars
			$$outRef =~ s/$prompt->{Match}\n//g;	# Remove empty prompts from host (if Return hit multiple times by user)
			if ($term_io->{LtPrompt} && $$outRef =~ /([ -])+\^\x0d?\n(?:%|syntax error:)/) {
				# Since we add a prompt suffix, we need the syntax error pointer to be offset by as many chars
				my $padchar = $1;
				(my $pad = $term_io->{LtPromptSuffix}) =~ s/./$padchar/g;	# pad as many spaces as the PromptSuffix
				chop($pad) if $prompt->{Match} =~ / $/;			# devices which have 1 space between prompt and cursor
				$$outRef =~ s/([ -]+\^)/$pad$1/;
			}
			debugMsg(2,"AfterOutputModifying:\n>", $outRef, "<\n");
			return unless length $$outRef;	# Skip rest unless there is something left in $$outRef
			#
			# Now check for Connect/Disconnect patterns
			#
			if (exists $NewConnectionPatterns{$host_io->{LastCommand}} # We now only go here, if the last command was: ssh,telnet or peer
			    && ( $$outRef =~ s/^((?:.*\n|^)$NewConnectionPatterns.*?\n)(.*)$/$1/s || $$outRef =~ /^$NewConnectionPatterns{$host_io->{LastCommand}}$/m) ) {
				my $restBuffer = defined $2 ? $2 : $$outRef;
				$$outRef = '' unless defined $2;
				debugMsg(2,"NewConnectionPattern-restBuffer:\n>", \$restBuffer, "<\n");
				if ($$outRef =~ /Connected to 127\./) {
					$host_io->{LoopbackConnect} = 0;
					if ( ( (! defined $host_io->{Model} || $host_io->{Model} =~ /VSP-[89]/) && $$outRef =~ /Connected to 127.32.0.[12]/) # On VSP8600 standby CPU, attrib Model is undefined
					     || ( $host_io->{Model} =~ /ERS-8/ && $$outRef =~ /Connected to 127.0.[01].[56]/) ) {
					     	$host_io->{LoopbackConnect} = 1;
						$host_io->{CLI}->{BUFFER} = $restBuffer; # Cheat! Shove it all back onto Control::CLI's internal buffer to read again
						debugMsg(2,"ConnectionToStandbyCPUDetected\n");
						$host_io->{OutBuffer} = ''; # Empty this buffer
						changeMode($mode, {term_in => 'rk', dev_inp => 'sb', dev_del => 'ds', dev_fct => 'ds', dev_out => 'ub', buf_out => 'ds'}, '#HDO30');
					}
				}
				else {
					$host_io->{CLI}->{BUFFER} = $restBuffer; # Cheat! Shove it all back onto Control::CLI's internal buffer to read again
					debugMsg(2,"NewConnectionPatternDetected\n");
					push @{$term_io->{ConnectHistory}}, [	$term_io->{Mode}, $term_io->{AcliType},
										$prompt->{Match}, $prompt->{Regex},
										$prompt->{More}, $prompt->{MoreRegex},
										$host_io->{Type}, $host_io->{Model},
										$host_io->{Sysname}, $host_io->{BaseMAC},
										$host_io->{CpuSlot}, $host_io->{MasterCpu}, 
										$host_io->{DualCP}, $host_io->{SwitchMode},
										$host_io->{UnitNumber},
										$host_io->{Slots}, $host_io->{Ports},
										];
					push @{$term_io->{CredentHistory}}, [ $host_io->{Username}, $host_io->{Password} ];
					push @{$term_io->{VarsHistory}}, [ %$vars ];
					push @{$term_io->{SocketHistory}}, [ keys %{$socket_io->{ListenSockets}} ];
					$host_io->{Type} = '';
					$host_io->{OutBuffer} = ''; # Empty this buffer

					# Clear sockets if any were active
					untieSocket($socket_io);
					closeSockets($socket_io, 1);
					setPromptSuffix($db);

					disconnectPeerCP($db) if $peercp_io->{Connected}; # Tear down connection to peer CPU
					$host_io->{CLI}->{LOGINSTAGE} = ''; # Clear this Control::CLI flag before we call as we don't want it to think it is resuming any logins
					changeMode($mode, {term_in => 'rk', dev_inp => 'lg', dev_del => 'ds', dev_fct => 'ds', dev_out => 'ub', buf_out => 'ds'}, '#HDO31');
				}
			}
			elsif ($$outRef =~ /^$ReleaseConnectionPatterns/mo) {
				if ($host_io->{LoopbackConnect}) { # Leaving Peer CPU
					debugMsg(2,"ReleaseConnectionPatternDetected-FromPeerCPU\n");
					$host_io->{CLI}->{BUFFER} = "\n$$outRef"; # Cheat! Shove it all back onto Control::CLI's internal buffer to read again
					changeMode($mode, {term_in => 'rk', dev_inp => 'cp', dev_del => 'ds', dev_fct => 'ds', dev_out => 'ub', buf_out => 'ds'}, '#HDO32');
					$host_io->{LoopbackConnect} = undef;
					return;
				}
				elsif (!defined $host_io->{LoopbackConnect}) {
					debugMsg(2,"ReleaseConnectionPatternDetected\n");
					$host_io->{OutBuffer} = ''; # Empty this buffer
					if (@{$term_io->{ConnectHistory}}) {
						($term_io->{Mode}, $term_io->{AcliType},
						 $prompt->{Match}, $prompt->{Regex},
						 $prompt->{More}, $prompt->{MoreRegex},
						 $host_io->{Type}, $host_io->{Model},
						 $host_io->{Sysname}, $host_io->{BaseMAC},
						 $host_io->{CpuSlot}, $host_io->{MasterCpu}, 
						 $host_io->{DualCP}, $host_io->{SwitchMode},
						 $host_io->{UnitNumber},
						 $host_io->{Slots}, $host_io->{Ports},
						 ) = @{ pop @{$term_io->{ConnectHistory}} };
	 					($host_io->{Username}, $host_io->{Password}) = @{ pop @{$term_io->{CredentHistory}} };
						%$vars = @{ pop @{$term_io->{VarsHistory}} };

						# Clear sockets if any were active
						untieSocket($socket_io);
						closeSockets($socket_io, 1);
						openSockets($socket_io, @{ pop @{$term_io->{SocketHistory}} });

						$host_io->{CLI}->{BUFFER} = "\n$$outRef"; # Cheat! Shove it all back onto Control::CLI's internal buffer to read again
						$host_io->{CLI}->{LOGINSTAGE} = ''; # Clear this Control::CLI flag before we call as we don't want it to think it is resuming any logins
						changeMode($mode, {term_in => 'rk', dev_inp => 'cp', dev_del => 'ds', dev_fct => 'ds', dev_out => 'ub', buf_out => 'ds'}, '#HDO33');
						return;
					}
					elsif ($host_io->{RelayHost}) { # We are back on proxy host; close connection
						disconnect($db);
						connectionError($db, 'Host Disconnection from Relay');
						# We get here from connectionError if QuitOnDisconnect is not true
						return;
					}
				}
				$host_io->{LoopbackConnect} = undef;
			}
			if ($mode->{dev_out} eq 'bf' && !$doNotCacheLastLine) { # Only in buffered mode we do this
				# Here we check whether we have input to feed to command generated prompts
				if (defined $term_io->{FeedInputs} && @{$term_io->{FeedInputs}} && $$outRef =~ /$CmdInitiatedPrompt/o) {
					my $feedInput = pop(@{$term_io->{FeedInputs}});
					$host_io->{SendBuffer} .= $feedInput . $term_io->{Newline};
					debugMsg(2,"Detected Cmd Initated Prompt - Feeding: >", \$feedInput, "<\n");
					if (defined $term_io->{CacheInputCmd}) {
						push(@{$term_io->{CacheFeedInputs}}, $feedInput);
						debugMsg(2,"Caching FeedInput: >", \$feedInput, "<\n");
					}
					$doNotCacheLastLine = 1;
				}
				# Here we check for -more- prompts
				elsif (defined $prompt->{MoreRegex} && $$outRef =~ s/($prompt->{MoreRegex})$//) {
					my $moreStripped = $1;
					if ($moreStripped =~ /^$MorePromptDelay$/o && chomp $$outRef) { # Check for more patterns which are valid subset patterns
						$host_io->{OutCache} = "\n".$moreStripped;	# If yes, cache it, and we process it after next read
						debugMsg(2,"MorePromptSubsetPatternTrigger:>", \$host_io->{OutCache}, "<\n");
						changeMode($mode, {dev_cch => 'md'}, '#HDO34');
					}
					else {
						$moreStripped =~ s/^\n//; # If a newline was stripped, don't count it for expected backspaces
						$host_io->{BackspaceCount} = length $moreStripped; # Number of backspaces we expect after paging
						debugMsg(2,"BackspaceCount:>", \$host_io->{BackspaceCount}, "<\n");
						$host_io->{SendBuffer} .= $term_io->{BufMoreAction};	# We page automatically
						debugMsg(2,"AutomaticMore:>", \$term_io->{BufMoreAction}, "<\n");
						$termbuf->{TabMatchSent} = undef; # Only because this is otherwise used in 'te' code
						changeMode($mode, {dev_del => ($host_io->{Type} eq 'ExtremeXOS' ? 'te' : 'bs')}, '#HDO35'); # Delete backspace sequence following more prompt
					}
					$doNotCacheLastLine = 1;
				}
				# Here we check for patterns for which we want to switch to unbuffered mode (no grep, no local more)
				elsif ( $host_io->{DotActivityCnt} >= $DotActivityUnbufferThreshold ||
					($host_io->{Type} && $$outRef =~ /$UnbufferPatterns{$host_io->{Type}}/ && !(defined $UnbufPatExceptions{$host_io->{Type}} && $$outRef =~ $UnbufPatExceptions{$host_io->{Type}}))
					) {
					# Recover any previous partial output which might still be cached
					$$outRef = join('', $host_io->{GrepBuffer}, $host_io->{GrepCache}, $host_io->{OutBuffer}, $$outRef);
					# And empty those buffers
					($host_io->{GrepCache}, $host_io->{GrepBuffer}, $host_io->{OutBuffer}) = ('', '', '');
					# If in the midst of a local more prompt (unlikely), delete it
					print $term_io->{DeleteMorePrompt} if $mode->{buf_out} eq 'mp';
					if (defined $script_io->{CmdLogFH}) { # If we were logging, abort that
						close $script_io->{CmdLogFH};
						$script_io->{CmdLogFH} = $script_io->{CmdLogFile} = $script_io->{CmdLogFlag} = undef;
						printOut($script_io, "abort\n") if $script_io->{CmdLogOnly};
						$script_io->{CmdLogOnly} = undef;
					}
					elsif ($script_io->{CmdLogFile}) { # We might not have started logging yet, as this happens after printing 1st line
						$script_io->{CmdLogFH} = $script_io->{CmdLogFile} = $script_io->{CmdLogFlag} = $script_io->{CmdLogOnly} = undef;
					}
					changeMode($mode, {term_in => 'ps', dev_out => 'ub', buf_out => 'ds'}, '#HDO36'); # Switch to unbuffered mode; but keep term_in in ps mode if we are scripting so that when a prompt is received, script goes on
					$host_io->{PacedSentChars} = ''; # Wipe it clean, or it can screw our next prompt match
					debugMsg(1,"-> Switching to unbuffered output for this command!\n");
					# In ub mode now, we won't come back here anymore
				}
			}
			#
			# In order to match more prompts and other stuff above, we need to hold last line in cache (with exceptions: $doNotCacheLastLine = 1)
			# It will be fast track released by cache (below **) if we have a pause in reads and read nothing for $OutputCacheFastTimeout cycles
			#
			unless ($mode->{dev_out} eq 'ub' || $doNotCacheLastLine || $$outRef =~ /$prompt->{Match}$/) {
				$host_io->{OutCache} = stripLastLine($outRef);				# Strip last line..
				if (chomp $$outRef) {
					$host_io->{OutCache} = "\n" . $host_io->{OutCache};	# ..and preceding \n if present
					$$outRef .= $CompleteLineMarker;
				}
				debugMsg(2,"Interact-lastline-and-preceding-newline-ontoFastCache:\n>", \$host_io->{OutCache}, "<\n");
				($host_io->{CacheTimeout}, $host_io->{CacheTimeoutDF}) = (Time::HiRes::time + $OutputCacheFastTimeout, 1); # Reset to use cache fast timer
				debugMsg(4,"=Set CacheFastTimeout expiry time = ", \$host_io->{CacheTimeout}, "\n");
				changeMode($mode, {dev_cch => 'fs'}, '#HDO37');
			}
			# We shall distinguish between these incomplete lastline scenarions
			# - could be a fragment of CLI prompt / ok to print out
			# - could be a fragment of --more-- or other pattern matched above / must retain it in case
			# - could be a device prompt we need to interact with, e.g. the prompt after config / must print out fairly rapidly
			# - could be an activity line, like when upgrading a stackable, or in edit mode, or in shell; these are $UnbufferPatterns;
			#   $UnbufferPatterns will force us into dev_out 'ub' mode, and now we no longer do caching for these lines (bug13)

			# This is where we apply sed output patterns
			if (%{$term_io->{SedOutputPats}}) {
				my $markerRemoved = 1 if $$outRef =~ s/$CompleteLineMarker$//;
				sedPatternReplace($host_io, $term_io->{SedOutputPats}, $outRef);
				$$outRef .= $CompleteLineMarker if $markerRemoved;
			}
		}
		else {	# Output resulting from normal read sequence AND we are in transparent mode
			#
			# WLAN9100 spits these out with Telnet; Teraterm seems to get them also, but it suppresses them, so we do same
			$$outRef =~ s/\x10?\x00//g;
			# If running on Windows, Win32::Console::ANSI does not support ESC[?25l or ESC[?25h
			$$outRef =~ s/\e\[\?25[lh]//g if $^O eq "MSWin32"; # Remove hide/show cursor ESCape sequences
			#
			# Detection patterns for Remote Annex connection
			#
			if ($$outRef =~ /$RemoteAnnex/o) {
				$host_io->{RemoteAnnex} = 1;
				debugMsg(2,"DetectedRemoteAnnex!\n");
			}
			if ($host_io->{RemoteAnnex} && !defined $host_io->{TcpPort} && $$outRef =~ /$RemoteAnnexPort/mo) {
				$host_io->{TcpPort} = $RemoteAnnexBasePort + $1;
				debugMsg(2,"UpdatedTcpPort-to-RemoteAnnexPort:>", \$host_io->{TcpPort}, "<\n");
			}
		}
		#
		# At this point, output (if any) is ready to be printed, in either buffered or unbuffered mode
		#
		debugMsg(2,"ReadyForOutput:\n>", $outRef, "<\n");
		return unless length $$outRef;	# Skip rest unless there is something left in $$outRef
	}
	elsif (length $host_io->{OutCache}) {
		#
		# No new output but we have something in the cache
		#
		if ($mode->{dev_cch} eq 'md') { # Process more prompt handling
			# Delayed by 1 cycle, because we might have matched on --more--, but (q = quit) did not follow, so we use --more-- alone
			if (defined $prompt->{MoreRegex} && $host_io->{OutCache} =~ s/($prompt->{MoreRegex})$//) {
				my $moreStripped = $1;
				$moreStripped =~ s/^\n//; # If a newline was stripped, don't count it for expected backspaces
				$host_io->{BackspaceCount} = length $moreStripped; # Number of backspaces we expect after paging
				debugMsg(2,"BackspaceCount-fromCache:>", \$host_io->{BackspaceCount}, "<\n");
				$host_io->{SendBuffer} .= $term_io->{BufMoreAction};	# We page automatically
				debugMsg(2,"AutomaticMore-fromCache:>", \$term_io->{BufMoreAction}, "<\n");
				changeMode($mode, {dev_del => 'bs', dev_cch => 'ds'}, '#HDO38');
			}
		}
		elsif ($mode->{dev_cch} eq 'fs') { # Fast track (**)! Release the cache
			if (Time::HiRes::time < $host_io->{CacheTimeout}) { # Not yet timed out...
				debugMsg(1,"-> OutCache fast track timeout not expired; time = ", \Time::HiRes::time, " < $host_io->{CacheTimeout}\n") if $host_io->{CacheTimeoutDF};
				$host_io->{CacheTimeoutDF} = 0;
				return;
			}
			else { # Cache has timed out, so we process the cache output and clear the cache
				debugMsg(1,"-> OutCache fast track timeout EXPIRED; time = ", \Time::HiRes::time, " > $host_io->{CacheTimeout}\n");
				my $cache = $host_io->{OutCache};	# Workaround..
				($outRef, $host_io->{OutCache}) = (\$cache, '');
				debugMsg(2,"Interact-lastline-and-preceding-newline-releaseCache:\n>", $outRef, "<\n");
				changeMode($mode, {dev_cch => 'ds'}, '#HDO39');
			}
		}
		elsif ($mode->{dev_cch} eq 'ds') { # Cache normal handling
			if (Time::HiRes::time < $host_io->{CacheTimeout}) { # Not yet timed out...
				debugMsg(1,"-> OutCache timeout not expired; time = ", \Time::HiRes::time, " < $host_io->{CacheTimeout}\n") if $host_io->{CacheTimeoutDF};
				$host_io->{CacheTimeoutDF} = 0;
				return;
			}
			else { # Cache has timed out, so we process the cache output and clear the cache
				#($$outRef, $host_io->{OutCache}) = ($host_io->{OutCache}, '');	(bug9), this and line below was failing with:
				#$$outRef = $host_io->{OutCache};	Modification of a read-only value attempted at ...acli.pl line <this line>
				#$host_io->{OutCache} = '';
				debugMsg(1,"-> OutCache timeout EXPIRED; time = ", \Time::HiRes::time, " > $host_io->{CacheTimeout}\n");
				my $cache = $host_io->{OutCache};	# Workaround..
				($outRef, $host_io->{OutCache}) = (\$cache, '');
				debugMsg(1,"-> oph-cache: timeout expired!!\n");
				debugMsg(2,"==================================\nCacheTimeout:\n>", $outRef, "<\n");
				stopSourcing($db);	# If in a run script, need to stop it
				# If we were in the midst of Tab/Syntax/Delete pattern processing, drop to 'sh' mode; otherwise maintain same mode
				#  .. must also preserve term_in mode if buf_out is either 'se' or 'mp' (both of which set term_in to 'rk')
				my $newTerm_in = $mode->{dev_del} ne 'ds' || $mode->{dev_fct} ne 'ds' || $mode->{term_in} ne 'rk' ? 'sh' : $mode->{term_in};
				changeMode($mode, {term_in => $newTerm_in, dev_del => 'ds', dev_fct => 'ds'}, '#HDO40');
				$term_io->{BackSpaceMode} = undef;
			}
		}
		else {
			quit(1, "ERROR: unexpected dev_cch mode: ".$mode->{dev_cch}, $db);
		}
	}
	elsif ($mode->{dev_out} eq 'ub' && $socket_io->{Tie} && $socket_io->{TieEchoMode} == 1 && %{$socket_io->{TieEchoBuffers}}) { # Socket echo errors which did not make last prompt
		my $echoRecovered;
		foreach my $echoBuffer (keys %{$socket_io->{TieEchoBuffers}}) {
			if ($socket_io->{TieEchoSeqNumb}->{$echoBuffer} == 0) { # A complete buffer
				#$$outRef .= $socket_io->{TieEchoBuffers}->{$echoBuffer}; (bug18) was getting "Modification of a read-only value attempted" on this line [like (bug9) above]
				my $echoBuff = $$outRef . $socket_io->{TieEchoBuffers}->{$echoBuffer};
				$outRef = \$echoBuff;
				delete($socket_io->{TieEchoBuffers}->{$echoBuffer});
				delete($socket_io->{TieEchoSeqNumb}->{$echoBuffer});
				debugMsg(2,"SocketEchoCompleteOutputRecovered-in-UnbufferedMode\n");
				$echoRecovered = 1;
			}
		}
		return unless $echoRecovered;
	}
	else { # We have no output to process
		debugMsg(2,"==================================\nDEVICE: EMPTY READ\n") if $host_io->{DeviceReadFlag};
		$host_io->{DeviceReadFlag} = 0;
		return;
	}
	###########
	# DISPOSE #
	###########
	#
	# If we get here, we have output to dispose of (either print directly or queue up on the output buffer in buffered mode)
	#
	if ($mode->{dev_out} eq 'ub') { # ------> Unbuffered Mode (ub) <----------
		if ($term_io->{Mode} eq 'interact' && $mode->{dev_inp} ne 'ct' && $mode->{dev_inp} ne 'lg') { # Check for presence of prompt and set mode accordingly
			if ( checkFragPrompt($db, $outRef) ) {
				#
				# Unbuffered device prompt detected!
				#
				if (defined $script_io->{CmdLogFH}) {
					close $script_io->{CmdLogFH};
					$script_io->{CmdLogFH} = $script_io->{CmdLogFile} = $script_io->{CmdLogFlag} = undef;
					printOut($script_io, "done\n") if $script_io->{CmdLogOnly};
					printOut($script_io, "$ScriptName: Output saved to:\n$script_io->{CmdLogFullPath}\n\n");
					$script_io->{CmdLogOnly} = undef;
				}
				$term_io->{PageLineCount} = $term_io->{MorePageLines};
				$term_io->{YnPrompt} = '';
				$term_io->{YnPromptForce} = 0;
				if ($term_io->{InteractRestore}) {
					printOut($script_io, "\n$ScriptName: Using terminal interactive mode\n");
					$term_io->{InteractRestore} = undef;
				}
				$$outRef =~ s/ ?$/$term_io->{LtPromptSuffix}/ if $term_io->{LtPrompt};
				($term_io->{DelayCharProcTm}, $term_io->{DelayCharProcDF}) = (Time::HiRes::time + $DelayCharProcTm, 1);
				debugMsg(4,"=Set DelayCharProcTm expiry time = ", \$term_io->{DelayCharProcTm}, "\n");
				changeMode($mode, {term_in => 'tm'}, '#HDO41');
				if ($termbuf->{Linebuf1} || $termbuf->{Linebuf2}) { # Local Terminal input buffer is not empty (from transition #10)
					# Keep input buffer and append its contents to the device output we are about to printout
					$$outRef = join('', $$outRef, $termbuf->{Linebuf1}, $termbuf->{Linebuf2}, $termbuf->{Bufback2});
				}
				if ($term_io->{StartScriptOnTm}) { # We have a script ready to start or resume following connection
					printOut($script_io, "$ScriptName: Executing script from $term_io->{StartScriptOnTm}\n\n");
					$term_io->{StartScriptOnTm} = undef;
					releaseInputBuffer($term_io);
				}
			}
			elsif ($mode->{term_in} eq 'tm') { # Unsolicited output in term mode, not ending in prompt; we fight it
				$$outRef = "\n" . $$outRef if $$outRef !~ /^\n/;	# Make sure this output goes on fresh line
				$$outRef .= "\n" . appendPrompt($host_io, $term_io);	# Display a fresh prompt
				$$outRef .= join('', $termbuf->{Linebuf1}, $termbuf->{Linebuf2}, $termbuf->{Bufback2});	# And linebuf
				debugMsg(2,"Unsolicited output; prompt restored:\n>", $outRef, "<\n");
			}
			elsif ($term_io->{InteractRestore}) { # No prompt, and we wanted to switch back to interact mode..
				if ($term_io->{InteractRestore} > 1 && $$outRef eq "\n") { # Ignore one echo-ed CR
					$term_io->{InteractRestore}--;
					debugMsg(2,"Fast switch back to interact mode / ignoring CR: ", \$term_io->{InteractRestore}, "\n");
				}
				else { # We give up; force a new login attempt and full rediscovery of device
					$term_io->{InteractRestore} = undef;
					$host_io->{Discovery} = undef;	# Make sure we don't try any further fast switch backs to interact mode (bug22)
					$host_io->{SendBuffer} .= $term_io->{Newline} unless $host_io->{Console}; # On console we automatically send wake_console (bug22)
					changeMode($mode, {term_in => 'rk', dev_inp => 'lg'}, '#HDO42');
				}
			}
		}
		($host_io->{CacheTimeout}, $host_io->{CacheTimeoutDF}) = (Time::HiRes::time + $OutputCacheTimeout, 1);
		debugMsg(4,"=Set CacheTimeout expiry time (ub) = ", \$host_io->{CacheTimeout}, "\n");
		debugMsg(2,"UnbufferedOutput:\n>", $outRef, "<\n");
		printOut($script_io, '', '', $outRef);
	}
	elsif ($mode->{dev_out} eq 'bf') { # ------> Buffered Mode (bf) <------------
		$host_io->{OutputSinceCmd} = 1;
		$host_io->{OutBuffer} =~ s/$CompleteLineMarker$//;
		$host_io->{OutBuffer} .= $$outRef;
		if ($socket_io->{EchoSendFlag}) {
			$host_io->{DeltaBuffer} =~ s/$CompleteLineMarker$//;
			$host_io->{DeltaBuffer} = $$outRef;
		}
		debugMsg(2,"Appended to Output Buffer\n>", \$host_io->{OutBuffer}, "<\n");
	}
	else {
		quit(1, "ERROR: unexpected dev_out mode: ".$mode->{dev_out}, $db);
	}
}


sub appendOutDeltaBuffers { # Appends to both OutBuffer & DeltaBuffer
	my ($db, $outRef) = @_;
	my $host_io = $db->[3];
	my $socket_io = $db->[6];
	$host_io->{OutBuffer} .= $$outRef;
	$host_io->{DeltaBuffer} .= $$outRef if $socket_io->{EchoSendFlag};
}

1;
