# ACLI sub-module
package AcliPm::Ssh;
our $Version = "1.02";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(verifySshKeys compactIPv6 inspectSshPublicKeys readSshPublicKeyFile inspectLocalSshKeys
			 deleteSshKnownHostEntry clenseSshKnownHostFile readSshKnownHosts readDeviceSshKeys
			 determineSshStack deviceAddSshKey deviceSshKeyDelete deviceDeleteSshFile verifySshHostKey);
}
use MIME::Base64 ();
use Crypt::Digest::MD5 qw( md5 );
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::DebugMessage;
use AcliPm::GlobalDefaults;
use AcliPm::Print;
use AcliPm::ReadKey;
use AcliPm::Version;


sub verifySshKeys { # Tries to find all of private and public SSH keys
	my ($hashRef, $privatekey) = @_;
	my ($keyName, $keyPath) = defined $privatekey && $privatekey =~ /[\/\\]/ ? File::Basename::fileparse($privatekey) : ($privatekey, '');
	my @keyNames = $keyName ? ($keyName) : @{$Default{ssh_default_keys_lst}};
	my @pathDirs = $keyPath ? ($keyPath) : @SshKeyPath;
	$keyPath = undef;
	foreach my $key (@keyNames) {
		my $pubkey;
		# See if we have public/private keys to use
		foreach my $path (@pathDirs) {
			if (-e "$path/$key") {
				debugMsg(1,"Private key found @ $path/$key\n");
				($pubkey = $key) =~ s/.prv$//; # Remove .prv suffix if one present
				$pubkey .= '.pub'; # Add .pub suffix
				unless (-e "$path/$pubkey") {
					debugMsg(1, "No Public Key $path/$pubkey found\n");
					return;
				}
				debugMsg(1,"Public key found @ $path/$pubkey\n");
				$keyPath = $path;
				last;
			}
		}
		if ($keyPath) {
			$hashRef->{SshPrivateKey} = File::Spec->canonpath("$keyPath/$key");
			$hashRef->{SshPublicKey} = File::Spec->canonpath("$keyPath/$pubkey");
			return 1;
		}
	}
	return;
}


sub compactIPv6 { # Taken & modified from IPv6::Address on CPAN; needed when adding or comparing to SSH known_hosts file
	# This function will simply do a lowercase if the input string is not an IPv6 address
	my $str = lc shift;
	# Remove leeading zeros, if an IPv6 address
	$str =~ s/^0+(?=[a-f\d]+:)//;	# 1st ipv6 word
	$str =~ s/:\K0+(?=[a-f\d]+)//g;	# other ipv6 words
	return $str if $str =~ /::/; # Already compacted IPv6 addres
	# Compact 0:0 sequences if an IPv6 address
	return '::' if($str eq '0:0:0:0:0:0:0:0');
	for(my $i=7;$i>1;$i--) {
		my $zerostr = join(':',split('','0'x$i));
		###print "DEBUG: $str $zerostr \n";
		if($str =~ /:$zerostr$/) {
			$str =~ s/:$zerostr$/::/;
			return $str;
		}
		elsif ($str =~ /:$zerostr:/) {
			$str =~ s/:$zerostr:/::/;
			return $str;
		}
		elsif ($str =~ /^$zerostr:/) {
			$str =~ s/^$zerostr:/::/;
			return $str;
		}
	}
	return $str;
}


sub decodeSshKey { # Base64 decodes key type & keylength; key can be supplied as base64 or as raw; in latter case set 2nd arg to true
	my ($keyRef, $raw) = @_;
	my $base64decode = $raw ? $$keyRef : MIME::Base64::decode($$keyRef);
	my ($lv, $keyType, $keylength, $fingerPrint);

	# Extract key type & size
	$lv = unpack('N', substr($base64decode, 0, 4, ''));		# Key type length
	$keyType = unpack('A*', substr($base64decode, 0, $lv, ''));	# Key type (ssh-rsa or ssh-dss)
	$lv = unpack('N', substr($base64decode, 0, 4, ''));		# RSA = Exponent length / DSA = key length
	if ($keyType eq 'ssh-rsa') {
		substr($base64decode, 0, $lv, '');			# Skip
		$lv = unpack('N', substr($base64decode, 0, 4, ''));	# RSA = key length
	}
	$keylength = defined $lv ? ($lv - 1) * 8 : '-';
	# Get MD5 fingerprint of key
	$fingerPrint = join(':', map { sprintf "%02x", ord } split //, md5($$keyRef));
	return ($keyType, $keylength, $fingerPrint);
}


sub inspectSshPublicKeys { # Takes the file output of 1 or more public keys and returns an array structure with key data for all keys found
	my $outref = shift;
	my (@keyData, $type, $key, $comment, $length, $lineNumber, $fingerPrint);
	my $number = 0;
	while ($$outref =~ /^(.+)$/mg) {
		my $line = $1;
		$number++;
		$line =~ /^-+\s*BEGIN/ && do { # IETF format, begin
			$type = $key = $comment = '';
			$lineNumber = $number;
			next;
		};
		$line =~ /^-+\s*END/ && do { # IETF format, end
			($type, $length, $fingerPrint) = decodeSshKey(\$key);
			push(@keyData, ['ietf', $type, $length, $comment, $key, $fingerPrint, $lineNumber, $number+1]);
			next;
		};
		$line =~ /^Comment: "?(.+?)"?$/ && do { # IETF format, fragmented key
			$comment = $1;
			next;
		};
		$line =~ /^(\S+) (\S+)(?: (.+))?$/ && do { # OpenSSH format (single line)
			($type, $key, $comment) = ($1, $2, $3);
			($type, $length, $fingerPrint) = decodeSshKey(\$key);
			push(@keyData, ['openssh', $type, $length, $comment, $key, $fingerPrint, $number, $number+1]);
			next;
		};
		$line =~ /^(\S+)$/ && do {
			$key .= $1;
		};
	}
	return \@keyData;
}


sub readSshPublicKeyFile { # Reads the contents of the local public key and returns a reference to it
	my $publicKey = shift;

	open(KEY, '<', $publicKey) or return;
	local $/;	# Read in file in one shot
	my $content = <KEY>;
	close KEY;
	return \$content;
}

sub inspectLocalSshKeys { # Inspects the local SSH keys, bot Private & Public
	my ($privateKey, $publicKey) = @_;
	my ($keyType, $encrypted, $dek, $keylength, $keycomment, $fingerPrint);
	$keyType = $dek = $keylength = '';

	# Inspect the private key
	open(KEY, '<', $privateKey) or return ($keyType, $encrypted, $dek, $keylength);
	while (<KEY>) {
		/-+\s?BEGIN (\S+) PRIVATE KEY\s?-+/ && do {
			$keyType = $1;
			next;
		};
		/ENCRYPTED/ && do {
			$encrypted = 1;
			next;
		};
		/DEK-Info: ([^,]+),/ && do {
			$dek = $1;
			last;
		};
	}
	close KEY;
	$encrypted = 0 unless $encrypted;

	# Inspect the public key
	my $publicKeyContent = readSshPublicKeyFile($publicKey) or return ($keyType, $encrypted, $dek, $keylength);
	(undef, undef, $keylength, $keycomment, undef, $fingerPrint) = @{inspectSshPublicKeys($publicKeyContent)->[0]};

	return ($keyType, $encrypted, $dek, $keylength, $keycomment, $fingerPrint);
}


sub deleteSshKnownHostEntry { # Delete an entry in the known_hosts file
	my ($db, $hostname) = @_;
	my $term_io = $db->[2];
	my $knownhosts;
	my $retVal = 0;
	$hostname =~ s/([\[\]])/\\$1/g; # Prep regex for [host]:port => \[host\]:port

	# Put an exclusive lock
	my $dummyOpen = open(DUMMYKH, '>', $term_io->{KnownHostsDummy});
	flock(DUMMYKH, 2) if $dummyOpen; # 2 = LOCK_EX; Put an exclusive lock on the file as we are modifying it below
	# Read in entire file contents
	open(KHOSTS, '<', $term_io->{KnownHostsFile}) or return;
	local $/;	# Read in file in one shot
	$knownhosts = <KHOSTS>;
	close KHOSTS;

	# Remove entry
	if ($knownhosts =~ s/^(?:.+[ ,])?$hostname[ ,].+\n//igm) { # Entry found and removed (all matching lines)
		# Re-write modified file
		open(KHOSTS, '>', $term_io->{KnownHostsFile}) or return;
		print KHOSTS $knownhosts;
		close KHOSTS;
		$retVal = 1;
	}
	close DUMMYKH if $dummyOpen; # This will release the above flock
	return $retVal;
}


sub clenseSshKnownHostFile { # Tries to clean up a corrupted known_hosts file and to remove any case-sensitive duplicate entries
	my $db = shift;
	my $term_io = $db->[2];
	my (@khosts, %khostsHash);
	my ($duplicate, $corrupted, $modified) = (0,0,0);

	my $recordEntry = sub { # Adds entry to array and hash
		my ($host, $entry, $original) = @_;
		if ($khostsHash{$host}) { # Duplicate
			$duplicate++;
		}
		else { # New entry to record
			push(@khosts, $host);
			$khostsHash{$host} = $entry;
			$modified++ if $entry ne $original;
		}
	};

	# Read in known-hosts and add valid & non-duplicate entries to list + hash
	my $dummyOpen = open(DUMMYKH, '<', $term_io->{KnownHostsDummy}) if -e $term_io->{KnownHostsDummy};
	flock(DUMMYKH, 1) if $dummyOpen; # 1 = LOCK_SH; Put a shared lock on the file (wait to read if it's being changed)
	open(KHOSTS, '<', $term_io->{KnownHostsFile}) or return;
	while (<KHOSTS>) {
		my $entry = $_;
		(/^(\d+(?:\.\d+){3})\h/ || /^(\[\d+(?:\.\d+){3}\]:\d+)\h/) && do { # ipv4 or [ipv4]:port
			my $host = $1;
			&$recordEntry($host, $entry, $_);
			next;
		};
		$entry =~ s/^([\da-fA-F]{1,4}:(?::?[\da-fA-F]{1,4}){1,7}(?:::)?)(?=\h)/compactIPv6($1)/e && do { # ipv6  - also uppercase as we will correct this
			my $host = compactIPv6($1);
			&$recordEntry($host, $entry, $_);
			next;
		};
		$entry =~ s/^\[\K([\da-fA-F]{1,4}:(?::?[\da-fA-F]{1,4}){1,7}(?:::)?)(?=\]:(\d+)\h)/compactIPv6($1)/e && do { # [ipv6]:port - also uppercase as we will correct this
			my $host = "[" . compactIPv6($1) . "]:" . $2;
			&$recordEntry($host, $entry, $_);
			next;
		};
		$entry =~ s/^([a-zA-Z\d-]{1,63}(?:\.[a-zA-Z\d-]{1,63})*)(?=\h)/lc($1)/e && length($1) <= 253 && do { # hostname - also uppercase as we will correct this
			my $host = lc $1;
			&$recordEntry($host, $entry, $_);
			next;
		};
		$entry =~ s/^\[\K([a-zA-Z\d-]{1,63}(?:\.[a-zA-Z\d-]{1,63})*)(?=\]:(\d+)\h)/lc($1)/e && length($1) <= 253 && do { # [hostname]:port - also uppercase as we will correct this
			my $host = "[" . lc $1 . "]:" . $2;
			&$recordEntry($host, $entry, $_);
			next;
		};
		$corrupted++;
	}
	close KHOSTS;
	close DUMMYKH if $dummyOpen; # Release the flock

	if ($duplicate || $corrupted) { # Only if we found things to correct
		# Re-write modified file
		my $dummyOpen = open(DUMMYKH, '>', $term_io->{KnownHostsDummy});
		flock(DUMMYKH, 2) if $dummyOpen; # 2 = LOCK_EX; Put an exclusive lock on the file as we are modifying it
		open(KHOSTS, '>', $term_io->{KnownHostsFile}) or return;
		for my $host (@khosts) {
			print KHOSTS $khostsHash{$host};
		}
		close KHOSTS;
		close DUMMYKH if $dummyOpen; # This will release the above flock
	}
	return ($duplicate, $corrupted, $modified);
}


sub readSshKnownHosts { # Reads in all the known hosts from known_hosts file
	my $db = shift;
	my $term_io = $db->[2];
	my (@knownhosts, $marker, $hostname, $type, $key, $comment, $length, $fingerprint);

	my $dummyOpen = open(DUMMYKH, '<', $term_io->{KnownHostsDummy}) if -e $term_io->{KnownHostsDummy};
	flock(DUMMYKH, 1) if $dummyOpen; # 1 = LOCK_SH; Put a shared lock on the file (wait to read if it's being changed)
	open(KHOSTS, '<', $term_io->{KnownHostsFile}) or return;
	while (<KHOSTS>) {
		next if /^#/;	# Comment lines 
		/^(\@\S+)\s+(\S+)\s+(\S+)\s+(\S+)(?:\s+(.+))?$/ && do { # Line with optinal @markers
			($marker, $hostname, $type, $key, $comment) = ($1, $2, $3, $4, $5 || '');
			($type, $length, $fingerprint) = decodeSshKey(\$key);
			push(@knownhosts, [$hostname, $marker, $type, $length, $fingerprint, $comment]);
			next;
		};
		/^(\S+)\s+(\S+)\s+(\S+)(?:\s+(.+))?$/ && do { # Line without optinal @markers
			($hostname, $type, $key, $comment) = ($1, $2, $3, $4 || '');
			($type, $length, $fingerprint) = decodeSshKey(\$key);
			push(@knownhosts, [$hostname, '', $type, $length, $fingerprint, $comment]);
			next;
		};
	}
	close KHOSTS;
	close DUMMYKH if $dummyOpen; # Release the flock
	return \@knownhosts;
}


sub readDeviceSshKeys { # Dumps all the files containing ssh public keys on the switch and returns hash structure with them
	my $db = shift;
	my $host_io = $db->[3];
	my %sshkeys;

	# Get a directory listing of .ssh/
	my $sshpath = $host_io->{VOSS} ? '/intflash/.ssh' : '/flash/.ssh';
	$host_io->{CLI}->cmd("dir $sshpath");
	$host_io->{CLI}->poll( Poll_code => [\&cmdMessage, $db, "."] );
	unless ($host_io->{CLI}->cmd_poll && $host_io->{CLI}->last_cmd_success) {
		cmdMessage($db, "error!\n" . $host_io->{CLI}->last_cmd_errmsg . "\n");
		return;
	}
	my $outref = ($host_io->{CLI}->cmd_poll)[1];

	# See what ssh files exist, if any
	while ($$outref =~ /\.ssh\/((dsa|rsa)_key_([^_\s]+)(?:_ietf)?)\s*$/mg) {
		$sshkeys{$1}{type} = $2;
		$sshkeys{$1}{level} = $3;
	}

	# For each file found, dump it and record the keys within
	foreach my $sshfile (keys %sshkeys) {
		$host_io->{CLI}->cmd("more $sshpath/$sshfile");
		$host_io->{CLI}->poll( Poll_code => [\&cmdMessage, $db, "."] );
		unless ($host_io->{CLI}->cmd_poll && $host_io->{CLI}->last_cmd_success) {
			cmdMessage($db, "error!\n" . $host_io->{CLI}->last_cmd_errmsg . "\n");
			return;
		}
		$outref = ($host_io->{CLI}->cmd_poll)[1];
		$sshkeys{$sshfile}{keys} = inspectSshPublicKeys($outref);
	}
	# If no ssh files found, will return a defined ref to an undefined hash
	# If ssh files found, will return a defined ref to a defined hash
	# If there was an error, we would have already exited above with an undefined value
	return \%sshkeys;
}


sub ietfConvertSshKey { # Convert our local Public SSh key from openSSH format to IETF format
	my $publicKey = shift;
	my $ietfKey = '';

	debugMsg(1, "ietfConvertSshKey: public key to convert to IETF format :\n>", $publicKey, "<\n");
	$$publicKey =~ /^\S+ (\S+) (.+)$/ && do { # OpenSSH format (single line)
		my ($key, $comment) = ($1, $2);
		$ietfKey = "---- BEGIN SSH2 PUBLIC KEY ----\n";
		$ietfKey .= 'Comment: "' . $comment . '"' . "\n";
		while (my $line = substr($key, 0, 64, '')) {
			$ietfKey .= $line . "\n";
		}
		$ietfKey .= "---- END SSH2 PUBLIC KEY ----\n";
	};
	debugMsg(1, "ietfConvertSshKey: converted public key to IETF format :\n>", \$ietfKey, "<\n");
	return \$ietfKey;
}


sub determineSshStack { # Determines whether switch is VOSS with new Mocana SSH stack (introduced in VOSS 4.2)
	my $db = shift;
	my $term_io = $db->[2];
	my $host_io = $db->[3];

	return 0 unless $term_io->{AcliType}; # If PPCLI then it's the old SSH stack for sure..

	$host_io->{CLI}->cmd("show ssh global");
	$host_io->{CLI}->poll( Poll_code => [\&cmdMessage, $db, "."] );
	unless ($host_io->{CLI}->cmd_poll && $host_io->{CLI}->last_cmd_success) {
		cmdMessage($db, "error!\n" . $host_io->{CLI}->last_cmd_errmsg . "\n");
		return;
	}
	my $outref = ($host_io->{CLI}->cmd_poll)[1];
	return 1 if $$outref =~ /sftp enable/;	# New in the Mocana stack was SFTP support
	return 0; # Otherwise
}


sub deviceAddSshKey { # Add the local SSH public key to the requested switch .ssh/ file and requested format (ietf|openssh)
	my ($db, $file, $format, $publicKey) = @_;
	my $host_io = $db->[3];

	# Edit the SSH file (if it did not exist it will get created on exit)
	my $sshpath = $host_io->{VOSS} ? '/intflash/.ssh' : '/flash/.ssh';
	debugMsg(1, "deviceAddSshKey: adding our public key to switch file ", \$sshpath, " in $format format\n");
	$host_io->{CLI}->print("edit $sshpath/$file");
	$host_io->{CLI}->waitfor(
			Match 	=> '   0> $',
			Match	=> '   1> .*$',
			Errmode	=> 'return',
		);
	$host_io->{CLI}->poll( Poll_code => [\&cmdMessage, $db, "."] );
	unless ($host_io->{CLI}->waitfor_poll) {
		cmdMessage($db, "error!\nFailed to edit file $sshpath/$file\n");
		return;
	}

	# Enter edit mode, at the end of existing file contents (if file already existed)
	my $matched = ($host_io->{CLI}->waitfor_poll)[2];
	if ($matched =~ s/^   1> //) {
		$matched =~ s/\x08.*$//;
		$host_io->{CLI}->put('C');	# Replace existing 1st line
		$host_io->{CLI}->waitfor(	# New line
				Match	=> ' +\x08+$',
				Errmode	=> 'return',
			);
	}
	else {
		$matched = '';
		$host_io->{CLI}->put('o');	# Edit line below
		$host_io->{CLI}->waitfor(	# New line
				Match	=> '\d+> +\x08*$',
				Errmode	=> 'return',
			);
	}
	$host_io->{CLI}->poll( Poll_code => [\&cmdMessage, $db, "."] );
	unless ($host_io->{CLI}->waitfor_poll) {
		cmdMessage($db, "error!\nFailed to enter edit mode in file $sshpath/$file\n");
		return;
	}

	# Dump our SSH Public key into the file using requested format
	my $publicKeyInsert = $format eq 'ietf' ? ietfConvertSshKey($publicKey) : $publicKey;
	$host_io->{CLI}->put($$publicKeyInsert);
	$host_io->{CLI}->put($matched) if $matched;

	# Come out of file edit and save the file
	$host_io->{CLI}->put("\e");	# Exit edit mode
	$host_io->{CLI}->print('ZZ');	# Save and Exit
	$host_io->{CLI}->waitfor(	# Expect a new prompt
			Match	=> $host_io->{CLI}->prompt,
			Errmode	=> 'return',
		);
	$host_io->{CLI}->poll( Poll_code => [\&cmdMessage, $db, "."] );
	unless ($host_io->{CLI}->waitfor_poll) {
		cmdMessage($db, "error!\nFailed to exit editing of file $sshpath/$file\n");
		return;
	}
	return 1;
}


sub deviceSshKeyDelete { # Removes a specific SSH key within an SSH file on switch
	my ($db, $file, $sshkeys, $index) = @_;
	my $host_io = $db->[3];

	# Edit the already existing SSH file
	my $sshpath = $host_io->{VOSS} ? '/intflash/.ssh' : '/flash/.ssh';
	debugMsg(1, "deviceSshKeyDelete: removing key index $index from switch file ", \$sshpath, "\n");
	$host_io->{CLI}->print("edit $sshpath/$file");
	$host_io->{CLI}->waitfor(
			Match	=> '   1> .*$',
			Errmode	=> 'return',
		);
	$host_io->{CLI}->poll( Poll_code => [\&cmdMessage, $db, "."] );
	unless ($host_io->{CLI}->waitfor_poll) {
		cmdMessage($db, "error!\nFailed to edit file $sshpath/$file\n");
		return;
	}

	# Go to the line number corresponding to key index
	$host_io->{CLI}->put($sshkeys->{$file}->{keys}->[$index - 1]->[6] . 'G');
	$host_io->{CLI}->waitfor(	# New line
			Match	=> $sshkeys->{$file}->{keys}->[$index - 1]->[6] . '> .*$',
			Errmode	=> 'return',
		);
	$host_io->{CLI}->poll( Poll_code => [\&cmdMessage, $db, "."] );
	unless ($host_io->{CLI}->waitfor_poll) {
		cmdMessage($db, "error!\nFailed to edit line number corresponding to key index $index\n");
		return;
	}

	# Delete the key
	my $delLines = $sshkeys->{$file}->{keys}->[$index - 1]->[7] - $sshkeys->{$file}->{keys}->[$index - 1]->[6];
	$host_io->{CLI}->put($delLines . 'dd');
	$host_io->{CLI}->waitfor(	# New line
			Match	=> '\d+> .*$',
			Errmode	=> 'return',
		);
	$host_io->{CLI}->poll( Poll_code => [\&cmdMessage, $db, "."] );
	unless ($host_io->{CLI}->waitfor_poll) {
		cmdMessage($db, "error!\nFailed to delete key index $index\n");
		return;
	}

	# Come out of file edit and save the file
	$host_io->{CLI}->put("\e");	# Exit edit mode
	$host_io->{CLI}->print('ZZ');	# Save and Exit
	$host_io->{CLI}->waitfor(	# Expect a new prompt
			Match	=> $host_io->{CLI}->prompt,
			Errmode	=> 'return',
		);
	$host_io->{CLI}->poll( Poll_code => [\&cmdMessage, $db, "."] );
	unless ($host_io->{CLI}->waitfor_poll) {
		cmdMessage($db, "error!\nFailed to exit editing of file $sshpath/$file\n");
		return;
	}
	return 1;
}


sub deviceDeleteSshFile { # Deletes the provided SSH file on switch
	my ($db, $file) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];

	# Delete the requested .ssh/file
	my $sshpath = $host_io->{VOSS} ? '/intflash/.ssh' : '/flash/.ssh';
	my $delCmd = $term_io->{AcliType} ? 'delete' : 'rm';
	$host_io->{CLI}->cmd("$delCmd $sshpath/$file -y");
	$host_io->{CLI}->poll( Poll_code => [\&cmdMessage, $db, "."] );
	unless ($host_io->{CLI}->cmd_poll && $host_io->{CLI}->last_cmd_success) {
		cmdMessage($db, "error!\n" . $host_io->{CLI}->last_cmd_errmsg . "\n");
		return;
	}
	return 1;
}


sub verifySshHostKey { # Check host key against known_hosts file during connect
	my ($db, $cli) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $ssh2 = $cli->parent;
	my $kh = $ssh2->known_hosts;
	my ($ok, $actionUpdateKey, $actionDisconnect);

	import Net::SSH2 qw( :all ); # Need to import Net::SSH2's LIBSSH2 constants

	if ($term_io->{KnownHostsFile}) { # We already located it
		# Net::SSH2::KnownHosts method readfile() does not perforn any flock; so we do it instead on a dummy file
		my $dummyOpen = open(DUMMYKH, '<', $term_io->{KnownHostsDummy}) if -e $term_io->{KnownHostsDummy};
		flock(DUMMYKH, 1) if $dummyOpen; # 1 = LOCK_SH; Put a shared lock on the file (wait to read if it's being changed)
		$ok = eval {
			$kh->readfile($term_io->{KnownHostsFile});
		};
		close DUMMYKH if $dummyOpen; # Release the flock
		unless (defined $ok || $ssh2->error == &LIBSSH2_ERROR_FILE) {
			printOut($script_io, "\n$ScriptName: Unable to read SSH file $term_io->{KnownHostsFile}\n");
			return (undef, ($ssh2->error)[2] );
		}
	}
	else { # We have not yet located / chosen one
		foreach my $path (@SshKeyPath) {
			my $known_hosts = File::Spec->canonpath("$path/$KnownHostsFile");
			my $dummyFile = File::Spec->canonpath("$path/$KnownHostsDummy"); # In same path as real known_hosts file
			# Net::SSH2::KnownHosts method readfile() does not perforn any flock; so we do it instead on a dummy file
			my $dummyOpen = open(DUMMYKH, '<', $dummyFile) if -e $dummyFile;
			flock(DUMMYKH, 1) if $dummyOpen; # 1 = LOCK_SH; Put a shared lock on the file (wait to read if it's being changed)
			$ok = eval {
				$kh->readfile($known_hosts);
			};
			close DUMMYKH if $dummyOpen; # Release the flock
			unless (defined $ok || $ssh2->error == &LIBSSH2_ERROR_FILE) {
				printOut($script_io, "\n$ScriptName: Unable to read SSH file $known_hosts\n");
				return (undef, ($ssh2->error)[2] );
			}
			if ($ok) { # We have our known_hosts file
				$term_io->{KnownHostsFile} = $known_hosts;
				$term_io->{KnownHostsDummy} = $dummyFile;
				last;
			}
		}
	}

	my $hostname = $cli->port == 22 ? compactIPv6($cli->host) : '['.compactIPv6($cli->host).']:'.$cli->port;
	my ($key, $type) = $ssh2->remote_hostkey;
	#  $flags = ( LIBSSH2_KNOWNHOST_TYPE_PLAIN | LIBSSH2_KNOWNHOST_KEYENC_RAW | (($type + 1) << LIBSSH2_KNOWNHOST_KEY_SHIFT) ); # Not exported by Net::SSH2
	my $flags = (                            1 |                    (1 << 16) | (($type + 1) <<                          18) );
	$host_io->{SshKeySrvFingPr} = join(' ', decodeSshKey(\$key, 1));
	my $pad = ' ' x length($ScriptName);

	my $check = $term_io->{KnownHostsFile} ? $kh->check(compactIPv6($cli->host), $cli->port, $key, $flags) : 2;
	# If there is no known_hosts file, then the check equates to 2 = LIBSSH2_KNOWNHOST_CHECK_NOTFOUND
	if ($check == 0) { # LIBSSH2_KNOWNHOST_CHECK_MATCH
		$host_io->{SshKnownHost} = 'verified';
		return 1;
	}
	elsif ($check == 1) { # LIBSSH2_KNOWNHOST_CHECK_MISMATCH
		printOut($script_io, "\n$ScriptName: Host SSH key verification failed in $KnownHostsFile file, the key has changed!\n");
		printOut($script_io, "$ScriptName: SSH Server key fingerprint is: $host_io->{SshKeySrvFingPr}\n");
		if ($Default{ssh_known_hosts_key_changed_val} == 1) {
			printOut($script_io, "$ScriptName: Press 'Y' to trust host and update key in $KnownHostsFile file\n");
			printOut($script_io, "$pad  Press 'O' to connect once without updating the key in $KnownHostsFile file\n");
			printOut($script_io, "$pad  Press any other key to abort the connection\nChoice : ");
			my $key = readKey;
			printOut($script_io, "$key\n");
			$cli->{POLL}{endtime} = time + $cli->{POLL}{timeout}; # Try and reset the Control::CLI::connect timeout
			if ($key eq 'Y') {
				$actionUpdateKey = 1 ;
			}
			elsif ($key eq 'O') {
				$host_io->{SshKnownHost} = 'failed-connect-once';
				return 1;
			}
			else {
				$actionDisconnect = 1;
			}
		}
		elsif ($Default{ssh_known_hosts_key_changed_val} == 2) {
			$actionUpdateKey = 1;
		}
		else { # ssh_known_hosts_key_changed_val == 0
			$actionDisconnect = 1;
		}
		if ($actionUpdateKey) {
			return (undef, "Unable to update host SSH key in $KnownHostsFile file") unless deleteSshKnownHostEntry($db, $hostname);
		}
		if ($actionDisconnect) {
			return (undef, "Host SSH key verification failed, the key has changed!");
		}
	}
	elsif ($check == 2) { # LIBSSH2_KNOWNHOST_CHECK_NOTFOUND
		unless ($Default{ssh_known_hosts_key_missing_val} == 2) {
			printOut($script_io, "\n$ScriptName: Host SSH key verification failed in $KnownHostsFile file, the key is missing!\n");
			printOut($script_io, "$ScriptName: SSH Server key fingerprint is: $host_io->{SshKeySrvFingPr}\n");
		}
		if ($Default{ssh_known_hosts_key_missing_val} == 0) {
			$actionDisconnect = 1;
		}
		elsif ($Default{ssh_known_hosts_key_missing_val} == 1) {
			printOut($script_io, "$ScriptName: Press 'Y' to trust host and add key in $KnownHostsFile file\n");
			printOut($script_io, "$pad  Press 'O' to connect once without adding the key to $KnownHostsFile file\n");
			printOut($script_io, "$pad  Press any other key to abort the connection\nChoice : ");
			my $key = readKey;
			printOut($script_io, "$key\n");
			$cli->{POLL}{endtime} = time + $cli->{POLL}{timeout}; # Try and reset the Control::CLI::connect timeout
			if ($key eq 'O') {
				$host_io->{SshKnownHost} = 'failed-connect-once';
				return 1;
			}
			elsif ($key ne 'Y') {
				$actionDisconnect = 1;
			}
		}
		# ssh_known_hosts_key_missing_val == 2, fall through
		if ($actionDisconnect) {
			return (undef, "Host SSH key verification failed, the key is missing!");
		}
	}
	else { # $check == 3  LIBSSH2_KNOWNHOST_CHECK_FAILURE (or $check value outside 0,1,2,3)
		printOut($script_io, "\n$ScriptName: Host SSH key verification failed in $KnownHostsFile file, unknown reason...\n");
		printOut($script_io, "$ScriptName: SSH Server key fingerprint is: $host_io->{SshKeySrvFingPr}\n");
		return (undef, "Host SSH key verification failed, unknown reason");
	}

	# If we get here, we don't have this host in our known hosts file (or it existed but we deleted it above), so we can now add/update it

	unless (-e $SshKeyPath[0] && -d $SshKeyPath[0]) { # Create base .ssh directory if not existing
		mkdir $SshKeyPath[0] or do {
			printOut($script_io, "\n$ScriptName: SSH $KnownHostsFile; unable to create directory $SshKeyPath[0]\n");
			$host_io->{SshKnownHost} = 'failure';
			return 1; # Exit success, we don't want to prevent the connection
		};
		debugMsg(1, "verifySshHostKey: Created directory:\n ", \$SshKeyPath[0], "\n");
	}
	unless ($term_io->{KnownHostsFile}) { # Set the known_hosts file (which will be created below)
		$term_io->{KnownHostsFile} = File::Spec->canonpath("$SshKeyPath[0]/$KnownHostsFile");
		$term_io->{KnownHostsDummy} = File::Spec->canonpath("$SshKeyPath[0]/$KnownHostsDummy"); # In same path as real known_hosts file
		printOut($script_io, "\n$ScriptName: Creating SSH Known Hosts file: $term_io->{KnownHostsFile}");
	}

	# Net::SSH2::KnownHosts method writefile() does not perforn any flock; so we perform flock on a dummy file instead
	my $dummyOpen = open(DUMMYKH, '>', $term_io->{KnownHostsDummy}); # Should this fail, we'll let $kh->writefile fail directly
	flock(DUMMYKH, 2) if $dummyOpen; # 2 = LOCK_EX; Put an exclusive lock; this will block other ACLI instances from calling $kh->writefile below

	# We reload the knownhosts file again, just before adding the new host; this is because there might be other instances trying to update it at the same time
	$kh = $ssh2->known_hosts; # Re-init the object
	# Re-load the file
	$ok = eval {
		$kh->readfile($term_io->{KnownHostsFile});
	};
	unless (defined $ok || $ssh2->error == &LIBSSH2_ERROR_FILE) {
		close DUMMYKH if $dummyOpen; # This will release the above flock
		return (undef, "Unable to re-read SSH file $term_io->{KnownHostsFile} after deleting old host key from it");
	}
	# Add the new key
	$ok = eval {
		$kh->add($hostname, '', $key, "$ScriptName v$VERSION", $flags);
		$kh->writefile($term_io->{KnownHostsFile});
	};
	close DUMMYKH if $dummyOpen; # This will release the above flock
	if ($ok) {
		if ($actionUpdateKey) {
			printOut($script_io, "\n$ScriptName: Updated SSH host key in $KnownHostsFile file\n");
		}
		else {
			printOut($script_io, "\n$ScriptName: Added SSH host key to $KnownHostsFile file\n");
		}
	}
	else {
		printOut($script_io, "\n$ScriptName: Unable to update SSH $KnownHostsFile file: " . ($ssh2->error)[2]);
	}
	$host_io->{SshKnownHost} = $actionUpdateKey ? 'updated' : 'added';
	return 1;
}

1;
