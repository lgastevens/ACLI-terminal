# ACLI sub-module
package AcliPm::TerminalServer;
our $Version = "1.01";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(printTrmSrvList loadTrmSrvStruct loadTrmSrvConnections saveTrmSrvList addTrmSrvListEntry
			 updateTrmSrvFile processTrmSrvSelection);
}
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::DebugMessage;
use AcliPm::GlobalDefaults;


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


sub trmSrvSortBy { # Sort function to print out trmsrv list
	my $annexData = shift;
	return -1 unless defined $annexData->{Sort}; #If undefined, print list as is
	my $a_entry = $annexData->{List}->[$a];
	my $b_entry = $annexData->{List}->[$b];
	if ($annexData->{Sort} eq 'ip') {
		my $result;
		if ($a_entry->[0] =~ /^\d+\.\d+\.\d+\.\d+$/ && $b_entry->[0] =~ /^\d+\.\d+\.\d+\.\d+$/) { # Both are IP addresses
			my @a_digits = split(/[\._]/, $a_entry->[0]);
			my @b_digits = split(/[\._]/, $b_entry->[0]);
			$result = compareDigitList(\@a_digits, \@b_digits);
		}
		else {
			$result = $a_entry->[0] cmp $b_entry->[0];
		}
		return $result unless $result == 0;		# Order by IP, unless a tie
		return $a_entry->[2] <=> $b_entry->[2];		# Compare Port if IPs the same
	}
	elsif ($annexData->{Sort} eq 'name') {
		return $a_entry->[3] cmp $b_entry->[3];
	}
	else { # 'cmnt' = comments field
		return $a_entry->[5] cmp $b_entry->[5];
	}
}


sub printTrmSrvList { # Print out list of known trmsrv connections or those that match a selection
	my ($annexData, $selection, $noPrompt) = @_;

	print "\nKnown remote terminal-server sessions";
	print " matching '$selection'" if $selection;
	print ":\n\n";
	my $comments;
	for my $i ( 0 .. $#{$annexData->{List}} ) { # Do we need a comments column ?
		if (length $annexData->{List}->[$i][4]) {
			$comments = 1;
			last;
		}
	}
	printf "%3s  %-15s %5s %-70s %s\n", 'Num', 'TrmSrv/IP ssh/tel', 'Port', 'Name of attached device (details)', $comments ? 'Comments':'';
	printf "%3s  %-15s %5s %-70s %s\n", '---', '-'x17, '----', '-'x70, $comments ? '-'x25:'';
	for my $i ( 0..$#{$annexData->{List}} ) {
		my $entry = $annexData->{List}->[$i];
		next if $selection && !($entry->[0] eq $selection || $entry->[3] =~ /$selection/i || $entry->[4] =~ /$selection/i || $entry->[5] =~ /$selection/i);
		printf "%3s  %-15s %s %5s %-70s %s\n", $i+1, $entry->[0], $entry->[1], $entry->[2], $entry->[3] .' '. $entry->[4], $entry->[5];
	}
	print "\n";
	print "Select entry number / device name glob / <entry|IP>#<port> : " unless $noPrompt;
}


sub loadTrmSrvStruct { # Load Terminal Server file into the hash structure
	my ($db, $loadMsgFlag) = @_;
	my $host_io = $db->[3];
	my $annexData = $db->[13];
	my $annexFile;
	@{$annexData->{List}} = ();

	# Try and find a matching annex file in the paths available
	PATH: foreach my $path (@AcliFilePath) {
		foreach my $trmsrvFileName (@AnnexFileName) {
			if (-e "$path/$trmsrvFileName") {
				$annexFile = "$path/$trmsrvFileName";
				last PATH;
			}
		}
	}
	debugMsg(1, "AnnexFileRead: Found file:\n ", \$annexFile, "\n") if $annexFile;
	if ($annexData->{MasterFile}) { # A master file is set
		my $masterFileExists;
		if (-e $ScriptDir . $annexData->{MasterFile}) {
			$annexData->{MasterFile} = File::Spec->canonpath($ScriptDir . $annexData->{MasterFile});
			$masterFileExists = 1;
		}
		elsif (-e $annexData->{MasterFile}) {
			$annexData->{MasterFile} = File::Spec->canonpath($annexData->{MasterFile});
			$masterFileExists = 1;
		}
		if ($masterFileExists) {
			debugMsg(1, "AnnexFileRead: Master file exist:\n ", \$annexData->{MasterFile}, "\n");
			if ($annexFile) { # A normal trmsrv.annex file was already found above
				if ( (stat($annexData->{MasterFile}))[9] > (stat($annexFile))[9] ) {
					debugMsg(1, "AnnexFileRead: Master file is more recent! We use it.\n");
					$annexFile = $annexData->{MasterFile};
				}
				else {
					debugMsg(1, "AnnexFileRead: Master file is older than regular file.\n");
				}
			}
			else {
				debugMsg(1, "AnnexFileRead: Using Master file as normal file not found\n");
				$annexFile = $annexData->{MasterFile};
			}
		}
		else {
			debugMsg(1, "AnnexFileRead: Master file is set but was not found:\n ", \$annexData->{MasterFile}, "\n");
			print "Master terminal-server file not found: ", $annexData->{MasterFile}, "\n" if $loadMsgFlag;
			$annexData->{MasterFile} = "File '$annexData->{MasterFile}' not found";
		}
	}

	unless ($annexFile) {
		$host_io->{AnnexFile} = '';
		return;
	}

	$host_io->{AnnexFile} = File::Spec->canonpath($annexFile); # Update display path
	# We should have an annex file to work with now
	debugMsg(1, "AnnexFileRead: Loading file:\n ", \$annexFile, "\n");
	print "Loading terminal-server file: ", File::Spec->rel2abs($annexFile), "\n" if $loadMsgFlag;

	# Read in annex data
	my $lineNumber = 0;
	open(ANNEX, '<', $annexFile) or return;
	flock(ANNEX, 1); # 1 = LOCK_SH; Put a shared lock on the file (wait to read if it's being changed)
	while (<ANNEX>) {
		chomp;
		$lineNumber++;
		next if /^\s*$/; # skip empty lines
		next if /^\s*#/; # skip comment lines
		/^\s*:sort\s*=\s*(ip|name|cmnt)\s*$/i && do {
			$annexData->{Sort} = lc $1;
			debugMsg(1, "loadTrmSrvStruct: :sort flag set to: ", \$annexData->{Sort}, "\n");
			next;
		};
		/^\s*:static\s*=\s*([01])\s*$/i && do {
			$annexData->{Static} = $1;
			debugMsg(1, "loadTrmSrvStruct: :static flag set\n") if $annexData->{Static};
			next;
		};
		/^\s*(\S+)(?:\s+([sStT]))?\s+(\d+)\s+(\S+)(?:\s+(\(.+?\)))?(?:\s+(.+?))?\s*$/ && do {
			push(@{$annexData->{List}}, [$1, defined $2 ? lc $2:'t', $3, $4, defined $5 ? $5:'', defined $6 ? $6:'']);
			next;
		};
		# We just skip lines we don't like!
		debugMsg(1, "loadTrmSrvStruct: Syntax error on line $lineNumber while reading annex file:\n ", \$annexFile, "\n");
	}
	close ANNEX;

	# Sort the array structure, with a slice of itself
	@{$annexData->{List}} = @{$annexData->{List}}[ sort { trmSrvSortBy($annexData) } 0..$#{$annexData->{List}} ];

	return 1;
}


sub loadTrmSrvConnections { # Load Terminal Server file and process selection if possible
	my ($db, $selection) = @_;
	my $host_io = $db->[3];
	my $annexData = $db->[13];

	$host_io->{Name} = ''; # Clear this out to start with
	loadTrmSrvStruct($db, 1) or return;

	# Verify if selection is a valid regex
	if ($selection && !defined eval { qr/$selection/ }) {
		print "\nSelection \"$selection\" is not a valid regex";
		$selection = '';
	}

	# If a selection was specified, check if we have an immediate match
	if ($selection) {
		if ($selection =~ /^(.+?)\s*\#\s*(\d+)$/) { # Hostname/IP #<port>
			$host_io->{Name} = $1;
			$host_io->{ComPort} = 'TELNET';
			$host_io->{TcpPort} = $2;
			$host_io->{TcpPort} += $RemoteAnnexBasePort if ($host_io->{TcpPort} && $host_io->{TcpPort} <= 16);
			return 1;
		}
		my $match;
		$selection =~ s/([\{\}\[\]\(\)])/\\$1/g; # Backslash perl metachars
		foreach my $entry (@{$annexData->{List}}) {
			if ($entry->[0] eq $selection || $entry->[3] =~ /$selection/i || $entry->[4] =~ /$selection/i || $entry->[5] =~ /$selection/i) {
				if (defined $match) {
					print "\nMultiple entries match selection \"$selection\"";
					$match = 0;
					last;
				}
				$match = $entry;
			}
		}
		print "\nNo entries match selection \"$selection\"" unless defined $match;
		if ($match) { # We have a matching entry
			$host_io->{Name} = $match->[0];
			$host_io->{ComPort} = $match->[1] eq 's' ? 'SSH' : 'TELNET';
			$host_io->{TcpPort} = $match->[2];
			debugMsg(1, "AnnexEntryMatch: $host_io->{Name} port $host_io->{TcpPort}\n");
			return 1;
		}
	}

	# If we get here we don't have a clear match; so we print the list and come out
	printTrmSrvList($annexData, $selection);
	return 1;
}


sub saveTrmSrvList { # Save new Terminal Server file
	my $db = shift;
	my $host_io = $db->[3];
	my $annexData = $db->[13];

	debugMsg(1, "AnnexFileSave: Saving file:\n ", \$host_io->{AnnexFile}, "\n");

	my $annexFile = join('', $AcliFilePath[0], '/', $AnnexFileName[0]);
	$host_io->{AnnexFile} = File::Spec->canonpath($annexFile); # Update display path

	open(ANNEX, '>', $annexFile) or return;
	flock(ANNEX, 2); # 2 = LOCK_EX; Put an exclusive lock on the file as we are modifying it
	my $timestamp = localtime;
	print ANNEX "# $ScriptName saved on $timestamp\n";
	printf ANNEX ":sort	= %s\n", $annexData->{Sort} if defined $annexData->{Sort};
	printf ANNEX ":static	= %s\n", $annexData->{Static} if defined $annexData->{Static};
	print ANNEX "\n";
	printf ANNEX "#%-16s %5s %-70s %s\n", 'TmSrv/IP ssh/tel', 'Port', 'Name of attached device (details)', 'Comments';
	printf ANNEX "#%-16s %5s %-70s %s\n", '-'x16, '----', '-'x70, '-'x25;
	for my $i ( sort { trmSrvSortBy($annexData) } 0..$#{$annexData->{List}} ) { # Iterate sorted array index list
		my $entry = $annexData->{List}->[$i];
		printf ANNEX "%-15s %s %5s %-70s %s\n", $entry->[0], $entry->[1], $entry->[2], $entry->[3] .' '. $entry->[4], $entry->[5];
	}
	close ANNEX;
	return 1;
}


sub addTrmSrvListEntry { # Add an entry to the trmsrv list struct
	my ($db, $ip, $com, $port, $name, $details, $comments, $mac, $sysname) = @_;
	my $host_io = $db->[3];
	my $annexData = $db->[13];
	my $existingEntry;

	unless ($annexData->{Static}) {
		my @delIndex;
		for my $i ( 0..$#{$annexData->{List}} ) {
			my $entry = $annexData->{List}->[$i];
			if (defined $mac && $entry->[4] =~ /$mac/) { # Delete existing entry for same MAC
				debugMsg(1, "addTrmSrvListEntry: Deleting entry with same MAC : ", \join(',', @$entry), "\n");
				push(@delIndex, $i);
			}
			elsif (defined $sysname && $entry->[4] !~ /[\dA-Fa-f]-{5}[\dA-Fa-f]/ && $entry->[3] eq $sysname) { # Delete existing entry with no MAC but same name
				debugMsg(1, "addTrmSrvListEntry: Deleting entry with same Name : ", \join(',', @$entry), "\n");
				push(@delIndex, $i);
			}
		}
		if (@delIndex) {
			foreach my $i (@delIndex) {
				splice(@{$annexData->{List}}, $i, 1);
			}
		}
	}

	# See if we already have the same trmsrv IP & port
	for my $entry ( @{$annexData->{List}} ) {
		if ($entry->[0] eq $ip && $entry->[1] eq $com && $entry->[2] eq $port) {
			# We already have an entry for the same trmsrv IP & port; update it
			$entry->[3] = $name;
			$entry->[4] = $details;
			$entry->[5] = $comments if defined $comments;
			$existingEntry = 1;
			debugMsg(1, "addTrmSrvListEntry: Updated existing entry\n");
			last;
		}
	}
	unless ($existingEntry) { # The entry was not found; so we append to the list instead
		$comments = '' unless defined $comments;
		push(@{$annexData->{List}}, [$ip, $com, $port, $name, $details, $comments]);
		debugMsg(1, "addTrmSrvListEntry: Appended new entry\n");
	}
}


sub updateTrmSrvFile { # Updates Terminal Server file with details of known connections and port to device name mappings
	my $db = shift;
	my $host_io = $db->[3];
	my $annexData = $db->[13];
	my @grepLines;

	return unless $host_io->{RemoteAnnex};

	unless (-e $AcliFilePath[0] && -d $AcliFilePath[0]) { # Create base directory if not existing
		mkdir $AcliFilePath[0] or return;
		debugMsg(1, "AnnexFileSave: Created directory:\n ", \$AcliFilePath[0], "\n");
	}

	# Reload anyway the structure (it could have changed)
	loadTrmSrvStruct($db) or return;

	# Create/Update the new entry details
	my @details;
	my @t = localtime;
	push(@details, sprintf("%02d/%02d/%02d", $t[3], $t[4] + 1, $t[5] - 100));
	push(@details, $host_io->{Model}) if defined $host_io->{Model};
	push(@details, $host_io->{BaseMAC}) if defined $host_io->{BaseMAC};
	if ($host_io->{Type} eq 'PassportERS') {
		push(@details, "CPU" . $host_io->{CpuSlot}) if defined $host_io->{CpuSlot};
	}
	elsif ( ($host_io->{Type} eq 'BaystackERS' || $host_io->{Type} eq 'ExtremeXOS') && defined $host_io->{SwitchMode}) {
		if ($host_io->{SwitchMode} eq 'Stack') {
			push(@details, "Unit" . $host_io->{UnitNumber}) if defined $host_io->{UnitNumber};
		}
		else { # $host_io->{SwitchMode} eq 'Switch'
			push(@details, "Standalone");
		}
	}
	my $details .= ' (' . join('; ', @details) . ')' if @details;
	addTrmSrvListEntry($db, $host_io->{Name}, $host_io->{ComPort} eq 'SSH' ? 's':'t', $host_io->{TcpPort}, $host_io->{Sysname}, $details, undef, $host_io->{BaseMAC}, $host_io->{Sysname});
	saveTrmSrvList($db) or return;
	return 1;
}


sub processTrmSrvSelection { # Process a selection from terminal server table
	my ($db, $selection) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $annexData = $db->[13];

	print "\n";
	if ($selection =~ /^\s*$/) { # Nothing entered, come out
		print "Nothing entered! ($term_io->{CtrlQuitPrn} to quit)\n";
		print "Select entry number / device name glob / <entry|IP>#<port> : ";
		return;
	}
	$selection =~ s/^\s*//;	# Remove starting spaces
	$selection =~ s/\s*$//;	# Remove trailing spaces

	# Verify if selection is a valid regex
	if ($selection && !defined eval { qr/$selection/ }) {
		print "Selection \"$selection\" is not a valid regex\n";
		print "Select entry number / device name glob / <entry|IP>#<port> : ";
		return;
	}

	if ($selection =~ /^\d+$/ && $selection >= 1 && $selection <= scalar @{$annexData->{List}}) { # Number in range entered
		$host_io->{Name} = $annexData->{List}->[$selection - 1][0];
		$host_io->{ComPort} = $annexData->{List}->[$selection - 1][1] eq 's' ? 'SSH' : 'TELNET';
		$host_io->{TcpPort} = $annexData->{List}->[$selection - 1][2];
		return 1;
	}
	elsif ($selection =~ /^(\d+)\s*\#\s*(\d+)$/ && $1 >= 1 && $1 <= scalar @{$annexData->{List}}) { # Number in range entered #<port>
		$host_io->{Name} = $annexData->{List}->[$1 - 1][0];
		$host_io->{ComPort} = $annexData->{List}->[$1 - 1][1] eq 's' ? 'SSH' : 'TELNET';
		$host_io->{TcpPort} = $2;
		$host_io->{TcpPort} += $RemoteAnnexBasePort if ($host_io->{TcpPort} && $host_io->{TcpPort} <= 16);
		return 1;
	}
	elsif ($selection =~ /^(.+?)\s*\#\s*(\d+)$/) { # Hostname/IP #<port>
		$host_io->{Name} = $1;
		$host_io->{ComPort} = 'TELNET';
		$host_io->{TcpPort} = $2;
		$host_io->{TcpPort} += $RemoteAnnexBasePort if ($host_io->{TcpPort} && $host_io->{TcpPort} <= 16);
		return 1;
	}
	# Else, we have a string entered
	my $match;
	$selection =~ s/([\{\}\[\]\(\)])/\\$1/g; # Backslash perl metachars
	foreach my $entry (@{$annexData->{List}}) {
		if ($entry->[0] eq $selection || $entry->[3] =~ /$selection/i || $entry->[4] =~ /$selection/i || $entry->[5] =~ /$selection/i) {
			if (defined $match) {
				printTrmSrvList($annexData, $selection);
				return;
			}
			$match = $entry;
		}
	}
	unless (defined $match) {
		print "No entries match selection \"$selection\"\n";
		print "Select entry number / device name glob / <entry|IP>#<port> : ";
		return;
	}
	$host_io->{Name} = $match->[0];
	$host_io->{ComPort} = $match->[1] eq 's' ? 'SSH' : 'TELNET';
	$host_io->{TcpPort} = $match->[2];
	return 1;
}

1;
