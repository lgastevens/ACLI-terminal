#!/usr/bin/perl

my $Version = "1.17";
my $Debug = 0;

# Written by Ludovico Stevens (lstevens@extremenetworks.com)
#
# Version history:
# 1.0	- Initial
# 1.01	- First version distributed with acli.pl 3.01
# 1.02	- Fixed problem where uninitialized value error was displayed on command prompt
#	- Spaces can be used in IP list in GUI but are now removed before extracting the IP list
# 1.03	- Path argument -w can now also used to find the -f hostfile if the latter includes no path
#	- Launch was failing if -w <work-dir> or -i <log-dir> path included spaces
#	- Can now read hosts out of batch file
# 1.04	- Ability to specify listening socket names (-s)
#	- Ability to launch script on connections (-m)
#	- Gui can be forced with -g switch even if credentials all set
#	- Clear button was not working for logging directory field
# 1.05	- Change on how resizing is prevented
#	- Added -t argument and ability to specify containing window
# 1.06	- Added -n argument to launch terminals in transparent mode
# 1.07	- Fixed issue with -t argument not implementing the wait timer between 1st and subsequent tabs
# 1.08	- Enhanced to also work on MAC OS distribution
# 1.09	- Version now shows in window title
# 1.10	- Input field backgrounds now set to white for correct rendering on MAC OS
# 1.11	- The -f hostfile now accepts IPs/Hostnames + TCP port number in format [<ip/hostname>]:<port>
#	- Also selected entries in -f hostfile can have a '-n' or '-t' flag appended to trigger the
#	  same flag when launching ACLI for that host only
#	- Added support for external acli.spawn file; now acligui can be theoretically launched and
#	  customized on any OS; in practice this adds support for Linux
#	- Transparent mode (-n) now has a checkbox in the GUI
# 1.12	- Sockets are not loaded in transparent mode (-n)
#	- Acli.spawn key <ACLI-PL-PATH> was not replaced with "acli.pl" but just "acli"
# 1.13	- Update to -s switch syntax
# 1.14	- Corrections to debug function
# 1.15	- Switch -s is normally suppressed if the -n switch is set; but is now not suppressed if the -s
#	  switch is set to 0 (disable sockets)
#	- If the -n transparent switch is specified now the -u credentials are no longer required to
#	  ensure that the connections are immdiately launched without calling the GUI window
# 1.16	- If the password contains special characters like *,&,etc.. the -l argument can be enclosed in
#	  double quotes, and now the credentials are always also double quoted when launching ACLI
# 1.17	- Setting the Logging or Working directory from GUI, the directory chooser now starts from the directory which was
#	  specified with command line switches or from the very top "This PC"
#	- Last Logging or Working directory selected from directory chooser is remembered and offered as default in subsequent
#	  executions of the script


#############################
# STANDARD MODULES          #
#############################

use strict;
use warnings;
use Getopt::Std;
use Cwd;
use File::Basename;
use File::Spec;
use Tk;
use Time::HiRes qw( sleep );
if ($^O eq "MSWin32") {
	unless (eval "require Win32::Process") { die "Cannot find module Win32::Process" }
	import Win32::Process qw( NORMAL_PRIORITY_CLASS );
}

############################
# GLOBAL VARIABLES         #
############################
my $MaxWindowSessions = 20;	# Maximum number of ConsoleZ tabs we want to open in same window
my $IPentryBoxWidth = 65;	# Size of text box with IP list
my $CredentialBoxWidth = 25;	# Size of username & password text boxes
my $WindowNameBoxWidth = 30;	# Size of window name text box
my $WorkDirBoxWidth = 61;	# Size of working directory text box
my $SocketNamesWidth = 61;	# Size of socket names text box
my $RunScriptWidth = 61;	# Size of run script text box
my ($ScriptName, $ScriptDir) = File::Basename::fileparse(File::Spec->rel2abs($0));
my $ConsoleWinTitle = "ACLI Terminal Launched Sessions";
my $ConsoleAcliProfile = 'ACLI';
my $RunScriptExtensions = [
	["Run Scripts", ['.run', '.src', '']],
	["All files",	'*']
];
my $Ofh = \*STDOUT; # Default debug Output File Handle
our ($opt_d, $opt_f, $opt_h, $opt_i, $opt_g, $opt_m, $opt_n, $opt_p, $opt_s, $opt_t, $opt_u, $opt_w); #Getopts switches

my $LastWorkingLoggingDir = 'acligui.lastdir',
my $AcliSpawnFile = 'acli.spawn';
my $AcliDir = '/.acli';
my (@AcliFilePath, $RunFilePath);
if (defined(my $path = $ENV{'ACLI'})) {
	push(@AcliFilePath, File::Spec->canonpath($path));
	$RunFilePath = File::Spec->canonpath($path);
}
elsif (defined($path = $ENV{'HOME'})) {
	push(@AcliFilePath, File::Spec->canonpath($path.$AcliDir));
	$RunFilePath = File::Spec->canonpath($path.$AcliDir);
}
elsif (defined($path = $ENV{'USERPROFILE'})) {
	push(@AcliFilePath, File::Spec->canonpath($path.$AcliDir));
	$RunFilePath = File::Spec->canonpath($path.$AcliDir);
}
push(@AcliFilePath, File::Spec->canonpath($ScriptDir)); # Last resort, script directory


#############################
# FUNCTIONS                 #
#############################

sub printSyntax {
	printf "%s version %s%s\n\n", $ScriptName, $Version, ($Debug ? " running on $^O perl version $]" : "");
	print "Usage:\n";
	print " $ScriptName [-gimnpstuw] [<hostname/IP list>]\n";
	print " $ScriptName [-gimnpstuw] -f <hostfile>\n\n";
	print " <host/IP list>   : List of hostnames or IP addresses\n";
	print "                  : Note that valid IP lists can be written as: 192.168.10.1-10,40-45,51\n";
	print "                  : IPv6 addresses are also supported: 2000:10::1-10 (decimal range 1-10)\n";
	print "                  : 2000:20::01-10 (hex range 1,2,3,4,5,6,7,8,9,a,b,c,d,e,f,10)\n";
	print "                  : As well as IP:Port ranges: [<hostname/IPv4/IPv6>]:20000-20010\n";
	print " -f <hostfile>    : File containing a list of hostnames/IPs to connect to; valid lines:\n";
	print "                  :   <IP/hostname>         [<name-for-ACLI-tab>] [-n|-t] [# Comments]\n";
	print "                  :  [<IP/hostname>]:<port> [<name-for-ACLI-tab>] [-n|-t] [# Comments]\n";
	print "                  : The -n or -t flags will be passed onto ACLI when connecting to that host\n";
	print " -g               : Show GUI even if host/IP and credentials provided\n";
	print " -h               : Help and usage (this output)\n";
	print " -i <log-dir>     : Path to use when logging to file\n";
	print " -m <script>      : Once connected execute script (if no path included will use \@run search paths)\n";
	print " -n               : Launch terminals in transparent mode (no auto-detect & interact)\n";
	print " -p ssh|telnet    : Protocol to use; can be either SSH or Telnet (case insensitive)\n";
	print " -s <sockets>     : List of socket names for terminals to listen on (0 to disable sockets)\n";
	print " -t <window-title>: Sets the containing window title into which all connections will be opened\n";
	print " -u user[:<pwd>]  : Specify username[& password] to use\n";
	print " -w <work-dir>    : Working directory to use (including for <hostfile>)\n";
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


sub checkValidIP { # v1 - Verify that the IP address is valid
	my ($tk, $ip, $ipv6, $line) = @_;
	$line = length $line ? " at line $line" : '';
	my $firstByte = 1;
	if ($ipv6) {
		if (($ipv6 = $ip) =~ /::/) {
			$ipv6 =~ s/::/my $r = ':'; $r .= '0:' for (1 .. (9 - scalar split(':', $ip))); $r/e;
		}
		return errorMsg($tk, "Invalid IP", "Invalid IPv6 $ip$line") if $ipv6 =~ /::/;
		my @ipBytes = split(/:/, $ipv6);
		return errorMsg($tk, "Invalid IP", "Invalid IPv6 $ip$line") if scalar @ipBytes != 8;
		foreach my $byte ( @ipBytes ) {
			return errorMsg($tk, "Invalid IP", "Invalid IPv6 $ip$line") unless $byte =~ /^[\da-fA-F]{1,4}$/;
			if ($firstByte) {
				return errorMsg($tk, "Invalid IP", "Invalid IPv6 $ip$line") if hex($byte) == 0;
				return errorMsg($tk, "Invalid IP", "Invalid IPv6 $ip$line") if hex($byte) >= 65280;
				$firstByte = 0;
			}
			return errorMsg($tk, "Invalid IP", "Invalid IPv6 $ip$line") if hex($byte) > 65535;
		}
		debugMsg(1, " - IPv6 address = ", \$ipv6, "\n");
	}
	else { # IPv4
		my @ipBytes = split(/\./, $ip);
		return errorMsg($tk, "Invalid IP", "Invalid IP $ip$line") if scalar @ipBytes != 4;
		foreach my $byte ( @ipBytes ) {
			if ($firstByte) {
				return errorMsg($tk, "Invalid IP", "Invalid IP $ip$line") if $byte == 0;
				return errorMsg($tk, "Invalid IP", "Invalid IP $ip$line") if $byte >= 224;
				$firstByte = 0;
			}
			return errorMsg($tk, "Invalid IP", "Invalid IP $ip$line") if $byte > 255;
		}
		debugMsg(1, " - IPv4 address = ", \$ip, "\n");
	}
	return 1; # Is valid
}


sub listHosts { # v2 - Produce a list of hostnames from command line
	my ($inList, $tk) = @_;
	my (@commaList, @outList, $basePart, $ipv6, $ipPort);
	# Split into comma separated list 1st
	@commaList = split(',', $inList);

	#Run through list
	foreach my $host (@commaList) {
		debugMsg(1, "processing input = ", \$host, "\n");
		if ($host =~ /^(\d+\.\d+\.\d+\.)\d+$/) { # 1.2.3.4
			($basePart, $ipv6, $ipPort) = ($1, undef, undef);
			return unless checkValidIP($tk, $host);
			return errorMsg($tk, "Duplicate IP", "Duplicate IP $host") if grep($_ eq $host, @outList);
			push(@outList, $host) unless grep(/^$host$/, @outList);
		}
		elsif ($host =~ /^((?:\w*:)+)\w+$/) { # 2000::10
			($basePart, $ipv6, $ipPort) = ($1, 1, undef);
			return unless checkValidIP($tk, $host, 1);
			return errorMsg($tk, "Duplicate IP", "Duplicate IP $host") if grep($_ eq $host, @outList);
			push(@outList, $host) unless grep(/^$host$/, @outList);
		}
		elsif ($host =~ /^(\[(\d+\.\d+\.\d+\.\d+)\]:)\d+$/) { # [1.2.3.4]:10
			($basePart, $ipv6, $ipPort) = ($1, undef, 1);
			return unless checkValidIP($tk, $2);
			return errorMsg($tk, "Duplicate IP:Port", "Duplicate IP:Port $host") if grep($_ eq $host, @outList);
			push(@outList, $host) unless grep(/^$host$/, @outList);
		}
		elsif ($host =~ /^(\[((?:\w*:)+\w+)\]:)\d+$/) { # [2000::10]:10
			($basePart, $ipv6, $ipPort) = ($1, undef, 1);
			return unless checkValidIP($tk, $2, 1);
			return errorMsg($tk, "Duplicate IP:Port", "Duplicate IP:Port $host") if grep($_ eq $host, @outList);
			push(@outList, $host) unless grep(/^$host$/, @outList);
		}
		elsif ($host =~ /^(\d+\.\d+\.\d+\.)(\d+)-(\d+)$/) { # 1.2.3.4-10
			($basePart, $ipv6, $ipPort) = ($1, undef, undef);
			my ($startVal, $endVal) = ($2, $3);
			return errorMsg($tk, "Invalid IP", "Invalid IP starting range $startVal") if $startVal > 255;
			return errorMsg($tk, "Invalid IP", "Invalid IP ending range $endVal") if $endVal > 255;
			return errorMsg($tk, "Invalid IP", "Invalid IP range $startVal-$endVal") if $startVal >= $endVal;
			return errorMsg($tk, "Too many connections", "A single ConsoleZ window does not scale well with more than $MaxWindowSessions tabs") if ($endVal - $startVal + 1) > $MaxWindowSessions;
			for my $i ($startVal .. $endVal) {
				my $ip = $basePart.$i;
				return unless checkValidIP($tk, $ip);
				return errorMsg($tk, "Duplicate IP", "Duplicate IP $ip") if grep($_ eq $ip, @outList);
				push(@outList, $ip) unless grep(/^$ip$/, @outList);
			}
		}
		elsif ($host =~ /^((?:\w*:)+)([1-9]\d*)-([1-9]\d*)$/) { # 2000:10::1-10 (decimal range 1-10)
			($basePart, $ipv6, $ipPort) = ($1, 1, undef);
			my ($startVal, $endVal) = ($2, $3);
			return errorMsg($tk, "Invalid IP", "Invalid IP starting range $startVal") if $startVal > 9999;
			return errorMsg($tk, "Invalid IP", "Invalid IP ending range $endVal") if $endVal > 9999;
			return errorMsg($tk, "Invalid IP", "Invalid IP range $startVal-$endVal") if $startVal >= $endVal;
			return errorMsg($tk, "Too many connections", "A single ConsoleZ window does not scale well with more than $MaxWindowSessions tabs") if ($endVal - $startVal + 1) > $MaxWindowSessions;
			for my $i ($startVal .. $endVal) {
				my $ip = $basePart.$i;
				return unless checkValidIP($tk, $ip, 1);
				return errorMsg($tk, "Duplicate IP", "Duplicate IP $ip") if grep($_ eq $ip, @outList);
				push(@outList, $ip) unless grep(/^$ip$/, @outList);
			}
		}
		elsif ($host =~ /^((?:\w*:)+)(\w+)-(\w+)$/) { # 2000:20::01-10 (hex range 1,2,3,4,5,6,7,8,9,a,b,c,d,e,f,10)
			($basePart, $ipv6, $ipPort) = ($1, 1, undef);
			my ($startVal, $endVal) = ($2, $3);
			$startVal =~ s/^0+//;	# Remove leading zeros
			$endVal =~ s/^0+//;	# ditto
			return errorMsg($tk, "Invalid IP", "Invalid IP starting range $startVal") unless $startVal =~ /^[\da-fA-F]{1,4}$/;
			return errorMsg($tk, "Invalid IP", "Invalid IP ending range $endVal") unless $endVal =~ /^[\da-fA-F]{1,4}$/;
			return errorMsg($tk, "Invalid IP", "Invalid IP range $startVal-$endVal") if hex($startVal) >= hex($endVal);
			return errorMsg($tk, "Too many connections", "A single ConsoleZ window does not scale well with more than $MaxWindowSessions tabs") if (hex($endVal) - hex($startVal) + 1) > $MaxWindowSessions;
			for my $i (hex($startVal) .. hex($endVal)) {
				my $ip = sprintf("%s%x", $basePart, $i);
				return unless checkValidIP($tk, $ip, 1);
				return errorMsg($tk, "Duplicate IP", "Duplicate IP $ip") if grep($_ eq $ip, @outList);
				push(@outList, $ip) unless grep(/^$ip$/, @outList);
			}
		}
		elsif ($host =~ /^(\[(\d+\.\d+\.\d+\.\d+)\]:)(\d+)-(\d+)$/) { # [1.2.3.4]:10-20
			($basePart, $ipv6, $ipPort) = ($1, undef, 1);
			my ($startVal, $endVal) = ($3, $4);
			return unless checkValidIP($tk, $2);
			return errorMsg($tk, "Invalid TCP port", "Invalid TCP port starting range $startVal") if $startVal > 65535;
			return errorMsg($tk, "Invalid TCP port", "Invalid TCP port ending range $endVal") if $endVal > 65535;
			return errorMsg($tk, "Invalid TCP port", "Invalid TCP port range $startVal-$endVal") if $startVal >= $endVal;
			return errorMsg($tk, "Too many connections", "A single ConsoleZ window does not scale well with more than $MaxWindowSessions tabs") if ($endVal - $startVal + 1) > $MaxWindowSessions;
			for my $i ($startVal .. $endVal) {
				my $ip = $basePart.$i;
				return errorMsg($tk, "Duplicate IP:Port", "Duplicate IP:Port $ip") if grep($_ eq $ip, @outList);
				push(@outList, $ip) unless grep(/^$ip$/, @outList);
			}
		}
		elsif ($host =~ /^(\[((?:\w*:)+\w+)\]:)(\d+)-(\d+)$/) { # [2000::10]:10-20
			($basePart, $ipv6, $ipPort) = ($1, undef, 1);
			my ($startVal, $endVal) = ($3, $4);
			return unless checkValidIP($tk, $2, 1);
			return errorMsg($tk, "Invalid TCP port", "Invalid TCP port starting range $startVal") if $startVal > 65535;
			return errorMsg($tk, "Invalid TCP port", "Invalid TCP port ending range $endVal") if $endVal > 65535;
			return errorMsg($tk, "Invalid TCP port", "Invalid TCP port range $startVal-$endVal") if $startVal >= $endVal;
			return errorMsg($tk, "Too many connections", "A single ConsoleZ window does not scale well with more than $MaxWindowSessions tabs") if ($endVal - $startVal + 1) > $MaxWindowSessions;
			for my $i ($startVal .. $endVal) {
				my $ip = $basePart.$i;
				return errorMsg($tk, "Duplicate IP:Port", "Duplicate IP:Port $ip") if grep($_ eq $ip, @outList);
				push(@outList, $ip) unless grep(/^$ip$/, @outList);
			}
		}
		elsif ($host =~ /^([1-9]\d*)-([1-9]\d*)$/) { # 1-10 (decimal range 1-10)
			my ($startVal, $endVal) = ($1, $2);
			return errorMsg($tk, "Invalid IP", "No base IP for range $startVal-$endVal") unless defined $basePart;
			if ($ipPort) {
				return errorMsg($tk, "Invalid TCP port", "Invalid TCP port starting range $startVal") if $startVal > 65535;
				return errorMsg($tk, "Invalid TCP port", "Invalid TCP port ending range $endVal") if $endVal > 65535;
				return errorMsg($tk, "Invalid TCP port", "Invalid TCP port range $startVal-$endVal") if $startVal >= $endVal;
			}
			else {
				return errorMsg($tk, "Invalid IP", "Invalid IP starting range $startVal") if $startVal > ($ipv6 ? 9999 : 255);
				return errorMsg($tk, "Invalid IP", "Invalid IP ending range $endVal") if $endVal > ($ipv6 ? 9999 : 255);
				return errorMsg($tk, "Invalid IP", "Invalid IP range $startVal-$endVal") if $startVal >= $endVal;
			}
			return errorMsg($tk, "Too many connections", "A single ConsoleZ window does not scale well with more than $MaxWindowSessions tabs") if ($endVal - $startVal + 1) > $MaxWindowSessions;
			for my $i ($startVal .. $endVal) {
				my $ip = $basePart.$i;
				return unless checkValidIP($tk, $ip, $ipv6);
				my $suffix = $ipPort ? ':Port' : '';
				return errorMsg($tk, "Duplicate IP$suffix", "Duplicate IP$suffix $ip") if grep($_ eq $ip, @outList);
				push(@outList, $ip) unless grep(/^$ip$/, @outList);
			}
		}
		elsif ($host =~ /^([\da-fA-F]{1,4})-([\da-fA-F]{1,4})$/ && $ipv6) { # 01-10 (hex range 1,2,3,4,5,6,7,8,9,a,b,c,d,e,f,10)
			my ($startVal, $endVal) = ($1, $2);
			return errorMsg($tk, "Invalid IP", "Invalid IP range $startVal-$endVal") if hex($startVal) >= hex($endVal);
			return errorMsg($tk, "Too many connections", "A single ConsoleZ window does not scale well with more than $MaxWindowSessions tabs") if (hex($endVal) - hex($startVal) + 1) > $MaxWindowSessions;
			for my $i (hex($startVal) .. hex($endVal)) {
				my $ip = sprintf("%s%x", $basePart, $i);
				return unless checkValidIP($tk, $ip, $ipv6);
				return errorMsg($tk, "Duplicate IP", "Duplicate IP $ip") if grep($_ eq $ip, @outList);
				push(@outList, $ip) unless grep(/^$ip$/, @outList);
			}
		}
		elsif ($host =~ /^(\d+)$/) { # 10
			return errorMsg($tk, "Invalid IP", "No base IP for ip last byte $1") unless defined $basePart;
			my $ip = $basePart.$1;
			return unless $ipPort || checkValidIP($tk, $ip, $ipv6);
			my $suffix = $ipPort ? ':Port' : '';
			return errorMsg($tk, "Duplicate IP$suffix", "Duplicate IP$suffix $ip") if grep($_ eq $ip, @outList);
			push(@outList, $ip) unless grep(/^$ip$/, @outList);
		}
		elsif ($host =~ /^([\da-fA-F]{1,4})$/ && $ipv6) { # 0a
			my $ip = $basePart.$1;
			return unless $ipPort || checkValidIP($tk, $ip, 1);
			return errorMsg($tk, "Duplicate IP", "Duplicate IP $ip") if grep($_ eq $ip, @outList);
			push(@outList, $ip) unless grep(/^$ip$/, @outList);
		}
		else { # Assume a hostname
			debugMsg(1, " - treating as hostname: ", \$host, "\n");
			$basePart = $ipv6 = undef;
			return errorMsg($tk, "Duplicate Hostname", "Duplicate hostname $host") if grep($_ eq $host, @outList);
			push(@outList, $host) unless grep(/^$host$/, @outList);
		}
	}
	return \@outList;
}


sub loadHosts { # Read a list of hostnames from file
	my $infile = shift;
	my (@outList, %hashNames, %hashOptions, $lineNum);

	debugMsg(1, "loadHosts: opening file: ", \File::Spec->rel2abs($infile), "\n");
	open(FILE, $infile) or quit(1, "Cannot open input hosts file: $!");
	while (<FILE>) {
		$lineNum++;
		chomp;				# Remove trailing newline char
		next if /^#/;			# Skip comment lines
		next if /^\s*$/;		# Skip blank lines
		next if /^(?:\@echo|acligui|exit)/;		# Skip batch launcher lines
		if (/^\s*(\S+)\s*(?:([^-]\S+)\s*)?(?:-([nt])\s*)?(?:\#|$)/) {	# Valid entry
			my ($host, $hostname, $options) = ($1, $2, $3);
			debugMsg(1, "processing file input = $host	", \$hostname, "\n");
			checkValidIP(undef, $host, undef, $lineNum) if $host =~ /^\d+\.\d+\.\d+\.\d+$/;
			checkValidIP(undef, $1, undef, $lineNum) if $host =~ /^\[(\d+\.\d+\.\d+\.\d+)\]:\d+$/;
			checkValidIP(undef, $host, 1, $lineNum) if $host =~ /^(?:\w*:)+\w+$/;
			checkValidIP(undef, $1, 1, $lineNum) if $host =~ /^\[(?:\w*:)+\w+\]:\d+$/;
			push(@outList, $host) unless grep(/^$host$/, @outList);
			$hashNames{$host} = $hostname;
			$hashOptions{$host} = $options;
			next;
		}
		quit(1, "Hosts file \"$infile\" invalid syntax at line $lineNum\n");
	}
	return (\@outList, \%hashNames, \%hashOptions);
}


sub splitHostPort { # Given an IP/hostname in format [<ip/hostname>]:<port> will split and return the host and port parts
	my $inputHost = shift;
	return ($1, $2) if $inputHost =~ /\[([^\]]+)\]:(\d+)/;
	return ($inputHost, undef); # Otherwise
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
	my ($ipListRef, $launchValues, $tk) = @_;
	my $waitTimer;
	my $containingWindow = length $launchValues->{Window} ? $launchValues->{Window} : $ConsoleWinTitle;
	my $execTemplate = readAcliSpawnFile($tk);
	return unless defined $execTemplate;

	return errorMsg($tk, "Too many IPs", "A single ConsoleZ window does not scale well with more than $MaxWindowSessions tabs") if scalar @$ipListRef > $MaxWindowSessions;
	$launchValues->{IpNames} = undef unless $launchValues->{IpList} eq $launchValues->{InitIpList}; # Clear names unless what provided from command line
	for my $hostkey (@$ipListRef) {
		debugMsg(1,"\nlaunchNewTerm / hostkey = ", \$hostkey, "\n");
		my ($host, $port) = splitHostPort($hostkey);
		my $acliArgs = '';
		$acliArgs .= '-d 7 ' if $Debug;
		$acliArgs .= '-n ' if $launchValues->{Transparent} || (defined $launchValues->{IpOptions}->{$hostkey} && $launchValues->{IpOptions}->{$hostkey} eq 'n');
		$acliArgs .= '-t ' if !$launchValues->{Transparent} && defined $launchValues->{IpOptions}->{$hostkey} && $launchValues->{IpOptions}->{$hostkey} eq 't';
		$acliArgs .= "-w \\\"$launchValues->{WorkDir}\\\" " if defined $launchValues->{WorkDir};
		$acliArgs .= "-i \\\"$launchValues->{LogDir}\\\" " if defined $launchValues->{LogDir};
		$acliArgs .= "-s \\\"$launchValues->{Sockets}\\\" " if defined $launchValues->{Sockets} && ($acliArgs !~ /-n/ || $launchValues->{Sockets} eq '0');
		$acliArgs .= "-m \\\"$launchValues->{RunScript}\\\" " if defined $launchValues->{RunScript};
		if (defined $launchValues->{Username}) {
			my $credentials = $launchValues->{Username} . (defined $launchValues->{Password} ? ':'.$launchValues->{Password} : '');
			if ($launchValues->{'Protocol'} eq 'SSH') {
				$acliArgs .= "-l \\\"$credentials\\\" $host";
			}
			else { # TELNET
				$acliArgs .= "\\\"$credentials\@$host\\\"";
			}
		}
		$acliArgs .= " " . $port if defined $port;

		my $executeArgs = substituteExecArgs( # Substitutes values into the executable arguments template
			$execTemplate->{arguments},										# Template
			$containingWindow,											# <WINDOW-NAME>
			$containingWindow,											# <INSTANCE-NAME>
			(defined $launchValues->{IpNames}->{$hostkey} ? $launchValues->{IpNames}->{$hostkey} : $hostkey),	# <TAB-NAME>
			File::Spec->rel2abs(cwd), 										# <CWD>
			$ConsoleAcliProfile,											# <ACLI-PROFILE>
			$ScriptDir . 'acli',											# <ACLI-PATH>
			$ScriptDir . 'acli.pl',											# <ACLI-PL-PATH>
			$acliArgs,												# <ACLI-ARGS>
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
			return errorMsg($tk, "Failed to Launch", "Error launching $hostkey with ACLI Terminal") unless $processObj;
		}
		else { # Any other OS (MAC-OS and Linux...)
			my $executable = join(' ', $execTemplate->{executable}, $executeArgs);
			debugMsg(1,"launchNewTerm / execuatable after joining = ", \$executable, "\n");
			my $retVal = system($executable);
			return errorMsg($tk, "Failed to Launch", "Error launching $hostkey with ACLI Terminal") if $retVal;
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
		#last if ++$count == $HistoryDepth;
	}
	close HISTORY;
	debugMsg(1, "writeHistoryFile - updated history file : ", \$histFile, "\n");
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
	my ($tk, $launchValues) = @_;
	my $ipList = $launchValues->{IpList};
	$ipList =~ s/\s+//g;	# Remove all spaces
	unless (length $ipList) {
		$tk->{mw}->messageBox(
			-title	=> 'Missing hostname / IP list',
			-icon	=> 'info',
			-type	=> 'OK',
			-message => 'No hostname / IP list provided',
	        );
		$tk->{enIpList}->focus;
	        return;
	}
	my $ipListRef = listHosts($ipList, $tk);
	launchConsole($ipListRef, $launchValues, $tk);
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


#############################
# MAIN                      #
#############################

MAIN:{
	getopts('df:ghi:m:np:s:t:u:w:');

	$Debug = 1 if $opt_d;
	printSyntax if $opt_h || scalar @ARGV > ($opt_f ? 0 : 1);

	my ($ipList, $username, $password, $protocol, $workDir, $logDir, $ipListRef, $ipNamesRef, $ipOptionsRef, $sockets, $runScript, $window, $transparent);

	$window = $opt_t if defined $opt_t;
	$workDir = $opt_w if defined $opt_w;
	$logDir = $opt_i if defined $opt_i;
	$sockets = $opt_s if defined $opt_s;
	$runScript = $opt_m if defined $opt_m;
	$transparent = $opt_n if defined $opt_n;

	if (@ARGV) {
		$ipList = shift @ARGV;
		$ipListRef = listHosts($ipList); # Just let this run, if there is an error in the IP list provided it will bomb out
	}
	elsif ($opt_f) { # if a file is provided with no path, and -w is set, then look for the hostfile in -w path 
		my $hostfile = File::Spec->splitdir($opt_f) == 1 && $opt_w ? File::Spec->canonpath($opt_w) . '/' . $opt_f : $opt_f;
		($ipListRef, $ipNamesRef, $ipOptionsRef) = loadHosts($hostfile); # If there is an error in the IP list provided it will bomb out
		$ipList = join(',', @$ipListRef);
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

	my $launchValues = { # Values to use to launch ACLI with
		InitIpList	=> $ipList || '',
		IpList		=> $ipList || '',
		IpNames		=> $ipNamesRef,
		IpOptions	=> $ipOptionsRef,
		Username	=> $username,
		Password	=> $password,
		Protocol	=> $protocol,
		Window		=> $window,
		WorkDir		=> $workDir,
		LogDir		=> $logDir,
		Sockets		=> $sockets,
		RunScript	=> $runScript,
		Transparent	=> $transparent,
	};

	if (!$opt_g && defined $ipListRef && ($transparent || (defined $username && defined $password) ) ) {
		# We have all we need, skip the gui and launch directly
		launchConsole($ipListRef, $launchValues);
		exit 0;
	}

	my $tk = { # Perl/tk window pointers
		mw				=> undef,	# Main Window
		mwFrameGrid			=> undef,	# Frame with parameters
			enIpList		=> undef,	# IP List entry box
			enUsername		=> undef,	# Username entry box
			enPassword		=> undef,	# Password entry box
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
	$tk->{mw}->title('ACLI GUI Launcher - v' . $Version);
	$tk->{mw}->resizable(0,0); # Prevent window resize

	# Frame containing buttons at the bottom of main window
	$tk->{mwFrameButtons} = $tk->{mw}->Frame;
		# LAUNCH button
		$tk->{btLaunch} = $tk->{mwFrameButtons}->Button(
			-text		=> 'Launch',
			-command	=> [\&launch, $tk, $launchValues],
		)->pack( -side => 'left', -expand => 1, -fill => 'x' );

		# CLEAR button
		$tk->{btClear} = $tk->{mwFrameButtons}->Button(
			-text		=> 'Clear',
			-command	=> [\&clear, $launchValues],
		)->pack( -side => 'left', -expand => 1, -fill => 'x' );

		# QUIT button
		$tk->{btQuit} = $tk->{mwFrameButtons}->Button(
			-text		=> 'Quit',
			-command	=> \&exit
		)->pack( -side => 'left', -expand => 1, -fill => 'x' );
	$tk->{mwFrameButtons}->pack( -side => 'bottom', -expand => 1, -fill => 'both' );

	# Frame containing the parameters and their labels, using grid geometry manager
	$tk->{mwFrameGrid} = $tk->{mw}->Frame;
		$tk->{mwFrameGrid}->Label(-text => "Hostname or IP Address List:")->grid(-row => 0, -column => 0);
		$tk->{enIpList} = $tk->{mwFrameGrid}->Entry(
			-textvariable	=> \$launchValues->{IpList},
			-width		=> $IPentryBoxWidth,
			-background	=> 'white',
		)->grid(-row => 0, -column => 1);

		$tk->{mwFrameGrid}->Label(-text => "Username:")->grid(-row => 1, -column => 0, -sticky => 'e');
		$tk->{enUsername} = $tk->{mwFrameGrid}->Entry(
			-textvariable	=> \$launchValues->{Username},
			-width		=> $CredentialBoxWidth,
			-background	=> 'white',
		)->grid(-row => 1, -column => 1, -sticky => 'w');

		$tk->{mwFrameGrid}->Label(-text => "Password:")->grid(-row => 2, -column => 0, -sticky => 'e');
		$tk->{enPassword} = $tk->{mwFrameGrid}->Entry(
			-textvariable	=> \$launchValues->{Password},
			-width		=> $CredentialBoxWidth,
			-show		=> '*',
			-background	=> 'white',
		)->grid(-row => 2, -column => 1, -sticky => 'w');

		$tk->{mwFrameGrid}->Label(-text => "Protocol:")->grid(-row => 3, -column => 0, -sticky => 'e');
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
		$tk->{frameProtocol}->grid(-row => 3, -column => 1, -sticky => 'w');

		$tk->{mwFrameGrid}->Label(-text => "Transparent mode:")->grid(-row => 4, -column => 0, -sticky => 'e');
		$tk->{enTransparent} = $tk->{mwFrameGrid}->Checkbutton(
			-variable	=> \$launchValues->{Transparent},
		)->grid(-row => 4, -column => 1, -sticky => 'w');

		$tk->{mwFrameGrid}->Label(-text => "Containing Window:")->grid(-row => 5, -column => 0, -sticky => 'e');
		$tk->{enWindow} = $tk->{mwFrameGrid}->Entry(
			-textvariable	=> \$launchValues->{Window},
			-width		=> $WindowNameBoxWidth,
			-background	=> 'white',
		)->grid(-row => 5, -column => 1, -sticky => 'w');

		$tk->{mwFrameGrid}->Label(-text => "Working Directory:")->grid(-row => 6, -column => 0, -sticky => 'e');
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
		$tk->{frameWorkDir}->grid(-row => 6, -column => 1, -sticky => 'w');

		$tk->{mwFrameGrid}->Label(-text => "Logging Directory:")->grid(-row => 7, -column => 0, -sticky => 'e');
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
		$tk->{frameLogDir}->grid(-row => 7, -column => 1, -sticky => 'w');

		$tk->{mwFrameGrid}->Label(-text => "Listen Socket Names:")->grid(-row => 8, -column => 0, -sticky => 'e');
		$tk->{enSockets} = $tk->{mwFrameGrid}->Entry(
			-textvariable	=> \$launchValues->{Sockets},
			-width		=> $SocketNamesWidth,
			-background	=> 'white',
		)->grid(-row => 8, -column => 1, -sticky => 'w');

		$tk->{mwFrameGrid}->Label(-text => "Run Script:")->grid(-row => 9, -column => 0, -sticky => 'e');
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
		$tk->{frameRunScript}->grid(-row => 9, -column => 1, -sticky => 'w');

	$tk->{mwFrameGrid}->pack;

	MainLoop;	#perl/tk mainloop
}
