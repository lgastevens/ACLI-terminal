#!/usr/bin/perl

my $Version = "1.17";
my $Debug = 0;

# Written by Ludovico Stevens (lstevens@extremenetworks.com)
#
# Version history:
# 0.01	- Initial
# 0.03	- After launch, selected entries are deselceted automatically
#	- Containing window entry box now has a history pull down
#	- Added -n argument to launch terminals in transparent mode
# 0.04	- Fixed issue with -t argument not implementing the wait timer between 1st and subsequent tabs
# 1.00	- Added -q argument to provide an override graphQl file (to work with different versions of XMC which have incompatible API keys..)
#	- Hitting Quit button during Fetch was hanging the application
#	- JSON device data structure is now flattened to eliminate the inconsistent 'extraData' sub key, which becomes 'deviceData' in XMC8.2 
# 1.01	- Enhanced to also work on MAC OS distribution
# 1.02	- Added ISW to list of devices to launch ACLI in interact mode
#	- Version now shows in window title
# 1.03	- Issues with threads on MAC OS; no longer sets stack_size on MAC OS
#	- If no XMC server details and filtering criteria were provided in xmcacli.ini then the Sysname column was missing in app
#	- Input field backgrounds now set to white for correct rendering on MAC OS
# 1.04	- Correction in syntax display
#	- Added new 'Extreme Access Series' family which is how XMC classifies XA1400 since VOSS8.1
# 1.05	- Added new 'Unified Switching VOSS' & 'Unified Switching EXOS' families used in XMC for 5520 unified hardware
#	- Added support for external acli.spawn file; now acligui can be theoretically launched and
#	  customized on any OS; in practice this adds support for Linux
#	- Transparent mode (-n) now has a checkbox in the GUI
# 1.06	- HTTP timeout changed from 5 to 20 seconds
#	- HTTP timeout can now be changed in the xmcacli.ini file
# 1.07	- Sockets are not loaded in transparent mode (-n)
#	- Acli.spawn key <ACLI-PL-PATH> was not replaced with "acli.pl" but just "acli"
# 1.08	- Update to work with XIQ-SE 21.9 which no longer calls itself XMC on server responses
# 1.09	- Update to -s switch syntax
# 1.10	- Corrections to debug function
# 1.11	- Switch -s is normally suppressed if the -n switch is set; but is now not suppressed if the -s
#	  switch is set to 0 (disable sockets)
# 1.12	- Added new 'Universal Platform Fabric Engine' & 'Universal Platform Switch Engine' families used in XIQ-SE 22.3 for
#	  universal hardware running VOSS8.6 or EXOS31.6 or later
# 1.13	- The login credentials are now always double quoted when launching ACLI in case the password might contain special
#	  characters like *,&,etc..
# 1.14	- Added new 'Universal Platform Fabric Engine' & 'Universal Platform Switch Engine' families used in XIQ-SE 22.3 for
#	  universal hardware running VOSS8.6 or EXOS31.6 or later - was not added in 1.12
# 1.15	- Site filter pull down was matching other sites if other sites had longer names containing the selected site
#	- Site filter pull down was causing application to crash with "Tk_FreeCursor received unknown cursor argument"
#	  if a site was selected and then the site filter pull down was used to select a site
#	- Setting the Logging or Working directory from GUI, the directory chooser now starts from the directory which was
#	  specified with command line switches or from the very top "This PC"
#	- Last Logging or Working directory selected from directory chooser is remembered and offered as default in subsequent
#	  executions of the script
# 1.16	- Added new 'XIQ Native' XIQ-SE family since ACLI now supports Cloud APs (HiveOS)
# 1.17	- Added missing '200 Series' XIQ-SE family for Series200 support


#############################
# STANDARD MODULES          #
#############################

use strict;
use warnings;
no warnings 'threads';			# Prevents errors on console window about thread terminated abnormally when quiting the application
use threads;
use threads::shared;
use Getopt::Std;
use Cwd;
use File::Basename;
use File::Spec;
use Tk;
use Tk::Tree;
use Tk::ProgressBar;
use Tk::BrowseEntry;
use Tk::DoubleClick;
use Time::HiRes qw( sleep );
use LWP::UserAgent;
use HTTP::Request;
use Cpanel::JSON::XS;	# Can't use JSON, as it uses JSON::XS as backend, which does not work with threads
use Config::INI::Reader::Ordered;
if ($^O eq "MSWin32") {
	unless (eval "require Win32::Process") { die "Cannot find module Win32::Process" }
	import Win32::Process qw( NORMAL_PRIORITY_CLASS );

	# http://www.perlmonks.org/?node_id=874944 / On MSWin32 minimum becomes 8192, but not setting would use 16Meg
	# However we stay with default stack_size on MAC OS as otherwise we get all sorts of errors 
	threads->set_stack_size(8192);
}
#use Data::Dumper;


############################
# GLOBAL VARIABLES         #
############################
my $ThreadSleepTimer = 0.5;	# Sleep timer for worker thread, between checking if $Shared_flag has been set
my $MaxWindowSessions = 20;	# Maximum number of ConsoleZ tabs we want to open in same window
my $ThreadCheckInterval = 150;	# Time to wait between checking status of httpThread
my $HttpTimeout = 20;		# Timeout to use by LWP::UserAgent

my $IPentryBoxWidth = 50;	# Size of text box with IP list
my $CredentialBoxWidth = 25;	# Size of username & password text boxes
my $WindowNameBoxWidth = 30;	# Size of window name text box
my $WorkDirBoxWidth = 61;	# Size of working directory text box
my $SocketNamesWidth = 61;	# Size of socket names text box
my $RunScriptWidth = 61;	# Size of run script text box
my $ProgressBarMax = 100;	# Progress bar on 100%
my $ProgressBarBit = 2;		# Granularity of progress bar increases
my $DefaultSortColumn = 0;	# Sets default sort column (0 = no sort)
my $HistoryDepth = 15;		# Maximum number of entries we will list in XMC server history recall pull down (can be modified via xmcacli.ini)

my %XmcDeviceFamilyInteract = ( # This hash holds the XMC deviceDisplayFamily values for which we want to launch acli in interact mode
				# For any device not in these families, acli will be launched with the -n flag set, for transparent mode
	'VSP Series'				=> 1,
	'ERS Series'				=> 1,
	'Summit Series'				=> 1,
	'WLAN Series'				=> 1, # WLAN9100
	'ISW-Series'				=> 1,
	'Extreme Access Series'			=> 1, # XA1400
	'Unified Switching VOSS'		=> 1, # 5520-VOSS
	'Unified Switching EXOS'		=> 1, # 5520-EXOS
	'Universal Platform Fabric Engine'	=> 1, # 5520,5420,5320
	'Universal Platform Switch Engine'	=> 1, # 5520,5420,5320
	'XIQ Native'				=> 1, # HiveOS
	'200 Series'				=> 1, # Series200
);

my ($ScriptName, $ScriptDir) = File::Basename::fileparse(File::Spec->rel2abs($0));
my $ConsoleWinTitle = "ACLI Terminal Launched Sessions";
my $ConsoleAcliProfile = 'ACLI';
my $RunScriptExtensions = [
	["Run Scripts", ['.run', '.src', '']],
	["All files",	'*']
];
my $Ofh = \*STDOUT; # Default debug Output File Handle
our ($opt_d, $opt_f, $opt_g, $opt_h, $opt_i, $opt_m, $opt_n, $opt_p, $opt_q, $opt_s, $opt_t, $opt_u, $opt_w); #Getopts switches

my $IniFileName = 'xmcacli.ini';
my $GraphQlFile = 'xmcacli.graphql';
my $XmcHistoryFile = 'xmcacli.hist';
my $WindowHistoryFile = 'xmcacli.whist';
my $LastWorkingLoggingDir = 'xmcacli.lastdir',
my $AcliSpawnFile = 'acli.spawn';
my $AcliDir = '/.acli';
my (@AcliFilePath, $RunFilePath);
if (defined(my $path = $ENV{'ACLI'})) {
	push(@AcliFilePath,      File::Spec->canonpath($path));
	$RunFilePath = File::Spec->canonpath($path);
}
elsif (defined($path = $ENV{'HOME'})) {
	push(@AcliFilePath,      File::Spec->canonpath($path.$AcliDir));
	$RunFilePath = File::Spec->canonpath($path.$AcliDir);
}
elsif (defined($path = $ENV{'USERPROFILE'})) {
	push(@AcliFilePath,      File::Spec->canonpath($path.$AcliDir));
	$RunFilePath = File::Spec->canonpath($path.$AcliDir);
}
push(@AcliFilePath, File::Spec->canonpath($ScriptDir)); # Last resort, script directory


############################
# THREAD SHARED VARIABLES  #
############################
my $Shared_flag :shared = 0;		# When set to 1, httpWorkerThread fetches data
my %Shared_xmcServer :shared;		# Hash with info about XMC IP,port,credentials
my @Shared_thrdError : shared;		# When $Shared_flag reset to 0 by thread, this will hold the error, if thread failed
my $Shared_JsonOutput : shared;		# When $Shared_flag reset to 0 by thread, this will hold JSON output data, if the thread succeeded


#############################
# FUNCTIONS                 #
#############################

sub printSyntax {
	printf "%s version %s%s\n\n", $ScriptName, $Version, ($Debug ? " running on $^O perl version $]" : "");
	print "Usage:\n";
	print " $ScriptName [-fgimnpqstuw] [<XMC server/IP[:port]>]\n\n";
	print " <XMC server/IP[:port]>: Extreme Management Center IP address or hostname & port number\n";
	print " -f <site-wildcard>    : Filter entries on Site wildcard\n";
	print " -g <record-grep>      : Filter entries pattern match across any column data\n";
	print " -h                    : Help and usage (this output)\n";
	print " -i <log-dir>          : Path to use when logging to file\n";
	print " -m <script>           : Once connected execute script (if no path included will use \@run search paths)\n";
	print " -n                    : Launch terminals in transparent mode (no auto-detect & interact)\n";
	print " -p ssh|telnet         : Protocol to use; can be either SSH or Telnet (case insensitive)\n";
	print " -q <graphql-file>     : Override of default xmcacli.graphql file; must be placed in same path\n";
	print " -s <sockets>          : List of socket names for terminals to listen on (0 to disable sockets)\n";
	print " -t <window-title>     : Sets the containing window title into which all connections will be opened\n";
	print " -u user[:<pwd>]       : Specify XMC username[& password] to use\n";
	print " -w <work-dir>         : Working directory to use\n";
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


sub errorMsg { # Display invalid IP message to user
	my ($tk, $title, $message) = @_;
	# From command line
	quit(1, $message) unless defined $tk;

	# From Gui, don't exit, give popup
	$tk->{mw}->messageBox(
		-title	=> $title,
		-icon	=> 'info',
		-type	=> 'OK',
		-message => $message,
        );
        return; # Invalid
}


sub readAcliSpawnFile { # Reads in acli.spawn file with command to execute based on local OS
	my $tk = shift;
	my $spawnFile;

	foreach my $path (@AcliFilePath) {
		if (-e "$path/$AcliSpawnFile") {
			$spawnFile = "$path/$AcliSpawnFile";
			last;
		}
	}
	return errorMsg($tk, "File not found", "Unable to locate ACLI spawn file $AcliSpawnFile") unless defined $spawnFile;

	open(SPAWN, '<', $spawnFile) or
		return errorMsg($tk, "Cannot open file", "Unable to open ACLI spawn file " . File::Spec->canonpath($spawnFile));

	my $lineNumber = 0;
	my %execTemplate;
	while (<SPAWN>) {
		chomp;
		$lineNumber++;
		next if /^\s*$/; # skip empty lines
		next if /^\s*#/; # skip comment lines
		next unless s/^(\S+)\s+//; # Grab 1st word (OS)
		next unless $1 eq $^O;
		debugMsg(1,"ACLI.SPAWN: Entry for OS $^O found in line ", \$lineNumber, "\n");
		%execTemplate = (timer1 => 0, timer2 => 0);
		s/^(?:(\d{1,4}):)?(\d{1,4})\s+// && do {
			$execTemplate{timer1} = defined $1 ? $1 : $2;
			$execTemplate{timer2} = $2;
			debugMsg(1,"ACLI.SPAWN: Timer1 = ", \$execTemplate{timer1}, " / Timer2 = $execTemplate{timer2}\n");
		};
		next unless s/^(\S+)\s+//; # Grab 2nd word (executable)
		$execTemplate{executable} = $1;
		$execTemplate{arguments} = $_;
		debugMsg(1,"ACLI.SPAWN: Executable = ", \$execTemplate{executable}, "\n");
		debugMsg(1,"ACLI.SPAWN: Arguments = ", \$execTemplate{arguments}, "\n");
	}
	close SPAWN;
	unless (defined $execTemplate{executable} && defined $execTemplate{arguments}) {
		print "Error: Unable to extract $^O executable + arguments from ACLI spawn file ", File::Spec->canonpath($AcliSpawnFile), "\n";
		return;
	}
	return \%execTemplate;
}


sub substituteExecArgs { # Substitutes values into the arguments template obtained from acli.spawn file for the OS at hand
	my ($template, $windowName, $instanceName, $tabName, $cwd, $acliProfile, $acliPath, $acliPlPath, $acliArgs) = @_;

	# Replace values
	$template =~ s/<WINDOW-NAME>/$windowName/g if defined $windowName;
	$template =~ s/<INSTANCE-NAME>/$instanceName/g if defined $instanceName;
	$template =~ s/<TAB-NAME>/$tabName/g if defined $tabName;
	$template =~ s/<CWD>/$cwd/g if defined $cwd;
	$template =~ s/<ACLI-PROFILE>/$acliProfile/g if defined $acliProfile;
	$template =~ s/<ACLI-PATH>/$acliPath/g if defined $acliPath;
	$template =~ s/<ACLI-PL-PATH>/$acliPlPath/g if defined $acliPlPath;
	$template =~ s/<ACLI-ARGS>/$acliArgs/g if defined $acliArgs;

	# Remove unused value markers
	$template =~ s/(?:-[a-z]|--\w[\w-]+)(?:\s+|=)\"<[A-Z-]+>\"\s*//g;	# Double quoted with preceding -switch
	$template =~ s/(?:-[a-z]|--\w[\w-]+)(?:\s+|=)\'<[A-Z-]+>\'\s*//g;	# Single quoted with preceding -switch
	$template =~ s/(?:-[a-z]|--\w[\w-]+)(?:\s+|=)<[A-Z-]+>\s*//g;		# Non quoted with preceding -switch
	$template =~ s/\"<[A-Z-]+>\"\s*//g;					# Double quoted with no preceding -switch
	$template =~ s/\'<[A-Z-]+>\'\s*//g;					# Single quoted with no preceding -switch
	$template =~ s/<[A-Z-]+>\s*//g;						# Non quoted with no preceding -switch

	return $template;
}


sub exeIsRunning { # Checks whether the provided exe file is already running on the system
	my $exeFile = File::Basename::fileparse(shift);
	my $exeWinTitle = shift;
	debugMsg(1, "exeIsRunning checking file $exeFile with Window Title: ", \$exeWinTitle, "\n");
	my $tasklist = `tasklist /FI "IMAGENAME eq $exeFile" /FI "WINDOWTITLE eq $exeWinTitle"`;
	debugMsg(1, "exeIsRunning tasklist :>", \$tasklist, "<\n");
	return 1 if $tasklist =~ /^$exeFile/m;
	return 0; # Otherwise
}


sub launchConsole { # Spawn entry into ConsoleZ; use Win32/Process instead of exec to avoid annoying DOS box
	my ($tk, $displayData, $launchValues) = @_;
	my $waitTimer;
	my $containingWindow = length $launchValues->{Window} ? $launchValues->{Window} : $ConsoleWinTitle;
	my $execTemplate = readAcliSpawnFile($tk);
	return unless defined $execTemplate;

	foreach my $device ( @{$displayData->{sortedDevices}} ) {
		next unless $device->{selected};
		$device->{selected} = 0; # Deselect it

		my $acliArgs = '';
		$acliArgs .= '-d 7 ' if $Debug;
		$acliArgs .= '-n ' if $launchValues->{Transparent} || !$XmcDeviceFamilyInteract{$device->{deviceDisplayFamily}};
		$acliArgs .= "-w \\\"$launchValues->{WorkDir}\\\" " if defined $launchValues->{WorkDir};
		$acliArgs .= "-i \\\"$launchValues->{LogDir}\\\" " if defined $launchValues->{LogDir};
		$acliArgs .= "-s \\\"$launchValues->{Sockets}\\\" " if defined $launchValues->{Sockets} && ($acliArgs !~ /-n/ || $launchValues->{Sockets} eq '0');
		$acliArgs .= "-m \\\"$launchValues->{RunScript}\\\" " if defined $launchValues->{RunScript};

		my $profile = $device->{profileName};	# Get device profile
		if (defined $profile && defined $displayData->{profiles}->{$profile}->{userName}) { # We have a username
			my $credentials = $displayData->{profiles}->{$profile}->{userName} . (defined $displayData->{profiles}->{$profile}->{loginPassword} ? ':'.$displayData->{profiles}->{$profile}->{loginPassword} : '');
			if ($launchValues->{'Protocol'} eq 'SSH') {
				$acliArgs .= "-l \\\"$credentials\\\" $device->{ip}";
			}
			else { # TELNET
				$acliArgs .= "\\\"$credentials\@$device->{ip}\\\"";
			}
		}

		my $executeArgs = substituteExecArgs( # Substitutes values into the executable arguments template
			$execTemplate->{arguments},						# Template
			$containingWindow,							# <WINDOW-NAME>
			$containingWindow,							# <INSTANCE-NAME>
			(defined $device->{sysName} ? $device->{sysName} : $device->{ip}),	# <TAB-NAME>
			File::Spec->rel2abs(cwd), 						# <CWD>
			$ConsoleAcliProfile,							# <ACLI-PROFILE>
			$ScriptDir . 'acli',							# <ACLI-PATH>
			$ScriptDir . 'acli.pl',							# <ACLI-PL-PATH>
			$acliArgs,								# <ACLI-ARGS>
		);
		debugMsg(1,"launchNewTerm / execuatable = ", \$execTemplate->{executable}, "\n");
		debugMsg(1,"launchNewTerm / arguments = ", \$executeArgs, "\n");

		# Perform sleep delay if applicable
		if (defined $waitTimer) { # We never sleep on 1st instance launch
			my $sleepTime;
			if ($waitTimer) { # 2nd launch
				if ($^O eq "MSWin32" && exeIsRunning($execTemplate->{executable}, $containingWindow) ) {
					$sleepTime = $execTemplate->{timer2} / 1000;
					debugMsg(1,"launchNewTerm / Sleep time 2nd launch (exe already running) = ", \$sleepTime, "\n");
				}
				else { # On MSWin32 make timer1 conditional on Console.exe not already running
					$sleepTime = $execTemplate->{timer1} / 1000;
					debugMsg(1,"launchNewTerm / Sleep time 2nd launch = ", \$sleepTime, "\n");
				}
				$waitTimer = 0; # Only do this once
			}
			else { # 3rd and beyond launches
				$sleepTime = $execTemplate->{timer2} / 1000;
				debugMsg(1,"launchNewTerm / Sleep time 3rd and above launch = ", \$sleepTime, "\n");
			}
			sleep $sleepTime if defined $sleepTime;
		}
		else {
			$waitTimer = 1; # Force wait time on 2nd launch
		}

		if ($^O eq "MSWin32") { # Windows
			my $processObj;
			(my $executable = $execTemplate->{executable}) =~ s/\%([^\%]+)\%/defined $ENV{$1} ? $ENV{$1} : $1/ge;
			debugMsg(1,"launchNewTerm / execuatable after resolving %ENV = ", \$executable, "\n");
			Win32::Process::Create($processObj, $executable, $executeArgs, 0, &NORMAL_PRIORITY_CLASS, File::Spec->rel2abs(cwd));
			return errorMsg($tk, "Failed to Launch", "Error launching $device->{ip} with ACLI Terminal") unless $processObj;
		}
		else { # Any other OS (MAC-OS and Linux...)
			my $executable = join(' ', $execTemplate->{executable}, $executeArgs);
			debugMsg(1,"launchNewTerm / execuatable after joining = ", \$executable, "\n");
			my $retVal = system($executable);
			return errorMsg($tk, "Failed to Launch", "Error launching $device->{ip} with ACLI Terminal") if $retVal;
		}
	}
}


sub findFile { # Searches our paths for specified file
	my $fileName = shift;
	my $filePath;

	# Determine which file to work with
	foreach my $path (@AcliFilePath) {
		if (-e "$path/$fileName") {
			$filePath = "$path/$fileName";
			last;
		}
	}
	return $filePath;
}


sub readIniFile { # Reads in acli.ini file
	my ($xmcValues, $displayData) = @_;

	my $iniFile = findFile($IniFileName);
	quit(1, "Cannot find INI file $IniFileName") unless defined $iniFile;
	debugMsg(1, "readIniFile - read in file : ", \$iniFile, "\n");

	my $iniData = Config::INI::Reader::Ordered->read_file($iniFile);
	my $xmcInfo = (shift @{$iniData})->[1] if $iniData->[0][0] eq '_'; # Remove the XMC hostname/credentials fields if present
	unshift(@$iniData, [undef, {display => "Tree selection"}]);	   # Pre-pend our 1st header column, always present

	$displayData->{headers} = $iniData;
	$xmcValues->{xmcServer} = $xmcInfo->{xmcServer} if defined $xmcInfo->{xmcServer};
	$xmcValues->{xmcUsername} = $xmcInfo->{xmcUsername} if defined $xmcInfo->{xmcUsername};
	$xmcValues->{xmcPassword} = $xmcInfo->{xmcPassword} if defined $xmcInfo->{xmcPassword};
	$HttpTimeout = $xmcInfo->{httpTimeout} if defined $xmcInfo->{httpTimeout}; # Override global
	$HistoryDepth = $xmcInfo->{historyDepth} if defined $xmcInfo->{historyDepth}; # Override global
	$displayData->{siteFilter} = $xmcInfo->{siteFilter} if defined $xmcInfo->{siteFilter};
	$displayData->{grepFilter} = $xmcInfo->{grepFilter} if defined $xmcInfo->{grepFilter};
}


sub readHistoryFile { # Read the xmcacli.hist file
	my $historyFile = shift;

	my $histFile = findFile($historyFile);
	unless (defined $histFile) { # If the file does not yet exist...
		debugMsg(1, "readHistoryFile - history file ", \$historyFile, " does not exist\n");
		return;
	}

	# Read the file into our array
	open(HISTORY, '<', $histFile) or do {
		debugMsg(1, "readHistoryFile - cannot open file to read : ", \$histFile, "\n");
		return; # Same, if we can't open it
	};
	flock(HISTORY, 1); # 1 = LOCK_SH; Put a shared lock on the file (wait to read if it's being changed)
	my @history;
	while (<HISTORY>) {
		chomp;
		next unless length;
		push(@history, $_);
	}
	close HISTORY;
	debugMsg(1, "readHistoryFile - read in file : ", \$histFile, "\n");
	return \@history;
}


sub writeHistoryFile { # Write a new xmcacli.hist file
	my ($historyFile, $history) = @_;

	unless (-e $AcliFilePath[0] && -d $AcliFilePath[0]) { # Create base directory if not existing
		mkdir $AcliFilePath[0] or return;
		debugMsg(1, "writeHistoryFile - created directory:\n ", \$AcliFilePath[0], "\n");
	}

	my $histFile = join('', $AcliFilePath[0], '/', $historyFile);

	open(HISTORY, '>', $histFile) or do {
		debugMsg(1, "writeHistoryFile - cannot open file to write : ", \$histFile, "\n");
		return;
	};
	flock(HISTORY, 2); # 2 = LOCK_EX; Put an exclusive lock on the file as we are modifying it
	my $count;
	foreach (@$history) {
		print HISTORY "$_\n";
		last if ++$count == $HistoryDepth;
	}
	close HISTORY;
	debugMsg(1, "writeHistoryFile - updated history file : ", \$histFile, "\n");
}


sub httpWorkerThread { # This is the actual http thread which handles GraphQL queries to XMC; it runs all the time and is triggered via shared variables
	my ($graphQlFile, $dataSet, $nbiUrl, %nbi_call, $lwp, $request, $response, $history);

	$SIG{'KILL'} = sub { die; };	# Signal handler for thread if killed by gui

	JOB: while (1) { # Loop forever

		# Wait for signal from GUI
		sleep $ThreadSleepTimer until $Shared_flag;
		debugMsg(1, "httpWorkerThread - starting\n");

		# Empty both shared data structures
		@Shared_thrdError = ();
		$Shared_JsonOutput = '';

		# Determine which acli.graphql file to work with
		$graphQlFile = findFile($Shared_xmcServer{xmcGraphQl});
		unless (defined $graphQlFile) {
			@Shared_thrdError = ("No GraphQl query file", "Unable to locate file $Shared_xmcServer{xmcGraphQl}");
			$Shared_flag = 0;
			next JOB;
		}
		debugMsg(1, "httpWorkerThread - read in file : ", \$graphQlFile, "\n");

		# Read in GraphQL dataset
		open(GRAPHQL, '<', $graphQlFile) or do {
			@Shared_thrdError = ("Cannot read GraphQl query file", "Unable to read GraphQL query file $Shared_xmcServer{xmcGraphQl}");
			$Shared_flag = 0;
			next JOB;
		};
		$dataSet = '';
		while (<GRAPHQL>) {
			next if /^$/; # Skip empty lines
			next if /^#/; # Skip comment lines
			$dataSet .= $_;
		}
		close GRAPHQL;

		# Prepare GraphQL query
		%nbi_call = (
			operationName	=> undef,
			query		=> $dataSet,
			variables	=> undef,
		);

		# Prepare URL for HTTP POST
		$nbiUrl = 'https://' . $Shared_xmcServer{xmcServer} . '/nbi/graphql';
		debugMsg(1, "httpWorkerThread - url = ", \$nbiUrl, "\n");

		# Create HTTP client
		$lwp = LWP::UserAgent->new(
			timeout		=> $HttpTimeout,
			ssl_opts	=> {
				verify_hostname => 0,		# disable check called host name <=> CN
				SSL_verify_mode => 0x00,	# disable certificate validation
			},
		);

		# Set the user-agent HTTP field to reflect this script/version + libwww-perl/version
		$lwp->agent("$ScriptName/$Version" . $lwp->agent);

		# Setup HTTP Headers to use
		$lwp->default_header(
			'Accept'		=> 'application/json',
			'Accept-Encoding'	=> 'gzip, deflate, br',
			'Connection'		=> 'keep-alive',
			'Content-type'		=> 'application/json',
			'Cache-Control'		=> 'no-cache',
			'Pragma'		=> 'no-cache',
		);

		# Create HTTP Request
		$request = HTTP::Request->new( POST => $nbiUrl );
		$request->content( encode_json(\%nbi_call) );
		$request->authorization_basic($Shared_xmcServer{xmcUsername}, $Shared_xmcServer{xmcPassword});

		# Send HTTP Request to XMC server and fetch response
		$response = $lwp->request( $request );
		#print $response->as_string;

		# Verify response for errors or success
		if (!$response->is_success) { # HTTP Request failed
			@Shared_thrdError = ("HTTP Request failed", $response->status_line);
		}
		elsif (!defined $response->header("Server")
			|| ($response->header("Server") ne "Extreme Management Center" && $response->header("Server") ne "ExtremeCloudIQSiteEngine")
			) { # We are not talking with an XMC server
			@Shared_thrdError = ("Invalid HTTP Server", "Server is not Extreme Management Center");
		}
		elsif (!defined $response->header("Server-Version") || version->parse($response->header("Server-Version")) < version->parse("8.1.2")) { # We are talking with an XMC server which does not support GraphQL
			@Shared_thrdError = ("No GraphQL support", "Extreme Management Center needs to be version 8.1.2 or higher to support GraphQL queries");
		}
		else { # Send the JSON output back
			$Shared_JsonOutput = $response->content;
			# It is not possible to do the decode_json here, as the hash structure returned becomes impossible to share back with the main gui thread

			# Update the XMC history file with this XMC server, only if the fetch was successful
			$history = readHistoryFile($XmcHistoryFile);						# Read in history file
			@$history = grep($_ ne $Shared_xmcServer{xmcServer}, @$history) if defined $history;	# Filter out this XMC server if it was already present
			unshift(@$history, $Shared_xmcServer{xmcServer});					# Add this XMC server at top of the list
			writeHistoryFile($XmcHistoryFile, $history);						# Re-write the file
		}

		# Reset shared flag to 0; ensures that thread will wait again at next loop cycle
		$Shared_flag = 0;

	} # Loop forever
}


sub flattenData { # This function flattend the $json->{data}->{network}->{devices} data to a single level; basically the extraData/deviceData sub key is ironed out
	my ($tk, $arrayRef) = @_;
	my ($dataLossError, $suffixAddedError);
	foreach my $device (@$arrayRef) {
		foreach my $key (keys %$device) {
			next unless ref($device->{$key}) eq 'HASH'; # Skip local keys (or keys which are not a hash)
			# Nested keys, we move to upper context
			foreach my $nestedKey (keys %{$device->{$key}}) { # Sub-keys
				if ( ref($device->{$key}->{$nestedKey}) ) { # If nested key has a 2nd level of hash/array, this will be lost..
					$dataLossError = 1;	# Generate an error once completed
					next;			# Skip
				}
				my $newKey = $nestedKey;	# Assume we can just move the key up one level
				my $suffix = '';		# Assume no suffix needed
				while (exists $device->{$newKey . $suffix}) { # We have a key clash; there is already a key with the same name as the nested one
					$suffix = 1 unless length $suffix; # Init to 1 (becomes 2 below)
					$suffix++;
				}
				if ($suffix) { # If we had to add a suffix to the new key
					$newKey .= $suffix;
					$suffixAddedError = 1;
				}
				$device->{$newKey} = $device->{$key}->{$nestedKey}; # Move the key up a level
			}
			delete $device->{$key}; # Now remove the nested hash
		}
	}
	errorMsg($tk, "Unexpected JSON returned", "JSON response from server contains more than one level of nested data; some data was lost while flattening the structure") if $dataLossError;
	errorMsg($tk, "Unexpected JSON returned", "Nested data in JSON response from server contains keys which clash with the base level keys; some keys had a numerical suffix append while flattening the structure") if $suffixAddedError;
	return $arrayRef;
}


sub profileHash { # This function re-arranges the XMC admin profiles array structure into a hash structure where the profile name is the key
	my $arrayRef = shift;
	my $hashRef = {};
	foreach my $profile (@$arrayRef) {
		$hashRef->{$profile->{profileName}} = $profile->{authCred};
	}
	return $hashRef;
}


sub recordSite { # Enters path into data structure and returns list of paths (may include parent ones) which had to be added and which will require adding to HList widget
	my ($device, $sites, $sitePath, $siteFilter) = @_;
	my @siteChain = split('/', $sitePath);
	my $filterMatch = length $siteFilter ? 0 : 1;
	my @newSites;
	my $path = '';
	my $prunedPath = '/';
	while (my $branch = shift(@siteChain)) {
		$filterMatch = 1 if length $siteFilter && $branch =~ /$siteFilter/i;
		unless ($filterMatch) { # No match
			$prunedPath .= $branch . '/';
			next
		}
		$path .= length $path ? '/'.$branch : $branch;
		unless ($sites->{$path}) { # New path
			$sites->{$path}->{name} = $branch;
			$sites->{$path}->{state} = scalar @siteChain ? 'normal' : 'disabled';
			debugMsg(1, "recordSite - add parent site = ", \$path, "\n");
			push(@newSites, $path);
		}
	}
	$device->{prunedPath} = $prunedPath;
	debugMsg(1, "recordSite - prunedPath = ", \$prunedPath, "\n");
	debugMsg(1, "recordSite - returnPath = ", \$path, "\n");
	return ($path, \@newSites);
}


sub convert_time { # Stolen here : https://neilang.com/articles/converting-seconds-into-a-readable-format-in-perl/
	my $time = shift;	# XMC time is in hunderds of a sec
	my $timeSecs = int($time / 100); # Total sysuptime in secs
	my $days = int($timeSecs / 86400);
	$timeSecs -= ($days * 86400);
	my $hours = int($timeSecs / 3600);
	$timeSecs -= ($hours * 3600);
	my $minutes = int($timeSecs / 60);
	my $seconds = $timeSecs % 60;
	
	$days = $days < 1 ? '' : $days .'d ';
	$hours = $hours < 1 ? '' : $hours .'h ';
	$minutes = $minutes < 1 ? '' : $minutes . 'm ';
	$time = $days . $hours . $minutes . $seconds . 's';
	return $time;
}


sub filterDevice { # Given a device, determines whether the device should be displayed based on siteFilter and/or grepFilter, if these are set
		   # If device is to be skipped, returns undef; if device is to be listed, returns a list ref with values to display
	my ($displayData, $device) = @_;

	# Immediately skip device if siteFilter is set and it has no match in the device sitePath
	if (length $displayData->{siteFilter} && $device->{sitePath} !~ /\/$displayData->{siteFilter}(?:\/|$)/i) {
		debugMsg(1, "filterDevice - device filtered due to siteFilter >", \$displayData->{siteFilter}, "<\n");
		$device->{selected} = undef;	# undef = entry filtered and not displayed
		return
	}

	my @valuesList; 
	my $grepMatch = length $displayData->{grepFilter} ? 0 : 1;	# If we have grepFilter set, the device will need to match on at least one field below; if not, the entry will be passed on anyway
	for my $h (1 .. $#{$displayData->{headers}}) { # Skip 1st header, as that is just the tree view
		my $hdr = $displayData->{headers}->[$h]->[0];		# Name of field (as returned by XMC)
		my $hdrInfo = $displayData->{headers}->[$h]->[1];	# Hash with how we display the header {display} and how we format the value from XMC {type}
		my $displayValue;
		my $value = $device->{$hdr};
		if (defined $value) { # Format it
			if ($hdrInfo->{type} eq 'Time') {
				$displayValue = convert_time($value);
			}
			elsif ($hdrInfo->{type} eq 'Flag') {
				$displayValue = $value ? 'True' : 'False';
			}
			elsif ($hdrInfo->{type} eq 'YesNo') {
				$displayValue = $value ? 'Yes' : 'No';
			}
			else { # we assume String, DotDecimal, Number
				$displayValue = $value;
			}
		}
		debugMsg(1, "filterDevice - value $h = ", \$displayValue, "\n");
		push(@valuesList, $displayValue);
		next unless defined $displayValue;
		$grepMatch = 1 if !$grepMatch && $displayValue =~ /$displayData->{grepFilter}/i;	# See if value gives us a match
	}
	# If $grepMatch is not set this means that a grepFilter was set and it did not match any of the device fields; so we skip the device
	unless ($grepMatch) {
		debugMsg(1, "filterDevice - device filtered due to grepFilter >", \$displayData->{grepFilter}, "<\n");
		$device->{selected} = undef;	# undef = entry filtered and not displayed
		return
	}

	# If we get here, then the device is to be listed; return its values
	$device->{selected} = 0 unless defined $device->{selected};	# defined value = entry is to be displayed
	return \@valuesList;
}


sub doubleClickTree { # Handle double click performed on a branch of the tree
	my ($tk, $displayData) = @_;
	my $pathSelected = $tk->{mwTree}->infoAnchor; # Pre-pend the pruned path (if siteFilter is in effect) or '/' otherwise
	return unless defined $pathSelected;	# Not sure when this happens, but sometime it does...
	debugMsg(1, "doubleClickTree - pathSelected = ", \$pathSelected, "\n");
	# First determine if switches under path are all selected, or not
	my $allSelected = 1; # Assume yes
	foreach my $device ( @{$displayData->{devices}} ) {
		next unless $device->{prunedPath} . $pathSelected eq $device->{sitePath};
		if (defined $device->{selected} && $device->{selected} == 0) { # Device is diplayed (not filtered out by siteFilter or grepFilter) and not selected
			$allSelected = 0; # Conclude no
			last;
		}
	}
	debugMsg(1, "doubleClickTree - allSelected = ", \$allSelected, "\n");

	if ($allSelected) { # All selected
		# Deselect all
		foreach my $device ( @{$displayData->{devices}} ) {
			next unless defined $device->{selected}; # If entry not displayed, skip
			next unless $device->{prunedPath} . $pathSelected eq $device->{sitePath};
			$device->{selected} = 0 if defined $device->{selected}; # Unselect, if displayed
			debugMsg(1, "doubleClickTree - deselecting device = ", \$device->{ip}, "\n");
		}
	}
	else { # Some selected & some not, or none selected
		# Select all
		foreach my $device ( @{$displayData->{devices}} ) {
			next unless defined $device->{selected}; # If entry not displayed, skip
			next unless $device->{prunedPath} . $pathSelected eq $device->{sitePath};
			$device->{selected} = 1 if defined $device->{selected}; # Select, if displayed
			debugMsg(1, "doubleClickTree - selecting device = ", \$device->{ip}, "\n");
		}
	}
}


sub compareDigitList { # Does a compare between 2 lists of digits
	my ($aList, $bList) = @_;
	my $result = 0;

	for (my $i = 0; $i <= $#$aList || $i <= $#$bList; $i++) {
		if (defined $aList->[$i] && defined $bList->[$i]) {
			$result = $aList->[$i] <=> $bList->[$i];
		}
		else {
			$result = defined $aList->[$i] ? 1 : -1;
		}
		last if $result;
	}
	return $result;
}

sub byHeader { # Sort function to arrange devices according to one of the elements of info (headers)
	my ($displayData, $hdrIdx) = @_;
	my ($a_field, $b_field, $direction, $result);

	my $hdr = $displayData->{headers}->[$hdrIdx]->[0];	# Name of field (as returned by XMC)
	my $hdrInfo = $displayData->{headers}->[$hdrIdx]->[1];	# Hash with how we need to perform sort

	$a_field = $a->{$hdr};
	$a_field = '' unless defined $a_field;
	$b_field = $b->{$hdr};
	$b_field = '' unless defined $b_field;

	$direction = $displayData->{sortHeaders}->{$hdr};
	if ($hdrInfo->{type} eq 'DotDecimal') {
		$a_field =~ s/[^\d\._]//g;	# Version numbers sometimes preceded by 'v'; betas sometimes have a 'b'
		$b_field =~ s/[^\d\._]//g;	# Take out any non-digit / valid separator characters
		my @a_digits = split(/[\._]/, $a_field);
		my @b_digits = split(/[\._]/, $b_field);
		$result = compareDigitList(\@a_digits, \@b_digits);
	}
	elsif ($hdrInfo->{type} eq 'Time' || $hdrInfo->{type} eq 'Number') {
		$result = lc($a_field) <=> lc($b_field);
	}
	else { # we assume String
		$result = lc($a_field) cmp lc($b_field);
	}

	return $direction * $result;
}


sub bySitePath { # Sort function to arrange devices accorfing to the depth of their sitePath
	my ($displayData) = @_;

	my $a_pathDepth = scalar( split('/', $a->{sitePath}) );
	my $b_pathDepth = scalar( split('/', $b->{sitePath}) );

	return $a_pathDepth <=> $b_pathDepth;
}


sub updateDeviceData { # Populates the GUI window with the data extracted from XMC
	my ($tk, $displayData, $sortHdrIdx) = @_;
	my $sortHdr = defined $sortHdrIdx ? $displayData->{headers}->[$sortHdrIdx]->[0] : undef;

	return unless @{$displayData->{devices}}; # If we have no data, simply come out

	if ( Tk::Exists($tk->{mwTree}) ) { # Widget already exists, remove it and delete it
		$tk->{mwTree}->packForget;
		#$tk->{mwTree}->destroy; # We don't do this anymore because it was bombing with "Tk_FreeCursor received unknown cursor argument"
		# when selecting a site folder, and then using the Site Filter input to select a site (bug29)
		# See: https://github.com/eserte/perl-tk/pull/40
	}

	# We have to create a new widget, as the -columns can only be set on creation
	$tk->{mwTree} = $tk->{mwMiddleFrame}->ScrlTree(
		-itemtype	=> 'text',
		-separator	=> '/',
		-scrollbars	=> "se",
		-selectmode	=> 'browse',
		#-command	=> [\&doubleClickTree, $tk, $displayData], # Has issues on window resize (stops working); using Tk::DoubleClick instead
		-columns	=> scalar @{$displayData->{headers}},
		-header		=> 1,
	);

	# Display the headers
	for my $h (0 .. $#{$displayData->{headers}}) {
		my $hdrInfo = $displayData->{headers}->[$h]->[1];	# Hash with how we display the header {display} and how we format the value from XMC {type}
		$tk->{mwTree}->headerCreate(
			$h,
			-itemtype => 'window',
			-borderwidth => -2,
			-widget => $tk->{mwTree}->Button(
				-anchor		=> 'center',
				-text		=> $hdrInfo->{display},
				-command	=> [\&updateDeviceData, $tk, $displayData, $h],
				-state		=> ($h == 0 ? 'disabled' : 'normal'),
			),
		);
	}

	# Sort the device records according to any selected header column
	if (defined $sortHdr) { # User clicked on one of the headers
		if (!defined $displayData->{sortHeaders}->{$sortHdr} || $displayData->{sortHeaders}->{$sortHdr} == -1) { # First time, or last sort was reverse
			$displayData->{sortHeaders}->{$sortHdr} = 1;	# Do a normal sort
		}
		else { # Last sort was normal sort
			$displayData->{sortHeaders}->{$sortHdr} = -1;	# Do a reverse sort
		}
		@{$displayData->{sortedDevices}} = sort { byHeader($displayData, $sortHdrIdx) } @{$displayData->{devices}};
	}
	else { # We just show the records in the order in which they are
		$displayData->{sortedDevices} = $displayData->{devices};
	}

	# The above sort was across all site paths; but for parent site branches, which have devices and child branches,
	# we want the devices to be added to the widget before the branches, otherwise it looks ugly.
	# This means adding devices with path X before adding devices with path X/Y
	# So we do another sort, this time on the sitePath
	my @deviceDisplayOrder = sort { bySitePath($displayData) } @{$displayData->{sortedDevices}};

	# Display the records
	$displayData->{sites} = {};	# Clear this before starting
	foreach my $d ( 0 .. $#deviceDisplayOrder ) {
		my $device = $deviceDisplayOrder[$d];
		debugMsg(1, "\nupdateDeviceData - device = ", \$device->{ip}, "\n");

		# Check if  this device is to be shown, based on siteFilter and grepFilter, if these are set
		next unless my $valuesList = filterDevice($displayData, $device);

		# Process the device sitePath
		my $sitePath = $device->{sitePath};
		$sitePath =~ s/^\///;	# Remove leading \; HList does not like it
		$sitePath .= "/&$d";	# We use the array index as switch leaf path name and we prepend it with & which ensures no clash with XMC site names
		my $parentList;
		($sitePath, $parentList) = recordSite($device, $displayData->{sites}, $sitePath, $displayData->{siteFilter});

		# Create the device sitePath as well as parents, if these were not already created before
		foreach my $site (@$parentList) {
			$tk->{mwTree}->add(
				$site,
				-text	=> $displayData->{sites}->{$site}->{name},
				-state	=> $displayData->{sites}->{$site}->{state},
			);
		}

		# Create the tree entry (1st column)
		$tk->{mwTree}->itemCreate(
			$sitePath,
			0,  # Column 0
			-itemtype => 'window',
			-widget	=> $tk->{mwTree}->Checkbutton(
				-anchor		=> 'w',
				-variable	=> \$device->{selected},
				-borderwidth	=> $^O eq "MSWin32" ? 0 : 1
			),
		);

		# Create the entries for the values (2nd to last columns)
		foreach my $i (0 .. $#{$valuesList}) {
			$tk->{mwTree}->itemCreate(
				$sitePath,
				$i + 1,
				-text => $valuesList->[$i],
			);
		}
	}
	$tk->{mwTree}->pack( -fill => 'both', -expand => 1 );
	$tk->{mwTree}->autosetmode();
	$tk->{mwTree}->update;

	# Bind mouse double click event to ScrlTree widget
	#$tk->{mwTree}->bind('<Double-Button-1>' => sub { doubleClickTree($tk, $displayData) } ); # Process double-click
	# Binding <Double-Button-1> with ScrlTree/HList widget has issues on window resize (stops working); so using Tk::DoubleClick instead
	Tk::DoubleClick::bind_clicks(
		$tk->{mwTree},
		sub{},					# Single callback -> do nothing
		[\&doubleClickTree, $tk, $displayData],	# Double callback -> this is what we want
		-delay  => 500,
		-button => 'left',
	);
}


sub updateSiteFilterListBox { # From freshly fetched data, we extract all the branches for the sitePaths we see
	my ($tk, $displayData) = @_;
	my %branches;

	foreach my $device ( @{$displayData->{devices}} ) {
		my @siteChain = split('/', $device->{sitePath});
		foreach my $branch (@siteChain) {
			next unless length $branch;
			$branches{$branch} = 1;
		}
	}
	my @branches = sort { $a cmp $b } keys %branches;
	$tk->{enSiteFilt}->configure( -choices => \@branches );
}


sub updateXmcHistoryListBox { # The thread will have updated the xmcacli.hist file; so need to refresh the Gui list box
	my ($tk, $xmcData) = @_;

	$xmcData->{xmcHistory} = readHistoryFile($XmcHistoryFile);
	$tk->{enXmcIp}->configure( -choices => $xmcData->{xmcHistory} );
}


sub checkThread { # This function is used to communicate between the httpWorkingThread and the tk Gui Mainloop
	my ($tk, $displayData, $xmcData) = @_;

	# Update progress bar
	$tk->{progressPercent} += $ProgressBarBit;

	# If worker thread has not finished come out
	return if $Shared_flag;

	# Worker thread has completed; disable running myself again
	$tk->{mwRepeatId}->cancel;

	# Check what the outcome was
	my $success;
	if (@Shared_thrdError) { # We got an error back
		errorMsg($tk, @Shared_thrdError);
	}
	elsif ($Shared_JsonOutput) { # We got JSON data back
		# Decode the JSON output
		my $json = decode_json( $Shared_JsonOutput );
		if (!defined $json) { # Invalid JSON
			errorMsg($tk, "Invalid JSON returned", "Unable to decode JSON response from server");
		}
		else { # JSON is valid
			if (!defined $json->{data}) { # XMC Server did not like our query
				errorMsg($tk, "GraphQL query ".$json->{errors}->[0]->{errorType}, $json->{errors}->[0]->{message});
			}
			else { # We got good data!
				$success = 1;
				#print Dumper $json->{data}->{network}->{devices};
				$displayData->{devices} =  flattenData($tk, $json->{data}->{network}->{devices});
				$displayData->{profiles} = profileHash($json->{data}->{administration}->{profiles});
				#print Dumper $displayData->{devices};
				#print Dumper $displayData->{profiles};
				updateDeviceData($tk, $displayData, $DefaultSortColumn);
				updateSiteFilterListBox($tk, $displayData);	# Update the site filter pull down list
				updateXmcHistoryListBox($tk, $xmcData);
			}
		}
	}
	else { # Unknown error!
		errorMsg($tk, "ERROR", "Unexpected result from HTTP worker thread");
	}

	# Set progress bar according to success or if we still have data from previous fetch
	$tk->{progressPercent} = $success || @{$displayData->{devices}} ? $ProgressBarMax : 0;

	# Reactivate fetch button
	$tk->{btXmcFetch}->configure( -state => 'normal' );	# Re-enable the Fetch button now
}


###############################
# Tk FUNCTIONS for buttons    #
###############################

sub clear { # Handle Clear button
	my $launchValues = shift;
	$launchValues->{IpList} = '';
	$launchValues->{IpNames} = undef;
	$launchValues->{Username} = undef;
	$launchValues->{Password} = undef;
	$launchValues->{Window} = undef;
	$launchValues->{WorkDir} = undef;
	$launchValues->{LogDir} = undef;
	$launchValues->{Sockets} = undef;
	$launchValues->{RunScript} = undef;
}


sub launch { # Handle Launch button
	my ($tk, $displayData, $launchValues) = @_;

	# First check if we fetched any data
	unless (@{$displayData->{devices}}) {
		$tk->{mw}->messageBox(
			-title	=> 'No Device Data',
			-icon	=> 'info',
			-type	=> 'OK',
			-message => 'No device data was fetched from Extreme Management Center',
	        );
	        return;
	}

	# Then check that at least one entry has been selected
	my $selections;
	foreach my $device ( @{$displayData->{devices}} ) {
		next unless $device->{selected};
		$selections++;
	}
	unless ($selections) {
		$tk->{mw}->messageBox(
			-title	=> 'No Device Selected',
			-icon	=> 'info',
			-type	=> 'OK',
			-message => 'No device was selected for ACLI launch',
	        );
	        return;
	}
	# And not more than we can support
	if ($selections > $MaxWindowSessions) {
		$tk->{mw}->messageBox(
			-title	=> 'Too Many Devices',
			-icon	=> 'info',
			-type	=> 'OK',
			-message => "A single ConsoleZ window does not scale well with more than $MaxWindowSessions tabs",
	        );
	        return;
	}

	# If a containing window was specified, add it to history file
	if (length $launchValues->{Window}) {
		# Filter out this window name if it was already present
		@{$launchValues->{WHistory}} = grep($_ ne $launchValues->{Window}, @{$launchValues->{WHistory}}) if defined $launchValues->{WHistory};
		unshift(@{$launchValues->{WHistory}}, $launchValues->{Window});		# Add this window name at top of the list
		writeHistoryFile($WindowHistoryFile, $launchValues->{WHistory});	# Re-write the file
		$tk->{enWindow}->configure( -choices => $launchValues->{WHistory} );	# Update the widget
	}

	# We are good, launch ACLI on what is selected
	launchConsole($tk, $displayData, $launchValues);
}


sub setDirectory { # Set the start directory for selected entries
	my ($tk, $key, $launchValues) = @_;
	my ($initialDir, $lastDirList);

	if (defined $launchValues->{$key}) {
		$initialDir = $launchValues->{$key}
	}
	else {
		$lastDirList = readHistoryFile($LastWorkingLoggingDir);
		($initialDir = ( grep {/^$key:/} @$lastDirList)[0] ) =~ s/^$key://;
		debugMsg(1, "setDirectory - initialDir = ", \$initialDir, "\n");
	}
	my $dir = File::Spec->canonpath($tk->{mw}->chooseDirectory(-initialdir => $initialDir));
	if (defined $dir and $dir ne '') {
		my $updatedFlag;
		for my $idx (0 .. $#$lastDirList) {
			if ($lastDirList->[$idx] =~ /^$key:/) {
				$lastDirList->[$idx] = "$key:$dir";
				$updatedFlag = 1;
				last;
			}
		}
		unless ($updatedFlag) {
			push(@$lastDirList, "$key:$dir");
		}
		writeHistoryFile($LastWorkingLoggingDir, $lastDirList);
		$launchValues->{$key} = $dir;
	}
}


sub getFile { # Get a file
	my ($tk, $key, $launchValues, $types) = @_;
	my $file = $tk->{mw}->getOpenFile(-filetypes => $types, -initialdir => $RunFilePath);
	if (defined $file and $file ne '') {
		$launchValues->{$key} = $file;
	}
}


sub quitGui { # Handle quit button
	my $httpThread = shift;
	if ( defined $httpThread && $httpThread->is_running() ) {
		$httpThread->kill('KILL');
	}
	exit;
}


sub xmcClear { # Handle XMC Clear button
	my $xmcValues = shift;
	$xmcValues->{xmcServer} = undef;
	$xmcValues->{xmcUsername} = undef;
	$xmcValues->{xmcPassword} = undef;
}


sub filterClear { # Handle Filter Clear button
	my ($tk, $displayData) = @_;

	foreach my $device ( @{$displayData->{devices}} ) {
		delete $device->{selected}; # Simply remove the selected key
	}
	$displayData->{siteFilter} = undef;
	$displayData->{grepFilter} = undef;
	updateDeviceData($tk, $displayData, $DefaultSortColumn);
}


sub xmcFetch { # Handle XMC Fetch button
	my ($tk, $xmcData, $displayData) = @_;

	# Disable the Fetch button; we don't want to come back here while our worker thread is working
	$tk->{btXmcFetch}->configure( -state => 'disabled' );

	# Copy across XMC data
	$Shared_xmcServer{xmcServer} = $xmcData->{xmcServer};
	$Shared_xmcServer{xmcUsername} = $xmcData->{xmcUsername};
	$Shared_xmcServer{xmcPassword} = $xmcData->{xmcPassword};
	$Shared_xmcServer{xmcGraphQl} = $xmcData->{xmcGraphQl};

	# Signal to thread that it can start working
	$Shared_flag = 1;

	# Set up handler check on thread completion
	$tk->{mwRepeatId} = $tk->{mw}->repeat($ThreadCheckInterval, [\&checkThread, $tk, $displayData, $xmcData]);

	# Reset progress bar
	$tk->{progressPercent} = 0;

	return;
}

#############################
# MAIN                      #
#############################

MAIN:{
	getopts('df:g:hi:m:np:q:s:t:u:w:');

	$Debug = 1 if $opt_d;
	printSyntax if $opt_h || scalar @ARGV > 1;

	my ($xmcServer, $username, $password, $siteFilter, $grepFilter, $protocol, $workDir, $logDir, $sockets, $runScript, $window, $history, $transparent, $graphQl);

	$window = $opt_t if defined $opt_t;
	$siteFilter = $opt_f if defined $opt_f;
	$grepFilter = $opt_g if defined $opt_g;
	$workDir = $opt_w if defined $opt_w;
	$logDir = $opt_i if defined $opt_i;
	$sockets = $opt_s if defined $opt_s;
	$runScript = $opt_m if defined $opt_m;
	$transparent = $opt_n if defined $opt_n;
	$graphQl = defined $opt_q ? $opt_q : $GraphQlFile;

	if (@ARGV) {
		$xmcServer = shift @ARGV;
	}

	if (defined $opt_u) {
		if ($opt_u =~ /^([^:\s]+):(\S*)$/) {
			($username, $password) = ($1, $2);
		}
		else {
			$username = $opt_u;
		}
	}
	if (defined $opt_p && ( uc($opt_p) eq 'SSH' || uc($opt_p) eq 'TELNET' )) {
		$protocol = uc($opt_p);
	}
	else {
		$protocol = 'SSH';
	}

	# Read history file, if we have one
	$history = readHistoryFile($XmcHistoryFile);

	my $xmcData = { # Values for XMC NBI connection
		xmcServer	=> undef, # Can be set by INI file or command line
		xmcUsername	=> undef, # Can be set by INI file or command line
		xmcPassword	=> undef, # Can be set by INI file or command line
		xmcHistory	=> $history,
		xmcGraphQl	=> $graphQl,
	};

	# Read window history file, if we have one
	$history = readHistoryFile($WindowHistoryFile);

	my $launchValues = { # Values to use to launch ACLI with
		Protocol	=> $protocol,
		Window		=> $window,
		WorkDir		=> $workDir,
		LogDir		=> $logDir,
		Sockets		=> $sockets,
		RunScript	=> $runScript,
		WHistory	=> $history,
		Transparent	=> $transparent,
	};

	my $displayData = { # Hash structure holding all the information to display (switch data extracted from XMC)
		headers		=> [],	# Will hold list of which headers to show (extracted from xmcacli.ini)
		devices		=> [],	# Will hold devices hash structure as returned by XMC 
		profiles	=> {},	# Will hold admin profiles structure as returned by XMC
		sites		=> {},	# Will hold all the site hierarchies
		branches	=> {},	# Will hold all the individual site branches (for populating browseEntry listbox)
		sortedDevices	=> [],	# Will hold same data as devices key, but sorted according to gui display
		sortHeaders	=> {},	# Will hold hash of header keys indicating state of sort & reverse sort
		siteFilter	=> undef, # Can be set by INI file or command line
		grepFilter	=> undef, # Can be set by INI file or command line
	};


	# Read ini file (this can set values in both $xmcData & $displayData hash structures
	readIniFile($xmcData, $displayData);

	# But we want command line switches to override settings from INI file
	$xmcData->{xmcServer}	= $xmcServer if defined $xmcServer;
	$xmcData->{xmcUsername}	= $username if defined $username;
	$xmcData->{xmcPassword}	= $password if defined $password;
	$displayData->{siteFilter} = $siteFilter if defined $siteFilter;
	$displayData->{grepFilter} = $grepFilter if defined $grepFilter;


	# Must run worker thread before invoking any tk: https://www.perlmonks.org/?node_id=732294
	my $httpThread = threads->create(\&httpWorkerThread);

	my $tk = { # Perl/tk window pointers
		mw					=> undef,	# Main Window
			mwRepeatId			=> undef,	# Timer ID of repeat timer

		mwTopFrame				=> undef,	# Top frame
			mwFrameXmc			=> undef,	# Frame with XMC input parameters
				mwFrameXmcGrid		=> undef,	# Grid frame with XMC entry fields
					enXmcIp		=> undef,	# XMC IP/hostname entry box
					enUsername	=> undef,	# Username entry box
					enPassword	=> undef,	# Password entry box
					enSiteFilt	=> undef,	# Site Filter box
					enGrepFilt	=> undef,	# Switch Type box
				mwFrameXmcButtons	=> undef,	# Frame holding XMC buttons
					btXmcFetch	=> undef,	# XMC Fetch button
					btXmcClear	=> undef,	# XMC Clear button
					btXmcFilter	=> undef,	# XMC Apply Filter button
			mwProgressBar			=> undef,	# Progress bar
				progressPercent		=> undef,	# Progress bar progress

		mwMiddleFrame				=> undef,	# Middle frame
			mwTree				=> undef,	# HList Tree view

		mwBottomFrame				=> undef,	# Bottom frame
			mwFrameGrid			=> undef,	# Frame with parameters
				frameProtocol		=> undef,	# Frame with protocol radio buttons
				enTransparent		=> undef,	# Transparent entry checkbox
				enWindow		=> undef,	# Window name entry box
				frameWorkDir		=> undef,	# Frame with working directory
				frameLogDir		=> undef,	# Frame with logging directory
				enSockets		=> undef,	# Socket names entry box
				frameRunScript		=> undef,	# Frame with run script
			mwFrameButtons			=> undef,	# Frame holding global buttons
				btLaunch		=> undef,	# Launch button
				btClear			=> undef,	# Clear button
				btQuit			=> undef,	# Quit button
	};

	# Setup tk GUI
	$tk->{mw} = MainWindow->new;
	$tk->{mw}->title('XMC ACLI Launcher - v' . $Version);
	$tk->{mw}->bind('<Configure>' => sub { # Runs on window resize
		$tk->{mw}->minsize($tk->{mw}->reqwidth, $tk->{mw}->reqheight); # Let window grow, but not shrink
	});

	# Top frame (contains XMC input fields, Clear + Fetch buttons and progress bar)
	$tk->{mwTopFrame} = $tk->{mw}->Frame;

		# Frame containnig XMC input fields and Clear + Fetch buttons
		$tk->{mwFrameXmc} = $tk->{mwTopFrame}->Frame;

			# Frame containing the XMC parameters and their labels, using grid geometry manager
			$tk->{mwFrameXmcGrid} = $tk->{mwFrameXmc}->Frame;
				$tk->{mwFrameXmcGrid}->Label(-text => "XMC Server/IP[:port]:")->grid(-row => 0, -column => 0);
				$tk->{enXmcIp} = $tk->{mwFrameXmcGrid}->BrowseEntry(
					-variable	=> \$xmcData->{xmcServer},
					-choices	=> $xmcData->{xmcHistory},
					-width		=> $IPentryBoxWidth,
					-background	=> 'white',
				)->grid(-row => 0, -column => 1);

				$tk->{mwFrameXmcGrid}->Label(-text => "XMC Username:")->grid(-row => 1, -column => 0, -sticky => 'e');
				$tk->{enUsername} = $tk->{mwFrameXmcGrid}->Entry(
					-textvariable	=> \$xmcData->{xmcUsername},
					-width		=> $CredentialBoxWidth,
					-background	=> 'white',
				)->grid(-row => 1, -column => 1, -sticky => 'w');

				$tk->{mwFrameXmcGrid}->Label(-text => "XMC Password:")->grid(-row => 2, -column => 0, -sticky => 'e');
				$tk->{enPassword} = $tk->{mwFrameXmcGrid}->Entry(
					-textvariable	=> \$xmcData->{xmcPassword},
					-width		=> $CredentialBoxWidth,
					-show		=> '*',
					-background	=> 'white',
				)->grid(-row => 2, -column => 1, -sticky => 'w');

				$tk->{mwFrameXmcGrid}->Label(-text => "Optional Site Filter:")->grid(-row => 3, -column => 0, -sticky => 'e');
				$tk->{enSiteFilt} = $tk->{mwFrameXmcGrid}->BrowseEntry(
					-variable	=> \$displayData->{siteFilter},
					-width		=> $CredentialBoxWidth,
					-browsecmd	=> [\&updateDeviceData, $tk, $displayData, $DefaultSortColumn],
					-background	=> 'white',
				)->grid(-row => 3, -column => 1, -sticky => 'w');
				$tk->{enSiteFilt}->bind('<Key-Return>' => sub { updateDeviceData($tk, $displayData, $DefaultSortColumn) } ); # Process entry with Return key

				$tk->{mwFrameXmcGrid}->Label(-text => "Record Grep Filter:")->grid(-row => 4, -column => 0, -sticky => 'e');
				$tk->{enGrepFilt} = $tk->{mwFrameXmcGrid}->Entry(
					-textvariable	=> \$displayData->{grepFilter},
					-width		=> $CredentialBoxWidth,
					-background	=> 'white',
				)->grid(-row => 4, -column => 1, -sticky => 'w');
				$tk->{enGrepFilt}->bind('<Key-Return>' => sub { updateDeviceData($tk, $displayData, $DefaultSortColumn) } ); # Process entry with Return key
			$tk->{mwFrameXmcGrid}->pack( -side => 'left');

			# FETCH button
			$tk->{btXmcFetch} = $tk->{mwFrameXmc}->Button(
				-text		=> 'Fetch Data',
				-command	=> [\&xmcFetch, $tk, $xmcData, $displayData],
			)->pack( -side => 'top', -expand => 1, -fill => 'x' );

			# CLEAR XMC button
			$tk->{btXmcClear} = $tk->{mwFrameXmc}->Button(
				-text		=> 'Clear XMC',
				-command	=> [\&xmcClear, $xmcData],
			)->pack( -side => 'top', -expand => 1, -fill => 'x' );

			# CLEAR Filters button
			$tk->{btXmcClear} = $tk->{mwFrameXmc}->Button(
				-text		=> 'Clear Filters',
				-command	=> [\&filterClear, $tk, $displayData],
			)->pack( -side => 'top', -expand => 1, -fill => 'x' );

			# Apply Filters button
			$tk->{btXmcFilter} = $tk->{mwFrameXmc}->Button(
				-text		=> 'Apply Filter',
				-command	=> [\&updateDeviceData, $tk, $displayData, $DefaultSortColumn],
			)->pack( -side => 'top', -expand => 1, -fill => 'x' );

		$tk->{mwFrameXmc}->pack( -side => 'top', -expand => 1, -fill => 'x' );

		$tk->{mwProgressBar} = $tk->{mwTopFrame}->ProgressBar(
			-gap		=> 1,
			-variable	=> \$tk->{progressPercent},
			-width		=> 10,
			-to		=> $ProgressBarMax,
			-blocks		=> 1,
			-colors		=> [0, 'purple'],
			-resolution	=> 0,
		)->pack( -side => 'bottom', -expand => 1, -fill => 'x', -padx => '5', -pady => '5' );

	$tk->{mwTopFrame}->pack( -side => 'top');


	# Middle frame (will contain the HList ScrlTree)
	$tk->{mwMiddleFrame} = $tk->{mw}->Frame->pack( -side => 'top', -fill => 'both', -expand => 1 );


	# Bottom frame (contains ACLI input fields, Launch, Clear + Quit buttons)
	$tk->{mwBottomFrame} = $tk->{mw}->Frame;

		# Frame containing the parameters and their labels, using grid geometry manager
		$tk->{mwFrameGrid} = $tk->{mwBottomFrame}->Frame;
			$tk->{mwFrameGrid}->Label(-text => "Protocol:")->grid(-row => 0, -column => 0, -sticky => 'e');
			$tk->{frameProtocol} = $tk->{mwFrameGrid}->Frame;
				$tk->{frameProtocol}->Radiobutton(
					-text		=> 'SSH',
					-variable	=> \$launchValues->{Protocol},
					-value		=> 'SSH',
				)->pack( -side => 'left' );
				$tk->{frameProtocol}->Radiobutton(
					-text		=> 'Telnet',
					-variable	=> \$launchValues->{Protocol},
					-value		=> 'TELNET',
				)->pack( -side => 'left' );
			$tk->{frameProtocol}->grid(-row => 0, -column => 1, -sticky => 'w');

			$tk->{mwFrameGrid}->Label(-text => "Transparent mode:")->grid(-row => 1, -column => 0, -sticky => 'e');
			$tk->{enTransparent} = $tk->{mwFrameGrid}->Checkbutton(
				-variable	=> \$launchValues->{Transparent},
			)->grid(-row => 1, -column => 1, -sticky => 'w');

			$tk->{mwFrameGrid}->Label(-text => "Containing Window:")->grid(-row => 2, -column => 0, -sticky => 'e');
			$tk->{enWindow} = $tk->{mwFrameGrid}->BrowseEntry(
				-variable	=> \$launchValues->{Window},
				-choices	=> $launchValues->{WHistory},
				-width		=> $WindowNameBoxWidth,
				-background	=> 'white',
			)->grid(-row => 2, -column => 1, -sticky => 'w');

			$tk->{mwFrameGrid}->Label(-text => "Working Directory:")->grid(-row => 3, -column => 0, -sticky => 'e');
			$tk->{frameWorkDir} = $tk->{mwFrameGrid}->Frame;
				$tk->{frameWorkDir}->Entry(
					-textvariable	=> \$launchValues->{WorkDir},
					-width		=> $WorkDirBoxWidth,
					-background	=> 'white',
				)->pack( -side => 'left' );
				$tk->{frameWorkDir}->Button(
					-text		=> '...',
					-command	=> [\&setDirectory, $tk, 'WorkDir', $launchValues],
				)->pack( -side => 'left' );
			$tk->{frameWorkDir}->grid(-row => 3, -column => 1, -sticky => 'w');

			$tk->{mwFrameGrid}->Label(-text => "Logging Directory:")->grid(-row => 4, -column => 0, -sticky => 'e');
			$tk->{frameLogDir} = $tk->{mwFrameGrid}->Frame;
				$tk->{frameLogDir}->Entry(
					-textvariable	=> \$launchValues->{LogDir},
					-width		=> $WorkDirBoxWidth,
					-background	=> 'white',
				)->pack( -side => 'left' );
				$tk->{frameLogDir}->Button(
					-text		=> '...',
					-command	=> [\&setDirectory, $tk, 'LogDir', $launchValues],
				)->pack( -side => 'left' );
			$tk->{frameLogDir}->grid(-row => 4, -column => 1, -sticky => 'w');

			$tk->{mwFrameGrid}->Label(-text => "Listen Socket Names:")->grid(-row => 5, -column => 0, -sticky => 'e');
			$tk->{enSockets} = $tk->{mwFrameGrid}->Entry(
				-textvariable => \$launchValues->{Sockets},
				-width => $SocketNamesWidth,
				-background	=> 'white',
			)->grid(-row => 5, -column => 1, -sticky => 'w');

			$tk->{mwFrameGrid}->Label(-text => "Run Script:")->grid(-row => 6, -column => 0, -sticky => 'e');
			$tk->{frameRunScript} = $tk->{mwFrameGrid}->Frame;
				$tk->{frameRunScript}->Entry(
					-textvariable	=> \$launchValues->{RunScript},
					-width		=> $RunScriptWidth,
					-background	=> 'white',
				)->pack( -side => 'left' );
				$tk->{frameRunScript}->Button(
					-text		=> '...',
					-command	=> [\&getFile, $tk, 'RunScript', $launchValues, $RunScriptExtensions],
				)->pack( -side => 'left' );
			$tk->{frameRunScript}->grid(-row => 6, -column => 1, -sticky => 'w');
		$tk->{mwFrameGrid}->pack( -side => 'top' );

		# Frame containing buttons at the bottom of main window
		$tk->{mwFrameButtons} = $tk->{mwBottomFrame}->Frame;
			# LAUNCH button
			$tk->{btLaunch} = $tk->{mwFrameButtons}->Button(
				-text		=> 'Launch',
				-command	=> [\&launch, $tk, $displayData, $launchValues],
			)->pack( -side => 'left', -expand => 1, -fill => 'x' );

			# CLEAR button
			$tk->{btClear} = $tk->{mwFrameButtons}->Button(
				-text		=> 'Clear',
				-command	=> [\&clear, $launchValues],
			)->pack( -side => 'left', -expand => 1, -fill => 'x' );

			# QUIT button
			$tk->{btQuit} = $tk->{mwFrameButtons}->Button(
				-text		=> 'Quit',
				-command	=> [\&quitGui, $httpThread],
			)->pack( -side => 'left', -expand => 1, -fill => 'x' );
		$tk->{mwFrameButtons}->pack( -side => 'bottom', -expand => 1, -fill => 'both' );

	$tk->{mwBottomFrame}->pack( -side => 'bottom');

	MainLoop;	#perl/tk mainloop
}
