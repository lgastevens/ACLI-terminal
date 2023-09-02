# ACLI sub-module
package AcliPm::SerialPort;
our $Version = "1.01";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(readSerialPorts processSerialSelection);
}
use POSIX ();
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::DebugMessage;


sub printSerialList { # Print out list of known serial ports or those that match a selection
	my ($serialData, $selection) = @_;

	print "\nKnown serial ports";
	print " matching '$selection'" if $selection;
	print ":\n\n";
	printf "%3s  %-20s  %s\n", 'Num', 'Serial Port', 'Description';
	printf "%3s  %-20s  %s\n", '---', '-----------', '-----------';
	for my $i ( 0 .. $#{$serialData} ) {
		next if $selection && $serialData->[$i]->[0] !~ /$selection/;
		printf "%3s  %-20s  %s\n", $i+1, @{$serialData->[$i]};
	}
	print "\nSelect entry number / serial port name glob / <entry>@<baudrate> : ";
}


sub readSerialPorts { # Read in available serial ports on this machine
	my $serialData = shift;

	@$serialData = ();	# Clear it
	if ($^O eq 'MSWin32') { # On Windows we use WMIC
		my %comPort;
		my $tasklist = `wmic path win32_pnpentity get caption /format:list`;
		while ($tasklist =~ /^Caption=(.+)\(COM(\d+)\)[\x00\r]$/gm) {
			$comPort{"COM$2"} = $1;
		}
		foreach my $com (sort {$a cmp $b } keys %comPort) { # Arrange in COM-X order
			push(@$serialData, [$com, $comPort{$com}]);
		}
	}
	else { # On Unix, just try the usual /dev/ttyS? ones...
		my @devttys = glob '/dev/ttyS?';
		if (@devttys && eval {require POSIX}) {
			foreach my $port (@devttys) {
				my $tryport = $1;
				my $fd = POSIX::open($tryport, &POSIX::O_RDWR | &POSIX::O_NOCTTY | &POSIX::O_NONBLOCK);
				my $to = POSIX::Termios->new();
				if ( $to && $fd && $to->getattr($fd) ) {
					push(@$serialData, [$tryport, '']);
				}
			}
		}
	}
	return 0 unless @$serialData;
	printSerialList($serialData);
	return 1;
}


sub processSerialSelection { # Process a selection from serial port table
	my ($db, $selection) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $serialData = $db->[14];
	my $baudrate;

	print "\n";
	if ($selection =~ /^\s*$/) { # Nothing entered, come out
		print "Nothing entered! ($term_io->{CtrlQuitPrn} to quit)\n";
		print "Select entry number / serial port name glob / <entry>@<baudrate> : ";
		return;
	}
	$selection =~ s/^\s*//;	# Remove starting spaces
	$selection =~ s/\s*$//;	# Remove trailing spaces

	if ($selection =~ /^\d+$/ && $selection >= 1 && $selection <= scalar @$serialData) { # Number in range entered
		$host_io->{Name} = 'serial:' . $serialData->[$selection - 1]->[0];
		$host_io->{ComPort} = $serialData->[$selection - 1]->[0];
		return 1;
	}
	elsif ($selection =~ /^(\d+)\s*\@\s*(\d+)$/ && $1 >= 1 && $1 <= scalar @$serialData) { # Number in range entered #<port>
		$host_io->{Name} = 'serial:' . $serialData->[$1 - 1]->[0];
		$host_io->{ComPort} = $serialData->[$1 - 1]->[0];
		$host_io->{Baudrate} = $2;
		return 1;
	}
	elsif ($selection =~ /^(.+)\s*\@\s*(\d+)$/) { # Glob + baudrate
		$selection = $1;
		$baudrate = $2;
	}
		
	# Else, we have a string entered
	my $match;
	foreach my $entry (@$serialData) {
		if ($entry->[0] =~ /\Q$selection\E/) {
			if (defined $match) {
				printSerialList($serialData, $selection);
				return;
			}
			$match = $entry->[0];
		}
	}
	unless (defined $match) {
		print "No entries match selection \"$selection\"\n";
		print "Select entry number / serial port name glob / <entry>@<baudrate> : ";
		return;
	}
	$host_io->{Name} = 'serial:' . $match;
	$host_io->{ComPort} = $match;
	$host_io->{Baudrate} = $baudrate;
	return 1;
}

1;
