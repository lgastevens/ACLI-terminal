# ACLI sub-module
package AcliPm::ReadKey;
our $Version = "1.02";

use strict;
use warnings;
use 5.010; # required for state declaration in readKeyPress
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(readKeyPress readKey);
}
use Term::ReadKey;
use AcliPm::GlobalConstants;

my $WinConsole;
if ($^O eq "MSWin32") {
	unless (eval "require Win32::Console") { die "Cannot find module Win32::Console" }
	$WinConsole = new Win32::Console(Win32::Console::STD_INPUT_HANDLE() );
}


sub readKeyPress { # Read the keyboard, in a non-blocking manner
	my $key;
	if ($^O eq "MSWin32") { # Windows is a bitch...
		state $enhKey; # Enhanced key flag
		while ($WinConsole->GetEvents()) {
			my @event = $WinConsole->Input();
			printf "\nevent = [0]keybrd/mouse=%u [1]keyPressed=%u [2]repeatCount=%u [3]keycode=0x%x [4]scancode=0x%x [5]char=0x%x [6]ctrlkeys=0x%x\n", @event if $::TestScript;
			next unless $event[1] || $enhKey; # Only process events with keyPressed true (or following an enhanced_key flag read)
			$enhKey = defined $event[6] && ($event[6] & 256) && ($event[6] & 1); # If the ENHANCED_KEY flag is set + AltGr, we relax reading only events with keyPressed true at next cycle
			# Decodes here: https://msdn.microsoft.com/en-us/library/windows/desktop/ms684166(v=vs.85).aspx
			if (defined $event[0] && $event[0] == 1 ) { # keyboard event ([0]=1), because a key was pressed ([1]=true)
				if ($event[5] == 0) { # No ASCII character available
					$key = $::CrsrLeft  if $event[3] == 37; #0x25
					$key = $::CrsrUp    if $event[3] == 38; #0x26
					$key = $::CrsrRight if $event[3] == 39; #0x27
					$key = $::CrsrDown  if $event[3] == 40; #0x28
					$key = $::Delete    if $event[3] == 46; #0x2E
					if ($event[6] & 4 || $event[6] & 8) { # We have CTRL keys pressed
						$key = "\c@"  if $event[3] == 192; #0xC0
						$key = "\c["  if $event[3] == 219; #0xDB
						$key = "\c\\" if $event[3] == 220; #0xDC
						$key = "\c]"  if $event[3] == 221; #0xDD
						$key = "\c^"  if $event[3] == 54;  #0x36
						$key = "\c_"  if $event[3] == 189; #0xBD
					}
				}
				elsif ($event[5] > 0) { # An ASCII character is set (only if > 0; bug24)
					$key = chr($event[5]);
					if ($event[6] & 4) { # We have CTRL keys pressed
						$key = "\c@"  if $event[5] == 64; #0x40 (FR)
						$key = "\c["  if $event[5] == 91; #0x5B (FR)
						$key = "\c\\" if $event[5] == 92; #0x5C (FR)
						$key = "\c]"  if $event[5] == 93; #0x5D (FR)
						$key = "\c^"  if $event[5] == 94; #0x5E (FR)
					}
					$key = "\n" if defined $key and ord($key) == 13; #0x0D
				}
				return undef if defined $key && $key =~ /[^[:ascii:]]/; # Protection against unicode, to avoid wide character warnings
				return $key;
			}
		}
		return undef;
	}
	else { # MAC OS and Solaris unix...
		state $escHold;
		$key = ReadKey(-1);
		if (defined $key) {
			return undef if $key =~ /[^[:ascii:]]/; # Protection against unicode, to avoid wide character warnings
			if (defined $escHold && length($escHold) == 2) { # The idea is that if we read in an escape sequence (like CRSR up etc..)
				$key = $escHold.$key;	# we only pass it on once we have read it entirely
				$escHold = undef;
			}
			elsif (defined $escHold && length($escHold) == 1) {
				if ($key eq '[') {
					my $nextKey = ReadKey(-1);
					if (defined $nextKey) {
						$key = $escHold . $key . $nextKey;
						$escHold = undef;
					}
					else {
						$escHold .= $key;
						$key = undef;
					}
				}
				else {
					$key = $escHold . $key;
					$escHold = undef;
				}
			}
			elsif (!defined $escHold && $key eq $Escape) {
				my $nextKey = ReadKey(-1);
				if (defined $nextKey) {	# Here we are able to read it in all at once
					$key .= $nextKey;
					if ($nextKey eq '[') {
						$nextKey = ReadKey(-1);
						if (defined $nextKey) {
							$key .= $nextKey;
						}
						else { # or maybe not..
							$escHold = $key;
							$key = undef;
						}
					}
				}
				else { # Here we are not (rlogin to vulcano)
					$escHold = $key;
					$key = undef;
				}
			}
			$key = "\cH" if ord($key) == 127; # Convert Backspace on iMAC
		}
		return $key;
	}
}


sub readKey { # Read in a a key stroke
	my $key;
	do {
	        select(undef, undef, undef, 0.1); # Fraction of a sec sleep (otherwise CPU gets hammered..)
		$key = ReadKey(-1);
	} until defined $key;
	return uc $key;
}

1;
