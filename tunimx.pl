#!/usr/local/bin/perl

my $Version = "1.6";
# Written by Ludovico Stevens (lstevens@extremenetworks.com)
# VSP as a L1 matrix using Transparent UNI on port pairs

# 1.0	- First version
# 1.1	- LLDP state now checked as part of acquireMuxData
#	- Multi-point and orphaned connections now show LLDP state
#	- Mirroring data was not cleared before being re-read
#	- Now detects when connections timeout, and re-connects automatically
#	- Added sanitize menu option; initially checks point-point connections for LLDP on
#	- More paging now allows for Q to quit
#	- Compacted options to enable/disable LLDP on unused ports
#	- Added option to enable/disable/bounce poe
# 1.2	- acquireMuxData() is no longer called twice on timeout and reconnect to all nodes
# 1.3	- readMenuKey() fixed so that it does not crash when it reads ESC sequences from keyboard
# 1.4	- Option to enable/disable/bounce poe now also works if a connection exists for endpoint
# 1.5	- Automatic reconect in case of timeout now also applies to menu option (O) for Enable/
#	  Disable/Bounce POE
# 1.6	- On re-connect, when flushing the portid data of switches we need to reload, if the
#	  portid had an I-SID assigned, was incorrectly deleting the whole I-SID record, instead
#	  of just deleting the portid from the I-SID record; if the I-SID record also contained
#	  the portid of other switches which are not being updated, this was resulting in orphaned
#	  connections as the I-SID record became corrupted on reload

# Todo...
# - show ISID mirror offset in output


#############################
# STANDARD MODULES          #
#############################

use strict;
use warnings;
use feature 'state'; # State variable in sub page()
use Cwd;
use File::Spec;
use File::Basename;
use Getopt::Std;
use Term::ReadKey;
use Control::CLI::Extreme qw(poll :prompt);	# Export class poll method
use Data::Dumper;
$Data::Dumper::Indent = 1;
if ($^O eq "MSWin32") {
	# This is for being able to print ANSI colours
	unless (eval "require Win32::Console::ANSI") { die "Cannot find module Win32::Console::ANSI" }
}


#############################
# VARIABLES                 #
#############################

my $Debug = 0;
my $ScriptName = basename($0);
my $DefaultUsr = 'rwa';
my $DefaultPwd = 'rwa';
my $TuniIsidBase = 10000000; # We use 7 digits, so the offset can only be 10mil
my $OobVlan = 4000;
my $IgnorePortNames = '^(?i:mgmt|NNI|OOB)$';
my $OobPort = 1;
my $HostnameRegex = '-R((?:\d+\/)?\d+)';
my %ModelMap = ( # Special mapping based on switch mode; the goal is to present all ports sequential on slot1
	'VSP-7254-XTQ'		=> {
				in	=> ['^2\/(\d)', 'sprintf("1\/%s", $1+48)'],	# Map ports 2/1-2/6 to 1/49-1/54
				out	=> ['^1\/(49|5\d)', 'sprintf("2\/%s", $1-48)'],	# Re-map ports 1/49-1/54 to 2/1-2/6
				},
	'VSP-7254-XSQ'		=> {
				in	=> ['^2\/(\d)', 'sprintf("1\/%s", $1+48)'],	# Map ports 2/1-2/6 to 1/49-1/54
				out	=> ['^1\/(49|5\d)', 'sprintf("2\/%s", $1-48)'],	# Re-map ports 1/49-1/54 to 2/1-2/6
				},
);
my $PageLines = 23;
my $MorePrompt = "-- More (SPACE) / Quit (Q) --";
my $DonePrompt = "-- Done (SPACE) --";
my $TuniMxDump = "muxHash.dump";
my %InfoLine = ( # Formatting of how tunimx records will be displayed
	# Status/poe fields are normally 4/5 characters, but with ANSI clouring, need to add 9+9=18 to that; hence 22/23
	'oob_connection'		=> "%8s: %30s (%9s) %-22s <-> OOB Network\n",
					   # 4 args: vlan,portname,portid,status
	'vlan_connection'		=> "%8s: %30s (%9s) %-22s <-> Other VLAN\n",
					   # 4 args: vlan,portname,portid,status
	'point_point_connection'	=> "%8s: %30s (%9s) %-22s <-> %30s (%9s) %-4s\n",
					   # 7 args: isid,portname1,portid1,status1,portname2,portid2,status2
	'multi_point_connection1'	=> "%8s: +-> %30s (%9s) %-22s  LLDP: %s\n",
					   # 5 args: isid,portname,portid,status,lldpState
	'multi_point_connectionN'	=> "          +-> %30s (%9s) %-22s  LLDP: %s\n",
					   # 4 args: portname,portid,status,lldpState
	'orphaned_connection'		=> "%8s: --> %30s (%9s) %-22s  LLDP: %s\n",
					   # 5 args: isid,portname,portid,status,lldpState
	'endpoint_isid_assigned'	=> "%-9s %-30s %-22s %-23s ----> assigned-to-MUX-connection (I-SID %-8s)\n",
					   # 5 args: portid,portname,status,poe,isid
	'endpoint_oob_with_lldp'	=> "%-9s %-30s %-22s %-23s Connected to OOB / LLDP: %s %s %s\n",
					   # 7 args: portid,portname,status,poe,lldpIp,lldpMac,lldpName
	'endpoint_free_with_lldp'	=> "%-9s %-30s %-22s %-23s LLDP: %s %s %s\n",
					   # 7 args: portid,portname,status,poe,lldpIp,lldpMac,lldpName
	'endpoint_oob_lldp_off'		=> "%-9s %-30s %-22s %-23s Connected to OOB / LLDP: %s\n",
					   # 5 args: portid,portname,status,poe,lldpState
	'endpoint_free_lldp_off'	=> "%-9s %-30s %-22s %-23s LLDP: %s\n",
					   # 5 args: portid,portname,status,poe,lldpState
	'endpoint_oob_no_lldp'		=> "%-9s %-30s %-22s %-23s Connected to OOB\n",
					   # 4 args: portid,portname,status,poe
	'endpoint_free_no_lldp'		=> "%-9s %-30s %-22s %-23s\n",
					   # 4 args: portid,portname,status,poe
	'endpoint_free_no_status'	=> "%-9s %-30s\n",
					   # 2 args: portid,portname
	'mirror_in_and_out_line1'	=> "%30s (%9s) %-22s (%-22s) %s ---> [%8s] ---> %30s (%9s) %-22s %s\n",
					   # 10 args: portid,portname,status,mode,admin,isid/node,portid,portname,status,admin
	'mirror_in_and_out_lineN'	=> "%30s (%9s) %-22s (%-22s) %s -+            +-> %30s (%9s) %-22s %s\n",
					   # 10 args: portid,portname,status,mode,admin,isid/node,portid,portname,status,admin
	'mirror_in_only_line1'		=> "%30s (%9s) %-22s (%-22s) %s ---> [%8s]\n",
					   # 6 args: portid,portname,status,mode,admin,isid/node
	'mirror_in_only_lineN'		=> "%30s (%9s) %-22s (%-22s) %s -+\n",
					   # 6 args: portid,portname,status,mode,admin,isid/node
	'mirror_out_only_line1'		=> " "x64 . "[%8s] ---> %30s (%9s) %-22s %s\n",
					   # 5 args: isid/node,portid,portname,status,admin
	'mirror_out_only_lineN'		=> " "x76 . "+-> %30s (%9s) %-22s %s\n",
					   # 4 args: portid,portname,status,admin
);

my %Hlcolours	= (black => 0, red => 1, green => 2, yellow => 3, blue => 4, magenta => 5, cyan => 6, white => 7, disable => undef, none => undef);
my %HL = (
	red	=> { # Bright, foreground red
		on	=> "\e[1m\e[3" . $Hlcolours{'red'} . "m",
		off	=> "\e[39m\e[0m",
	},
	green	=> { # Bright, foreground green
		on	=> "\e[1m\e[3" . $Hlcolours{'green'} . "m",
		off	=> "\e[39m\e[0m",
	},
	yellow	=> { # Bright, foreground yellow
		on	=> "\e[1m\e[3" . $Hlcolours{'yellow'} . "m",
		off	=> "\e[39m\e[0m",
	},
	cyan	=> { # Bright, foreground magenta
		on	=> "\e[1m\e[3" . $Hlcolours{'cyan'} . "m",
		off	=> "\e[39m\e[0m",
	},
	magenta	=> { # Bright, foreground magenta
		on	=> "\e[1m\e[3" . $Hlcolours{'magenta'} . "m",
		off	=> "\e[39m\e[0m",
	},
);
our $opt_d;


#############################
# FUNCTIONS                 #
#############################

sub printSyntax {
	printf "%s version %s%s\n\n", $ScriptName, $Version, ($Debug ? " running on $^O perl version $]" : "");
	print "Usage:\n";
	print " $ScriptName <ssh|telnet> <switch-host-file> [<username[:password]>]\n\n";
	exit 1;
}

sub quit {
	my ($retval, $quitmsg) = @_;
	print "\n$ScriptName: ", $quitmsg, "\n" if $quitmsg;
	# Clean up and exit
	exit $retval;
}

sub debugMsg { # Takes 4 args: debug-level, string1 [, ref-to-string [, string2] ]
	if (shift() & $Debug) {
		my ($string1, $stringRef, $string2) = @_;
		my $refPrint = '';
		if (defined $stringRef) {
			if (!defined $$stringRef) {
				$refPrint = '%stringRef UNDEFINED%';
			}
			elsif (length($$stringRef) && $string1 =~ /0x$/) {
				$refPrint = unpack("H*", $$stringRef);
			}
			else {
				$refPrint = $$stringRef;
			}
		}
		$string2 = '' unless defined $string2;
		print $string1, $refPrint, $string2;
	}
}

sub checkValidHostname { # Check that hostname is consistent with TuniMX requirements of encoding a unit-id
	my $hostname = shift;
	return $1 if $hostname =~ /$HostnameRegex/;
	quit(1, "Invalid hostname '$hostname'; unable to extract switch unit-id");
}

sub checkValidIP { # v1 - Verify that the IP address is valid
	my ($ip, $ipv6, $line) = @_;
	$line = length $line ? " at line $line" : '';
	my $firstByte = 1;
	if ($ipv6) {
		if (($ipv6 = $ip) =~ /::/) {
			$ipv6 =~ s/::/my $r = ':'; $r .= '0:' for (1 .. (9 - scalar split(':', $ip))); $r/e;
		}
		quit(1, "Invalid IPv6 $ip$line") if $ipv6 =~ /::/;
		my @ipBytes = split(/:/, $ipv6);
		quit(1, "Invalid IPv6 $ip$line") if scalar @ipBytes != 8;
		foreach my $byte ( @ipBytes ) {
			quit(1, "Invalid IPv6 $ip$line") unless $byte =~ /^[\da-fA-F]{1,4}$/;
			if ($firstByte) {
				quit(1, "Invalid IPv6 $ip$line") if hex($byte) == 0;
				quit(1, "Invalid IPv6 $ip$line") if hex($byte) >= 65280;
				$firstByte = 0;
			}
			quit(1, "Invalid IPv6 $ip$line") if hex($byte) > 65535;
		}
		debugMsg(1, "checkValidIP() - IPv6 address = ", \$ipv6, "\n");
	}
	else { # IPv4
		my @ipBytes = split(/\./, $ip);
		quit(1, "Invalid IP $ip$line") if scalar @ipBytes != 4;
		foreach my $byte ( @ipBytes ) {
			if ($firstByte) {
				quit(1, "Invalid IP $ip$line") if $byte == 0;
				quit(1, "Invalid IP $ip$line") if $byte >= 224;
				$firstByte = 0;
			}
			quit(1, "Invalid IP $ip$line") if $byte > 255;
		}
		debugMsg(1, "checkValidIP() - IPv4 address = ", \$ip, "\n");
	}
	return 1; # Is valid
}

sub loadHosts { # Read a list of hostnames from file
	my ($muxHash, $infile) = @_;
	my ($lineNum, $dataSection, $hostSection);

	open(FILE, $infile) or quit(1, "Cannot open input hosts file: $!");
	while (<FILE>) {
		$lineNum++;
		chomp;				# Remove trailing newline char
		next if /^#/;			# Skip comment lines
		next if /^\s*$/;		# Skip blank lines
		if (/^__DATA__/) {
			$dataSection = '';
			next;
		}
		if (/^__HOSTS__/) {
			if (defined $dataSection) {
				my $dataHash = eval $dataSection;
				foreach my $portid (keys %$dataHash) {
					quit(1, "Invalid static portid $portid; slot must have format '0/<port>' line $lineNum\n") unless $portid =~ /^0\/\d+$/;
					$muxHash->{portid}->{$portid}->{name} = $dataHash->{$portid};
					$muxHash->{portid}->{$portid}->{status} = 'up';
					$muxHash->{portid}->{$portid}->{static} = 1;
					$muxHash->{portname}->{$dataHash->{$portid}} = $portid;
				}
				$dataSection = undef;
			}
			$hostSection = 1;
			next;
		}
		if (defined $dataSection) {
			$dataSection .= $_;	# Append
			next;
		}
		if ($hostSection) {
			if (/^\s*(\S+)\s*(?:(\S+)\s*)?(?:\#|$)/) {	# Valid entry
				my ($host, $hostname) = ($1, $2);
				checkValidIP($host, undef, $lineNum) if $host =~ /^\d+\.\d+\.\d+\.\d+$/;
				checkValidIP($1, undef, $lineNum) if $host =~ /^\[(\d+\.\d+\.\d+\.\d+)\]:\d+$/;
				checkValidIP($host, 1, $lineNum) if $host =~ /^(?:\w*:)+\w+$/;
				checkValidIP($1, 1, $lineNum) if $host =~ /^\[(?:\w*:)+\w+\]:\d+$/;
				$muxHash->{switch}->{$hostname}->{ip} = $host;
				$muxHash->{switch}->{$hostname}->{unitid} = checkValidHostname($hostname);
				next;
			}
			quit(1, "Hosts file \"$infile\" invalid syntax at line $lineNum\n");
		}
	}
	return;
}

sub readMenuKey { # Accept user menu option key
	my @validKeys = split(//, shift);
	my $key;
	do {{
		select(undef, undef, undef, 0.1); # Fraction of a sec sleep (otherwise CPU gets hammered..)
		$key = ReadKey(-1);
		next unless defined $key;
		if ($key eq "\e") { # Drain any ESC sequences
			$key = ReadKey(-1) while defined $key;
			next;
		}
	}} until defined $key && grep(/^\Q$key\E$/i, @validKeys);
	return uc $key;
}

sub mapRealPortId { # Map real switch port id to virtual port id
	my ($muxHash, $node, $portId) = @_;

	# Model specific port mapping, maps ports in non-slot1 into slot1
	if (exists $ModelMap{$muxHash->{switch}->{$node}->{model}}) {
		my ($match, $replace) = @{$ModelMap{$muxHash->{switch}->{$node}->{model}}{in}};
		$portId =~ s/$match/$replace/mgee;
	}
	# This maps VSP ports from 1/p to X/p, where X is extracted from switch sysname "TuniMX-RX"
	$portId =~ s/^1(?=\/\d)/$muxHash->{switch}->{$node}->{unitid}/mg;
	
	return $portId;
}

sub mapVirtPortId { # Map virtual switch port id back to real port id
	my ($muxHash, $node, $portId) = @_;

	# This maps VSP ports from X/p back to 1/p, where X is extracted from switch sysname "TuniMX-RX"
	$portId =~ s/^$muxHash->{switch}->{$node}->{unitid}(?=\/\d)/1/mg;

	# Model specific port mapping, maps ports in non-slot1 ports back into real slot
	if (exists $ModelMap{$muxHash->{switch}->{$node}->{model}}) {
		my ($match, $replace) = @{$ModelMap{$muxHash->{switch}->{$node}->{model}}{out}};
		$portId =~ s/$match/$replace/mgee;
	}
	
	return $portId;
}

sub hostError { # Prepend hostname before error its cli object generated
	my ($host, $errmsg) = @_;
	print "\n$host -> $errmsg";
	return;
}

sub promptCredentials { # Basically just adds a \n to promptClear / promptHide
	my ($node, $privacy, $credential) = @_;
	my $input;
	print "\n[$node] ";
	$input = promptClear($credential) if $privacy eq 'Clear';
	$input = promptHide($credential) if $privacy eq 'Hide';
	return $input;
}

sub printDots { # Prints unbuffered dots for polling activity
	local $| = 1;
	print '.';
}

sub pollComplete { # Poll current command to completion
	my $cli = shift;
	my ($running, $completed, $failed, $lastCompleted, $lastFailed);
	my @failedList;

	do {
		($running, $completed, $failed, $lastCompleted, $lastFailed) = poll(
			Object_list	=> $cli,
			Object_complete	=> 'all',
			Object_error	=> 'return',
			Poll_code	=> \&printDots,
			Errmode		=> 'return',	# Always return on error
		);
#		my $remaining = scalar(keys %$cli) - $completed;
#		printf "(%s)", $remaining if $remaining > 0;
#		print "\n - Have completed : ", join(',', @$lastCompleted) if @$lastCompleted;
		if (@$lastFailed) {
			print "\n - Have failed    : ", join(',', @$lastFailed);
			foreach my $key (@$lastFailed) {
				print "\n	 $key	: ", $cli->{$key}->errmsg;
				delete $cli->{$key};	# Don't bother with it anymore..
				push(@failedList, $key);
			}
			print "\n";
		}
#		print "\n - Summary        : Still running = $running ; Completed = $completed ; Failed = $failed\n";
	} while $running;

	return @failedList;
}

sub reportCmdError { # Reports cmd config errors and returns status accordingly
	my $cli = shift;
	my $status = 1; # Assume ok
	foreach my $host (keys %$cli) {
		unless ($cli->{$host}->last_cmd_success) {
			print "\n- $host error:\n", $cli->{$host}->last_cmd_errmsg, "\n\n";
			$status = 0;
		}
	}
	return $status;
}

sub bulkDo { # Repeat for all hosts
	my ($cli, $method, $argsRef, $noCmdError) = @_;

	foreach my $host (keys %$cli) { # Call $method for every object
		my $codeRef = $cli->{$host}->can($method);
		$codeRef->($cli->{$host}, @$argsRef);
	}
	pollComplete($cli);

	if ($method =~ /^cmd/) { # Check that command was accepted
		return reportCmdError($cli) unless $noCmdError
	}
	return 1;
}

sub acquireAll { # Connect to all TuniMX switches
	my ($muxHash, $cli) = @_;

	# Create CLI objects for all nodes
	printf "\n%s connecting to all (%s) nodes ", uc($muxHash->{connection}->{use}), scalar(keys %{$muxHash->{switch}});
	foreach my $node (sort {$a cmp $b} keys %{$muxHash->{switch}}) {
		$cli->{$node} = new Control::CLI::Extreme(
			Use			=> $muxHash->{connection}->{use},
			Blocking		=> 0,
			Prompt_credentials	=> [\&promptCredentials, $node],
			Errmode			=> [\&hostError, $node],
		);
	}
	
	# Connect to all nodes for which we have a CLI object created
	foreach my $node (keys %$cli) {
		$cli->{$node}->connect(
			Host		=> $muxHash->{switch}->{$node}->{ip},
			Username	=> $muxHash->{connection}->{username},
			Password	=> $muxHash->{connection}->{password},
			Atomic_connect	=> ($muxHash->{connection}->{use} eq 'SSH' ? 1 : 0),
		);
	}
	pollComplete($cli);
	print " done!\n";
	return unless %$cli;

	printf "Fetching global data from (%s) nodes ", scalar(keys %$cli);

	# Disable more paging
	bulkDo($cli, 'device_more_paging', [0]) or return;

	# Enable PrivExec mode
	bulkDo($cli, 'enable') or return;

	# Get the switch model
	bulkDo($cli, 'attribute', ['model']) or return;
	foreach my $node (keys %$cli) {
		$muxHash->{switch}->{$node}->{model} = ($cli->{$node}->attribute_poll)[1];
	}

	# Check PoE capability
	bulkDo($cli, 'cmd', ['show poe-main-status'], 1) or return;
	foreach my $node (keys %$cli) {
		$muxHash->{switch}->{$node}->{poe} = $cli->{$node}->last_cmd_success ? 1 : 0;
		debugMsg(1, "acquireAll() - $node is PoE capable = ", \$muxHash->{switch}->{$node}->{poe}, "\n");
	}
	print " done!\n";
	return 1;
}

sub acquireMuxData { # Get all port data from all TuniMX switches
	my ($muxHash, $cli) = @_;
	my $subNodes = {};

	# Get changes version count
	printf "Checking switch changes count from (%s) nodes ", scalar(keys %$cli);
	bulkDo($cli, 'cmd', ['show ip vrf vrfids 511']) or return;
	foreach my $node (keys %$cli) {
		my $output = ($cli->{$node}->cmd_poll)[1];
		my $changes = $output =~ /^(\d+)\s+511/mg ? $1 : 0;
		debugMsg(1, "acquireMuxData() - $node changes = ", \$changes, "\n");
		if ( !defined $muxHash->{switch}->{$node}->{changes}
		    || $changes > $muxHash->{switch}->{$node}->{changes}) {
			$muxHash->{switch}->{$node}->{changes} = $changes;
			$subNodes->{$node} = $cli->{$node};
			debugMsg(1, "acquireMuxData() - updating all data for switch $node\n");
		}
	}
	print " done!\n";
	return 1 unless %$subNodes;

	# Flush data structure of data from switches we are about to refresh
	foreach my $portid (keys %{$muxHash->{portid}}) { # Used portids
		next if exists $muxHash->{portid}->{$portid}->{static}; # Skip static ports
		my $node = $muxHash->{portid}->{$portid}->{switch};
		if (exists $subNodes->{$node}) {
			# Portid to delete
			if (exists $muxHash->{portid}->{$portid}->{isid}) {
				# Remove port-id from I-SID
				my $isid = $muxHash->{portid}->{$portid}->{isid};
				@{$muxHash->{isid}->{$isid}} = grep {$_ ne $portid} @{$muxHash->{isid}->{$isid}};
				debugMsg(1, "acquireMuxData() - data struct deleted portid $portid from I-SID $isid\n");
			}
			my $portname = $muxHash->{portid}->{$portid}->{name};
			delete $muxHash->{portname}->{$portname};
			debugMsg(1, "acquireMuxData() - data struct deleted portname $portname\n");
			delete $muxHash->{portid}->{$portid};
			debugMsg(1, "acquireMuxData() - data struct deleted portid $portid\n");
		}
	}
	foreach my $portid (keys %{$muxHash->{unused}}) { # Same for unused portids
		if (exists $subNodes->{$muxHash->{unused}->{$portid}}) {
			# Unused Portid to delete
			delete $muxHash->{unused}->{$portid};
			debugMsg(1, "acquireMuxData() - data struct deleted unused portid $portid\n");
		}
	}

	# Get port name data
	printf "Fetching port data from (%s) nodes ", scalar(keys %$subNodes);
	bulkDo($subNodes, 'cmd', ['show interfaces gigabitEthernet name']) or return;
	foreach my $node (keys %$subNodes) {
		my $output = ($subNodes->{$node}->cmd_poll)[1];
		while ($output =~ /^((?:\d+\/)?\d+\/\d+)\s+(?:(\S.*\S)\s+)?\S+\s+(?:up|down)/mg) {
			my ($portid, $portname) = (mapRealPortId($muxHash, $node, $1), $2);
			unless (defined $portname) { # Unused ports; we add them to db
				debugMsg(1, "acquireMuxData() - $node portid $portid is unused\n");
				$muxHash->{unused}->{$portid} = $node;
				next;
			}
			next if $portname =~ /$IgnorePortNames/;
			debugMsg(1, "acquireMuxData() - $node portid $portid name $portname\n");
			$muxHash->{portname}->{$portname} = $portid;
			$muxHash->{portid}->{$portid}->{name} = $portname;
			$muxHash->{portid}->{$portid}->{switch} = $node;
		}
	}
	print " done!\n";

	# Get ports where LLDP status
	printf "Fetching ports LLDP status from (%s) nodes ", scalar(keys %$subNodes);
	bulkDo($subNodes, 'cmd', ['show lldp port']) or return;
	foreach my $node (keys %$subNodes) {
		my $output = ($subNodes->{$node}->cmd_poll)[1];
		while ($output =~ /^((?:\d+\/)?\d+\/\d+)\s+(disabled|txAndRx)/mg) {
			my $portid = mapRealPortId($muxHash, $node, $1);
			next unless exists $muxHash->{portid}->{$portid};
			my $lldpState = $2 eq 'disabled' ? 'off' : 'on';
			debugMsg(1, "acquireMuxData() - $node portid $portid has LLDP $lldpState\n");
			$muxHash->{portid}->{$portid}->{lldp}->{state} = $lldpState;
		}
	}
	print " done!\n";

	# Get port PoE status
	my $poeNodes = {};
	foreach my $node (keys %$subNodes) {
		$poeNodes->{$node} = $subNodes->{$node} if $muxHash->{switch}->{$node}->{poe};
	}
	printf "Fetching port PoE status from (%s) nodes ", scalar(keys %$poeNodes);
	bulkDo($poeNodes, 'cmd', ['show poe-port-status']) or return;
	foreach my $node (keys %$poeNodes) {
		my $output = ($poeNodes->{$node}->cmd_poll)[1];
		while ($output =~ /^((?:\d+\/)?\d+\/\d+)\s+(Enable|Disable)\s+(DeliveringPower)?/mg) {
			my $portid = mapRealPortId($muxHash, $node, $1);
			next unless exists $muxHash->{portid}->{$portid};
			my ($poeState, $poePower) = ($2, $3);
			debugMsg(1, "acquireMuxData() - $node portid $portid has POE $poeState and is delivering power\n") if defined $3;
			debugMsg(1, "acquireMuxData() - $node portid $portid has POE $poeState and is not delivering power\n") unless defined $3;
			$muxHash->{portid}->{$portid}->{poe}->{state} = $poeState eq 'Enable' ? 1 : 0;
			$muxHash->{portid}->{$portid}->{poe}->{power} = defined $poePower ? 1 : 0;
		}
	}
	print " done!\n";

	# Get port T-UNI I-SIDs
	printf "Fetching port I-SID data from (%s) nodes ", scalar(keys %$subNodes);
	bulkDo($subNodes, 'cmd', ['show interfaces gigabitEthernet i-sid']) or return;
	foreach my $node (keys %$subNodes) {
		my $output = ($subNodes->{$node}->cmd_poll)[1];
		while ($output =~ /^((?:\d+\/)?\d+\/\d+)\s+\d+\s+(\d+)\s+N\/A\s+N\/A\s+ELAN_TR/mg) {
			my ($portid, $isid) = (mapRealPortId($muxHash, $node, $1), $2);
			debugMsg(1, "acquireMuxData() - $node portid $portid i-sid $isid\n");
			$muxHash->{portid}->{$portid}->{isid} = $isid;
			push(@{$muxHash->{isid}->{$isid}}, $portid);
		}
	}
	print " done!\n";

	# Get port VLAN (OOB) connections
	printf "Fetching port VLAN data from (%s) nodes ", scalar(keys %$subNodes);
	bulkDo($subNodes, 'cmd', ['show interfaces gigabitEthernet vlan']) or return;
	foreach my $node (keys %$subNodes) {
		my $output = ($subNodes->{$node}->cmd_poll)[1];
		while ($output =~ /^((?:\d+\/)?\d+\/\d+)\s+disable\s+false\s+false\s+\d+\s+([1-9]\d*)/mg) {
			my ($portid, $vlan) = (mapRealPortId($muxHash, $node, $1), $2);
			next unless exists $muxHash->{portid}->{$portid};
			debugMsg(1, "acquireMuxData() - $node portid $portid vlan $vlan\n");
			$muxHash->{portid}->{$portid}->{vlan} = $vlan;
		}
	}
	print " done!\n";
	return 1;
}

sub refreshPortStatus { # Get fresh port status of port ids
	my ($muxHash, $cli) = @_;

	# Get port link status
	printf "Fetching port status from (%s) nodes ", scalar(keys %$cli);
	bulkDo($cli, 'cmd', ['show interfaces gigabitEthernet interface']) or return;
	foreach my $node (keys %$cli) {
		my $output = ($cli->{$node}->cmd_poll)[1];
		while ($output =~ /^((?:\d+\/)?\d+\/\d+)\s+\d+\s+\S+\s+(?:true|false)\s+(?:true|false)\s+\d+\s+[\d:a-f]+\s+(up|down)\s+(up|down)/mg) {
			my ($portid, $admin, $oper) = (mapRealPortId($muxHash, $node, $1), $2, $3);
			next unless exists $muxHash->{portid}->{$portid};
			debugMsg(1, "refreshPortStatus() - $node portid $portid admin $admin oper $oper\n");
			$muxHash->{portid}->{$portid}->{status} = $admin eq 'down' ? 'dis' : $oper;
		}
	}
	print " done!\n";
	return 1;
}

sub refreshLldpNeighbours { # Get fresh LLDP neighbours of port ids
	my ($muxHash, $cli) = @_;

	# Get port LLDP neighbours
	printf "Fetching port LLDP neighbours from (%s) nodes ", scalar(keys %$cli);
	bulkDo($cli, 'cmd', ['show lldp neighbor summary']) or return;
	foreach my $node (keys %$cli) {
		my $output = ($cli->{$node}->cmd_poll)[1];
		while ($output =~ /^((?:\d+\/)?\d+\/\d+)\s+LLDP\s+((?:\d+\.){3}\d+)\s+((?:[a-f\d]{2}:){5}[a-f\d]{2})\s+\S+\s+(\S+)/mg) {
			my ($portid, $ip, $mac, $sysname) = (mapRealPortId($muxHash, $node, $1), $2, $3, $4);
			next unless exists $muxHash->{portid}->{$portid};
			debugMsg(1, "refreshLldpNeighbours() - $node portid $portid LLDP neighbour $ip $mac $sysname\n");
			$muxHash->{portid}->{$portid}->{lldp}->{nghbr} = [$ip, $mac, $sysname];
		}
	}
	print " done!\n";
	return 1;
}

sub incrementChangesCount { # Increment changes version number on selected TuniMX switches
	my ($muxHash, $cli) = @_;
	my $changeCount = {};

	# Get current changes version count
	printf "Updating switch changes count from (%s) nodes ", scalar(keys %$cli);
	bulkDo($cli, 'cmd', ['show ip vrf vrfids 511']) or return;
	foreach my $node (keys %$cli) {
		my $output = ($cli->{$node}->cmd_poll)[1];
		my $changes = $output =~ /^(\d+)\s+511/mg ? $1 : 0;
		debugMsg(1, "incrementChangesCount() - $node changes = ", \$changes, "\n");
		$changeCount->{$node} = $changes;
	}
	bulkDo($cli, 'cmd', ['config term']);
	foreach my $node (keys %$cli) {
		if ($changeCount->{$node}) {
			$cli->{$node}->cmd(sprintf("ip vrf %s name %s", $changeCount->{$node}, $changeCount->{$node}+1));
			$changeCount->{$node}++;
		}
		else {
			$cli->{$node}->cmd("ip vrf 1 vrfid 511");
			$changeCount->{$node} = 1;
		}
	}
	pollComplete($cli);
	return unless reportCmdError($cli);
	bulkDo($cli, 'cmd', ['end'])  or return;
	foreach my $node (keys %$cli) {
		$muxHash->{switch}->{$node}->{changes} = $changeCount->{$node};
		debugMsg(1, "incrementChangesCount() - $node changes increased to = ", \$changeCount->{$node}, "\n");
	}
	print " done!\n";
	return 1;
}

sub acquireMirroringData { # Extract mirroring info
	my ($muxHash, $cli) = @_;

	$muxHash->{mirror} = {}; # Flush all data

	# Get RSPAN monitor ports
	printf "Fetching fabric RSPAN monitor ports from (%s) nodes ", scalar(keys %$cli);
	bulkDo($cli, 'cmd', ['show monitor-by-isid']) or return;
	foreach my $node (keys %$cli) {
		my $output = ($cli->{$node}->cmd_poll)[1];
		while ($output =~ /^\d+\s+(\d+)\s+\d+\s+((?:\d+\/)?\d+\/\d+)\s+-\s+(-|\d+)\s+(true|false)/mg) {
			my ($isid, $portid, $qtag, $enabled) = ($1, mapRealPortId($muxHash, $node, $2), $3, $4);
			debugMsg(1, "acquireMirroringData() - $node isid $isid monitor $portid qtag $qtag enable $enabled\n");
			$muxHash->{mirror}->{isid}->{$isid}->{monitor}->{$portid}->{qtag} = $qtag eq '-' ? 0 : $qtag;
			$muxHash->{mirror}->{isid}->{$isid}->{monitor}->{$portid}->{enabled} = $enabled eq 'true' ? 'ena' : 'dis';
			$muxHash->{mirror}->{isid}->{$isid}->{monitor}->{$portid}->{switch} = $node;
		}
	}
	print " done!\n";

	# Get RSPAN/normal mirror ports
	printf "Fetching fabric mirror ports from (%s) nodes ", scalar(keys %$cli);
	bulkDo($cli, 'cmd', ['show mirror-by-port']) or return;
	foreach my $node (keys %$cli) {
		my $output = ($cli->{$node}->cmd_poll)[1];
		while ($output =~ /^\d+\s+((?:\d+\/)?\d+\/\d+)\s+(?:((?:\d+\/)?\d+\/\d+)\s+-|(\d+)\s+\d+)\s+(true|false)\s+(rx|tx|both)/mg) {
			# $1 & $2 could in theory be more than 1 port... but we'll assume not!
			my ($inportid, $outportid, $isid, $enabled, $mode) = (mapRealPortId($muxHash, $node, $1), $2, $3, $4, $5);
			$outportid = mapRealPortId($muxHash, $node, $outportid) if defined $outportid;
			if (defined $outportid) {
				debugMsg(1, "acquireMirroringData() - $node in-port $inportid out-port $outportid enable $enabled mode $mode\n");
				$muxHash->{mirror}->{switch}->{$node}->{mirror}->{$inportid}->{enabled} = $enabled eq 'true' ? 'ena' : 'dis';
				$muxHash->{mirror}->{switch}->{$node}->{mirror}->{$inportid}->{mode} = $mode eq 'both' ? 'rxtx' : $mode;
				$muxHash->{mirror}->{switch}->{$node}->{monitor}->{$outportid} = 1;
			}
			elsif (defined $isid) {
				debugMsg(1, "acquireMirroringData() - $node in-port $inportid isid $isid enable $enabled mode $mode\n");
				$muxHash->{mirror}->{isid}->{$isid}->{mirror}->{$inportid}->{enabled} = $enabled eq 'true' ? 'ena' : 'dis';
				$muxHash->{mirror}->{isid}->{$isid}->{mirror}->{$inportid}->{mode} = $mode eq 'both' ? 'rxtx' : $mode;
				$muxHash->{mirror}->{isid}->{$isid}->{mirror}->{$inportid}->{switch} = $node;
			}
		}
	}
	print " done!\n";

	return 1;
}

sub checkConnections { # Check CLI object to see whether all are connected
	my $cli = shift;
	foreach my $node (keys %$cli) {
		$cli->{$node}->put(String => ' ', Errmode => 'return');
		$cli->{$node}->read(Errmode => 'return');
		return 0 if $cli->{$node}->eof;
	}
	return 1;
}

sub relinquishAll { # Disconnect from all switches
	my $cli = shift;

	foreach my $node (keys %$cli) {
		$cli->{$node}->disconnect;
	}
}

sub pause { # Prints a more/done line and pauses until space hit
	my $prompt = shift;
	(my $delete = $prompt) =~ s/./\cH \cH/g;
	$| = 1; # Unbuffer STDOUT
	print $prompt;
	my $key = readMenuKey(' Q');
	print $delete;
	$| = 0;
	return $key eq 'Q' ? 0 : 1;
}

sub page { # Print output while paging
	my ($output, $resetCount) = @_;
	state $count = 0;
	$count = 0 if $resetCount;
	while ($output =~ s/^(.*\n|.+\n?)//) { # For every line
		print $1;
		next if ++$count < $PageLines;
		pause($MorePrompt) or return;
		$count = 0;
	}
	return 1;
}

sub searchEndPoint { # Given a port id or string returns matching port ids
	my ($muxHash, $searchString) = @_;

	if (exists($muxHash->{portid}->{$searchString})) { # Port match
		return [$searchString];
	}
	else { # Name search
		my @match = grep(/$searchString/i, keys %{$muxHash->{portname}});
		my @matchIds = map {$muxHash->{portname}->{$_}} @match;
		return \@matchIds;
	}
}

sub matchin { # Searches for occurrence of at least 1 element in searchList in compareList
	my ($compareListRef, $searchListRef) = @_;

	foreach my $portid (@$compareListRef) {
		return 1 if grep {$_ eq $portid} @$searchListRef;
	}
	return 0;
}

sub selectPorts{ # Input selection of end-points
	my ($muxHash, $numberEndpoints, $connectionCheck) = @_;
	# $connectionCheck:
	# 0 =     there must be no connections on selected endpoint
	# 1 =     there must be a connection on selected endpoint
	# undef = don't care, selected endpoint may or may not have a connection
	my (@portids, $endPoint);

	unless (defined $numberEndpoints) {
		print "\nNumber of end-points (minimum 3) ? ";
		chomp($numberEndpoints = <STDIN>);
		return unless $numberEndpoints && $numberEndpoints =~ /^\d+$/ && $numberEndpoints >= 3;
	}

	for my $i (1..$numberEndpoints) {
		print "\nEnter end-point name or port #$i: ";
		chomp($endPoint = <STDIN>);
		my $matchPortids = searchEndPoint($muxHash, $endPoint);
		if (@$matchPortids) {
			if (scalar @$matchPortids == 1) {
				push(@portids, $matchPortids->[0]);
			}
			else {
				print "Selection matches multiple ports:\n";
				foreach my $portid (@$matchPortids) {
					printf " - %9s : %s\n", $portid, $muxHash->{portid}->{$portid}->{name};
				}
				return;
			}
		}
		else {
			print "No matching end-point found\n";
			return;
		}
		my $portid = $portids[$i-1];
		my $portname = $muxHash->{portid}->{$portid}->{name};
		printf "----> Port %s: %s\n", $portid, $portname;
		next unless defined $connectionCheck;
		if ($connectionCheck) {
			unless (exists $muxHash->{portid}->{$portid}->{isid} || exists $muxHash->{portid}->{$portid}->{vlan}) {
				printf "End-point %s (%s) has no I-SID or OOB Connection\n", $portid, $portname;
				return;
			}
		}
		else {
			if (exists $muxHash->{portid}->{$portid}->{isid}) {
				printf "I-SID Connection already exists for end-point %s (%s)\n", $portid, $portname;
				return;
			}
			if (exists $muxHash->{portid}->{$portid}->{vlan}) {
				printf "OOB Connection already exists for end-point %s (%s)\n", $portid, $portname;
				return;
			}
		}
	}
	return @portids;
}

sub deriveIsid { # Given port numbers derives unique I-SID fot T-UNI
	my ($muxHash, $portids) = @_;
	my ($isidOffset, $isid);

	foreach my $portid (@$portids) {
		my @portidNumbers = split('/', $portid);
		if (exists $muxHash->{portid}->{$portid}->{static}) {	# Static ports
			$isidOffset = $portidNumbers[1];	# I-SID has to be $TuniIsidBase + port-id
			last;
		}
		push(@portidNumbers, "0") while scalar @portidNumbers < 4; # adjust to 4 values
		debugMsg(1, "deriveIsid() - portid $portid digits = ", \join('-', @portidNumbers), "\n");
		my $derived = sprintf("%02u%02u%02u%01u", @portidNumbers);
		$isidOffset = $derived if !defined $isidOffset || $isidOffset > $derived; # Use lowest port number as index
	}
	$isid = $TuniIsidBase + $isidOffset;
	while (exists $muxHash->{isid}->{$isid}) {
		printf "Derived I-SID %s is clashing with same I-SID used on ports %s\n", $isid, join(',', @{$muxHash->{isid}->{$isid}});
		$isid++;
	}
	debugMsg(1, "deriveIsid() - derived I-SID  = ", \$isid, "\n");
	return $isid;
}

sub by_slotPort { # Sort by rack/[unit]/port/channel
	my $compareResult;
	my @a = split("[/:]", $a);
	my @b = split("[/:]", $b);
	$compareResult = $a[0] <=> $b[0];			# Sort on rack number first
	return $compareResult if $compareResult;
	$compareResult = $a[1] <=> $b[1];			# Then on unit/port number
	return $compareResult if $compareResult;
	$compareResult = defined $a[2] <=> defined $b[2];	# In case we are sorting between a 1/2 port and a 1/2/3 port
	return $compareResult if $compareResult;
	$compareResult =  $a[2] <=> $b[2];			# Then on port/channel number
	return $compareResult if $compareResult;
	$compareResult = defined $a[3] <=> defined $b[3];	# In case we are sorting between a 1/2/3 port and a 1/2/3/4 port
	return $compareResult if $compareResult;
	return $a[3] <=> $b[3];					# Then on channelized port
}

sub colourStatus { # Colour up/down/dis port & poe status
	my $status = shift;
	return $HL{green}{on} . $status . $HL{green}{off} if $status =~ /^(?:up|ena|on)$/;
	return $HL{red}{on} . $status . $HL{red}{off} if $status =~ /^(?:down|off|poff)$/;
	return $HL{yellow}{on} . $status . $HL{yellow}{off} if $status eq 'dis';
	return $HL{cyan}{on} . $status . $HL{cyan}{off} if $status =~ /^(?:rx|tx|rxtx)$/;
	return $HL{magenta}{on} . $status . $HL{yellow}{off}; # PoE status
}

sub poePortStatus { # Formats the poe status to print for end-point
	my ($muxHash, $portid) = @_;
	return '' unless exists $muxHash->{portid}->{$portid}->{poe};
	return 'poff' if $muxHash->{portid}->{$portid}->{poe}->{state} eq 'off';
	return 'poe' if $muxHash->{portid}->{$portid}->{poe}->{power};
	return ''; # Otherwise
}

sub printConnections { # Print out all connections
	my ($muxHash, $listIn) = @_;
	my $portidList = defined $listIn ? $listIn : [keys %{$muxHash->{portid}}];

	my $sectionStarted;
	foreach my $portid (sort by_slotPort @$portidList) {
		next unless exists $muxHash->{portid}->{$portid}->{vlan};
		page("\nOOB Connections:\n") or return unless $sectionStarted++;
		if ($muxHash->{portid}->{$portid}->{vlan} == $OobVlan) {
			page(sprintf $InfoLine{oob_connection},
				$muxHash->{portid}->{$portid}->{vlan},
				$muxHash->{portid}->{$portid}->{name},
				$portid,
				colourStatus($muxHash->{portid}->{$portid}->{status}),
			) or return;
		}
		else {
			page(sprintf $InfoLine{vlan_connection},
				$muxHash->{portid}->{$portid}->{vlan},
				$muxHash->{portid}->{$portid}->{name},
				$portid,
				colourStatus($muxHash->{portid}->{$portid}->{status}),
				$muxHash->{portid}->{$portid}->{vlan}
			) or return;
		}
	}
	undef $sectionStarted;
	foreach my $isid (sort { $a <=> $b } keys %{$muxHash->{isid}}) {
		next unless scalar @{$muxHash->{isid}->{$isid}} == 2;
		next if defined $listIn && !matchin($muxHash->{isid}->{$isid}, $listIn);
		page("\nT-UNI point-point connections:\n") or return unless $sectionStarted++;
		my ($portid1, $portid2);
		if ( defined $listIn && grep {$_ eq $muxHash->{isid}->{$isid}->[1]} @$listIn) {
			$portid1 = $muxHash->{isid}->{$isid}->[1];
			$portid2 = $muxHash->{isid}->{$isid}->[0];
		}
		else {
			$portid1 = $muxHash->{isid}->{$isid}->[0];
			$portid2 = $muxHash->{isid}->{$isid}->[1];
		}
		page(sprintf $InfoLine{point_point_connection},
			$isid,
			$muxHash->{portid}->{$portid1}->{name},
			$portid1,
			colourStatus($muxHash->{portid}->{$portid1}->{status}),
			$muxHash->{portid}->{$portid2}->{name},
			$portid2,
			colourStatus($muxHash->{portid}->{$portid2}->{status}),
		) or return;
	}
	undef $sectionStarted;
	foreach my $isid (sort { $a <=> $b } keys %{$muxHash->{isid}}) {
		next unless scalar @{$muxHash->{isid}->{$isid}} > 2;
		next if defined $listIn && !matchin($muxHash->{isid}->{$isid}, $listIn);
		page("\nT-UNI multi-point connections:\n") or return unless $sectionStarted++;
		for my $i (0..$#{$muxHash->{isid}->{$isid}}) {
			my $portid = $muxHash->{isid}->{$isid}->[$i];
			page(sprintf $InfoLine{multi_point_connection1},
				$isid,
				$muxHash->{portid}->{$portid}->{name},
				$portid,
				colourStatus($muxHash->{portid}->{$portid}->{status}),
				colourStatus($muxHash->{portid}->{$portid}->{lldp}->{state}),
			) or return if $i == 0;
			page(sprintf $InfoLine{multi_point_connectionN},
				$muxHash->{portid}->{$portid}->{name},
				$portid,
				colourStatus($muxHash->{portid}->{$portid}->{status}),
				colourStatus($muxHash->{portid}->{$portid}->{lldp}->{state}),
			) or return if $i > 0;
		}
	}
	undef $sectionStarted;
	foreach my $isid (sort { $a <=> $b } keys %{$muxHash->{isid}}) {
		next unless scalar @{$muxHash->{isid}->{$isid}} == 1;
		next if defined $listIn && !matchin($muxHash->{isid}->{$isid}, $listIn);
		page("\nT-UNI orphaned connections:\n") or return unless $sectionStarted++;
		my $portid = $muxHash->{isid}->{$isid}->[0];
		page(sprintf $InfoLine{orphaned_connection},
			$isid,
			$muxHash->{portid}->{$portid}->{name},
			$portid,
			colourStatus($muxHash->{portid}->{$portid}->{status}),
			colourStatus($muxHash->{portid}->{$portid}->{lldp}->{state}),
		) or return;
	}
	return 1;
}

sub printEndPoints { # Print out all end points
	my ($muxHash, $listIn) = @_;
	my $portidList = defined $listIn ? $listIn : [keys %{$muxHash->{portid}}];

	foreach my $portid (sort by_slotPort @$portidList) {
		if (exists $muxHash->{portid}->{$portid}->{isid}) {
			page(sprintf $InfoLine{endpoint_isid_assigned},
				$portid,
				$muxHash->{portid}->{$portid}->{name},
				colourStatus($muxHash->{portid}->{$portid}->{status}),
				colourStatus(poePortStatus($muxHash, $portid)),
				$muxHash->{portid}->{$portid}->{isid},
			) or return;
		}
		elsif ($muxHash->{portid}->{$portid}->{lldp}->{nghbr}) {
			if (exists $muxHash->{portid}->{$portid}->{vlan}) {
				page(sprintf $InfoLine{endpoint_oob_with_lldp},
					$portid,
					$muxHash->{portid}->{$portid}->{name},
					colourStatus($muxHash->{portid}->{$portid}->{status}),
					colourStatus(poePortStatus($muxHash, $portid)),
					$muxHash->{portid}->{$portid}->{lldp}->{nghbr}->[0],
					$muxHash->{portid}->{$portid}->{lldp}->{nghbr}->[1],
					$muxHash->{portid}->{$portid}->{lldp}->{nghbr}->[2],
				) or return;
			}
			else {
				page(sprintf $InfoLine{endpoint_free_with_lldp},
					$portid,
					$muxHash->{portid}->{$portid}->{name},
					colourStatus($muxHash->{portid}->{$portid}->{status}),
					colourStatus(poePortStatus($muxHash, $portid)),
					$muxHash->{portid}->{$portid}->{lldp}->{nghbr}->[0],
					$muxHash->{portid}->{$portid}->{lldp}->{nghbr}->[1],
					$muxHash->{portid}->{$portid}->{lldp}->{nghbr}->[2],
				) or return;
			}
		}
		elsif (defined $muxHash->{portid}->{$portid}->{lldp}->{state} && $muxHash->{portid}->{$portid}->{lldp}->{state} eq 'off') { # LLDP off
			if (exists $muxHash->{portid}->{$portid}->{vlan}) {
				page(sprintf $InfoLine{endpoint_oob_lldp_off},
					$portid,
					$muxHash->{portid}->{$portid}->{name},
					colourStatus($muxHash->{portid}->{$portid}->{status}),
					colourStatus(poePortStatus($muxHash, $portid)),
					colourStatus('off'),
				) or return;
			}
			else {
				page(sprintf $InfoLine{endpoint_free_lldp_off},
					$portid,
					$muxHash->{portid}->{$portid}->{name},
					colourStatus($muxHash->{portid}->{$portid}->{status}),
					colourStatus(poePortStatus($muxHash, $portid)),
					colourStatus('off'),
				) or return;
			}
		}
		else { # No LLDP data
			if (exists $muxHash->{portid}->{$portid}->{vlan}) {
				page(sprintf $InfoLine{endpoint_oob_no_lldp},
					$portid,
					$muxHash->{portid}->{$portid}->{name},
					colourStatus($muxHash->{portid}->{$portid}->{status}),
					colourStatus(poePortStatus($muxHash, $portid)),
				) or return;
			}
			else {
				page(sprintf $InfoLine{endpoint_free_no_lldp},
					$portid,
					$muxHash->{portid}->{$portid}->{name},
					colourStatus($muxHash->{portid}->{$portid}->{status}),
					colourStatus(poePortStatus($muxHash, $portid)),
				) or return;
			}
		}
	}
	return 1;
}


#############################
# MAIN                      #
#############################

MAIN:{
	# Variables
	my ($inputHostsfile, $credentials);
	my $mainloop = 1;

	my $cli = {}; # Hash reference holding Control::CLI::AvayaData objects
	my $muxHash = {};
	#  $muxHash = {
	#	switch	=> {
	#		<switch-name>	=> {
	#			ip	=> <ip>,
	#			model	=> <model>
	#			poe	=> 0|1,
	#			unitid	=> <unitid>
	#			changes	=> <number>
	#		},
	#	},
	#	connection	=> {
	#		use		=> telnet|ssh,
	#		username	=> <username>
	#		password	=> <password>
	#	},
	#	portname	=> <portId>,
	#	portid	=> {
	#		<portid>	=> {
	#			switch	=> <switch-name>
	#			name	=> <undef|name>
	#			isid	=> <none|isid>
	#			vlan	=> <vlan-id>
	#			poe	=> {
	#				state	=> on|off
	#				power	=> 0|1
	#			},
	#			status	=> up|down|dis
	#			lldp	=> {
	#				nghbr	=> [ip, mac, sysname]
	#				state	=> on|off
	#			},
	#			static	= 1 # Set for static TuniMx ports
	#		},
	#	},
	#	isid	=> {
	#		<isid>		=> <port-list>,
	#	},
	#	unused	=> {
	#		<portid>	=> <switch-name>,
	#	},
	#	mirror	=> {
	#		isid	=> {
	#			<isid>	=> {
	#				mirror	=> {
	#					<portid>	=> {
	#						mode	=> 'rx|tx|rx+tx'
	#						enabled	=> 'ena|dis'
	#						switch	=> <switch-name>
	#					}
	#				}
	#				monitor	=> {
	#					<portid>	=> {
	#						qtag	=> <q-tag>
	#						enabled	=> 'ena|dis'
	#						switch	=> <switch-name>
	#					}
	#				}
	#			}
	#		},
	#		switch	=> {
	#			<switch>	=> {
	#				mirror	=> {
	#					<portid>	=> {
	#						mode	=> 'rx|tx|rx+tx'
	#						enabled	=> 0|1
	#					}
	#				}
	#				monitor	=> {
	#					<portid>	=> 1,
	#				}
	#			}
	#		}
	#	},
	#  };


	# Debug flag -d
	getopts('d');
	$Debug = 1 if $opt_d;

	# Argument processing
	$muxHash->{connection}->{use} = uc shift(@ARGV) or printSyntax;
	$muxHash->{connection}->{use} =~ /^ssh|telnet$/i or printSyntax;

	$inputHostsfile = shift(@ARGV) or printSyntax;
	loadHosts($muxHash, $inputHostsfile);

	$credentials = shift(@ARGV) if @ARGV;
	if ($credentials) {
		printSyntax unless $credentials =~ /^([^:]+?)(?::(.+?))?$/;
		$muxHash->{connection}->{username} = $1;
		$muxHash->{connection}->{password} = $2 || $DefaultPwd;
	}
	else {
		$muxHash->{connection}->{username} = $DefaultUsr;
		$muxHash->{connection}->{password} = $DefaultPwd;
	}

	# Connect to all switches
	acquireAll($muxHash, $cli) or quit(1, "Unable to acquire TuniMX nodes");

	# Acquire rest of mux port data
	acquireMuxData($muxHash, $cli) or quit(1, "Unable to acquire TuniMX data");

	my $key;
	LOOP: while ($mainloop) {
		print "\n";
		print "==========================\n";
		print "TuniMX Script (v$Version)\n";
		print "==========================\n";

		# Print list of available actions
		print "Select desired action:\n";
		print "  (P) - Create a new point-point patch connection\n";
		print "  (M) - Create a new multi-point patch connection\n";
		print "  (B) - Attach end-point to OOB network\n";
		print "  (D) - Delete existing patch connection\n";
		print "  (C) - List established end-point connections\n";
		print "  (E) - List available end-points\n";
		print "  (A) - Add a new end-point\n";
		print "  (R) - Remove an end-point\n";
		print "  (S) - Search an end-point\n";
		print "  (N) - Show mirroring ports\n";
		print "  (L) - Enable/Disable LLDP on unused end-points\n";
		print "  (O) - Enable/Disable/Bounce POE on end-points\n";
		print "  (Z) - Sanitize configuration\n";
		print "  (W) - Dump data structure\n";
		print "  (Q) - Quit\n\n";

		$key = readMenuKey('PMBDCEARSNLOZWQ ');
		$key = '' if $key eq ' '; # Refresh menu on hitting space

		# Check connections are all active
		unless ($key eq 'Q') { # Skip check for these options
			unless (checkConnections($cli)) {
				print "Some connections were lost... reconnecting...\n";
				$cli = {};	# Clear out the CLI object and re-connect from scratch
				acquireAll($muxHash, $cli) or quit(1, "Unable to acquire TuniMX nodes");
			}
		}

		($key eq 'P' || $key eq 'M') && do { # Create a new point-point/multi-point patch connection
			acquireMuxData($muxHash, $cli) or next LOOP; # Refresh data if needed
			print "\n($key) - Select end-points(ports) to connect together\n";
			my @portids = selectPorts($muxHash, $key eq 'P' ? 2 : undef, 0);
			next LOOP unless @portids;
			my $isid = deriveIsid($muxHash, \@portids);
			next LOOP unless $isid;
			my $lldpAction = 'D'; # Assume we will disable it
			if ($key eq 'M') { # FOr multi-point user chooses
				print "\nLLDP (E) Enabled or (D) Disabled on end-points?\n";
				$lldpAction = readMenuKey('EDQ');
				next LOOP if $lldpAction eq 'Q';
			}
			# Prepare hash of nodes and related ports
			my $nodePortHash = {};
			foreach my $portid (@portids) {
				next if exists $muxHash->{portid}->{$portid}->{static};
				my $node = $muxHash->{portid}->{$portid}->{switch};
				push(@{$nodePortHash->{$node}}, mapVirtPortId($muxHash, $node, $portid));
			}
			# Get the switches CLI objects involved, and reformat port list to comma separated string
			my $subNodes = {};
			foreach my $node (keys %$nodePortHash) {
				$nodePortHash->{$node} = join(',', @{$nodePortHash->{$node}});
				$subNodes->{$node} = $cli->{$node};
			}
			printf "Configuring (%s) nodes ", scalar(keys %$subNodes);
			bulkDo($subNodes, 'return_result', [1]);
			bulkDo($subNodes, 'cmd', ['config term']) or next LOOP;

			# Create the TUNI I-SID
			bulkDo($subNodes, 'cmd', ['spbm']) or next LOOP;	# Enable spbm, if it was not already set..
			bulkDo($subNodes, 'cmd', ["i-sid $isid elan-transparent"]) or next LOOP;
			foreach my $node (keys %$subNodes) {
				$subNodes->{$node}->cmd("port " . $nodePortHash->{$node});
			}
			pollComplete($subNodes);
			next LOOP unless reportCmdError($subNodes);
			bulkDo($subNodes, 'cmd', ['exit']) or next LOOP;

			# Bring up the ports (if they were down), take off LLDP, enable PoE
			foreach my $node (keys %$subNodes) {
				$subNodes->{$node}->cmd("interface gigabitEthernet " . $nodePortHash->{$node});
			}
			pollComplete($subNodes);
			next LOOP unless reportCmdError($subNodes);
			if ($lldpAction eq 'D') {
				bulkDo($subNodes, 'cmd', ['no lldp status']) or next LOOP;
			}
			else {
				bulkDo($subNodes, 'cmd', ['lldp status txAndRx']) or next LOOP;
			}
			bulkDo($subNodes, 'cmd', ['no shutdown']) or next LOOP;
			foreach my $node (keys %$subNodes) {
				next unless $muxHash->{switch}->{$node}->{poe};
				$subNodes->{$node}->cmd("no poe-shutdown");
			}
			pollComplete($subNodes);
			next LOOP unless reportCmdError($subNodes);
			bulkDo($subNodes, 'cmd', ['end']) or next LOOP;
			bulkDo($subNodes, 'cmd', ['save config']) or next LOOP;
			bulkDo($subNodes, 'return_result', [0]) or next LOOP;

			# Update muxHash data
			$muxHash->{isid}->{$isid} = \@portids;
			foreach my $portid (@portids) {
				$muxHash->{portid}->{$portid}->{isid} = $isid;
				$muxHash->{portid}->{$portid}->{lldp}->{state} = $lldpAction eq 'D' ? 'off' : 'on';
			}
			print " done!\n";

			# Update change versions
			incrementChangesCount($muxHash, $subNodes) or next LOOP;

			refreshPortStatus($muxHash, $cli) or next LOOP; # Refresh port status
			$key eq 'P' && do {
				page("\nAdded T-UNI point-point connection:\n", 1) or next LOOP;
				my $portid1 = $portids[0];
				my $portid2 = $portids[1];
				page(sprintf $InfoLine{point_point_connection},
					$isid,
					$muxHash->{portid}->{$portid1}->{name},
					$portid1,
					colourStatus($muxHash->{portid}->{$portid1}->{status}),
					$muxHash->{portid}->{$portid2}->{name},
					$portid2,
					colourStatus($muxHash->{portid}->{$portid2}->{status}),
				) or next LOOP;
			};
			$key eq 'M' && do {
				page("\nAdded T-UNI multi-point connection:\n", 1) or next LOOP;
				for my $i (0..$#portids) {
					my $portid = $portids[$i];
					page(sprintf $InfoLine{multi_point_connection1},
						$isid,
						$muxHash->{portid}->{$portid}->{name},
						$portid,
						colourStatus($muxHash->{portid}->{$portid}->{status}),
						colourStatus($muxHash->{portid}->{$portid}->{lldp}->{state}),
					) or next LOOP if $i == 0;
					page(sprintf $InfoLine{multi_point_connectionN},
						$muxHash->{portid}->{$portid}->{name},
						$portid,
						colourStatus($muxHash->{portid}->{$portid}->{status}),
						colourStatus($muxHash->{portid}->{$portid}->{lldp}->{state}),
					) or next LOOP if $i > 0;
				}
			};
			pause($DonePrompt);
			next LOOP;
		};
		$key eq 'B' && do { # Attach end-point to OOB network
			acquireMuxData($muxHash, $cli) or next LOOP; # Refresh data if needed
			print "\n($key) - Select end-point to connect to OOB network\n";
			my @portids = selectPorts($muxHash, 1, 0);
			next LOOP unless @portids;
			my $portid = $portids[0];
			my $portname = $muxHash->{portid}->{$portid}->{name};
			if (exists $muxHash->{portid}->{$portid}->{static}) {
				printf "Portid %s (%s) is a static port; it cannot be assigned to OOB\n", $portid, $portname;
				next LOOP;
			}
			my $node = $muxHash->{portid}->{$portid}->{switch};
			unless (exists $muxHash->{portid}->{$portid}->{poe}) {
				printf "Port %s (%s) is not a PoE powered device, hence most likely a switch.\n", $portid, $portname;
				print "Connecting a switch to the OOB network risks causing loops; are you SURE you want to proceed ? [Y/N]\n";
				my $key = readMenuKey('YN');
				next LOOP if $key eq 'N';
			}
			my $subNodes = {};
			$subNodes->{$node} = $cli->{$node};
			my $realPortid = mapVirtPortId($muxHash, $node, $portid);
			print "Configuring (1) node ";
			bulkDo($subNodes, 'return_result', [1]);
			bulkDo($subNodes, 'cmd', ['config term']) or next LOOP;
			bulkDo($subNodes, 'cmd', ["interface gigabitEthernet $realPortid"]) or next LOOP;
			# Ensure Spanning Tree is disabled (it should already)
			bulkDo($subNodes, 'cmd', ['no spanning-tree mstp']) or next LOOP;
			# Ensure Port is enabled (it should already)
			bulkDo($subNodes, 'cmd', ['no shutdown']) or next LOOP;
			bulkDo($subNodes, 'cmd', ['exit']) or next LOOP;
			# Simply add the OOB VLAN on the port..
			bulkDo($subNodes, 'cmd', ["vlan members add $OobVlan $realPortid"]) or next LOOP;
			bulkDo($subNodes, 'cmd', ['end']) or next LOOP;
			bulkDo($subNodes, 'cmd', ['save config']) or next LOOP;
			bulkDo($subNodes, 'return_result', [0]);

			# Update muxHash data
			$muxHash->{portid}->{$portid}->{vlan} = $OobVlan;
			print " done!\n";

			# Update change versions
			incrementChangesCount($muxHash, $subNodes) or next LOOP;

			refreshPortStatus($muxHash, $cli) or next LOOP; # Refresh port status
			page("\nAdded connection:\n", 1) or next LOOP;
			page(sprintf $InfoLine{oob_connection},
				$muxHash->{portid}->{$portid}->{vlan},
				$portname,
				$portid,
				colourStatus($muxHash->{portid}->{$portid}->{status}),
			) or next LOOP;
			pause($DonePrompt);
			next LOOP;
		};
		$key eq 'D' && do { # Delete existing patch connection
			acquireMuxData($muxHash, $cli) or next LOOP; # Refresh data if needed
			print "\n($key) - Enter end-point name or port of connection to delete\n";
			my @portids = selectPorts($muxHash, 1, 1);
			next LOOP unless @portids;
			my $portid = $portids[0];
			my $node = $muxHash->{portid}->{$portid}->{switch};

			if (exists $muxHash->{portid}->{$portid}->{isid}) { # T-UNI connection to delete
				my $isid = $muxHash->{portid}->{$portid}->{isid};
				# Get the other ports involved
				foreach my $isidPort (@{$muxHash->{isid}->{$isid}}) {
					next if $isidPort eq $portid;
					push(@portids, $isidPort);
				}
				# Prepare hash of nodes and related ports
				my $nodePortHash = {};
				foreach my $portid (@portids) {
					next if exists $muxHash->{portid}->{$portid}->{static};
					my $node = $muxHash->{portid}->{$portid}->{switch};
					push(@{$nodePortHash->{$node}}, mapVirtPortId($muxHash, $node, $portid));
				}
				# Get the switches CLI objects involved, and reformat port list to comma separated string
				my $subNodes = {};
				foreach my $node (keys %$nodePortHash) {
					$nodePortHash->{$node} = join(',', @{$nodePortHash->{$node}});
					$subNodes->{$node} = $cli->{$node};
				}
				printf "Configuring (%s) nodes ", scalar(keys %$subNodes);
				bulkDo($subNodes, 'return_result', [1]);
				bulkDo($subNodes, 'cmd', ['config term']) or next LOOP;
	
				# Delete the TUNI I-SID
				bulkDo($subNodes, 'cmd', ["no i-sid $isid"]) or next LOOP;
	
				# Re-enable LLDP so we can see what's connected
				foreach my $node (keys %$subNodes) {
					$subNodes->{$node}->cmd("interface gigabitEthernet " . $nodePortHash->{$node});
				}
				pollComplete($subNodes);
				next LOOP unless reportCmdError($subNodes);
				bulkDo($subNodes, 'cmd', ['no spanning-tree mstp']) or next LOOP;
				bulkDo($subNodes, 'cmd', ['no shutdown']) or next LOOP;
				foreach my $node (keys %$subNodes) {
					next unless $muxHash->{switch}->{$node}->{poe};
					$subNodes->{$node}->cmd("no poe-shutdown");
				}
				pollComplete($subNodes);
				next LOOP unless reportCmdError($subNodes);
				bulkDo($subNodes, 'cmd', ['lldp status txAndrx']) or next LOOP;
				bulkDo($subNodes, 'cmd', ['end']) or next LOOP;
				bulkDo($subNodes, 'cmd', ['save config']) or next LOOP;
				bulkDo($subNodes, 'return_result', [0]) or next LOOP;
				print " done!\n";

				# Update change versions
				incrementChangesCount($muxHash, $subNodes) or next LOOP;

				refreshPortStatus($muxHash, $cli) or next LOOP; # Refresh port status
				page("\nDeleted connection:\n", 1) or next LOOP;
				if (scalar @portids == 1) {
					my $portid = $portids[0];
					page(sprintf $InfoLine{orphaned_connection},
						$isid,
						$muxHash->{portid}->{$portid}->{name},
						$portid,
						colourStatus($muxHash->{portid}->{$portid}->{status}),
						colourStatus($muxHash->{portid}->{$portid}->{lldp}->{state}),
					) or next LOOP;
				}
				elsif (scalar @portids == 2) {
					my $portid1 = $portids[0];
					my $portid2 = $portids[1];
					page(sprintf $InfoLine{point_point_connection},
						$isid,
						$muxHash->{portid}->{$portid1}->{name},
						$portid1,
						colourStatus($muxHash->{portid}->{$portid1}->{status}),
						$muxHash->{portid}->{$portid2}->{name},
						$portid2,
						colourStatus($muxHash->{portid}->{$portid2}->{status}),
					) or next LOOP;
				}
				elsif (scalar @portids > 2) {
					for my $i (0..$#portids) {
						my $portid = $portids[$i];
						page(sprintf $InfoLine{multi_point_connection1},
							$isid,
							$muxHash->{portid}->{$portid}->{name},
							$portid,
							colourStatus($muxHash->{portid}->{$portid}->{status}),
							colourStatus($muxHash->{portid}->{$portid}->{lldp}->{state}),
						) or next LOOP if $i == 0;
						page(sprintf $InfoLine{multi_point_connectionN},
							$muxHash->{portid}->{$portid}->{name},
							$portid,
							colourStatus($muxHash->{portid}->{$portid}->{status}),
							colourStatus($muxHash->{portid}->{$portid}->{lldp}->{state}),
						) or next LOOP if $i > 0;
					}
				}

				# Update muxHash data - do it after so that we can use {lldp}->{state} above
				delete $muxHash->{isid}->{$isid};
				foreach my $portid (@portids) {
					delete $muxHash->{portid}->{$portid}->{isid};
					$muxHash->{portid}->{$portid}->{lldp}->{state} = 'on';
				}
			}
			elsif (exists $muxHash->{portid}->{$portid}->{vlan}) { # OOB connection to delete
				my $vlan = $muxHash->{portid}->{$portid}->{vlan};
				my $subNodes = {};
				$subNodes->{$node} = $cli->{$node};
				my $realPortid = mapVirtPortId($muxHash, $node, $portid);
				print "Configuring (1) node ";
				bulkDo($subNodes, 'return_result', [1]);
				bulkDo($subNodes, 'cmd', ['config term']) or next LOOP;
				# Simply delete the OOB VLAN on the port..
				bulkDo($subNodes, 'cmd', ["vlan members remove $vlan $realPortid"]) or next LOOP;
				bulkDo($subNodes, 'cmd', ['end']) or next LOOP;
				bulkDo($subNodes, 'cmd', ['save config']) or next LOOP;
				bulkDo($subNodes, 'return_result', [0]);

				# Update muxHash data
				delete $muxHash->{portid}->{$portid}->{vlan};
				print " done!\n";

				# Update change versions
				incrementChangesCount($muxHash, $subNodes) or next LOOP;

				page("\nDeleted connection:\n") or next LOOP;
				page(sprintf $InfoLine{oob_connection},
					$vlan,
					$muxHash->{portid}->{$portid}->{name},
					$portid,
					colourStatus($muxHash->{portid}->{$portid}->{status}),
				) or next LOOP;
			}
			pause($DonePrompt);
			next LOOP;
		};
		$key eq 'C' && do { # List established end-point connections
			acquireMuxData($muxHash, $cli) or next LOOP; # Refresh data if needed
			refreshPortStatus($muxHash, $cli) or next LOOP; # Refresh port status
			page("\n($key) - The following patch connections exist\n",1) or next LOOP;
			page("===========================================\n") or next LOOP;
			printConnections($muxHash) or next LOOP;
			pause($DonePrompt);
			next LOOP;
		};
		$key eq 'E' && do { # List available end-points
			acquireMuxData($muxHash, $cli) or next LOOP; # Refresh data if needed
			refreshPortStatus($muxHash, $cli) or next LOOP; # Refresh port status
			refreshLldpNeighbours($muxHash, $cli) or next LOOP; # Refresh LLDP neighbours
			page("\n($key) - The following end-points are available for connection\n",1) or next LOOP;
			page("===========================================================\n\n") or next LOOP;
			printEndPoints($muxHash) or next LOOP;
			pause($DonePrompt);
			next LOOP;
		};
		$key eq 'A' && do { # Add a new end-point
			acquireMuxData($muxHash, $cli) or next LOOP; # Refresh data if needed
			print "\n($key) - Enter new end-point port number: ";
			chomp(my $portid = <STDIN>);
			if (exists $muxHash->{portid}->{$portid}) {
				printf "Port %s is already configured for end-point '%s'\n", $portid, $muxHash->{portid}->{$portid}->{name};
				next LOOP;
			}
			unless (exists $muxHash->{unused}->{$portid}) {
				print "No matching port found\n";
				next LOOP;
			}
			print "Enter new end-point name (no spaces in name): ";
			chomp(my $portname = <STDIN>);
			if ($portname =~ /\s/) {
				print "Name must not contain spaces\n";
				next LOOP;
			}
			if (exists $muxHash->{portname}->{$portname}) {
				printf "Name '%s' has already been assigned to end-point on port %s\n", $portname, $muxHash->{portname}->{$portname};
				next LOOP;
			}
			my $node = $muxHash->{unused}->{$portid};
			my $subNodes = {};
			$subNodes->{$node} = $cli->{$node};
			my $realPortid = mapVirtPortId($muxHash, $node, $portid);
			print "Configuring (1) node ";
			bulkDo($subNodes, 'return_result', [1]);
			bulkDo($subNodes, 'cmd', ['config term']) or next LOOP;
			bulkDo($subNodes, 'cmd', ["vlan members remove 1 $realPortid"]) or next LOOP;
			bulkDo($subNodes, 'cmd', ["interface gigabitEthernet $realPortid"]) or next LOOP;
			bulkDo($subNodes, 'cmd', ["name \"$portname\""]) or next LOOP;
			bulkDo($subNodes, 'cmd', ['lldp status txAndrx']) or next LOOP;
			bulkDo($subNodes, 'cmd', ['no spanning-tree mstp']) or next LOOP;
			bulkDo($subNodes, 'cmd', ['no shutdown']) or next LOOP;
			bulkDo($subNodes, 'cmd', ['end']) or next LOOP;
			bulkDo($subNodes, 'cmd', ['save config']) or next LOOP;
			bulkDo($subNodes, 'return_result', [0]);

			# Update muxHash data
			delete $muxHash->{unused}->{$portid};
			$muxHash->{portid}->{$portid}->{name} = $portname;
			$muxHash->{portid}->{$portid}->{switch} = $node;
			$muxHash->{portname}->{$portname} = $portid;
			print " done!\n";

			# Update change versions
			incrementChangesCount($muxHash, $subNodes) or next LOOP;

			refreshPortStatus($muxHash, $subNodes) or next LOOP; # Refresh port status
			page("\nAdded end-point:\n", 1) or next LOOP;
			page(sprintf $InfoLine{endpoint_free_no_lldp},
				$portid,
				$muxHash->{portid}->{$portid}->{name},
				colourStatus($muxHash->{portid}->{$portid}->{status}),
				colourStatus(poePortStatus($muxHash, $portid)),
			) or next LOOP;
			pause($DonePrompt);
			next LOOP;
		};
		$key eq 'R' && do { # Remove an end-point
			acquireMuxData($muxHash, $cli) or next LOOP; # Refresh data if needed
			print "\n($key) - Enter end-point name or port to remove";
			my @portids = selectPorts($muxHash, 1, 0);
			next LOOP unless @portids;
			my $portid = $portids[0];
			my $portname = $muxHash->{portid}->{$portid}->{name};
			if (exists $muxHash->{portid}->{$portid}->{static}) {
				printf "Portid %s (%s) is a static port; it cannot be removed\n", $portid, $portname;
				next LOOP;
			}
			my $node = $muxHash->{portid}->{$portid}->{switch};
			my $subNodes = {};
			$subNodes->{$node} = $cli->{$node};
			my $realPortid = mapVirtPortId($muxHash, $node, $portid);
			print "Configuring (1) node ";
			bulkDo($subNodes, 'return_result', [1]);
			bulkDo($subNodes, 'cmd', ['config term']) or next LOOP;
			bulkDo($subNodes, 'cmd', ["interface gigabitEthernet $realPortid"]) or next LOOP;
			bulkDo($subNodes, 'cmd', ['shutdown']) or next LOOP;
			bulkDo($subNodes, 'cmd', ['no name']) or next LOOP;
			bulkDo($subNodes, 'cmd', ['no lldp status']) or next LOOP;
			bulkDo($subNodes, 'cmd', ['end']) or next LOOP;
			bulkDo($subNodes, 'cmd', ['save config']) or next LOOP;
			bulkDo($subNodes, 'return_result', [0]);

			# Update muxHash data
			delete $muxHash->{portid}->{$portid};
			delete $muxHash->{portname}->{$portname};
			$muxHash->{unused}->{$portid} = $node;
			print " done!\n";

			# Update change versions
			incrementChangesCount($muxHash, $subNodes) or next LOOP;

			page("\nRemoved end-point:\n", 1) or next LOOP;
			page(sprintf $InfoLine{endpoint_free_no_status},
				$portid,
				$portname
			) or next LOOP;
			pause($DonePrompt);
			next LOOP;
		};
		$key eq 'S' && do { # Search an end-point
			acquireMuxData($muxHash, $cli) or next LOOP; # Refresh data if needed
			print "\n($key) - Enter end-point name or port to search: ";
			chomp(my $search = <STDIN>);
			next LOOP unless $search;
			refreshPortStatus($muxHash, $cli) or next LOOP; # Refresh port status
			refreshLldpNeighbours($muxHash, $cli) or next LOOP; # Refresh LLDP neighbours
			page("Matching connections\n",1) or next LOOP;
			page("====================\n") or next LOOP;
			my $matchPortids = searchEndPoint($muxHash, $search);
			printConnections($muxHash, $matchPortids) or next LOOP;;

			page("\nMatching end-points\n") or next LOOP;
			page("===================\n") or next LOOP;
			printEndPoints($muxHash, $matchPortids) or next LOOP;
			pause($DonePrompt);
			next LOOP;
		};
		$key eq 'N' && do { # Show mirroring ports
			acquireMirroringData($muxHash, $cli) or next LOOP; # Refresh mirroring data
			refreshPortStatus($muxHash, $cli) or next LOOP; # Refresh port status
			page("\n($key) - Mirroring ports\n",1) or next LOOP;
			page("=====================\n") or next LOOP;
			my $sectionStarted;
			foreach my $isid (sort { $a <=> $b } keys %{$muxHash->{mirror}->{isid}}) {
				next unless exists $muxHash->{mirror}->{isid}->{$isid}->{mirror}
					|| exists $muxHash->{mirror}->{isid}->{$isid}->{monitor};
				page("\nFabric RSPAN mirrors:\n") or next LOOP unless $sectionStarted++;
				my $i = 0;
				my $row = [];
				foreach my $portid (sort by_slotPort keys %{$muxHash->{mirror}->{isid}->{$isid}->{mirror}}) {
					$row->[$i++]->{in} = $portid;
				}
				$i = 0;
				foreach my $portid (sort by_slotPort keys %{$muxHash->{mirror}->{isid}->{$isid}->{monitor}}) {
					$row->[$i++]->{out} = $portid;
				}
				for my $i (0..$#$row) {
					if (exists $row->[$i]->{in} && exists $row->[$i]->{out}) {
						page(sprintf $InfoLine{mirror_in_and_out_line1},
							$muxHash->{portid}->{$row->[$i]->{in}}->{name},
							$row->[$i]->{in},
							colourStatus($muxHash->{portid}->{$row->[$i]->{in}}->{status}),
							colourStatus($muxHash->{mirror}->{isid}->{$isid}->{mirror}->{$row->[$i]->{in}}->{mode}),
							colourStatus($muxHash->{mirror}->{isid}->{$isid}->{mirror}->{$row->[$i]->{in}}->{enabled}),
							$isid,
							$muxHash->{portid}->{$row->[$i]->{out}}->{name},
							$row->[$i]->{out},
							colourStatus($muxHash->{portid}->{$row->[$i]->{out}}->{status}),
							colourStatus($muxHash->{mirror}->{isid}->{$isid}->{monitor}->{$row->[$i]->{out}}->{enabled}),
						) or next LOOP if $i == 0;
						page(sprintf $InfoLine{mirror_in_and_out_lineN},
							$muxHash->{portid}->{$row->[$i]->{in}}->{name},
							$row->[$i]->{in},
							colourStatus($muxHash->{portid}->{$row->[$i]->{in}}->{status}),
							colourStatus($muxHash->{mirror}->{isid}->{$isid}->{mirror}->{$row->[$i]->{in}}->{mode}),
							colourStatus($muxHash->{mirror}->{isid}->{$isid}->{mirror}->{$row->[$i]->{in}}->{enabled}),
							$isid,
							$muxHash->{portid}->{$row->[$i]->{out}}->{name},
							$row->[$i]->{out},
							colourStatus($muxHash->{portid}->{$row->[$i]->{out}}->{status}),
							colourStatus($muxHash->{mirror}->{isid}->{$isid}->{monitor}->{$row->[$i]->{out}}->{enabled}),
						) or next LOOP if $i > 0;
					}
					elsif (exists $row->[$i]->{in}) {
						page(sprintf $InfoLine{mirror_in_only_line1},
							$muxHash->{portid}->{$row->[$i]->{in}}->{name},
							$row->[$i]->{in},
							colourStatus($muxHash->{portid}->{$row->[$i]->{in}}->{status}),
							colourStatus($muxHash->{mirror}->{isid}->{$isid}->{mirror}->{$row->[$i]->{in}}->{mode}),
							colourStatus($muxHash->{mirror}->{isid}->{$isid}->{mirror}->{$row->[$i]->{in}}->{enabled}),
							$isid,
						) or next LOOP if $i == 0;
						page(sprintf $InfoLine{mirror_in_only_lineN},
							$muxHash->{portid}->{$row->[$i]->{in}}->{name},
							$row->[$i]->{in},
							colourStatus($muxHash->{portid}->{$row->[$i]->{in}}->{status}),
							colourStatus($muxHash->{mirror}->{isid}->{$isid}->{mirror}->{$row->[$i]->{in}}->{mode}),
							colourStatus($muxHash->{mirror}->{isid}->{$isid}->{mirror}->{$row->[$i]->{in}}->{enabled}),
						) or next LOOP if $i > 0;
					}
					elsif (exists $row->[$i]->{out}) {
						page(sprintf $InfoLine{mirror_out_only_line1},
							$isid,
							$muxHash->{portid}->{$row->[$i]->{out}}->{name},
							$row->[$i]->{out},
							colourStatus($muxHash->{portid}->{$row->[$i]->{out}}->{status}),
							colourStatus($muxHash->{mirror}->{isid}->{$isid}->{monitor}->{$row->[$i]->{out}}->{enabled}),
						) or next LOOP if $i == 0;
						page(sprintf $InfoLine{mirror_out_only_lineN},
							$muxHash->{portid}->{$row->[$i]->{out}}->{name},
							$row->[$i]->{out},
							colourStatus($muxHash->{portid}->{$row->[$i]->{out}}->{status}),
							colourStatus($muxHash->{mirror}->{isid}->{$isid}->{monitor}->{$row->[$i]->{out}}->{enabled}),
						) or next LOOP if $i > 0;
					}
					$i++;
				}
				page("\n") or next LOOP;
			}
			undef $sectionStarted;
			foreach my $node (sort { $a cmp $b } keys %{$muxHash->{mirror}->{switch}}) {
				next unless exists $muxHash->{mirror}->{switch}->{$node}->{mirror}
					|| exists $muxHash->{mirror}->{switch}->{$node}->{monitor};
				page("\nLocal port mirrors:\n") or next LOOP unless $sectionStarted++;
				my $i = 0;
				my $row = [];
				foreach my $portid (sort by_slotPort keys %{$muxHash->{mirror}->{switch}->{$node}->{mirror}}) {
					$row->[$i++]->{in} = $portid;
				}
				$i = 0;
				foreach my $portid (sort by_slotPort keys %{$muxHash->{mirror}->{switch}->{$node}->{monitor}}) {
					$row->[$i++]->{out} = $portid;
				}
				for my $i (0..$#$row) {
					if (exists $row->[$i]->{in} && exists $row->[$i]->{out}) {
						page(sprintf $InfoLine{mirror_in_and_out_line1},
							$muxHash->{portid}->{$row->[$i]->{in}}->{name},
							$row->[$i]->{in},
							colourStatus($muxHash->{portid}->{$row->[$i]->{in}}->{status}),
							colourStatus($muxHash->{mirror}->{switch}->{$node}->{mirror}->{$row->[$i]->{in}}->{mode}),
							colourStatus($muxHash->{mirror}->{switch}->{$node}->{mirror}->{$row->[$i]->{in}}->{enabled}),
							'Unit' . $muxHash->{switch}->{$node}->{unitid},
							$muxHash->{portid}->{$row->[$i]->{out}}->{name},
							$row->[$i]->{out},
							colourStatus($muxHash->{portid}->{$row->[$i]->{out}}->{status}),
							'',
						) or next LOOP if $i == 0;
						page(sprintf $InfoLine{mirror_in_and_out_lineN},
							$muxHash->{portid}->{$row->[$i]->{in}}->{name},
							$row->[$i]->{in},
							colourStatus($muxHash->{portid}->{$row->[$i]->{in}}->{status}),
							colourStatus($muxHash->{mirror}->{switch}->{$node}->{mirror}->{$row->[$i]->{in}}->{mode}),
							colourStatus($muxHash->{mirror}->{switch}->{$node}->{mirror}->{$row->[$i]->{in}}->{enabled}),
							'Unit' . $muxHash->{switch}->{$node}->{unitid},
							$muxHash->{portid}->{$row->[$i]->{out}}->{name},
							$row->[$i]->{out},
							colourStatus($muxHash->{portid}->{$row->[$i]->{out}}->{status}),
							'',
						) or next LOOP if $i > 0;
					}
					elsif (exists $row->[$i]->{in}) {
						page(sprintf $InfoLine{mirror_in_only_lineN},
							$muxHash->{portid}->{$row->[$i]->{in}}->{name},
							$row->[$i]->{in},
							colourStatus($muxHash->{portid}->{$row->[$i]->{in}}->{status}),
							colourStatus($muxHash->{mirror}->{switch}->{$node}->{mirror}->{$row->[$i]->{in}}->{mode}),
							colourStatus($muxHash->{mirror}->{switch}->{$node}->{mirror}->{$row->[$i]->{in}}->{enabled}),
						) or next LOOP;
					}
					elsif (exists $row->[$i]->{out}) {
						page(sprintf $InfoLine{mirror_out_only_lineN},
							$muxHash->{portid}->{$row->[$i]->{out}}->{name},
							$row->[$i]->{out},
							colourStatus($muxHash->{portid}->{$row->[$i]->{out}}->{status}),
							colourStatus($muxHash->{mirror}->{switch}->{$node}->{monitor}->{$row->[$i]->{out}}->{enabled}),
						) or next LOOP;
					}
					$i++;
				}
				page("\n") or next LOOP;
			}
			pause($DonePrompt);
			next LOOP;
		};
		$key eq 'L' && do { # Enable/Disable LLDP on unused end-points
			acquireMuxData($muxHash, $cli) or next LOOP; # Refresh data if needed
			print "\n($key) - (E) Enable or (D) Disable LLDP on unused end-points (E/D/Q) ?\n";
			my $lldpAction = readMenuKey('EDQ');
			if ($lldpAction eq 'D') {
				page("Disabling LLDP on all unused end-points\n",1) or next LOOP;
			}
			elsif ($lldpAction eq 'E') {
				page("Enabling LLDP on all unused end-points\n",1) or next LOOP;
			}
			else {
				next LOOP; #'Q'
			}
			my $nodePortHash = {};
			my @portids;
			foreach my $portid (sort by_slotPort keys %{$muxHash->{portid}}) {
				next if exists $muxHash->{portid}->{$portid}->{isid};
				next if exists $muxHash->{portid}->{$portid}->{vlan};
				next if exists $muxHash->{portid}->{$portid}->{static};
				my $node = $muxHash->{portid}->{$portid}->{switch};
				push(@{$nodePortHash->{$node}}, mapVirtPortId($muxHash, $node, $portid));
				push(@portids, $portid);
			}
			# Get the switches CLI objects involved, and reformat port list to comma separated string
			my $subNodes = {};
			foreach my $node (keys %$nodePortHash) {
				$nodePortHash->{$node} = join(',', @{$nodePortHash->{$node}});
				$subNodes->{$node} = $cli->{$node};
				debugMsg(1, "Enable LLDP on $node ports: ", \$nodePortHash->{$node}, "\n");
			}
			printf "Configuring (%s) nodes ", scalar(keys %$subNodes);
			bulkDo($subNodes, 'return_result', [1]);
			bulkDo($subNodes, 'cmd', ['config term']) or next LOOP;
			# Enable or Disable LLDP
			foreach my $node (keys %$subNodes) {
				$subNodes->{$node}->cmd("interface gigabitEthernet " . $nodePortHash->{$node});
			}
			pollComplete($subNodes);
			next LOOP unless reportCmdError($subNodes);
			if ($lldpAction eq 'D') {
				bulkDo($subNodes, 'cmd', ['no lldp status']) or next LOOP;
			}
			else {
				bulkDo($subNodes, 'cmd', ['lldp status txAndRx']) or next LOOP;
			}
			bulkDo($subNodes, 'cmd', ['save config']) or next LOOP;
			bulkDo($subNodes, 'return_result', [0]) or next LOOP;

			# Update muxHash data
			foreach my $portid (@portids) {
				$muxHash->{portid}->{$portid}->{lldp}->{state} = $lldpAction eq 'D' ? 'off' : 'on';
			}
			print " done!\n";

			# Update change versions
			incrementChangesCount($muxHash, $subNodes) or next LOOP;

			pause($DonePrompt);
			next LOOP;
		};
		$key eq 'O' && do { # Enable/Disable/Bounce POE on end-points
			acquireMuxData($muxHash, $cli) or next LOOP; # Refresh data if needed
			print "\n($key) - Enter end-point name or port to enable/disable/bounce POE on";
			my @portids = selectPorts($muxHash, 1);
			next LOOP unless @portids;
			my $portid = $portids[0];
			my $portname = $muxHash->{portid}->{$portid}->{name};
			unless (exists $muxHash->{portid}->{$portid}->{poe}) {
				printf "Portid %s (%s) is not using POE\n", $portid, $portname;
				next LOOP;
			}
			print "\n (E) Enable or (D) Disable or (B) Bounce POE (E/D/B/Q) ?\n";
			my $poeAction = readMenuKey('EDBQ');
			if ($poeAction eq 'D') {
				page("Disabling POE on end-point\n",1) or next LOOP;
			}
			elsif ($poeAction eq 'E') {
				page("Enabling POE on end-point\n",1) or next LOOP;
			}
			elsif ($poeAction eq 'B') {
				page("Bouncing POE on end-point\n",1) or next LOOP;
			}
			else { # 'Q'
				next LOOP;
			}
			my $node = $muxHash->{portid}->{$portid}->{switch};
			my $subNodes = {};
			$subNodes->{$node} = $cli->{$node};
			my $realPortid = mapVirtPortId($muxHash, $node, $portid);
			print "Configuring (1) node ";
			bulkDo($subNodes, 'return_result', [1]);
			bulkDo($subNodes, 'cmd', ['config term']) or next LOOP;
			bulkDo($subNodes, 'cmd', ["interface gigabitEthernet $realPortid"]) or next LOOP;
			if ($poeAction eq 'D') {
				bulkDo($subNodes, 'cmd', ['poe poe-shutdown']) or next LOOP;
			}
			elsif ($poeAction eq 'E') {
				bulkDo($subNodes, 'cmd', ['no poe-shutdown']) or next LOOP;
			}
			elsif ($poeAction eq 'B') {
				bulkDo($subNodes, 'cmd', ['poe poe-shutdown']) or next LOOP;
				sleep 1;
				bulkDo($subNodes, 'cmd', ['no poe-shutdown']) or next LOOP;
			}
			bulkDo($subNodes, 'cmd', ['end']) or next LOOP;
			bulkDo($subNodes, 'cmd', ['save config']) or next LOOP;
			bulkDo($subNodes, 'return_result', [0]);

			# Update muxHash data
			$muxHash->{portid}->{$portid}->{poe}->{state} = $poeAction eq 'D' ? 'off' : 'on';
			print " done!\n";

			# Update change versions
			incrementChangesCount($muxHash, $subNodes) or next LOOP;

			pause($DonePrompt);
			next LOOP;
		};
		$key eq 'Z' && do { # Sanitize configuration
			acquireMuxData($muxHash, $cli) or next LOOP; # Refresh data if needed

			# Check all T-UNI point-point connections and see if any have LLDP enabled
			print "\nChecking T-UNI point-point connections for LLDP enabled endpoints\n";
			my $nodePortHash = {};
			my @portids;
			foreach my $isid (sort { $a <=> $b } keys %{$muxHash->{isid}}) {
				next unless scalar @{$muxHash->{isid}->{$isid}} == 2;
				for my $i (0..$#{$muxHash->{isid}->{$isid}}) {
					my $portid = $muxHash->{isid}->{$isid}->[$i];
					if ($muxHash->{portid}->{$portid}->{lldp}->{state} eq 'on') {
						printf " - I-SID %s point-point T-UNI port %s (%s) has LLDP on!\n", $isid, $portid, $muxHash->{portid}->{$portid}->{name};
						my $node = $muxHash->{portid}->{$portid}->{switch};
						push(@{$nodePortHash->{$node}}, mapVirtPortId($muxHash, $node, $portid));
						push(@portids, $portid);
					}
				}
			}
			if (%$nodePortHash) { # If any found
				print "Disable LLDP on above ports (Y/N) ?\n";
				if (readMenuKey('YN') eq 'Y') {
					# Get the switches CLI objects involved, and reformat port list to comma separated string
					my $subNodes = {};
					foreach my $node (keys %$nodePortHash) {
						$nodePortHash->{$node} = join(',', @{$nodePortHash->{$node}});
						$subNodes->{$node} = $cli->{$node};
					}
					printf "Configuring (%s) nodes ", scalar(keys %$subNodes);
					bulkDo($subNodes, 'return_result', [1]);
					bulkDo($subNodes, 'cmd', ['config term']) or next LOOP;
					foreach my $node (keys %$subNodes) {
						$subNodes->{$node}->cmd("interface gigabitEthernet " . $nodePortHash->{$node});
					}
					pollComplete($subNodes);
					next LOOP unless reportCmdError($subNodes);
					bulkDo($subNodes, 'cmd', ['no lldp status']) or next LOOP;
					bulkDo($subNodes, 'cmd', ['end']) or next LOOP;
					bulkDo($subNodes, 'cmd', ['save config']) or next LOOP;
					bulkDo($subNodes, 'return_result', [0]) or next LOOP;
					# Update muxHash data
					foreach my $portid (@portids) {
						$muxHash->{portid}->{$portid}->{lldp}->{state} = 'off';
					}
					print " done!\n";
					# Update change versions
					incrementChangesCount($muxHash, $subNodes) or next LOOP;
				}
			}
			pause($DonePrompt);
			next LOOP;
		};
		$key eq 'W' && do { # Dump data structure
			printf "\n($key) - Optional path and/or filename to use [default = %s]: ", File::Spec->rel2abs(cwd . '/' . $TuniMxDump);
			chomp(my $path = <STDIN>);
			$path = File::Spec->rel2abs(cwd . '/' . $TuniMxDump) unless $path;
			open(DUMP, '>', $path) or do {
				print "Unable to open file $path : $!\n";
				next LOOP;
			};
			print DUMP Dumper($muxHash);
			close DUMP;
			print "Saved dump in: $path\n";
			pause($DonePrompt);
			next LOOP;
		};
		$key eq 'Q' && do { # Quit
			$mainloop = 0;
		};
	}

	# Disconnect from all switches
	relinquishAll($cli);
}
