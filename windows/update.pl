# This script pulls from HTTPS/HTTP/FTP a list of latest files making the distribution
# It then compares those versons with the ones currently installed
# User is then asked whether to do an update (or a roll back)

my $Version = "1.21";

# Written by Ludovico Stevens (lstevens@extremenetworks.com)
# Changes
# 1.00	Initial version
# 1.01	Enhanced to always copy across Changes file as well
#	Changed Zip Download (D) option to fetch full installer from server ./downloads directory
# 1.02	Changes to allow update of already existing file with no version (acli.alias)
#	Update script version now added to log file and banner
#	If new version of itself exists, this script now only updates itself, then runs new version of itself for rest of updates
#	When doing update, rollback directory, if already present, is now purged of existing files (directory deleted and re-created)
#	Was allowing update even when not possible due to inconsistent Perl version/flavour or Perl modules in distributon
#	Perl version/flavour and module digest version now shown in listed tables
#	Update.log files are now saved for certain outcomes with a timestamp in file name so as not to be overridden
#	Ported same fix as acli.pl wherby messages about Perl Interpreter stopped working are suppressed when closing window
# 1.03	If updates existed, manual (M) option to provide different URL was failing to allow update due to wrong digest
# 1.04	If local bundled file (file with no extension containing list of files - ConsoleZ) does not exist, its update is not taken
# 1.05	Rollback directory was sometimes not re-created after being deleted during update
#	Cannot update Console.exe if update script is running within it; added checks to prevent updates if update exe files are running
# 1.06	Modified fileVersion sub to detect Version numbers from new run scripts
# 1.07	Method readSubFiles() was being called with a relative path and could cause script not to do exeIsRunning() on Console.exe
# 1.08	Was not able to push files with no version, like launch batch files (cfm-test.bat)
# 1.09	Added more logic around updating files with no version, or files that were not already present; also rollback cases (see update.RULES) 
# 1.10	If the default ZIP download directory (D option) does not exist, the update script now asks user to provide a valid directory
# 1.11	Added logic to check whether update script is launched in a directory where user has no write access and in that case go no further
#	Added new public Internet update server to replace the Avaya ftp.avaya.com server when/if it eventually goes offline 
# 1.12	Update script is now able to fetch the update files as zip files
# 1.13	Updated the with the Extreme servers
#	Rollback was not working properly with Perl modules which did not exist prior to update
# 1.14	Update script now able to detect whether it has write access in install directory and if not to restart with admin priviledges
#	Had to remove use of smartmatch ~~ for comparing arrays as this is being discountinued since Perl 5.2x
# 1.15	Update.log file now records whether the directory was writeable on start and whether this script is running with Admin rights
# 1.16	Fix to allow update to offer new exe installer instead of old zip file in cases where a new install is required for the updates
#	Modified to operate for MACOS ACLI distribution as well as Windows distribution
#	Use of update.skip.<OS> file used to skip files which are not applicable to OS distribution
# 1.17	If an offered update file does not already exist and it needs to reside is a sub-directory, now the update script can create that
#	directory (if it is just 1 level); this was added to allow a pre-5.00 instal to be able to update to a 5.00 release with AcliPm files
# 1.18	Changed order of update servers; Internet link is tried first now.
# 1.19	Updated AcliPm module file versions were incorrectly deducted from the Perl dist digests which was making the update impossible
# 1.20	Updated to be able to read the version of a Visual Basic .vbs file, where the comment character is single quote "'"
# 1.21	Added new Github URL and fixed HTTPS retrieval of updates


#############################
# STANDARD MODULES          #
#############################

use strict;
use warnings;
no warnings 'redefine'; # To supress warnings of redefined subs when calling updated verson of itself
use version 0.77;
use 5.010; # required for state declarations
use Cwd;
use File::Path qw(remove_tree);
use File::Spec;
use File::Copy;
use File::Basename;
use Term::ReadKey;
use LWP::Simple;
use Net::FTP;
use Archive::Zip qw( :ERROR_CODES );
use Win32::RunAsAdmin;
use Win32API::File;
Win32API::File::SetErrorMode(2); # This is supposed to suppress windows message about Perl Interpreter stopped working, when closing Window


#############################
# VARIABLES                 #
#############################

my $SanityCheck = 0;	# 1 = No actual change is made; 0 = We go for it
my $Debug = 0;		# Show debug messages of changes being made
my $LogToFile = 1;	# Record activity to log file
my $ScriptName = basename($0);
my $InstallPath = dirname(File::Spec->rel2abs($0)) . '\\';
my $UserHomePath = $ENV{'USERPROFILE'} . '\\';
my $DownloadPath = $UserHomePath . 'Downloads\\';
my $PerlPath = $InstallPath . 'Perl\\';
my $UpdatePath = $InstallPath . 'updates\\';
my $RollbackPath = $UpdatePath . 'rollback\\';
my @UpdateServers = (
	'https://github.com/lgastevens/ACLI-terminal/releases/download/updates',# Github
#	'http://www.oranda.fr/ACLI-terminal/updates',				# Web server on public Internet (in France)
#	'http://dante.extremenetworks.com/ACLI-terminal/updates',		# Extreme corporate (in Singapore)
#	'http://nhweb.labs.extremenetworks.com/ACLI-terminal/updates',		# Extreme corporate (in US)
);
my $PerlDigest = 'version.digest';
my $PerlDigestPath = $PerlPath . $PerlDigest;
my $UpdateDigest = 'update.digest';
my $UpdateDigestPath = $UpdatePath . $UpdateDigest;
my $RollbackDigest = 'rollback.digest';
my $RollbackDigestPath = $RollbackPath . $RollbackDigest;
my $Changes = 'Changes';
my $ChangesPath = $InstallPath . $Changes;
my $UpdateSkip = 'update-skip.' . $^O;	# Will be a different file for MSWin32 & darwin
my $UpdateSkipPath = $InstallPath . $UpdateSkip;
my $FTPtimeout = 10;

my ($ExecMode, $UpdateUrl);
($ExecMode, $UpdateUrl) = (1, $ARGV[0]) if @ARGV;

my $LogFilename = $InstallPath . 'update.log';
my $LogHandle;


#############################
# INIT CODE                 #
#############################

# Do this at the very begining, before setting the die handler
my $RunAsAdmin = Win32::RunAsAdmin::check;
my $DirWriteable = &checkPathWriteAccess;
Win32::RunAsAdmin::restart unless $DirWriteable || $RunAsAdmin;

# Start the log file now
if ($LogToFile) {
	open($LogHandle, $ExecMode ? '>>':'>', $LogFilename) or do {
		undef $LogHandle;
		exitError("\nUnable to open log file in update script directory for reason: $!\nMake sure update script has write-access to directory!\n");
	};
}


#############################
# FUNCTIONS                 #
#############################

sub printLog { # Print a message to logfile
	if ($LogHandle) {
		my $msg = shift;
		print {$LogHandle} $msg, "\n";
	}
}

sub printfLog { # Printf a message to logfile
	if ($LogHandle) {
		my $template = shift;
		my @data = @_;
		printf {$LogHandle} "$template\n", @data;
	}
}

sub printOut { # Print a message to screen
	my $msg = shift;
	printLog($msg);
	print $msg, "\n";
	return;
}

sub printfOut { # Printf a message to screen
	my $template = shift;
	my @data = @_;
	printfLog($template, @data);
	printf "$template\n", @data;
	return;
}

sub errorMsg { # Print HTTP/FTP error messages
	my ($msg, $silent) = @_;
	printLog($msg);
	print "\n", $msg, "\n" unless $silent;
	return;
}

sub logCloseSave { # Closes the logfile and makes a copy of it if a type is set
	my $type = shift;
	close $LogHandle;
	return unless $type;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime;
	my $stamp = sprintf "%02d%02d%02d%02d%02d%02d", $year - 100, $mon, $mday, $hour, $min, $sec;
	(my $saveFile = $LogFilename) =~ s/\.log$/\.$type$stamp\.log/;
	copy($LogFilename, $saveFile);
}

sub exitError { # Come out with an error message
	my $msg = shift;
	print $msg, "\n";
	printLog($msg);
	logCloseSave('err') if $LogHandle;
	system("pause");
	exit 1;
}

sub exitSuccess { # Come out with a success message
	my ($msg, $type) = @_;
	if (defined $msg) {
		print $msg, "\n";
		printLog($msg);
	}
	logCloseSave($type) if $LogHandle;
	system("pause");
	exit 0;
}

sub doMkdir { # Mkdir a directory
	my $dir = shift;
	printLog("Creating directory $dir");
	unless ($SanityCheck) {
		mkdir $dir or die "Mkdir failed: $!";
	}
}

sub doCopy { # Copy a file
	my ($source, $destination) = @_;
	printLog("COPY   $source  ->  $destination");
	unless ($SanityCheck) {
		copy($source, $destination) or die "Copy failed: $!";
	}
}

sub doMove { # Move a file
	my ($source, $destination) = @_;
	printLog("MOVE   $source  ->  $destination");
	unless ($SanityCheck) {
		move($source, $destination) or die "Move failed: $!";
	}
}

sub doDelete { # Delete (unlink) a file
	my $file = shift;
	printLog("Deleting file $file");
	unless ($SanityCheck) {
		unlink($file) or die "Failed delete of $file\n$!";
	}
}

sub doRmtree { # Rmdir a directory
	my $dir = shift;
	printLog("RMTREE $dir");
	unless ($SanityCheck) {
		remove_tree($dir) or die "Rmtree failed: $!";
	}
}

sub dieHandler { # We trap die to this function
	die @_ unless defined $^S; # Prevents handler being called when "parsing" eval EXPR
	die @_ if $^S; # Prevents handler being called when "executing" eval BLOCK
	# So we exit only if $^S is true(1)
	my $errmsg = shift;
	printLog("\nDIE handler:\n============\n");
	print "\nDIE handler:\n============\n";
	if (defined $errmsg) {
		printLog($errmsg);
		print $errmsg;
	}
	print "\n";	# Extra newline..
	logCloseSave('die') if $LogHandle;
	system("pause");
	exit 1;
}

sub httpGet {
	my ($server, $file, $savePath, $mode) = @_;

	printLog("httpGet $file from $server");
	my $url = $server . ($server =~ /\/$/ ? '' : '/') . $file;
	is_success(getstore($url, $savePath.$file)) or return errorMsg("Cannot HTTP get $file", $mode);
	print '.'; printLog("HTTP get succeeded");
	return 1;
}

sub ftpGet {
	my ($server, $file, $savePath, $mode) = @_;

	printLog("ftpGet $file from $server");
	$server =~ s/^ftp:\/\/(\w+):([^@]+)@//;
	my ($user, $pwd) = ($1, $2);
	printLog("FTP credentials = $user / $pwd");
	$server =~ s/\/(.+)$//;
	my $path = $1;
	printLog("FTP path = $path");

	# FTP to pull digest of latest files
	my $ftp = Net::FTP->new($server, Timeout => $FTPtimeout) or return errorMsg("Cannot FTP connect to Update Server: $@", $mode);
	$ftp->login($user, $pwd) or return errorMsg("Cannot login to Update Server: ".$ftp->message, $mode);
	print '.'; printLog("FTP login succeeded");
	$ftp->cwd($path) or return errorMsg("Cannot change to directory $path: ".$ftp->message, $mode);
	print '.'; printLog("FTP cwd succeeded");
	$ftp->binary;
	print '.'; printLog("FTP bin succeeded");
	$ftp->get($file, $savePath.$file) or return errorMsg("Get failed: ".$ftp->message, $mode);
	print '.'; printLog("FTP get succeeded");
	$ftp->quit;
	return 1;
}

sub getFile {
	my ($file, $savePath, $zipFile, $newurl, $zipDown) = @_;
	my $updateFile;
	state ($prot, $server);
	my @urls;
	if (length $newurl) {
		@urls = ($newurl);
		($prot, $server) = (); # Undefine them if we have a manual url
	}
	else {
		@urls = @UpdateServers;
	}
	if ($zipFile && !(length $newurl || $zipDown)) { # Fetch a zip update file (filename needs renaming)
		$updateFile = $file;
		$file =~ s/(?:\.([^\.]*))?$/defined $1 ? "_$1" : "_"/e;
		$file .= '.zip';
		printLog("Fetching ZIP file $file");
	}

	if (!defined $prot) {
		foreach my $url (@urls) {
			print "Trying $url ";
			if ($url =~ /^(ftp|https?):/) {
				$prot = $1;
			}
			else {
				$prot = 'http';
			}
			$url =~ s/\/$file$//;	# If file appended, remove it
			if ( ($prot eq 'ftp' && ftpGet($url, $file, $savePath, 1)) || ($prot =~ /^https?$/ && httpGet($url, $file, $savePath, 1) ) ) {
				$server = $url;
				print "\n";
				last;
			}
			print "\n";
		}
		return errorMsg("Unable to contact update servers") unless defined $server;
		return $server; # Otherwise
	}
	elsif ($zipDown) {
		my $url = $server; 
		$url =~ s/\/updates\/?/\/downloads/;
		print "Trying $url/$file\nDownloading to folder $savePath\n";
		return ftpGet($url, $file, $savePath) if $prot eq 'ftp';
		return httpGet($url, $file, $savePath) if $prot eq 'http';
	}
	else {
		my $status;
		$status = ftpGet($server, $file, $savePath) if $prot eq 'ftp';
		$status = httpGet($server, $file, $savePath) if $prot eq 'http';
		return unless $status;
		if ($zipFile) { # We got a zip file, unzip it and delete the zip file
			my $zip = Archive::Zip->new();
			$zip->read($savePath.$file) == AZ_OK or return errorMsg("Unable to read zip file $file");
			$zip->extractTree('', $savePath) == AZ_OK or return errorMsg("Unable to zip extract file $updateFile");
			printLog("Zip extracted file $updateFile");
			doDelete($savePath.$file);
		}
		return 1;
	}
}

sub readUpdateSkip { # Read the update-skip.<OS> file; return a hash with contents
	my $skipFile = shift;
	my %skipFiles = ();
	if (-e $skipFile) {
		printLog("Reading Update-Skip file: $skipFile");
		open(SKIP, '<', $skipFile) or die "Can't open update skip file: $!";
		while(<SKIP>) {
			chomp;
			/^\s*__END__/ && last;
			/^\s*#/ && next; # Comment lines
			/^\s*(\S+)\s*$/ && do {
				$skipFiles{$1} = 1;
				printLog(" - $1");
			};
		}
		close SKIP;
	}
	else {
		printLog("No Update-Skip file found");
	}
	return \%skipFiles;
}

sub readDigest { # Read digest file
	my ($digestFile, $skipFile) = @_;
	my (%hash, @list, %digest, $latestZip, $updatesZipped);
	my $skipFiles = defined $skipFile ? readUpdateSkip($skipFile) : {};

	printLog("Reading Digest file: $digestFile");
	open(DIGEST, '<', $digestFile) or die "Can't open digest file: $!";
	while(<DIGEST>) {
		chomp;
		printLog("	$_");
		next if /^\s*$/; # skip empty lines
		next if /^\s*#/; # skip comment lines
		/^(\w[\w\.-]+?\.(?:zip|exe))$/ && do {
			$latestZip = $1;
			next;
		};
		/^(\w+) Perl (v\d+\.\d+\.\d+)\s*$/ && do {
			$digest{PerlFlavour} = $1;
			$digest{PerlVersion} = $2;
			next;
		};
		/^DISTRIBUTION VERSION DIGEST\s*(\d+)\.(\d+)_(\d+)-(\d+)-(\d+)\s*$/ && do {
			$digest{ModVersions} = [$1, $2, $3, $4, $5];
			next;
		};
		/^UPDATES-ARE-ZIPPED\s*$/ && do {
			$updatesZipped = 1;
			next;
		};
		/^(\S+)(?:(?:\s+([\d\._]+|unknown))?(?:\s+(\S+))?)?\s*$/ && do {
			my ($key, $ver, $path) = ($1, $2, $3);
			if (exists $skipFiles->{$key}) {
				printLog("<above key was update-skipped>");
				next;
			}
			push(@list, $key);
			if (!defined $ver) { # Undefined
				$hash{$key}->{Version} = '';
			}
			elsif ($ver !~/\d/) { # e.g. 'unknown'
				$hash{$key}->{Version} = $ver;
			}
			else {
				$hash{$key}->{Version} = version->parse("$ver");
			}
			$hash{$key}->{Path} = defined $path ? $path : '';
			$hash{$key}->{Path} .= '\\' if length $hash{$key}->{Path} && $hash{$key}->{Path} !~ /\\$/;
			next;
		};
		printLog("<above line was ignored>");
	}
	close DIGEST;
	return (\%hash, \@list, \%digest, $latestZip, $updatesZipped);
}

sub readPerlDigest { # Read perl digest file
	my %digest;

	printLog("Reading Distribution Digest file: $PerlDigestPath");
	open(DIGEST, '<', $PerlDigestPath) or die "Can't open Perl digest file: $!";
	while(<DIGEST>) {
		chomp;
		next if /^\s*$/; # skip empty lines
		next if /^\s*#/; # skip comment lines
		/^(\w+) Perl (v\d+\.\d+\.\d+)\s*$/ && do {
			$digest{PerlFlavour} = $1;
			$digest{PerlVersion} = $2;
			next;
		};
		/^DISTRIBUTION VERSION DIGEST\s*(\d+)\.(\d+)_(\d+)-(\d+)-(\d+)\s*$/ && do {
			$digest{ModVersions} = [$1, $2, $3, $4, $5];
			next;
		};
	}
	close DIGEST;
	return \%digest;
}

sub fileVersion { # Read version of local files
	# Returns the version of the file if the file exists and has a version number within
	# Returns 'unknown' if the file exists but no version number within
	# Returns '' if the file does not exist
	my $file = shift;
	my $path = shift || '';
	my $version = '';
	$path .= '\\' if length $path && $path !~ /\\$/;
	my $filePath = join('', $InstallPath, $path, $file);
	return '' unless -e $filePath;
	open(FILE, '<', $filePath) or return '';
	my $line = 0;
	LINE: while (<FILE>) {
		chomp;
		$line++;
		/^\s*__END__/ && last;
		/^\s*#/ && !/^\#\s*VERSION\s*=\s*([\d\.]+)$/i && next; # Comment lines
		(/^\s*(?:our|my)?\s*\$VERSION\s*=([^~].*)$/i || /^[#;\']\s*VERSION\s*=\s*([\d\.]+)$/i) && do {
			my $versionString = $1;
			if ($versionString =~ /.*?[\"\']?(\d+(?:\.\d+)+(?:_\d+)?)[\"\']?/) {
				$version = version->parse($1);
				printLog("File $file line $line local version $version");
			}
			elsif (!$version) { # Unless we already recorded a version number for this module..
				printLog("File $file line $line unable to read local version");
			}
			last;
		};
	}
	close FILE;
	$version = 'unknown' unless length $version;
	return $version;
}

sub readMenuKey { # Accept user menu option key
	my @validKeys = split(//, shift);
	my $key;
	do {
	        select(undef, undef, undef, 0.1); # Fraction of a sec sleep (otherwise CPU gets hammered..)
		$key = ReadKey(-1);
	} until defined $key && grep(/^$key$/i, @validKeys);
	printLog("\nreadMenuKey = $key");
	return uc $key;
}

sub adjustModVersionDigest { # Deduct provided version from perl digest version
	my ($hashRef, $version) = @_;

	$version =~ /(\d+)\.(\d+)(?:_(\d+))?/ and do {
		$hashRef->{ModVersions}[0] -= $1;
		$hashRef->{ModVersions}[1] -= $2;
		$hashRef->{ModVersions}[2] -= $3 if defined $3;
		$hashRef->{ModVersions}[3]--;
		$hashRef->{ModVersions}[4]--;
	};
	printLog("Adjusted ModVersion digest to: " . join('.', @{$hashRef->{ModVersions}}));
}

sub readSubFiles { # Files with no extension, are a list of subfiles
	my $file = shift;
	my @subfiles = ();

	if ($file !~ /\./) {
		printLog("readSubFiles of $file");
		if (open(FILE, '<', $file)) {
			while (<FILE>) {
				chomp;
				/^\s*__END__/ && last;
				/^\s*#/ && next; # Comment lines
				/^\s*(\S+)\s*$/ && do {
					push(@subfiles, $1);
					printLog(" - $1");
				};
			}
			close FILE;
		}
		else {
			printLog("readSubFiles failed to read file: $!");
		}
	}
	return @subfiles;
}

sub exeIsRunning { # Checks whether the provided exe file is running on the system, which would imply it cannot be deleted/replaced
	my $exeFile = shift;
	printLog("exeIsRunning checking file $exeFile");
	my $tasklist = `tasklist /FI "IMAGENAME eq $exeFile"`;
	return 1 if $tasklist =~ /^$exeFile/m;
	return 0; # Otherwise
}

sub exeRunningList { # Given a list of files, produces a list of which are currently running (exe files)
	my @exeList = @_;
	my @exeRunningList = ();
	foreach my $exe (@exeList) {
		push(@exeRunningList, $exe) if exeIsRunning($exe);
	}
	return @exeRunningList;
}

sub checkPathWriteAccess { # Tests the install directory to see whether we have write access on it
	my $testWriteFile = $InstallPath . '\check_write';
	my $dirWriteable = open(FH, '>', $testWriteFile) ? 1 : 0;
	close(FH);
	unlink('check_write') if $dirWriteable;
	return $dirWriteable;
}

sub compareArrays { # Workaround function since the loss of smartmatch ~~ operator
	my ($arrayRef1, $arrayRef2) = @_;
	return @$arrayRef1 == @$arrayRef2 && !grep { !$_ } map { $arrayRef1->[$_] eq $arrayRef2->[$_] } 0 .. $#$arrayRef1;
}


#############################
# MAIN                      #
#############################

$SIG{__DIE__}  = 'dieHandler';

MAIN:{
	printLog($ScriptName . " verion " . $Version . " - Timestamp " . localtime);
	printLog($DirWriteable ? 'Install directory is writeable' : 'Install directory was not writeable');
	printLog($RunAsAdmin ? 'Running as Administrator' : 'Running without Administrator rights');

	# Now we can get started
	my (@updatable, @exeUpdatable, @exeRunning);
	my ($update, $order, $distDigest, $perlDigest, $updateFlag, $rollbackFlag, $downloadFlag, $zipFilename, $updatesZipped, $updateMe, $updateOs, $server);
	my $updateUrl = $UpdateUrl;
	local $| = 1;

	# If an updates directory does not exist, create one now
	doMkdir($UpdatePath) unless -e $UpdatePath && -d $UpdatePath;

	while (1) {
		system("cls") unless $Debug || $ExecMode; # Clear the screen
		print "==========================\n";
		print "ACLI Update script (v$Version)\n";
		print "==========================\n";
		print "\n";

		# Record local Perl digest signatures
		$perlDigest = readPerlDigest();
		printLog("Local ModVersion digest is: " . join('.', @{$perlDigest->{ModVersions}}));

		# Re-init storage variables
		@updatable = @exeUpdatable = @exeRunning = (); # Reset to zero
		$updateFlag = $downloadFlag = $updateMe = $updateOs = 0;
		$zipFilename = $server = '';

		# Get the update digest file
		if ( $server = getFile($UpdateDigest, $UpdatePath, 0, $updateUrl) ) {

			# Read digest file
			($update, $order, $distDigest, $zipFilename, $updatesZipped) = readDigest($UpdateDigestPath, $UpdateSkipPath);
			if (keys %$update) { # If we have update files, see if some are more recent than what we have
				foreach my $file (@$order) {
					$update->{$file}->{Installed} = fileVersion($file, $update->{$file}->{Path});
					if (	# (i) We have this file installed with a reported version, but a newer version is available in the update
						(ref $update->{$file}->{Installed} eq 'version' && ref $update->{$file}->{Version} eq 'version' && $update->{$file}->{Installed} < $update->{$file}->{Version})
					     ||	# (ii) We do not have this file installed, so always take it
						(ref $update->{$file}->{Installed} ne 'version' && $update->{$file}->{Installed} eq '')
					     ||	# (iii) We have this file installed but it has no version; only take the update if marked with a version
						(ref $update->{$file}->{Installed} ne 'version' && $update->{$file}->{Installed} eq 'unknown' && ref $update->{$file}->{Version} eq 'version')
					    ) {
						$updateFlag = 1;
						push(@updatable, $file);
						if ($file =~ /\.exe$/) { # An exe file
							push(@exeUpdatable, $file);
							push(@exeRunning, $file) if exeIsRunning($file);
						}
						foreach my $subfile (readSubFiles($InstallPath.$file)) { # Exe checking for subfiles
							if ($subfile =~ /\.exe$/) { # An exe file
								push(@exeUpdatable, $subfile);
								push(@exeRunning, $subfile) if exeIsRunning($subfile);
							}
						}
						$updateMe = 1 if $file eq $ScriptName;	# Newer version of this update script available
						$updateOs = 1 if $file eq $UpdateSkip; # Newer version of the update-skip file
						# Adjust ModVersions to exclude this update file if it is a file with a path other than 'AcliPm' (indicating it is under Perl dir)
						adjustModVersionDigest($distDigest, $update->{$file}->{Version}) if length $update->{$file}->{Path} && $update->{$file}->{Path} !~ /^AcliPm/;
						adjustModVersionDigest($perlDigest, $update->{$file}->{Installed}) if length $update->{$file}->{Path} && $update->{$file}->{Path} !~ /^AcliPm/;
					}
				}
				if ($updateFlag) { # If some more recent, list those only
					$updateMe = 0 if scalar @updatable == 1; # Only if more than just the update script needs updating
					printOut("\nUpdate file               Available version         Installed version");
					printOut("---------------------------------------------------------------------");
					if ($distDigest->{PerlFlavour} ne $perlDigest->{PerlFlavour} || $distDigest->{PerlVersion} ne $perlDigest->{PerlVersion}) {
						printfOut("%-25s %-25s %-25s %s", 'Perl Interpreter', $distDigest->{PerlFlavour}.'-'.$distDigest->{PerlVersion}, $perlDigest->{PerlFlavour}.'-'.$perlDigest->{PerlVersion}, '');
					}
					if ( !compareArrays($distDigest->{ModVersions}, $perlDigest->{ModVersions}) ) {
						printfOut("%-25s %-25s %-25s %s", 'Perl Mods Digest', join('-', @{$distDigest->{ModVersions}}), join('-', @{$perlDigest->{ModVersions}}), '');
					}
					foreach my $file (@updatable) {
						printfOut("%-25s %-25s %-25s %s", $file, $update->{$file}->{Version}, $update->{$file}->{Installed}, $Debug ? $update->{$file}->{Path} :'');
					}
					# Now check whether we have a compatible distribution
					if ($distDigest->{PerlFlavour} ne $perlDigest->{PerlFlavour} || $distDigest->{PerlVersion} ne $perlDigest->{PerlVersion}) {
						printOut("\nUpdated versions run on new Perl distribution $distDigest->{PerlFlavour} $distDigest->{PerlVersion}");
						printOut("Update is not possible");
						printOut("Please obtain new install zip file using (D) option") if $zipFilename;
						$downloadFlag = 1;
						$updateFlag = 0;
					}
					elsif ( !compareArrays($distDigest->{ModVersions}, $perlDigest->{ModVersions}) ) {
						printOut("\nUpdated versions require additional Perl Modules in distribution");
						printOut("Update is not possible");
						printOut("Please obtain new install zip file using (D) option") if $zipFilename;
						$downloadFlag = 1;
						$updateFlag = 0;
					}
					elsif (@exeRunning) {
						printOut("\nWARNING, these exe files cannot be updated while running: " . join(', ', @exeRunning));
					}
				}
				else {
					printOut("\nAll files are up to date!");
				}
			}
		}

		# See if we have rollback files
		$rollbackFlag = -d $RollbackPath && -e $RollbackDigestPath;

		# Print list of available actions
		print "\nSelect desired action:\n\n";
		print "  (S) - Show full listing of all available update files and versions\n";
		if ($updateFlag) {
			print "  (U) - Perform update for files which have a newer version\n";
			if ($updateMe) {
				print "        (Note: newer version of this update script; this script will be updated\n";
				print "         first; then the new update script will be used for the other updates)\n";
			}
			elsif ($updateOs) {
				print "        (Note: newer version of the update OS file; this file will be updated\n";
				print "         first; then the update script will run again for the other updates)\n";
			}
		}
		print "  (R) - Rollback and reverse last update performed\n" if $rollbackFlag;
		print "  (M) - Provide alternative URL where to pull updates\n";
		print "  (D) - Download latest zip installation file\n" if $downloadFlag && $zipFilename;
		print "  (Q) - Quit\n\n";

		my $validKeys = 'SMQ' . ($updateFlag ? 'U':'') . ($rollbackFlag ? 'R':'') . ($downloadFlag && $zipFilename ? 'D':'');
		my $key = readMenuKey($validKeys);

		$key eq 'S' && do { # Display full list of available update files
			printOut("\nUpdate file               Available version         Installed version");
			printOut("---------------------------------------------------------------------");
			printfOut("%-25s %-25s %-25s %s", 'Perl Interpreter', $distDigest->{PerlFlavour}.'-'.$distDigest->{PerlVersion}, $perlDigest->{PerlFlavour}.'-'.$perlDigest->{PerlVersion}, '');
			printfOut("%-25s %-25s %-25s %s", 'Perl Mods Digest', join('-', @{$distDigest->{ModVersions}}), join('-', @{$perlDigest->{ModVersions}}), '');
			foreach my $file (@$order) {
				printfOut("%-25s %-25s %-25s %s", $file, $update->{$file}->{Version}, $update->{$file}->{Installed}, $Debug ? $update->{$file}->{Path} :'');
			}
			print "\n\n";
			exitSuccess;
		};

		$key eq 'U' && do { # Do the update
			# First make sure that if some exe files are to be updated, they must not be running, as we cannot delete an exe file which is running
			if (@exeUpdatable) {
				@exeRunning = exeRunningList(@exeUpdatable); # Re-check this list
				if (@exeRunning) {
					print "Cannot perform update of these exe files if they are running: ", join(', ', @exeRunning), "\n";
					print "Retry or Quit (R/Q) ?";
					my $key = readMenuKey('RQ');
					print "\n\n";
					exitSuccess("No update performed") if $key eq 'Q';
					@exeRunning = exeRunningList(@exeUpdatable); # Try again
					exitError("Cannot perform update; these exe files are still running: " . join(', ', @exeRunning)) if @exeRunning;
				}
			}
			# Fetch all the files in the update directory
			print "Fetching update files ";
			if ($updateMe || $updateOs) { # One or the other
				if ($updateMe) { # We only update this update script
					getFile($ScriptName, $UpdatePath, $updatesZipped) or exitError("Unable to complete $ScriptName update");
				}
				if ($updateOs) { # Make sure we also take the skip file if a newer one exists
					getFile($UpdateSkip, $UpdatePath, $updatesZipped) or exitError("Unable to complete $UpdateSkip update");
				}
			}
			else { # Normal update procedure
				foreach my $file (@updatable) {
					getFile($file, $UpdatePath, $updatesZipped) or exitError("Unable to complete update");
					print '.';
					foreach my $subfile (readSubFiles($UpdatePath.$file)) {
						getFile($subfile, $UpdatePath, $updatesZipped) or exitError("Unable to complete update");
						print '.';
					}
				}
				# Also the Perl version digest and Changes files
				getFile($PerlDigest, $UpdatePath, $updatesZipped) or exitError("Unable to complete update");
				print '.';
				getFile($Changes, $UpdatePath, 0) or exitError("Unable to complete update");
			}
			print "\n";

			# Make sure a roll back directory exists (delete existing and re-create)
			unless ($ExecMode) { # In exec mode, we will append updates to existing files
				doRmtree($RollbackPath) if -e $RollbackPath && -d $RollbackPath;
				doMkdir($RollbackPath);	# Always create new directory (we removed it above)
			}

			# Now backup the existing files in the rollback directory
			print "Backing up existing files ";
			if ($updateMe || $updateOs) { # One or the other
				if ($updateMe) { # We only update this update script
					doDelete($RollbackPath.$ScriptName) if -e $RollbackPath.$ScriptName;
					doCopy($InstallPath.$ScriptName, $RollbackPath.$ScriptName);
					print '.';
				}
				if ($updateOs) { # Make sure we also take the skip file if a newer one exists
					doDelete($RollbackPath.$UpdateSkip) if -e $RollbackPath.$UpdateSkip;
					doCopy($InstallPath.$UpdateSkip, $RollbackPath.$UpdateSkip);
					print '.';
				}
			}
			else { # Normal update procedure
				foreach my $file (@updatable) {
					doDelete($RollbackPath.$file) if -e $RollbackPath.$file;
					if ($update->{$file}->{Installed}) { # If the file exists
						doCopy($InstallPath.$update->{$file}->{Path}.$file, $RollbackPath.$file);
						print '.';
						foreach my $subfile (readSubFiles($RollbackPath.$file)) {
							doDelete($RollbackPath.$subfile) if -e $RollbackPath.$subfile;
							doCopy($InstallPath.$update->{$file}->{Path}.$subfile, $RollbackPath.$subfile);
							print '.';
						}
					}
				}
				# Also the Perl version digest and Changes files
				doDelete($RollbackPath.$PerlDigest) if -e $RollbackPath.$PerlDigest;
				doCopy($PerlDigestPath, $RollbackPath.$PerlDigest);
				print '.';
				doDelete($RollbackPath.$Changes) if -e $RollbackPath.$Changes;
				doCopy($ChangesPath, $RollbackPath.$Changes) if -e $ChangesPath;
				print '.';
			}

			# Update/Create a rollback digest file (in execMode we append to existing file)
			open(RDIGEST, $ExecMode ? '>>':'>', $RollbackDigestPath) or die "Can't open file $RollbackDigestPath : $!";
			if ($updateMe || $updateOs) { # One or the other
				if ($updateMe) { # We only update this update script
					printf RDIGEST "%-20s %-10s %s\n", $ScriptName, $update->{$ScriptName}->{Installed}, $update->{$ScriptName}->{Path};
					print '.';
				}
				if ($updateOs) { # Make sure we also take the skip file if a newer one exists
					printf RDIGEST "%-20s %-10s %s\n", $UpdateSkip, $update->{$UpdateSkip}->{Installed}, $update->{$UpdateSkip}->{Path};
					print '.';
				}
			}
			else { # Normal update procedure
				foreach my $file (@updatable) {
					# We place entry whether the file exists (so it can be rolled back) or it does not (version=''; so that it can be deleted)
					printf RDIGEST "%-20s %-10s %s\n", $file, $update->{$file}->{Installed}, $update->{$file}->{Path};
					print '.';
				}
			}
			close RDIGEST;
			print "\n";

			# Now move the new versions into place by over-writing the existing files
			print "Moving new files into place ";
			if ($updateMe || $updateOs) { # One or the other
				if ($updateMe) { # We only update this update script
					doDelete($InstallPath.$ScriptName) if -e $InstallPath.$ScriptName;
					doMove($UpdatePath.$ScriptName, $InstallPath.$ScriptName);
				}
				if ($updateOs) { # Make sure we also take the skip file if a newer one exists
					doDelete($InstallPath.$UpdateSkip) if -e $InstallPath.$UpdateSkip;
					doMove($UpdatePath.$UpdateSkip, $InstallPath.$UpdateSkip);
				}
				print ".\n";
				print "Re-executing update script with updated versions\n";
				printLog("Do -> $InstallPath$ScriptName $server");
				close $LogHandle if $LogHandle;
				{	# This should execute the new updated version of this update script
					local @ARGV = ($server);
					unless (defined do "$InstallPath$ScriptName") {
						exitError("Could not parse new version of this script: $@") if $@;
						exitError("Could not execute new version of this script: $!");
					}
				}
				# If all goes well, we should not return here
				exitError("Unable to exec new version of this script");
			}
			else { # Normal update procedure
				foreach my $file (@updatable) {
					doMkdir($InstallPath.$update->{$file}->{Path}) unless -e $InstallPath.$update->{$file}->{Path}; # Allow creation of 1 level directory
					doDelete($InstallPath.$update->{$file}->{Path}.$file) if -e $InstallPath.$update->{$file}->{Path}.$file;
					doMove($UpdatePath.$file, $InstallPath.$update->{$file}->{Path}.$file);
					print '.';
					foreach my $subfile (readSubFiles($InstallPath.$file)) {
						doDelete($InstallPath.$update->{$file}->{Path}.$subfile) if -e $InstallPath.$update->{$file}->{Path}.$subfile;
						doMove($UpdatePath.$subfile, $InstallPath.$update->{$file}->{Path}.$subfile);
						print '.';
					}
				}
				# Also the Perl version digest and Changes files
				doDelete($PerlDigestPath) if -e $PerlDigestPath;
				doMove($UpdatePath.$PerlDigest, $PerlDigestPath);
				print '.';
				doDelete($ChangesPath) if -e $ChangesPath;
				doMove($UpdatePath.$Changes, $ChangesPath);
				print "\n\n";
				exitSuccess("Update complete. Please restart application to use updated versions", 'upd');
			}
		};

		$key eq 'R' && do { # Do the rollback
			@updatable = @exeUpdatable = @exeRunning = (); # Reset to zero

			# Read rollback digest file
			($update, $order) = readDigest($RollbackDigestPath);

			exitSuccess("No files to rollback from") unless keys %$update;

			# If we have update files, list them now
			foreach my $file (@$order) {
				$update->{$file}->{Installed} = fileVersion($file, $update->{$file}->{Path});
				if (	# (i) Rollback version is older than Installed version
					(ref $update->{$file}->{Installed} eq 'version' && ref $update->{$file}->{Version} eq 'version' && $update->{$file}->{Installed} > $update->{$file}->{Version})
				     ||	# (ii) Rollback version has no version
					(ref $update->{$file}->{Version} ne 'version' && $update->{$file}->{Version} eq 'unknown')
				     ||	# (iii) Rollback version does not exist (just delete Installed)
					(ref $update->{$file}->{Version} ne 'version' && $update->{$file}->{Version} eq '')
				    ) {
					push(@updatable, $file);
					if ($file =~ /\.exe$/) { # An exe file
						push(@exeUpdatable, $file);
						push(@exeRunning, $file) if exeIsRunning($file);
					}
					foreach my $subfile (readSubFiles($InstallPath.$file)) { # Exe checking for subfiles
						if ($subfile =~ /\.exe$/) { # An exe file
							push(@exeUpdatable, $subfile);
							push(@exeRunning, $subfile) if exeIsRunning($subfile);
						}
					}
				}
			}
			printOut("\nRollback file             Available version         Installed version");
			printOut("---------------------------------------------------------------------");
			foreach my $file (@$order) {
				printfOut("%-25s %-25s %-25s %s", $file, length $update->{$file}->{Version} ? $update->{$file}->{Version} : 'delete', $update->{$file}->{Installed}, $Debug ? $update->{$file}->{Path} :'');
			}
			printOut("\nWARNING, these exe files cannot be rolled back while running: " . join(', ', @exeRunning)) if @exeRunning;

			# Ask for comfirmation
			print "\nOk to rollback (Y/N) ?";
			my $key = readMenuKey('YN');
			print "\n\n";
			exitSuccess("No rollback performed") if $key eq 'N';

			# First make sure that if some exe files are to be updated, they must not be running, as we cannot delete an exe file which is running
			if (@exeUpdatable) {
				@exeRunning = exeRunningList(@exeUpdatable); # Re-check this list
				if (@exeRunning) {
					print "Cannot perform rollback of these exe files if they are running: ", join(', ', @exeRunning), "\n";
					print "Retry or Quit (R/Q) ?";
					my $key = readMenuKey('RQ');
					print "\n\n";
					exitSuccess("No rollback performed") if $key eq 'Q';
					@exeRunning = exeRunningList(@exeUpdatable); # Try again
					exitError("Cannot perform rollback; these exe files are still running: " . join(', ', @exeRunning)) if @exeRunning;
				}
			}

			# Rollback the old versions into place by over-writing the existing files
			print "Restoring rollback version files ";
			foreach my $file (@updatable) {
				doDelete($InstallPath.$update->{$file}->{Path}.$file) if -e $InstallPath.$update->{$file}->{Path}.$file;
				doMove($RollbackPath.$file, $InstallPath.$update->{$file}->{Path}.$file) if length $update->{$file}->{Version};
				print '.';
				foreach my $subfile (readSubFiles($InstallPath.$file)) {
					doDelete($InstallPath.$update->{$file}->{Path}.$subfile) if -e $InstallPath.$update->{$file}->{Path}.$subfile;
					doMove($RollbackPath.$subfile, $InstallPath.$update->{$file}->{Path}.$subfile);
					print '.';
				}
			}
			# Also the Perl version digest and Changes files
			doDelete($PerlDigestPath) if -e $PerlDigestPath && -e $RollbackPath.$PerlDigest;
			doMove($RollbackPath.$PerlDigest, $PerlDigestPath) if -e $RollbackPath.$PerlDigest;
			print '.';
			doDelete($ChangesPath) if -e $ChangesPath && -e $RollbackPath.$Changes;
			doMove($RollbackPath.$Changes, $ChangesPath) if -e $RollbackPath.$Changes;

			# Remove the rollback digest file
			doDelete($RollbackDigestPath);

			print "\n\n";
			exitSuccess("Rollback complete. Please restart application to use restored versions", 'rlb');
		};

		$key eq 'D' && do { # Download zip install file
			until (-e $DownloadPath && -d $DownloadPath) {
				print "\nDownload directory ( $DownloadPath ) does not exist\n";
				print "Please provide alternative directory to download to\n : ";
				chomp($DownloadPath = <STDIN>);
				$DownloadPath .= "\\" unless $DownloadPath =~ /\\$/;
				printLog("Manual Download directory entered : $DownloadPath");
			}
			getFile($zipFilename, $DownloadPath, 0, undef, 1) or exitError("\nUnable to download new installer");
			exitSuccess("\nDownload complete\n");
		};

		$key eq 'M' && do { # Manual URL
			print "Enter URL: ";
			chomp($updateUrl = <STDIN>);
			printLog("Manual URL entered : $updateUrl");
			next;
		};

		$key eq 'Q' && do { # Quit
			close $LogHandle if $LogHandle;
			exit;
		};
	}
}
