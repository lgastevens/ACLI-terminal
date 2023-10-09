# ACLI sub-module
package AcliPm::Logging;
our $Version = "1.03";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(closeLogFile openLogFile);
}
use POSIX ();
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::GlobalConstants;
use AcliPm::GlobalDefaults;


sub closeLogFile { # Handles closing log file
	my $script_io = shift;
	printf { $script_io->{LogFH} } "\n=~=~=~=~=~=~=~=~=~=~= %s CLOSE log %s =~=~=~=~=~=~=~=~=~=~=\n", $ScriptName, scalar localtime;
	close $script_io->{LogFH};
	$script_io->{LogFile} = $script_io->{LogFH} = undef;
}


sub openLogFile { # Handles opening log file
	my $db = shift;
	my $host_io = $db->[3];
	my $script_io = $db->[4];

	if ($script_io->{AutoLog}) { # Auto-log mode
		# If already logging, we close it IF auto-log is active
		closeLogFile($script_io) if defined $script_io->{LogFH};
		# Generate the new filename
		$script_io->{LogFile} = $host_io->{Name};
		$script_io->{LogFile} =~ s/:/_/g;	# Produce a suitable filename for serial ports & IPv6 addresses
		$script_io->{LogFile} =~ s/[\/\\]/-/g;	# Produce a suitable filename for serial ports (on unix systems)
		$script_io->{LogFile} .= '-' . $host_io->{TcpPort} if $host_io->{TcpPort};
		if (length $Default{auto_log_filename_str}) {
			my $timestampfilename = POSIX::strftime($Default{auto_log_filename_str}, localtime);
			if ($timestampfilename =~ s/<>/$script_io->{LogFile}/) {
				$script_io->{LogFile} = $timestampfilename;				# New syntax
			}
			else {
				$script_io->{LogFile} = $timestampfilename . $script_io->{LogFile};	# Legacy syntax
			}
		}
		$script_io->{LogFile} .= '.log';
		$script_io->{OverWrite} = '>>'; # We always append in auto-log mode
	} # If not in auto-log mode, existing logging is preserved

	if ($script_io->{LogFile} && !defined $script_io->{LogFH}) {
		my ($logfile, @subdirs);
		my $logpath = '';
		$logpath = $script_io->{LogDir} . "/" if $script_io->{LogDir};
		if ($script_io->{AutoLog}) {
			if ($script_io->{LogFile} =~ /[\/\\]/) { # filename includes partial path
				@subdirs = split(/[\/\\]/, $script_io->{LogFile});
				pop @subdirs; # Remove the filename, just keep the sub directories
			}
		}
		elsif ($script_io->{LogFile} =~ /[\/\\]/) { # filename includes path; case where logfile provided on command line or via @log start
			$logpath = '';	# then we don't use the LogDir (preserve original behaviour)
		}
		$logfile = $logpath . $script_io->{LogFile};	# append it to the LogDir
		$script_io->{LogFullPath} = File::Spec->rel2abs($logfile); # Set this now, as we might fail on the mkdir
		if (@subdirs) { # We have sub-directories to create
			for my $subdir (@subdirs) {
				$logpath .= $subdir;
				unless (-e $logpath && -d $logpath) { # Sub directory does not exist, create it
					mkdir $logpath or do {
						$script_io->{LogFile} = undef;
						$script_io->{AutoLogFail} = 1 if $script_io->{AutoLog};
						return; # Failed to open file (mkdir)
					};
				}
				$logpath .= "/";
			}
		}
		if ( open($script_io->{LogFH}, $script_io->{OverWrite}, $logfile) ) {
			printf { $script_io->{LogFH} } "\n=~=~=~=~=~=~=~=~=~=~= %s OPEN  log %s =~=~=~=~=~=~=~=~=~=~=\n", $ScriptName, scalar localtime;
			$script_io->{AutoLogFail} = 0 if $script_io->{AutoLog};
			return 1; # File opened successfully
		}
		else { # Failed to open...
			$script_io->{LogFH} = undef; # Needs to happen before printOut()
			$script_io->{LogFile} = undef;
			$script_io->{AutoLogFail} = 1 if $script_io->{AutoLog};
			return; # Failed to open file
		}
	}
	return 0; # No file to open
}

1;
