# ACLI sub-module
package AcliPm::GeneratePortListRange;
our $Version = "1.07";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(sortByPort generatePortList manualSlotPortStruct generateVlanList generateRange);
}
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::DebugMessage;
use AcliPm::GlobalDeviceSettings;


sub by_slotPort { # Sort by slot/port
	my $compareResult;
	my @a = split("[/:]", $a);
	my @b = split("[/:]", $b);
	$compareResult = $a[0] <=> $b[0];	# Sort on slot number first (or prt number if setvar was called with non-slot ports)
	return $compareResult if $compareResult;
	if ($a[1] =~ /^\d+$/ && $b[1] =~ /^\d+$/) {
		$compareResult = $a[1] <=> $b[1];	# Then on port number
	}
	else {
		$compareResult = $a[1] cmp $b[1];	# Then on port number (Insight port)
	}
	return $compareResult if $compareResult;
	$compareResult = defined $a[2] <=> defined $b[2];	# In case we are sorting between a channelized port and a normal port
	return $compareResult if $compareResult;
	return $a[2] <=> $b[2]			# Then on channelized port (if both $a & $b are channelized)
}


sub sortByPort { # Takes a list ref input of ports and returns a sorted list
	return sort by_slotPort @_;
}


sub generateSlotPortStruct { # Generates a Slot/Port structure including all slots 0-12 and ports 1-99
	my $host_io = shift;
	$host_io->{Slots} = [0..12];		# VSP9000 has the most slots; Secure Router uses slot 0
	$host_io->{Ports}->[0] = [0..4];	# Secure router slot 0
	foreach my $slot (1..8) {		# VSP slots where 40GbE ports might be channelized
		foreach my $port (1..16) {	# VSP8600 40G ports
			push(@{$host_io->{Ports}->[$slot]}, $port, "$port/1", "$port/2", "$port/3", "$port/4");
		}
		push(@{$host_io->{Ports}->[$slot]}, 17..40);
		foreach my $port (41..42) {	# VSP8200 40G ports
			push(@{$host_io->{Ports}->[$slot]}, $port, "$port/1", "$port/2", "$port/3", "$port/4") if $slot <= 2; 
			push(@{$host_io->{Ports}->[$slot]}, $port) if $slot >= 3;
		}
		push(@{$host_io->{Ports}->[$slot]}, 43..99);
	}
	foreach my $slot (9..12) {		# These slots are 40G free (VSP9000 channelization remains on slot/port format)
		$host_io->{Ports}->[$slot] = [1..99];
	}
	debugMsg(1,"-> generateSlotPortStruct using generic Slots/Ports struct\n");
	return ($host_io->{Slots}, $host_io->{Ports});
}


sub manualSlotPortStruct { # Generates a Slot/Port structure based on provided input port list (provided in list or range format)
	my $inlist = shift;
	my (@slots, @ports, $type);

	my $processPort = sub { # Used by generatePortList to process adding a port to the list based on certain checks
		my ($port, $slot, $chan) = @_;
		if (defined $slot) {
			my $pushPort = defined $chan ? "$port/$chan" : $port;
			push(@{$ports[$slot]}, $pushPort) unless grep(/^$pushPort$/, @{$ports[$slot]});
		}
		else {
			push(@ports, $port) unless grep(/^$port$/, @ports);
		}
	};

	$inlist = [ split(',', $inlist) ] unless ref($inlist) eq 'ARRAY';
	foreach my $element (@$inlist) {
		if ($element =~ /^\d+$/) { # portX (standalone stackable) or other number (e.g. vlan)
			$type = 'noslot' unless defined $type;
			return if $type ne 'noslot';
			if ($element >= 100) { # Safety limit
				debugMsg(1,"-> manualSlotPortStruct unacceptably large port : >", \$element, "<\n");
				return;
			}
			@slots = ();
			&$processPort($element);
		}
		elsif ($element =~ /^(\d+)-(\d+)$/) { # portX-portY (standalone stackable); also number ranges allowed now
			$type = 'noslot' unless defined $type;
			return if $type ne 'noslot';
			if ($1 < 1 || $2 >= 100 || $1 > $2) { # Safety limit
				debugMsg(1,"-> manualSlotPortStruct unacceptable numeric range element : >", \$element, "<\n");
				return;
			}
			@slots = ();
			for my $i ($1..$2) {
				&$processPort($i);
			}
		}
		elsif ($element =~ /^(\d{1,3})[\/:](\d{1,2})(?:\/(\d{1,2}))?$/) { # slotX/portY[/channelZ]
			$type = 'slot/port' unless defined $type;
			return if $type ne 'slot/port';
			my ($slot, $port, $chan) = ($1, $2, $3);
			push(@slots, $slot) unless grep(/^$slot$/, @slots);
			&$processPort($port, $slot, $chan);
		}
		elsif ($element =~ /^(\d{1,3})[\/:](\d{1,2})-(\d{1,2})$/) { # slot/portX-portY
			$type = 'slot/port' unless defined $type;
			return if $type ne 'slot/port';
			my ($slot, $portX, $portY) = ($1, $2, $3);
			if ($portX >= $portY) {
				debugMsg(1,"-> manualSlotPortStruct invalid slot/port range : >", \$element, "<\n");
				return;
			}
			push(@slots, $slot) unless grep(/^$slot$/, @slots);
			for my $i ($portX..$portY) {
				&$processPort($i, $slot);
			}
		}
		elsif ($element =~ /^(\d{1,2})\/(\d{1,2})\/(\d{1,2})-(\d{1,2})$/) { # slot/port/channelX-channelY
			$type = 'slot/port' unless defined $type;
			return if $type ne 'slot/port';
			my ($slot, $port, $chanX, $chanY) = ($1, $2, $3, $4);
			if ($chanX < 1 || $chanY > 4 || $chanX >= $chanY) {
				debugMsg(1,"-> manualSlotPortStruct invalid channelized range : >", \$element, "<\n");
				return;
			}
			push(@slots, $slot) unless grep(/^$slot$/, @slots);
			for my $i ($chanX..$chanY) {
				&$processPort($port, $slot, $i);
			}
		}
		elsif ( $element =~ /^(\d{1,3})[\/:](\d{1,2})(?:\/(\d{1,2}))?-(\d{1,2})[\/:](\d{1,2})(?:\/(\d{1,2}))?$/) { # slotN/portX[/channelV]-slotM/portY[/channelW]
			$type = 'slot/port' unless defined $type;
			return if $type ne 'slot/port';
			my ($slotN, $portX, $chanV, $slotM, $portY, $chanW) = ($1, $2, $3, $4, $5, $6);
			if (defined $chanV && defined $chanW) {
				if ($slotN != $slotM || $portX != $portY || $chanV < 1 || $chanW > 4 || $chanV >= $chanW) {
					debugMsg(1,"-> manualSlotPortStruct invalid channelized range 2 : >", \$element, "<\n");
					return;
				}
				push(@slots, $slotN) unless grep(/^$slotN$/, @slots);
				for my $i ($chanV..$chanW) {
					&$processPort($portX, $slotN, $i);
				}
			}
			else {
				if ($slotN != $slotM || $portX >= $portY) {
					debugMsg(1,"-> manualSlotPortStruct invalid slot/port range 2 : >", \$element, "<\n");
					return;
				}
				push(@slots, $slotN) unless grep(/^$slotN$/, @slots);
				for my $i ($portX..$portY) {
					&$processPort($i, $slotN);
				}
			}
		}
		else {
			debugMsg(1,"-> manualSlotPortStruct unrecognized element : >", \$element, "<\n");
			return;
		}
	}
	if ($type eq 'noslot') {
		@ports = sort { $a <=> $b } @ports;
	}
	else { # 'slot/type' format
		foreach my $slot (@slots) {
			@{$ports[$slot]} = sort by_slotPort @{$ports[$slot]};
		}
	}
	return (\@slots, \@ports);
}


sub generatePortList { # Takes an unordered port list/range, and produces an ordered list (with no ranges & no duplicates)
	my ($host_io, $inlist, $constrainHash, $slotPortStruct) = @_;
	my (@ports, @sortedPorts, $sortedPorts, $portHash, $standalonePorts);
	my $sep = $DeviceSlotPortSep{$host_io->{Type}} || '/'; # Pseudo mode with no type set will default to '/'
	my ($slotStruct, $portStruct) = defined $slotPortStruct ? @$slotPortStruct : ($host_io->{Slots}, $host_io->{Ports});
	$portHash = {} if wantarray;

	my $processPort = sub { # Used by generatePortList to process adding a port to the list based on certain checks
		my $port = shift;
		if (!defined $constrainHash || $constrainHash->{$port}) { # Skip unless in constrain hash
			unless (grep(/^$port$/, @ports)) {
				push(@ports, $port);
				$portHash->{$port} = 1 if defined $portHash;
			}
		}
	};

	my $portIterate = sub { # Used by generatePortList to iterate over valid ports of a given slot
		my ($slot, $slotN, $portX, $chanV, $slotM, $portY, $chanW) = @_;
		$portX = 0 unless defined $portX;	# Ensure all ports will be taken if no start port set
		$portY = 1000 unless defined $portY;	# Ensure all ports will be taken if no end port set
		$portX =~ s/^s/10/; # Make Insight ports 1/s1,1/s2 look like 1/101 & 1/102
		$portY =~ s/^s/10/; # Make Insight ports 1/s1,1/s2 look like 1/101 & 1/102
		if ($host_io->{PortUnconstrain} || ref($portStruct) eq 'HASH') { # We treat ISW port structure as unconstrained
			my $maxSlotPort = $host_io->{PortUnconstrain} ? 99 : 8; # ISW has at most 8 ports per slot type (gig/fast)
			my $startPort = $slot == $slotN ? $portX : 1;
			my $endPort = $slot == $slotM ? $portY : $maxSlotPort;
			if ($startPort == $endPort && defined $chanV && defined $chanW) { 
				# For now handle only cases: slotX/portY[/channelZ] & slot/port/channelX-channelY
				for my $chan ($chanV .. $chanW) {
					&$processPort("$slot$sep$startPort$sep$chan");
				}
			}
			else {
				for my $port ($startPort .. $endPort) {
					&$processPort("$slot$sep$port");
				}
			}
		}
		else {
			return unless @$slotStruct;
			for my $pprt (@{$portStruct->[$slot]}) {
				my $port = $pprt; # We are going to modify it so we make a copy of it
				$port =~ s/^s/10/; # Make Insight ports 1/s1,1/s2 look like 1/101 & 1/102
				my @portChannel = split(/[\/:]/, $port);
				if (scalar @portChannel == 2) { # 40GbE Channelized port
					next if $slot == $slotN && $portChannel[0] < $portX;
					last if $slot == $slotM && $portChannel[0] > $portY;
					last if $slot == $slotM && $portChannel[0] == $portY && !defined $chanV && !defined $chanW;
					next if defined $chanV && $slot == $slotN && $portChannel[0] == $portX && $portChannel[1] < $chanV;
					last if defined $chanW && $slot == $slotM && $portChannel[0] == $portY && $portChannel[1] > $chanW;
					&$processPort("$slot$sep$port");
				}
				else { # Normal ports
					next if $slot == $slotN && defined $chanV;
					next if $slot == $slotN && $port < $portX;
					last if $slot == $slotM && $port > $portY;
					$port =~ s/^10(\d)$/s$1/; # Restore Insight port before appending
					&$processPort("$slot$sep$port");
				}
			}
		}
	};

	$inlist = [ split(',', $inlist) ] unless ref($inlist) eq 'ARRAY';
	debugMsg(1,"-> generatePortList input = ", \join(';', @$inlist), "\n") if $::Debug;

	unless (defined $portStruct && defined $slotStruct) { # If these are not set, we populate them (forgiving grep)
		($slotStruct, $portStruct) = generateSlotPortStruct($host_io);	# We get here in -g mode as well as in pseudo term mode
	}

	$standalonePorts = @$slotStruct ? 0 : 1; # This is NOT of @$slotStruct, but can change in first section below

	if (@$slotStruct) { # Port structure for switch is using slot/port format

		foreach my $element (@$inlist) { # Slot based processing
			if ($element =~ /^ALL$/i && !$host_io->{PortUnconstrain} && ref($portStruct) eq 'ARRAY') { # All ports
				@ports = ();	# If we had some ports in array already, never mind, we are about to fill it with all ports
				for my $slot (@$slotStruct) {
					for my $port (@{$portStruct->[$slot]}) {
						&$processPort("$slot$sep$port");
					}
				}
				last;		# If we have some extra entries, never mind, we have all ports in array now
			}
			elsif ($element =~ /^\d+$/ || $element =~ /^(\d+)-(\d+)$/) { # Other number (e.g. vlan) or number ranges
				if (scalar @ports) {
					debugMsg(1,"-> generatePortList some ports listed, cannot fall into simple ranges : >", \$element, "<\n");
					return wantarray ? () : ''; # empty string we have an unrecognized port format
				}
				$standalonePorts = 1; # Fall into next section
				last;
			}
			elsif ($element =~ /^(\d{1,3})[\/:](\d{1,2})(?:[\/:](\d{1,2}))?$/) { # slotX/portY[/channelZ]
				my ($slot, $port, $chan) = ($1, $2, $3);
				&$portIterate($slot, $slot, $port, $chan, $slot, $port, $chan);
			}
			elsif ($element =~ /^1\/(s\d)$/) { # 1/s1 or 1/s2 ; VSP Insight ports
				my ($slot, $port) = (1, $1);
				&$portIterate($slot, $slot, $port, undef, $slot, $port, undef);
			}
			elsif ($element =~ /^1\/(s\d)-(?:1\/)?(s\d)$/) { # 1/s1-s2 ; VSP Insight ports
				my ($slot, $portX, $portY) = (1, $1, $2);
				&$portIterate($slot, $slot, $portX, undef, $slot, $portY, undef);
			}
			elsif ($element =~ /^(\d{1,3})[\/:](\d{1,2})-(\d{1,2})$/) { # slot/portX-portY
				my ($slot, $portX, $portY) = ($1, $2, $3);
				&$portIterate($slot, $slot, $portX, undef, $slot, $portY, undef);
			}
			elsif ($element =~ /^(\d{1,3})[\/:]ALL$/i) { # slot/ALL
				my $slot = $1;
				&$portIterate($slot, $slot, undef, undef, $slot, undef, undef);
			}
			elsif ($element =~ /^(\d{1,2})[\/:](\d{1,2})[\/:](\d{1,2})-(\d{1,2})$/) { # slot/port/channelX-channelY
				my ($slot, $port, $chanX, $chanY) = ($1, $2, $3, $4);
				&$portIterate($slot, $slot, $port, $chanX, $slot, $port, $chanY);
			}
			elsif ($element =~ /^(\d{1,2})[\/:](\d{1,2})[\/:]ALL$/i) { # slot/port/ALL ; all channelized 40GbE sub-ports
				my ($slot, $port) = ($1, $2);
				&$portIterate($slot, $slot, $port, 1, $slot, $port, 4);
			}
			elsif ( $element =~ /^(\d{1,3})[\/:](\d{1,2})(?:[\/:](\d{1,2}))?-(\d{1,2})[\/:](\d{1,2})(?:[\/:](\d{1,2}))?$/ ||# slotN/portX[/channelV]-slotM/portY[/channelW]
				$element =~ /^(1)\/(s\d)()-(\d{1,2})[\/:](\d{1,2})(?:\/(\d{1,2}))?$/ ||					# 1/sX-slotM/portY[/channelW]
				$element =~ /^(1)[\/:](\d{1,2})(?:\/(\d{1,2}))?-(1)\/(s\d)()$/ ||					# slotN/portX[/channelV]-1/sY
				$element =~ /^(1)\/(s\d)()-(1)\/(s\d)()$/								# 1/sX-1/sY
			      ) {
				my ($slotN, $portX, $chanV, $slotM, $portY, $chanW) = ($1, $2, $3, $4, $5, $6);
				if ($host_io->{PortUnconstrain} || ref($portStruct) eq 'HASH') {
					for my $slot ($slotN .. $slotM) {
						&$portIterate($slot, $slotN, $portX, $chanV, $slotM, $portY, $chanW);
					}
				}
				else {
					for my $slot (@$slotStruct) {
						next if $slot < $slotN;
						last if $slot > $slotM;
						&$portIterate($slot, $slotN, $portX, $chanV, $slotM, $portY, $chanW);
					}
				}
			}
			else {
				debugMsg(1,"-> generatePortList unrecognized element : >", \$element, "<\n");
				return wantarray ? () : ''; # empty string we have an unrecognized port format
			}
		}
	}

	if ($standalonePorts) { # Port structure for switch is using only the port list format

		foreach my $element (@$inlist) { # Non-Slot based processing
			if ($element =~ /^ALL$/i && !$host_io->{PortUnconstrain} && ref($portStruct) eq 'ARRAY') { # All ports
				@ports = ();	# If we had some ports in array already, never mind, we are about to fill it with all ports
				for my $port (@$portStruct) {
					&$processPort($port);
				}
				last;		# If we have some extra entries, never mind, we have all ports in array now
			}
			elsif ($element =~ /^\d+$/) { # portX (standalone stackable) or other number (e.g. vlan)
				&$processPort($element);
			}
			elsif ($element =~ /^(\d+)-(\d+)$/) { # portX-portY (standalone stackable); also number ranges allowed now
				if ($2 > $1 && ($2 - $1) <= 5000 ) { # Safety limit
					for my $i ($1..$2) {
						&$processPort($i);
					}
				}
				else {
					debugMsg(1,"-> generatePortList unacceptable numeric range element : >", \$element, "<\n");
					return wantarray ? () : ''; # empty string we have an unrecognized port format
				}
			}
			elsif ($element =~ /^\d{1,3}[\/:]\d{1,2}$/) { # slotX/portY (this can be valid on 5720 in EXOS mode)
				&$processPort($element);
			}
			# Slot1 ports on a standalone switch will be accepted
			elsif (!@$slotStruct && $element =~ /^1[\/:](\d{1,2})$/) { # 1/portX
				&$processPort($1) if $host_io->{PortUnconstrain} || grep(/^$1$/, @$portStruct);
			}
			elsif (!@$slotStruct && $element =~ /^1[\/:](\d{1,2})-(\d{1,2})$/) { # 1/portX-portY
				for my $port ($1..$2) {
					&$processPort($port) if $host_io->{PortUnconstrain} || grep(/^$port$/, @$portStruct);
				}
			}
			elsif (!@$slotStruct && $element =~ /^1[\/:](\d{1,2})-1[\/:](\d{1,2})$/) { # 1/portX-1/portY
				for my $port ($1..$2) {
					&$processPort($port) if $host_io->{PortUnconstrain} || grep(/^$port$/, @$portStruct);
				}
			}
			else {
				debugMsg(1,"-> generatePortList unrecognized element : >", \$element, "<\n");
				return wantarray ? () : ''; # empty string we have an unrecognized port format
			}
		}
	}
	@sortedPorts = sort by_slotPort @ports;
	$sortedPorts = join(',', @sortedPorts);
	debugMsg(1,"-> generatePortList output = ", \$sortedPorts, "\n");
	return ($sortedPorts, $portHash) if wantarray;
	return $sortedPorts;
}


sub generateVlanList { # Takes an unordered VLAN list/range, and produces an ordered list (with no ranges & no duplicates)
	my ($inlist, $retListRef, $constrainList) = @_;
	my (@vlans, $vlanList);
	$inlist = [ split(',', $inlist) ] unless ref($inlist) eq 'ARRAY';

	if (defined $constrainList) {
		foreach my $element (@$inlist) {
			if ($element =~ /^\d+$/) { # single vlan
				next unless grep(/^$element$/, @$constrainList); # Skip if not in constrain list
				push(@vlans, $element) unless grep(/^$element$/, @vlans);
			}
			elsif ($element =~ /^(\d{1,4})-(\d{1,4})$/) { # vlanX-vlanY vlan range
				my ($start, $end) = ($1, $2);
				foreach my $celem (@$constrainList) {
					next if $celem < $start || $celem > $end; # Skip if out of range
					push(@vlans, $celem) unless grep(/^$celem$/, @vlans);
				}
			}
			else {
				debugMsg(1,"-> generateVlanList unrecognized element : >", \$element, "<\n");
				return ''; # empty string we have an unrecognized range format
			}
		}
	}
	else {
		foreach my $element (@$inlist) {
			if ($element =~ /^\d+$/) { # single vlan
				push(@vlans, $element) unless grep(/^$element$/, @vlans);
			}
			elsif ($element =~ /^(\d{1,4})-(\d{1,4})$/) { # vlanX-vlanY vlan range
				for my $i ($1..$2) {
					push(@vlans, $i) unless grep(/^$i$/, @vlans);
				}
			}
			else {
				debugMsg(1,"-> generateVlanList unrecognized element : >", \$element, "<\n");
				return ''; # empty string we have an unrecognized range format
			}
		}
	}
	return \@vlans if $retListRef;
	$vlanList = join(',', @vlans);
	return $vlanList;
}


sub generateRange { # Takes an ordered port (or vlan) list (with no ranges & no duplicates) and produces a compacted port list/range
	my ($db, $inlist, $rangeMode, $slotPortStruct) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	# $rangeMode: 0 = do not generate ranges; 1 = compact ranges (Baystack like : 1/1-24); 2 = VOSS ranges (less compact 1/1-1/24); bit2 determines ranges across slots
	$rangeMode = $term_io->{DefaultPortRng} unless defined $rangeMode; # 1 is default, if none specified
	$inlist = [ split(',', $inlist) ] unless ref($inlist) eq 'ARRAY';
	return join(',', @$inlist) unless $rangeMode & 3; # if bits 0 & 1 @ 0
	my (@ports, $elementBuild, $elementType, $elementSlot, $elementPort, $elementChan, $elementLast, $elemNextSlot, $elemLastPortOfSlot, $elemStartSlot, $rangePorts);
	my ($slotStruct, $portStruct) = defined $slotPortStruct ? @$slotPortStruct : ($host_io->{Slots}, $host_io->{Ports});

	my $validSlot = sub { # Validates slot
		my $slot = shift;
		return 1 if $host_io->{PortUnconstrain} || ref($portStruct) eq 'HASH';
		return scalar grep {$_ == $slot} @$slotStruct;
	};

	my $nextSlot = sub { # Next slot after current slot; 0 if last
		my $slot = shift;
		my $nextSlot = 0;
		return ++$slot if $host_io->{PortUnconstrain} || ref($portStruct) eq 'HASH';
		foreach my $s (@$slotStruct) {
			next if $s <= $slot;
			$nextSlot = $s;
			last;
		}
		return $nextSlot;
	};

	my $lastPortOfSlot = sub { # Returns true if port is last port of slot; false otherwise
		my ($slot, $port) = @_;
		if ($host_io->{PortUnconstrain}) {
			return $port == 99 ? 1 : 0;
		}
		elsif (ref($portStruct) eq 'HASH') { # ISW Case
			return $port == 8 ? 1 : 0; # Max ports per slot type (gig/fast) on ISW is 8
		}
		return @$slotStruct && defined $portStruct->[$slot] && $portStruct->[$slot][-1] =~ /^$port(?:[\/:]|$)/;
	};

	debugMsg(1,"-> generateRange input = ", \join(';', @$inlist), "\n") if $::Debug;
	unless (defined $portStruct && defined $slotStruct) { # If these are not set, we populate them (forgiving grep)
		($slotStruct, $portStruct) = generateSlotPortStruct($host_io);	# We get here in -g mode as well as in pseudo term mode
	}

	foreach my $element (@$inlist) {
		if ($element =~ /^(\d{1,2})([\/:])(\d{1,2})[\/:](\d{1,2})$/) { # slotX/portY/channelZ
			my ($slot, $sep, $port, $chan) = ($1, $2, $3, $4);
			next unless &$validSlot($slot);
			my $type = 's/p';
			if (defined $elementBuild) {
				if ($type eq $elementType && $slot == $elementSlot && $port == $elementPort && $chan == $elementChan + 1) {
					$elementChan = $chan;
					$elementLast = $elementSlot . $sep . $elementPort . $sep . $elementChan;
					next;
				}
				elsif ( $term_io->{PortRngSpanSlot} && $rangeMode & 4 &&
					$type eq $elementType && $slot == $elementSlot && $port == $elementPort + 1 && ($elementChan == 0 || $elementChan == 4) && $chan == 1) {
					$elementPort = $port;
					$elementChan = $chan;
					$elemLastPortOfSlot = &$lastPortOfSlot($slot, $port);
					$elementLast = $elementSlot . $sep . $elementPort . $sep . $elementChan;
					next;
				}
				elsif ( $term_io->{PortRngSpanSlot} && $rangeMode & 4 &&
					$type eq $elementType && $slot == $elemNextSlot && $elemLastPortOfSlot && $port == 1 && $chan == 1) {
					$elementSlot = $slot;
					$elementPort = $port;
					$elementChan = $chan;
					$elemNextSlot = &$nextSlot($slot);
					$elemLastPortOfSlot = &$lastPortOfSlot($slot, $port);
					$elementLast = $elementSlot . $sep . $elementPort . $sep . $elementChan;
					next;
				}
				else { # Range complete
					$elementBuild .= "-" . $elementLast if $elementLast;
					push(@ports, $elementBuild);
					($elementBuild, $elementType, $elementSlot, $elementPort, $elementChan, $elementLast) = ();
					# Fall through below
				}
			}
			$elementType = $type;
			$elementSlot = $elemStartSlot = $slot;
			$elementPort = $port;
			$elementChan = $chan;
			$elemNextSlot = &$nextSlot($slot);
			$elemLastPortOfSlot = &$lastPortOfSlot($slot, $port);
			$elementBuild = "$slot$sep$port$sep$chan";
		}
		elsif ($element =~ /^(\d{1,2})([\/:])(\d{1,2})$/) { # slotX/portY
			my ($slot, $sep, $port) = ($1, $2, $3);
			next if @$slotStruct && !&$validSlot($slot); # Only validate the slot, on devices with slot based ports (i.e. not 5720 in XOS mode)
			my $type = 's/p';
			if (defined $elementBuild) {
				if ( $term_io->{PortRngSpanSlot} && ($type eq $elementType && $slot == $elementSlot && $port == $elementPort + 1 && $elementChan == 4)
				    ) {
					$elementPort = $port;
					$elementChan = 0;
					$elemLastPortOfSlot = &$lastPortOfSlot($slot, $port);
					$elementLast = $rangeMode & 1 && $elementSlot == $elemStartSlot ? $elementPort : $elementSlot . $sep . $elementPort;
					next;
				}
				elsif ( ($type eq $elementType && $slot == $elementSlot && $port == $elementPort + 1 && $elementChan == 0) ) {
					$elementPort = $port;
					$elementChan = 0;
					$elemLastPortOfSlot = &$lastPortOfSlot($slot, $port);
					$elementLast = $rangeMode & 1 && $elementSlot == $elemStartSlot ? $elementPort : $elementSlot . $sep . $elementPort;
					next;
				}
				elsif ( $term_io->{PortRngSpanSlot} && $rangeMode & 4 &&
					$type eq $elementType && $slot == $elemNextSlot && $elemLastPortOfSlot && $port == 1 && ($elementChan == 0 || $elementChan == 4)) {
					$elementSlot = $slot;
					$elementPort = $port;
					$elementChan = 0;
					$elemNextSlot = &$nextSlot($slot);
					$elemLastPortOfSlot = &$lastPortOfSlot($slot, $port);
					$elementLast = $rangeMode & 1 && $elementSlot == $elemStartSlot ? $elementPort : $elementSlot . $sep . $elementPort;
					next;
				}
				else { # Range complete
					$elementBuild .= "-" . $elementLast if $elementLast;
					push(@ports, $elementBuild);
					($elementBuild, $elementType, $elementSlot, $elementPort, $elementChan, $elementLast) = ();
					# Fall through below
				}
			}
			$elementType = $type;
			$elementSlot = $elemStartSlot = $slot;
			$elementPort = $port;
			$elementChan = 0;
			$elemNextSlot = &$nextSlot($slot);
			$elemLastPortOfSlot = &$lastPortOfSlot($slot, $port);
			$elementBuild = "$slot$sep$port";
		}
		elsif ($element =~ /^(\d+)$/) { # portY (or VlanX)
			my $port = $1;
			my $type = 'p';
			if (defined $elementBuild) {
				if ($type eq $elementType && $port == $elementPort + 1) { # Add to current range
					$elementLast = $elementPort = $port;
					next;
				}
				else { # Range complete
					$elementBuild .= "-" . $elementLast if $elementLast;
					push(@ports, $elementBuild);
					($elementBuild, $elementType, $elementSlot, $elementPort, $elementChan, $elementLast) = ();
					# Fall through below
				}
			}
			$elementType = $type;
			$elementPort = $port;
			$elementBuild = "$port";
		}
		else { # Other formats
			if (defined $elementBuild) { # Range complete
				$elementBuild .= "-" . $elementLast if $elementLast;
				push(@ports, $elementBuild);
				($elementBuild, $elementType, $elementSlot, $elementPort, $elementChan, $elementLast) = ();
				# Fall through below
			}
			push(@ports, $element);
		}
	}
	if (defined $elementBuild) { # Close off last element we were holding
		$elementBuild .= "-" . $elementLast if $elementLast;
		push(@ports, $elementBuild);
	}
	$rangePorts = join(',', @ports);
	debugMsg(1,"-> generateRange output = ", \$rangePorts, "\n");
	return $rangePorts;
}

1;
