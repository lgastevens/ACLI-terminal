# ACLI sub-module
package AcliPm::CacheFeedInputs;
our $Version = "1.00";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(cacheFeedInputs applyFeedInputs);
}
use Cpanel::JSON::XS;
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::GlobalDefaults;
use AcliPm::DebugMessage;
use AcliPm::Print;

my $JsonCoder = Cpanel::JSON::XS->new->ascii->pretty->allow_nonref->canonical->unblessed_bool(1);


sub loadCacheFeedInputs { # Loads acli.cache file if local data absent or stale
	my $db = shift;
	my $cacheInputs = $db->[18];
	my $cacheFile;

	# Try and find acli.cache file in the paths available
	PATH: foreach my $path (@AcliFilePath) {
		if (-e "$path/$AcliCacheFile") {
			$cacheFile = "$path/$AcliCacheFile";
			last PATH;
		}
	}
	unless ($cacheFile) {
		return 1 if $cacheInputs->{timestamp}; # We already have a structure loaded...
		return; # No structure loaded and no file found
	}
	debugMsg(1, "CacheFileRead: Found file: ", \$cacheFile, "\n") if $cacheFile;

	if ($cacheInputs->{timestamp}) { # File was already loaded into internal structure...
		my $fileModifyTime = (stat($cacheFile))[9]; # Get file's last modify time (mtime)
		return 1 if $fileModifyTime < $cacheInputs->{timestamp}; # We have latest already loaded, come out
	}

	# If we get here, either we never loaded the file or the file was modified since we last read it
	# So we read the file
	debugMsg(1, "CacheFileRead: Loading file: ", \$cacheFile, "\n");

	open(CACHE, '<', $cacheFile) or return;
	flock(CACHE, 1); # 1 = LOCK_SH; Put a shared lock on the file (wait to read if it's being changed)
	local $/;	# Read in file in one shot
	$cacheInputs->{data} = $JsonCoder->decode(<CACHE>);
	$cacheInputs->{timestamp} = time(); # Update structure timestamp
	close CACHE;

	return 1;
}


sub saveCacheFeedInputs { # Saves command feed input data to acli.cache file
	my $db = shift;
	my $cacheInputs = $db->[18];
	my $cacheFile = join('', $AcliFilePath[0], '/', $AcliCacheFile);

	debugMsg(1, "CacheFileSave: Saving file: ", \$cacheFile, "\n");
	open(CACHE, '>', $cacheFile) or return;
	flock(CACHE, 2); # 2 = LOCK_EX; Put an exclusive lock on the file as we are modifying it
	print CACHE $JsonCoder->encode($cacheInputs->{data}); # Pretty format
	close CACHE;
	return 1;
}


sub cacheFeedInputs { # Update feed input cache data and save to acli.cache file
	my ($db, $command, $cachekey, $inputListRef) = @_;
	my $term_io = $db->[2];
	my $script_io = $db->[4];
	my $cacheInputs = $db->[18];

	# Make sure we have the latest cache data already loaded
	loadCacheFeedInputs($db);

	# Update cache data with new data provided
	$cacheInputs->{data}->{$command}->{$cachekey} = $inputListRef;

	# Save/update acli.cache file
	saveCacheFeedInputs($db);

	# Display message
	unless ($term_io->{EchoOutputOff} && $term_io->{Sourcing}) {
		printOut($script_io, "$ScriptName: Cached input to above command\n" );
	}
}


sub applyFeedInputs { # Check command if in inputs cache data and if there apply cached FeedInputs
	my ($db, $command) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $cacheInputs = $db->[18];

	# Make sure we have the latest cache data already loaded
	return unless loadCacheFeedInputs($db); # and come out if no cached data

	# Check if command has cached input data
	return unless exists $cacheInputs->{data}->{$command};

	# Check if cached data applies to this host or device family type
	if (defined $host_io->{BaseMAC} && exists $cacheInputs->{data}->{$command}->{$host_io->{BaseMAC}}) {
		@{$term_io->{FeedInputs}} = @{$cacheInputs->{data}->{$command}->{$host_io->{BaseMAC}}};
	}
	elsif (defined $host_io->{Type} && exists $cacheInputs->{data}->{$command}->{$host_io->{Type}}) {
		@{$term_io->{FeedInputs}} = @{$cacheInputs->{data}->{$command}->{$host_io->{Type}}};
	}
	debugMsg(4,"=applying cache FeedInputs: // ", \join(' // ', @{$term_io->{FeedInputs}}), "\n") if @{$term_io->{FeedInputs}};
}

1;
