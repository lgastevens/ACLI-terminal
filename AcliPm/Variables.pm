# ACLI sub-module
package AcliPm::Variables;
our $Version = "1.06";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(loadVarFile saveVarFile setvar printVar assignVar derefVarSection derefConditionSection
			 variablesCaptureValues variablesStoreValues processVarCapInput derefVariables echoVarReplacement
			 replaceAttribute);
}
use Cwd;
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::Alias;
use AcliPm::DebugMessage;
use AcliPm::GeneratePortListRange;
use AcliPm::GlobalDefaults;
use AcliPm::GlobalDeviceSettings;
use AcliPm::GlobalMatchingPatterns;
use AcliPm::MaskUnmaskChars;
use AcliPm::Print;
use AcliPm::Prompt;
use AcliPm::QuotesRemove;
use AcliPm::Socket;


my $VarPrintSpacing = 18;

sub by_type { # Sort function for listing $variable{} hash keys
	my $compareResult;
	if ($a =~ /\d+(?:\.\d+){3}/ && $b =~ /\d+(?:\.\d+){3}/) { # IPv4 addr
		my @a = split('\.', $a); # dot needs to be backslashed..
		my @b = split('\.', $b);
		for my $i (0 .. 3) {
			$compareResult = $a[$i] <=> $b[$i];
			last if $compareResult;
		}
		return $compareResult;
	}
	elsif ($a =~ /[\da-f]\{,2}(?::[\da-f]\{,2}){7}/i && $b =~ /[\da-f]\{,2}(?::[\da-f]\{,2}){7}/i) { # IPv6 addr
		my @a = split(':', $a);
		my @b = split(':', $b);
		for my $i (0 .. 7) {
			$compareResult = sprintf("%02s", $a[$i]) cmp sprintf("%02s", $b[$i]);
			last if $compareResult;
		}
		return $compareResult;
	}
	elsif ($a =~ /\d+[\/:]\d+(?:[\/:]\d+)?/ && $b =~ /\d+[\/:]\d+(?:[\/:]\d+)?/) { # Slot/Port[/Chan]
		my @a = split(/[\/:]/, $a);
		my @b = split(/[\/:]/, $b);
		for (my $i = 0; $i <= $#a || $i <= $#b; $i++) {
			if (defined $a[$i] && defined $b[$i]) {
				$compareResult = $a[$i] <=> $b[$i];
			}
			else {
				$compareResult = defined $a[$i] ? 1 : -1;
			}
			last if $compareResult;
		}
		return $compareResult;
	}
	elsif ($a =~ /^\d+$/ && $b =~ /^\d+$/) { # Number
		$compareResult = $a <=> $b;
	}
	else { # Text
		$compareResult = $a cmp $b;
	}
}


sub loadVarFile { # Reads a variables file for MAC provided and populate $vars structure
	my ($db, $connectSameMac) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $socket_io = $db->[6];
	my $prompt = $db->[7];
	my $vars = $db->[12];
	my ($varFile, $varFileName);

	return unless defined $host_io->{BaseMAC} || $term_io->{PseudoTerm}; # Can't go further if no Base MAC or PseudoTerm

	if ($term_io->{PseudoTerm}) { # Expected variable filename with PseudoTerm
		if ($term_io->{PseudoTermName} =~ /^\d+$/) {
			$varFileName = 'pseudo';
			$varFileName .= $term_io->{PseudoTermName} if $term_io->{PseudoTermName} < 100;
			$varFileName .= $VarFileExt;
		}
		else { # New format
			$varFileName = 'pseudo.' . $term_io->{PseudoTermName} . $VarFileExt;
		}
	}
	else { # Expected variable filename otherwise
		$varFileName = $host_io->{BaseMAC} . $VarFileExt; # Expected variable filename
	}

	# Try and find a matching variable file in the paths available
	foreach my $path (@VarFilePath) {
		if (-e "$path/$varFileName") {
			$varFile = "$path/$varFileName";
			last;
		}
	}
	unless ($varFile) {
		$host_io->{VarsFile} = '';
		return;
	}

	$host_io->{VarsFile} = File::Spec->canonpath($varFile); # Update display path
	return if $connectSameMac; # In this case, we come out after just updating $host_io->{VarsFile} (bug26)

	# We should have a variable file to work with now
	debugMsg(1, "VarFileRead: Loading file:\n ", \$varFile, "\n");
	cmdMessage($db, "$ScriptName: ") if defined $connectSameMac;
	cmdMessage($db, "Loading var file $host_io->{VarsFile}\n");

	%$vars = (); # Clear the vars structure to start with

	my $lineNumber = 0;
	open(VARFILE, '<', $varFile) or return;
	flock(VARFILE, 1); # 1 = LOCK_SH; Put a shared lock on the file (wait to read if it's being changed)
	while (<VARFILE>) {
		chomp;
		$lineNumber++;
		next if /^\s*$/; # skip empty lines
		next if /^\s*#/; # skip comment lines
		next if /^\s*\$[_%]\s*=/; # Skip $_ & $% (if they were saved in versions 0.70 or earlier)
		(/^\s*\$($VarUser)\s*=\s*(\'[^\']*\'|\"[^\"]*\"|.*?)\s*$/o) && do { # Stored variable
			assignVar($db, '', $1, '=', $2);
			next;
		};
		(/^\s*\$($VarScript)\[\]\s*=\s*(.*?)\s*$/o) && do { # Stored list
			assignVar($db, 'list', $1, '=', $2);
			next;
		};
		(/^\s*\$($VarScript)\{\}\s*=\s*(.*?)\s*$/o) && do { # Stored hash
			assignVar($db, 'hash', $1, '=', $2);
			next;
		};
		(/^\s*\{(\w+)\}\s*=\s*(.*?)\s*$/o) && do { # Stored pseudo attribute
			next unless $term_io->{PseudoTerm};
			$term_io->{PseudoAttribs}->{$1} = $2;
			next;
		};
		/^\s*:wd\s*=\s*(.+?)\s*$/ && do {
			chdir $1 unless $term_io->{PathSetSwitch};
			next;
		};
		/^\s*:socket-disable$/ && do {
			next if $term_io->{SockSetSwitch};
			$term_io->{SocketEnable} = 0;
			next;
		};
		/^\s*:sockets\s*=\s*(.+?)\s*$/ && do {
			next if $term_io->{SockSetSwitch};
			next unless $term_io->{SocketEnable};
			my ($success, @failedSockets) = openSockets($socket_io, split(',', $1));
			if (!$success) {
				cmdMessage($db, " " x length("$ScriptName: ")) if defined $connectSameMac;
				cmdMessage($db, "Unable to allocate socket numbers\n");
			}
			elsif (@failedSockets) {
				cmdMessage($db, " " x length("$ScriptName: ")) if defined $connectSameMac;
				cmdMessage($db, "Failed to create sockets: " . join(', ', @failedSockets) . "\n");
			}
			next;
		};
		/^\s*:prompt\s*=\s*(.+?)\s*$/ && do {
			next unless $term_io->{PseudoTerm};
			$host_io->{Prompt} = $prompt->{Match} = $1;
			$prompt->{Regex} = qr/($prompt->{Match})/;
			next;
		};
		/^\s*:cmdecho\s*=\s*(.+?)\s*$/ && do {
			next unless $term_io->{PseudoTerm};
			$term_io->{PseudoTermEcho} = $1;
			next;
		};
		/^\s*:port-model\s*=\s*(.*?)\s*$/ && do {
			next; # Was once supported in pseudo mode; no longer, we ignore it
		};
		/^\s*:port-range\s*=\s*(.+?)\s*$/ && do {
			next unless $term_io->{PseudoTerm};
			next if $1 =~ /^\d$/;	# We no longer use the old syntax of this key
			my ($slotRef, $portRef) = manualSlotPortStruct($1);
			if (defined $portRef) {
				$host_io->{Slots} = $slotRef;
				$host_io->{Ports} = $portRef;
				$term_io->{PseudoAttribs}->{slots} = $slotRef;
				$term_io->{PseudoAttribs}->{ports} = $portRef;
			}
			next;
		};
		/^\s*:family-type\s*=\s*(.+?)\s*$/ && do {
			next unless $term_io->{PseudoTerm};
			$host_io->{Type} = $1 if exists $DevicePortRange{$1};
			next;
		};
		/^\s*:acli-type\s*=\s*([01])\s*$/ && do {
			next unless $term_io->{PseudoTerm};
			$term_io->{AcliType} = $1;
			next;
		};
		debugMsg(1, "VarFileRead: Syntax error on line $lineNumber while reading alias file:\n ", \$varFile, "\n");
		close VARFILE;
		return;
	}
	close VARFILE;
	%{$host_io->{UnsavedVars}} = ();
	return 1;
}


sub saveVarFile { # Saves a variables file for MAC provided
	my ($db, $saveVars, $saveSockets, $saveWorkDir) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $socket_io = $db->[6];
	my $vars = $db->[12];
	my ($varFile, $varFileName);

	return unless defined $host_io->{BaseMAC} || $term_io->{PseudoTerm}; # Can't go further if no Base MAC or PseudoTerm
	$saveVars = scalar keys %$vars && $saveVars; # Can only save variable if we have some
	$saveSockets = scalar keys %{$socket_io->{ListenSockets}} && $saveSockets; # Can only save sockets if we have some

	if ($term_io->{PseudoTerm}) { # Expected variable filename with PseudoTerm
		if ($term_io->{PseudoTermName} =~ /^\d+$/) {
			$varFileName = 'pseudo';
			$varFileName .= $term_io->{PseudoTermName} if $term_io->{PseudoTermName} < 100;
			$varFileName .= $VarFileExt;
		}
		else { # New format
			$varFileName = 'pseudo.' . $term_io->{PseudoTermName} . $VarFileExt;
		}
	}
	else { # Expected variable filename otherwise
		$varFileName = $host_io->{BaseMAC} . $VarFileExt; # Expected variable filename
	}

	unless (-e $AcliFilePath[0] && -d $AcliFilePath[0]) { # Create base directory if not existing
		mkdir $AcliFilePath[0] or return;
		debugMsg(1, "VarFileSave: Created directory:\n ", \$AcliFilePath[0], "\n");
	}
	unless (-e $VarFilePath[0] && -d $VarFilePath[0]) { # Create base directory if not existing
		mkdir $VarFilePath[0] or return;
		debugMsg(1, "VarFileSave: Created directory:\n ", \$VarFilePath[0], "\n");
	}
	$varFile = join('', $VarFilePath[0], '/', $varFileName);
	$host_io->{VarsFile} = File::Spec->canonpath($varFile); # Update display path
	# We should have a variable file to work with now

	debugMsg(1, "VarFileSave: Saving file:\n ", \$varFile, "\n");

	open(VARFILE, '>', $varFile) or return;
	flock(VARFILE, 2); # 2 = LOCK_EX; Put an exclusive lock on the file as we are modifying it
	my $timestamp = localtime;
	print VARFILE "# $ScriptName saved on $timestamp\n";
	if ($term_io->{PseudoTerm}) {
		print VARFILE "# Pseudo Terminal    : ", $term_io->{PseudoTermName}, "\n\n";
	}
	else {
		print VARFILE "# Device base MAC    : ", $host_io->{BaseMAC}, "\n";
		print VARFILE "# Device sysname     : ", $host_io->{Sysname}, "\n";
		print VARFILE "# Device ip/hostname : ", $host_io->{Name}, "\n\n";
	}
	if ($term_io->{PseudoTerm}) {
		printf VARFILE "%-${VarPrintSpacing}s = %s\n", ":prompt", $host_io->{Prompt};
		printf VARFILE "%-${VarPrintSpacing}s = %s\n", ":cmdecho", $term_io->{PseudoTermEcho};
		printf VARFILE "%-${VarPrintSpacing}s = %s\n", ":family-type", $host_io->{Type};
		printf VARFILE "%-${VarPrintSpacing}s = %s\n", ":acli-type", $term_io->{AcliType};
		printf VARFILE "%-${VarPrintSpacing}s = %s\n", ":port-range", generateRange($db, scalar generatePortList($host_io, 'ALL'), $DevicePortRange{$host_io->{Type}}) if exists $term_io->{PseudoAttribs}->{ports};
	}
	printf VARFILE "%-${VarPrintSpacing}s = %s\n", ":wd", File::Spec->rel2abs(cwd) if $saveWorkDir;
	if ($saveSockets) {
		printf VARFILE "%-${VarPrintSpacing}s = %s\n", ":sockets", join(',', keys %{$socket_io->{ListenSockets}}) if $term_io->{SocketEnable};
		printf VARFILE ":socket-disable\n" if !$term_io->{SocketEnable};
	}
	if ($term_io->{PseudoTerm} && %{$term_io->{PseudoAttribs}}) {
		foreach my $key (keys %{$term_io->{PseudoAttribs}}) {
			next if ref($term_io->{PseudoAttribs}->{$key});
			printf VARFILE "%-${VarPrintSpacing}s = %s\n", "{$key}", $term_io->{PseudoAttribs}->{$key};
		}
	}
	if ($saveVars) {
		foreach my $var (keys %$vars) {
			next if $vars->{$var}->{nosave}; # Dont save $_ or $%
			next if $vars->{$var}->{myscope};
			next if $vars->{$var}->{dictscope};
			print VARFILE printVar($db, $var);
			$vars->{$var}->{script} = undef if $vars->{$var}->{script};
		}
	}
	close VARFILE;
	%{$host_io->{UnsavedVars}} = ();
	return 1;
}


sub setvar { # Assigns value (and flags) to a variable
	my ($db, $var, $value) = (shift, shift, shift);
	my %flags = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $vars = $db->[12];
	my $varscope = $db->[15];
	my $dictscope= $db->[17];

	# Automatically set nosave flag for $_, $%, $* $1-9
	$flags{nosave} = 1 if $var =~ /^[_\*\%\d]$/;

	# Set myscope/dictscope flag
	if ($dictscope->{varnames}->{$var}) { # If exact name is there
		$flags{dictscope} = 1;
	}
	else { # Try wildcards
		foreach my $wc (@{$dictscope->{wildcards}}) {
			if ($var =~ /^$wc$/) {
				debugMsg(1, "setvar: $var dictscope wildcard match with: ", \$wc, "\n");
				$flags{dictscope} = 1;
				last;
			}
		}
	}
	unless ($flags{dictscope}) { # Dictscope takes precedence over myscope
		if ($varscope->{varnames}->{$var}) { # If exact name is there
			$flags{myscope} = 1;
		}
		else { # Try wildcards
			foreach my $wc (@{$varscope->{wildcards}}) {
				if ($var =~ /^$wc$/) {
					debugMsg(1, "setvar: $var myscope wildcard match with: ", \$wc, "\n");
					$flags{myscope} = 1;
					last;
				}
			}
		}
	}

	# Myscope flag can only be set on newly defined variables; but can be reset if var is assigned to outside of scripting mode
	# if var not defined, leave myscope as requested (leave as is)
	# if var is already defined, then:
	# - if requested myscope is the same as var's myscope, ignore (leave as is)
	# * if requested myscope is not set but var's myscope is already set and we are in script mode => SET myscope (sync it)
	# - if requested myscope is not set but var's myscope is already set and we are not in script mode => do not set myscope (leave as is)
	# * if requested myscope is set (@my: we can only be in script mode) but var's myscope is not set => RESET myscope (sync it)
	$flags{myscope} = $vars->{$var}->{myscope} if defined $vars->{$var} && ( (!$flags{myscope} && $vars->{$var}->{myscope} && $flags{script}) || ($flags{myscope} && !$vars->{$var}->{myscope}) );

	# Do not set the script flag to already existing (not script flagged) variables
	$flags{script} = undef if $flags{script} && defined $vars->{$var} && !$vars->{$var}->{script};

	# Type is set to empty string unless specified as 'list' or 'hash'
	$flags{type} = '' unless defined $flags{type};

	if ($flags{append}) { # Append new value
		$vars->{$var}->{value} .= ',' . $value;
		debugMsg(1, "setvar: $var append: ", \$value, "\n");
		delete $flags{append};
	}
	else { # Set new value
		$vars->{$var}->{value} = $value;
		debugMsg(1, "setvar: $var = ", \$value, "\n");
	}

	unless ($flags{nosave} || $flags{myscope} || $flags{dictscope}) {	# Update unsaved flag
		$host_io->{UnsavedVars}->{$var} = 1;
		debugMsg(1, "setvar: UnsavedVars set\n");
	}

	# Set the other flags for the variable
	foreach my $flag (keys %flags) { # Any other flags are added to structure
		$vars->{$var}->{$flag} = $flags{$flag};
		debugMsg(1, "setvar: $var flag $flag => ", \$flags{$flag}, "\n");
	}
}


sub printVar { # Returns printable string of variable value
	my ($db, $var, $mode, $koi) = @_;
	$mode = '' unless defined $mode;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $vars = $db->[12];
	my $value;

	if ($var =~ /^$VarSlotAll$/) { # # $ALL, $1/ALL, $2:ALL, etc...
		my $portList = generatePortList($host_io, $var);
		if ($mode eq 'size') {
			$value = scalar split(',', $portList);
			$var = "#$var";
		}
		else {
			$value = $portList;
		}
	}
	elsif (!defined $vars->{$var}) {
		return sprintf "%-${VarPrintSpacing}s = <undefined>\n", "\$$var"
	}
	elsif ($vars->{$var}->{type} eq 'list') {
		if ($mode eq 'size') {
			if (defined $koi) {
				$value = scalar split(',', $vars->{$var}->{value}->[$koi - 1]);
				$koi = scalar @{$vars->{$var}->{value}} if $koi == 0;
				$var = "#$var\[$koi\]";
			}
			else {
				$value = scalar @{$vars->{$var}->{value}};
				$var = "#$var";
			}
		}
		else {
			if (defined $koi) {
				$value = $vars->{$var}->{value}->[$koi - 1];
				$value = '<undefined>' unless defined $value;
				$koi = scalar @{$vars->{$var}->{value}} if $koi == 0;
				$var .= "[$koi]";
			}
			else {
				my @list;
				foreach $value (@{$vars->{$var}->{value}}) {
					push(@list, $mode eq 'raw' ? $value : generateRange($db, defined $value ? $value : '', $DevicePortRange{$host_io->{Type}} || $term_io->{DefaultPortRng}));
				}
				return sprintf "%-${VarPrintSpacing}s = (%s)\n", "\$$var\[\]", join('; ', @list);
			}
		}
	}
	elsif ($vars->{$var}->{type} eq 'hash') {
		if ($mode eq 'size') {
			if (defined $koi) {
				$value = scalar split(',', $vars->{$var}->{value}->{$koi});
				$var = "#$var\{$koi\}";
			}
			else {
				$value = scalar keys %{$vars->{$var}->{value}};
				$var = "#$var";
			}
		}
		else {
			if (defined $koi) {
				$value = $vars->{$var}->{value}->{$koi};
				$value = '<undefined>' unless defined $value;
				$var .= "{$koi}";
			}
			else {
				my @list;
				foreach my $key (sort by_type keys %{$vars->{$var}->{value}}) {
					$value = $vars->{$var}->{value}->{$key};
					push(@list, $key . '=>' . ($mode eq 'raw' ? $value : generateRange($db, defined $value ? $value : '', $DevicePortRange{$host_io->{Type}} || $term_io->{DefaultPortRng})));
				}
				return sprintf "%-${VarPrintSpacing}s = (%s)\n", "\$$var\{\}", join('; ', @list);
			}
		}
	}
	else { # Normal variable
		if ($mode eq 'size') {
			$value = scalar split(',', $vars->{$var}->{value});
			$var = "#$var";
		}
		else {
			$value = $vars->{$var}->{value};
		}
	}
	if ($value =~ /^\s+/ || $value =~ /\s+$/ || $value eq '') {
		return sprintf "%-${VarPrintSpacing}s = '%s'\n", "\$$var", $value;
	}
	else {
		return sprintf "%-${VarPrintSpacing}s = %s\n", "\$$var", $mode eq 'raw' ? $value : generateRange($db, $value, $DevicePortRange{$host_io->{Type}} || $term_io->{DefaultPortRng});
	}
}


sub assignVar { # Assigns input values to variable
	my ($db, $type, $var, $assignmode, $value, $koi) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $vars = $db->[12];
	my ($portList, $quotedValue, @list, %hash);
	$var = '_' unless defined $var;
	$value = '' unless defined $value;
	$value = doubleQuoteMask($value, "'");
	$value =~ s/'',//g; # If we have empty values in the list (beginning or middle), we remove them
	$value =~ s/,''$//; # If we have empty values at end of list, we also remove them
	$value = doubleQuoteUnmask($value, "'");

	if ($type eq 'list') {
		if (defined $koi) { # List element
			if (defined $vars->{$var} && $vars->{$var}->{type} eq 'list') {
				@list = @{$vars->{$var}->{value}};
			}
			if ($koi == 0 and !@list) {
				cmdMessage($db, "\n$ScriptName: cannot assign last element of non-existing array");
				return '';
			}
			if ($koi > scalar(@list) + 1) {
				cmdMessage($db, "\n$ScriptName: index out of range; can only grow array by one element");
				return '';
			}
			$quotedValue = quotesRemove(\$value); # Remove quotes from $value, and remember if quotes were there in $quotedValue
			if (length $value) { # Assign value
				if (!$quotedValue) {
					if ($assignmode eq '.=' && defined $list[$koi - 1]) {
						$portList = generatePortList($host_io, join('', $list[$koi - 1], ',', $value));
					}
					else {
						$portList = generatePortList($host_io, $value);
					}
				}
				if (length $portList) { # A list of ports was recognized
					$list[$koi - 1] = $portList;
				}
				elsif ($assignmode eq '.=' && defined $vars->{$var}) { # Append value
					$list[$koi - 1] .= $value;
				}
				else { # Assign value
					$list[$koi - 1] = $value;
				}
			}
			elsif ($assignmode eq '=' && defined $vars->{$var}) { # Undefine element
				undef $list[$koi - 1];
			}
			if (@list) { # Only set if some values are present
				setvar($db, $var => \@list, type => 'list', script => $term_io->{Sourcing});
				return "\$$var\[$koi\]";
			}
		}
		else { # Full list
			if (length $value) { # Assign value
				$value =~ s/^\(([^\(\)]*)\)$/$1/;	# Remove () brackets
				if (length $value) {
					for my $elem (map {s/^\s+//; s/\s+$//; quotesRemove($_)} split(';', $value)) {
						$portList = generatePortList($host_io, $elem);
						push(@list, length $portList ? $portList : $elem);
					}
					if ($assignmode eq '.=' && defined $vars->{$var} && $vars->{$var}->{type} eq 'list') { # If variable list already set and we want to append
						unshift(@list, @{$vars->{$var}->{value}});
					}
				}
				setvar($db, $var => \@list, type => 'list', script => $term_io->{Sourcing});
			}
			elsif ($assignmode eq '=') {
				delete($vars->{$var}) if defined $vars->{$var};
				delete($host_io->{UnsavedVars}->{$var}) if defined $host_io->{UnsavedVars}->{$var};
			}
			if (defined $vars->{$var}) {
				return "\$$var\[\]";
			}
		}
	}
	elsif ($type eq 'hash') {
		if (defined $koi) { # Hash element
			if (defined $vars->{$var} && $vars->{$var}->{type} eq 'hash') {
				%hash = %{$vars->{$var}->{value}};
			}
			$quotedValue = quotesRemove(\$value); # Remove quotes from $value, and remember if quotes were there in $quotedValue
			if (length $value) { # Assign value
				if (!$quotedValue) {
					if ($assignmode eq '.=' && defined $hash{$koi}) {
						$portList = generatePortList($host_io, join('', $hash{$koi}, ',', $value));
					}
					else {
						$portList = generatePortList($host_io, $value);
					}
				}
				if (length $portList) { # A list of ports was recognized
					$hash{$koi} = $portList;
				}
				elsif ($assignmode eq '.=' && defined $vars->{$var}) { # Append value
					$hash{$koi} .= $value;
				}
				else { # Assign value
					$hash{$koi} = $value;
				}
			}
			elsif ($assignmode eq '=' && defined $vars->{$var}) { # Undefine element
				delete $hash{$koi};
			}
			if (%hash) { # Only set if some values are present
				setvar($db, $var => \%hash, type => 'hash', script => $term_io->{Sourcing});
				return "\$$var\{$koi\}";
			}
		}
		else { # Full hash
			if (length $value) { # Assign value
				$value =~ s/^\(([^\(\)]*)\)$/$1/;	# Remove () brackets
				if (length $value) {
					if ($assignmode eq '.=' && defined $vars->{$var} && $vars->{$var}->{type} eq 'hash') { # If variable hash already set and we want to append
						%hash = %{$vars->{$var}->{value}};
					}
					for my $elem (split(';', $value)) {
						my ($key, $val) = map {s/^\s+//; s/\s+$//; quotesRemove($_)} split('=>', $elem);
						next unless defined $key && defined $val;
						$portList = generatePortList($host_io, $val);
						$hash{$key} = length $portList ? $portList : $val;
					}
				}
				setvar($db, $var => \%hash, type => 'hash', script => $term_io->{Sourcing});
			}
			elsif ($assignmode eq '=') {
				delete($vars->{$var}) if defined $vars->{$var};
				delete($host_io->{UnsavedVars}->{$var}) if defined $host_io->{UnsavedVars}->{$var};
			}
			if (defined $vars->{$var}) {
				return "\$$var\{\}";
			}
		}
	}
	else { # Normal variable
		$quotedValue = quotesRemove(\$value); # Remove quotes from $value, and remember if quotes were there in $quotedValue
		if (length $value) { # Assign value
			if (!$quotedValue) {
				if ($assignmode eq '.=' && defined $vars->{$var}) {
					$portList = generatePortList($host_io, join('', $vars->{$var}->{value}, ',', $value));
				}
				else {
					$portList = generatePortList($host_io, $value);
				}
			}
			if (length $portList) { # A list of ports was recognized
				setvar($db, $var => $portList, script => $term_io->{Sourcing});
			}
			elsif ($assignmode eq '.=' && defined $vars->{$var}) { # Append value
				setvar($db, $var => $value, append => 1, script => $term_io->{Sourcing});
			}
			else { # Assign value
				setvar($db, $var => $value, script => $term_io->{Sourcing});
			}
		}
		elsif ($assignmode eq '=') { # Delete variable
			delete($vars->{$var}) if defined $vars->{$var};
			delete($host_io->{UnsavedVars}->{$var}) if defined $host_io->{UnsavedVars}->{$var};
		}
		if (defined $vars->{$var}) {
			return "\$$var";
		}
	}
	return '';
}


sub sizeVariable { # Replace a $#variable with its size
	my ($vars, $var, $type, $koi) = @_;
	$type = '' unless defined $type;

	unless (defined $vars->{$var}) {
		return "\$#$var\[" . ($koi + 1) . "]" if $type eq 'list';
		return "\$#$var\{$koi}" if $type eq 'hash';
		return "\$#$var";
	}
	if ($vars->{$var}->{type} eq 'list') {
		if ($type eq 'list' && defined $koi) {
			return scalar split(',', $vars->{$var}->{value}->[$koi]);
		}
		else {
			return scalar @{$vars->{$var}->{value}};
		}
	}
	elsif ($vars->{$var}->{type} eq 'hash') {
		if ($type eq 'hash' && defined $koi) {
			return scalar split(',', $vars->{$var}->{value}->{$koi});
		}
		else {
			return scalar keys %{$vars->{$var}->{value}};
		}
	}
	else { # Normal variable
		return scalar split(',', $vars->{$var}->{value});
	}
}


sub checkUndefVar { # Sets the error message if a variable was undefined
	my ($section, $error, $doNotDerefDollarAlone) = @_;

	if ($section =~ /\$($VarScript(?:\[[^\]]*\]|\{[^\}]*\}))/o) {
		$$error = "<variable \$$1 is undefined>";
	}
	elsif ($section =~ /\$(#?$VarNormal)/o) {
		$$error = "<variable \$$1 is undefined>";
	}
	elsif ($section =~ /\$\$$VarDelim/o) {
		$$error = "<variable \$\$ is undefined>";
	}
	elsif ($section =~ /\$\@$VarDelim/o) {
		$$error = "<variable \$\@ is undefined>";
	}
	elsif (!$doNotDerefDollarAlone && $section =~ /\$$VarDelim/o) {
		$$error = "<variable \$_ is undefined>";
	}
	elsif ($section =~ /\%$VarDelim/o) {
		$$error = "<variable \$% is undefined>";
	}
}


sub evalExpression { # Replace an expression or $variables by evaluating it as perl code
	my ($expression, $rangeMode, $error, $doNotDerefDollarAlone) = @_;
	my ($replaceValue, $returnValue);

	# Eval the expression as perl code
	$expression =~ s/^0+(\d+)$/$1/;	# If a numeric value with leading zeros, remove them or we end up doing eval of octal (bug19)
	debugMsg(4,"=Eval-Expression : ", \$expression, "\n");
	{	# Try and eval the expression in a block to suppress warnings
		no warnings;
		$replaceValue = eval $expression;
		debugMsg(4,"=Eval-ReplaceValue = ", \$replaceValue, "\n");
	}
	if (!$@ && defined $replaceValue && $replaceValue =~/^[ -~]+$/) { # && $replaceValue !~/^0\.\d+$/; was causing: $rmask = 0.0; $rmask = {"$rmask"}.0  to give "0.0".0
		# If eval ok & ascii char from 20' ' to 126'~' & not a numeric fraction
		$returnValue = $replaceValue;
	}
	else { # Otherwise
		$returnValue = $expression;
	}
	debugMsg(4,"=evalExpression returnValue = ", \$returnValue, "\n");
	unless (defined $error && defined $$error) { # Skip if error string already set
		checkUndefVar($returnValue, $error, $doNotDerefDollarAlone);
		debugMsg(4,"=evalExpression error = >", $error, "<\n") if defined $error && $$error;
	}
	return $returnValue;
}


sub portsAllDerefVar { # Hooks into dereferencing normal variables to get reserved variables $ALL, $1/ALL, $2:ALL, etc..
	my ($var, $db, $rangeMode) = @_;
	my $host_io = $db->[3];
	my $vars = $db->[12];

	if ($var =~ /^(?:\d+[\/:])?ALL$/) {
		my $portList = generatePortList($host_io, $var);
		return generateRange($db, $portList, $rangeMode) if defined $rangeMode;
		return $portList; # otherwise
	}
	elsif (defined $vars->{$var} && !$vars->{$var}->{type}) {
		return generateRange($db, $vars->{$1}->{value}, $rangeMode) if defined $rangeMode;
		return $vars->{$var}->{value}; # otherwise
	}
	else {
		return "\$$1";
	}
}


sub derefVarSection { # Replace $variables in a string section
	my ($db, $varSection, $rangeMode, $replFlag, $error, $doNotDerefDollarAlone, $doNotCompactEmptyQuotes) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $vars = $db->[12];
	my $switchName = switchname($host_io);
	unless (defined $replFlag) { # Not all callers provide a $replFlag reference
		my $flag;
		$replFlag = \$flag;
	}

	debugMsg(4,"=derefVarSection IN = >", \$varSection, "<\n");
	$varSection = backslashMask($varSection, '$%') if $varSection =~ /^\".+\"$/; # We don't look at $ or % signs which are backslashed (normally should only apply to double-quoted sections)

	# Dereference /$variables/ in m//
	$$replFlag = 1 if $varSection =~ s/~\s*\/\K\$($VarNormal)(?=\/)/defined $vars->{$1} && !$vars->{$1}->{type} ? quotemeta($vars->{$1}->{value}) : "\$$1"/geo;
	debugMsg(4,"=derefVarSection after /var/ = >", \$varSection, "<\n") if $$replFlag;

	# Dereference $variables
	$$replFlag = 1 if $varSection =~ s/\$($VarNormalAugm)$VarDelim/portsAllDerefVar($1, $db, $rangeMode)/geo;
	# Dereference $'variables
	$$replFlag = 1 if $varSection =~ s/\$\'($VarNormalAugm)$VarDelim/portsAllDerefVar($1, $db)/geo;
	# Dereference $$ switch name variable
	$$replFlag = 1 if $varSection =~ s/\$\$$VarDelim/defined $switchName ? $switchName : '$$'/geo;
	# Dereference $@ error variable
	$$replFlag = 1 if $varSection =~ s/\$\@$VarDelim/defined $host_io->{LastCmdError} ? $host_io->{LastCmdError} : '$@'/geo;
	# Dereference $> prompt variable
	$$replFlag = 1 if $varSection =~ s/\$\>$VarDelim/defined $host_io->{Prompt} ? $host_io->{Prompt} : '$@'/geo;
	# Dereference $ simple variable
	$$replFlag = 1 if !$doNotDerefDollarAlone && $varSection =~ s/\$$VarDelim/defined $vars->{_} ? generateRange($db, $vars->{_}->{value}, $rangeMode) : '$'/geo;
	# Dereference % simple variable
	$varSection = curlyMask($varSection, '%'); # We don't look at % var inside curlies, as we might want to use the Perl % mod operator
	$$replFlag = 1 if $varSection =~ s/\%$VarDelim/defined $vars->{'%'} ? $vars->{'%'}->{value} : '%'/geo;
	$varSection = curlyUnmask($varSection, '%');
	debugMsg(4,"=derefVarSection after simple vars = >", \$varSection, "<\n");

	# Dereference $_variables (for Control::CLI::Extreme attributes)
	$$replFlag = 1 if $varSection =~ s/\$(?:$VarAttrib)/replaceAttribute($db, $1, $2)/geo;
	# Dereference List $variable[idx]
	$$replFlag = 1 if $varSection =~ s/\$($VarScript)\[(\d+)\]/defined $vars->{$1} && $vars->{$1}->{type} eq 'list' && defined $vars->{$1}->{value}->[$2 - 1] ?
		generateRange($db, $vars->{$1}->{value}->[$2 - 1], $rangeMode) : "\$$1\[$2]"/geo;
	# Dereference List $'variable[idx]
	$$replFlag = 1 if $varSection =~ s/\$\'($VarScript)\[(\d+)\]/defined $vars->{$1} && $vars->{$1}->{type} eq 'list' && defined $vars->{$1}->{value}->[$2 - 1] ?
		$vars->{$1}->{value}->[$2 - 1] : "\$$1\[$2]"/geo;
	# Dereference Hash $variable{key}
	$$replFlag = 1 if $varSection =~ s/\$($VarScript)\{($VarHashKey)\}/defined $vars->{$1} && $vars->{$1}->{type} eq 'hash' && defined $vars->{$1}->{value}->{$2} ?
		generateRange($db, $vars->{$1}->{value}->{$2}, $rangeMode) : "\$$1\{$2}"/geo;
	# Dereference Hash $'variable{key}
	$$replFlag = 1 if $varSection =~ s/\$\'($VarScript)\{($VarHashKey)\}/defined $vars->{$1} && $vars->{$1}->{type} eq 'hash' && defined $vars->{$1}->{value}->{$2} ?
		$vars->{$1}->{value}->{$2} : "\$$1\{$2}"/geo;
	# Dereference List $variable[]
	$$replFlag = 1 if $varSection =~ s/\$($VarScript)\[\]/defined $vars->{$1} && $vars->{$1}->{type} eq 'list' ? join(',', (1 .. $#{$vars->{$1}->{value}} + 1)) : "\$$1\[]"/geo;
	# Dereference Hash $variable{}
	$$replFlag = 1 if $varSection =~ s/\$($VarScript)\{\}/defined $vars->{$1} && $vars->{$1}->{type} eq 'hash' ? join(',', sort by_type keys %{$vars->{$1}->{value}}) : "\$$1\{}"/geo;
	# Dereference $#variable[idx]
	$$replFlag = 1 if $varSection =~ s/\$#($VarScript)\[(\d+)\]/sizeVariable($vars, $1, 'list', $2 - 1)/ge;
	# Dereference $#variable{key}
	$$replFlag = 1 if $varSection =~ s/\$#($VarScript)\{($VarHashKey)\}/sizeVariable($vars, $1, 'hash', $2)/ge;
	# Dereference $#variable
	$$replFlag = 1 if $varSection =~ s/\$#($VarAny)?/sizeVariable($vars, $1 || '_')/ge;
	debugMsg(4,"=derefVarSection after complex vars = >", \$varSection, "<\n");

	# Dereference {$variables and/or perl expression}
	$varSection =~ s/(\$$VarScript)\{([^\}]+)\}/$1\x00$2\x01/g; # If we have any $var{$key} where either $key or $var{$key} could not be dereferenced, we mask the curly section to skip below
	$$replFlag = 1 if $varSection =~ s/\{([^\}]+)\}/evalExpression($1, $rangeMode, $error, $doNotDerefDollarAlone)/ge;
	$varSection =~ s/(\$$VarScript)\x00([^\x01]+)\x01/$1\{$2\}/g; # We unmask the curly section now
	debugMsg(4,"=derefVarSection after {perl} = >", \$varSection, "<\n");

	# Dereference List $variable[idx] - take2; in case we had $var[{$v+1}], the $v+1 would only evaluate above
	$$replFlag = 1 if $varSection =~ s/\$($VarScript)\[(\d+)\]/defined $vars->{$1} && $vars->{$1}->{type} eq 'list' && defined $vars->{$1}->{value}->[$2 - 1] ?
		generateRange($db, $vars->{$1}->{value}->[$2 - 1], $rangeMode) : "\$$1\[$2]"/geo;
	# Dereference List $'variable[idx] - take2; in case we had $var[{$v+1}], the $v+1 would only evaluate above
	$$replFlag = 1 if $varSection =~ s/\$\'($VarScript)\[(\d+)\]/defined $vars->{$1} && $vars->{$1}->{type} eq 'list' && defined $vars->{$1}->{value}->[$2 - 1] ?
		$vars->{$1}->{value}->[$2 - 1] : "\$$1\[$2]"/geo;
	debugMsg(4,"=derefVarSection after list deref take2 = >", \$varSection, "<\n");
	unless (defined $error && defined $$error) { # Skip if error string already set
		checkUndefVar($varSection, $error, $doNotDerefDollarAlone);
		debugMsg(4,"=derefVarSection error = >", $error, "<\n") if defined $error && $$error;
	}

	if ($term_io->{Sourcing}) { # In sourcing
		while ($varSection =~ /(.)?(\$(?:$VarAny(?:\[[^\]]*\]|\{[^\}]*\})?))(.)?/) { # While unreferenced vars present
			my $residualVar = $2;
			if (defined $1 && defined $3 && ("$1$3" eq '""' || "$1$3" eq "''")) { # If already quoted
				$varSection =~ s/\Q$residualVar\E// or last;	# Remove the variable and leave empty quotes
			}
			else { # If not already quoted
				$varSection =~ s/\Q$residualVar\E/''/ or last;	# Replace the variable with empty quotes
			}
			debugMsg(4,"=derefVarSection sourcing removing unref vars = >", \$varSection, "<\n");
		}
		unless ($doNotCompactEmptyQuotes) {
			if ($varSection =~ s/'',//g || $varSection =~ s/,''//) {
				debugMsg(4,"=derefVarSection sourcing removing redundant empty quotes = >", \$varSection, "<\n");
			}
		}
	}
	$varSection = backslashUnmask($varSection, '$%', 1) if $varSection =~ /^\".+\"$/;
	debugMsg(4,"=derefVarSection OUT = >", \$varSection, "<\n");
	return $varSection;
}


sub derefConditionSection { # Prepare embedded logical operator conditions for variable replacement
	my ($db, $condition, $error) = @_;
	# Put quotes around naked variable, but only where needed; e.g. here: $in =~ /^\d+\.\d+\.\d+\.\d+$/ but not here: @until "no" =~ /^$more/i
	# New approach
	$condition = quoteSlashMask($condition, '$'); # Now mask vars which might be inside quotes or inside // pattern matches
	my ($change, $quote);
	$change = 1 if $condition =~ s/(\$\'?(?:$VarAny(?:\[[^\]]*\]|\{[^\}]*\})?))/"$1"/go; # Add quotes to any unmasked variables
	$condition = quoteSlashUnmask($condition, '$'); # Unmask
	$condition = derefVarSection($db, $condition, 0, undef, $error, 1); # Set $doNotDerefDollarAlone as it can conflict with condition pattern matches
	$condition =~ s/(\".*?\")/$quote = $1; $quote =~ s!\$!"\\\$"!ge; $quote/ge;
	debugMsg(4,"=derefConditionSection = >", \$condition, "<\n") if $change;
	return $condition;
}


sub generateVarList { # Takes an unordered list and produces an alphabetically ordered list without any duplicates
	my $inlist = shift;
	my (@list, @sortedList);
	$inlist = [ split(',', $inlist) ] unless ref($inlist) eq 'ARRAY';
	debugMsg(1,"-> generateVarList input = ", \join(',', @$inlist), "\n");

	foreach my $element (@$inlist) {
		push(@list, $element) unless grep(/^\Q$element\E$/, @list);
	}
	if ( grep {!/^\d+$/} @list) { # If some non-numeric values exists..
		@sortedList = sort { $a cmp $b } @list;	# .. use alphanumeric sorting
	}
	else {	# All values are numeric..
		@sortedList = sort { $a <=> $b } @list;	# .. use numeric sorting
	}
	return join(',', @sortedList);
}


sub variablesCaptureValues { # Complete the variable capturing (once prompt received) and assign new values into $vars structure
	my $db = shift;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $vars = $db->[12];

	my $variableFormatCapturedValue = sub { # Format captured value before assigning it to a variable
		my $value = shift;
		# Note that $value can be a string, or an array ref
		my $stringValue = ref($value) ? join(',', @$value) : $value;
	
		if ($term_io->{VarCustomRegex} && $stringValue !~ /^$VarCapturePortRegex$/) {
			# For custom regex, except if we ended up capturing ports
			$value = generateVarList($value);
		}
		else {	# For standard port regex OR custom regex if we ended up capturing ports
			$value = generatePortList($host_io, $value);
		}
		return $value;
	};

	printOut($script_io, "\n") unless $term_io->{EchoOutputOff} && $term_io->{Sourcing};
	foreach my $variable (@{$term_io->{VarCapture}}) {
		if ($term_io->{VarCaptureType}->{$variable} eq 'list') {
			my @list;
			if (defined $term_io->{VarCaptureKoi}->{$variable}) { # List element
				@list = defined $vars->{$variable} && $vars->{$variable}->{type} eq 'list' ? @{$vars->{$variable}->{value}} : ();
				$list[$term_io->{VarCaptureKoi}->{$variable} - 1] = &$variableFormatCapturedValue($term_io->{VarCaptureVals}->{$variable});
			}
			else { # Full list
				foreach my $value (@{$term_io->{VarCaptureVals}->{$variable}}) {
					push(@list, &$variableFormatCapturedValue($value));
				}
			}
			setvar($db, $variable => \@list, type => 'list', script => $term_io->{Sourcing});
		}
		elsif ($term_io->{VarCaptureType}->{$variable} eq 'hash') {
			my %hash;
			if (defined $term_io->{VarCaptureKoi}->{$variable}) { # Hash element
				%hash = defined $vars->{$variable} && $vars->{$variable}->{type} eq 'hash' ? %{$vars->{$variable}->{value}} : ();
				$hash{$term_io->{VarCaptureKoi}->{$variable}} = &$variableFormatCapturedValue($term_io->{VarCaptureVals}->{$variable});
			}
			else { # Full hash
				foreach my $key (keys %{$term_io->{VarCaptureVals}->{$variable}}) {
					my $value = $term_io->{VarCaptureVals}->{$variable}->{$key};
					$hash{$key} = &$variableFormatCapturedValue($value);
				}
			}
			setvar($db, $variable => \%hash, type => 'hash', script => $term_io->{Sourcing});
		}
		else { # Flat variables
			my $value = &$variableFormatCapturedValue($term_io->{VarCaptureVals}->{$variable});
			setvar($db, $variable => $value, script => $term_io->{Sourcing});
		}
		unless ($term_io->{EchoOutputOff} && $term_io->{Sourcing}) {
			printOut($script_io, printVar($db, $variable, 0, $term_io->{VarCaptureKoi}->{$variable}) );
		}
	}
	printOut($script_io, "\n") unless $term_io->{EchoOutputOff} && $term_io->{Sourcing};
}


sub variablesStoreValues { # Process line of output and store values into $term_io variable structures if regex matches
	my ($term_io, $line) = @_;

	my @captures = $term_io->{VarGRegex} ? ($line =~ /$term_io->{VarRegex}/g) : ($line =~ /$term_io->{VarRegex}/);
	return unless @captures;
	debugMsg(2,"Variable captures array = (", \join(';', map(defined $_ ? $_ : '<undef>', @captures)), ")\n") if $::Debug;

	my $storeValue = sub { # Assign 1 value
		my ($variable, $key, $capValue) = @_;
		chomp($capValue); # Make sure no trailing \n
		if (!$term_io->{VarCustomRegex} && ( $capValue =~ s/$VarCapturePortFormatRegex/$1\/$2/go || $capValue =~ s/\/ /\//g) ) {
			debugMsg(2,"Value Formatted to:>", \$capValue, "<\n");
		}
		if ($term_io->{VarCaptureType}->{$variable} eq 'list' && !defined $term_io->{VarCaptureKoi}->{$variable}) {
			push(@{$term_io->{VarCaptureVals}->{$variable}}, $capValue);
			debugMsg(2,"Capture to Variable \$$variable\[] value :>", \$capValue, "<\n");
		}
		else {
			foreach my $value (split(',', $capValue)) {
				if ($term_io->{VarCaptureType}->{$variable} eq 'hash' && !defined $term_io->{VarCaptureKoi}->{$variable}) {
					unless ( grep($_ eq $value, @{$term_io->{VarCaptureVals}->{$variable}->{$key}}) ) {
						push(@{$term_io->{VarCaptureVals}->{$variable}->{$key}}, $value);
						debugMsg(2,"Capture to Variable \$$variable\{$key} value :>", \$value, "<\n");
					}
				}
				else { # All other variable types, add on list
					unless ( grep($_ eq $value, @{$term_io->{VarCaptureVals}->{$variable}}) ) {
						push(@{$term_io->{VarCaptureVals}->{$variable}}, $value);
						debugMsg(2,"Capture to Variable \$$variable value :>", \$value, "<\n");
					}
				}
			}
		}
	};

	my $getHashKey = sub { # Set the hash key, if a hash
		my ($variable, $captureListRef, $capValue) = @_;
		my $key = $captureListRef->[ $term_io->{VarCapHashKeys}->{$variable} ];
		if ($term_io->{VarCustomRegex} == 2) {
			if (defined $key) { # Hash & key is defined => remember the key for next line
				$term_io->{VarKeyThenValue} = 1 if not defined $term_io->{VarKeyThenValue};
				$term_io->{VarHeldKey} = $key if $term_io->{VarKeyThenValue} == 1;
				debugMsg(2,"Capture to Variable \$$variable\{$key} - caching key\n");
			}
			elsif (!defined $key && defined $term_io->{VarHeldKey}) { # Hash & key is not defined => use cached key if one was set
				$key = $term_io->{VarHeldKey};
				debugMsg(2,"Capture to Variable \$$variable\{$key} - key was undef so using cached key\n");
			}
			if (defined $capValue) {
				$term_io->{VarKeyThenValue} = 0 if not defined $term_io->{VarKeyThenValue};
				$term_io->{VarHeldValue} = $capValue if $term_io->{VarKeyThenValue} == 0;
				debugMsg(2,"Capture to Variable \$$variable\{} - caching value: >", \$capValue, "<\n");
			}
			elsif (!defined $capValue && defined $term_io->{VarHeldValue}) {
				$capValue = $term_io->{VarHeldValue};
				$term_io->{VarHeldValue} = undef;
				debugMsg(2,"Capture to Variable \$$variable\{$key} - value was undef so using cached value: >", \$capValue, "<\n");
			}
		}
		return ($key, $capValue);
	};

	while (scalar @captures) { # We unshift $term_io->{VarCaptureNumb} elements at each cycle
		my @capturePortion = splice(@captures, 0, $term_io->{VarCaptureNumb});
		debugMsg(2,"Variable capture portion array = (", \join(';', map(defined $_ ? $_ : '<undef>', @capturePortion)), ")\n") if $::Debug;
		if (%{$term_io->{VarCapIndxVals}}) { # 1 or more vars BUT each var = 1 value per capturePortion
			foreach my $variable (@{$term_io->{VarCapture}}) {
				my $capValue = $capturePortion[ $term_io->{VarCapIndxVals}->{$variable} ];
				my $key = 0; # Will be set if variable is a hash
				if ($term_io->{VarCaptureType}->{$variable} eq 'hash' && !defined $term_io->{VarCaptureKoi}->{$variable}) {
					($key, $capValue) = &$getHashKey($variable, \@capturePortion, $capValue);
				}
				if ($::Debug) {
					debugMsg(2,"capValue = ", \$capValue, " / ");
					debugMsg(2,"key = ", \$key, "\n");
				}
				next unless defined $capValue && defined $key;
				&$storeValue($variable, $key, $capValue);
			}
		}
		else { # 1 var = many values per capturePortion
			my $variable = $term_io->{VarCapture}->[0];
			my $key = 0;
			if ($term_io->{VarCaptureType}->{$variable} eq 'hash' && !defined $term_io->{VarCaptureKoi}->{$variable}) {
				($key) = &$getHashKey($variable, \@capturePortion);
				next unless defined $key;
				splice(@capturePortion, $term_io->{VarCapHashKeys}->{$variable}, 1); # Remove the key from the list
			}
			for my $i (0 .. $#capturePortion) {
				next unless defined $capturePortion[$i];
				&$storeValue($variable, $key, $capturePortion[$i]);
			}
		}
	}
	$term_io->{VarCaptureFlag} = 1;
}


sub processVarCapInput { # Do initial processing of variable capture input
	my ($db, $prompt, $input) = @_;
	my $term_io = $db->[2];
	my $script_io = $db->[4];
	my $vars = $db->[12];
	my ($columnRegex, $customRegex);

	my $initVarStorage = sub { # Init all var storage keys
		$term_io->{VarCapture} = [];
		$term_io->{VarCaptureNumb} = undef;
		$term_io->{VarCaptureVals} = {};
		$term_io->{VarCaptureType} = {};
		$term_io->{VarCapHashKeys} = {};
		$term_io->{VarCapIndxVals} = {};
		$term_io->{VarCaptureKoi} = {};
		$term_io->{VarHeldKey} = undef;
		$term_io->{VarHeldValue} = undef;
		$term_io->{VarKeyThenValue} = undef;
		$term_io->{VarGRegex} = undef;
	};

	# Init var storage
	&$initVarStorage;

	# Process regex
	if ($input =~ s/\s*'((?:[\$\%]\d+[,-]?)+)'$// || $input =~ s/\s*((?:\%\d+[,-]?)+)$//) { # %<n> Regex supplied
		$columnRegex = $1
	}
	elsif ($input =~ s/\s*'([^']+)'$// || $input =~ s/\s*"([^"]+)"$//) { #'# Custom Regex supplied
		$customRegex = $1;
	}

	# Process var input
	foreach my $variable ( split(',', $input) ) {
		debugMsg(1,"-> processVarCapInput / inspecting var: ", \$variable, "\n");
		if ($variable =~ s/^\$($VarScript)\[\]$/$1/o) { # List
			if (defined $term_io->{VarCaptureType}->{$variable}) {
				printOut($script_io, "\n$ScriptName: duplicate variable \$$variable\n$prompt");
				&$initVarStorage;
				return;
			}
			push(@{$term_io->{VarCapture}}, $variable);
			$term_io->{VarCaptureType}->{$variable} = 'list';
			debugMsg(1,"-> Variable capture to list[] \$$variable\[]\n");
		}
		elsif ($variable =~ s/^\$($VarScript)\{\}$/$1/o) { # Hash with no index
			printOut($script_io, "\n$ScriptName: capturing to a hash variable requires a key index <%n> in the curlies\n$prompt");
			&$initVarStorage;
			return;
		}
		elsif ($variable =~ s/^\$($VarScript)\{%(\d+)\}$/$1/o) { # Hash
			if (defined $term_io->{VarCaptureType}->{$variable}) {
				printOut($script_io, "\n$ScriptName: duplicate variable \$$variable\n$prompt");
				&$initVarStorage;
				return;
			}
			if ($2 == 0) {
				printOut($script_io, "\n$ScriptName: hash index %0 not allowed\n$prompt");
				&$initVarStorage;
				return;
			}
			elsif ($2 >$VarRangeUnboundMax) {
				printOut($script_io, "\n$ScriptName: hash index greater than $VarRangeUnboundMax not supported\n$prompt");
				&$initVarStorage;
				return;
			}
			push(@{$term_io->{VarCapture}}, $variable);
			$term_io->{VarCaptureType}->{$variable} = 'hash';
			$term_io->{VarCapHashKeys}->{$variable} = $2;
			debugMsg(1,"-> Variable capture to hash{} \$$variable\{\%$2}\n");
		}
		elsif ($variable =~ s/^\$($VarScript)\[(\d+)\]$/$1/o) { # List element
			if (defined $term_io->{VarCaptureType}->{$variable}) {
				printOut($script_io, "\n$ScriptName: duplicate variable \$$variable\n$prompt");
				&$initVarStorage;
				return;
			}
			my $maxIdx = defined $vars->{$variable} && $vars->{$variable}->{type} eq 'list' ? scalar(@{$vars->{$variable}->{value}}) : 0;
			if ($2 == 0 and $maxIdx == 0) {
				printOut($script_io, "\n$ScriptName: cannot assign last element of non-existing array\n$prompt");
				&$initVarStorage;
				return;
			}
			if ($2 > $maxIdx + 1) {
				printOut($script_io, "\n$ScriptName: index out of range; can only grow array by one element\n$prompt");
				&$initVarStorage;
				return;
			}
			push(@{$term_io->{VarCapture}}, $variable);
			$term_io->{VarCaptureType}->{$variable} = 'list';
			$term_io->{VarCaptureKoi}->{$variable} = $2;
			debugMsg(1,"-> Variable capture to list[index] \$$variable\[$2]\n");
		}
		elsif ($variable =~ s/^\$($VarScript)\{($VarHashKey)\}$/$1/o) { # Hash element
			if (defined $term_io->{VarCaptureType}->{$variable}) {
				printOut($script_io, "\n$ScriptName: duplicate variable \$$variable\n$prompt");
				&$initVarStorage;
				return;
			}
			push(@{$term_io->{VarCapture}}, $variable);
			$term_io->{VarCaptureType}->{$variable} = 'hash';
			$term_io->{VarCaptureKoi}->{$variable} = $2;
			debugMsg(1,"-> Variable capture to hash{key} \$$variable\{$2}\n");
		}
		elsif ($variable =~ s/^\$($VarUser)$/$1/o) { # Valid variable name; only accept letters/numbers & '_'
			if ($variable eq 'ALL') {
				printOut($script_io, "\n$ScriptName: reserved variable \$$variable\n$prompt");
				&$initVarStorage;
				return;
			}
			if (defined $term_io->{VarCaptureType}->{$variable}) {
				printOut($script_io, "\n$ScriptName: duplicate variable \$$variable\n$prompt");
				&$initVarStorage;
				return;
			}
			push(@{$term_io->{VarCapture}}, $variable);
			$term_io->{VarCaptureType}->{$variable} = '';
			debugMsg(1,"-> Variable capture to flat variable \$$variable\n");
		}
		elsif ($variable eq '$') { # Wildcard variable ($_ is handled above)
			if (defined $term_io->{VarCaptureType}->{$variable}) {
				printOut($script_io, "\n$ScriptName: duplicate variable \$$variable\n$prompt");
				&$initVarStorage;
				return;
			}
			push(@{$term_io->{VarCapture}}, '_');
			$term_io->{VarCaptureType}->{'_'} = '';
			debugMsg(1,"-> Variable capture to \$_ ('\$' case)\n");
		}
		else { # Invalid variable name
			printOut($script_io, "\n$ScriptName: invalid variable name\n$prompt");
			&$initVarStorage;
			return;
		}
	}
	return (1, $columnRegex, $customRegex);
}


sub derefVariables { # Replace $variables
	my ($db, $cmdParsed, $cmdSection, $doNotEcho, $doNotCompactEmptyQuotes) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];

	# Prepare the prompt and alias echo header
	my $prompt = appendPrompt($host_io, $term_io);
	my $varsEcho = echoPrompt($term_io, $prompt, 'vars');

	for my $varSection (@{$cmdSection->{var}}) {
		debugMsg(4,"=Processing cmdParsed variable section: ", \$varSection, "\n");
		my $varReplaced = 0;
		my $error = 0;
		# Actual variable replacement is handed off to a subroutine
		my $derefSection = derefVarSection($db, $varSection, $DevicePortRange{$host_io->{Type}}, \$varReplaced, \$error, 0, $doNotCompactEmptyQuotes);
		if (!$doNotEcho && $error) {
			$error = "\n$varsEcho" . $error;
			if ($term_io->{EchoOff} && $term_io->{Sourcing}) {
				$host_io->{CommandCache} .= $error;
				debugMsg(4,"=adding to CommandCache - derefVariables:\n>",\$host_io->{CommandCache}, "<\n");
			}
			else {
				printOut($script_io, $error);
				--$term_io->{PageLineCount};
			}
		}
		if ($varReplaced) {
			# $VarDelim added otherwise we get problem with '$tmr_static = 0/15' + '$tmr_staticPortStatus{$tmr_static} = "down"' = '0/15PortStatus{$tmr_static} = "down"'
			# but if we don't match with $VarDelim, then we try without as well
			$cmdSection->{str} =~ s/\Q$varSection\E(?=$VarDelim)/$derefSection/ or		# $tmr_static = 0/15
			$cmdSection->{str} =~ s/\Q$varSection\E/$derefSection/;
			$cmdParsed->{thiscmd} =~ s/\Q$varSection\E(?=$VarDelim)/$derefSection/ or	# $tmr_staticPortStatus{$tmr_static} = "down"
			$cmdParsed->{thiscmd} =~ s/\Q$varSection\E/$derefSection/;
			$cmdParsed->{varflag} = 1;
		}
	}
	return 1;
}


sub echoVarReplacement { # Echos to screen replaced variables
	my ($db, $cmdParsed) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];

	return unless $cmdParsed->{varflag}; # Come out if no variable was replaced

	# Prepare the prompt and alias echo header
	my $prompt = appendPrompt($host_io, $term_io);
	my $varsEcho = echoPrompt($term_io, $prompt, 'vars');

	# Show variable de-referencing on output
	if ($term_io->{VarsEcho} && !( $term_io->{InputBuffQueue}->[0] eq 'RepeatCmd') ) {
		if ($term_io->{EchoOff} && $term_io->{Sourcing}) {
			$host_io->{CommandCache} .= "\n$varsEcho" . $cmdParsed->{thiscmd};
			debugMsg(4,"=adding to CommandCache - echoVarReplacement:\n>",\$host_io->{CommandCache}, "<\n");
		}
		else {
			printOut($script_io, "\n$varsEcho" . $cmdParsed->{thiscmd});
			--$term_io->{PageLineCount};
		}
	}
	$cmdParsed->{varflag} = 0;
}


sub replaceAttribute { # Replace connected device Control::CLI::Extreme attributes
	my ($db, $attributeName, $indx, $addQuotes) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $attributeValue;
	if ($host_io->{Connected}) { # This is skipped in PseudoTerm
		$attributeValue = $host_io->{CLI}->attribute(
			Attribute	=>	$attributeName,
			Blocking	=>	1,	# For now we block on these requests
		);
	}
	elsif ($term_io->{PseudoTerm}) {
		$attributeValue = $term_io->{PseudoAttribs}->{$attributeName} if exists $term_io->{PseudoAttribs}->{$attributeName};
	}
	$attributeValue = $attributeValue->[$indx] if ref($attributeValue) eq 'ARRAY' && defined $indx;
	$attributeValue = $attributeValue->{$indx} if ref($attributeValue) eq 'HASH' && defined $indx;
	$attributeValue = join(',', map {defined $_ ? $_ : ''} @{$attributeValue}) if ref($attributeValue) eq 'ARRAY';
	$attributeValue = '' unless defined $attributeValue;
	return $attributeValue unless $addQuotes;
	$attributeValue = "'".$attributeValue."'"; # in between single quotes
	return $attributeValue;
}


1;
