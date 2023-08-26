#!/usr/bin/perl

my $Version = "1.07";

# Written by Ludovico Stevens (lstevens@extremenetworks.com)
# Bulk CLI Command tool for Extreme Networks devices

# 0.01	- Initial
# 0.02	- Switched to using Control::CLI::Extreme
# 0.03	- Can now read hosts out of batch file
# 1.00	- Updated to accept IPv6 addresses
#	- Added -p option to provide password on command line
# 1.01	- Added -i option
#	- Fixed option -f which was no longer working since addition of IPv6 support
# 1.02	- The -f hostfile now accepts IPs/Hostnames + TCP port number in format [<ip/hostname>]:<port>
# 1.03	- Commands which change the device prompt are now detected upfront and Reset_prompt is set on cmd method
# 1.04	- Added support for $$ variable in supplied commands; if acmd was supplied with a -f hosts file and names
#	  are associated in it for each IP/hostname, then those names will be used to replace $$ in the commands
# 1.05	- Added support and new syntax for reading in data from a spreadsheet; spreadsheet must be a simple table
#	  where one designated column has the switch IPs (or hostnames) and the other columns provide values into
#	  $variables which can be used in the supplied commands; the variable names need to match the spreadsheet
#	  column label name (case insensitive)
# 1.06	- Corrections to debug function
# 1.07	- Password prompt was asking always for username "rwa" even if a different username was specified
#	- Made changes so it can work even with a "generic" host which is not an Extreme Networks switch

#############################
# STANDARD MODULES          #
#############################

use strict;
use warnings;
use Getopt::Std;
use File::Basename;
use Term::ReadKey;
use Time::HiRes;
use Control::CLI::Extreme qw(poll);	# Export class poll method
#use Spreadsheet::Read; # This is "required" only in readSpreadsheet()


############################
# GLOBAL DEFAULT VARIABLES #
############################
my $Debug = 0;			# bit0 = acmd only; bit1 = Control::CLI::Extreme
my $Timeout = 20;
my $PollTimer = 100;		# Polling loop timer in ms
my $Username = 'rwa';
my $Password = 'rwa';
my $ScriptName = basename($0);
my $DebugLog = $ScriptName . '.debug';
my $HostDebugLog = $ScriptName . '<HOST>.debug';
my $ControlCLIDebugLevel = 13;
my $DebugLogFH;
our ($opt_a, $opt_d, $opt_f, $opt_g, $opt_i, $opt_l, $opt_n, $opt_o, $opt_p, $opt_s, $opt_t, $opt_x, $opt_y);


############################
# Global Matching patterns #
############################

# Copied from AcliPm::GlobalMatchingPatterns;
my $VarNormal = '[\w_\d]+';	# Matches valid user variable names (modified to reject $% + $*)
my $VarDelim = '(?=[\s;:,|!\.\/\\\"\+\-\*\%\)\}\]\$\>\<\?]|$)'; # Matches at the end of a valid variable
my %ChangePromptCmds = ( # Commands which change the device prompt; for which we need to re-lock onto the new prompt
	BaystackERS	=> '^\s*snm(?:p(?:-(?:s(?:e(?:r(?:v(?:er?)?)?)?)?)?)?)? +na',		# snmp-server name
	PassportERS	=> '^\s*(?:(?:(?:con(?:f(?:ig?)?)?)? +)?(?:cli +pr|sys? +set? +n)|snmp-(?:s(?:e(?:r(?:v(?:er?)?)?)?)?) +na)|pr(?:o(?:m(?:pt?)))',
												# PPCLI: config cli prompt OR config sys set name
												# ACLI:  snmp-server name OR prompt
	ExtremeXOS	=> '^\s*co(?:n(?:f(?:i(?:g(?:u(?:re?)?)?)?)?)?)? +snmp +sysn',		# configure snmp sysname
	ISW		=> '^\s*ho',								# hostname
	Series200	=> '^\s*(?:(?:no )?ho|set +p)',						# hostname / set prompt (both in privExec only)
	Wing		=> '^\s*com',								# commit (hostname is the command, but it gets applied after commit, so does not work)
	SLX		=> '^\s*sw(?:i(?:t(?:c(?:h(?:-(?:a(?:t(?:t(?:r(?:i(?:b(?:u(?:t(?:es?)?)?)?)?)?)?)?)?)?)?)?)?)?)? +h',	# switch-attributes host-name
	SecureRouter	=> '^\s*ho',								# hostname
	WLAN2300	=> '^\s*set? +pr',							# set prompt
	WLAN9100	=> '^\s*ho',								# hostname
	Accelar		=> '^\s*(?:(?:con(?:f(?:ig?)?)?)? +)?(?:cli +pr|sys? +set? +n)',	# config cli prompt OR config sys set name
);

# Copied from AcliPm::GlobalDeviceSettings;
my %DeviceComment = ( # This structure holds the character which acts as comment in ascii config
		BaystackERS	=> '!',
		PassportERS	=> '#',
		ExtremeXOS	=> '#',
		ISW		=> '!',
		Series200	=> '!',
		Wing		=> '!',
		SLX		=> '!',
		SecureRouter	=> '#',
		WLAN2300	=> '#',
		WLAN9100	=> '!',
		Accelar		=> '#',
);


#############################
# FUNCTIONS                 #
#############################

sub printSyntax {
	printf "%s version %s%s\n\n", $ScriptName, $Version, ($Debug ? " running on $^O perl version $]" : "");
	print " Execution of CLI commands/script in bulk to many Extreme Networks devices using SSH or Telnet\n";
	print "\nUsage:\n";
	print " $ScriptName [-agiopty] [-l <user>] <host/IP/list> <telnet|ssh> \"semicolon-separated-cmds\" [<output-file>]\n";
	print " $ScriptName [-agiopty] [-l <user>] -s <script-file> <host/IP/list> <telnet|ssh> [<output-file>]\n";
	print " $ScriptName [-agiopty] [-l <user>] -f <hostfile> <telnet|ssh> \"semicolon-separated-cmds\" [<output-file>]\n";
	print " $ScriptName [-agiopty] [-l <user>] -f <hostfile> -s <script-file> <telnet|ssh> [<output-file>]\n";
	print " $ScriptName [-agiopty] [-l <user>] -x <spreadsheet>[:<sheetname>]!<column-label> <telnet|ssh> \"semicolon-separated-cmds\" [<output-file>]\n";
	print " $ScriptName [-agiopty] [-l <user>] -x <spreadsheet>[:<sheetname>]!<column-label> -s <script-file> <telnet|ssh> [<output-file>]\n\n";
	print " -a               : In staggered mode (-g) abort further iterations if at least one host fails\n";
	print " -f <hostfile>    : File containing a list of hostnames/IPs to connect to; valid lines:\n";
	print "                  :   <IP/hostname>         [<display-name>] [# Comments]\n";
	print "                  :  [<IP/hostname>]:<port> [<display-name>] [# Comments]\n";
	print " -g <number-N>    : Stagger job over more iterations each for a maximum of N hosts;\n";
	print "                    if not specified, job is performed against all hosts in a single cycle\n";
	print " -i               : Create output file per-host, using filename <host/IP>[_<output-file>]\n";
	print " -l <user>        : Specify user credentials to use (password will be prompted)(default = rwa/rwa)\n";
	print " -o               : Overwrite <output-file>; default is to append\n";
	print " -p <password>    : Specify a password via command line (instead of being prompted for it)\n";
	print " -s <script-file> : File containing list of commands to be executed against all hosts\n";
	print " -t <timeout>     : Timeout value in seconds to use (default = 20secs)\n";
	print " -x <spreadsheet>[:<sheetname>]!<column-label>  : Spreadsheet file (Microsoft Excel, OpenOffice, CSV)\n";
	print "                    Spreadsheet must be a simple table where every row is a device with a number\n";
	print "                    of parameters. The first row of the table must be a label for the column values.\n";
	print "                    The label corresponding to the column with the switch IP/hostnames must be\n";
	print "                    supplied in <column-label>. The other column labels can be embedded as variables\n";
	print "                    \$<label-name> in the supplied CLI commands or script file.\n";
	print "                    The <column-label> and \$<label-name> names are case insensitive and any spaces used\n";
	print "                    within them in the spreadsheet will be replaced with the '_' underscore character.\n";
	print "                    The <sheetname> is optional; if not supplied the first sheet of the spreadsheet\n";
	print "                    will be used\n";
	print " -y               : Skip job detailed summary and user confirmation prompt\n";
	print " <host/IP list>   : List of hostnames or IP addresses\n";
	print "                  : Note that valid IP lists can be written as: 192.168.10.1-10,40-45,51\n";
	print "                  : IPv6 addresses are also supported: 2000:10::1-10 (decimal range 1-10)\n";
	print "                  : 2000:20::01-10 (hex range 1,2,3,4,5,6,7,8,9,a,b,c,d,e,f,10)\n";
	print " <telnet|ssh>     : Protocol to use\n";
	print " <output-file>    : Output file (and suffix with -i) for output filenames\n"; 
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
		if ($DebugLogFH) { print {$DebugLogFH} $string1, $refPrint, $string2 }
		else { print $string1, $refPrint, $string2 }
	}
}

sub quit {
	my ($retval, $quitmsg) = @_;
	print "\n$ScriptName: ",$quitmsg,"\n" if $quitmsg;
	# Clean up and exit
	exit $retval;
}

sub statusMsg { # Print status messages
	print @_;
	$| = 1; # Flush STDOUT buffer
	$| = 0; # Revert to line buffered mode
}

sub printDot { # Prints unbuffered dot for polling activity
	statusMsg('.');
}

sub promptOk { # Prompt user to proceed
	my $key;
	local $| = 1;
	print "OK to proceed [Y = yes; any other key = no] ? ";
	do {
	        Time::HiRes::sleep(0.1); # Fraction of a sec sleep (otherwise CPU gets hammered..)
		$key = ReadKey(-1);
	} until defined $key;
	if ($key =~ /^[Yy]$/) {
		print "y\n";
		return 1;
	}
	else {
		print "\n";
		return 0;
	}
}

sub promptHide { # Interactively prompt for a password, input is hidden
	my $password = shift;
	my $input;
	print "Enter $password: ";
	ReadMode('noecho');
	chomp($input = ReadLine(0));
	ReadMode('restore');
	print "\n";
	return $input;
}

sub quoteMask { # Returns a new string where all occurrences of char(s) are replaced inside quoted (or curlies) sections with hex \x00 \x01 etc..
	my ($string, $char) = @_;
	my @chars = split(//, $char);
	map(s/([|!^\$\%])/\\$1/, @chars); # Characters which need backslashing
	my ($quote, $i);
	$string =~ s/(\".*?\"|\'.*?\'|\{.*?\})/$quote = $1; foreach $i (0..$#chars) {$quote =~ s!$chars[$i]!chr($i)!ge}; $quote/ge;
	#debugMsg(1,"-> String quotes masked for '$char' : $string\n");
	return $string;
}

sub quoteUnmask { # Restores all occurrences of char(s) inside quoted (or curlies) sections if these were previously masked with hex \x00 \x01 etc..
	my ($string, $char) = @_;
	my @chars = split(//, $char);
	my ($quote, $i);
	$string =~ s/(\".*?\"|\'.*?\'|\{.*?\})/$quote = $1; foreach $i (0..$#chars) {$quote =~ s!\x$i!$chars[$i]!g}; $quote/ge;
	#debugMsg(1,"-> String quotes UN-masked for '$char' : $string\n");
	return $string;
}

sub checkValidIP { # v1 - Verify that the IP address is valid
	my ($ip, $ipv6, $line) = @_;
	$line = length $line ? " at line $line" : '';
	my $firstByte = 1;
	if ($ipv6) {
		if (($ipv6 = $ip) =~ /::/) {
			$ipv6 =~ s/::/my $r = ':'; $r .= '0:' for (1 .. (9 - scalar split(':', $ip))); $r/e;
		}
		quit(1, "Invalid IPv6 $ip$line") if $ipv6 =~ /::/;
		my @ipBytes = split(/:/, $ipv6);
		quit(1, "Invalid IPv6 $ip$line") if scalar @ipBytes != 8;
		foreach my $byte ( @ipBytes ) {
			quit(1, "Invalid IPv6 $ip$line") unless $byte =~ /^[\da-fA-F]{1,4}$/;
			if ($firstByte) {
				quit(1, "Invalid IPv6 $ip$line") if hex($byte) == 0;
				quit(1, "Invalid IPv6 $ip$line") if hex($byte) >= 65280;
				$firstByte = 0;
			}
			quit(1, "Invalid IPv6 $ip$line") if hex($byte) > 65535;
		}
		debugMsg(1, " - IPv6 address = ", \$ipv6, "\n");
	}
	else { # IPv4
		my @ipBytes = split(/\./, $ip);
		quit(1, "Invalid IP $ip$line") if scalar @ipBytes != 4;
		foreach my $byte ( @ipBytes ) {
			if ($firstByte) {
				quit(1, "Invalid IP $ip$line") if $byte == 0;
				quit(1, "Invalid IP $ip$line") if $byte >= 224;
				$firstByte = 0;
			}
			quit(1, "Invalid IP $ip$line") if $byte > 255;
		}
		debugMsg(1, " - IPv4 address = ", \$ip, "\n");
	}
	return 1; # Is valid
}

sub listHosts { # v2 - Produce a list of hostnames from command line
	my $inList = shift;
	my (@commaList, @outList, $basePart, $ipv6, $ipPort);
	# Split into comma separated list 1st
	@commaList = split(',', $inList);

	#Run through list
	foreach my $host (@commaList) {
		debugMsg(1, "processing input = ", \$host, "\n");
		if ($host =~ /^(\d+\.\d+\.\d+\.)\d+$/) { # 1.2.3.4
			($basePart, $ipv6, $ipPort) = ($1, undef, undef);
			checkValidIP($host);
			quit(1, "Duplicate IP $host") if grep($_ eq $host, @outList);
			push(@outList, $host) unless grep(/^$host$/, @outList);
		}
		elsif ($host =~ /^((?:\w*:)+)\w+$/) { # 2000::10
			($basePart, $ipv6, $ipPort) = ($1, 1, undef);
			checkValidIP($host, 1);
			quit(1, "Duplicate IP $host") if grep($_ eq $host, @outList);
			push(@outList, $host) unless grep(/^$host$/, @outList);
		}
		elsif ($host =~ /^(\[(\d+\.\d+\.\d+\.\d+)\]:)\d+$/) { # [1.2.3.4]:10
			($basePart, $ipv6, $ipPort) = ($1, undef, 1);
			checkValidIP($2);
			quit(1, "Duplicate IP:Port $host") if grep($_ eq $host, @outList);
			push(@outList, $host) unless grep(/^$host$/, @outList);
		}
		elsif ($host =~ /^(\[((?:\w*:)+\w+)\]:)\d+$/) { # [2000::10]:10
			($basePart, $ipv6, $ipPort) = ($1, undef, 1);
			checkValidIP($2, 1);
			quit(1, "Duplicate IP:Port $host") if grep($_ eq $host, @outList);
			push(@outList, $host) unless grep(/^$host$/, @outList);
		}
		elsif ($host =~ /^(\d+\.\d+\.\d+\.)(\d+)-(\d+)$/) { # 1.2.3.4-10
			($basePart, $ipv6, $ipPort) = ($1, undef, undef);
			my ($startVal, $endVal) = ($2, $3);
			quit(1, "Invalid IP starting range $startVal") if $startVal > 255;
			quit(1, "Invalid IP ending range $endVal") if $endVal > 255;
			quit(1, "Invalid IP range $startVal-$endVal") if $startVal >= $endVal;
			for my $i ($startVal .. $endVal) {
				my $ip = $basePart.$i;
				checkValidIP($ip);
				quit(1, "Duplicate IP $ip") if grep($_ eq $ip, @outList);
				push(@outList, $ip) unless grep(/^$ip$/, @outList);
			}
		}
		elsif ($host =~ /^((?:\w*:)+)([1-9]\d*)-([1-9]\d*)$/) { # 2000:10::1-10 (decimal range 1-10)
			($basePart, $ipv6, $ipPort) = ($1, 1, undef);
			my ($startVal, $endVal) = ($2, $3);
			quit(1, "Invalid IP starting range $startVal") if $startVal > 9999;
			quit(1, "Invalid IP ending range $endVal") if $endVal > 9999;
			quit(1, "Invalid IP range $startVal-$endVal") if $startVal >= $endVal;
			for my $i ($startVal .. $endVal) {
				my $ip = $basePart.$i;
				checkValidIP($ip, 1);
				quit(1, "Duplicate IP $ip") if grep($_ eq $ip, @outList);
				push(@outList, $ip) unless grep(/^$ip$/, @outList);
			}
		}
		elsif ($host =~ /^((?:\w*:)+)(\w+)-(\w+)$/) { # 2000:20::01-10 (hex range 1,2,3,4,5,6,7,8,9,a,b,c,d,e,f,10)
			($basePart, $ipv6, $ipPort) = ($1, 1, undef);
			my ($startVal, $endVal) = ($2, $3);
			$startVal =~ s/^0+//;	# Remove leading zeros
			$endVal =~ s/^0+//;	# ditto
			quit(1, "Invalid IP starting range $startVal") unless $startVal =~ /^[\da-fA-F]{1,4}$/;
			quit(1, "Invalid IP ending range $endVal") unless $endVal =~ /^[\da-fA-F]{1,4}$/;
			quit(1, "Invalid IP range $startVal-$endVal") if hex($startVal) >= hex($endVal);
			for my $i (hex($startVal) .. hex($endVal)) {
				my $ip = sprintf("%s%x", $basePart, $i);
				checkValidIP($ip, $ipv6);
				quit(1, "Duplicate IP $ip") if grep($_ eq $ip, @outList);
				push(@outList, $ip) unless grep(/^$ip$/, @outList);
			}
		}
		elsif ($host =~ /^(\[(\d+\.\d+\.\d+\.\d+)\]:)(\d+)-(\d+)$/) { # [1.2.3.4]:10-20
			($basePart, $ipv6, $ipPort) = ($1, undef, 1);
			my ($startVal, $endVal) = ($3, $4);
			checkValidIP($2);
			quit(1, "Invalid TCP port starting range $startVal") if $startVal > 65535;
			quit(1, "Invalid TCP port ending range $endVal") if $endVal > 65535;
			quit(1, "Invalid TCP port range $startVal-$endVal") if $startVal >= $endVal;
			for my $i ($startVal .. $endVal) {
				my $ip = $basePart.$i;
				quit(1, "Duplicate IP:Port $ip") if grep($_ eq $ip, @outList);
				push(@outList, $ip) unless grep(/^$ip$/, @outList);
			}
		}
		elsif ($host =~ /^(\[((?:\w*:)+\w+)\]:)(\d+)-(\d+)$/) { # [2000::10]:10-20
			($basePart, $ipv6, $ipPort) = ($1, undef, 1);
			my ($startVal, $endVal) = ($3, $4);
			checkValidIP($2, 1);
			quit(1, "Invalid TCP port starting range $startVal") if $startVal > 65535;
			quit(1, "Invalid TCP port ending range $endVal") if $endVal > 65535;
			quit(1, "Invalid TCP port range $startVal-$endVal") if $startVal >= $endVal;
			for my $i ($startVal .. $endVal) {
				my $ip = $basePart.$i;
				quit(1, "Duplicate IP:Port $ip") if grep($_ eq $ip, @outList);
				push(@outList, $ip) unless grep(/^$ip$/, @outList);
			}
		}
		elsif ($host =~ /^([1-9]\d*)-([1-9]\d*)$/) { # 1-10 (decimal range 1-10)
			my ($startVal, $endVal) = ($1, $2);
			quit(1, "No base IP for range $startVal-$endVal") unless defined $basePart;
			if ($ipPort) {
				quit(1, "Invalid TCP port starting range $startVal") if $startVal > 65535;
				quit(1, "Invalid TCP port ending range $endVal") if $endVal > 65535;
				quit(1, "Invalid TCP port range $startVal-$endVal") if $startVal >= $endVal;
			}
			else {
				quit(1, "Invalid IP starting range $startVal") if $startVal > ($ipv6 ? 9999 : 255);
				quit(1, "Invalid IP ending range $endVal") if $endVal > ($ipv6 ? 9999 : 255);
				quit(1, "Invalid IP range $startVal-$endVal") if $startVal >= $endVal;
			}
			for my $i ($startVal .. $endVal) {
				my $ip = $basePart.$i;
				checkValidIP($ip, $ipv6);
				my $suffix = $ipPort ? ':Port' : '';
				quit(1, "Duplicate IP$suffix $ip") if grep($_ eq $ip, @outList);
				push(@outList, $ip) unless grep(/^$ip$/, @outList);
			}
		}
		elsif ($host =~ /^([\da-fA-F]{1,4})-([\da-fA-F]{1,4})$/ && $ipv6) { # 01-10 (hex range 1,2,3,4,5,6,7,8,9,a,b,c,d,e,f,10)
			my ($startVal, $endVal) = ($1, $2);
			quit(1, "Invalid IP range $startVal-$endVal") if hex($startVal) >= hex($endVal);
			for my $i (hex($startVal) .. hex($endVal)) {
				my $ip = sprintf("%s%x", $basePart, $i);
				checkValidIP($ip, $ipv6);
				quit(1, "Duplicate IP $ip") if grep($_ eq $ip, @outList);
				push(@outList, $ip) unless grep(/^$ip$/, @outList);
			}
		}
		elsif ($host =~ /^(\d+)$/) { # 10
			quit(1, "No base IP for ip last byte $1") unless defined $basePart;
			my $ip = $basePart.$1;
			checkValidIP($ip, $ipv6) unless $ipPort;
			my $suffix = $ipPort ? ':Port' : '';
			quit(1, "Duplicate IP$suffix $ip") if grep($_ eq $ip, @outList);
			push(@outList, $ip) unless grep(/^$ip$/, @outList);
		}
		elsif ($host =~ /^([\da-fA-F]{1,4})$/ && $ipv6) { # 0a
			my $ip = $basePart.$1;
			checkValidIP($ip, 1);
			quit(1, "Duplicate IP $ip") if grep($_ eq $ip, @outList);
			push(@outList, $ip) unless grep(/^$ip$/, @outList);
		}
		else { # Assume a hostname
			debugMsg(1, " - treating as hostname: ", \$host, "\n");
			$basePart = $ipv6 = undef;
			quit(1, "Duplicate hostname $host") if grep($_ eq $host, @outList);
			push(@outList, $host) unless grep(/^$host$/, @outList);
		}
	}
	return \@outList;
}

sub loadHosts { # Read a list of hostnames from file
	my $infile = shift;
	my (@outList, %hashNames, $lineNum);

	open(FILE, $infile) or quit(1, "Cannot open input hosts file: $!");
	while (<FILE>) {
		$lineNum++;
		chomp;				# Remove trailing newline char
		next if /^#/;			# Skip comment lines
		next if /^\s*$/;		# Skip blank lines
		next if /^(?:\@echo|acligui|exit)/;		# Skip batch launcher lines
		if (/^\s*(\S+)\s*(?:(\S+)\s*)?(?:\#|$)/) {	# Valid entry
			my ($host, $hostname) = ($1, $2);
			checkValidIP($host, undef, $lineNum) if $host =~ /^\d+\.\d+\.\d+\.\d+$/;
			checkValidIP($1, undef, $lineNum) if $host =~ /^\[(\d+\.\d+\.\d+\.\d+)\]:\d+$/;
			checkValidIP($host, 1, $lineNum) if $host =~ /^(?:\w*:)+\w+$/;
			checkValidIP($1, 1, $lineNum) if $host =~ /^\[(?:\w*:)+\w+\]:\d+$/;
			push(@outList, $host) unless grep(/^$host$/, @outList);
			$hashNames{$host} = $hostname;
			next;
		}
		quit(1, "Hosts file \"$infile\" invalid syntax at line $lineNum\n");
	}
	return (\@outList, \%hashNames);
}

sub splitHostPort { # Given an IP/hostname in format [<ip/hostname>]:<port> will split and return the host and port parts
	my $inputHost = shift;
	return ($1, $2) if $inputHost =~ /\[([^\]]+)\]:(\d+)/;
	return ($inputHost, undef); # Otherwise
}

sub listCliScript { # Produce a list of commands (script) from command line
	my $inList = shift;
	my (@semicolonList, @outList);

	# Split into semicolon separated list
	@semicolonList = split(';', $inList);
	foreach (@semicolonList) {
		s/^\s+//;    # Remove indentation, if any
		s/\s+$//;    # Remove trailing spaces, if any
		next if /^#/;			# Skip comment lines
		next if /^\s*$/;		# Skip blank lines
		push( @outList, $_);
	}
	return \@outList;
}

sub loadCliScript { # Load in the script file
	my $infile = shift;
	my @outList;

	open(FILE, $infile) or quit(1, "Cannot open input script file: $!");
	while (<FILE>) {
		chomp;				# Remove trailing newline char
		s/\x0d+$//g; # Remove trailing CRs (had this reading text files created on Solaris)
		s/^\s+//;    # Remove indentation, if any
		s/\s+$//;    # Remove trailing spaces, if any
		next if /^#/;			# Skip comment lines
		next if /^\s*$/;		# Skip blank lines
		push( @outList, $_);
	}
	return \@outList;
}

sub readSpreadsheet { # Reads in spreadsheet and populates supplied hash reference
	my ($filename, $sheetName, $ipColumnName) = @_;
	require Spreadsheet::Read; # Require the module here, as it is quite slow to load into memory..
	my %sheetTable = ();
	my $book = Spreadsheet::Read::ReadData($filename, strip => 3);
	quit(1, "Cannot open spreadsheet file: $filename") unless defined $book;
	my $sheetNumber = 1; # Assume 1st sheet
	if (defined $sheetName) {
		quit(1, "Spreadsheet '$filename' does not have a sheet name: $sheetName") unless exists $book->[0]->{sheet}->{$sheetName};
		$sheetNumber = $book->[0]->{sheet}->{$sheetName};
	}
	my $minRow = $book->[$sheetNumber]->{minrow} || 1;
	my @rows = Spreadsheet::Read::rows($book->[$sheetNumber]);
	map {s/\x{feff}//g} @{$rows[$minRow-1]}; # For a CSV file created from Microsoft Excel, we need to get rid of this character
	map {s/\s/_/g} @{$rows[$minRow-1]}; # Convert spaces to underscore
	my $index;
	my $columns = $#{$rows[$minRow-1]};
	for my $i (0 .. $#{$rows[$minRow-1]}) {
		next unless lc($rows[$minRow-1][$i]) eq lc($ipColumnName);
		$index = $i; # Holds the column index of the designated switch IP column
	}
	quit(1, "Did not find column labeled '$ipColumnName' in spreadsheet '$filename'") unless defined $index;
	foreach my $i ($minRow .. $#rows) {
		next unless length $rows[$i][$index]; # Skip rows with no switch ip/hostname
		foreach my $j (0 .. $columns) {
			my $value = $rows[$i][$j];
			$value = '"'.$value.'"' if $value =~ /\s/ && $value !~ /^\"[^\"]+\"$/; # Quote value if it contains spaces
			$sheetTable{$rows[$i][$index]}{lc $rows[$minRow-1][$j]} = $value;
		}
	}
	return (\%sheetTable, $rows[$minRow-1]);
}

sub validateUsedVariables { # Validate that there are no $variables in CLI script which cannot be dereferenced
	my ($acmdScript, $hostNames, $spreadsheet, $labelRow) = @_;
	my ($doubleDollar, %varHash);
	foreach my $command (@$acmdScript) {
		$doubleDollar = 1 if $command =~ /\$\$$VarDelim/;
		my @matches = ($command =~ /\$($VarNormal)$VarDelim/g);
		for my $match (@matches) {
			$varHash{lc $match} = 1; # Hash avoids duplicates
		}
	}
	if ($doubleDollar && !scalar values %$hostNames) {
		quit(1, "Variable \$\$ present in CLI script but no hostfile switch names provided");
	}
	if (%varHash) {
		quit(1, "Variables present in CLI script but no spreadsheet loaded") unless defined $spreadsheet;
		for my $label (@$labelRow) {
			delete $varHash{lc $label} if exists $varHash{lc $label};
		}
		if (%varHash) { # If any keys left...
			quit(1, "Variables used in the CLI script but not found in the spreadsheet: " . join(',', keys %varHash) . "\n");
		}
	}
}

sub hostName { # Returns the host's name if known, else its IP address
	my ($host, $namesHashRef) = @_;
	return $namesHashRef->{$host} if defined $namesHashRef->{$host};
	return $host;
}

sub listFailedHosts { # Terse way of listing which hosts generated an error (we don't want a list of 200+ IPs!!)
	my ($hostListRef, $namesHashRef) = @_;

	if (scalar @{$hostListRef} == 1) {
		statusMsg("\nHost ", hostName($hostListRef->[0], $namesHashRef), "\n");
	}
	elsif (scalar @{$hostListRef} == 2) {
		statusMsg("\nHosts ", hostName($hostListRef->[0], $namesHashRef), " and ", hostName($hostListRef->[1], $namesHashRef), "\n");
	}
	elsif (scalar @{$hostListRef} == 3) {
		statusMsg("\nHosts: ", join(', ', map(hostName($_, $namesHashRef), @{$hostListRef})), "\n");
	}
	else { # > 2
		statusMsg("\nHost ", hostName($hostListRef->[0], $namesHashRef), " and ", $#$hostListRef, " others\n");
	}
}

sub formatCmdErrMsg { # Re-format the error message to single line by removing the prompt and pointer
	my $errmsg = shift;
	$errmsg =~ s/^.+\n//;		# Remove 1st line
	$errmsg =~ s/^\s+\^\n//;	# Remove line with pointer
	$errmsg =~ s/ at '\^' marker//;	# Remove marker text
	return $errmsg;
}

sub replaceVariables { # Replaces variables in the command lines
	my ($host, $cmdRef, $familyType, $switchName, $vars) = @_;

	# Dereference $variables
	$$cmdRef =~ s/\$($VarNormal)$VarDelim/defined $vars->{lc $1} ? $vars->{lc $1} : "\$$1"/geo;
	# Dereference $$ variable (name from -f hosts file)
	$$cmdRef =~ s/\$\$$VarDelim/defined $switchName ? $switchName : '$$'/geo;
	if ($$cmdRef =~ /\$\$$VarDelim/ || $$cmdRef =~ /\$($VarNormal)$VarDelim/) {
		$$cmdRef = $DeviceComment{$familyType} . $$cmdRef; # If variable was not resolved, comment out line
		debugMsg(1,"$host : unable to resolve variable; commenting command '", $cmdRef, "'\n");
	}
}

sub pollComplete { # Poll all objects to completion
	my $db = shift;
	my $cliHashRef = $db->[0];
	my $namesHashRef = $db->[1];
	my $failedListRef = $db->[2];
	my $errorHashRef = $db->[3];
	
	my ($running, $completed, $lastFailed, @failedList, %failHash);
	my $lastCompleted = 0;

	do {
		($running, $completed, undef, undef, $lastFailed) = poll(
			Object_list	=>	$cliHashRef,
			Object_complete	=>	'next',
			Object_error	=>	'ignore',
			Poll_timer	=>	$PollTimer,
			Poll_code	=>	\&printDot,
		);
		statusMsg("<$completed>") if $completed > $lastCompleted;
		$lastCompleted = $completed;
		push(@failedList, @$lastFailed) if @$lastFailed;
	} while $running;
	statusMsg(" done!\n");

	if (@failedList) {
		push(@$failedListRef, @failedList);
		foreach my $host (@failedList) {
			debugMsg(1,"$host : failed in poll, with message:");
			my $errMsg = $cliHashRef->{$host}->errmsg;
			debugMsg(1," ", \$errMsg, "\n");
			push(@{$failHash{$errMsg}}, $host);
			$errorHashRef->{$host} = $errMsg;
			$cliHashRef->{$host}->disconnect;	# Disconnect from failed host
			delete $cliHashRef->{$host};		# and remove it from working hash
		}
		debugMsg(1,"   Succeded with hosts : ", \join(', ', keys %$cliHashRef), "\n");
		foreach my $error (keys %failHash) {
			listFailedHosts($failHash{$error}, $namesHashRef);
			statusMsg("=> Failed with error: ", $error, "\n");
		}
		statusMsg("\n");
	}
	return scalar keys %$cliHashRef; # True if some succeeded
}

sub bulkDo { # Repeat for all hosts
	my ($db, $method, $argsRef) = @_;
	my $cliHashRef = $db->[0];
	my $namesHashRef = $db->[1];
	my $failedListRef = $db->[2];
	my $errorHashRef = $db->[3];
	my $outHandle = $db->[4];
	my $hostHandle = $db->[5];
	my $hostFilename = $db->[6];
	my $fileOverWrite = $db->[7];
	my $outFileSuffix = $db->[8];
	my $spreadsheet = $db->[9];
	my %failHash;

	foreach my $host (keys %$cliHashRef) { # Call $method for every object
		my $codeRef = $cliHashRef->{$host}->can($method);
		my @argsCopy = @$argsRef if defined $argsRef;
		if ($method =~ /^cmd/) {
			my $familyType = $cliHashRef->{$host}->attribute('family_type');
			replaceVariables($host, \$argsCopy[0], $familyType, $namesHashRef->{$host}, $spreadsheet->{$host});
			if (defined $ChangePromptCmds{$familyType} && $argsCopy[0] =~ /$ChangePromptCmds{$familyType}/i) {
				debugMsg(1,"$host : cmd method with command '", \$argsCopy[0], "' to change device prompt; enabling Reset_prompt\n");
				$codeRef->($cliHashRef->{$host}, Command => $argsCopy[0], Reset_prompt => 1);
				next;
			}
		}
		$codeRef->($cliHashRef->{$host}, @argsCopy);
	}
	debugMsg(1,"-> BulkDo - ", \$method, " - polling\n");
	pollComplete($db);

	if ($method =~ /^cmd/) { # Check for output and whether command was accepted
		print $outHandle $ScriptName, ": Executed: ", $argsRef->[0], "\n" if defined $outHandle;
		foreach my $host (keys %$cliHashRef) {
			if ($cliHashRef->{$host}->last_cmd_success) {
				if (defined $outHandle || exists $hostHandle->{$host}) { # If we have an output file or need to capture variable
					my $outRef = ($cliHashRef->{$host}->cmd_poll)[1];
					if (length $$outRef) { # only if output generated
						if (exists $hostHandle->{$host} && !defined $hostHandle->{$host}) { # We need to open the file for 1st write..
							(my $filehost = $host) =~ s/:/_/g; # Produce a suitable filename for IPv6 addresses
							$hostFilename->{$host} = defined $outFileSuffix ? $filehost . $outFileSuffix : $filehost;
							open($hostHandle->{$host}, $fileOverWrite ? '>' : '>>', $hostFilename->{$host}) or do {
								delete $hostHandle->{$host};	# Make sure we don't try this again..
								print $outHandle $ScriptName, "Unable to open host output file : ", $hostFilename->{$host}, "\n";
							};
						}
						if (defined $hostHandle->{$host}) {
							print {$hostHandle->{$host}} $$outRef;
							print $outHandle $ScriptName, ": Output from ", hostName($host, $namesHashRef), " saved to file: ", $hostFilename->{$host}, "\n" if defined $outHandle;
						}
						else { # defined $outHandle
							print $outHandle $ScriptName, ": Output from ", hostName($host, $namesHashRef), ":\n";
							print $outHandle $$outRef;
						}
					}
				}
			}
			elsif (defined $cliHashRef->{$host}->last_cmd_success) { # Command generated an error on host (undef = generic host)
				debugMsg(1,"$host : failed in bulkDo, with message:");
				my $errMsg = formatCmdErrMsg($cliHashRef->{$host}->last_cmd_errmsg);
				debugMsg(1," ", \$errMsg, "\n");
				push(@{$failHash{$errMsg}}, $host);
				$errorHashRef->{$host} = $errMsg;
				push(@$failedListRef, $host);
				$cliHashRef->{$host}->disconnect;	# Disconnect from failed host
				delete $cliHashRef->{$host};		# and remove it from working hash
			}
		}
		if (%failHash) {
			foreach my $error (keys %failHash) {
				listFailedHosts($failHash{$error}, $namesHashRef);
				statusMsg("=> Command sent: ", $argsRef->[0], "\n");
				statusMsg("=> Generated error: ", $error, "\n");
			}
			statusMsg("\n");
		}
	}
	return scalar keys %$cliHashRef; # True if some succeeded
}

sub retryHostFile { # Returns file name to use to write list of hosts which failed
	my $inputFile = shift;

	if (defined $inputFile) {
		return $inputFile if $inputFile =~ /\.retry$/;
		return $inputFile . '.retry';
	}
	$ScriptName =~ /^([^\.]+)/;
	return $1.'.retry';
}


#############################
# MAIN                      #
#############################

MAIN:{
	my ($acmdProtocol, $acmdHosts, $hostNames, $acmdScript, $acmdOutFile, $outHandle, $retryFile, $outFileSuffix, $spreadsheet, $labelRow);
	my ($db, $hostStruct, %cli, @failed, %error, @aborted, $batchCount, $hostCount, $staggerN, $abortOnFail, $abortFlag, %hostHandle, %hostFilename);
	my ($username, $password, $timeout) = ($Username, $Password, $Timeout);

	getopts('ad:f:g:il:n:op:s:t:x:y');

	$Debug = $opt_d if $opt_d;
	if ($Debug) {
		open($DebugLogFH, '>', $DebugLog) or quit(1, "Unable to open debug file $DebugLog");
	}
	printSyntax if !@ARGV || $ARGV[0] eq '?';

	if ($opt_g) { # Process staggered argument
		printSyntax unless $opt_g =~ /^\d+$/ && $opt_g > 0;
		$staggerN = $opt_g;
		$abortOnFail = $opt_a;
	}
	if ($opt_t) { # Set timeout value
		printSyntax unless $opt_t =~ /^\d+$/;
		$timeout = $opt_t == 0 ? undef : $opt_t;
	}

	if ($opt_f) { # A hosts file
		($acmdHosts, $hostNames) = loadHosts($opt_f);
	}
	elsif ($opt_x) { # A spreadsheet file
		printSyntax unless $opt_x =~ /^([^:!\s]+)(?::([^!\s]+))?(?:!(.+))$/;
		my ($filename, $sheetname, $deviceLabel) = ($1, $2, $3);
		($spreadsheet, $labelRow) = readSpreadsheet($filename, $sheetname, $deviceLabel);
		$acmdHosts = [keys %$spreadsheet];
	}
	else { # or hosts list
		printSyntax unless @ARGV;
		$acmdHosts = listHosts(shift @ARGV);
	}

	printSyntax unless @ARGV;
	$acmdProtocol = uc shift @ARGV;
	printSyntax unless $acmdProtocol eq 'TELNET' || $acmdProtocol eq 'SSH';

	if ($opt_s) { # A script file
		$acmdScript = loadCliScript($opt_s);
	}
	else { # or a command list
		printSyntax unless @ARGV;
		$acmdScript = listCliScript(shift @ARGV);
	}

	# Check if variables used in CLI script and if we have them
	validateUsedVariables($acmdScript, $hostNames, $spreadsheet, $labelRow);

	$acmdOutFile = shift @ARGV if @ARGV;
	if ($opt_i && defined $acmdOutFile) { # Create a suffix for per-host files
		if ($acmdOutFile =~ /^\./) { # If only a suffix provided...
			$outFileSuffix = $acmdOutFile;	# ..we only do per-host files
			$acmdOutFile = undef;		# ..and no global file
		}
		else { # We do both
			$outFileSuffix = "_$acmdOutFile";
		}
	}
	printSyntax if @ARGV;	# Accept no more arguments
	$retryFile = retryHostFile($opt_f);

	# Dispatch the hosts into the host structure (which may be staggered if -g argument was used)
	$batchCount = $hostCount = 0;
	foreach my $host (@$acmdHosts) {
		push(@{$hostStruct->[$batchCount]}, $host);
		if ($staggerN && ++$hostCount == $staggerN) {
			$batchCount++;
			$hostCount = 0;
		}
	}

	unless ($opt_y) { # Provide summary of job and let user confirm before proceeding
		statusMsg("="x80, "\n");
		statusMsg("Identified ", scalar @$acmdHosts, " hosts to run job against\n");
		if ($opt_s) {
			statusMsg("Job consists of pushing CLI script contained in file: ", $opt_s, "\n");
		}
		else {
			statusMsg("Job consists of pushing CLI commands provided in command line (", scalar @$acmdScript, " commands)\n");
		}
		if ($#$hostStruct) { # Staggered mode
			statusMsg("Performing job over ", scalar @$hostStruct, " iterations\n");
			statusMsg("-> where each iteration will connect to at most ", $staggerN, " hosts at the same time\n");
			if ($abortOnFail) {
				statusMsg("-> if the script fails against at least 1 host, further iterations will be aborted\n");
			}
			else {
				statusMsg("-> if the script fails against all hosts in 1st iteration, then further iterations will be aborted\n");
				statusMsg("-> if the script fails against any hosts in subsequent iterations, all further iterations will be performed\n");
			}
		}
		else { # No-staggered mode
			statusMsg("Performing job over single iteration\n");
			statusMsg("-> job will be performed by connecting to all ", scalar @$acmdHosts, " hosts at the same time\n");
		}
		if ($opt_l) { # Credentials set
			if ($opt_p) {
				statusMsg($acmdProtocol, " will be used with '", $opt_l, "' username and password provided\n");
			}
			else {
				statusMsg($acmdProtocol, " will be used with '", $opt_l, "' username (you will be prompted for password at job start)\n");
			}
		}
		else { # Default credentials
			if ($opt_p) {
				statusMsg($acmdProtocol, " will be used with default username 'rwa' and password provided\n");
			}
			else {
				statusMsg($acmdProtocol, " will be used with default credentials: rwa/rwa\n");
			}
		}
		if (defined $acmdOutFile || $opt_i) { # With output file
			if ($opt_i) {
				if (defined $outFileSuffix) {
					statusMsg("Any output received from hosts will be collected in per host file: <host-or-IP>", $outFileSuffix, "\n");
					statusMsg("A log of output received from hosts will also be in file: ", $acmdOutFile, "\n") if defined $acmdOutFile;
				}
				else {
					statusMsg("Any output received from hosts will be collected in per host file: <host-or-IP>\n");
				}
				statusMsg("-> if these files already exist they will be overwritten!\n") if $opt_o; # Over-write file
				statusMsg("-> if these files already exist they will be appended to\n") unless $opt_o; # Append file
			}
			else {
				statusMsg("Any output received from hosts will be collected in file: ", $acmdOutFile, "\n");
				if (-e $acmdOutFile) { # Output file exists
					statusMsg("-> output file '$acmdOutFile' already exists and will be overwritten!\n") if $opt_o; # Over-write file
					statusMsg("-> file '$acmdOutFile' already exists and output will be appended to it\n") unless $opt_o; # Append file
				}
			}
		}
		else { # No output file
			statusMsg("Any output received from hosts will be discarded (config only script)\n");
		}
		statusMsg("If the script succeeds on some hosts but fails on others\n");
		if ($#$hostStruct && $abortOnFail) { # Staggered mode with abort -a arg
			statusMsg("-> list of hosts which failed + all hosts from aborted iterations will be listed in file: $retryFile\n");
		}
		else {
			statusMsg("-> list of hosts which failed will be listed in file: $retryFile\n");
		}
		statusMsg("-> file '$retryFile' already exists and will be overwritten!\n") if -e $retryFile;
		statusMsg("="x80, "\n");
		exit 0 unless promptOk;
	}

	if ($opt_l) { # Set credentials if different from default
		$username = $opt_l;
		$password = promptHide("password for $username") unless $opt_p;
	}
	if ($opt_p) { # Set password from command line
		$password = $opt_p;
	}

	if (defined $acmdOutFile) { # Try and open the output file
		open($outHandle, $opt_o ? '>' : '>>', $acmdOutFile) or quit(1, "Unable to append to output file $acmdOutFile");
		printf $outHandle "=~=~=~=~=~=~=~=~=~=~= %s =~=~=~=~=~=~=~=~=~=~=\n", scalar localtime;
	}

	# Create db struct
	$db = [
		\%cli,		# 0
		$hostNames,	# 1
		\@failed,	# 2
		\%error,	# 3
		$outHandle,	# 4
		\%hostHandle,	# 5
		\%hostFilename,	# 6
		$opt_o,		# 7
		$outFileSuffix,	# 8
		$spreadsheet,	# 9
	];

	$batchCount = $hostCount = 0; # Same vars reused
	foreach my $batch (0 .. $#$hostStruct) {
		if ($abortFlag) { # Abort subsequent iterations
			push(@aborted, @{$hostStruct->[$batch]});
			next;
		}
		$hostCount = scalar @{$hostStruct->[$batch]};
		$batchCount += $hostCount;
		statusMsg("Initiating batch ", $batch + 1, " for ", $hostCount, " host", $hostCount > 1 ? 's' : '', " (cumulative ", $batchCount, ")\n") if $#$hostStruct;
		my $pad = $#$hostStruct ? '  ' : '';
		%cli = ();	# Empty the CLI object hash

		# Create and Connect all the object instances
		statusMsg($pad, "Connecting to ", scalar @{$hostStruct->[$batch]}, " hosts ");
		foreach my $hostkey (@{$hostStruct->[$batch]}) {
			my ($host, $port) = splitHostPort($hostkey);
			$cli{$hostkey} = new Control::CLI::Extreme(
				Use			=> $acmdProtocol,	# TELNET/SSH
				Blocking		=> 0,			# Use non-blocking mode
				Return_reference	=> 1,			# Faster
				Timeout			=> $timeout,		# Timeout for responses
				Connection_timeout	=> $timeout,		# Timeout for connection
				Errmsg_format		=> $Debug ? 'verbose' : 'terse',
				Errmode			=> 'return',		# Always return
			);
			if ($Debug & 2) {
				(my $filehost = $hostkey) =~ s/:/_/g; # Produce a suitable filename for IPv6 addresses or [<ip>]:<port>
				(my $hostDebugLog = $HostDebugLog) =~ s/<HOST>/$filehost/;
				$cli{$hostkey}->debug_file($hostDebugLog);
				$cli{$hostkey}->debug($ControlCLIDebugLevel);
			}
			$cli{$hostkey}->connect(
				Host		=>	$host,
				Port		=>	$port,
				Username	=>	$username,
				Password	=>	$password,
				Atomic_connect	=> ($acmdProtocol eq 'SSH' ? 1 : 0),
			);
			$hostHandle{$hostkey} = undef if $opt_i; 	# Create the key, this will produce the output logging
		}
		debugMsg(1,"-> Connect polling\n");
		pollComplete($db) or do {
			quit(1, "Failed to connect to all 1st iteration hosts") unless $batch; # If all failed at 1st iteration, then bomb out
			$abortFlag = 1 if $abortOnFail; # If not 1st iteration, and -a, then abort subsequent iterations
			next; # # If not 1st iteration and no abort mode, then keep going
		};
		
		statusMsg($pad, "Entering PrivExec on ", scalar keys %cli, " hosts ");
		bulkDo($db, 'enable') or do {
			quit(1, "Failed to enter PrivExec mode on all 1st iteration hosts") unless $batch; # If all failed at 1st iteration, then bomb out
			$abortFlag = 1 if $abortOnFail; # If not 1st iteration, and -a, then abort subsequent iterations
			next; # # If not 1st iteration and no abort mode, then keep going
		};
		if ($#$hostStruct) {
			my $hostCount = scalar keys %cli;
			print $outHandle $ScriptName, ": Batch ", $batch + 1, " connected to ", $hostCount, " host", $hostCount > 1 ? 's' : '',
			      ": ", join(', ', map(hostName($_, $hostNames), keys %cli)), "\n";
		}

		# Execute the script commands
		statusMsg($pad, "Executing CLI script on ", scalar keys %cli, " hosts\n");
		my $enableSeen;
		foreach my $command (@$acmdScript) {
			$command =~ /^enable$/ && !$enableSeen && do { # We already entered PrivExec mode
				$enableSeen = 1;
				next;
			};
			statusMsg($pad, "- $command   ");
			$command = quoteMask($command, '/');
			my @feedInputs;
			while ($command =~ s/(?:(.*)\/\/)\s*(.*?)\s*$/$1/) { # This regex was tricky; $command =~ s/\s*\/\/(.*?)$// did not work as you always get a greedy match from the right hand side..
				my $feed = $2;
				$feed = '' unless defined $feed;
				unshift(@feedInputs, $feed);
				debugMsg(1,"-> Feed Input added :>", \$feed, "<\n");
			}
			$command = quoteUnmask($command, '/');
			if (@feedInputs) { # Send command with feed arguments
				bulkDo($db, 'cmd_prompted', [$command, @feedInputs]) or do {
					quit(1, "On all 1st iteration hosts failed to send command: $command") unless $batch; # If all failed at 1st iteration, then bomb out
					$abortFlag = 1 if $abortOnFail; # If not 1st iteration, and -a, then abort subsequent iterations
					next; # # If not 1st iteration and no abort mode, then keep going
				};

			}
			else { # Send normal command
				bulkDo($db, 'cmd', [$command]) or do {
					quit(1, "On all 1st iteration hosts failed to send command: $command") unless $batch; # If all failed at 1st iteration, then bomb out
					$abortFlag = 1 if $abortOnFail; # If not 1st iteration, and -a, then abort subsequent iterations
					next; # # If not 1st iteration and no abort mode, then keep going
				};

			}
		}
	
		statusMsg($pad, "Disconnecting from ", scalar keys %cli, " hosts\n");
		foreach my $host (keys %cli) {
			$cli{$host}->disconnect;
		}
		statusMsg("\n") if $#$hostStruct;

		# If only some hosts in the iteration failed, and abort -a flag is set, then abort any further iterations
		$abortFlag = 1 if @failed && $abortOnFail;
	}

	if (defined $acmdOutFile) { # Close the output file if it was provided
		close $outHandle;
		statusMsg("Output saved to file ", $acmdOutFile, "\n");
	}
	if ($opt_i) { # Close the per-host output files
		foreach my $host (keys %hostHandle) {
			close $hostHandle{$host} if defined $hostHandle{$host};
		}
		statusMsg("Output saved to per-host files <host-or-IP>", $outFileSuffix, "\n") if defined $outFileSuffix;
		statusMsg("Output saved to per-host files <host-or-IP>\n") unless defined $outFileSuffix;
	}

	if (@failed) { # Process failed host
		open(RETRY, '>', $retryFile) or quit(1, "Unable to write failed hosts list to file $retryFile");
		foreach my $host (@failed, @aborted) {
			print RETRY $host;
			print RETRY "	", $hostNames->{$host} if defined $hostNames->{$host};
			print RETRY "	# ", $error{$host} if defined $error{$host};
			print RETRY "\n";
		}
		close RETRY;
		statusMsg("Script failed on ", scalar @failed, " host", $#failed ? 's' : '');
		statusMsg(" and was aborted on ", scalar @aborted, " host", $#aborted ? 's' : '', "\n") if @aborted;
		statusMsg("\n") unless @aborted;
		statusMsg("The above hosts for which the script was not executed are stored in file: ", $retryFile, "\n");
	}
}
