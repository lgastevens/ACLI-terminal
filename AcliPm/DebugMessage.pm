# ACLI sub-module
package AcliPm::DebugMessage;
our $Version = "1.02";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(debugMsg debugLevels);
}
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::GlobalDefaults;


# Debug Bit values: 512=loadAliasFile 256=tabExpand/quoteCurlyBackslashMask 128=historyDump 64=Errmode-Die 32=Errmode-Croak 16=ControlCLI(Serial) 8=ControlCLI 4=Input 2=output 1=basic

sub debugMsg { # Takes 4 args: debug-level, string1 [, ref-to-string [, string2] ]
	if (shift() & $::Debug) {
		my ($string1, $stringRef, $string2) = @_;
		my $cycle = '';
		my $callingPkg = caller . " ";
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
		unless ($string1 =~ /^[a-z]/) {
			$cycle = sprintf "[%04u]", $DebugCycleCounter;
			$cycle = "\n" . $cycle if $string1 =~ /^[A-Z]/;
		}
		if ($DebugLogFH) { print {$DebugLogFH} $cycle, $callingPkg, $string1, $refPrint, $string2 }
		else { print $cycle, $callingPkg, $string1, $refPrint, $string2 }
	}
}

sub debugLevels { # Print out debug levels
	print "Debug levels:\n";
	print " 0	: No debugging\n";
	print " bit1	: Basic debugging of input values\n";
	print " bit2	: Debugging of device output stream\n";
	print " bit4	: Debugging of device input stream\n";
	print " bit8	: Control::CLI::Extreme debug level = $DebugCLIExtreme\n";
	print " bit16	: Control::CLI::Extreme (SerialPort) debug level = $DebugCLIExtremeSerial\n";
	print " bit32	: Control::CLI::Extreme errmode left in croak mode\n";
	print " bit64	: Control::CLI::Extreme errmode set to die mode\n";
	print " bit128	: Debugging of History recall array\n";
	print " bit256	: Debugging of tabExpand()\n";
	print " bit512	: Debugging of loadAliasFile()\n";
	print " bit1024: Debugging of printOut()\n";
}

1;
