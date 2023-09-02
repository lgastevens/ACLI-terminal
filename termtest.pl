use warnings;
use strict;
use Term::ReadKey;
use FindBin;
use lib $FindBin::Bin;
use AcliPm::ReadKey;

my $Version = "1.06";
our $TestScript = 1;

$| = 1;

print $^O, "\n";

my (@chars, $key, $keychar, $keyhex, $keyprint);

print "Press 'Q' to quit this test program\n";
print "Press 'C' to clear the screen\n";
print "Event decode = (keyboard=1, keyDown=1, repeatCount, virtualKeyCode, virtualScanCode, ASCIIcode, controlKeys)\n";
ReadMode('raw');
while(1) {
	select(undef, undef, undef, 0.1); # Fraction of a sec sleep (otherwise CPU gets hammered..)
	# Check if any key was pressed (non-blocking read)
	if (defined($key = readKeyPress)) {
		@chars = split(//, $key);
		$keychar = $keyhex = $keyprint = '';
		foreach my $c (@chars) {
			$keychar .= sprintf " %3u", ord($c);
			$keyhex .= sprintf " 0x%x", ord($c);
			$keyprint .= ord($c) >= 32 ? $c : '.';
		}
		printf "\n%s /%s '%s'\n", $keychar, $keyhex, $keyprint;
		last if $key eq 'q' || $key eq 'Q';
		if ($key eq 'c' || $key eq 'C') {
			system('cls');
			ReadMode('raw'); # Must re-activate raw mode after a cls, otherwise CTRL-C will kill the script!
		}
	}
	print '.';
}
ReadMode('normal');
