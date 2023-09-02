# ACLI sub-module
package AcliPm::Error;
our $Version = "1.01";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(errorDetected);
}
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::GlobalMatchingPatterns;


sub errorDetected { # Verifies whether an error is to be detected in given data stream
	my ($db, $bufRef, $ifErrEnabled) = @_;
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $error;

	if (	( defined $ErrorPatterns{$host_io->{Type}} && $$bufRef =~ /$ErrorPatterns{$host_io->{Type}}/m )
		|| ($host_io->{ErrorLevel} eq 'warning' && length $WarningPatterns{$host_io->{Type}} && $$bufRef =~ /($WarningPatterns{$host_io->{Type}})/m)
		) { # Set & format the error message
		$host_io->{LastCmdError} = $host_io->{LastCmdErrorRaw} = $1;
		$host_io->{LastCmdError} =~ s/^\s+\^\n//; # Remove line with caret only; just keep error message
		$host_io->{LastCmdError} =~ s/^\%\s+//; # Remove initial '%' if present
		$host_io->{LastCmdError} =~ s/[\'\"]//g; # Remove any quotes
		$error = 1;
	}
	elsif ($$bufRef =~ /^\cGError from \S+: Cannot process command /m) { # This is if we get an error from a listening terminal
		# We don't want to set $host_io->{LastCmdError} in this case... I think... not sure.. just interrupt scripting
		$error = 1;
	}
	return 0 if $ifErrEnabled && (!$host_io->{ErrorDetect} || defined $script_io->{CmdLogFH}); # Always return false, if error detection disabled and $ifErrEnabled set
	return $error ? 1 : 0;	# Else return based on if an error seen
}

1;
