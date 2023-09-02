#!/usr/bin/perl
my $Version = "0.05";
our $Debug = 0; # 8 Dumper; 4 detail; 2 advanced; 1 basic

#
# Written by Ludovico Stevens (lstevens@extremenetworks.com)
#

#############################
# STANDARD MODULES          #
#############################

use strict;
use warnings;

use File::Basename;
use File::Spec;
use File::Glob ':bsd_glob';
use Getopt::Std;
use Cpanel::JSON::XS;
use YAML::XS;
use Hash::Merge;
use Storable 'dclone';

use Data::Dumper;
$Data::Dumper::Indent = 1;


############################
# GLOBAL VARIABLES         #
############################
my ($ScriptName, $ScriptDir) = File::Basename::fileparse(File::Spec->rel2abs($0));
my $JsonCoder = Cpanel::JSON::XS->new->ascii->pretty->allow_nonref->canonical->unblessed_bool(1);
our $HashMerge = Hash::Merge->new( 'RIGHT_PRECEDENT' );
my $Space = ' ';
my $Marker = "\x00";
my $PortsRegex = '^((?:\d{1,3}[\/:](?:ALL|s\d|\d{1,2}(?:\/\d{1,2})?)(?:\-\d{1,3}(?:[\/:](?:s\d|\d{1,2}(?:\/\d{1,2})?))?)?,)*\d{1,3}[\/:](?:ALL|s\d|\d{1,2}(?:\/\d{1,2})?)(?:\-\d{1,3}(?:[\/:](?:s\d|\d{1,2}(?:\/\d{1,2})?))?)?|(?:\d{1,2}(?:\-\d{1,2})?,)*\d{1,2}(?:\-\d{1,2})?|ALL)$';
my $PortsRegex2 = '((?:\d{1,3}[\/:](?:s\d|\d{1,2}(?:\/\d{1,2})?)(?:\-\d{1,3}(?:[\/:](?:s\d|\d{1,2}(?:\/\d{1,2})?))?)?,)*\d{1,3}[\/:](?:s\d|\d{1,2}(?:\/\d{1,2})?)(?:\-\d{1,3}(?:[\/:](?:s\d|\d{1,2}(?:\/\d{1,2})?))?)?)';
my $VarJson   = '(?:x|[\w-]+(?:\{(?:x(?::v)?|[\w-]+)\}|\[(?:x|\d+)\])+)';	# Matches valid json variable for use in encoder.out file
my $VarJson2  = '[\w-]+(?:\{<?[\w-]+>?\}|\[(?:x|<?\d+>?)\])+';	# Matches valid json variable for use in encoder.out file - 
my $VarJson3  = '[\w-]+(?:\{[\w\.:-]+\}|\[(?:x|\d+)\])+';	# Matches valid json variable for use in encoder.out file - embedding jsonVars in c2j encoder file
my $ArgJson = '<(([\w-]+)(:(?:\!?\%|\*|[\*\w=,-]+))?)>';	#$1 = all; $2 = arg name; $3 = arg modifiers including :

my $Ofh = \*STDOUT; # Default debug Output File Handle
my $AcliDir = '/.acli';
my (@AcliFilePath);
if (defined(my $path = $ENV{'ACLI'})) {
	push(@AcliFilePath, File::Spec->canonpath($path));
}
elsif (defined($path = $ENV{'HOME'})) {
	push(@AcliFilePath, File::Spec->canonpath($path.$AcliDir));
}
elsif (defined($path = $ENV{'USERPROFILE'})) {
	push(@AcliFilePath, File::Spec->canonpath($path.$AcliDir));
}
push(@AcliFilePath, File::Spec->canonpath($ScriptDir)); # Last resort, script directory
our ($opt_d);


#############################
# FUNCTIONS                 #
#############################

sub printSyntax {
	printf "%s version %s%s\n\n", $ScriptName, $Version, ($Debug ? " running on $^O perl version $]" : "");
	print " Tool to extract data from config files and/or generate new config files from that data\n";
	print " Data rendered in either JSON or YAML format for inspection or intermediate editing\n";
	print "\nUsage:\n";
	print " $ScriptName schema <encoder.c2j> [<out-schema-file>]\n" if $Debug;
	print " $ScriptName makej2c <encoder.c2j> [<out-j2c-file>]\n" if $Debug;
	print " $ScriptName extract json|yaml <encoder.c2j> <in-cfg-file(s)>\n";
	print " $ScriptName makecfg <data.yaml-or-json> <decoder.j2c> [<out-cfg-file>]\n";
	print " $ScriptName convert <encoder.c2j> <decoder.j2c> <in-cfg-file(s)>\n\n";
	print " schema           : Extracts the data schema used by the encoder c2j file\n" if $Debug;
	print " makej2c          : Uses the encoder c2j file to make a first stab at the equivalent j2c decoder\n" if $Debug;
	print " extract          : Extract data from input config file(s) using provided encoder c2j file\n";
	print "                  : The resulting data is saved as either in-cfg-file.json or in-cfg-file.yaml\n";
	print " makecfg          : Generates a config from json/yaml data file using provided decoder j2c file\n";
	print "                  : If no output file provided, will save to file data.decoder\n";
	print " convert          : Combines 'extract' and 'makecfg' without saving any json/yaml data file\n";
	print "                  : Will save output to file(s) in-cfg-file.decoder\n";
	print " <encoder.c2j>    : Definition file for extracting config into data structure schema\n";
	print " <decoder.j2c>    : Definition file for generating config from data structure schema\n";
	print " <in-cfg-file(s)> : One or more input config files or wildcard\n";
	print " <out-cfg-file>   : Name of output config file to generate; if omitted will be infile.decoder\n";
	print " <out-schema-file>: Name of output schema file to generate; if omitted will be encoder.schema\n" if $Debug;
	print " <out-j2c-file>   : Name of output decoder file to generate; if omitted will be encoder.c2j.j2c\n" if $Debug;
	exit 1;
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
		print $Ofh $string1, $refPrint, $string2;
	}
}

sub quit { # Quit printing script name + error message
	my ($retval, $quitmsg) = @_;
	print "\n$ScriptName: ",$quitmsg,"\n" if $quitmsg;
	# Clean up and exit
	exit $retval;
}

sub quoteCurlyMask { # Returns a new string where all occurrences of char(s) are replaced inside quoted (or curlies) sections with ASCII code OR 128
	# Modified from AcliPm::MaskUnmaskChars
	my ($string, $char) = @_;
	my @chars = split(//, $char);
	map(s/([|!^\$\%{}\(\)])/\\$1/, @chars); # Characters which need backslashing; need to use substr below to get ascii value of last char
	my ($quote, $i);
	$string =~ s/(\".*?\"|\'.*?\'|\{.*?\}|\(.*?\)|\[.*?\])/$quote = $1; foreach $i (0..$#chars) {$quote =~ s!$chars[$i]!chr(ord(substr $chars[$i], -1)|128)!ge}; $quote/ge;
	return $string;
}

sub quoteCurlyUnmask { # Restores all occurrences of char(s) inside quoted (or curlies) sections if these were previously masked with ASCII code OR 128
	# Modified from AcliPm::MaskUnmaskChars
	my ($string, $char) = @_;
	my @chars = split(//, $char);
	my ($quote, $i);
	$string =~ s/(\".*?\"|\'.*?\'|\{.*?\}|\(.*?\)|\[.*?\])/$quote = $1; foreach $i (0..$#chars) {my $c = chr(ord($chars[$i])|128); $quote =~ s!$c!$chars[$i]!g}; $quote/ge;
	return $string;
}

sub argColonMask { # Returns a new string where all occurrences of char(s) are replaced inside quoted (or curlies) sections with ASCII code OR 128
	my $stringRef = shift;
	my @chars = (':', ',');
	my ($quote, $i);
	$$stringRef =~ s/(<.*?>)/$quote = $1; foreach $i (0..$#chars) {$quote =~ s!$chars[$i]!chr(ord(substr $chars[$i], -1)|128)!ge}; $quote/ge;
}

sub argColonUnmask { # Restores all occurrences of char(s) inside quoted (or curlies) sections if these were previously masked with ASCII code OR 128
	my $stringRef = shift;
	my @chars = (':', ',');
	my ($quote, $i);
	$$stringRef =~ s/(<.*?>)/$quote = $1; foreach $i (0..$#chars) {my $c = chr(ord($chars[$i])|128); $quote =~ s!$c!$chars[$i]!g}; $quote/ge;
}

sub optSquareMask { # Returns a new string where all occurrences of char(s) are replaced inside quoted (or curlies) sections with ASCII code OR 128
	my $stringRef = shift;
	my @chars = ('\[', '\]');
	my ($quote, $i);
	$$stringRef =~ s/(<.*?>)/$quote = $1; foreach $i (0..$#chars) {$quote =~ s!$chars[$i]!chr(ord(substr $chars[$i], -1)|128)!ge}; $quote/ge;
}

sub optSquareUnmask { # Restores all occurrences of char(s) inside quoted (or curlies) sections if these were previously masked with ASCII code OR 128
	my $stringRef = shift;
	my @chars = ('[', ']');
	my ($quote, $i);
	$$stringRef =~ s/(<.*?>)/$quote = $1; foreach $i (0..$#chars) {my $c = chr(ord($chars[$i])|128); $quote =~ s!$c!$chars[$i]!g}; $quote/ge;
}

sub by_slotPort { # Sort by slot/port
	# Unmodified from AcliPm::GeneratePortListRange
	my $compareResult;
	my @a = split("[/:]", $a);
	my @b = split("[/:]", $b);
	$compareResult = $a[0] <=> $b[0];	# Sort on slot number first
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

sub generatePortList { # Takes an unordered port list/range, and produces an ordered list (with no ranges & no duplicates)
	# Modified from AcliPm::GeneratePortListRange
	my ($inlist, $portall) = @_;
	return '' unless defined $inlist;
	my (@ports, @sortedPorts, $sortedPorts, $type);
	my $maxSlotPort = defined $portall ? $portall : 99;
	my $sep = ($inlist =~ /\d([\/:])\d/) ? $1 : '/'; # Detect from input port list

	my $processPort = sub { # Used by generatePortList to process adding a port to the list based on certain checks
		my $port = shift;
		unless (grep(/^$port$/, @ports)) {
			push(@ports, $port);
		}
	};

	my $portIterate = sub { # Used by generatePortList to iterate over valid ports of a given slot
		my ($slot, $slotN, $portX, $chanV, $slotM, $portY, $chanW) = @_;
		$portX = 1 unless defined $portX;	# Ensure all ports will be taken if no start port set
		$portY = $portall unless defined $portY;	# Ensure all ports will be taken if no end port set
		$portX =~ s/^s/10/; # Make Insight ports 1/s1,1/s2 look like 1/101 & 1/102
		$portY =~ s/^s/10/; # Make Insight ports 1/s1,1/s2 look like 1/101 & 1/102
		my $startPort = $slot == $slotN ? $portX : 1;
		my $endPort = $slot == $slotM ? $portY : $maxSlotPort;
		for my $port ($startPort .. $endPort) {
			&$processPort("$slot$sep$port");
		}
	};

	$inlist = [ split(',', $inlist) ] unless ref($inlist) eq 'ARRAY';
	debugMsg(2,"-> generatePortList input = ", \join(';', @$inlist), "\n") if $::Debug;

	foreach my $element (@$inlist) {
		next if $element =~ /^ALL$/i; # We are not supporting this
		if ($element =~ /^\d+$/) { # portX (standalone stackable) or other number (e.g. vlan)
			$type = 'noslot' unless defined $type;
			return wantarray ? () : '' if $type ne 'noslot';
			&$processPort($element);
		}
		elsif ($element =~ /^(\d+)-(\d+)$/) { # portX-portY (standalone stackable); also number ranges allowed now
			$type = 'noslot' unless defined $type;
			return wantarray ? () : '' if $type ne 'noslot';
			if ($2 > $1 && ($2 - $1) <= 5000 ) { # Safety limit
				for my $i ($1..$2) {
					&$processPort($i);
				}
			}
			else {
				debugMsg(8,"-> generatePortList unacceptable numeric range element : >", \$element, "<\n");
				return wantarray ? () : ''; # empty string we have an unrecognized port format
			}
		}
		# Chassis or Stack port format (1 or 2 digit slot / 1 or 2 digit port)
		elsif ($element =~ /^(\d{1,3})[\/:](\d{1,2})(?:\/(\d{1,2}))?$/) { # slotX/portY[/channelZ]
			$type = 'slot/port' unless defined $type;
			return wantarray ? () : '' if $type ne 'slot/port';
			my ($slot, $port, $chan) = ($1, $2, $3);
			&$portIterate($slot, $slot, $port, $chan, $slot, $port, $chan);
		}
		elsif ($element =~ /^(1\/s\d)$/) { # 1/s1 or 1/s2 ; VSP Insight ports
			$type = 'slot/port' unless defined $type;
			return wantarray ? () : '' if $type ne 'slot/port';
			&$portIterate(1, 1, $1, undef, 1, $1, undef);
		}
		elsif ($element =~ /^1\/(s\d)-(?:1\/)?(s\d)$/) { # 1/s1-s2 ; VSP Insight ports
			$type = 'slot/port' unless defined $type;
			return wantarray ? () : '' if $type ne 'slot/port';
			my ($slot, $portX, $portY) = (1, $1, $2);
			&$portIterate($slot, $slot, $portX, undef, $slot, $portY, undef);
		}
		elsif ($element =~ /^(\d{1,3})[\/:](\d{1,2})-(\d{1,2})$/) { # slot/portX-portY
			$type = 'slot/port' unless defined $type;
			return wantarray ? () : '' if $type ne 'slot/port';
			my ($slot, $portX, $portY) = ($1, $2, $3);
			&$portIterate($slot, $slot, $portX, undef, $slot, $portY, undef);
		}
		elsif ($element =~ /^(\d{1,3})[\/:]ALL$/i) { # slot/ALL
			$type = 'slot/port' unless defined $type;
			return wantarray ? () : '' if $type ne 'slot/port';
			my $slot = $1;
			&$portIterate($slot, $slot, undef, undef, $slot, undef, undef);
		}
		elsif ($element =~ /^(\d{1,2})\/(\d{1,2})\/(\d{1,2})-(\d{1,2})$/) { # slot/port/channelX-channelY
			$type = 'slot/port' unless defined $type;
			return wantarray ? () : '' if $type ne 'slot/port';
			my ($slot, $port, $chanX, $chanY) = ($1, $2, $3, $4);
			&$portIterate($slot, $slot, $port, $chanX, $slot, $port, $chanY);
		}
		elsif ($element =~ /^(\d{1,2})\/(\d{1,2})\/ALL$/i) { # slot/port/ALL ; all channelized 40GbE sub-ports
			$type = 'slot/port' unless defined $type;
			return wantarray ? () : '' if $type ne 'slot/port';
			my ($slot, $port) = ($1, $2);
			&$portIterate($slot, $slot, $port, 1, $slot, $port, 4);
		}
		elsif ( $element =~ /^(\d{1,3})[\/:](\d{1,2})(?:\/(\d{1,2}))?-(\d{1,2})[\/:](\d{1,2})(?:\/(\d{1,2}))?$/ ||	# slotN/portX[/channelV]-slotM/portY[/channelW]
			$element =~ /^(1)\/(s\d)()-(\d{1,2})[\/:](\d{1,2})(?:\/(\d{1,2}))?$/ ||					# 1/sX-slotM/portY[/channelW]
			$element =~ /^(1)[\/:](\d{1,2})(?:\/(\d{1,2}))?-(1)\/(s\d)()$/ ||					# slotN/portX[/channelV]-1/sY
			$element =~ /^(1)\/(s\d)()-(1)\/(s\d)()$/								# 1/sX-1/sY
		      ) {
			$type = 'slot/port' unless defined $type;
			return wantarray ? () : '' if $type ne 'slot/port';
			my ($slotN, $portX, $chanV, $slotM, $portY, $chanW) = ($1, $2, $3, $4, $5, $6);
			for my $slot ($slotN .. $slotM) {
				&$portIterate($slot, $slotN, $portX, $chanV, $slotM, $portY, $chanW);
			}
		}
		else {
			debugMsg(8,"-> generatePortList unrecognized element : >", \$element, "<\n");
			return wantarray ? () : ''; # empty string we have an unrecognized port format
		}
	}
	return '' unless @ports;
	if ($type eq 'noslot') {
		@sortedPorts = sort { $a <=> $b } @ports;
	}
	else { # 'slot/type' format
		@sortedPorts = sort by_slotPort @ports;
	}
	$sortedPorts = join(',', @sortedPorts);
	debugMsg(2,"-> generatePortList output = ", \$sortedPorts, "\n");
	return $sortedPorts;
}

sub generateVlanList { # Takes an unordered VLAN list/range, and produces an ordered list (with no ranges & no duplicates)
	# Unmodified from AcliPm::GeneratePortListRange
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
				debugMsg(2,"-> generateVlanList unrecognized element : >", \$element, "<\n");
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
				debugMsg(2,"-> generateVlanList unrecognized element : >", \$element, "<\n");
				return ''; # empty string we have an unrecognized range format
			}
		}
	}
	return \@vlans if $retListRef;
	$vlanList = join(',', @vlans);
	return $vlanList;
}

sub generateRange { # Takes an ordered port (or vlan) list (with no ranges & no duplicates) and produces a compacted port list/range
	# Modified from AcliPm::GeneratePortListRange
	my ($inlist, $rangeMode, $slotportSeparator) = @_;
	# $rangeMode: 0 = do not generate ranges; 1 = compact ranges (Baystack like : 1/1-24); 2 = VOSS ranges (less compact 1/1-1/24); bit2 determines ranges across slots
	$inlist = [ split(',', $inlist) ] unless ref($inlist) eq 'ARRAY';
	return join(',', @$inlist) unless $rangeMode & 3; # if bits 0 & 1 @ 0
	my (@ports, $elementBuild, $elementType, $elementSlot, $elementPort, $elementChan, $elementLast, $elemStartSlot, $rangePorts);

	debugMsg(2,"-> generateRange input = ", \join(';', @$inlist), "\n") if $::Debug;

	foreach my $element (@$inlist) {
		if ($element =~ /^(\d{1,2})\/(\d{1,2})\/(\d{1,2})$/) { # slotX/portY/channelZ
			my ($slot, $port, $chan) = ($1, $2, $3);
			my $sep = defined $slotportSeparator ? $slotportSeparator : '/';
			my $type = 's/p';
			if (defined $elementBuild) {
				if ($type eq $elementType && $slot == $elementSlot && $port == $elementPort && $chan == $elementChan + 1) {
					$elementChan = $chan;
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
			$elementBuild = "$slot/$port/$chan";
		}
		elsif ($element =~ /^(\d{1,2})([\/:])(\d{1,2})$/) { # slotX/portY
			my ($slot, $sep, $port) = ($1, $2, $3);
			$sep = $slotportSeparator if defined $slotportSeparator;
			my $type = 's/p';
			if (defined $elementBuild) {
				if (  ($type eq $elementType && $slot == $elementSlot && $port == $elementPort + 1 && $elementChan == 0)
				   || ($type eq $elementType && $slot == $elementSlot && $port == $elementPort + 1 && $elementChan == 4)
				    ) {
					$elementPort = $port;
					$elementChan = 0;
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
	debugMsg(2,"-> generateRange output = ", \$rangePorts, "\n");
	return $rangePorts;
}

sub evalCondition { # Evaluate a condition as true or false
	# Unmodified from AcliPm::CommandProcessing
	my $condition = shift;
	my $result;
	{
		no warnings;
		no strict;
		$result = eval $condition;
	}
	if ($@) {
		(my $message = $@) =~s/;.*$//;
		debugMsg(4, "=evalCondition: error = ", \$message, "\n");
		$message =~ s/ at .+ line .+$//; # Delete file & line number info
		return (undef, $message);
	}
	else {
		$result = '' unless defined $result;
		debugMsg(4, "=evalCondition: $condition = ", \($result ? 'TRUE' : 'FALSE'), "\n");
		return ($result, undef);
	}
}


# ---------------- extract functions  ------------------

sub deconstructCmd { # Breaks up the line into composing words and populates the dictionary input hash
	# Unmodified from deconstructCmd() in AcliPm::Dictionary
	my ($inputHash, $idx, $line) = @_;
	debugMsg(1,"=deconstructCmd / line = ", \$line, "\n");
	my @hashRefList = ($inputHash);
	my @wordList = split(/\s+/, quoteCurlyMask($line, $Space));
	while (length (my $word = shift @wordList)) {
		$word = quoteCurlyUnmask($word, $Space);
		debugMsg(2,"=deconstructCmd / word = ", \$word, "\n");
		my @mandatoryWordList = grep {!/^\[[^\]]+\]$/} @wordList;
		#debugMsg(2,"=deconstructCmd / mandatoryWordList = ", \join(',', @mandatoryWordList), "\n");
		if ($word =~ s/^\[([^\]]+)\]$/$1/) { # Optional word/section in command
			my @iterHashRefList = @hashRefList;	# Make a copy from which we can iterate over
			my @sectWordList = split(/\s+/, $word); # In case section was = [word <value>]
			while (my $sectWord = shift @sectWordList) {
				debugMsg(2,"=deconstructCmd / sectWord = ", \$sectWord, "\n");
				my @newHashRefList; # Will replace @iterHashRefList for next cycle
				for my $hashRef (@iterHashRefList) {
					$hashRef->{$sectWord} = {} unless exists $hashRef->{$sectWord}; # Create new empty hash, unless one already existed
					if (@sectWordList || @wordList) { # This is not the final word in the section/command
						push(@newHashRefList, $hashRef->{$sectWord});	# Add this word's hashRef for next cycle
					}
					unless (@sectWordList || @mandatoryWordList) { # This is a valid final word in the section + command
						$hashRef->{$sectWord}->{$Marker} = $idx;	# Add marker and lookup index
					}
				}
				@iterHashRefList = @newHashRefList;
			}
			push(@hashRefList, @iterHashRefList);	# Append hasref lists following optional section
		}
		elsif ($word =~ /^\[/ || $word =~ /\]$/) { # Syntax error, come out with error
			return "Unmatched '[' ']'";
		}
		else { # Mandatory word in command
			my @newHashRefList; # Will replace @hashRefList for next cycle
			for my $hashRef (@hashRefList) {
				$hashRef->{$word} = {} unless exists $hashRef->{$word};	# Create new empty hash, unless one already existed
				if (@wordList) { # This is not the final word in the command
					push(@newHashRefList, $hashRef->{$word});	# Add this word's hashRef for next cycle
				}
				unless (@mandatoryWordList) { # This is a valid final word in the command
					$hashRef->{$word}->{$Marker} = $idx;		# Add marker and lookup index
				}
			}
			@hashRefList = @newHashRefList;
		}
	}
}

sub jsonVarHide { # Stores jsonVar and returns &x index
	my ($jsonVarsCache, $jsonVar) = @_;
	my $idx = scalar @$jsonVarsCache;
	$jsonVarsCache->[$idx] = $jsonVar;
	return "&$idx";
}

sub jsonVarRestore { # Restores jsonVar from £x index
	my ($jsonVarsCache, $idx) = @_;
	return $jsonVarsCache->[$idx];
}

sub dereferenceJson { # Adds a dictionary dereferenced translation
	# Modified from dereferenceCmd() in AcliPm::Dictionary
	my ($outputList, $idx, $cndIdxRef, $curlyCount, $line) = @_;
	$line =~ s/^\s+//; # Remove leading spaces
	$line =~ s/\s+$//; # Remove trailing spaces
	debugMsg(2,"=dereferenceJson / input line = ", \$line, "\n");
	$outputList->[$idx]->[++$$cndIdxRef] = '' if $$curlyCount == 0;	# New json assignment
	my $curliesBalance = ($line =~ tr/\{//) - ($line =~ tr/\}//); # Number of '{' minus number of '}' in line
	$$curlyCount += $curliesBalance;
	return 'Too many close curly brackets' if $$curlyCount < 0;

	# JSON syntax is very rigid; these modificatons will tolerate a more generous syntax in the encoder.in file
	argColonMask(\$line); # We use ":" in our own <arg:value1=X,value2=Y> syntax; mask that ':'
	$line =~ s/\'([\w-]+)\'(?=\s*:)/"$1"/g;			# Convert single quotes to double quotes

	# Special handling for json vars - part#1
	my $jsonVarsCache = [];
	$line =~ s/(\$$VarJson2)(?=[\s:\}]|$)/jsonVarHide($jsonVarsCache, $1)/ge;	# Stores and replaces json vars with &1, &2, etc
	#debugMsg(2,"=dereferenceJson / line2 = ", \$line, "\n");

	$line =~ s/(?<!\")([^\{\}\[\]:,\s]+)(?!\")/"$1"/g;	# Put double quotes around everything
	argColonUnmask(\$line); # Unmask our use of ':' in <arg:...>

	# Special handling for json vars - part#2
	$line =~ s/\"\K&(\d+)(?=\")/jsonVarRestore($jsonVarsCache, $1)/ge;	# Replaces json vars with original in quotes now
	#debugMsg(2,"=dereferenceJson / line3 = ", \$line, "\n");

	$line =~ s/\"(true|false|null)\"/$1/g;			# No quotes for true, false & null
	$line =~ s/:\s*\K\"(\d+)\"/$1/g;			# No quotes for numbers
	if ($outputList->[$idx]->[$$cndIdxRef] =~ /,$/ && $line =~ /^[\{\}]/) {
		chop $outputList->[$idx]->[$$cndIdxRef]; # No comma followed by curly
	}
	if (length $outputList->[$idx]->[$$cndIdxRef] && $outputList->[$idx]->[$$cndIdxRef] !~ /[\{\},]$/ && $line !~ /^[\{\}]/) {
		$outputList->[$idx]->[$$cndIdxRef] .= ','; # Must have comma if appending non curly
	}
	if (length $outputList->[$idx]->[$$cndIdxRef] && $outputList->[$idx]->[$$cndIdxRef] =~ /\}$/ && $line !~ /^[\{\}]/) {
		$outputList->[$idx]->[$$cndIdxRef] .= ','; # Must have comma if appending non curly
	}
	if (length $outputList->[$idx]->[$$cndIdxRef] && $outputList->[$idx]->[$$cndIdxRef] !~ /[\{\}]$/) {
		$outputList->[$idx]->[$$cndIdxRef] .= ' '; # Trailing space, except after curlies (looks nicer!)
	}

	# Assign/append
	$outputList->[$idx]->[$$cndIdxRef] .= $line;
	#debugMsg(4,"=dereferenceJson / JSON append = ", \$outputList->[$idx]->[$$cndIdxRef], "\n");
	return unless $$curlyCount == 0;

	# Complete JSON assignment, let's check if it reads ok in JSON
	if ($outputList->[$idx]->[$$cndIdxRef] !~ /^\{/) { # We need to have outer enclosing curlies
		$outputList->[$idx]->[$$cndIdxRef] = '{' . $outputList->[$idx]->[$$cndIdxRef] . '}';
	}
	debugMsg(1,"=dereferenceJson / parsing JSON = ", \$outputList->[$idx]->[$$cndIdxRef], "\n");
	eval {
		local $SIG{__WARN__} = sub { die shift }; # Turn every warning into an exception
		decode_json($outputList->[$idx]->[$$cndIdxRef]);
	};
	if ($@) {
		(my $message = $@) =~s/;.*$//;
		$message =~ s/,? at (?:\w:)[\\\/]?.+ line .+$//; # Delete file & line number info
		return "JSON decode error: $message";
	}
	return;
}

sub readEncoderFile { # Reads an encoder.in file into data structure
	# Modified from loadDictionary() in AcliPm::Dictionary
	my ($enc_in) = @_;
	my ($encoder, $encFile);
	%$encoder = (input => {}, output => []);	# Start it clean
	#encoder-hash = (
	#	input	=> {
	#		no	=> {},
	#		vlan	=> {
	#			create	=> {
	#				<vid:2-4050>	=> {
	#						type	=> {
	#							port	=> {x00 => <idx>},
	#							},
	#						},
	#				},
	#			delete	=> {
	#				<vid:2-4050>	=> {x00 => <idx>},
	#				},
	#			},
	#		etc..	=> {},
	#	},
	#	output	=> [
	#		[ # idx 0
	#			[json assignments#1],
	#			[json assignments#2],
	#			[etc..],
	#		],
	#		[ # idx 1
	#			[json assignments#1],
	#			[json assignments#2],
	#			[etc..],
	#		],
	#	],
	#	comment => '<comment character>'
	#	default => <idx>
	#	portall	=> 1-50
	#	contexit => <command>
	#	perlcode => flag indicating if we were able to "require" the encoder file
	#);

	# Find the encoder.in file
	foreach my $path (@AcliFilePath) {
		if (-e "$path/$enc_in") {
			$encFile = "$path/$enc_in";
			last;
		}
	}
	unless (defined $encFile) {
		quit(1, "Unable to locate encoder file $enc_in\n");
	}
	debugMsg(1,"-> Source input from encoder file $encFile\n");

	open(ENC, '<', $encFile) or do {
		quit(1, "Unable to open encoder file " . File::Spec->canonpath($encFile) . "\n");
	};
	print "Loading encoder file: " . File::Spec->rel2abs($encFile) . "\n";

	my $lineNumber = 0;
	my $outputIndex = -1;
	my $conditionIndex = -1;
	my $curliesCount = 0;
	my $synErr;
	my $skipSchemaLines;
	while (<ENC>) {
		chomp;
		s/\x0d+$//g; # Remove trailing CRs (DOS files read on Unix OS)
		$lineNumber++;
		next if /^\s*$/; # skip empty lines
		next if /^\s*#/; # skip comment lines
		next if /^package .+;$/; # Skip the package line
		next if /^my \$Version = .+;$/; # Skip the version line
		next if /^=ignore/; # Skip the Perl marker which tells Perl to ingnore lines
		last if /^=cut/; # This Perl marker tells us where Perl code begins, and thus where the encoder data ends
		$_ = quoteCurlyMask($_, '#'); # Mask comment character in case it appears inside quotes or brackets
		s/\s+#.*$//; # Remove comments on same line
		$_ = quoteCurlyUnmask($_, '#'); # Unmask
		/^SCHEMA_END\s*$/ && do {
			$skipSchemaLines = 0;
			next;
		};
		next if $skipSchemaLines;
		/^SCHEMA_BEGIN\s*$/ && do {
			$skipSchemaLines = 1;
			next;
		};
		/^COMMENT_LINE\s*=\s*(?|"(.)"|'(.)')\s*$/ && do {
			$encoder->{comment} = $1;
			next;
		};
		/^PORT_ALL\s*=\s*1\s*-\s*(\d\d?)\s*$/ && do {
			$encoder->{portall} = $1;
			next;
		};
		/^CLEAR_PERSIST_CONTEXT\s*=\s*(?|"([\w-]+)"|'([\w-]+)')\s*$/ && do {
			$encoder->{contexit} = $1;
			next;
		};
		/^DEFAULTS\s*$/ && do {
			$encoder->{default} = ++$outputIndex;
			next;
		};
		/^[^\s\{\}]/ && do {
			if ($curliesCount == 0) {
				$synErr = deconstructCmd($encoder->{input}, ++$outputIndex, $_);
				$conditionIndex = -1;
				$curliesCount = 0;
				next unless $synErr;
			}
			else {
				$synErr = 'cannot process new command if previous json is incomplete'
			}
		};
		/^[\s\{\}]/ && do {
			if ($outputIndex >= 0) {
				$synErr = dereferenceJson($encoder->{output}, $outputIndex, \$conditionIndex, \$curliesCount, $_);
				next unless $synErr;
			}
			else {
				$synErr = 'json decode requires definition first'
			}
		};
		print "- syntax error on line $lineNumber" . (defined $synErr ? ": $synErr" : '') . "\n";
		close ENC;
		quit(1, "Unable to read encoder file " . File::Spec->canonpath($encFile) . "\n");
	}
	close ENC;

	# Here we try and readin the encoder file as if it was a Perl module; this will allow us to run the Perl post processing code
	$encoder->{perlcode} = eval { require $ScriptDir . $enc_in };

	print Dumper($encoder) if $Debug & 8;
	return $encoder;
}

sub readEncoderFile2 { # Reads encoder c2j file and convert to decoder j2c file
	# Modified version of readEncoderFile for makej2c mode
	my ($enc_in, $require) = @_;
	my ($encoder, $encFile);
	%$encoder = (input => [], output => []);	# Start it clean
	#encoder-hash = (
	#	input	=> [
	#			cmd1,
	#			cmd2,
	#			...
	#		]
	#	},
	#	output	=> [
	#		[ # idx 0	--> maps to cmd1
	#			[json assignments#1],
	#			[json assignments#2],
	#			[etc..],
	#		],
	#		[ # idx 1	--> maps to cmd2
	#			[json assignments#1],
	#			[json assignments#2],
	#			[etc..],
	#		],
	#	],
	#	perlcode => flag indicating if we were able to "require" the encoder file
	#);

	# Find the encoder.in file
	foreach my $path (@AcliFilePath) {
		if (-e "$path/$enc_in") {
			$encFile = "$path/$enc_in";
			last;
		}
	}
	unless (defined $encFile) {
		quit(1, "Unable to locate encoder file $enc_in\n");
	}
	debugMsg(1,"-> Source input from encoder file $encFile\n");

	open(ENC, '<', $encFile) or do {
		quit(1, "Unable to open encoder file " . File::Spec->canonpath($encFile) . "\n");
	};
	print "Loading encoder file: " . File::Spec->rel2abs($encFile) . "\n";

	my $lineNumber = 0;
	my $outputIndex = -1;
	my $conditionIndex = -1;
	my $curliesCount = 0;
	my $synErr;
	my $skipSchemaLines;
	my $skipDefaults;
	while (<ENC>) {
		chomp;
		s/\x0d+$//g; # Remove trailing CRs (DOS files read on Unix OS)
		$lineNumber++;
		next if /^\s*$/; # skip empty lines
		next if /^\s*#/; # skip comment lines
		next if /^package .+;$/; # Skip the package line
		next if /^my \$Version = .+;$/; # Skip the version line
		next if /^=ignore/; # Skip the Perl marker which tells Perl to ingnore lines
		last if /^=cut/; # This Perl marker tells us where Perl code begins, and thus where the encoder data ends
		$_ = quoteCurlyMask($_, '#'); # Mask comment character in case it appears inside quotes or brackets
		s/\s+#.*$//; # Remove comments on same line
		$_ = quoteCurlyUnmask($_, '#'); # Unmask
		/^SCHEMA_END\s*$/ && do {
			$skipSchemaLines = 0;
			next;
		};
		next if $skipSchemaLines;
		/^SCHEMA_BEGIN\s*$/ && do {
			$skipSchemaLines = 1;
			next;
		};
		/^COMMENT_LINE\s*=\s*(?|"(.)"|'(.)')\s*$/ && do {
			next;
		};
		/^PORT_ALL\s*=\s*1\s*-\s*(\d\d?)\s*$/ && do {
			next;
		};
		/^DEFAULTS\s*$/ && do {
			$skipDefaults = 1;
			next;
		};
		/^[^\s\{\}]/ && do {
			$skipDefaults = 0;
			if ($curliesCount == 0) {
				push(@{$encoder->{input}}, $_);
				debugMsg(1,"=readEncoderFile2 / inline = ", \$_, "\n");
				++$outputIndex;
				$conditionIndex = -1;
				$curliesCount = 0;
				next unless $synErr;
			}
			else {
				$synErr = 'cannot process new command if previous json is incomplete'
			}
		};
		/^[\s\{\}]/ && do {
			next if $skipDefaults;
			if ($outputIndex >= 0) {
				$synErr = dereferenceJson($encoder->{output}, $outputIndex, \$conditionIndex, \$curliesCount, $_);
				next unless $synErr;
			}
			else {
				$synErr = 'json decode requires definition first'
			}
		};
		print "- syntax error on line $lineNumber" . (defined $synErr ? ": $synErr" : '') . "\n";
		close ENC;
		quit(1, "Unable to read encoder file " . File::Spec->canonpath($encFile) . "\n");
	}
	close ENC;

	# Here we try and read in the encoder file as if it was a Perl module; this will allow us to run the Perl post processing code
	$encoder->{perlcode} = eval { require $ScriptDir . $enc_in } if $require;

	print Dumper($encoder) if $Debug & 8;
	return $encoder;
}


sub argRegexVar { # Produce a regex and return the variable name for the various <argument:formats>
	# Modified from argRegexVar() in AcliPm::Dictionary
	my $arg = shift;
	my $varTable = 0;
	my ($regex, $varName, $min, $max, $list);
	$arg =~ /<(!?)([^>]+)>/ && do {
		my ($permanentArg, $argSection) = ($1, $2);
		$varTable = 1 if $permanentArg;
		if ($argSection =~ /^ports?$/) {
			$varName = lc $argSection;
			$regex = $PortsRegex;
			debugMsg(4, "=argRegexVar : arg = $arg / port-regex >", \$regex, "< / varName = $varName\n");
		}
		elsif ($argSection =~ /^ip$/) {
			$varName = lc $argSection;
			$regex = '^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$';
			debugMsg(4, "=argRegexVar : arg = $arg / ip-address >", \$regex, "< / varName = $varName\n");
		}
		elsif ($argSection =~ /^ip:mask$/) {
			$varName = lc $argSection;
			$regex = '^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/(\d+)$';
			debugMsg(4, "=argRegexVar : arg = $arg / ip:mask >", \$regex, "< / varName = $varName\n");
		}
		elsif ($argSection =~ /^ipv6$/) {
			$varName = lc $argSection;
			$regex = '^((?:[\da-fA-F]{1,4}:){7}[\da-fA-F]{1,4})$';
			debugMsg(4, "=argRegexVar : arg = $arg / ipv6-address >", \$regex, "< / varName = $varName\n");
		}
		elsif ($argSection =~ /^ipv6:mask$/) {
			$varName = lc $argSection;
			$regex = '^((?:[\da-fA-F]{1,4}:){7}[\da-fA-F]{1,4}|(?:[\da-fA-F]{1,4}:){0,6}:)/(\d+)$';
			debugMsg(4, "=argRegexVar : arg = $arg / ipv6:mask >", \$regex, "< / varName = $varName\n");
		}
		elsif ($argSection =~ /^([\d\w\-_]+):(\d+)-(\d+)(,)?$/) {
			($varName, $min, $max, $list) = ($1, $2, $3, $4);
			if ($list) {
				$regex = '^(\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*)$';
			}
			else {
				$regex = '^(\d+)$';
			}
			debugMsg(4, "=argRegexVar : arg = $arg / number-regex >", \$regex, "< / varName = $varName\n");
		}
		elsif ($argSection =~ /^([\d\w\-_]+):(\*)$/) {
			$varName = $1;
			$regex = '(.*)'; # Match anything (but double quotes, as we add them later)
			debugMsg(4, "=argRegexVar : arg = $arg / glob-regex >", \$regex, "< / varName = $varName\n");
		}
		elsif ($argSection =~ /^([\d\w\-_]+):((?:[^,]+,)*.+)$/) {
			$varName = $1;
			$regex = [split(',', $2)];
			debugMsg(4, "=argRegexVar : arg = $arg / list-regex >", \join('.', @$regex), "< / varName = $varName\n");
		}
		elsif ($argSection =~ /^([\d\w\-_]+)$/) {
			$varName = $1;
			$regex = '^(?|\'([^\']+)\'|\"([^\"]+)\"|(\S+))$';
			debugMsg(4, "=argRegexVar : arg = $arg / anytext-regex >", \$regex, "< / varName = $varName\n");
		}
	};
	return ($regex, $varName, $varTable, $min, $max);
}


sub matchMostRecentPersistentVar { # Matches most recently set persistent !var
	my ($available, $varHash) = @_;
	my $regexPersArgs = qr/![\w-]*/;
	my @persistArgs = grep(/$regexPersArgs/, @$available);
	for my $persistArg (@persistArgs) {
		return $persistArg if $persistArg eq '!' && !defined $varHash->[2];
		return $persistArg if defined $varHash->[2] && $persistArg eq $varHash->[2];
	}
	return;
}


sub matchEncoderWord { # Matches a word entered by user with a list of available encoder next valid words/arguments
	# Modified from matchDictWord() in AcliPm::Dictionary
	my ($entered, $available, $varHash, $portall) = @_;
	return ([]) unless length $entered && $entered ne '?';
	my @match;

	# Split the available into <arguments> and fixed words 
	my $regexArg = qr/<!?[^>]+>/;
	my @arguments = grep(/$regexArg/, @$available);
	my @cmdwords = grep(!/$regexArg/, @$available);

	# Check if we have a full match of fixed word
	my $regexFull = qr/^\Q$entered\E$/i;
	@match = grep(/$regexFull/, @cmdwords);
	return (\@match) if scalar @match == 1;

	# If not, then try a partial match
	my $regexPart = qr/^\Q$entered\E/i;
	@match = grep(/$regexPart/, @cmdwords);
	return (\@match) if @match; # Return the list, whatever it may be

	# Else, check if we match the <arguments>
	for my $arg (@arguments) {
		my ($regex, $varName, $varTable, $min, $max) = argRegexVar($arg);
		if (ref($regex) eq 'ARRAY') { # Regex is infact a listRef
			# Check if we have a full match of fixed word
			@match = grep(/$regexFull/, @$regex);
			if (scalar @match == 1) {
				$varHash->[$varTable]->{$varName} = $match[0];
				$varHash->[2] = '!'.$varName if $varTable == 1;
				debugMsg(4, "=matchEncoderWord : input variable (array-full-match) $varTable:$varName = ", \$varHash->[$varTable]->{$varName}, "\n");
				return (\@match, $arg);
			}
			# If not, then try a partial match
			@match = grep(/$regexPart/, @$regex);
			if (scalar @match == 1) {
				$varHash->[$varTable]->{$varName} = $match[0];
				$varHash->[2] = '!'.$varName if $varTable == 1;
				debugMsg(4, "=matchEncoderWord : input variable (array-part-match) $varTable:$varName = ", \$varHash->[$varTable]->{$varName}, "\n");
			}
			return (\@match, $arg) if @match; # Return the list, whatever it may be
		}
		elsif ($entered =~ /$regex/) { # Else is a regex
			my ($match, $match2) = ($1, $2);
			my $globVar = "$varTable:$varName" if $regex eq '(.*)';
			if ($varName =~ /^port(s)?$/) {
				my $many = $1;
				my $portList = generatePortList($match, $portall);
				next if $portList =~ /,/ && !$many;
#				$portList = mapPortList($dictionary->{prtmap}, $portList) if defined $dictionary->{prtinp};
				$match = generateRange($portList, 1);
#				$match = $portList;
			}
			elsif (defined $min && defined $max) {
				my $valListRef = generateVlanList($match, 1);
				next if grep {$_ < $min} @$valListRef;
				next if grep {$_ > $max} @$valListRef;
				$match = join(',', @$valListRef);
			}
			if ($varName =~ /^(\w+):(\w+)$/) {
				my ($var1, $var2) = ($1, $2);
				$varHash->[$varTable]->{$var1} = $match;
				if ($varName eq 'ip:mask') {
					my @bytes = unpack 'CCCC', pack 'N', 2**32 - 2**(32 - $match2);
					$varHash->[$varTable]->{$var2} = join '.', @bytes; # 255.255.x.0
					$varHash->[$varTable]->{masklen} = $match2;
				}
				else { # for ipv6:mask fall through
					$varHash->[$varTable]->{$var2} = defined $match2 ? $match2 : '';
				}
			}
			else {
				$varHash->[$varTable]->{$varName} = $match;
				$varHash->[2] = '!'.$varName if $varTable == 1;
			}
			debugMsg(4, "=matchEncoderWord : input variable (regex) $varTable:$varName = ", \$varHash->[$varTable]->{$varName}, "\n");
			return ([$entered], $arg, $globVar);
		}
	}

	# If nothing matches
	return ([]);
}


sub encoderMatch { # Searches for command into dictionary (modified tabExpand)
	# Modified from dictionaryMatch() in AcliPm::Dictionary
	# If it's recognized it is expanded and returned with a trailing space; otherwise nothing is returned
	# Returns: (
	#		parsed command if command complete, empty string otherwise,
	#		index if parsed command complete, undef otherwise,
	#		arg var ref if parsed command complete, undef otherwise,
	#		list ref of avail syntax if parsed command incomplete, undef otherwise
	#	)
	my ($cmdHash, $cliCmd, $varHash, $portall, $globVar) = @_;
	my $idx;

	debugMsg(4, "=encoderMatch : called with >$cliCmd<\n");
	# Process the input command to clean it up
	$cliCmd =~ s/\s+$//;			# Remove trailing spaces
	$cliCmd =~ s/^\s+//;			# Remove leading spaces
	$cliCmd =~ s/([^\s@])\?$/$1 ?/;		# If command ends with ? make sure space before ? (except for @?)
	$cliCmd = quoteCurlyMask($cliCmd, ' ');	# Mask spaces inside quotes
	my @cliCmd = split(/\s+/, $cliCmd);	# Split it into an array
	@cliCmd = map { quoteCurlyUnmask($_, ' ') } @cliCmd;	# Needs to re-assign, otherwise quoteCurlyUnmask won't work
	$cliCmd[0] = '' unless $cliCmd[0];	# First word must be defined
	debugMsg(4, "=encoderMatch : command split into array : ", \join(',', @cliCmd), "\n");

	my $cmdWord = shift @cliCmd;
	my ($parsed, $dictEntry) = ('', '');
	while (length $cmdWord && ref $cmdHash eq 'HASH') {
		my ($cmdList, $cmdNextHash, $globVar) = matchEncoderWord($cmdWord, [keys %$cmdHash], $varHash, $portall);
		debugMsg(4, join('', "=encoderMatch : number of matched commands = ", scalar @$cmdList, " / list = ", join(',', @$cmdList), "\n"));
		last unless @$cmdList; # No match, come out
		if (defined $globVar) { # Glob variable, we suck rest of input command int var
			my ($varTable, $varName) = split(':', $globVar);
			$varHash->[$varTable]->{$varName} .= ' ' . join(' ', @cliCmd);
			debugMsg(4, "=encoderMatch : remaining globbed by var '$globVar': >", \$varHash->[$varTable]->{$varName}, "<\n");
			$cmdHash = $cmdHash->{$cmdNextHash};
			@cliCmd = (); # Empty it
			$cmdWord = '';
			last;
		}
		if (scalar @$cmdList == 1) { # Exact (single) command matched; continue while loop
			$cmdWord = $cmdList->[0];
			$parsed .= (length($parsed) ? ' ':'') . $cmdWord;
			$dictEntry .= ' ' if length $dictEntry;
			if (defined $cmdNextHash) { # We matched an <arg:values>
				$cmdHash = $cmdHash->{$cmdNextHash};
				$cmdNextHash =~ s/^<[\d\w\-_]+\K:[^:]+(?=>$)//; # Remove :values and leave <arg>
				$dictEntry .= $cmdNextHash;
			}
			else {
				$cmdHash = $cmdHash->{$cmdWord};
				$dictEntry .= $cmdWord;
			}
			$cmdWord = shift @cliCmd;
			$cmdWord = '' unless defined $cmdWord;
		}
		else { # More than one match; return the list
			debugMsg(4, "=encoderMatch - more than 1 match : returning null string\n");
			return ('', undef, undef, undef, $cmdList);
		}
	}
	debugMsg(4, "=encoderMatch : parsed command : >$parsed<\n");
	debugMsg(4, "=encoderMatch : dictionary entry : >$dictEntry<\n");
	debugMsg(4, "=encoderMatch : residual cmdWord : >", \$cmdWord, "<\n");
	unless (length $parsed) { # If no match at all come out
		debugMsg(4, "=encoderMatch - no match at all\n");
		return ('', undef, undef, undef, undef);
	}
	my $remaining = join(' ', $cmdWord, @cliCmd);
	debugMsg(4, "=encoderMatch : remaining unmatched input : >", \$remaining, "<\n");
	debugMsg(4, "=encoderMatch : what cmd points to in hash structure(cmdHash) : >", \$cmdHash, "<\n");
	print Dumper($cmdHash) if $Debug & 8;

	# If all words used, maybe we have a !var persistent condition to match, in which case hash pointer is updated
	my $cmdNextHash = matchMostRecentPersistentVar([keys %$cmdHash], $varHash) unless length $cmdWord;
	if (defined $cmdNextHash) {
		$cmdHash = $cmdHash->{$cmdNextHash};
		debugMsg(4, "=encoderMatch : what cmd points to in hash structure(cmdHash) after !var match : >", \$cmdHash, "<\n");
		print Dumper($cmdHash) if $Debug & 8;
	}

	$idx = $cmdHash->{$Marker} if exists $cmdHash->{$Marker};
	debugMsg(4, "=encoderMatch : index = >$idx<\n") if defined $idx;
	if (defined $idx && length $cmdWord) { # Complete match, optional keywords remain
		if ($cmdWord eq '?') { # We have possible optional words other then just the marker
			debugMsg(4, "=encoderMatch - complete match but with optional keywords remaining\n");
			return ($parsed, undef, undef, undef, [keys %$cmdHash]);
		}
		else {
			debugMsg(4, "=encoderMatch - complete match but with excessive input from user\n");
			return ('', undef, undef, undef, undef);
		}
	}
	if (length $cmdWord) { # Partial match, provide available syntax list
		if ($cmdWord eq '?') { # We have possible optional words other then just the marker
			debugMsg(4, "=encoderMatch - partial match but with optional keywords remaining\n");
			return ('', undef, undef, undef, [keys %$cmdHash]);
		}
		else {
			debugMsg(4, "=encoderMatch - partial match but with excessive input from user\n");
			return ('', undef, undef, undef, undef);
		}
	}
	debugMsg(4, "=encoderMatch - complete and full match\n");
	return ($parsed, $idx, undef, $dictEntry, undef);
}

sub deRefEncVar { # Replace argument variables
	# Modified from deRefDictVar() in AcliPm::Dictionary
	my ($inputVars, $varField, $varAll, $varName, $valueMods) = @_;
	my $replValue;
	$replValue = $inputVars->[0]->{$varName} if defined $inputVars->[0]->{$varName};
	$replValue = $inputVars->[1]->{$varName} if !defined $replValue && defined $inputVars->[1]->{$varName};
	$replValue = '' if defined $replValue && $replValue eq '""';
	if (defined $replValue) { # Value is available; either was entered in the command line or from permanent table [1]
		debugMsg(4,"=deRefEncVar: De-RefVar: <$varName> / >$varField< / replValue = >", \$replValue, "<\n");
		if (length $valueMods) {
			if ($valueMods eq ':%') {
				$replValue = 'true';
			}
			elsif ($valueMods eq ':!%') {
				$replValue = 'false';
			}
			else {
				$valueMods =~ s/^://;
				debugMsg(4,"=deRefEncVar: valueMods: >$valueMods<\n");
				my %modHash = split(/\s*[=,]\s*/, $valueMods);
				$replValue = $modHash{$replValue} if exists $modHash{$replValue};
				debugMsg(4,"=deRefEncVar: De-RefVar modified: $replValue\n");
			}
		}
		$varField =~ s/\Q<$varAll>\E/$replValue/;
		debugMsg(4,"=deRefEncVar: to >$varField<\n");
		return $varField;
	}
	# Mandatory or optional field, replace with nothing...
	return 'false' if defined $valueMods && $valueMods eq ':%';
	return 'true' if defined $valueMods && $valueMods eq ':!%';
	return 'null';
}

sub nextHashListRef { # Returns hashref pointer to next key/index (handles both array & hash
	my ($hashref, $key) = @_;
	if ($key =~ /^\[(\d+)\]$/) {
		return unless exists $hashref->[$1];
		return $hashref->[$1];
	}
	else {
		return unless exists $hashref->{$key};
		return $hashref->{$key};
	}
}

sub deRefJsonVar { # Replace json variable in json encoding
	my ($encodedData, $jVar) = @_;

	my ($synErr, $keyChain) = extractKeyChain($jVar);
	return "£$synErr£" if $synErr;

	debugMsg(1,"-> deRefJsonVar input jsnoVar: ", \$jVar, "\n");
	my $jsonVars = {};
	my $hashref = $encodedData;
	KEYPARSE: for my $i (0 .. $#{$keyChain}) {
		my $key = $keyChain->[$i];
		if ($key =~ /,/) { # We only support this for hash keys, for now
			@{$jsonVars->{x}} = split(',', $key);
			$keyChain->[$i] = 'x';
			last;
		}
		$hashref = nextHashListRef($hashref, $key);
		return "£variable $jVar key '$key' not found in extracted data£" unless defined $hashref;
	}

	# Next assign values to jVar in the $jsonVars structure as we go
	if (defined $jsonVars->{x}) { # If an x range is set, we will need to calculate as many values for each var
		EACHX: for my $i (0 .. $#{$jsonVars->{x}}) {
			my $x = $jsonVars->{x}->[$i];
			my $hashref = $encodedData;
			for my $k (0 .. $#{$keyChain}) {
				my $key = $keyChain->[$k];
				if ($key eq 'x') {
					return "£variable $jVar not a hash for x=$x in input json/yaml datafile£" unless ref($hashref) eq 'HASH';
					if ($k == $#{$keyChain}) {
						$jsonVars->{$jVar}->{values}->[$i] = $x;
						next EACHX;
					}
					$hashref = nextHashListRef($hashref, $x);
					return "£variable $jVar key '$x' not found in extracted data£" unless defined $hashref;
					next;
				}
				unless (exists $hashref->{$key}) { # If key does not exist
					$jsonVars->{$jVar}->{values}->[$i] = undef;
					next EACHX;
				}
				$hashref = nextHashListRef($hashref, $key);
				return "£variable $jVar key '$key' not found in extracted data£" unless defined $hashref;
			}
			if (ref($hashref) eq 'ARRAY') {
				my $list = join(',', @$hashref);
				my $portlist = generateRange($list, 1);
				$jsonVars->{$jVar}->{values}->[$i] = $portlist ? $portlist : $list;
				next;
			}
			return "£no scalar value for variable $jVar x=$x in input json/yaml datafile£" if ref($hashref);
			$jsonVars->{$jVar}->{values}->[$i] = $hashref;
		}
	}
	else { # Each var has one value only
		my $hashref = $encodedData;
		for my $key (@$keyChain) {
			$hashref = nextHashListRef($hashref, $key);
			return "£variable $jVar key '$key' not found in extracted data£" unless defined $hashref;
		}
		return "£no scalar value for variable $jVar in input json/yaml datafile£" if ref($hashref);
		$jsonVars->{$jVar}->{values}->[0] = $hashref;
	}
	print Dumper($jsonVars) if $Debug & 8;
	return 'null' unless @{$jsonVars->{$jVar}->{values}}; # Might never happen..
	my $jsonVarOut = join(',', @{$jsonVars->{$jVar}->{values}});
	debugMsg(1,"-> deRefJsonVar output jsnoVar: ", \$jsonVarOut, "\n");
	return '"'.$jsonVarOut.'"';
}

sub expandHash { # Expand hash keys which are comma lists
	my $hashRef = shift;
	for my $key (keys %$hashRef) {
		#debugMsg(1,"=expandHash - key: ", \$key, "\n");
		my $portList = generatePortList($key);
		my @list = $portList ? split(',', $portList) : split(',', $key);
		next unless $#list;
		# If we get here, we have a key as a list
		for my $elem (@list) {
			$hashRef->{$elem} = dclone $hashRef->{$key}; # Deep Copy
		}
		delete $hashRef->{$key};
		return;
	}
	# If we did not find any key lists at this level, recursively try next levels
	for my $key (keys %$hashRef) {
		if (ref($hashRef->{$key}) eq 'HASH') {
			expandHash($hashRef->{$key});
		}
		elsif (ref($hashRef->{$key}) eq 'ARRAY' && !ref($hashRef->{$key}->[0])) {
			if (my $portList = generatePortList($hashRef->{$key}->[0])) {
				my @list = $portList ? split(',', $portList) : split(',', $key);
				$hashRef->{$key} = \@list;
			}
		}
	}
	return;
}

sub encodeData { # Adds to the encoded data structure new json assignments resulting from input command lookup (or defaults)
	my ($encodedData, $listRef, $lineNumber, $inputVars) = @_;
	my $expression;
	$lineNumber = 0 unless defined $lineNumber;
	for my $c (0 .. $#{$listRef}) { # For every json assignment
		$expression = $listRef->[$c];
		if (defined $inputVars) {
			debugMsg(1,"=encodeData - expression before <var> repl: >$expression<\n");
			$expression =~ s/\s*\K(\"$ArgJson\")/deRefEncVar($inputVars, $1, $2, $3, $4)/ge; # <var> replacements
			$expression =~ s/\s*\K(\{$ArgJson\})/deRefEncVar($inputVars, $1, $2, $3, $4)/ge; # <var> replacements
			$expression =~ s/\s*\K(\[$ArgJson\])/deRefEncVar($inputVars, $1, $2, $3, $4)/ge; # <var> replacements
			my $expressionCopy = $expression;
			$expression =~ s/\"\$($VarJson3)\"/deRefJsonVar($encodedData, $1)/ge; # json var replacements
			if ($expression =~ /£([^£]+)£/) {
				print " - Line number $lineNumber using json: $expressionCopy\n   $1\n";
				next;
			}
			$expression =~ s/\"(true|false|null)\"/$1/g;	# No quotes for true, false & null
			$expression =~ s/:\s*\K\"(\d+)\"/$1/g;		# No quotes for numbers
			debugMsg(1,"=encodeData - expression after <var> repl: >$expression<\n");
		}
		# Create hash
		my $hash;
		eval {
			local $SIG{__WARN__} = sub { die shift }; # Turn every warning into an exception
			$hash = decode_json($expression);
		};
		if ($@) {
			(my $message = $@) =~s/;.*$//;
			$message =~ s/,? at (?:\w:)[\\\/]?.+ line .+$//; # Delete file & line number info
			quit(1, "Error on line number $lineNumber while encoding: $expression\nJSON error: $message");
		}
		# Expand hash keys which are comma lists
		expandHash($hash);

		# Merge together
		$encodedData = \%{ $HashMerge->merge( $encodedData, $hash ) };
	}
	return $encodedData;
}

sub encodeInputConfig { # Encode input config file using provided encoder
	my ($encoder, $infile) = @_;
	my $encodedData = {};

	unless (-e $infile) {
		quit(1, "Unable to locate input config file $infile\n");
	}
	open(CONFIG, '<', $infile) or do {
		quit(1, "Unable to open config file " . File::Spec->canonpath($infile) . "\n");
	};
	print "Loading config file: " . File::Spec->rel2abs($infile) . "\n";

	# Set up the DEFAULTS
	$encodedData = encodeData($encodedData, $encoder->{output}->[$encoder->{default}]) if exists $encoder->{default};

	# Read config file line by line
	my $lineNumber = 0;
	my $inputVars = [];
	# [0] = {hash of variables flushed at every command}
	# [1] = {hash of persistent variables}
	# [2] = <name of last set persistent variables>
	while (<CONFIG>) {
		chomp;
		$lineNumber++;
		next if /^\s*$/; # Empty line
		# Verify for comment line first
		if (defined $encoder->{comment} && /^\Q$encoder->{comment}/) {
			debugMsg(1,"=encodeInputConfig: comment line :>", \$_, "<\n");
			next;
		}
		$inputVars->[0] = {};	# Wipe table 0; not table 1 (permanent args)
		debugMsg(1,"\n=encodeInputConfig - input line: >", \$_, "<\n");
		my ($enccmd, $idx) = encoderMatch($encoder->{input}, $_, $inputVars, $encoder->{portall});
		#             ^ Index into dictionary output
		#   ^ Full expanded command; can be used for tab expansion

		if ($enccmd eq $encoder->{contexit}) {
			debugMsg(1,"\n=encodeInputConfig - ", \$enccmd, " - clear last persistent context variable\n");
			$inputVars->[2] = undef;
		}

		unless (length $enccmd && defined $idx) {
			print "Warning: no encoding for line $lineNumber: $_\n";
			next;
		}

		# Add to encoded data structure
		$encodedData = encodeData($encodedData, $encoder->{output}->[$idx], $lineNumber, $inputVars);
	}
	print Dumper($encodedData) if $Debug & 8;

	# If we have post-processing Perl code in the encoder file, run it now
	debugMsg(1,"\n=encodeInputConfig - Encoder::run\n");
	Encoder::run($encodedData) if $encoder->{perlcode};

	return $encodedData;
}

sub saveEncodedConfig { # Generates output json/yaml file with encoded data extracted from config file
	my ($encodedData, $fileformat, $infile) = @_;
	my $outfile = $infile . '.' . $fileformat;

	open(OUT, '>', $outfile) or do {
		quit(1, "Unable to open output file " . File::Spec->canonpath($outfile) . "\n");
	};
	if ($fileformat eq 'json') {
		print OUT $JsonCoder->encode($encodedData); # Pretty format
	}
	else { # YAML
		local $YAML::XS::Boolean = "JSON::PP";
		print OUT Dump($encodedData);
	}
	close OUT;
	print "Saved encoded config to file: " . File::Spec->rel2abs($outfile) . "\n";
}


# ---------------- makecfg functions  ------------------

sub checkCondition { # Removes &IF: condition from line
	my $line = shift;
	my ($workingLine, $condition) = split(/&IF:/, $line);
	if (defined $condition) {
		$workingLine =~ s/\s+$//;
		$condition =~ s/^\s+//;
		$condition =~ s/\s+$//;
	}
	return ($workingLine, $condition);
}

sub extractKeyChain { # Given a variable from encoder.out file, produces list of hash key
	my $jVar = shift;
	my $jVarClip = $jVar;
	my @keyChain;
	my $xPresent = 0;

	return "Unexpected variable syntax: $jVar" unless $jVarClip =~ s/^([\w-]+)//;
	push(@keyChain, $1);
	while ($jVarClip =~ s/^(?|\{([\w\.:-]+)\}|(\[(?:x|\d+)\]))//) {
		$xPresent = 1 if $1 eq 'x' || $1 eq '[x]';
		push(@keyChain, $1);
	}
	return "Invalid Variable syntax: $jVar" if length $jVarClip;
	debugMsg(1,"-> extractKeyChain / X present = $xPresent / $jVar = ", \join(",", @keyChain), "\n");
	return (undef, \@keyChain, $xPresent);
}

sub replaceJsonVar { # Replaces json $variable with indexed value x
	my ($jsonVars, $x, $jVar, $prematch, $postmatch, $evalFlag) = @_;
	$prematch = '' unless defined $prematch;
	$postmatch = '' unless defined $postmatch;
	debugMsg(4,"-> replaceJsonVar input = >", \$jVar, "<\n");
	my $value = $jsonVars->{$jVar}->{values}->[$x];

	debugMsg(4,"-> replaceJsonVar value = >", \$value, "<\n");
	if (defined $value) {
		if ($postmatch =~ s/^%://) {
			debugMsg(4,"-> replaceJsonVar postmatch %: = >", \$postmatch, "<\n");
			my @boolValues = split(',', $postmatch);
			return $prematch . $boolValues[0] if $value; # True
			return $prematch . $boolValues[1] if defined $boolValues[1]; # False
			return ''; # False and no 2nd value
		}
		$value = '"' . $value . '"' if $value =~ /\s/ || !length $value || $evalFlag;
		return length $prematch ? join('', $prematch, $value, $postmatch) : $value;
	}
	return '""' if $evalFlag;
	return length $prematch || $evalFlag ? '' : '££undef££'; # Optional = delete segment; mandatory = return marker to skip line
}

sub replaceOptCond { # Replaces optional section [ blah &IF: eval ]
	my ($jsonVars, $x, $keepPart, $evalPart) = @_;
	debugMsg(4,"-> replaceOptCond eval part bef = >", \$evalPart, "<\n");
	$evalPart =~ s/\$($VarJson)(?=\s|$)/replaceJsonVar($jsonVars, $x, $1, undef, undef, 1)/ge;
	debugMsg(4,"-> replaceOptCond eval part aft = >", \$evalPart, "<\n");
	my ($result, $evalError) = evalCondition($evalPart);
	return $result ? $keepPart : '';
}


sub parseSectionToConfig { # Processes a line section from the encoder.out and produses ASCII config lines from encoded coanfig data
	my ($lineSection, $encodedData, $asciiConfigRef, $portRangeMode, $slotPortSep) = @_;
	my $jsonVars = {};
	# $jsonVars = {
	#	xrange			= [10,11,12],
	#	vlan{x}			= {
	#					mandatory = 1,
	#					values = [10,11,12],
	#				},
	#	vlan{x}{instance}	= {
	#					mandatory = 1,
	#					values = [0, 0, 0],
	#				},
	#	vlan{y}{isid}{x}	= {
	#					mandatory = 1,
	#					values = [20010, 20011, undef],
	#				},
	#	vlan{x}{name}		= {
	#					optional = 1,
	#					values = ['name1',undef,'name3'],
	#				},
	#	ip{route}[x]{route}	= {
	#					optional = 1,
	#					values = ['name1',undef,'name3'],
	#				},
	#	x			= { # Only for [x] arrays, list of indexes
	#					values = [1,2,3,4,5...],
	#				},
	# }

	debugMsg(1,"-> parseSectionToConfig input section:\n", \join("\n", @$lineSection), "\n\n");
	my (%optional, %mandatory);
	foreach my $line (@$lineSection) {
		my $trashLine = $line;
		map {$optional{$_}  = {optional  => 1}} ($trashLine =~ /\[[^\[\]]*\$($VarJson)(?:[\s%][^\[\]]*)?\]/g);	# First get the optional vars
		$trashLine =~ s/\[[^\[\]]*\$($VarJson)(?:[\s%][^\[\]]*)?\]//g;						# Delete all optional vars
		map {$mandatory{$_} = {mandatory => 1}} ($trashLine =~ /\$($VarJson)(?=[\s%]|$)/g);			# Then remove mandatory vars
	}
	$jsonVars = \%{ $HashMerge->merge( \%optional, \%mandatory ) };
	print Dumper($jsonVars) if $Debug & 8;

	# First run through mandatory variables, to see if x is in use, in which case x range must be set
	MPREPARSE: for my $jVar (keys %$jsonVars) {
		next unless $jsonVars->{$jVar}->{mandatory};
		next if $jVar eq 'x';
		my ($synErr, $keyChain, $xPresent) = extractKeyChain($jVar);
		return $synErr if $synErr;
		next unless $xPresent;
		# We have a json var using x
		my $hashref = $encodedData;
		my ($xhashref, $xlistref, $istart);
		KEYPARSE: for my $i (0 .. $#{$keyChain}) {
			my $key = $keyChain->[$i];
			if ($key eq '[x]') {
				unless (ref($hashref) eq 'ARRAY') {
					debugMsg(1,"-> parseSectionToConfig first run: $jVar not a list for x in input json/yaml datafile\n");
					return;
				}
				@{$jsonVars->{x}->{values}} = 1 .. scalar @$hashref;
				if ($i == $#{$keyChain}) {
					@{$jsonVars->{xrange}} = @$hashref;
					last MPREPARSE;
				}
				else {
					$xlistref = $hashref;
					$istart = $i + 1;
					last KEYPARSE;
				}
			}
			if ($key eq 'x') {
				unless (ref($hashref) eq 'HASH') {
					debugMsg(1,"-> parseSectionToConfig first run: $jVar not a hash for x in input json/yaml datafile\n");
					return;
				}
				if ($i == $#{$keyChain}) {
					@{$jsonVars->{xrange}} = (keys %$hashref);
					last MPREPARSE;
				}
				else {
					$xhashref = $hashref;
					$istart = $i + 1;
					last KEYPARSE;
				}
			}
			$hashref = nextHashListRef($hashref, $key);
			unless (defined $hashref) {
				debugMsg(1,"-> parseSectionToConfig first run: $jVar key '$key' not found in input json/yaml datafile\n");
				return;
			}
		}
		if (defined $xhashref) {
			$jsonVars->{xrange} = []; # Set to empty list
			XPARSE: for my $x (keys %$xhashref) {
				my $hashref = $xhashref->{$x};
				for my $i ($istart .. $#{$keyChain}) {
					my $key = $keyChain->[$i];
					next XPARSE unless exists $hashref->{$key};
					$hashref = nextHashListRef($hashref, $key);
					unless (defined $hashref) {
						debugMsg(1,"-> parseSectionToConfig xhashref: $jVar key '$key' not found in input json/yaml datafile for x = $x\n");
						return;
					}
				}
				push(@{$jsonVars->{xrange}}, $x);
			}
		}
		elsif (defined $xlistref) {
			$jsonVars->{xrange} = []; # Set to empty list
			XPARSE: for my $x (0 .. $#$xlistref) {
				my $hashref = $xlistref->[$x];
				for my $i ($istart .. $#{$keyChain}) {
					my $key = $keyChain->[$i];
					next XPARSE unless exists $hashref->{$key};
					$hashref = nextHashListRef($hashref, $key);
					unless (defined $hashref) {
						debugMsg(1,"-> parseSectionToConfig xlistref: $jVar key '$key' not found in input json/yaml datafile for x = $x\n");
						return;
					}
				}
				push(@{$jsonVars->{xrange}}, $x);
			}
		}
	}
	if (defined $jsonVars->{xrange}) { # If an x range is set sort them now
		if (grep {/\D/} @{$jsonVars->{xrange}}) {
			@{$jsonVars->{xrange}} = sort { $a cmp $b } @{$jsonVars->{xrange}};
		}
		else {
			@{$jsonVars->{xrange}} = sort { $a <=> $b } @{$jsonVars->{xrange}};
		}
		debugMsg(1,"-> parseSectionToConfig x-range = ", \join(",", @{$jsonVars->{xrange}}), "\n");
	}
	print Dumper($jsonVars) if $Debug & 8;

	# Next we parse all vars and assign values to them in the $jsonVars structure as we go
	# Using technique from here: https://stackoverflow.com/questions/22774118/referring-to-a-chain-of-hash-keys-in-a-perl-hash-of-hashes
	for my $jVar (keys %$jsonVars) {
		next if $jVar eq 'x' || $jVar eq 'xrange';
		my ($synErr, $keyChain) = extractKeyChain($jVar);
		return $synErr if $synErr;
		if (defined $jsonVars->{xrange}) { # If an x range is set, we will need to calculate as many values for each var
			EACHX: for my $i (0 .. $#{$jsonVars->{xrange}}) {
				my $x = $jsonVars->{xrange}->[$i];
				my $hashref = $encodedData;
				for my $k (0 .. $#{$keyChain}) {
					my $key = $keyChain->[$k];
					if ($key eq 'x') {
						unless (ref($hashref) eq 'HASH') {
							debugMsg(1,"-> parseSectionToConfig: $jVar not a hash for x=$x in input json/yaml datafile\n");
							return;
						}
						if ($k == $#{$keyChain}) {
							$jsonVars->{$jVar}->{values}->[$i] = $x;
							next EACHX;
						}
						$hashref = nextHashListRef($hashref, $x);
						unless (defined $hashref) {
							debugMsg(1,"-> parseSectionToConfig: $jVar key '$x' not found for x=$x in input json/yaml datafile\n");
							return;
						}
						next;
					}
					if ($key eq 'x:v' && $k == $#{$keyChain}) {
						$jsonVars->{$jVar}->{values}->[$i] = nextHashListRef($hashref, $x);
						next EACHX;
					}
					if ($key eq '[x]') {
						return "Error variable $jVar not a list for x=$x in input json/yaml datafile" unless ref($hashref) eq 'ARRAY';
						if ($k == $#{$keyChain}) {
							$jsonVars->{$jVar}->{values}->[$i] = $x;
							next EACHX;
						}
						$hashref = nextHashListRef($hashref, "[$x]");
						unless (defined $hashref) {
							debugMsg(1,"-> parseSectionToConfig: $jVar key '[$x]' not found for x=$x in input json/yaml datafile\n");
							return;
						}
						next;
					}
					unless (exists $hashref->{$key}) { # If key does not exist
						$jsonVars->{$jVar}->{values}->[$i] = undef;
						next EACHX;
					}
					$hashref = nextHashListRef($hashref, $key);
					if ($k < $#{$keyChain} && !defined $hashref) {
						debugMsg(1,"-> parseSectionToConfig: $jVar key '$key' not found for x=$x in input json/yaml datafile\n");
						return;
					}
				}
				if (ref($hashref) eq 'ARRAY') {
					my $list = join(',', @$hashref);
					my $portlist = generateRange($list, $portRangeMode, $slotPortSep);
					$jsonVars->{$jVar}->{values}->[$i] = $portlist ? $portlist : $list;
					next;
				}
				return "Error no scalar value for variable $jVar x=$x in input json/yaml datafile" if ref($hashref);
				$jsonVars->{$jVar}->{values}->[$i] = $hashref;
			}
		}
		else { # Each var has one value only
			my $hashref = $encodedData;
			for my $key (@$keyChain) {
				$hashref = nextHashListRef($hashref, $key);
				unless (defined $hashref) {
					debugMsg(1,"-> parseSectionToConfig single value: $jVar key '$key' not found in input json/yaml datafile\n");
					return;
				}
			}
			if (ref($hashref)) {
				debugMsg(1,"-> parseSectionToConfig single value: no scalar value for variable $jVar in input json/yaml datafile\n");
				return;
			}
			$jsonVars->{$jVar}->{values}->[0] = $hashref;
		}
	}
	$jsonVars->{xrange} = [0] unless defined $jsonVars->{xrange}; # Create a null single index in case no x range, so that code below works in both cases
	print Dumper($jsonVars) if $Debug & 8;

	# Finally we can replace the json vars across all lines in the section	
	my ($asciiSection, $cacheSection, $cachePorts);
	for my $i (0 .. $#{$jsonVars->{xrange}}) { # Do $var replacement as many times as we have x values
		my $firstLine = 1;
		$asciiSection = '';
		for my $line (@$lineSection) { # For every line in the section
			debugMsg(1,"-> parseSectionToConfig working line bef: ", \$line, "\n");
			# First do optional replacements with embedded &IF: condition
			$line =~ s/\[(.*?)\s*&IF:\s*(.*?)?\]/replaceOptCond($jsonVars, $i, $1, $2)/ge;
			# Then check for &IF: conditionat end of line
			my ($workingLine, $condition) = checkCondition($line);
			if (defined $condition) { # Evaluate &IF: condition
				debugMsg(1,"-> parseSectionToConfig condition bef: ", \$condition, "\n");
				$condition =~ s/\$($VarJson)(?=\s|$)/replaceJsonVar($jsonVars, $i, $1, undef, undef, 1)/ge;
				debugMsg(1,"-> parseSectionToConfig condition aft: ", \$condition, "\n");
				my ($result, $evalError) = evalCondition($condition);
				return $evalError unless defined $result;
				unless ($result) { # If result evaluates false
					debugMsg(1,"-> parseSectionToConfig condition evaluated FALSE\n");
					last if $firstLine;	# If we skip the 1st line, then we skip the whole line-section
					next;			# Else skip just current line
				}
				debugMsg(1,"-> parseSectionToConfig condition evaluated TRUE\n");
			}
			# First do optional replacements
			$workingLine =~ s/\[([^\[\]]*)\$($VarJson)([\s%][^\[\]]*)?\]/replaceJsonVar($jsonVars, $i, $2, $1, $3)/ge;
			next if $workingLine =~ /^\s+$/; # Skip empty lines
			# Then do mandatory replacements with %:
			$workingLine =~ s/\$($VarJson)(%:\S+)/replaceJsonVar($jsonVars, $i, $1, undef, $2)/ge;
			# Then do mandatory replacements
			$workingLine =~ s/\$($VarJson)(?=\s|$)/replaceJsonVar($jsonVars, $i, $1)/ge;
			debugMsg(1,"-> parseSectionToConfig working line aft: ", \$workingLine, "\n");
			if ($workingLine =~ /££undef££/) {
				last if $firstLine;	# If we skip the 1st line, then we skip the whole line-section
				next;			# Else skip just current line
			}
			optSquareMask(\$workingLine); # Mask square brackets inside quotes
			$workingLine =~ s/\[[^\[\]]*\]\s?//g;
			optSquareUnmask(\$workingLine); # Unmask square brackets inside quotes
			debugMsg(1,"-> parseSectionToConfig output line ----> ", \$workingLine, "\n");
			$asciiSection .= $workingLine . "\n";
			$firstLine = 0;
		}
		debugMsg(2,"-> parseSectionToConfig - asciiSection:\n>", \$asciiSection, "<\n");
		next unless length $asciiSection;

		# Compress port ranges
		if ($portRangeMode && $asciiSection =~ s/$PortsRegex2/<ports>/) {
			if (length $cacheSection) {
				if ($asciiSection eq $cacheSection) {
					$cachePorts = generatePortList($cachePorts . ",$1");
					debugMsg(2,"-> parseSectionToConfig - same cacheSection / ports = ", \$cachePorts, "\n");
					next;
				}
				else {
					$cacheSection =~ s/<ports>/generateRange($cachePorts, $portRangeMode, $slotPortSep)/ge;
					debugMsg(1,"-> parseSectionToConfig adding port range section1:\n", \$cacheSection, "\n");
					$$asciiConfigRef .= $cacheSection;
				}
			}
			$cacheSection = $asciiSection;
			debugMsg(2,"-> parseSectionToConfig - new cacheSection:\n", \$cacheSection, "\n");
			$cachePorts = generatePortList($1);
			next;
		}
		elsif (length $cacheSection) {
			$cacheSection =~ s/<ports>/generateRange($cachePorts, $portRangeMode, $slotPortSep)/ge;
			debugMsg(1,"-> parseSectionToConfig adding port range section2:\n", \$cacheSection, "\n");
			$$asciiConfigRef .= $cacheSection;
			$cacheSection = $cachePorts = undef;
		}
		$$asciiConfigRef .= $asciiSection;
	}
	if (length $cacheSection) {
		$cacheSection =~ s/<ports>/generateRange($cachePorts, $portRangeMode, $slotPortSep)/ge;
		debugMsg(1,"-> parseSectionToConfig adding port range section3:\n", \$cacheSection, "\n");
		$$asciiConfigRef .= $cacheSection;
	}
}

sub readEncodedConfig { # Reads in json/yaml file and returns encoded config data
	my $infile = shift;
	my $fileformat = ($infile =~ /\.(json|yaml)/i)[0];
	quit(1, "Invalid input file $infile") unless defined $fileformat;
	my $encodedData;
	open(IN, '<', $infile) or do {
		quit(1, "Unable to open input file " . File::Spec->canonpath($infile) . "\n");
	};
	local $/;	# Read in file in one shot
	if ($fileformat eq 'json') {
		$encodedData = $JsonCoder->decode(<IN>);
	}
	else { # YAML
		$encodedData = Load(<IN>);
	}
	close IN;
	print "Read config data from file: " . File::Spec->rel2abs($infile) . "\n";
	print Dumper($encodedData) if $Debug & 8;
	return $encodedData;
}


sub convertToConfig { # Converts data structure into target config file
	my ($encodedData, $enc_out) = @_;
	my $asciiConfig = '';
	my $encFile;

	# Find the encoder.out file
	if (-e $enc_out) { # Try in working directory first
		$encFile = $enc_out;
	}
	unless (defined $encFile) { # Then try in regular paths
		foreach my $path (@AcliFilePath) {
			if (-e "$path/$enc_out") {
				$encFile = "$path/$enc_out";
				last;
			}
		}
	}
	unless (defined $encFile) {
		quit(1, "Unable to locate decoder file $enc_out\n");
	}
	debugMsg(1,"-> Source input from decoder file $encFile\n");

	open(ENC, '<', $encFile) or do {
		quit(1, "Unable to open decoder file " . File::Spec->canonpath($encFile) . "\n");
	};
	print "Loading decoder file: " . File::Spec->rel2abs($encFile) . "\n";

	my $lineNumber = 0;
	my $synErr;
	my $sectionLines = [];
	my $linesSubtract = 0;
	my $portRangeMode = 0;
	my $slotPortSep = '/'; # Default
	while (<ENC>) {
		chomp;
		s/\x0d+$//g; # Remove trailing CRs (DOS files read on Unix OS)
		$lineNumber++;
		next if /^\s*$/; # skip empty lines
		next if /^\s*#/; # skip comment lines
		next if /^package .+;$/; # Skip the package line
		next if /^my \$Version = .+;$/; # Skip the version line
		next if /^__END__/; # Skip the end marker
		$_ = quoteCurlyMask($_, '#'); # Mask comment character in case it appears inside quotes or brackets
		s/\s+#.*$//; # Remove comments on same line
		$_ = quoteCurlyUnmask($_, '#'); # Unmask
		/^DEVICE_PORT_RANGE\s*=\s*([012])\s*$/ && do {
			$portRangeMode = $1;
			next;
		};
		/^SLOT_PORT_SEPARATOR\s*=\s*(?|"(.)"|'(.)')\s*$/ && do {
			$slotPortSep = $1;
			next;
		};
		/^exit\s*$/ && @$sectionLines && $sectionLines->[$#$sectionLines] =~ /^\s/ && do {
			push(@$sectionLines, $_);
			next;
		};
		/^\S/ && do {
			if (@$sectionLines) {
				parseSectionToConfig($sectionLines, $encodedData, \$asciiConfig, $portRangeMode, $slotPortSep);
				$linesSubtract = scalar @$sectionLines;
				@$sectionLines = (); # Empty section now
			}
			push(@$sectionLines, $_);
			next;
		};
		/^\s/ && do {
			if (@$sectionLines) {
				push(@$sectionLines, $_);
				next;
			}
			$synErr = 'Indented line does not belong to any context';
		};
		print "- syntax error on line " . ($lineNumber - $linesSubtract) . (defined $synErr ? ": $synErr" : '') . "\n";
		close ENC;
		quit(1, "Unable to read encoder file " . File::Spec->canonpath($encFile) . "\n");
	}
	close ENC;
	if (@$sectionLines) {
		parseSectionToConfig($sectionLines, $encodedData, \$asciiConfig, $portRangeMode, $slotPortSep);
	}
	return \$asciiConfig;
}

sub saveOutputFile { # Saves ASCII data to file
	my ($outConfigRef, $outfile, $what) = @_;

	open(OUT, '>', $outfile) or do {
		quit(1, "Unable to open output file " . File::Spec->canonpath($outfile) . "\n");
	};
	print OUT $$outConfigRef;
	close OUT;
	print "Saved generated $what to file: " . File::Spec->rel2abs($outfile) . "\n";
}


# ---------------- makej2c functions  ------------------

sub generateVar { # Given a list of hash keys returns string in format $key1{key2}{etc}
	my $keyList = shift;
	#debugMsg(4,"-> generateVar input keylist = ", \join(',', @$keyList), "\n");
	my $varString = '$' . $keyList->[0];
	my $curlyXseen;
	for my $i (1 .. $#$keyList) {
		$curlyXseen = 1 if $keyList->[$i] eq 'x';
		last if $curlyXseen && $keyList->[$i] eq '[x]' && $i == $#$keyList;
		# We want	ip name-server $dns{server}[x]
		# And		vlan ports $vlan{x}{pvid} pvid $vlan{x}
		$varString .= $keyList->[$i] eq '[x]' ? $keyList->[$i] : '{' . $keyList->[$i] . '}';
	}
	#debugMsg(4,"-> generateVar output jsonVar = ", \$varString, "\n");
	return $varString;
}

sub extractJsonVars { # From input json line, extract the <args> as json vars
	my $json = shift;
	my $jsonHash = {};
	my $keyList = [];

	# $jsonHash = {
	#	<arg:mods> = {
	#		jsonVar => $vlan{x}{instance}
	#		argMods => :mods
	#	}
	#	&IF: = $ntp{server}{ip}  OR   !$ntp{server}{ip}

	# from	'{"ntp": { "server": { "ip": "<ip>", "enable": true } }}'
	# to	ip => $ntp{server}{ip}

	# from	'{"vlan": {"<vids>": {"type": "port", "instance": "<inst:cist=0>", "voice-vlan": "<vvln:%>" }}}'
	# to	vids => $vlan{x}, inst => $vlan{x}{instance}, vvln => $vlan{x}{voice-vlan}

	# from	'{"syslog": { "server": ["<ip>"] }}'
	# to	ip => $syslog{server}[x]

	# Example of how this function nibbles at a json string
	#	{"ntp": { "server": { "ip": "<ip>", "enable": true }, "client": { "name": <name>} }}
	#	{ "server": { "ip": "<ip>", "enable": true }, "client": { "name": <name>} }
	#	{ "ip": "<ip>", "enable": true }, "client": { "name": <name>}
	#	"<ip>", "enable": true }, "client": { "name": <name>
	#	, "enable": true }, "client": { "name": <name>
	#	true }, "client": { "name": <name>
	#	}, "client": { "name": <name>
	#	,"client": { "name": <name> }
	#	{ "name": <name> }
	#	<name>

	# Example of how this function nibbles at a json string - with array
	#	{"ip": { "route": [{"route": "<route>", "mask": "<mask>", "next-hop": "<ip>", "weight": "<weight>" }] }}
	#	{ "route": [{"route": "<route>", "mask": "<mask>", "next-hop": "<ip>", "weight": "<weight>" }] }
	#	[{"route": "<route>", "mask": "<mask>", "next-hop": "<ip>", "weight": "<weight>" }]
	#	{"route": "<route>", "mask": "<mask>", "next-hop": "<ip>", "weight": "<weight>" }
	#	"<route>", "mask": "<mask>", "next-hop": "<ip>", "weight": "<weight>"
	#	, "mask": "<mask>", "next-hop": "<ip>", "weight": "<weight>"
	#	"<mask>", "next-hop": "<ip>", "weight": "<weight>"
	#	, "next-hop": "<ip>", "weight": "<weight>"
	#	"<ip>", "weight": "<weight>"
	#	, "weight": "<weight>"
	#	"<weight>"

	# Example with <arg> as key
	#	{"radius": {"server": {"<ip>" : {"accounting": "<acct:%>", "timeout": "<timeout>" }}}}
	#	{"server": {"<ip>" : {"accounting": "<acct:%>", "timeout": "<timeout>" }}}
	#	{"<ip>" : {"accounting": "<acct:%>", "timeout": "<timeout>" }}


	debugMsg(4,"-> extractJsonVars json string start: >", \$json, "<\n");
	WHL1: while ($json =~ s/^\s*(?|\{\s*\"([<:!%=,>\w-]+)\"\s*:|(\[))\s*//) { # Hash key / '{"key":' 
		my $key = $1;
		if ($key eq '[') {
			debugMsg(4,"-> extractJsonVars json after removing array from start '[': >", \$json, "<\n");
			$json =~ s/\s*\]$//;	# Remove outer square bracket
			push(@$keyList, "[x]");
		}
		else {
			debugMsg(4,"-> extractJsonVars json after removing key '$key': >", \$json, "<\n");
			$json =~ s/\s*\}$//;	# Remove outer curly
			if ($key =~ /^$ArgJson$/) {
				push(@$keyList, "x");
				return "Indeterminate arg key '$2' in json line parsing" if exists $jsonHash->{$2};
				$jsonHash->{$2} = {jsonVar => generateVar($keyList), argMods => $3};
				debugMsg(4,"-> extractJsonVars assigning <arg> key '$1' = ", \$jsonHash->{$2}->{jsonVar}, "<\n");
			}
			else { # 1st key
				push(@$keyList, $key);
			}
		}
		WHL2: while (1) {
			my $match;
			if ($json =~ s/^\s*\[\s*//) { # Array
				debugMsg(4,"-> extractJsonVars json after removing array '[': >", \$json, "<\n");
				$json =~ s/\s*\]$//;	# Remove outer square bracket
				push(@$keyList, "[x]");
			}
			if ($json =~ s/^\s*(?|\"([<:!%=,>\w-]+)\"|(\w+))\s*//) { # Hash value / '"value"' / '"<value>"' / 'true'
				my $value = $1;
				debugMsg(4,"-> extractJsonVars json after removing value '$value': >", \$json, "<\n");
				if ($value =~ /^$ArgJson$/) {
					return "Indeterminate arg key '$2' in json line parsing" if exists $jsonHash->{$2};
					$jsonHash->{$2} = {jsonVar => generateVar($keyList), argMods => $3};
					debugMsg(4,"-> extractJsonVars assigning <arg> value '$1' = ", \$jsonHash->{$2}->{jsonVar}, "<\n");
				}
				elsif (!exists $jsonHash->{'&IF:'}) {
					if ($value eq 'false' || $value eq 'null') {
						$jsonHash->{'&IF:'} .= '!'.generateVar($keyList);
					}
					else {
						$jsonHash->{'&IF:'} .= generateVar($keyList);
					}
					debugMsg(4,"-> extractJsonVars setting '&IF:' key = ", \$jsonHash->{'&IF:'}, "<\n");
				}
				$match = 1;
			}
			if ($json =~ s/^\s*\[\"$ArgJson\"\]\s*//) { # Array / '["<value>"]'
				debugMsg(4,"-> extractJsonVars json after removing [array]: >", \$json, "<\n");
				return "Indeterminate arg key '$2' in json line parsing" if exists $jsonHash->{$2};
				$jsonHash->{$2} = {jsonVar => generateVar($keyList) . "[x]", argMods => $3};
				debugMsg(4,"-> extractJsonVars assigning <arg> array '$1' = ", \$jsonHash->{$2}->{jsonVar}, "<\n");
				$match = 1;
			}
			if ($json =~ s/^\s*,\s*\"([<:!%=,>\w-]+)\"\s*:\s*//) { # Hash next key / ', "key":'
				my $key = $1;
				debugMsg(4,"-> extractJsonVars json after removing next-key '$key': >", \$json, "<\n");
				pop(@$keyList);
				if ($key =~ /^$ArgJson$/) {
					push(@$keyList, "x");
					return "Indeterminate arg key '$2' in json line parsing" if exists $jsonHash->{$2};
					$jsonHash->{$2} = {jsonVar => generateVar($keyList), argMods => $3};
					debugMsg(4,"-> extractJsonVars assigning <arg> inner-key '$1' = ", \$jsonHash->{$2}->{jsonVar}, "<\n");
				}
				else { # 1st key
					push(@$keyList, $key);
				}
				$match = 1;
			}
			if ($json =~ s/^\s*\}//) {
				$json .= "}"; # Re-add a curly
				pop(@$keyList);
				$match = 1;
				debugMsg(4,"-> extractJsonVars json string after end curly: >", \$json, "<\n");
			}
			last WHL1 unless length $json;
			last WHL2 if $json =~ /^\s*[\{\}]/;
			unless ($match) {
				return "Error, unable to match pattern in json line parsing";
				last WHL2;
			}
		}
	}
	print Dumper($jsonHash) if $Debug & 8;
	return $jsonHash;
}


sub changeArg2jsonVar { # Replace argument variables
	# Modified from deRefDictVar() in AcliPm::Dictionary
	my ($jsonHash, $varField, $varAll, $varName, $valueMods) = @_;
	my $replValue = $jsonHash->{$varName}->{jsonVar} if defined $jsonHash->{$varName}->{jsonVar};
	if (defined $replValue) { # Value is available
		debugMsg(4,"=changeArg2jsonVar: De-RefVar: varName = $varName / varField = >", \$varField, "<\n");
		#debugMsg(4,"=changeArg2jsonVar: De-RefVar: varName = $varName / varAll = >", \$varAll, "<\n");
		#debugMsg(4,"=changeArg2jsonVar: De-RefVar: varName = $varName / valueMods = >", \$valueMods, "<\n");
		#debugMsg(4,"=changeArg2jsonVar: De-RefVar: varName = $varName / replValue = >", \$replValue, "<\n");
		my $argModsJson = $jsonHash->{$varName}->{argMods};
		if (defined $argModsJson && defined $valueMods) {
			$valueMods =~ s/^://;
			if ($argModsJson eq ':%' && $valueMods !~ /,/) {
				$replValue = $valueMods . ' &IF: ' . $replValue;
			}
			elsif ($argModsJson eq ':!%' && $valueMods !~ /,/) {
				$replValue = $valueMods . ' &IF: !' . $replValue;
			}
			elsif ($argModsJson =~ /([\w-]+)=true/) {
				my $trueVal = $1;
				if ($argModsJson =~ /([\w-]+)=false/) {
					my $falseVal = $1;
					$replValue .= "%:$trueVal,$falseVal";
				}
			}
		}
		$varField =~ s/\Q<$varAll>\E/$replValue/;
		debugMsg(4,"=changeArg2jsonVar: to >$varField<\n");
		return $varField;
	}
	# Else, replace nothing
	return $varField;
}

sub removeOptSectWithNoVars { # Replace [optional] section with nothing if no jsonArg in it
	my $optSect = shift;
	return $optSect =~ /\$$VarJson/ || $optSect =~ /$ArgJson/ || $optSect =~ /\[x\]\s?/ ? $optSect : '';
}


sub generateDecoder { # Parse the simplified encoder structure and produce a decoder from it
	my $encoder = shift;
	my $asciiDecoder = '';

	for my $i (0 .. $#{$encoder->{input}}) {
		my $command = $encoder->{input}->[$i];
		my $jsonList = $encoder->{output}->[$i];
		unless (defined $jsonList) {
			$asciiDecoder .= $command . "\n";
			next;
		}
		# Extract from 1st json assignment, all the <args> in syntax $key{ke2}..
		my $jsonHash = extractJsonVars($jsonList->[0]);
		unless ( ref($jsonHash) ) { # It's an error string
			print "Error processing line: $command\n";
			print " - $jsonHash\n";
			next;
		}
		# And then replace <args> in the command line
		$command =~ s/\s*\K($ArgJson)/changeArg2jsonVar($jsonHash, $1, $2, $3, $4)/ge; # <var> replacements
		if (exists $jsonHash->{'&IF:'} && scalar keys %$jsonHash <= 2) {
#		if (exists $jsonHash->{'&IF:'}) {
			$command = sprintf "%-140s &IF: %s", $command, $jsonHash->{'&IF:'};
		}
		# We want to remove [optional] sections which do not contain any jsonArgs
		$command =~ s/(\[[^\[\]]+\]\s?)/removeOptSectWithNoVars($1)/ge; # <var> replacements
		debugMsg(1,"=generateDecoder final: ", \$command, "\n");

		$asciiDecoder .= $command . "\n";
	}
	return \$asciiDecoder;
}


# ---------------- schema functions  ------------------

sub extractSchema { # Simply combine all the json mappings into one single json schema output
	my $encoder = shift;
	my $encodedData = {};

	# Set up the DEFAULTS
	$encodedData = encodeData($encodedData, $encoder->{output}->[$encoder->{default}]) if exists $encoder->{default};

	# Simply parse all the encoder json mappings
	for my $listRef (@{$encoder->{output}}) {
		for my $expression (@$listRef) {
			debugMsg(1,"=extractSchema: processing: ", \$expression, "<\n");
			# Create hash
			my $hash;
			eval {
				local $SIG{__WARN__} = sub { die shift }; # Turn every warning into an exception
				$hash = decode_json($expression);
			};
			if ($@) {
				(my $message = $@) =~s/;.*$//;
				$message =~ s/,? at (?:\w:)[\\\/]?.+ line .+$//; # Delete file & line number info
				quit(1, "Error while encoding: $expression\nJSON error: $message");
			}
			# Merge together
			$encodedData = \%{ $HashMerge->merge( $encodedData, $hash ) };
		}
	}

	# Post-processing

	# Merge all of $vlan->{} <pvid>, <vids>, <vid>
	if (exists $encodedData->{vlan}->{'<vids>'}) {
		$encodedData->{vlan}->{'<vid>'} = \%{ $HashMerge->merge( $encodedData->{vlan}->{'<vid>'}, $encodedData->{vlan}->{'<vids>'} ) };
		delete $encodedData->{vlan}->{'<vids>'};
	}
	if (exists $encodedData->{vlan}->{'<pvid>'}) {
		$encodedData->{vlan}->{'<vid>'} = \%{ $HashMerge->merge( $encodedData->{vlan}->{'<vid>'}, $encodedData->{vlan}->{'<pvid>'} ) };
		delete $encodedData->{vlan}->{'<pvid>'};
	}

	# Merge all of $port->{} <ports>, <port>
	if (exists $encodedData->{port}->{'<port>'}) {
		$encodedData->{port}->{'<port>'} = \%{ $HashMerge->merge( $encodedData->{vlan}->{'<port>'}, $encodedData->{vlan}->{'<ports>'} ) };
	}
	else {
		$encodedData->{port}->{'<port>'} = $encodedData->{port}->{'<ports>'};
	}
	delete $encodedData->{vlan}->{'<ports>'};

	print Dumper($encodedData) if $Debug & 8;

	# If we have post-processing Perl code in the encoder file, run it now
	debugMsg(1,"\n=extractSchema - Encoder::run\n");
	Encoder::run($encodedData) if $encoder->{perlcode};

	return $encodedData;
}

sub saveEncodedSchema { # Generates output json/yaml file with encoded data extracted from config file
	my ($encodedData, $outfile) = @_;

	open(OUT, '>', $outfile) or do {
		quit(1, "Unable to open output file " . File::Spec->canonpath($outfile) . "\n");
	};
	print OUT $JsonCoder->encode($encodedData); # Pretty format
	close OUT;
	print "Saved schema to file: " . File::Spec->rel2abs($outfile) . "\n";
}



# ---------------- main file functions  ------------------

sub fileGlob { # Returns input files entered or as result of glob
	my $argList = shift;
	my @inFiles;
	if (scalar @$argList == 1 && (my $fileglob = $argList->[0]) =~ /[\*?\[\]]/) { # Wildcard
		@inFiles = bsd_glob("$fileglob");
		quit(1, "No files found matching \"$fileglob\"") unless @inFiles;
	}
	else { # Filenames (no wildcard)
		@inFiles = @$argList;
	}
	return @inFiles;
}

sub outCfgSuffix { # Creates output config file by appending as .suffix the decoder prefix to either config or json/yaml file
	my ($infile, $enc_out) = @_;
	(my $outfile = $infile) =~ s/\.(?:json|yaml)//i;	# Remove the json or yaml suffix, if present
	$outfile .= '.' . (split(/\./, $enc_out))[0];
	return $outfile;
}

sub outSuffix { # Self generated decoder j2c file from encoder c2j file
	my ($enc_in, $suffix) = @_;
	return $enc_in . ".$suffix";
}


# ---------------- main modes ------------------

sub extract { # Given a config file, encodes it into either json or yaml using provided encoder.c2j file 
	my ($enc_in, $infilelist, $fileformat) = @_;

	# Read the encoder.c2j file, and prepare the encoder data structure
	my $encoder = readEncoderFile($enc_in);

	for my $infile (@$infilelist) {

		# Read in the config file and use the encoder to produce a hash of extrated data from it
		my $encodedHash = encodeInputConfig($encoder, $infile);

		# Save the resulting hash of extracted data to file
		saveEncodedConfig($encodedHash, $fileformat, $infile);
	}
}

sub makecfg { # Given already encoded data (json/yaml file) converts it to an output config file using an decoder.j2c file 
	my ($enc_out, $infile, $outfile) = @_;

	# Read in the json/yaml file into encoded hash structure
	my $encodedHash = readEncodedConfig($infile);

	# Convert to destination config using encoder.out file
	my $convertedConfig = convertToConfig($encodedHash, $enc_out);

	# Save the resulting config to output filename provided
	saveOutputFile($convertedConfig, $outfile, 'config');
}

sub convert { # Given a config file, converts it using provided encoder.c2j and decoder.j2c files
	my ($enc_in, $enc_out, $infilelist) = @_;

	# Read the encoder.c2j file, and prepare the encoder data structure
	my $encoder = readEncoderFile($enc_in);

	for my $infile (@$infilelist) {

		# Read in the config file and use the encoder to produce a hash of extrated data from it
		my $encodedHash = encodeInputConfig($encoder, $infile);

		# To be consistent with 'extract' + 'makecfg' we convert the data to json and back again
		# We do that because we want canonical->unblessed_bool(1) on the decode
		# so that true/false values are scalars in perl instead of blessed references (JSON::PP::Boolean)
		$encodedHash = $JsonCoder->decode($JsonCoder->encode($encodedHash));

		# Convert to destination config using encoder.out file
		my $convertedConfig = convertToConfig($encodedHash, $enc_out);

		# Save the resulting config to output filename provided
		my $outfile = outCfgSuffix($infile, $enc_out);
		saveOutputFile($convertedConfig, $outfile, 'config');
	}
}

sub makej2c { # Reads encoder c2j file and convert to decoder j2c file
	my ($enc_in, $enc_out) = @_;

	# Read the encoder.c2j file, and prepare the encoder data structure
	my $encoder = readEncoderFile2($enc_in);

	# Save generated decoder file
	my $decoder = generateDecoder($encoder);

	# Save the resulting config to output filename provided
	saveOutputFile($decoder, $enc_out, 'decoder');
}

sub schema { # Reads encoder c2j file and dumps the schema of it
	my ($enc_in, $schema_out) = @_;

	# Read the encoder.c2j file, and prepare the encoder data structure
	my $encoder = readEncoderFile2($enc_in, 1);

	# Save generated decoder file
	my $schema = extractSchema($encoder);

	# Save the resulting config to output filename provided
	saveEncodedSchema($schema, $schema_out);
}




#############################
# MAIN                      #
#############################

MAIN:{
	my ($mode, $fileformat, $enc_in, $enc_out, $infile, @infiles, $outfile, $schema_out);

	getopts('d:');
	$Debug = $opt_d if $opt_d;

	printSyntax unless @ARGV;
	$mode = shift @ARGV;
	if ('extract' =~ /^\Q$mode\E/) {
		$fileformat = lc(shift @ARGV) or printSyntax;
		printSyntax unless $fileformat eq 'yaml' || $fileformat eq 'json';
		$enc_in = shift @ARGV or printSyntax;
		$enc_in .= '.c2j' unless $enc_in =~ /\.c2j$/;
		@infiles = fileGlob(\@ARGV) or printSyntax;
		extract($enc_in, \@infiles, $fileformat);
	}
	elsif ('makecfg' =~ /^\Q$mode\E/) {
		$infile = shift @ARGV or printSyntax;
		unless ($infile =~ /\.(?:json|yaml)/i) {
			print "Input file <input-yaml-json-file> must have either .json or .yaml suffix\n";
			printSyntax;
		}
		$enc_out = shift @ARGV or printSyntax;
		$enc_out .= '.j2c' unless $enc_out =~ /\.j2c$/;
		$outfile = shift @ARGV || outCfgSuffix($infile, $enc_out);
		makecfg($enc_out, $infile, $outfile);
	}
	elsif ('convert' =~ /^\Q$mode\E/) {
		$enc_in = shift @ARGV or printSyntax;
		$enc_in .= '.c2j' unless $enc_in =~ /\.c2j$/;
		$enc_out = shift @ARGV or printSyntax;
		$enc_out .= '.j2c' unless $enc_out =~ /\.j2c$/;
		@infiles = fileGlob(\@ARGV) or printSyntax;
		convert($enc_in, $enc_out, \@infiles);
	}
	elsif ('makej2c' =~ /^\Q$mode\E/) {
		$enc_in = shift @ARGV or printSyntax;
		$enc_in .= '.c2j' unless $enc_in =~ /\.c2j$/;
		$enc_out = shift @ARGV || outSuffix($enc_in, 'j2c');
		makej2c($enc_in, $enc_out);
	}
	elsif ('schema' =~ /^\Q$mode\E/) {
		$enc_in = shift @ARGV or printSyntax;
		$enc_in .= '.c2j' unless $enc_in =~ /\.c2j$/;
		$schema_out = shift @ARGV || outSuffix($enc_in, 'schema');
		schema($enc_in, $schema_out);
	}
	else {
		printSyntax;
	}
}

