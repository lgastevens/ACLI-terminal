#!/usr/bin/perl

my $Version = "1.12";

# Written by Ludovico Stevens (lstevens@extremenetworks.com)
# FTP, SFTP client for Extreme VOSS devices

# 0.01	- Initial
# 0.02	- Fixed glob problem
# 0.03	- Fixed other glob problem
# 0.04	- Added ability to set (-p) path and the ability to provide list of files on command line 
# 0.05	- Added ability to set (-l) username
# 0.06	- Added support for fetching PCAP00
# 0.07	- Fixed problem with fetching PCAP00
# 0.08	- Corrected formatting of error messages
# 0.09	- Improved error detection
# 0.10	- Added ability to supply a hostfile (-f)
# 0.11	- Enhanced progress activity dots
# 1.00	- Added SFTP support
# 1.01	- Default timeout increasd to 20 seconds
# 1.02	- Supplied (-f) hostfile can now have IP + name on every line (same format as IP hosts file)
# 1.03	- Fixed problem where -p path was not working with SFTP
#	- All threads now disconnect gracefully when any other thread fails
#	- Reduced thread stack_size
#	- Altered thread return value in order to detect thread which fail but get joined normally
# 1.04	- Can now read hosts out of batch file
# 1.05	- Minor changes to make it run on MAC OS
# 1.06	- Updated listHosts not to accept duplicate IPs and to accept IPv6 addresses
# 1.07	- Issues with threads on MAC OS; no longer sets stack_size on MAC OS
# 1.08	- Corrected input validation checks; now syntax is shown if no file-list/glob provided
# 1.09	- Absolute filepaths are now accepted but only for put mode
#	- The -f hostfile now accepts IPs/Hostnames + TCP port number in format [<ip/hostname>]:<port>
# 1.10	- Password can now be provided on the command line together with username on -u switch
# 1.11	- Added support and new syntax for reading in IPs from spreadsheet (as in acmd)
# 1.12	- Changed loadHosts to work with batch files using start instead of acligui.vbs


#############################
# STANDARD MODULES          #
#############################

use strict;
use warnings;
use 5.010; # required for sub state declarations
no warnings 'threads';
use threads;
use threads::shared;
use Getopt::Std;
use File::Basename;
use File::DosGlob 'glob';
use Net::FTP;
use Net::SSH2;
use Term::ReadKey;
use IO::Callback;
use Fcntl qw(O_WRONLY O_RDONLY O_CREAT O_TRUNC);
#use Spreadsheet::Read; # This is "required" only in readSpreadsheet()

# http://www.perlmonks.org/?node_id=874944 / On MSWin32 minimum becomes 8192, but not setting would use 16Meg
# However we stay with default stack_size on MAC OS as otherwise we get all sorts of errors 
threads->set_stack_size(8192) if $^O eq "MSWin32";


#############################
# GLOBAL CONSTANT VARIABLES #
#############################

############################
# GLOBAL DEFAULT VARIABLES #
############################
my $Debug = 0;
my $Timeout = 20;
my $BlockSize = 10240;	# Same as Net::FTP's default
my $BytesPerHash = 8192;
my $Username = 'rwa';
my $Password = 'rwa';
my $ScriptName = basename($0);
my $SH_TM_dots :shared;
my $SH_TM_cnct :shared;
my $SH_TM_path :shared;
my $SH_MT_copy :shared;
my $HashHandle = IO::Callback->new('>', sub { sendDotActivity(length shift) });
my %Thread = ( # Name the thread methods
	ftp	=> 'ftpThread',
	sftp	=> 'sftpThread',
);
our ($opt_f, $opt_d, $opt_p, $opt_l, $opt_x);


#############################
# FUNCTIONS                 #
#############################

sub printSyntax {
	printf "%s version %s%s\n\n", $ScriptName, $Version, ($Debug ? " running on $^O perl version $]" : "");
	print " Simultaneously transfers files to/from 1 or more devices using either FTP or SFTP\n";
	print " When GETting the same file from many devices, prepends device hostname/IP to filename\n";
	print " When PUTting the same file back to many devices, only specify the file without prepend\n";
	print "\nUsage:\n";
	print " $ScriptName [-l <user>] [-p <path>] <host/IP/list> [<ftp|sftp>] <get|put> <file-list/glob>\n";
	print " $ScriptName -f <hostfile> [-l <user>] [-p <path>] [<ftp|sftp>] <get|put> <file-list/glob>\n";
	print " $ScriptName -x <spreadsheet>[:<sheetname>]!<column-label> [-l <user>] [-p <path>] [<ftp|sftp>] <get|put> <file-list/glob>\n\n";
	print " -f <hostfile>     : File containing a list of hostnames/IPs to connect to; valid lines:\n";
	print "                   :   <IP/hostname>         [<unused-display-name>] [# Comments]\n";
	print "                   :  [<IP/hostname>]:<port> [<unused-display-name>] [# Comments]\n";
	print " -l <user>[:<pwd>] : Use non-default credentials; password will be prompted if not provided\n";
	print " -p <path>         : Path on device\n";
	print " -x <spreadsheet>[:<sheetname>]!<column-label>  : Spreadsheet file (Microsoft Excel, OpenOffice, CSV)\n";
	print "                    Spreadsheet must be a simple table where every row is a device with a number\n";
	print "                    of parameters. The first row of the table must be a label for the column values.\n";
	print "                    The label corresponding to the column with the switch IP/hostnames must be\n";
	print "                    supplied in <column-label>.\n";
	print "                    The <sheetname> is optional; if not supplied the first sheet of the spreadsheet\n";
	print "                    will be used\n";
	print " <host/IP list>    : List of hostnames or IP addresses\n";
	print "                   : Note that valid IP lists can be written as: 192.168.10.1-10,40-45,51\n";
	print "                   : IPv6 addresses are also supported: 2000:10::1-10 (decimal range 1-10)\n";
	print "                   : 2000:20::01-10 (hex range 1,2,3,4,5,6,7,8,9,a,b,c,d,e,f,10)\n";
	print " <ftp|sftp>        : Protocol to use; if omitted will default to FTP\n";
	print " <get|put>         : Whether we get files from device, or we put files to it\n";
	print " <file-list/glob>  : Filename or glob matching multiple files or space separated list\n";
	exit 1;
}

sub quit {
	my ($retval, $quitmsg, $disconnect) = @_;
	print "\n$ScriptName: ",$quitmsg,"\n" if $quitmsg;
	# Clean up and exit
	if ($disconnect) {
		{
			lock $SH_MT_copy;
			$SH_MT_copy = 0;
		}
		while (scalar threads->list(threads::running)) {
			threads->yield();
		}
	}
	exit $retval;
}

sub statusMsg { # Print status messages
	print shift();
	$| = 1; # Flush STDOUT buffer
	$| = 0; # Revert to line buffered mode
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

sub doGlob { # Fix bloody bug in File::DosGlob; and accept glob lists
	my @globpats = @_;
	my @files;

	foreach my $globpat (@globpats) {
		if ($globpat =~ /\s/) {
			push(@files, glob "'$globpat'");
		}
		else {
			push(@files, glob $globpat);
		}
	}
	return @files;
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
			$basePart = $ipv6 = undef;
			quit(1, "Duplicate hostname $host") if grep($_ eq $host, @outList);
			push(@outList, $host) unless grep(/^$host$/, @outList);
		}
	}
	return @outList;
}

sub loadHosts { # Read a list of hostnames from file
	my $infile = shift;
	my (@outList, $lineNum);

	open(FILE, $infile) or quit(1, "Cannot open input hosts file: $!");
	while (<FILE>) {
		$lineNum++;
		chomp;				# Remove trailing newline char
		next if /^#/;			# Skip comment lines
		next if /^\s*$/;		# Skip blank lines
		next if /^(?:\@echo|acligui|start|exit)/;		# Skip batch launcher lines
		if (/^\s*(\S+)\s*(?:\S+\s*)?(?:\#|$)/) {	# Valid entry
			my $host = $1;
			checkValidIP($host, undef, $lineNum) if $host =~ /^\d+\.\d+\.\d+\.\d+$/;
			checkValidIP($1, undef, $lineNum) if $host =~ /^\[(\d+\.\d+\.\d+\.\d+)\]:\d+$/;
			checkValidIP($host, 1, $lineNum) if $host =~ /^(?:\w*:)+\w+$/;
			checkValidIP($1, 1, $lineNum) if $host =~ /^\[(?:\w*:)+\w+\]:\d+$/;
			push(@outList, $host) unless grep(/^$host$/, @outList);
			next;
		}
		quit(1, "Hosts file \"$infile\" invalid syntax at line $lineNum\n");
	}
	return @outList;
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

sub splitHostPort { # Given an IP/hostname in format [<ip/hostname>]:<port> will split and return the host and port parts
	my $inputHost = shift;
	return ($1, $2) if $inputHost =~ /\[([^\]]+)\]:(\d+)/;
	return ($inputHost, undef); # Otherwise
}

sub readActivity {
	lock $SH_TM_dots;
	my $dots = $SH_TM_dots || '';
	undef $SH_TM_dots;
	return $dots;
}

sub sendActivity {
	my $char = shift;
	lock $SH_TM_dots;
	$SH_TM_dots .= $char;
}

sub sendDotActivity { # If X connections, only print a dot every X $BytesPerHash
	state ($connections, $count);	# State variables (set first time sub called; requires Perl 5.010 or later)
	return $connections = $_[1] if defined $_[1]; # Intialize state variable
	my $hashBlocks = shift;
	$count += $hashBlocks;
	my $dots = int($count / $connections);
	return unless $dots;
	$count %= $connections;
	sendActivity('.' x $dots);
}

sub ftpQuit { # Handles FTP disconnect and passing error message if provided
	my ($ftp, $error) = @_;
	$ftp->quit;
	return $error;
}

sub ftpThread { # FTP Thread to each device
	my ($tnum, $host, $remotePath, $transferMode, $regexRef, $globsRef, $multipleHosts, $globOrMany) = @_;
	my ($fnum, $filehost, $port);
	($host, $port) = splitHostPort($host);
	($filehost = $host) =~ s/:/_/g; # Produce a suitable filename for IPv6 addresses or [<ip>]:<port>

	# Connect
	my $ftp = Net::FTP->new($host, Port => $port, Timeout => $Timeout, BlockSize => $BlockSize) or return "Cannot connect: $@";
	$ftp->hash($HashHandle, $BytesPerHash);
	$ftp->login($Username, $Password) or return ftpQuit($ftp, "Cannot login: ".$ftp->message);
	$ftp->binary or return ftpQuit($ftp, "Setting bin mode failed: ".$ftp->message);
	{ # Signal connection ok
		lock $SH_TM_cnct;
		$SH_TM_cnct++;
	}

	# Set FTP path
	if ($remotePath) {
		$ftp->cwd($remotePath) or return ftpQuit($ftp, "Cannot change to directory $remotePath: ".$ftp->message);
		{ # Signal path ok
			lock $SH_TM_path;
			$SH_TM_path++;
		}
	}
	# Pause before copying
	WAIT: while (1) {
		threads->yield();
		{ # Check if green light to copy from main
			lock $SH_MT_copy;
			last WAIT if $SH_MT_copy; # = 1
			return ftpQuit($ftp) if defined $SH_MT_copy; # = 0
		}
	}

	# Get/Put files
	if ($transferMode eq 'get') {
		my @matchFiles;
		if ($globOrMany) { # Do an ls on host to see what files we'll be getting
			my @remoteFiles = $ftp->ls or return ftpQuit($ftp, "Retrieving ls failed: ".$ftp->message);
			foreach my $fileRegex (@$regexRef) {
				push(@matchFiles, grep(/$fileRegex/, @remoteFiles));
			}
		}
		else { # Just get the single file (not a glob)
			push(@matchFiles, $globsRef->[0]);
		}
		foreach my $remoteFile (@matchFiles) {
			$fnum++;
			if ($multipleHosts) { # Getting from multiple hosts
				my $localFile = "${filehost}_$remoteFile";
				$ftp->get($remoteFile, $localFile) or return ftpQuit($ftp, "Get failed: ".$ftp->message);
			}
			else { # Get from 1 host only
				$ftp->get($remoteFile) or return ftpQuit($ftp, "Get failed: ".$ftp->message);
			}
			$#matchFiles ? sendActivity("<$tnum:$fnum>") : sendActivity("<$tnum>");
		}
	}
	elsif ($transferMode eq 'put') {
		my @localFiles;
		if ($multipleHosts) { # Putting to multiple hosts
			@localFiles = doGlob( map("${filehost}_$_", @$globsRef) );
			@localFiles = doGlob(@$globsRef) unless scalar @localFiles;
			foreach my $localFile (@localFiles) {
				$fnum++;
				(my $remoteFile = $localFile) =~ s/^${filehost}_//;
				$ftp->put($localFile, $remoteFile) or return ftpQuit($ftp, "Put failed: ".$ftp->message);
				$#localFiles ? sendActivity("<$tnum:$fnum>") : sendActivity("<$tnum>");
			}
		}
		else { # Put to 1 host only
			@localFiles = doGlob(@$globsRef);
			@localFiles = doGlob( map("${filehost}_$_", @$globsRef) ) unless scalar @localFiles;
			foreach my $localFile (@localFiles) {
				$fnum++;
				$ftp->put($localFile) or return ftpQuit($ftp, "Put failed: ".$ftp->message);
				$#localFiles ? sendActivity("<$tnum:$fnum>") : sendActivity("<$tnum>");
			}
		}
	}
	
	# Disconnect
	ftpQuit($ftp);
	return 1;
}

sub sftpQuit { # Handles SFTP disconnect and passing error message if provided
	my ($ssh2, $sftpRef, $error) = @_;
	undef $$sftpRef if defined $sftpRef;
	$ssh2->disconnect;
	return $error;
}

sub sgetfile { # Read file from filehandle and save locally
	my ($fh, $localFile) = @_;
	my ($loc, $len, $buf, $count);

	sysopen($loc, $localFile, O_CREAT | O_WRONLY | O_TRUNC) or return;
	binmode($loc) or return;
	while($len = $fh->read($buf, $BlockSize)) {
		$count += $len;
		print $loc $buf;
		sendDotActivity( int($count / $BytesPerHash) );
		$count %= $BytesPerHash;
	}
	close($loc);
	return unless defined $len;	# fh read error
	return 1;			# copy was successful
}

sub sputfile { # Read file locally and write to filehandle
	my ($fh, $localFile) = @_;
	my ($loc, $len, $buf, $count);

	sysopen($loc, $localFile, O_RDONLY) or return;
	binmode($loc) or return;
	while($len = read($loc, $buf = '', $BlockSize)) {
		$count += $len;
		$fh->write($buf) or return;
		sendDotActivity( int($count / $BytesPerHash) );
		$count %= $BytesPerHash;
	}
	close($loc);
	return unless defined $len;	# file read error
	return 1;			# copy was successful
}

sub sftpThread { # SFTP Thread to each device
	my ($tnum, $host, $remotePath, $transferMode, $regexRef, $globsRef, $multipleHosts, $globOrMany) = @_;
	my ($fnum, $filehost, $port);
	($host, $port) = splitHostPort($host);
	($filehost = $host) =~ s/:/_/g; # Produce a suitable filename for IPv6 addresses or [<ip>]:<port>

	# Connect
	my $ssh2 = Net::SSH2->new;
	$ssh2->connect($host, $port) or return "Cannot SSH connect";
	$ssh2->auth(username => $Username, password => $Password) or return sftpQuit($ssh2, undef, "Cannot authenticate");
	my $sftp = $ssh2->sftp;
	{ # Signal connection ok
		lock $SH_TM_cnct;
		$SH_TM_cnct++;
	}

	# Adjust SFTP path
	$remotePath .= '/' unless $remotePath eq '' || $remotePath =~ /\/$/;

	# Pause before copying
	WAIT: while (1) {
		threads->yield();
		{ # Check if green light to copy from main
			lock $SH_MT_copy;
			last WAIT if $SH_MT_copy; # = 1
			return sftpQuit($ssh2, \$sftp) if defined $SH_MT_copy; # = 0
		}
	}

	# Get/Put files
	if ($transferMode eq 'get') {
		my @matchFiles;
		if ($globOrMany) { # Do an ls on host to see what files we'll be getting
			my $sdir = $sftp->opendir($remotePath) or return sftpQuit($ssh2, \$sftp, "Cannot change to directory $remotePath");
			while(my $item = $sdir->read) {
				foreach my $fileRegex (@$regexRef) {
					push(@matchFiles, $item->{name}) if $item->{name} =~ /$fileRegex/;
				}
			}
		}
		else { # Just get the single file (not a glob)
			push(@matchFiles, $globsRef->[0]);
		}
		foreach my $remoteFile (@matchFiles) {
			$fnum++;
			my $fh = $sftp->open($remotePath.$remoteFile) or return sftpQuit($ssh2, \$sftp, "Get failed: $remoteFile");
			if ($multipleHosts) { # Getting from multiple hosts
				my $localFile = "${filehost}_$remoteFile";
				sgetfile($fh, $localFile) or return sftpQuit($ssh2, \$sftp, "Get copy failed: $remoteFile");
			}
			else { # Get from 1 host only
				sgetfile($fh, $remoteFile) or return sftpQuit($ssh2, \$sftp, "Get copy failed: $remoteFile");
			}
			$#matchFiles ? sendActivity("<$tnum:$fnum>") : sendActivity("<$tnum>");
		}
	}
	elsif ($transferMode eq 'put') {
		my @localFiles;
		if ($multipleHosts) { # Putting to multiple hosts
			@localFiles = doGlob( map("${filehost}_$_", @$globsRef) );
			@localFiles = doGlob(@$globsRef) unless scalar @localFiles;
			foreach my $localFile (@localFiles) {
				$fnum++;
				(my $remoteFile = $localFile) =~ s/^${filehost}_//;
				my $fh = $sftp->open($remotePath.$remoteFile, O_WRONLY | O_CREAT | O_TRUNC) or return sftpQuit($ssh2, \$sftp, "Put failed: $remoteFile");
				sputfile($fh, $localFile) or return sftpQuit($ssh2, \$sftp, "Put copy failed: $remoteFile");
				$#localFiles ? sendActivity("<$tnum:$fnum>") : sendActivity("<$tnum>");
			}
		}
		else { # Put to 1 host only
			@localFiles = doGlob(@$globsRef);
			@localFiles = doGlob( map("${filehost}_$_", @$globsRef) ) unless scalar @localFiles;
			foreach my $localFile (@localFiles) {
				$fnum++;
				my $fh = $sftp->open($remotePath.$localFile, O_WRONLY | O_CREAT | O_TRUNC) or return sftpQuit($ssh2, \$sftp, "Put failed: $localFile");
				sputfile($fh, $localFile) or return sftpQuit($ssh2, \$sftp, "Put copy failed: $localFile");
				$#localFiles ? sendActivity("<$tnum:$fnum>") : sendActivity("<$tnum>");
			}
		}
	}
	
	# Disconnect
	sftpQuit($ssh2, \$sftp);
	return 1;
}


#############################
# MAIN                      #
#############################

MAIN:{
	my ($aftpProtocol, $aftpMode, @aftpHosts, $aftpPath, @fileGlobs, @fileRegex, %aftpThread, $glob, $globOrMany);
	getopts('df:p:l:x:');

	$Debug = 1 if $opt_d;
	printSyntax if !@ARGV || $ARGV[0] eq '?';

	if ($opt_f) {
		printSyntax if scalar @ARGV < 2;
		@aftpHosts = loadHosts($opt_f);
	}
	elsif ($opt_x) { # A spreadsheet file
		printSyntax unless $opt_x =~ /^([^:!\s]+)(?::([^!\s]+))?(?:!(.+))$/;
		my ($filename, $sheetname, $deviceLabel) = ($1, $2, $3);
		@aftpHosts = keys %{(readSpreadsheet($filename, $sheetname, $deviceLabel))[0]};
	}
	else {
		printSyntax unless @ARGV;
		@aftpHosts = listHosts(shift @ARGV);
	}
	printSyntax unless @ARGV;
	$aftpProtocol = lc shift @ARGV;
	if ($aftpProtocol eq 'ftp' || $aftpProtocol eq 'sftp') {
		printSyntax unless @ARGV;
		$aftpMode = lc shift @ARGV;
		printSyntax unless $aftpMode eq 'get' || $aftpMode eq 'put';
	}
	elsif ($aftpProtocol eq 'get' || $aftpProtocol eq 'put') {
		$aftpMode = $aftpProtocol;
		$aftpProtocol = 'ftp';
	}
	else {
		printSyntax;
	}
	printSyntax unless @ARGV;

	if ($opt_l) {
		if ($opt_l =~ /^([^:\s]+):(\S*)$/) {
			$Username = $1;
			$Password = $2;
		}
		else {
			$Username = $opt_l;
			$Password = promptHide("password for $Username");
		}
	}

	$aftpPath = $opt_p || '';
	print "Ftp path = $aftpPath\n" if $Debug && defined $aftpPath;
	@fileGlobs = @ARGV;
	foreach my $fileGlob (@fileGlobs) {
		quit(1, "Invalid filename/glob") unless length $fileGlob;
		quit(1, "Invalid filename/glob") if $aftpMode eq 'get' && $fileGlob =~ /[\\\/]/;
		print "File glob = $fileGlob\n" if $Debug;
		# Prepare regular expression glob pattern
		(my $fileRegex = $fileGlob) =~ s/([\.\$])/\\$1/g;	# Backslash perl's meta characters
		$fileRegex .= '$' unless $fileRegex =~ /\*$/;		# $ anchor unless ending with *
		$fileRegex = '^'.$fileRegex unless $fileRegex =~ /^\*/;	# ^ anchor unless beginning with *
		$glob = 1 if $fileRegex =~ s/\*/.*/g;	# Replace * with .*
		$glob = 1 if $fileRegex =~ s/\?/./g;	# Replace ? with .
		print "Modified File glob = $fileRegex\n" if $Debug;
		push(@fileRegex, $fileRegex);
	}
	$globOrMany = $glob || $#fileGlobs;

	# Set state variables in sendDotActivity
	sendDotActivity(undef, scalar @aftpHosts);

	# Start threads
	print "Connecting to hosts via ", uc($aftpProtocol), ":\n";
	for my $i (0 .. $#aftpHosts) {
		my $host = $aftpHosts[$i];
		printf " %2u - %s\n", $i+1, $host;
		$aftpThread{$host} = threads->create($Thread{$aftpProtocol}, $i+1, $host, $aftpPath, $aftpMode, \@fileRegex, \@fileGlobs, $#aftpHosts, $globOrMany);
	}
	print "\n";

	# Check connection phase complete
	my ($connectOk, $connectFail) = (0, 0);
	do {
		threads->yield();
		{ # Read connection ok
			lock $SH_TM_cnct;
			$connectOk = $SH_TM_cnct || 0;
		}
		# Check for connection errors
		foreach my $host (@aftpHosts) {
			my $retVal = $aftpThread{$host}->join if $aftpThread{$host}->is_joinable();
			if ($retVal) {
				print "ERROR from $host: $retVal\n";
				$connectFail++;
			}
		}
	} until ($connectOk + $connectFail == scalar @aftpHosts);
	quit(1, "Failed to connect to some hosts", 1) if $connectFail;

	# Check for path setting (only for FTP)
	if ($aftpProtocol eq 'ftp' && $aftpPath) {
		my ($pathOk, $pathFail) = (0, 0);
		do {
			threads->yield();
			{ # Read path ok
				lock $SH_TM_path;
				$pathOk = $SH_TM_path || 0;
			}
			# Check for connection errors
			foreach my $host (@aftpHosts) {
				my $retVal = $aftpThread{$host}->join if $aftpThread{$host}->is_joinable();
				if ($retVal) {
					print "ERROR from $host: $retVal\n";
					$pathFail++;
				}
			}
		} until ($pathOk + $pathFail == $connectOk);
		quit(1, "Failed to set path on some hosts", 1) if $pathFail;
	}

	# Send green light to start copying
	{
		lock $SH_MT_copy;
		$SH_MT_copy = 1;
	}
	
	# Activity dots while copying
	statusMsg "Copying files ";
	while (scalar threads->list(threads::running)) {
		threads->yield();
		statusMsg(readActivity);
	}
	print "\n";

	# Check for connection errors
	foreach my $host (@aftpHosts) {
		my $retVal = $aftpThread{$host}->join if $aftpThread{$host}->is_joinable();
		if (!defined $retVal) { # Failed thread
			print "ERROR from $host; thread did not complete\n";
		}
		elsif ($retVal ne '1') { # Thread where we did detect an error
			print "ERROR from $host: $retVal\n";
		}
	}
	print "\n";
}
