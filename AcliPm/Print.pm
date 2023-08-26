# ACLI sub-module
package AcliPm::Print;
our $Version = "1.01";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(printDot printOut cmdMessage);
}
use Time::HiRes;
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::DebugMessage;
use AcliPm::GlobalConstants;


sub printFlush { # Print to filehandle and flush output
	my ($fh, @text) = @_;
	my $stdiofh;

	if (defined $fh) {
		$text[2] =~ s/\e\[\d+m//g if length $text[2];	# Remove highlight escape sequence (only necessary on 3rd element passed)
		print {$fh} @text;
		$stdiofh = select($fh);
	}
	else {
		print @text
	}
	unless ($| == 1) {
		$| = 1; # Flush STDOUT buffer
		$| = 0; # Revert to line buffered mode
	}
	select($stdiofh) if defined $fh;
}


sub printDot { # Print out to user session an activity dot
	my $script_io = shift;

	if ( ($script_io->{DotPaceTime}+1) < int(10 * Time::HiRes::time)) { # Print dot if none printed in last sec
		printFlush(undef, '.'); #Stdout
		printFlush($script_io->{LogFH}, '.') if defined $script_io->{LogFH}; # Log file
		$script_io->{DotPaceTime} = int(10 * Time::HiRes::time);
	}
}


sub printOut { # Print out to user session; argv1 = string, argv2 optional reference to string
	my ($script_io, $toPrintOut, $toLogOnly, $toPrintRef) = @_;
	$toPrintOut =  '' unless defined $toPrintOut;
	$toLogOnly  =  '' unless defined $toLogOnly;
	$$toPrintRef = '' unless defined $$toPrintRef;

	debugMsg(1024,"=printOut (from ".(caller 1)[3]."):\n>", $toPrintRef, "$toPrintOut<\n") if $::Debug;
	if ($script_io->{CmdLogFile} && $script_io->{CmdLogFlag} && !defined $script_io->{CmdLogFH}) { # Set up CmdLog FH now
		printFlush(undef, "\n$ScriptName: Saving output "); #Stdout
		printFlush($script_io->{LogFH}, "\n$ScriptName: Saving output ") if defined $script_io->{LogFH}; # Log file
		open($script_io->{CmdLogFH}, $script_io->{CmdLogMode}, $script_io->{CmdLogFile}) or do {
			$script_io->{CmdLogFH} = $script_io->{CmdLogOnly} = undef;
			printFlush(undef, ": Cannot open output file \"$script_io->{CmdLogFile}\": $!\n\n"); #Stdout
			printFlush($script_io->{LogFH}, ": Cannot open output file \"$script_io->{CmdLogFile}\": $!\n\n") if defined $script_io->{LogFH}; # Log file
			$script_io->{CmdLogFile} = undef;
		};
		if (defined $script_io->{CmdLogFH}) { # Open above was successful
			$script_io->{CmdLogFullPath} = File::Spec->rel2abs($script_io->{CmdLogFile});
			printFlush($script_io->{CmdLogFH}, "\n") if $script_io->{CmdLogMode} eq '>>';
		}
	}
	unless (defined $script_io->{CmdLogFH} && $script_io->{CmdLogOnly}) {
		printFlush(undef, $$toPrintRef, $toPrintOut); #Stdout
		printFlush($script_io->{LogFH}, $$toPrintRef, $toLogOnly, $toPrintOut) if defined $script_io->{LogFH}; # Log file
	}
	if (defined $script_io->{CmdLogFH}) { # Cmd Log file
		printFlush($script_io->{CmdLogFH}, $$toPrintRef, $toLogOnly, $toPrintOut);
		printDot($script_io) if $script_io->{CmdLogOnly};
	}
	$script_io->{PrintFlag} = 1;
}


sub cmdMessage { # On embedded commands this output cannot be grepped
	my ($db, $text, $embedded) = @_;
	my $script_io = $db->[4];

	if ($script_io->{AcliControl}) {
		print $text;
	}
	else {
		$script_io->{EmbCmdSpacing} = 1 unless $script_io->{EmbCmdSpacing};
		printOut($script_io, $text);
	}
}

1;
