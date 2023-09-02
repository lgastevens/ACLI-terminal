#!/usr/local/bin/perl

my $Version = "1.4";

#############################
# STANDARD MODULES          #
#############################

use strict;
use warnings;
use File::Basename;
use Getopt::Std;
use Control::CLI::AvayaData qw(poll :prompt);	# Export class poll method

#############################
# VARIABLES                 #
#############################

my $Debug = 0;
my $ScriptName = basename($0);
my %Cfm = ( # [0] non-ACLI syntax; [1] ACLI syntax 
	ping		=> ['l2ping %s.%s', 'l2 ping vlan %s routernodename %s'],
	tracert		=> ['l2traceroute %s.%s', 'l2 traceroute vlan %s routernodename %s'],
);
our $opt_d;


#############################
# FUNCTIONS                 #
#############################

sub printSyntax {
	printf "%s version %s%s\n\n", $ScriptName, $Version, ($Debug ? " running on $^O perl version $]" : "");
	print "Usage:\n";
	print " $ScriptName <ssh|telnet> <[username[:password]@]seed-IP> <ping|tracert>\n\n";
	exit 1;
}

sub quit {
	my ($retval, $quitmsg) = @_;
	print "\n$ScriptName: ", $quitmsg, "\n" if $quitmsg;
	# Clean up and exit
	exit $retval;
}

sub debugMsg {
	if ($Debug) {
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

sub hostError { # Prepend hostname before error its cli object generated
	my ($host, $errmsg) = @_;
	die "\n$host -> $errmsg"; 
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

sub pollComplete {
	my $cli = shift;
	my ($running, $completed, $failed, $lastCompleted, $lastFailed);
	my @failedList;

	do {
		($running, $completed, $failed, $lastCompleted, $lastFailed) = poll(
			Object_list	=> $cli,
			Object_complete	=> 'next',
			Object_error	=> 'return',
			Poll_code	=> \&printDots,
	       		Errmode		=> 'return',	# Always return on error
		);
		print "\n - Have completed : ", join(',', @$lastCompleted) if @$lastCompleted;
		if (@$lastFailed) {
			print "\n - Have failed    : ", join(',', @$lastFailed);
			foreach my $key (@$lastFailed) {
				print "\n	 $key	: ", $cli->{$key}->errmsg;
				delete $cli->{$key};	# Don't bother with it anymore..
				push(@failedList, $key);
			}
		}
		print "\n - Summary        : Still running = $running ; Completed = $completed ; Failed = $failed\n";
	} while $running;

	return @failedList;
}

sub bulkDo { # Repeat for all hosts
	my ($cli, $method, $argsRef) = @_;

	foreach my $host (keys %$cli) { # Call $method for every object
		my $codeRef = $cli->{$host}->can($method);
		$codeRef->($cli->{$host}, @$argsRef);
	}
	pollComplete($cli);

	if ($method =~ /^cmd/) { # Check that command was accepted
		foreach my $host (keys %$cli) {
			unless ($cli->{$host}->last_cmd_success) {
				print "\n- $host error:\n", $cli->{$host}->last_cmd_errmsg, "\n\n";
			}
		}
	}
}

sub fabricSeedAcquire {
	my ($input, $cli, $fabricHash) = @_;
	my $output;

	# Create seed CLI object
	my $seedCli = new Control::CLI::AvayaData(
			Use			=> $input->{use},
			Blocking		=> 0,
			Prompt_credentials	=> [\&promptCredentials, 'Seed'],
			Errmode			=> [\&hostError, $input->{seed}],
	);

	# Connect
	print "Connecting to seed ", $input->{seed}, " ";
	$seedCli->connect(
			Host            => $input->{seed},
			Username        => $input->{username},
			Password        => $input->{password},
	);
	$seedCli->poll(	Poll_code => \&printDots );
	print " done!\n";

	# Check we are connected inband
	print "Acquiring Fabric nodes ";
	$seedCli->attribute('is_oob_connected');
	$seedCli->poll(	Poll_code => \&printDots );
	quit(1, "Out-of-Band connection! This script needs to connect inband!") if ($seedCli->attribute_poll)[1];

	# Cache credentials if they were not provided on command line
	$input->{username} = $seedCli->username unless $input->{username};
	$input->{password} = $seedCli->password unless $input->{password};

	# Enable PrivExec mode
	$seedCli->enable;
	$seedCli->poll(	Poll_code => \&printDots );

	# Record ACLI mode
	my $seedAcli = $seedCli->attribute('is_acli');

	# Retrieve ISIS sysname of seed
	$seedCli->device_more_paging(0);
	$seedCli->poll(	Poll_code => \&printDots );
	$seedCli->cmd('show isis' . ($seedAcli ? '':' info'));
	$seedCli->poll(	Poll_code => \&printDots );
	$output = ($seedCli->cmd_poll)[1];
	quit(1, "Unable to read seed's ISIS system name") unless $output =~ /^\s+Router Name : (.+)$/m;
	$input->{seedName} = $1;
	# Store seed node into data structures
	$cli->{$input->{seedName}} = $seedCli;
	$fabricHash->{$input->{seedName}}->{acli} = $seedAcli;
	$fabricHash->{$input->{seedName}}->{ip} = $input->{seed};

	# Retrieve BVLANs
	$seedCli->cmd('show isis spbm' . ($seedAcli ? '':' info'));
	$seedCli->poll(	Poll_code => \&printDots );
	$output = ($seedCli->cmd_poll)[1];
	quit(1, "Unable to read BVLANs") unless $output =~ /^\d+\s+(\d+)-(\d+)\s+\d+\s+[0-9a-z]\.[0-9a-z]{2}\.[0-9a-z]{2}/m;
	$input->{bvlans} = [$1, $2];

	# Retrieve all node names in the fabric
	$seedCli->cmd('show isis spbm nick-name');
	$seedCli->poll(	Poll_code => \&printDots );
	$output = ($seedCli->cmd_poll)[1];
	while ($output =~ /^[0-9a-f\.\-]+\s+\d+\s+[0-9a-f\.]+\s+(?:[0-9a-f:]+\s+)?(\S+)\s*$/mg) {
		next if $1 eq $input->{seedName};
		$fabricHash->{$1} = {};
	}

	# Retrieve all IP address for L3 BEB nodes
	$seedCli->cmd('show isis lsdb tlv 135 detail');
	$seedCli->poll(	Poll_code => \&printDots );
	$output = ($seedCli->cmd_poll)[1];
	my @tlvs = split('Host_name: ', $output);
	shift @tlvs;	# First record is just the banner
	foreach my $tlv (@tlvs) {
		$tlv =~ s/^(.+)//;
		my $sysName = $1;
		die "Unexpected ISIS node '$sysName' in LSDB" unless exists $fabricHash->{$sysName};
		next if $sysName eq $input->{seedName};
		$tlv =~ /IP Address: (\d+\.\d+\.\d+\.\d+)/;
		$fabricHash->{$sysName}->{ip} = $1;
	}
	print " done!\n";

	debugMsg("\nDiscovered Fabric nodes:\n");
	foreach my $node (sort {$a cmp $b} keys %$fabricHash) {
		debugMsg(" - $node : " . (defined $fabricHash->{$node}->{ip} ? $fabricHash->{$node}->{ip} : 'L2 BEB') . "\n");
	}
}

sub fabricTopologyAcquire {
	my ($input, $cli, $fabricHash) = @_;
	my (%tdppull, $subNodes, $firstRun, $loopFlag, @failedList);

	do {
		$loopFlag = 0;	# Assume we will not loop

		# Create CLI objects for all nodes
		print "\nConnecting to all Fabric nodes\n" unless $firstRun;
		print "\nConnecting to additional Fabric nodes\n" if $firstRun;
		print "=====================================\n";
		foreach my $node (sort {$a cmp $b} keys %$fabricHash) {
			next if defined $cli->{$node};	# Object already exists
			next unless defined $fabricHash->{$node}->{ip}; # if we don't have an IP yet
			$cli->{$node} = new Control::CLI::AvayaData(
				Use			=> $input->{use},
				Blocking		=> 0,
				Prompt_credentials	=> [\&promptCredentials, $node],
				Errmode			=> [\&hostError, $node],
			);
		}
	
		# Connect to all nodes for which we have a CLI object created
		$subNodes = {}; # Clear it
		foreach my $node (keys %$cli) {
			next if $cli->{$node}->connected; # Already connected
			$subNodes->{$node} = $cli->{$node};
			$cli->{$node}->connect(
				Host		=> $fabricHash->{$node}->{ip},
				Username	=> $input->{username},
				Password	=> $input->{password},
			);
		}
		@failedList = pollComplete($subNodes);
		foreach my $node (@failedList) { # If we failed to connect to some subnodes..
			delete $cli->{$node}; # Delete the object
		}
	
		# Enable PrivExec mode
		print "\nAcquiring Fabric topology\n" unless $firstRun;
		print "\nAcquiring additional Fabric topology\n" if $firstRun;
		print "====================================\n";
		bulkDo($subNodes, 'enable');

		# Record ACLI mode
		foreach my $node (keys %$subNodes) {
			$fabricHash->{$node}->{acli} = $cli->{$node}->attribute('is_acli');
		}

		# Now add seed into 1st batch of nodes to poll
		unless ($firstRun) {
			$subNodes->{$input->{seedName}} = $cli->{$input->{seedName}};
			$firstRun = 1;
		}
	
		# Dump ISIS adjacencies
		bulkDo($subNodes, 'cmd', ['show isis adjacencies']);
		%tdppull = ();
		foreach my $node (keys %$subNodes) {
			my $output = ($cli->{$node}->cmd_poll)[1];
			debugMsg("\n\n$node neighbors");
			while ($output =~ /^(\S+?(?:: [\d\/]+)?)\s+1 UP\s+(?:\S+)? \d\d:\d\d:\d\d \d+\s+\d+ [0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4}\s+(\S+)\s*$/mg) {
				my ($if, $neighbour) = ($1, $2);
				$fabricHash->{$node}->{neighbours}->{$neighbour} = 1;
				debugMsg(" :${if}-$neighbour");
				if (!defined $fabricHash->{$neighbour}->{ip} && $if =~ /^(Port|Mlt|Port: |Trunk: )(\d+$|\d+\/\d+(?:\/\d+)?$)/) {
					my ($iftype, $number) = ($1, $2);
					$iftype =~ s/: $//;
					$iftype =~ s/Trunk/Mlt/;
					$iftype = lc($iftype);
					debugMsg("[$iftype,$number]");
					push(@{$tdppull{$node}{$iftype}}, [$number, $neighbour]);
				}
			}
		}
	
		# Dump MLT tables if we recorded an MLT interface towards a neighbour for which we have no IP yet
		$subNodes = {}; # Clear it
		foreach my $node (keys %tdppull) {
			if ($tdppull{$node}{'mlt'}) {
				$subNodes->{$node} = $cli->{$node};
				$cli->{$node}->cmd('show mlt' . ($fabricHash->{$node}->{acli} ? '':' info'));
			}
		}
		if (%$subNodes) {
			debugMsg("\n\nMLT to Port conversion on nodes:");
			pollComplete($subNodes);
			foreach my $node (keys %$subNodes) {
				debugMsg("\n- $node mlts:");
				my $output = ($cli->{$node}->cmd_poll)[1];
				foreach my $neigh (@{$tdppull{$node}{'mlt'}}) {
					my ($mlt, $neighbour) = ($neigh->[0], $neigh->[1]);
					debugMsg(" $mlt->");
					(  $output =~ /^$mlt \d+  .+?(?:trunk|access)\s+(?:norm|smlt|ist)\s+(?:norm|smlt|ist)\s+([\d,-\/]+)\s/m
					|| $output =~ /^$mlt   .+?\s+([\d,-\/]+)\s+(?:All|Single)\s/m) && do {
						foreach my $port (split(/[,\-]/, $1)) {
							push(@{$tdppull{$node}{'port'}}, [$port, $neighbour]);
							debugMsg($port);
						}
					};
				}
				delete $tdppull{$node}{'mlt'}; # We converted them to ports
			}
			debugMsg("\n");
		}
	
		# Dump topology table for nodes which have neighbour for which we have no IP yet
		$subNodes = {}; # Clear it
		foreach my $node (keys %tdppull) {
			$subNodes->{$node} = $cli->{$node};
			$cli->{$node}->cmd($fabricHash->{$node}->{acli} ? 'show autotopology nmm-table' : 'show sys topology');
		}
		pollComplete($subNodes);
		debugMsg("\n\nTDP table pull on nodes:");
		foreach my $node (keys %$subNodes) {
			debugMsg("\n- $node port:");
			my $output = ($cli->{$node}->cmd_poll)[1];
			foreach my $neigh (@{$tdppull{$node}{'port'}}) {
				my ($port, $neighbour) = ($neigh->[0], $neigh->[1]);
				debugMsg(" $port->");
				next if defined $fabricHash->{$neighbour}->{ip}; # Skip if we have it set already
				$output =~ /^\s*(?:1\/)?$port\s+(\d+\.\d+\.\d+\.\d+)\s/m && do {
					$fabricHash->{$neighbour}->{ip} = $1;
					debugMsg($1);
					$loopFlag = 1; # Force a loop as we have learnt a new IP
				};
			}
		}
	
		debugMsg("\nDiscovered Fabric nodes:\n");
		foreach my $node (sort {$a cmp $b} keys %$fabricHash) {
			debugMsg(" - $node : " . (defined $fabricHash->{$node}->{ip} ? $fabricHash->{$node}->{ip} : 'L2 BEB') . "\n");
		}

	} while $loopFlag;
}

sub cfmCheckResult {
	my ($fabricHash, $cfmFailure, $cfmTest, $node, $bvid, $targnode, $cmd, $output) = @_;

	$cfmTest eq 'ping' && do {
		unless ($output =~ /0.00\% packet loss/) {
			$cfmFailure->{$node}->{$bvid}->{$targnode}->{'cmd'} = $cmd;
			$cfmFailure->{$node}->{$bvid}->{$targnode}->{'output'} = $output;
			return 1;
		}
		return 0;
	};

	$cfmTest eq 'tracert' && do {
		my $nexthop = 0;
		my ($hop, $hopname, $currenthop, $error);
		while ( $output =~ /^(\d)+\s+(\S+)\s+\(/mg ) {
			($hop, $hopname) = ($1, $2);
			debugMsg("hop $hop node $hopname\n");
			if ($hop == $nexthop && ( ($hop == 0 && $hopname eq $node) || ($hop > 0 && $fabricHash->{$currenthop}->{'neighbours'}->{$hopname}) ) ) { # Expected
				++$nexthop;
				$currenthop = $hopname;
				debugMsg("Next expected hop $nexthop / current node $currenthop\n");
			}
			else { # Error
				$error = 1;
				debugMsg("******* Mark as FAILED (missing hop) !! ********\n");
				last;
			}
		}
		# Check that final hop was indeed the target node
		if (!defined $hopname) {
			$error = 1;
			debugMsg("******* Mark as FAILED (we did not get expected output) !! ********\n");
		}
		elsif ($hopname ne $targnode) {
			$error = 1;
			debugMsg("******* Mark as FAILED (last hop not target) !! ********\n");
		}
		
		# Error processing
		if ($error) {
			$cfmFailure->{$node}->{$bvid}->{$targnode}->{'cmd'} = $cmd;
			$cfmFailure->{$node}->{$bvid}->{$targnode}->{'output'} = $output;
			return 1;
		}
		return 0;
	};

	die "Unexpected cfm test (should be ping|tracert)";
}

sub fabricCfmTest {
	my ($input, $cli, $fabricHash) = @_;
	my $subNodes;
	my $cfmFailure = {};
	#  $cfmFailure = {
	#		nodename	=> {
	#				bvid	=> {
	#						targetnode	=> {
	#								cmd	=> cmd,
	#								output	=> output,
	#								},
	#						},
	#				},
	#		},
	#  };

	foreach my $bvid (@{$input->{bvlans}}) {
		print "\n\nPerforming CFM ", $input->{cfmTest}, " tests on BVLAN ", $bvid, "\n";
		print "===========================================\n";
		foreach my $targnode (sort {$a cmp $b} keys %$fabricHash) {
			my $cmd;
			my $failures = 0;
			my $success  = 0;
			my @errors = ();
			print "From ALL nodes (except $targnode), performing L2 ", $input->{cfmTest}, " to ", $targnode, " ";
			$subNodes = {}; # Clear it
			foreach my $node (keys %$cli) {
				next if $node eq $targnode;
				$subNodes->{$node} = $cli->{$node};
				$cmd = sprintf($Cfm{$input->{cfmTest}}[$fabricHash->{$node}->{acli}], $bvid, $targnode);
				$cli->{$node}->cmd($cmd);
			}
			poll(
				Object_list	=>	$subNodes,
				Poll_code	=>	\&printDots,
		       		Errmode		=>	'return',	# Always return on error
			);
	
			# Retrieve output
			foreach my $node (keys %$subNodes) {
				my ($ok, $output) = $cli->{$node}->cmd_poll;
				if ($ok) {
					debugMsg("\n$node:$cmd\n$output");
					my $retVal = cfmCheckResult($fabricHash, $cfmFailure, $input->{cfmTest}, $node, $bvid, $targnode, $cmd, $output);
					$failures = 1 if $retVal;
					$success  = 1 if $retVal == 0;
				}
				else { # We got some errors
					push(@errors, $node . ' -> ' . $cli->{$node}->errmsg . "\n");
				}
			}
			if ($failures && $success) {
				print " some failed";
			}
			elsif ($failures) {
				print " all failed";
			}
			else {
				print " all ok!";
			}
			print "(command failed on some devices)" if @errors;
			print "\n";
			if (@errors) {
				foreach my $error (@errors) {
					print " - ", $error;
				}
				print "\n";
			}
		}
	}

	if (%$cfmFailure) { # We have some failures, report them now
		foreach my $node (sort {$a cmp $b} keys %$cfmFailure) {
			print "\n$node failed the following CFM tests\n";
			print "========================================\n";
			foreach my $bvid (sort {$a <=> $b} keys %{$cfmFailure->{$node}}) {
				foreach my $targnode (sort {$a cmp $b} keys %{$cfmFailure->{$node}->{$bvid}}) {
					print $cfmFailure->{$node}->{$bvid}->{$targnode}->{'cmd'}, "\n";
					print $cfmFailure->{$node}->{$bvid}->{$targnode}->{'output'}, "\n";
				}
			}
		}
	}
	else { # No failures !
		print "\nAll CFM tests were successful !!\n\n";
	}
}


#############################
# MAIN                      #
#############################

MAIN:{
	# Variables
	my $input = {}; # Hash reference holding input to this script 
	#  $input = {
	#  		use		=> telnet|ssh
	#  		seed		=> IP of seed
	#  		cfmTest		=> ping|tracert
	#  		bvlans		=> [bvlan1, bvlan2]
	#  		seedName	=> Sysname of seed
	#  };
	my $cli = {}; # Hash reference holding Control::CLI::AvayaData objects
	my $fabricHash = {}; # Hash reference holding data about fabric
	#  $fabricHash = {
	#		<sys-name>	=> {
	#				ip		=> <ip>,
	#				neighbours	=> {
	#						<neighbour1>	=> 1,
	#						<neighbour2>	=> 1,
	#						}
	#				}
	#  };

	# Debug flag -d
	getopts('d');
	$Debug = 1 if $opt_d;

	# Argument processing
	$input->{use} = shift(@ARGV) or printSyntax;
	$input->{use} =~ /^ssh|telnet$/i or printSyntax;
	$input->{seed} = shift(@ARGV) or printSyntax;
	$input->{cfmTest} = shift(@ARGV) or printSyntax;
	$input->{cfmTest} =~ /^ping|tracert$/i or printSyntax;
	if ($input->{seed} =~ s/^([^:]+?)(?::(.+?))?@(\S+)$/$3/) {
		$input->{username} = $1;
		$input->{password} = $2;
	}

	# Connect to seed node
	fabricSeedAcquire($input, $cli, $fabricHash);

	# Complete discovery of mgmt IP via TDP/LLDP is necessary
	fabricTopologyAcquire($input, $cli, $fabricHash);

	# Perform cfm tests
	fabricCfmTest($input, $cli, $fabricHash);
}
