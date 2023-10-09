# ACLI sub-module
package AcliPm::CommandProcessing;
our $Version = "1.10";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(processControlCommand processEmbeddedCommand);
}
use Cwd;
use Term::ReadKey;
use Net::Ping::External qw(ping);
use Time::HiRes;
use File::Glob ':bsd_glob';
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::Alias;
use AcliPm::ChangeMode;
use AcliPm::CommandStructures;
use AcliPm::ConnectDisconnect;
use AcliPm::DebugMessage;
use AcliPm::Dictionary;
use AcliPm::ExitHandlers;
use AcliPm::GeneratePortListRange;
use AcliPm::GlobalConstants;
use AcliPm::GlobalDefaults;
use AcliPm::GlobalDeviceSettings;
use AcliPm::GlobalMatchingPatterns;
use AcliPm::HandleDevicePeerCP;
use AcliPm::Logging;
use AcliPm::MaskUnmaskChars;
use AcliPm::Print;
use AcliPm::Prompt;
use AcliPm::QuotesRemove;
use AcliPm::Sed;
use AcliPm::SerialPort;
use AcliPm::Socket;
use AcliPm::Sourcing;
use AcliPm::Spawn;
use AcliPm::Ssh;
use AcliPm::TabExpand;
use AcliPm::TerminalServer;
use AcliPm::Variables;
use AcliPm::Version;


sub by_ip { # Sort function for command "ssh known_hosts"
	my $compareResult;
	my @a = split('\.', $a->[0]); # dot needs to be backslashed..
	my @b = split('\.', $b->[0]); # could be an IP or could be a dns name
	for (my $i = 0; $i <= $#a || $i <= $#b; $i++) {
		if (defined $a[$i] && defined $b[$i]) {
			if ($a[$i] =~ /^\d+$/ && $b[$i] =~ /^\d+$/) { # Numbers
				$compareResult = $a[$i] <=> $b[$i];
			}
			else { # Strings or one is a string and the other a number
				$compareResult = $a[$i] cmp $b[$i];
			}
		}
		else {
			$compareResult = defined $a[$i] ? 1 : -1;
		}
		last if $compareResult;
	}
	return $compareResult;
}


sub iniValue { # Return printable ini key value
	my ($key, $value) = @_;
	if ($key =~ /lst\d?$/) {
		return "[" . join(',', @$value) . "]";
	}
	elsif ($key =~ /chr$/) {
		return '"\n"' if $value eq "\n";
		return '"\r"' if $value eq "\r";
		return '"^' . chr(ord($value)|64) . '"' if ord($value) < 32;
	}
	elsif ($key =~ /str$/) {
		return '"' . $value . '"';
	}
	else {
		return $value;
	}
}


sub cmdOutput { # On embedded commands this output can be grepped
	my ($db, $text, $embedded) = @_;
	my $host_io = $db->[3];
	my $script_io = $db->[4];

	if ($script_io->{AcliControl}) {
		print $text;
	}
	else {
		unless ($script_io->{EmbCmdSpacing}) {
			$host_io->{OutBuffer} .= " \n"; # Without the space as if this executed after 3 lines below... @highlight info
			$script_io->{EmbCmdSpacing} = 1;
		}
		$host_io->{OutBuffer} .= $text;
	}
}


sub stringTimer { # Produce a string version of a minutes timer
	my $inValue = shift; # In minutes
	my $minutes = $inValue%60;
	$inValue = ($inValue - $minutes) / 60; # Now in hours
	my $hours = $inValue%24;
	$inValue = ($inValue - $hours) / 24; # Now in days
	my $days = $inValue%365;
	$inValue = ($inValue - $days) / 365; # Now in years!
	my $years = $inValue;
	my $outString;
	$outString .= "$years year" . ($years > 1 ? 's ':' ') if $years;
	$outString .= "$days day" . ($days > 1 ? 's ':' ') if $days;
	$outString .= "$hours hour" . ($hours > 1 ? 's ':' ') if $hours;
	$outString .= "$minutes minute" . ($minutes > 1 ? 's ':' ') if $minutes;
	return $outString;
}


sub evalCondition { # Evaluate a condition as true or false
	my $condition = shift;
	my $result;
	{
	#	local $SIG{__WARN__} = sub { die shift }; # Turn every warning into an exception
	#	local $SIG{__WARN__} = sub { }; # Disable warnings for the eval below (bug7)
		no warnings;
		no strict;
		$result = eval $condition;
	}
	if ($@) {
		(my $message = $@) =~s/;.*$//;
		debugMsg(4, "=evalCondition: error = ", \$message, "\n");
		$message =~ s/ at .+ line .+$//; # Delete file & line number info
		return (undef, $message);
	}
	else {
		$result = '' unless defined $result;
		debugMsg(4, "=evalCondition: $condition = ", \($result ? 'TRUE' : 'FALSE'), "\n");
		return ($result, undef);
	}
}


sub nestedBlock { # Makes sure we are in a block type, even if within 1 or more @if blocks
	my ($blockStack, $blockType) = @_;

	foreach my $block (reverse @$blockStack) {
		return 1 if $block->[0] eq $blockType;
		return 0 unless $block->[0] eq '@if';
	}
	return 0;
}


sub endofBlock { # Parses input buffer skipping lines until it finds a valid keyword indicating end of block to skip
	my ($db, $keywords, $exitIfBlocks) = @_;
	my $term_io = $db->[2];
	my @blockStack = ();
	my @blockCache = ();
	my $blockType;
	my $queue = $term_io->{InputBuffQueue}->[0];
	return unless defined $term_io->{InputBuffer}->{$queue}->[0]; # No more buffer to start with
	while (1) {
		my $nextCmd = tabExpandLite($EmbeddedCmds, $term_io->{InputBuffer}->{$queue}->[0]);
		if ( ($blockType) = grep($_ eq $nextCmd, keys %BlockTypes) ) {
			push(@blockStack, $BlockTypes{$blockType});
			debugMsg(4, "=endofBlock: embedded $blockType block found; level = ", \scalar @blockStack, "\n");
		}
		return 1 if scalar @blockStack == 0 && grep($_ eq $nextCmd, @$keywords);
		if (scalar @blockStack == 0 && $nextCmd eq '@endif' && $exitIfBlocks) {
			pop(@{$term_io->{BlockStack}});
			debugMsg(4, "=endofBlock: popping \@if block\n");
		}
		else {
			if (@blockStack && $nextCmd eq $blockStack[$#blockStack]) {
				pop(@blockStack);
				debugMsg(4, "=endofBlock: closing embedded block with $nextCmd; level = ", \scalar @blockStack, "\n");
			}
		}
		# We remove it from buffer
		my $command = shiftInputBuffer($db);
		debugMsg(4, "=endofBlock - skipping line : ", \$command, "\n");
		return unless @{$term_io->{InputBuffer}->{$queue}}; # Case where we have emptied the whole buffer
	}
}


sub cacheBlock { # Parses input buffer caching lines until it finds a valid keyword indicating end of block to cache
	my ($db, $keywords) = @_;
	my $term_io = $db->[2];
	my @blockStack = ();
	my @blockCache = ();
	my $blockType;
	my $queue = $term_io->{InputBuffQueue}->[0];
	foreach my $command (@{$term_io->{InputBuffer}->{$queue}}) {
		debugMsg(4, "=cacheBlock - caching line : ", \$command, "\n");
		push(@blockCache, $command);
		my $nextCmd = tabExpandLite($EmbeddedCmds, $command);
		if ( ($blockType) = grep($_ eq $nextCmd, keys %BlockTypes) ) {
			push(@blockStack, $BlockTypes{$blockType});
			debugMsg(4, "=cacheBlock: embedded $blockType block found; level = ", \scalar @blockStack, "\n");
		}
		return \@blockCache if scalar @blockStack == 0 && grep($_ eq $nextCmd, @$keywords);
		if (@blockStack && $nextCmd eq $blockStack[$#blockStack]) {
			pop(@blockStack);
			debugMsg(4, "=cacheBlock: closing embedded block with $nextCmd; level = ", \scalar @blockStack, "\n");
		}
	}
	return; # Case where we have traversed the whole buffer
}


sub processCommonCommand { # Process a control/embedded command which exists on both
	my ($db, $command) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $peercp_io = $db->[5];
	my $socket_io = $db->[6];
	my $prompt = $db->[7];
	my $history = $db->[9];
	my $alias = $db->[11];
	my $vars = $db->[12];
	my $dictionary = $db->[16];

	$command =~ s/^(\@)// unless $script_io->{AcliControl};	# Remove starting @ for embedded commands
	my $at = $1 || '';
	debugMsg(4,"=processCommonCommand - command to process = >", \$command, "<\n");

	# Below, use:
	# cmdMessage($db, "text"); for warning, syntax and error messages (will never be grep-able, or more paged)
	# cmdOutput($db, "text");  for useful output content (will be grep-able & more paged)

	# Common Commands prefixed with &

	#
	# &Alias command
	#
	$command eq 'alias disable' && do {
		$term_io->{AliasEnable} = 0;
		$command = '';
	};
	$command eq 'alias echo disable' && do {
		$term_io->{AliasEcho} = 0;
		$command = '';
	};
	$command eq 'alias echo enable' && do {
		$term_io->{AliasEcho} = 1;
		$command = '';
	};
	$command eq 'alias enable' && do {
		$term_io->{AliasEnable} = 1;
		$command = '';
	};
	$command eq 'alias info' && do {
		cmdOutput($db, "Alias settings:\n");
		cmdOutput($db, "	Alias state		: " . ($term_io->{AliasEnable} ? "enable\n" : "disable\n"));
		cmdOutput($db, "	Alias echoing		: " . ($term_io->{AliasEcho} ? "enable\n" : "disable\n"));
		cmdOutput($db, "	Alias file		: " . $term_io->{AliasFile} . "\n");
		cmdOutput($db, "	Alias merge file	: " . $term_io->{AliasMergeFile} . "\n") if length $term_io->{AliasMergeFile};
		$command = '';
	};
	$command eq 'alias list ?' && do {
		cmdMessage($db, "Syntax: ${at}alias list [<description-search-pattern>]\n");
		$command = '';
	};
	$command =~ /^alias list(?: (.*))?/ && do {
		my $namepat = $1;
		my @namepats;
		if (length $namepat) { # Process patterns; we split it up into words, or quoted strings
			$namepat = quoteCurlyMask($namepat, ' ');	# Mask spaces inside quotes;
			$namepat =~ s/\s+/ /g;				# Replace multiple spaces with single space (except inside quotes)
			@namepats = split($Space, $namepat);		# Split it into an array
			@namepats = map { quotesRemove(quoteCurlyUnmask($_, ' ')) } @namepats; # Needs to re-assign, otherwise quoteCurlyUnmask won't work
			debugMsg(1,"-> \@alias list = >", \join(';', @namepats),"<\n");
		}
		my $matchFlag;
		foreach my $name (sort {$a cmp $b} keys %$alias) {
			if (@namepats) {
				my @foundInAlias = grep {$name =~ /$_/i} @namepats;
				my @foundInDescr = defined $alias->{$name}{DSC} ? grep {$alias->{$name}{DSC} =~ /$_/i} @namepats : ();
				next unless scalar(keys %{{map {($_ => 1)} (@foundInAlias, @foundInDescr)}}) == scalar @namepats;
				# We only show entries which have a hit for EVERY search keyword provided
			}
			$matchFlag = 1;
			my $mvr = $alias->{$name}{MVR};
			my $ovr = $alias->{$name}{OVR};
			my $args = '';
			foreach my $var (sort {$alias->{$name}{VAR}{$a} <=> $alias->{$name}{VAR}{$b}} keys %{$alias->{$name}{VAR}}) {
				if    ($mvr) { $args .= " \$$var"; $mvr-- }
				elsif ($ovr) { $args .= " [\$$var]"; $ovr-- }
				else { $args .= "<error!>" }
			}
			cmdOutput($db, sprintf "%-32s : %s\n", $name.$args, defined $alias->{$name}{DSC} ? $alias->{$name}{DSC} : '<n/a>');
		}
		if ($namepat && !$matchFlag) {
			cmdMessage($db, "No alias found matching $namepat\n");
		}
		$command = '';
	};
	$command eq 'alias reload' && do {
		if ( loadAliasFile($db, $term_io->{AliasFile}) ) {
			if (length $term_io->{AliasMergeFile}) {
				if ( loadAliasFile($db, $term_io->{AliasMergeFile}, 1) ) {
					cmdMessage($db, "Successfully re-loaded default & merge alias files\n");
				}
				else {
					cmdMessage($db, "Successfully re-loaded default alias file BUT failed to re-load merge alias file\n");
				}
			}
			else {
				cmdMessage($db, "Successfully re-loaded alias file\n");
			}
		}
		else {
			cmdMessage($db, "Error re-loading alias file\n");
		}
		$command = '';
	};
	$command eq 'alias show ?' && do {
		cmdMessage($db, "Syntax: ${at}alias show [<pattern>]\n");
		$command = '';
	};
	$command =~ /^alias show(?: (.*))?/ && do {
		my $namepat = $1;
		my $matchFlag;
		foreach my $name (keys %$alias) {
			next if defined $namepat && $name !~ /$namepat/i;
			$matchFlag = 1;
			cmdOutput($db, $name);
			my $mvr = $alias->{$name}{MVR};
			my $ovr = $alias->{$name}{OVR};
			foreach my $var (sort {$alias->{$name}{VAR}{$a} <=> $alias->{$name}{VAR}{$b}} keys %{$alias->{$name}{VAR}}) {
				if    ($mvr) { cmdOutput($db, " \$$var"); $mvr-- }
				elsif ($ovr) { cmdOutput($db, " [\$$var]"); $ovr-- }
				else { cmdOutput($db, "Inconsistency: more vars than expected !: $var") }
#				print "($alias->{$name}{VAR}{$var})";
			}
			cmdOutput($db, "\n");
			foreach my $cnd (@{$alias->{$name}{SEL}}) {
				cmdOutput($db, "   IF " . $cnd->{CND} . "\n      THEN:\n") unless $cnd->{CND} eq 1;
				cmdOutput($db, "   ELSE:\n") if $cnd->{CND} eq 1;
				(my $cmd = quoteCurlyMask($cnd->{CMD}, ';')) =~ s/\s*;\s*/;/g;
				cmdOutput($db, "         " . join("\n         ", map(quoteCurlyUnmask($_, ';'), split(";", $cmd))) . "\n\n");
			}
		}
		if ($namepat && !$matchFlag) {
			cmdMessage($db, "No alias found matching $namepat\n");
		}
		$command = '';
	};
	#
	# &Cd command
	#
	$command =~ /^cd .*\?$/ && do {
		cmdMessage($db, "Syntax: ${at}cd '<relative or new directory>'\n");
		$command = '';
	};
	$command =~ /^cd (.+)/ && do {
		if (chdir $1) {
			cmdOutput($db, join('', "New working directory is:\n", File::Spec->rel2abs(cwd), "\n"));
		}
		else {
			cmdMessage($db, "Invalid directory !\n");
			cmdOutput($db, join('', "Working directory is:\n", File::Spec->rel2abs(cwd), "\n"));
			stopSourcing($db);
		}
		$command = '';
	};
	#
	# &Cls/Clear command
	#
	($command eq 'cls' || $command eq 'clear') && do {
		$command = $^O eq "MSWin32" ? 'cls' : 'clear';
		system($command);
		ReadMode('raw'); # Must re-activate raw mode after a cls, otherwise CTRL-C will kill the script!
		$command = '';
	};
	#
	# &Echo command
	#
	$command eq 'echo info' && do {
		cmdOutput($db, "Echo of commands & prompts : " . ($term_io->{EchoOff} ? ($term_io->{EchoOff} == 2 ? 'sent' : 'off') : 'on') . "\n");
		cmdOutput($db, "Echo of command output     : " . ($term_io->{EchoOutputOff} ? 'off' : 'on') . "\n");
		$command = '';
	};
	$command eq 'echo off' && do {
		cmdMessage($db, "Note: turning off echo only has an effect when sourcing/pasting commands\n") unless $script_io->{AcliControl} || $term_io->{Sourcing};
		$term_io->{EchoOutputOff} = 0 unless $term_io->{EchoOff}; # Only reset this if echo was not already enabled
		$term_io->{EchoOff} = 1;
		$term_io->{EchoReset} = 1 if $term_io->{Sourcing};
		$command = '';
	};
	$command eq 'echo off output off' && do {
		cmdMessage($db, "Note: turning off echo only has an effect when sourcing/pasting commands\n") unless $script_io->{AcliControl} || $term_io->{Sourcing};
		$term_io->{EchoOff} = 1;
		$term_io->{EchoOutputOff} = 1;
		$term_io->{EchoReset} = 1 if $term_io->{Sourcing};
		$command = '';
	};
	$command eq 'echo off output on' && do {
		cmdMessage($db, "Note: turning off echo only has an effect when sourcing/pasting commands\n") unless $script_io->{AcliControl} || $term_io->{Sourcing};
		$term_io->{EchoOutputOff} = 0;
		$term_io->{EchoOff} = 1;
		$term_io->{EchoReset} = 1 if $term_io->{Sourcing};
		$command = '';
	};
	$command eq 'echo on' && do {
		$term_io->{EchoOff} = 0;
		$term_io->{EchoOutputOff} = 0;
		$host_io->{CommandCache} = '';
		$command = '';
	};
	$command eq 'echo sent' && do {
		$term_io->{EchoOff} = 2;
		$term_io->{EchoOutputOff} = 0;
		$term_io->{EchoReset} = 0;
		$host_io->{CommandCache} = '';
		$command = '';
	};
	#
	# &Dictionary command
	#
	$command eq 'dictionary echo always' && do {
		$term_io->{DictionaryEcho} = 1;
		$command = '';
	};
	$command eq 'dictionary echo disable' && do {
		$term_io->{DictionaryEcho} = 0;
		$command = '';
	};
	$command eq 'dictionary echo single' && do {
		$term_io->{DictionaryEcho} = 2;
		$command = '';
	};
	$command eq 'dictionary info' && do {
		my ($portRange, $portCount);
		cmdOutput($db, "Dictionary settings:\n");
		cmdOutput($db, sprintf "	Loaded dictionary : %s\n", defined $term_io->{Dictionary} ? $term_io->{Dictionary} : '');
		cmdOutput($db, sprintf "	Dictionary echoing: %s\n", $term_io->{DictionaryEcho} ? ($term_io->{DictionaryEcho} == 2 ? 'single' : 'always') : 'disable');
		cmdOutput($db, sprintf "	Dictionary file   : %s\n", $term_io->{DictionaryFile});
		unless (defined $dictionary->{prtinp}) {
			cmdOutput($db, "	Input Port Range  :\n");
			unless (defined $dictionary->{prtout}) {
				cmdOutput($db, "	Mapped Host Ports :\n");
			}
		}
		if (defined $dictionary->{prtinp} || defined $dictionary->{prtout}) {
			my $data = setMapHashData($db);
			cmdOutput($db, sprintf "	Input Port Range  : %s (%s ports)\n", $data->{inputPortRange}, $data->{inputPortCount}) if $data->{inputPortCount};
			cmdOutput($db, sprintf "	Mapped Host Ports : %s (%s ports)\n", $data->{mappedPortRange}, $data->{mappedPortCount}) if $data->{mappedPortCount};
			cmdOutput($db, sprintf "	Unused Input Ports: %s (%s ports)\n", $data->{unusedInputPorts}, $data->{unusedInputPortCount}) if $data->{unusedInputPortCount};
			cmdOutput($db, sprintf "	Unused Host Ports : %s (%s ports)\n", $data->{unusedHostPorts}, $data->{unusedHostPortCount}) if $data->{unusedHostPortCount};
		}
		$command = '';
	};
	$command eq 'dictionary list' && do {
		my %list;
		foreach my $path (@DictFilePath) {
			my $globrun = $path . '\\*.dict';
			foreach my $file (glob $globrun) {
				my $basefile = File::Basename::basename($file);
				$list{$basefile} = $path unless grep($_ eq $basefile, keys %list);
			}
		}
		if (%list) { # We found some dictionaries
			cmdMessage($db, "Available Dictionaries:\n\n");
			cmdMessage($db, "   Name         Origin    Vers  Description\n");
			cmdMessage($db, "   ----         ------    ----  -----------\n");
			foreach my $file (sort { $a cmp $b } keys %list) {
				(my $basefile = $file) =~ s/\.dict$//;
				cmdOutput($db, sprintf "   %-12s %s ", uc $basefile, $list{$file} eq File::Spec->canonpath($ScriptDir) ? 'package' : 'private');
				my $dictFile = $list{$file} . '\\' . $file;
				if ( open(DICTFILE, '<', $dictFile) ) {
					my ($version, $description);
					while (<DICTFILE>) {
						if (!defined $version && /^#\s*Version\s*=\s*(\d+\.\d+)\s*$/) {
							$version = $1;
						}
						elsif (!defined $description && /^#\s*(.+)$/) {
							$description = $1;
						}
						last if length $version && length $description;
					}
					close DICTFILE;
					$description = File::Spec->rel2abs($dictFile) unless length $description;
					if (length $version) {
						cmdOutput($db, sprintf "%6s  %s\n", $version, $description);
					}
					else {
						cmdOutput($db, sprintf "%6s  %s\n", "n/a", $description);
					}
				}
				else {
					cmdOutput($db, "Error, unable to read this file!\n");
				}
			}
		}
		else {
			cmdMessage($db, "No dictionaries found\n");
		}
		$command = '';
	};
	$command =~ /^dictionary load .*\?$/ && do {
		cmdMessage($db, "Syntax: ${at}dictionary load <dictionary-name-or-file>\n");
		$command = '';
	};
	$command =~ /^dictionary load (.+)/ && do {
		my $dictName = $1;
		if (defined $term_io->{Dictionary}) {
			cmdMessage($db, "Dictionary '" . $term_io->{Dictionary} . "' already loaded; please unload first\n");
		}
		elsif (loadDictionary($db, $dictName)) {
			($term_io->{Dictionary} = uc $dictName) =~ s/\.dict$//i;
			setPromptSuffix($db);
		}
		else {
			$term_io->{DictionaryFile} = '';
		}
		$command = '';
	};
	$command eq 'dictionary path' && do {
		cmdOutput($db, "Paths for Dictionary files:\n\n");
		cmdOutput($db, "   Origin    Path\n");
		cmdOutput($db, "   ------    ----\n");
		foreach my $path (@DictFilePath) {
			cmdOutput($db, sprintf "   %s   %s\n", $path eq File::Spec->canonpath($ScriptDir) ? 'package' : 'private', File::Spec->rel2abs($path));
		}
		$command = '';
	};
	$command eq 'dictionary port-range info' && do {
		unless (defined $dictionary->{prtinp}) {
			cmdOutput($db, "Input Port Range  :\n");
			unless (defined $dictionary->{prtout}) {
				cmdOutput($db, "Mapped Host Ports :\n");
			}
		}
		if (defined $dictionary->{prtinp} || defined $dictionary->{prtout}) {
			my $data = setMapHashData($db);
			cmdOutput($db, sprintf "Input Port Range  : %s (%s ports)\n", $data->{inputPortRange}, $data->{inputPortCount}) if $data->{inputPortCount};
			cmdOutput($db, sprintf "Mapped Host Ports : %s (%s ports)\n", $data->{mappedPortRange}, $data->{mappedPortCount}) if $data->{mappedPortCount};
			cmdOutput($db, sprintf "Unused Input Ports: %s (%s ports)\n", $data->{unusedInputPorts}, $data->{unusedInputPortCount}) if $data->{unusedInputPortCount};
			cmdOutput($db, sprintf "Unused Host Ports : %s (%s ports)\n", $data->{unusedHostPorts}, $data->{unusedHostPortCount}) if $data->{unusedHostPortCount};
		}
		if (defined $dictionary->{prtmap}) {
			cmdOutput($db, "Mapping detail    :\n");
			for my $inPort (sortByPort keys %{$dictionary->{prtmap}}) {
				cmdOutput($db, sprintf "		%6s => %-6s\n", $inPort, $dictionary->{prtmap}->{$inPort});
			}
		}
		$command = '';
	};
	$command eq 'dictionary port-range input ?' && do {
		cmdMessage($db, "Syntax: ${at}dictionary port-range input <list-or-range-of-ports>\n        ${at}dictionary port-range input clear\n");
		$command = '';
	};
	$command eq 'dictionary port-range input clear' && do {
		delete $dictionary->{prtinp};
		$command = '';
	};
	$command =~ /^dictionary port-range input (\S+)/ && do {
		my ($slotRef, $portRef) = manualSlotPortStruct($1);
		if (defined $portRef) {
			$dictionary->{prtinp} = [$slotRef, $portRef];
			my $data = setMapHashData($db);
			cmdOutput($db, sprintf "Input Port Range  : %s (%s ports)\n", $data->{inputPortRange}, $data->{inputPortCount}) if $data->{inputPortCount};
			cmdOutput($db, sprintf "Mapped Host Ports : %s (%s ports)\n", $data->{mappedPortRange}, $data->{mappedPortCount}) if $data->{mappedPortCount};
			cmdOutput($db, sprintf "Unused Input Ports: %s (%s ports)\n", $data->{unusedInputPorts}, $data->{unusedInputPortCount}) if $data->{unusedInputPortCount};
			cmdOutput($db, sprintf "Unused Host Ports : %s (%s ports)\n", $data->{unusedHostPorts}, $data->{unusedHostPortCount}) if $data->{unusedHostPortCount};
		}
		else {
			cmdMessage($db, "Invalid port list/range; ranges cannot span slots; all ports slot-based, or all ports non-slot-based\n");
		}
		$command = '';
	};
	$command eq 'dictionary port-range mapping ?' && do {
		cmdMessage($db, "Syntax: ${at}dictionary port-range mapping <list-or-range-of-ports>\n        ${at}dictionary port-range mapping clear\n");
		$command = '';
	};
	$command eq 'dictionary port-range mapping clear' && do {
		delete $dictionary->{prtout};
		$command = '';
	};
	$command =~ /^dictionary port-range mapping (\S+)/ && do {
		$dictionary->{prtout} = generateRange($db, scalar generatePortList($host_io, $1), $DevicePortRange{$host_io->{Type}});
		my $data = setMapHashData($db);
		cmdOutput($db, sprintf "Input Port Range  : %s (%s ports)\n", $data->{inputPortRange}, $data->{inputPortCount}) if $data->{inputPortCount};
		cmdOutput($db, sprintf "Mapped Host Ports : %s (%s ports)\n", $data->{mappedPortRange}, $data->{mappedPortCount}) if $data->{mappedPortCount};
		cmdOutput($db, sprintf "Unused Input Ports: %s (%s ports)\n", $data->{unusedInputPorts}, $data->{unusedInputPortCount}) if $data->{unusedInputPortCount};
		cmdOutput($db, sprintf "Unused Host Ports : %s (%s ports)\n", $data->{unusedHostPorts}, $data->{unusedHostPortCount}) if $data->{unusedHostPortCount};
		$command = '';
	};
	$command eq 'dictionary reload' && do {
		if (defined $term_io->{Dictionary}) {
			unless (loadDictionary($db, $term_io->{Dictionary})) {
				$term_io->{Dictionary} = undef;
				$term_io->{DictionaryFile} = '';
				setPromptSuffix($db);
			}
		}
		else {
			cmdMessage($db, "No dictionary file loaded\n");
		}
		$command = '';
	};
	$command eq 'dictionary unload' && do {
		if (defined $term_io->{Dictionary}) {
			$term_io->{Dictionary} = undef;
			$term_io->{DictionaryFile} = '';
			# Delete any pre-existing dictionary variables
			foreach my $var (keys %$vars) {
				next unless $vars->{$var}->{dictscope};
				delete $vars->{$var};
			}
			setPromptSuffix($db);
		}
		else {
			cmdMessage($db, "No dictionary file loaded\n");
		}
		$command = '';
	};
	#
	# &Highlight command
	#
	$command =~ /^highlight background (\w+)/ && do {
		$term_io->{HLbgcolour} = $1;
		setHLstrings($term_io);
		$command = '';
	};
	$command eq 'highlight bright disable' && do {
		$term_io->{HLbright} = 0;
		setHLstrings($term_io);
		$command = '';
	};
	$command eq 'highlight bright enable' && do {
		$term_io->{HLbright} = 1;
		setHLstrings($term_io);
		$command = '';
	};
	$command eq 'highlight disable' && do {
		$term_io->{HLbgcolour} = $term_io->{HLfgcolour} = undef;
		$term_io->{HLbright} = $term_io->{HLreverse} = $term_io->{HLunderline} = 0;
		setHLstrings($term_io);
		$command = '';
	};
	$command =~ /^highlight foreground (\w+)/ && do {
		$term_io->{HLfgcolour} = $1;
		setHLstrings($term_io);
		$command = '';
	};
	$command eq 'highlight info' && do {
		cmdOutput($db, sprintf "	Highlight foreground : %s\n", defined $term_io->{HLfgcolour} ? $term_io->{HLfgcolour} : 'disabled');
		cmdOutput($db, sprintf "	Highlight background : %s\n", defined $term_io->{HLbgcolour} ? $term_io->{HLbgcolour} : 'disabled');
		cmdOutput($db, sprintf "	Highlight bright     : %s\n", $term_io->{HLbright} ? 'enabled' : 'disabled');
		cmdOutput($db, sprintf "	Highlight reverse    : %s\n", $term_io->{HLreverse} ? 'enabled' : 'disabled');
		cmdOutput($db, sprintf "	Highlight underline  : %s\n", $term_io->{HLunderline} ? 'enabled' : 'disabled');
		cmdOutput($db, sprintf "	Highlight rendering  : %sSAMPLE%s\n", $term_io->{HLon}, $term_io->{HLoff});
		$command = '';
	};
	$command eq 'highlight reverse disable' && do {
		$term_io->{HLreverse} = 0;
		setHLstrings($term_io);
		$command = '';
	};
	$command eq 'highlight reverse enable' && do {
		$term_io->{HLreverse} = 1;
		setHLstrings($term_io);
		$command = '';
	};
	$command eq 'highlight underline disable' && do {
		$term_io->{HLunderline} = 0;
		setHLstrings($term_io);
		$command = '';
	};
	$command eq 'highlight underline enable' && do {
		$term_io->{HLunderline} = 1;
		setHLstrings($term_io);
		$command = '';
	};
	#
	# &History command
	#
	$command eq 'history clear all' && do {
		@{$history->{HostRecall}} = ();
		@{$history->{UserEntered}} = ();
		@{$history->{DeviceSent}} = ();
		@{$history->{DeviceSentNoErr}} = ();
		cmdMessage($db, "Cleared all histories (recall, user-entered & device-sent)\n");
		$command = '';
	};
	$command eq 'history clear device-sent' && do {
		@{$history->{DeviceSent}} = ();
		cmdMessage($db, "Cleared history of commands sent to host device\n");
		$command = '';
	};
	$command eq 'history clear no-error-device' && do {
		@{$history->{DeviceSentNoErr}} = ();
		cmdMessage($db, "Cleared history of commands sent to host device which did not error\n");
		$command = '';
	};
	$command eq 'history clear recall' && do {
		@{$history->{HostRecall}} = ();
		cmdMessage($db, "Cleared recall history\n");
		$command = '';
	};
	$command eq 'history clear user-entered' && do {
		@{$history->{UserEntered}} = ();
		cmdMessage($db, "Cleared history of user entered commands\n");
		$command = '';
	};
	$command eq 'history device-sent' && do {
		if (@{$history->{DeviceSent}}) {
			cmdOutput($db, $script_io->{AcliControl} ? "\n" : "------Start of history of commands sent to host------\n");
	 		foreach my $cmd (@{$history->{DeviceSent}}) {
				cmdOutput($db, "$cmd\n");
			}
			cmdOutput($db, $script_io->{AcliControl} ? "\n" : "-------End of history of commands sent to host-------\n");
		}
		else {
			cmdMessage($db, "History is empty\n");
		}
		$command = '';
	};
	$command eq 'history echo disable' && do {
		$term_io->{HistoryEcho} = 0;
		$command = '';
	};
	$command eq 'history echo enable' && do {
		$term_io->{HistoryEcho} = 1;
		$command = '';
	};
	$command eq 'history info' && do {
		cmdMessage($db, "History echoing	: " . ($term_io->{HistoryEcho} ? "enable\n" : "disable\n"));
		$command = '';
	};
	$command eq 'history no-error-device' && do {
		if (@{$history->{DeviceSentNoErr}}) {
			cmdOutput($db, $script_io->{AcliControl} ? "\n" : "------Start of history of commands sent to host which did not error------\n");
	 		foreach my $cmd (@{$history->{DeviceSentNoErr}}) {
				cmdOutput($db, "$cmd\n");
			}
			cmdOutput($db, $script_io->{AcliControl} ? "\n" : "-------End of history of commands sent to host which did not error-------\n");
		}
		else {
			cmdMessage($db, "History is empty\n");
		}
		$command = '';
	};
	$command eq 'history recall' && do {
		my $last = pop @{$history->{HostRecall}} unless $script_io->{AcliControl}; # Take off last command, i.e @history recall
		if (@{$history->{HostRecall}}) {
			for my $i (0 .. $#{$history->{HostRecall}}) {
				cmdOutput($db, sprintf "%5s : %s\n", $i+1, $history->{HostRecall}[$i]);
			}
		}
		else {
			cmdMessage($db, "History is empty\n");
		}
		push(@{$history->{HostRecall}}, $last) unless $script_io->{AcliControl}; # Push back last command
		$command = '';
	};
	$command eq 'history user-entered' && do {
		my $last = pop @{$history->{HostRecall}} unless $script_io->{AcliControl}; # Take off last command, i.e @history recall
		if (@{$history->{UserEntered}}) {
			cmdOutput($db, $script_io->{AcliControl} ? "\n" : "------Start of history of user entered commands------\n");
	 		foreach my $cmd (@{$history->{UserEntered}}) {
				cmdOutput($db, "$cmd\n");
			}
			cmdOutput($db, $script_io->{AcliControl} ? "\n" : "-------End of history of user entered commands-------\n");
		}
		else {
			cmdMessage($db, "History is empty\n");
		}
		push(@{$history->{HostRecall}}, $last) unless $script_io->{AcliControl}; # Push back last command
		$command = '';
	};
	#
	# &Log command
	#
	$command eq 'log auto-log disable' && do {
		if ($script_io->{AutoLog}) {
			closeLogFile($script_io) if defined $script_io->{LogFH};
		}
		$script_io->{AutoLog} = 0;
		$command = '';
	};
	$command eq 'log auto-log enable' && do {
		if ($script_io->{AutoLog}) {
			cmdMessage($db, "Auto-log is already enabled\n");
		}
		elsif (defined $script_io->{LogFH}) {
			cmdMessage($db, sprintf "Already logging to file : %s\n", $script_io->{LogFullPath});
		}
		else {
			$script_io->{AutoLog} = 1;
			if ($host_io->{Connected}) {
				# We open the log file only if connection in place (otherwise it will get opened when we connect)
				if (openLogFile($db)) {
					print "Logging to file: ",$script_io->{LogFullPath}, "\n\n"; # Don't use printOut(cmdMessage) here or it will go to the newly opened log file
				}
				else {
					cmdMessage($db, "Cannot open logging file: $script_io->{LogFullPath}\nReason: $!\n\n");
				}
			}
		}
		$command = '';
	};
	$command eq 'log auto-log retry' && do {
		if ($script_io->{AutoLog}) {
			if (defined $script_io->{LogFH}) {
				cmdMessage($db, sprintf "Already logging to file : %s\n", $script_io->{LogFullPath});
			}
			elsif ($host_io->{Connected} && $script_io->{AutoLogFail}) {
				# We retry to open it
				if (openLogFile($db)) {
					print "Logging to file: ",$script_io->{LogFullPath}, "\n\n"; # Don't use printOut(cmdMessage) here or it will go to the newly opened log file
				}
				else {
					cmdMessage($db, "Cannot open logging file: $script_io->{LogFullPath}\nReason: $!\n\n");
				}
			}
		}
		else {
			cmdMessage($db, "Auto-log is not enabled\n");
		}
		$command = '';
	};
	$command eq 'log info' && do {
		cmdOutput($db, sprintf "Logging path    : %s\n", $script_io->{LogDir} ? $script_io->{LogDir} : '<not-set>');
		cmdOutput($db, sprintf "Logging to file : %s\n", defined $script_io->{LogFH} ? $script_io->{LogFullPath}
							: ($script_io->{AutoLogFail} ? '<failed>' : '<not-logging>'));
		cmdOutput($db, sprintf "Auto-Logging    : %s\n", $script_io->{AutoLog} ? 'enabled' : 'disabled');
		$command = '';
	};
	$command eq 'log path clear' && do {
		$script_io->{LogDir} = '';
		$command = '';
	};
	$command =~ /^log path set .*\?$/ && do {
		cmdMessage($db, "Syntax: ${at}log path set '<directory to use for logging>'\n");
		$command = '';
	};
	$command =~ /^log path set (.+)/ && do {
		if (-e $1 && -d $1) {
			$script_io->{LogDir} = File::Spec->rel2abs($1);
			cmdOutput($db, join('', "Logging path set to:\n", $script_io->{LogDir}, "\n"));
		}
		else {
			cmdMessage($db, "Invalid directory !\n");
		}
		$command = '';
	};
	$command eq 'log start ?' && do {
		cmdMessage($db, "Syntax: ${at}log start <capture-file> [-o|overwrite]\n");
		$command = '';
	};
	$command =~ /^log start (\S+)(?: (-o|-?overwrite))?/ && do {
		my ($file, $ovwr) = ($1, $2);
		if ($script_io->{AutoLog}) {
			cmdMessage($db, "Cannot start/stop logging with Auto-log enabled\n");
		}
		else {
			if (defined $script_io->{LogFH}) {
				cmdMessage($db, "Closing already open log file:\n$script_io->{LogFullPath}\n");
				closeLogFile($script_io);
			}
			$script_io->{LogFile} = $file;
			$script_io->{OverWrite} = $ovwr ? '>' : '>>';
			if ($host_io->{Connected} && $script_io->{LogFile} =~ /^\.[\w\d]+$/) { # .xxx -> switchname.xxx
				$script_io->{LogFile} = switchname($host_io) . $script_io->{LogFile};
			}
			if (openLogFile($db)) {
				print "Logging to file: ",$script_io->{LogFullPath}, "\n\n"; # Don't use printOut(cmdMessage) here or it will go to the newly opened log file
			}
			else {
				cmdMessage($db, "Cannot open logging file: $script_io->{LogFullPath}\nReason: $!\n\n");
			}
		}
		$command = '';
	};
	$command eq 'log stop' && do {
		if ($script_io->{AutoLog}) {
			cmdMessage($db, "Cannot start/stop logging with Auto-log enabled\n");
		}
		else {
			closeLogFile($script_io) if defined $script_io->{LogFH};
		}
		$command = '';
	};
	#
	# &Ls & Dir command
	#
	$command =~ /^ls .*\?/ && do {
		cmdMessage($db, "Syntax: \@ls [<arguments>]\n");
		$command = '';
	};
	$command =~ /^dir .*\?/ && do {
		cmdMessage($db, "Syntax: \@dir [<arguments>]\n");
		$command = '';
	};
	$command =~ /^(?:ls|dir)(?: (.*))?/ && do {
		$command = $^O eq "MSWin32" ? 'dir' : 'ls';
		$command .= " $1" if defined $1;
		cmdOutput($db, join('', qx/$command/));
		$command = '';
	};
	#
	# &Mkdir command
	#
	$command =~ /^mkdir .*\?$/ && do {
		cmdMessage($db, "Syntax: \@mkdir '<new directory to create>'\n");
		$command = '';
	};
	$command =~ /^mkdir (.+)/ && do {
		if (mkdir $1) {
			cmdOutput($db, join('', "Created directory:\n", File::Spec->rel2abs($1), "\n"));
		}
		else {
			cmdMessage($db, "Failed to create directory: $!\n");
			stopSourcing($db);
		}
		$command = '';
	};
	#
	# &More command
	#
	$command eq 'more disable' && do {
		$term_io->{MorePaging} = 0;
		$host_io->{CLI}->device_more_paging(
			Enable		=> $term_io->{MorePaging},
			Blocking	=> 1,
		) if defined $host_io->{SyncMorePaging} && !$term_io->{PseudoTerm};
		$command = '';
	};
	$command eq 'more enable' && do {
		$term_io->{MorePaging} = 1;
		$host_io->{CLI}->device_more_paging(
			Enable		=> $term_io->{MorePaging},
			Blocking	=> 1,
		) if defined $host_io->{SyncMorePaging} && !$term_io->{PseudoTerm};
		$command = '';
	};
	$command eq 'more info' && do {
		if ($term_io->{MorePaging}) {
			cmdOutput($db, "Local more paging                        : enabled\n");
		}
		else {
			cmdOutput($db, "Local more paging                        : disabled\n");
		}
		cmdOutput($db, "Lines per page                           : $term_io->{MorePageLines}\n");
		cmdOutput($db, "Toggle CTRL character                    : " . $term_io->{CtrlMorePrn} . "\n");
		cmdOutput($db, "Local paging mode synchronized on device : " . (defined $host_io->{SyncMorePaging} ? 'enabled' : 'disabled') . "\n");
		cmdOutput($db, "Underlying device more paging mode       : " . (defined $host_io->{SyncMorePaging} ? 'synchronized' : ($host_io->{MorePaging} ? 'enabled' : 'disabled')) . "\n");
		$command = '';
	};
	$command eq 'more lines ?' && do {
		cmdMessage($db, "Syntax: ${at}more lines <number of lines per page>\n");
		$command = '';
	};
	$command =~ /^more lines (\d+)/ && do {
		$term_io->{MorePageLines} = $1;
		$command = '';
	};
	$command eq 'more sync disable' && do {
		if (defined $DeviceMorePaging{$host_io->{Type}}[0]) {
			$host_io->{MorePaging} = $host_io->{MorePagingInit};
			$host_io->{CLI}->device_more_paging(
				Enable		=> $host_io->{MorePaging},
				Blocking	=> 1,
			) unless $term_io->{PseudoTerm};
			$host_io->{SyncMorePaging} = undef;
		}
		else {
			cmdMessage($db, "More sync mode not supported on family type $host_io->{Type}\n");
		}
		$command = '';
	};
	$command eq 'more sync enable' && do {
		if (defined $DeviceMorePaging{$host_io->{Type}}[0]) {
			$host_io->{CLI}->device_more_paging(
				Enable		=> $term_io->{MorePaging},
				Blocking	=> 1,
			) unless $term_io->{PseudoTerm};
			$host_io->{SyncMorePaging} = 0;
		}
		else {
			cmdMessage($db, "More sync mode not supported on family type $host_io->{Type}\n");
		}
		$command = '';
	};
	#
	# &PeerCP command
	#
	$command eq 'peercp connect' && do {
		if ($peercp_io->{Connected}) {
			cmdMessage($db, "Peer CPU connection already in place\n");
		}
		elsif (!$host_io->{DualCP}) {
			cmdMessage($db, "This is a single CPU system\n");
		}
		else {
			cmdMessage($db, "Connecting to peer CPU ...\n");
			if ( connectToPeerCP($db, 1) && handleDevicePeerCP($db, 1) ) {
				if ($peercp_io->{Connect_OOB}) {
					cmdMessage($db, "Directly connected to Peer CPU on OOB IP $peercp_io->{Connect_IP}\n");
				}
				else {
					cmdMessage($db, "Connected to Peer CPU via shadow connection to $host_io->{Name}\n");
				}
			}
			else {
				cmdMessage($db, "Failed to connect to Peer CPU: $peercp_io->{CLI}->errmsg\n");
			}
		}
		$command = '';
	};
	$command eq 'peercp disconnect' && do {
		if ($peercp_io->{Connected}) { # Tear down connection to peer CPU
			disconnectPeerCP($db);
			cmdMessage($db, "Connection to Peer CPU closed\n");
		}
		else {
			cmdMessage($db, "No Peer CPU connection to close\n");
		}
		$command = '';
	};
	$command eq 'peercp info' && do {
		if ($peercp_io->{Connected}) {
			if ($peercp_io->{Connect_OOB}) {
				cmdMessage($db, "Directly connected to Peer CPU on OOB IP $peercp_io->{Connect_IP}\n");
			}
			else {
				cmdMessage($db, "Connected to Peer CPU via shadow connection to $host_io->{Name}\n");
			}
		}
		else {
			cmdMessage($db, "Not connected to Peer CPU\n");
		}
		$command = '';
	};
	#
	# &Ping command
	#
	$command eq 'ping ?' && do {
		cmdMessage($db, "Syntax: ${at}ping <hostname|ip>\n");
		$command = '';
	};
	$command =~ /^ping (.+)/ && do {
		my $host = $1;
		if ( ping(host => $host, timeout => 2) ) {
			cmdOutput($db, "$host is alive\n");
		}
		else {
			cmdOutput($db, "no answer from $host\n");
		}
		$command = '';
	};
	#
	# &Pseudo command
	#
	$command eq 'pseudo attribute clear ?' && do {
		cmdMessage($db, "Syntax: ${at}pseudo attribute clear <name>\n");
		$command = '';
	};
	$command =~ /^pseudo attribute clear (\w+)/ && do {
		if ($term_io->{PseudoTerm}) {
			if (exists $term_io->{PseudoAttribs}->{$1} && !ref($term_io->{PseudoAttribs}->{$1})) {
				delete $term_io->{PseudoAttribs}->{$1};
				cmdMessage($db, "Deleted pseudo attribute '$1'\n");
			}
			else {
				cmdMessage($db, "Pseudo attribute '$1' does not exist\n");
			}
		}
		else {
			cmdMessage($db, "Pseudo terminal is not enabled\n");
		}
		$command = '';
	};
	$command eq 'pseudo attribute info' && do {
		if ($term_io->{PseudoTerm}) {
			foreach my $key (keys %{$term_io->{PseudoAttribs}}) {
				cmdOutput($db, sprintf "%-16s = %s\n", "{$key}", $term_io->{PseudoAttribs}->{$key});
			}
		}
		else {
			cmdMessage($db, "Pseudo terminal is not enabled\n");
		}
		$command = '';
	};
	$command eq 'pseudo attribute set ?' && do {
		cmdMessage($db, "Syntax: ${at}pseudo attribute set <name> = <value>\n");
		$command = '';
	};
	$command =~ /^pseudo attribute set (\w+)\s*=\s*(\S+)/ && do {
		if ($term_io->{PseudoTerm}) {
			$term_io->{PseudoAttribs}->{$1} = $2;
			cmdOutput($db, sprintf "%-16s = %s\n", "{$1}", $term_io->{PseudoAttribs}->{$1});
		}
		else {
			cmdMessage($db, "Pseudo terminal is not enabled\n");
		}
		$command = '';
	};
	$command eq 'pseudo echo disable' && do {
		if ($term_io->{PseudoTerm}) {
			$term_io->{PseudoTermEcho} = 0;
			cmdOutput($db, "Pseudo echoing of commands disabled\n");
		}
		else {
			cmdMessage($db, "Pseudo terminal is not enabled\n");
		}
		$command = '';
	};
	$command eq 'pseudo echo enable' && do {
		if ($term_io->{PseudoTerm}) {
			$term_io->{PseudoTermEcho} = 1;
			cmdOutput($db, "Pseudo echoing of commands enabled\n");
		}
		else {
			cmdMessage($db, "Pseudo terminal is not enabled\n");
		}
		$command = '';
	};
	$command eq 'pseudo info' && do {
		if ($term_io->{PseudoTerm}) {
			cmdOutput($db, sprintf "	Pseudo Terminal     : %s\n", $term_io->{PseudoTerm} ? 'enabled' : 'disabled');
			cmdOutput($db, sprintf "	Pseudo Name/Id      : %s\n", $term_io->{PseudoTermName});
			cmdOutput($db, sprintf "	Pseudo Prompt       : %s\n", $term_io->{PseudoTerm} ? $host_io->{Prompt} : '');
			cmdOutput($db, sprintf "	Pseudo Command Echo : %s\n", $term_io->{PseudoTermEcho} ? 'enabled' : 'disabled');
			cmdOutput($db, sprintf "	Pseudo Family Type  : %s\n", $host_io->{Type});
			cmdOutput($db, sprintf "	Pseudo ACLI/NNCLI   : %s\n", $term_io->{AcliType} ? 'Yes' : 'No');
			cmdOutput($db, sprintf "	Pseudo Port Range   : %s\n", exists $term_io->{PseudoAttribs}->{ports} ? generateRange($db, scalar generatePortList($host_io, 'ALL'), $DevicePortRange{$host_io->{Type}}) : 'unset');
		}
		else {
			cmdMessage($db, "Pseudo terminal is not enabled\n");
		}
		$command = '';
	};
	$command eq 'pseudo list' && do {
		my %list;
		foreach my $path (@VarFilePath) {
			my $globvar = $path . '\\pseudo.*.vars';
			foreach my $file (glob $globvar) {
				my $basefile = File::Basename::basename($file);
				$list{$basefile} = $path unless grep($_ eq $basefile, keys %list);
			}
		}
		if (%list) { # We found some dictionaries
			cmdMessage($db, "Available Saved Pseudo Terminals:\n\n");
			cmdMessage($db, "   Name                   Origin    Family Type  Port Range\n");
			cmdMessage($db, "   --------------------   -------   -----------  ----------\n");
			foreach my $file (sort { $a cmp $b } keys %list) {
				(my $name = $file) =~ s/^pseudo\.([^\.]+)\.vars$/$1/;
				cmdOutput($db, sprintf "   %-20s   %s   ", uc $name, $list{$file} eq File::Spec->canonpath($ScriptDir) ? 'package' : 'private');
				my $varFile = $list{$file} . '\\' . $file;
				if ( open(VARFILE, '<', $varFile) ) {
					my ($familyType, $portRange);
					while (<VARFILE>) {
						if (!defined $familyType && /^\s*:family-type\s*=\s*(.+?)\s*$/) {
							$familyType = $1;
						}
						elsif (!defined $portRange && /^\s*:port-range\s*=\s*(.+?)\s*$/) {
							$portRange = $1;
						}
						last if length $familyType && length $portRange;
					}
					close VARFILE;
					cmdOutput($db, sprintf "%-11s  %s\n", defined $familyType ? $familyType : '', defined $portRange ? $portRange : '');
				}
				else {
					cmdOutput($db, "Error, unable to read this file!\n");
				}
			}
			cmdMessage($db, "\n");
		}
		else {
			cmdMessage($db, "No saved pseudo terminals found\n");
		}
		$command = '';
	};
	$command =~ /^pseudo load .*\?$/ && do {
		cmdMessage($db, "Syntax: ${at}pseudo load <pseudo-name>\n");
		$command = '';
	};
	$command eq 'pseudo name ?' && do {
		cmdMessage($db, "Syntax: ${at}pseudo name <name>\n");
		$command = '';
	};
	$command =~ /^pseudo name (\S+)/ && do {
		if ($term_io->{PseudoTerm}) {
			$term_io->{PseudoTermName} = $1;
			cmdOutput($db, "Pseudo terminal name(/id) set. To save terminal use '\@save all'\n");
		}
		else {
			cmdMessage($db, "Pseudo terminal is not enabled\n");
		}
		$command = '';
	};
	$command eq 'pseudo port-range ?' && do {
		cmdMessage($db, "Syntax: ${at}pseudo port-range <list-or-range-of-ports>\n        ${at}pseudo port-range clear\n");
		$command = '';
	};
	$command eq 'pseudo port-range clear' && do {
		if ($term_io->{PseudoTerm}) {
			$host_io->{Slots} = $host_io->{Ports} = undef;
			delete $term_io->{PseudoAttribs}->{slots};
			delete $term_io->{PseudoAttribs}->{ports};
			delete $dictionary->{prtout};	# In case something was set
			cmdMessage($db, "Cleared pseudo terminal port-range\n");
		}
		else {
			cmdMessage($db, "Pseudo terminal is not enabled\n");
		}
		$command = '';
	};
	$command =~ /^pseudo port-range (\S+)/ && do {
		if ($term_io->{PseudoTerm}) {
			my ($slotRef, $portRef) = manualSlotPortStruct($1);
			if (defined $portRef) {
				$host_io->{Slots} = $slotRef;
				$host_io->{Ports} = $portRef;
				$term_io->{PseudoAttribs}->{slots} = $slotRef;
				$term_io->{PseudoAttribs}->{ports} = $portRef;
				cmdOutput($db, sprintf "Port Range: %s\n", generateRange($db, scalar generatePortList($host_io, 'ALL'), $DevicePortRange{$host_io->{Type}}));
			}
			else {
				cmdMessage($db, "Invalid port list/range; ranges cannot span slots; all ports slot-based, or all ports non-slot-based\n");
			}
		}
		else {
			cmdMessage($db, "Pseudo terminal is not enabled\n");
		}
		$command = '';
	};
	$command =~ /^pseudo prompt .*\?/ && do {
		cmdMessage($db, "Syntax: ${at}pseudo prompt <prompt>\n");
		$command = '';
	};
	$command =~ /^pseudo prompt(?: (.+))?/ && do {
		if ($term_io->{PseudoTerm}) {
			my $pseudoprompt = quotesRemove($1);
			$host_io->{Prompt} = $prompt->{Match} = $pseudoprompt;
			$prompt->{Regex} = qr/($prompt->{Match})/;
		}
		else {
			cmdMessage($db, "Pseudo terminal is not enabled\n");
		}
		$command = '';
	};
	$command =~ /^pseudo type (\S+)/ && do {
		if ($term_io->{PseudoTerm}) {
			if (exists $PseudoSelectionAttributes{$1}) {
				$host_io->{Type} = $PseudoSelectionAttributes{$1}{family_type};
				$term_io->{AcliType} = $PseudoSelectionAttributes{$1}{is_acli};
				%{$term_io->{PseudoAttribs}} = (); #Empty it first
				for my $key (keys %{$PseudoSelectionAttributes{$1}}) {
					$term_io->{PseudoAttribs}->{$key} = $PseudoSelectionAttributes{$1}{$key};
				}
			}
			else {
				cmdMessage($db, "Invalid pseudo type selected; must be in: ", join(',', keys %PseudoSelectionAttributes), "\n");
			}
		}
		else {
			cmdMessage($db, "Pseudo terminal is not enabled\n");
		}
		$command = '';
	};
	#
	# &Pwd command
	#
	$command eq 'pwd' && do {
		cmdOutput($db, join('', "Working directory is:\n", File::Spec->rel2abs(cwd), "\n"));
		$command = '';
	};
	#
	# &Rmdir command
	#
	$command =~ /^rmdir .*\?$/ && do {
		cmdMessage($db, "Syntax: \@rmdir '<directory to delete>'\n");
		$command = '';
	};
	$command =~ /^rmdir (.+)/ && do {
		if (rmdir $1) {
			cmdOutput($db, join('', "Deleted directory:\n", File::Spec->rel2abs($1), "\n"));
		}
		else {
			cmdMessage($db, "Failed to delete directory: $!\n");
			stopSourcing($db);
		}
		$command = '';
	};
	#
	# &Save command
	#
	$command eq 'save vars' && do {
		if (!$host_io->{Connected} && !$term_io->{PseudoTerm}) { # Only in control cmd processing
			cmdMessage($db, "Not connected to a device\n");
		}
		elsif (!defined $host_io->{BaseMAC} && !$term_io->{PseudoTerm}) {
			cmdMessage($db, "Unable to save as no base MAC detected for device\n");
		}
		elsif (saveVarFile($db, 1, 0, 0)) {
			cmdMessage($db, "Variables saved to:\n $host_io->{VarsFile}\n");
		}
		else {
			cmdMessage($db, "Error saving variables to file\n");
			stopSourcing($db);
		}
		$command = '';
	};
	$command eq 'save all' && do {
		if (!$host_io->{Connected} && !$term_io->{PseudoTerm}) { # Only in control cmd processing
			cmdMessage($db, "Not connected to a device\n");
		}
		elsif (!defined $host_io->{BaseMAC} && !$term_io->{PseudoTerm}) {
			cmdMessage($db, "Unable to save as no base MAC detected for device\n");
		}
		elsif (saveVarFile($db, 1, 1, 1)) {
			cmdMessage($db, "Variables, open sockets & working directory saved to:\n $host_io->{VarsFile}\n");
		}
		else {
			cmdMessage($db, "Error saving variables, open sockets & working directory to file\n");
			stopSourcing($db);
		}
		$command = '';
	};
	$command eq 'save delete' && do {
		if (!$host_io->{Connected} && !$term_io->{PseudoTerm}) { # Only in control cmd processing
			cmdMessage($db, "Not connected to a device\n");
		}
		elsif ($host_io->{VarsFile}) {
			if (unlink $host_io->{VarsFile}) {
				cmdMessage($db, "Deleted variable file $host_io->{VarsFile}\n");
				$host_io->{VarsFile} = '';
			}
			else {
				cmdMessage($db, "Failed delete of $host_io->{VarsFile}: $!\n");
			}
		}
		else {
			cmdMessage($db, "No save file to delete\n");
		}
		$command = '';
	};
	$command eq 'save info' && do {
		if (!$host_io->{Connected} && !$term_io->{PseudoTerm}) { # Only in control cmd processing
			cmdMessage($db, "Not connected to a device\n");
		}
		elsif ($host_io->{VarsFile}) {
			if ( open(VARFILE, '<', $host_io->{VarsFile}) ) {
				flock(VARFILE, 1); # 1 = LOCK_SH; Put a shared lock on the file (wait to read if it's being changed)
				local $/;	# Read in file in one shot
				cmdOutput($db, $host_io->{VarsFile} . ":\n\n");
				cmdOutput($db, <VARFILE> . "\n");
				close VARFILE;
			}
			else {
				cmdMessage($db, "Unable to open save file: $host_io->{VarsFile}\n");
			}
		}
		else {
			cmdMessage($db, "No save file for connected device\n");
		}
		$command = '';
	};
	$command eq 'save reload' && do {
		if (!$host_io->{Connected} && !$term_io->{PseudoTerm}) { # Only in control cmd processing
			cmdMessage($db, "Not connected to a device\n");
		}
		else {
			$term_io->{SockSetSwitch} = 0; # Override this flag
			if (loadVarFile($db)) {
				%{$host_io->{UnsavedVars}} = ();
			}
			else {
				cmdMessage($db, "Unable to reload saved var file settings\n");
			}
		}
		$command = '';
	};
	$command eq 'save sockets' && do {
		if (!$host_io->{Connected} && !$term_io->{PseudoTerm}) { # Only in control cmd processing
			cmdMessage($db, "Not connected to a device\n");
		}
		elsif (!defined $host_io->{BaseMAC} && !$term_io->{PseudoTerm}) {
			cmdMessage($db, "Unable to save as no base MAC detected for device\n");
		}
		elsif (saveVarFile($db, 0, 1, 0)) {
			cmdMessage($db, "Open sockets saved to:\n $host_io->{VarsFile}\n");
		}
		else {
			cmdMessage($db, "Error saving open sockets to file\n");
			stopSourcing($db);
		}
		$command = '';
	};
	$command eq 'save vars' && do {
		if (!$host_io->{Connected} && !$term_io->{PseudoTerm}) { # Only in control cmd processing
			cmdMessage($db, "Not connected to a device\n");
		}
		elsif (!defined $host_io->{BaseMAC} && !$term_io->{PseudoTerm}) {
			cmdMessage($db, "Unable to save as no base MAC detected for device\n");
		}
		elsif (saveVarFile($db, 1, 0, 0)) {
			cmdMessage($db, "Variables saved to:\n $host_io->{VarsFile}\n");
		}
		else {
			cmdMessage($db, "Error saving variables to file\n");
			stopSourcing($db);
		}
		$command = '';
	};
	$command eq 'save workdir' && do {
		if (!$host_io->{Connected} && !$term_io->{PseudoTerm}) { # Only in control cmd processing
			cmdMessage($db, "Not connected to a device\n");
		}
		elsif (!defined $host_io->{BaseMAC} && !$term_io->{PseudoTerm}) {
			cmdMessage($db, "Unable to save as no base MAC detected for device\n");
		}
		elsif (saveVarFile($db, 0, 0, 1)) {
			cmdMessage($db, "Working directory saved to:\n $host_io->{VarsFile}\n");
		}
		else {
			cmdMessage($db, "Error saving working directory to file\n");
			stopSourcing($db);
		}
		$command = '';
	};
	#
	# &Sed command
	#
	$command eq 'sed colour ?' && do {
		cmdMessage($db, "Syntax: ${at}sed colour <profile-name>|info'\n");
		$command = '';
	};
	$command eq 'sed colour info' && do {
		if (%{$term_io->{ColourProfiles}}) {
			cmdOutput($db, "Sed colour profiles:\n");
			for my $profile (sort {$a cmp $b} keys %{$term_io->{ColourProfiles}}) {
				cmdOutput($db, sprintf "   %-10s : %s\n", $profile, displayColourConfig($term_io->{ColourProfiles}->{$profile}));
			}
		}
		else {
			cmdOutput($db, "No sed colour profiles\n");
		}
		$command = '';
	};
	$command =~ /^sed colour [\'\"]?(\w+)[\'\"]? (\w+) (\w+)/ && do {
		my ($profile, $setting, $value) = ($1, $2, $3);
		$term_io->{ColourProfiles}->{$profile}->{$setting} = $value eq 'enable' ? 1 : $value eq 'disable' ? 0 : $value;
		for my $idx (sort {$a <=> $b} keys %{$term_io->{SedColourPats}}) {
			if ($term_io->{SedColourPats}->{$idx}->[4] eq $profile) {
				my ($hlOn, $hlOff) = returnHLstrings($term_io->{ColourProfiles}->{$profile});
				my $replace = $hlOn . '$&' . $hlOff;
				$term_io->{SedColourPats}->{$idx}->[2] = $replace;
				$term_io->{SedColourPats}->{$idx}->[3] = qq{"$replace"};
				cmdMessage($db, "Updated existing output colour pattern $idx\n");
			}
		}
		$command = '';
	};
	$command =~ /^sed colour [\'\"]?(\w+)[\'\"]? delete$/ && do {
		my $profile = $1;
		my $inUse;
		for my $idx (sort {$a <=> $b} keys %{$term_io->{SedColourPats}}) {
			if ($term_io->{SedColourPats}->{$idx}->[4] eq $profile) {
				$inUse = $idx;
				last;
			}
		}
		if ($inUse) {
			cmdMessage($db, "Sed colour profile '$profile' is in use in sed output colour pattern $inUse\n");
		}
		else {
			delete $term_io->{ColourProfiles}->{$profile} if exists $term_io->{ColourProfiles}->{$profile};
		}
		$command = '';
	};
	$command eq 'sed info' && do {
		cmdOutput($db, "Sed file: " . $term_io->{SedFile} . "\n");
		if (%{$term_io->{SedInputPats}}) {
			cmdOutput($db, "\nSed input patterns:\n");
			for my $idx (sort {$a <=> $b} keys %{$term_io->{SedInputPats}}) {
				my $cat = defined $term_io->{SedInputPats}->{$idx}->[0] ? "[".$term_io->{SedInputPats}->{$idx}->[0]."] " : '';
				cmdOutput($db, sprintf "   %2s : %s'%s'\n", $idx, $cat, $term_io->{SedInputPats}->{$idx}->[1]);
				cmdOutput($db, sprintf "        '%s'\n", $term_io->{SedInputPats}->{$idx}->[2]) if $::Debug;
				if ($term_io->{SedInputPats}->{$idx}->[5]) {
					cmdOutput($db, sprintf "        --> '%s'\n", $term_io->{SedInputPats}->{$idx}->[3]);
				}
				else {
					cmdOutput($db, sprintf "        --> {%s}\n", $term_io->{SedInputPats}->{$idx}->[3]);
				}
				#cmdOutput($db, sprintf "            '%s'\n", $term_io->{SedInputPats}->{$idx}->[4]) if $::Debug;
			}
		}
		else {
			cmdOutput($db, "\nNo sed input patterns set\n");
		}
		if (%{$term_io->{SedOutputPats}}) {
			cmdOutput($db, "\nSed output patterns:\n");
			for my $idx (sort {$a <=> $b} keys %{$term_io->{SedOutputPats}}) {
				my $cat = defined $term_io->{SedOutputPats}->{$idx}->[0] ? "[".$term_io->{SedOutputPats}->{$idx}->[0]."] " : '';
				cmdOutput($db, sprintf "   %2s : %s'%s'\n", $idx, $cat, $term_io->{SedOutputPats}->{$idx}->[1]);
				cmdOutput($db, sprintf "        '%s'\n", $term_io->{SedOutputPats}->{$idx}->[2]) if $::Debug;
				if ($term_io->{SedOutputPats}->{$idx}->[5]) {
					cmdOutput($db, sprintf "        --> '%s'\n", $term_io->{SedOutputPats}->{$idx}->[3]);
				}
				else {
					cmdOutput($db, sprintf "        --> {%s}\n", $term_io->{SedOutputPats}->{$idx}->[3]);
				}
				#cmdOutput($db, sprintf "            '%s'\n", $term_io->{SedOutputPats}->{$idx}->[4]) if $::Debug;
			}
		}
		else {
			cmdOutput($db, "\nNo sed output patterns set\n");
		}
		if (%{$term_io->{SedColourPats}}) {
			cmdOutput($db, "\nSed output colour patterns:\n");
			for my $idx (sort {$a <=> $b} keys %{$term_io->{SedColourPats}}) {
				my $cat = defined $term_io->{SedColourPats}->{$idx}->[0] ? "[".$term_io->{SedColourPats}->{$idx}->[0]."] " : '';
				my $colour = '';
				my $replace = "'" . $term_io->{SedColourPats}->{$idx}->[3] . "'";
				my $qqreplace = $term_io->{SedColourPats}->{$idx}->[4];
				if ($term_io->{SedColourPats}->{$idx}->[5]) {
					$replace =~ s/\e/\\e/g;
					$qqreplace =~ s/\e/\\e/g;
					$colour = sprintf("(colour profile: %s$term_io->{SedColourPats}->{$idx}->[5]%s)", returnHLstrings($term_io->{ColourProfiles}->{$term_io->{SedColourPats}->{$idx}->[5]}));
				}
				cmdOutput($db, sprintf "   %2s : %s'%s'\n", $idx, $cat, $term_io->{SedColourPats}->{$idx}->[1]);
				cmdOutput($db, sprintf "        '%s'\n", $term_io->{SedColourPats}->{$idx}->[2]) if $::Debug;
				cmdOutput($db, sprintf "        --> %-30s %s\n", $replace, $colour);
				#cmdOutput($db, sprintf "            '%s'\n", $qqreplace) if $::Debug;
			}
		}
		else {
			cmdOutput($db, "\nNo sed output colour patterns set\n");
		}
		$command = '';
	};
	$command eq 'sed input add ?' && do {
		cmdMessage($db, "Syntax: ${at}sed input add [<index:1-$MaxSedPatterns>] '<pattern>' '<replacement>'\n");
		cmdMessage($db, "Syntax: ${at}sed input add [<index:1-$MaxSedPatterns>] '<pattern>' '{<replacement-code>}'\n");
		$command = '';
	};
	$command =~ /^sed input add (?:(\d+) )?(?|"([^\"]+)"|'([^\']+)') (?:'\{(.+)\}'|(?|"([^\"]*)"|'([^\']*)'))/ && do {
		my ($idx, $pattern, $code, $replace) = ($1, $2, $3, $4);
		if (defined $idx) {
			if ($idx > $MaxSedPatterns) {
				cmdMessage($db, "Only patterns 1-$MaxSedPatterns allowed\n");
				$idx = undef;
			}
			elsif (exists $term_io->{SedInputPats}->{$idx}) {
				cmdMessage($db, "Input pattern $idx already defined; delete existing first\n");
				$idx = undef;
			}
		}
		else { # No index provided
			if ($term_io->{Sourcing}) { # We allocate an id above $MaxSedPatterns
				$idx = 1; # In case SedInputPats empty
				$idx = (sort { $a <=> $b } keys %{$term_io->{SedInputPats}})[-1] + 1 if %{$term_io->{SedInputPats}}; # Next unused index number
				$idx = $MaxSedPatterns + 1 if $idx <= $MaxSedPatterns; # Starting from $MaxSedPatterns + 1
			}
			else {
				cmdMessage($db, "Input pattern index value must be supplied if not in sourcing mode\n");
			}
		}
		if ($idx) {
			my ($qrPattern, $message) = validateQrPattern($pattern);
			my $cat = $host_io->{Type} ? $host_io->{Type} : undef;
			if ($message) {
				cmdMessage($db, "Invalid regular expression: $message");
			}
			elsif (defined $code) {
				my $replaceSub = sub { eval $code };
				$term_io->{SedInputPats}->{$idx} = [$cat, $pattern, $qrPattern, $code, $replaceSub];
				cmdOutput($db, "Input pattern $idx added : '$pattern' => {$code}\n");
			}
			else {
				(my $replfmt = $replace) =~ s/\"/\\"/g; #"
				$term_io->{SedInputPats}->{$idx} = [$cat, $pattern, $qrPattern, $replace, qq{"$replfmt"}, 1];
				cmdOutput($db, "Input pattern $idx added : '$pattern' => '$replace'\n");
			}
		}
		$command = '';
	};
	$command eq 'sed input delete ?' && do {
		cmdMessage($db, "Syntax: ${at}sed input delete <index:1-$MaxSedPatterns>\n");
		$command = '';
	};
	$command =~ /^sed input delete (\d+)/ && do {
		my $idx = $1;
		if (!exists $term_io->{SedInputPats}->{$idx}) {
			cmdMessage($db, "Input pattern $idx does not exist\n");
		}
		else {
			delete $term_io->{SedInputPats}->{$idx};
			cmdMessage($db, "Input pattern $idx deleted\n");
		}
		$command = '';
	};
	$command eq 'sed output add ?' && do {
		cmdMessage($db, "Syntax: ${at}sed output add [<index:1-$MaxSedPatterns>] '<pattern>' '<replacement>'\n");
		cmdMessage($db, "Syntax: ${at}sed output add [<index:1-$MaxSedPatterns>] '<pattern>' '{<replacement-code>}'\n");
		cmdMessage($db, "Syntax: ${at}sed output add colour [<index:1-$MaxSedPatterns>] '<pattern>' '<colour-profile>'\n");
		$command = '';
	};
	$command =~ /^sed output add (?:(\d+) )?(?|"([^\"]+)"|'([^\']+)') (?:'\{(.+)\}'|(?|"([^\"]*)"|'([^\']*)'))/ && do {
		my ($idx, $pattern, $code, $replace) = ($1, $2, $3, $4);
		if (defined $idx) {
			if ($idx > $MaxSedPatterns) {
				cmdMessage($db, "Only patterns 1-$MaxSedPatterns allowed\n");
				$idx = undef;
			}
			elsif (exists $term_io->{SedOutputPats}->{$idx}) {
				cmdMessage($db, "Output pattern $idx already defined; delete existing first\n");
				$idx = undef;
			}
		}
		else { # No index provided
			if ($term_io->{Sourcing}) { # We allocate an id above $MaxSedPatterns
				$idx = 1; # In case SedOutputPats empty
				$idx = (sort { $a <=> $b } keys %{$term_io->{SedOutputPats}})[-1] + 1 if %{$term_io->{SedOutputPats}}; # Next unused index number
				$idx = $MaxSedPatterns + 1 if $idx <= $MaxSedPatterns; # Starting from $MaxSedPatterns + 1
			}
			else {
				cmdMessage($db, "Output pattern index value must be supplied if not in sourcing mode\n");
			}
		}
		if ($idx) {
			my ($qrPattern, $message) = validateQrPattern($pattern);
			my $cat = $host_io->{Type} ? $host_io->{Type} : undef;
			if ($message) {
				cmdMessage($db, "Invalid regular expression: $message");
			}
			elsif (defined $code) {
				my $replaceSub = sub { eval $code };
				$term_io->{SedOutputPats}->{$idx} = [$cat, $pattern, $qrPattern, $code, $replaceSub];
				cmdOutput($db, "Output pattern $idx added : '$pattern' => {$code}\n");
			}
			else {
				(my $replfmt = $replace) =~ s/\"/\\"/g; #"
				$term_io->{SedOutputPats}->{$idx} = [$cat, $pattern, $qrPattern, $replace, qq{"$replfmt"}, 1];
				cmdOutput($db, "Output pattern $idx added : '$pattern' => '$replace'\n");
			}
		}
		$command = '';
	};
	$command eq 'sed output add colour ?' && do {
		cmdMessage($db, "Syntax: ${at}sed output add colour <index:1-$MaxSedPatterns> '<pattern>' '<colour-profile>'\n");
		$command = '';
	};
	$command =~ /^sed output add colour (?:(\d+) )?(?|"([^\"]+)"|'([^\']+)') (?|"([^\"]+)"|'([^\']+)'|(\w+))/ && do {
		my ($idx, $pattern, $profile) = ($1, $2, $3);
		if (defined $idx) {
			if ($idx > $MaxSedPatterns) {
				cmdMessage($db, "Only patterns 1-$MaxSedPatterns allowed\n");
				$idx = undef;
			}
			elsif (exists $term_io->{SedColourPats}->{$idx}) {
				cmdMessage($db, "Output colour pattern $idx already defined; delete existing first\n");
				$idx = undef;
			}
		}
		else { # No index provided
			if ($term_io->{Sourcing}) { # We allocate an id above $MaxSedPatterns
				$idx = 1; # In case SedColourPats empty
				$idx = (sort { $a <=> $b } keys %{$term_io->{SedColourPats}})[-1] + 1 if %{$term_io->{SedColourPats}}; # Next unused index number
				$idx = $MaxSedPatterns + 1 if $idx <= $MaxSedPatterns; # Starting from $MaxSedPatterns + 1
			}
			else {
				cmdMessage($db, "Output colour pattern index value must be supplied if not in sourcing mode\n");
			}
		}
		unless (defined $term_io->{ColourProfiles}->{$profile}) {
			cmdMessage($db, "Sed colour profile '$profile' does not exist\n");
			$profile = undef;
		}
		if ($idx and $profile) {
			my ($qrPattern, $message) = validateQrPattern($pattern);
			my $cat = $host_io->{Type} ? $host_io->{Type} : undef;
			if ($message) {
				cmdMessage($db, "Invalid regular expression: $message");
			}
			else {
				my ($hlOn, $hlOff) = returnHLstrings($term_io->{ColourProfiles}->{$profile});
				my $replace = $hlOn . '$&' . $hlOff;
				$term_io->{SedColourPats}->{$idx} = [$cat, $pattern, $qrPattern, $replace, qq{"$replace"}, $profile];
				cmdOutput($db, "Output colour pattern $idx added : '$pattern' => colour $profile\n");
			}
		}
		$command = '';
	};
	$command eq 'sed output delete ?' && do {
		cmdMessage($db, "Syntax: ${at}sed output delete <index:1-$MaxSedPatterns>\n");
		cmdMessage($db, "Syntax: ${at}sed output delete colour <index:1-$MaxSedPatterns>\n");
		$command = '';
	};
	$command =~ /^sed output delete (\d+)/ && do {
		my $idx = $1;
		if (!exists $term_io->{SedOutputPats}->{$idx}) {
			cmdMessage($db, "Output pattern $idx does not exist\n");
		}
		else {
			delete $term_io->{SedOutputPats}->{$idx};
			cmdMessage($db, "Output pattern $idx deleted\n");
		}
		$command = '';
	};
	$command =~ /^sed output delete colour (\d+)/ && do {
		my $idx = $1;
		if (!exists $term_io->{SedColourPats}->{$idx}) {
			cmdMessage($db, "Output colour pattern $idx does not exist\n");
		}
		else {
			delete $term_io->{SedColourPats}->{$idx};
			cmdMessage($db, "Output colour pattern $idx deleted\n");
		}
		$command = '';
	};
	$command eq 'sed reload' && do {
		$term_io->{SedInputPats} = {};
		$term_io->{SedOutputPats} = {};
		$term_io->{SedColourPats} = {};
		loadSedFile($db);
		$command = '';
	};
	$command eq 'sed reset' && do {
		if (%{$term_io->{SedInputPats}} || %{$term_io->{SedOutputPats}}) {
			if (%{$term_io->{SedInputPats}}) {
				$term_io->{SedInputPats} = {};
				cmdMessage($db, "Cleared all sed input patterns\n");
			}
			if (%{$term_io->{SedOutputPats}}) {
				$term_io->{SedOutputPats} = {};
				cmdMessage($db, "Cleared all sed output patterns\n");
			}
			if (%{$term_io->{SedColourPats}}) {
				$term_io->{SedColourPats} = {};
				cmdMessage($db, "Cleared all sed colour output patterns\n");
			}
		}
		else {
			cmdMessage($db, "No Sed patterns are set\n");
		}
		$command = '';
	};
	#
	# &Send command
	#
	$command eq 'send brk' && do {
		if ($host_io->{Connected}) {
			$host_io->{CLI}->break;
		}
		else {
			cmdMessage($db, "No active connection to send to\n");
			stopSourcing($db);
		}
		$command = '';
	};
	$command eq 'send char ?' && do {
		cmdMessage($db, "Syntax: ${at}send char <ASCII character number>\n");
		$command = '';
	};
	$command =~ /^send char (\d+)/ && do {
		my $char = chr($1);
		if ($host_io->{Connected}) {
			$host_io->{CLI}->put($char);
			return if $host_io->{ConnectionError};
		}
		else {
			cmdMessage($db, "No active connection to send to\n");
			stopSourcing($db);
		}
		$command = '';
	};
	$command eq 'send ctrl ?' && do {
		cmdMessage($db, "Syntax: ${at}send ctrl ^<char>\n");
		$command = '';
	};
	$command =~ /^send ctrl (\^?(.))/ && do {
		my $ctrl = ord($2) - 64;
		if ($ctrl < 0 || $ctrl > 31) {
			cmdMessage($db, "Invalid CTRL character sequence\n");
			stopSourcing($db);
		}
		elsif ($host_io->{Connected}) {
			$host_io->{CLI}->put(chr($ctrl));
			return if $host_io->{ConnectionError};
		}
		else {
			cmdMessage($db, "No active connection to send to\n");
			stopSourcing($db);
		}
		$command = '';
	};
	$command =~ /^send line .*\?$/ && do {
		cmdMessage($db, "Syntax: ${at}send line <line to send (carriage return will be added)>\n");
		$command = '';
	};
	$command =~ /^send line (.+)/ && do {
		my $string = quotesRemove($1);
		$string .= $term_io->{Newline}; # Add a carriage return
		if ($host_io->{Connected}) {
			$host_io->{CLI}->put($string);
			return if $host_io->{ConnectionError};
		}
		else {
			cmdMessage($db, "No active connection to send to\n");
			stopSourcing($db);
		}
		$command = '';
	};
	$command =~ /^send string .*\?$/ && do {
		cmdMessage($db, "Syntax: ${at}send string <string of text>\n");
		$command = '';
	};
	$command =~ /^send string (.+)/ && do {
		my $string = quotesRemove($1);
		$string =~ s/\\n/$term_io->{Newline}/g; # Process newline if "\n" if in string
		if ($host_io->{Connected}) {
			$host_io->{CLI}->put($string);
			return if $host_io->{ConnectionError};
		}
		else {
			cmdMessage($db, "No active connection to send to\n");
			stopSourcing($db);
		}
		$command = '';
	};
	#
	# &Socket command
	#
	$command eq 'socket allow add ?' && do {
		cmdMessage($db, "Syntax: ${at}socket allow add <IP address>\n");
		$command = '';
	};
	$command =~ /^socket allow add (.+)/ && do {
		push(@{$socket_io->{AllowedSrcIPs}}, $1);
		cmdMessage($db, "Socket allowed source IPs: ". join(', ', @{$socket_io->{AllowedSrcIPs}}). "\n");
		$command = '';
	};
	$command eq 'socket allow remove ?' && do {
		cmdMessage($db, "Syntax: ${at}socket allow remove <IP address>\n");
		$command = '';
	};
	$command =~ /^socket allow remove (.+)/ && do {
		my $removeIP = $1;
		if (scalar grep {$_ eq $removeIP} @{$socket_io->{AllowedSrcIPs}}) {
			@{$socket_io->{AllowedSrcIPs}} = grep {$_ ne $removeIP} @{$socket_io->{AllowedSrcIPs}};
			cmdMessage($db, "Socket allowed source IPs: ". join(', ', @{$socket_io->{AllowedSrcIPs}}). "\n");
		}
		else {
			cmdMessage($db, "IP $removeIP is not part of allow list\n");
		}
		$command = '';
	};
	$command eq 'socket allow reset' && do {
		$socket_io->{AllowedSrcIPs} = $Default{socket_allowed_source_ip_lst}; # Reset to just loopback
		cmdMessage($db, "Socket allowed source IPs: ". join(', ', @{$socket_io->{AllowedSrcIPs}}). "\n");
		$command = '';
	};
	$command eq 'socket bind all' && do {
		$socket_io->{SendBuffer} = '' unless $script_io->{AcliControl}; # Never send this command on other terminals!
		$socket_io->{BindLocalAddr} = '';
		cmdMessage($db, "Sockets will bind to all IP interfaces\n");
		if ($term_io->{SocketEnable}) {
			untieSocket($socket_io);
			closeSockets($socket_io, 0);
			openSockets($socket_io);
			setPromptSuffix($db);
			delete($vars->{'%'});
		}
		$command = '';
	};
	$command eq 'socket bind ip ?' && do {
		cmdMessage($db, "Syntax: ${at}socket bind ip <IP address>\n");
		$command = '';
	};
	$command =~ /^socket bind ip (.+)/ && do {
		$socket_io->{SendBuffer} = '' unless $script_io->{AcliControl}; # Never send this command on other terminals!
		$socket_io->{BindLocalAddr} = $1;
		cmdMessage($db, "Sockets will bind to IP interface: ". $socket_io->{BindLocalAddr}. "\n");
		if ($term_io->{SocketEnable}) {
			untieSocket($socket_io);
			closeSockets($socket_io, 0);
			openSockets($socket_io);
			setPromptSuffix($db);
			delete($vars->{'%'});
		}
		$command = '';
	};
	$command eq 'socket bind reset' && do {
		$socket_io->{SendBuffer} = '' unless $script_io->{AcliControl}; # Never send this command on other terminals!
		$socket_io->{BindLocalAddr} = $Default{socket_bind_ip_str};
		cmdMessage($db, "Sockets will bind to IP interface: ". $socket_io->{BindLocalAddr}. "\n");
		if ($term_io->{SocketEnable}) {
			untieSocket($socket_io);
			closeSockets($socket_io, 0);
			openSockets($socket_io);
			setPromptSuffix($db);
			delete($vars->{'%'});
		}
		$command = '';
	};
	$command eq 'socket disable' && do {
		$term_io->{SocketEnable} = 0;
		untieSocket($socket_io);
		closeSockets($socket_io, 0);
		setPromptSuffix($db);
		delete($vars->{'%'});
		$command = '';
	};
	$command eq 'socket echo all' && do {
		$socket_io->{SendBuffer} = '' unless $script_io->{AcliControl}; # Never send this command on other terminals!
		$socket_io->{TieEchoMode} = 2;
		# Set up the Echo mode RX socket if necessary
		tieSocketEcho($socket_io) or cmdMessage($db, "Unable to setup socket for echo mode\n");
		$command = '';
	};
	$command eq 'socket echo error' && do {
		$socket_io->{SendBuffer} = '' unless $script_io->{AcliControl}; # Never send this command on other terminals!
		$socket_io->{TieEchoMode} = 1;
		# Set up the Echo mode RX socket if necessary
		tieSocketEcho($socket_io) or cmdMessage($db, "Unable to setup socket for echo mode\n");
		$command = '';
	};
	$command eq 'socket echo none' && do {
		$socket_io->{SendBuffer} = '' unless $script_io->{AcliControl}; # Never send this command on other terminals!
		$socket_io->{TieEchoMode} = 0;
		tieSocketEcho($socket_io); # Tear down the Echo mode RX socket if necessary
		$command = '';
	};
	$command eq 'socket enable' && do {
		$term_io->{SocketEnable} = 1;
		openSockets($socket_io);
		$command = '';
	};
	$command eq 'socket info' && do {
		cmdOutput($db, "Socket settings:\n");
		cmdOutput($db, "	Socket functionality	: " . ($term_io->{SocketEnable} ? "enable\n" : "disable\n"));
		cmdOutput($db, "	IP Multicast address    : " . $socket_io->{SendIP} . "\n");
		cmdOutput($db, "	IP TTL			: " . $socket_io->{IPTTL} . "\n");
		cmdOutput($db, "	Bind to IP interface	: " . (length $socket_io->{BindLocalAddr} ? $socket_io->{BindLocalAddr} : 'all') . "\n");
		cmdOutput($db, "	Allowed source IPs	: " . join(', ', @{$socket_io->{AllowedSrcIPs}}) . "\n");
		cmdOutput($db, "	Socket username		: " . $AcliUsername . "\n");
		cmdOutput($db, "	Encode username		: " . ($socket_io->{SendUsername} ? "enable\n" : "disable\n"));
		cmdOutput($db, "	Tied to socket		: " . socketList($socket_io, $socket_io->{Tie}) . "\n");
		cmdOutput($db, "	Local Echo Mode		: " . ($socket_io->{TieEchoMode} ? ($socket_io->{TieEchoMode} == 2 ? 'all':'error'):'none') . "\n");
		cmdOutput($db, "	Listening to sockets	: " . socketList($socket_io, keys %{$socket_io->{ListenSockets}}) . "\n");
		cmdOutput($db, "	Socket Name File	: " . $socket_io->{SocketFile} . "\n");
		$command = '';
	};
	$command eq 'socket ip ?' && do {
		cmdMessage($db, "Syntax: ${at}socket ip [<Multicast IP address>]\n");
		$command = '';
	};
	$command =~ /^socket ip (.*)/ && do {
		my $ip = $1;
		if (multicastIp($ip)) {
			$socket_io->{SendIP} = $ip;
			if ($term_io->{SocketEnable}) {
				untieSocket($socket_io);
				closeSockets($socket_io, 0);
				openSockets($socket_io);
				setPromptSuffix($db);
				delete($vars->{'%'});
			}
		}
		else {
			cmdMessage($db, "Invalid IP; only IP Multicast addresses allowed (224.0.0.1 - 239.255.255.255)\n");
		}
		$command = '';
	};
	$command eq 'socket listen' && do {
		$socket_io->{SendBuffer} = '' unless $script_io->{AcliControl}; # Never send this command on other terminals!
		if (!$term_io->{SocketEnable}) {
			cmdMessage($db, "Socket functionality is disabled\n");
		}
		else {
			my ($success, @failedSockets) = openSockets($socket_io, 'all');
			if (!$success) {
				cmdMessage($db, "Unable to allocate socket numbers\n");
				stopSourcing($db);
			}
			elsif (@failedSockets) {
				cmdMessage($db, "Failed to create sockets: " . join(', ', @failedSockets) . "\n");
				stopSourcing($db);
			}
			else {
				cmdMessage($db, "Listening on sockets: " . join(',', sort {$a cmp $b} keys %{$socket_io->{ListenSockets}}) . "\n");
			}
		}
		$command = '';
	};
	$command eq 'socket listen add ?' && do {
		cmdMessage($db, "Syntax: ${at}socket listen add <comma separated list of sockets>\n");
		$command = '';
	};
	$command =~ /^socket listen add (.+)/ && do {
		my @sockets = split(/\s*,\s*/, $1);
		$socket_io->{SendBuffer} = '' unless $script_io->{AcliControl}; # Never send this command on other terminals!
		if (!$term_io->{SocketEnable}) {
			cmdMessage($db, "Socket functionality is disabled\n");
		}
		else {
			my ($success, @failedSockets) = openSockets($socket_io, @sockets);
			if (!$success) {
				cmdMessage($db, "Unable to allocate socket numbers\n");
				stopSourcing($db);
			}
			elsif (@failedSockets) {
				cmdMessage($db, "Failed to create sockets: " . join(', ', @failedSockets) . "\n");
				stopSourcing($db);
			}
			else {
				cmdMessage($db, "Listening on sockets: " . join(',', sort {$a cmp $b} keys %{$socket_io->{ListenSockets}}) . "\n");
			}
		}
		$command = '';
	};
	$command eq 'socket listen clear' && do {
		$socket_io->{SendBuffer} = '' unless $script_io->{AcliControl}; # Never send this command on other terminals!
		if (!$term_io->{SocketEnable}) {
			cmdMessage($db, "Socket functionality is disabled\n");
		}
		else {
			closeSockets($socket_io, 1);
			cmdMessage($db, "No longer listening to any sockets\n");
		}
		$command = '';
	};
	$command eq 'socket listen remove ?' && do {
		cmdMessage($db, "Syntax: ${at}socket listen remove <comma separated list of sockets>\n");
		$command = '';
	};
	$command =~ /^socket listen remove (.+)/ && do {
		my @sockets = split(/\s*,\s*/, $1);
		$socket_io->{SendBuffer} = '' unless $script_io->{AcliControl}; # Never send this command on other terminals!
		if (!$term_io->{SocketEnable}) {
			cmdMessage($db, "Socket functionality is disabled\n");
		}
		else {
			closeSockets($socket_io, 1, @sockets);
			if (scalar keys %{$socket_io->{ListenSockets}}) {
				cmdMessage($db, "Listening on sockets: " . join(',', sort {$a cmp $b} keys %{$socket_io->{ListenSockets}}) . "\n");
			}
			else {
				cmdMessage($db, "No longer listening to any sockets\n");
			}
		}
		$command = '';
	};
	$command eq 'socket names' && do {
		loadSocketNames($socket_io);
		cmdOutput($db, "Known sockets:\n");
		foreach my $sock (sort {$a cmp $b} keys %{$socket_io->{Port}}) {
			cmdOutput($db, sprintf "	%-15s	%s\n", $sock, $socket_io->{Port}->{$sock});
		}
		$command = '';
	};
	$command eq 'socket names numbers' && do {
		loadSocketNames($socket_io);
		cmdOutput($db, "Known sockets:\n");
		my %sockNum;
		foreach my $sock (keys %{$socket_io->{Port}}) {
			$sockNum{$socket_io->{Port}->{$sock}} = $sock;
		}
		foreach my $sock (sort {$a <=> $b} keys %sockNum) {
			cmdOutput($db, sprintf "	%s		%s\n", $sock, $sockNum{$sock});
		}
		$command = '';
	};
	$command eq 'socket tie ?' && do {
		cmdMessage($db, "Syntax: ${at}socket tie <socket name>\n");
		$command = '';
	};
	$command =~ /^socket tie(?: (.*))?/ && do {
		my $sockName = $1 || 'all';
		$socket_io->{SendBuffer} = '' unless $script_io->{AcliControl}; # Never send this command on other terminals!
		if (!$term_io->{SocketEnable}) {
			cmdMessage($db, "Socket functionality is disabled\n");
		}
		else {
			if (my $oldSock = $socket_io->{Tie}) {
				untieSocket($socket_io);
				cmdMessage($db, "Released socket '$oldSock'\n");
			}
			# Do tieSocketEcho() before tieSocket() as we need $socket_io->{TieRxLocalPort} to be set in socketBufferPack()
			unless ( tieSocketEcho($socket_io) ) { # Set up the Echo mode RX socket if necessary
				cmdMessage($db, "Unable to create echo mode socket\n");
				stopSourcing($db);
			}
			if ( tieSocket($socket_io, $sockName, $term_io->{Sourcing} ? 1 : undef) ) {
				setPromptSuffix($db);
				cmdMessage($db, "Tied to socket '$sockName'\n");
				setvar($db, '%' => ($host_io->{Prompt} =~ /\D(\d)(?::\d)?#$/ ? $1 : 1), nosave => 1);
			}
			else {
				cmdMessage($db, "Unable to create socket\n");
				stopSourcing($db);
			}
		}
		$command = '';
	};
	$command eq 'socket ttl ?' && do {
		cmdMessage($db, "Syntax: ${at}socket ttl <0-255>\n");
		$command = '';
	};
	$command =~ /^socket ttl (\d+)/ && do {
		$socket_io->{IPTTL} = $1;
		if ($term_io->{SocketEnable}) {
			untieSocket($socket_io);
			closeSockets($socket_io, 0);
			openSockets($socket_io);
			setPromptSuffix($db);
			delete($vars->{'%'});
		}
		$command = '';
	};
	$command eq 'socket untie' && do {
		$socket_io->{SendBuffer} = '' unless $script_io->{AcliControl}; # Never send this command on other terminals!
		if (!$term_io->{SocketEnable}) {
			cmdMessage($db, "Socket functionality is disabled\n");
		}
		else {
			untieSocket($socket_io);
			setPromptSuffix($db);
			delete($vars->{'%'});
		}
		$command = '';
	};
	$command eq 'socket username disable' && do {
		$socket_io->{SendUsername} = 0;
		$command = '';
	};
	$command eq 'socket username enable' && do {
		$socket_io->{SendUsername} = 1;
		$command = '';
	};
	#
	# &Ssh command
	#
	$command eq 'ssh info' && do {
		if ($host_io->{Connected}) {
			if ($host_io->{ComPort} eq 'SSH') {
				cmdMessage($db, "SSH Version 2\n");
				cmdMessage($db, "SSH Connected to " . $host_io->{Name});
				cmdMessage($db, $host_io->{TcpPort} ? " on tcp port $host_io->{TcpPort}\n" : "\n");
				cmdMessage($db, "SSH authentication used : " . $host_io->{CLI}->ssh_authentication . "\n");
				cmdMessage($db, "Server key fingerprint : " . $host_io->{SshKeySrvFingPr} . "\n");
				cmdMessage($db, "SSH known_hosts lookup result : " . $host_io->{SshKnownHost} . "\n");
				if ($peercp_io->{Connected}) {
					if ($peercp_io->{Connect_OOB}) {
						cmdMessage($db, "\nSSH Connected to Peer CPU on OOB IP " . $peercp_io->{Connect_IP} . "\n");
					}
					else {
						cmdMessage($db, "\nShadow SSH connection to same host to access Peer CPU\n");
					}
					cmdMessage($db, "SSH authentication used : " . $peercp_io->{CLI}->ssh_authentication . "\n");
				}
			}
			else {
				cmdMessage($db, "Current connection is not using SSH\n");
			}
		}
		else {
			cmdMessage($db, "No SSH connection established\n");
		}
		$command = '';
	};
	$command eq 'ssh keys info' && do {
		my ($keyType, $encrypted, $dek, $keylength, $keycomment, $fingerPrint);
		if ($host_io->{SshPrivateKey} && $host_io->{SshPublicKey}) {
			($keyType, $encrypted, $dek, $keylength, $keycomment, $fingerPrint) = inspectLocalSshKeys($host_io->{SshPrivateKey}, $host_io->{SshPublicKey});
		}
		else {
			$keyType = $dek = $keylength = '';
		}
		cmdMessage($db, "SSH keys loaded:\n");
		cmdMessage($db, "	SSH Private key		: " . ($host_io->{SshPrivateKey} ? $host_io->{SshPrivateKey} : '<no key loaded>') . "\n");
		cmdMessage($db, "	SSH Public key		: " . ($host_io->{SshPublicKey} ? $host_io->{SshPublicKey} : '<no key loaded>') . "\n");
		cmdMessage($db, "	SSH key type		: " . $keyType . "\n");
		cmdMessage($db, "	Passphrase encrypted	: " . (defined $encrypted ? ( $encrypted ? "Yes\n" : "No\n") : "\n"));
		cmdMessage($db, "	Data Encryption (DEK)	: " . $dek . "\n");
		cmdMessage($db, "	Key length		: " . ($keylength ? "$keylength bits\n" : "\n"));
		cmdMessage($db, "	Key MD5 fingerprint 	: " . ($fingerPrint ? "$fingerPrint\n" : "\n"));
		cmdMessage($db, "	Key comment		: " . ($keycomment ? "$keycomment\n" : "\n"));
		$command = '';
	};
	$command =~ /^ssh keys load .*\?$/ && do {
		cmdMessage($db, "Syntax: ${at}ssh keys load <private key>\n\n");
		cmdMessage($db, " - Private key must be in OpenSSH format\n");
		cmdMessage($db, " - Public key, also in OpenSSH format, is expected with same filename as private key with .pub prefix\n");
		$command = '';
	};
	$command =~ /^ssh keys load (.+)/ && do {
		unless (verifySshKeys($host_io, $1)) {
			cmdMessage($db, "Unable to locate SSH keys\n");
		}
		$command = '';
	};
	$command eq 'ssh keys unload' && do {
		$host_io->{SshPrivateKey} = $host_io->{SshPublicKey} = undef;
		$command = '';
	};
	$command eq 'ssh known-hosts' && do {
		unless ($term_io->{KnownHostsFile}) { # Try and locate it
			foreach my $path (@SshKeyPath) {
				my $known_hosts = File::Spec->canonpath("$path/$KnownHostsFile");
				next unless -e $known_hosts;
				$term_io->{KnownHostsFile} = $known_hosts;
				$term_io->{KnownHostsDummy} = File::Spec->canonpath("$path/$KnownHostsDummy"); # In same path as real known_hosts file
				last;
			}
		}
		if ($term_io->{KnownHostsFile}) {
			cmdOutput($db, "SSH $KnownHostsFile file: $term_io->{KnownHostsFile}\n\n");
			my $knownhosts = readSshKnownHosts($db);
			if (@$knownhosts) {
				cmdOutput($db, sprintf "%-25s %-34s %-7s %4s %-15s %s\n", 'Hostname(s)/IP', 'Fingerprint', 'Type', 'Bits', 'Marker', 'Comments');
				cmdOutput($db, sprintf "%-25s %-34s %-7s %4s %-15s %s\n", '-' x 25, '-'x 34, '-' x 7, '-' x 4, '-'x 15, '-' x 20);
				foreach my $khost (sort by_ip @$knownhosts) {
					my $padlen = length($khost->[0]) > 25 ? 34 - (length($khost->[0]) - 25) : 34;
					cmdOutput($db, sprintf "%-25s %${padlen}s %-7s %4s %-15s %s\n", $khost->[0], ' ' x $padlen, $khost->[2], $khost->[3], $khost->[1], $khost->[5]);
					cmdOutput($db, sprintf "%-25s %-47s\n", ' ' x 25, $khost->[4]);
				}
			}
			else {
				cmdMessage($db, "No SSH entries in $KnownHostsFile file\n");
			}
		}
		else {
			cmdMessage($db, "No SSH $KnownHostsFile file\n");
		}
		$command = '';
	};
	$command eq 'ssh known-hosts delete ?' && do {
		cmdMessage($db, "Syntax: ${at}ssh known-hosts delete <hostname/IP> [<tcp-port>]\n\n");
		cmdMessage($db, " - Hostname or IP must exactly match entry in $KnownHostsFile file\n");
		$command = '';
	};
	$command =~ /^ssh known-hosts delete (\S+)(?:\s+(\d+))?/ && do {
		my $hostname = ($2 && $2 != 22) ? '[' . compactIPv6($1) . ']:' . $2 : compactIPv6($1);
		unless ($term_io->{KnownHostsFile}) { # Try and locate it
			foreach my $path (@SshKeyPath) {
				my $known_hosts = File::Spec->canonpath("$path/$KnownHostsFile");
				next unless -e $known_hosts;
				$term_io->{KnownHostsFile} = $known_hosts;
				$term_io->{KnownHostsDummy} = File::Spec->canonpath("$path/$KnownHostsDummy"); # In same path as real known_hosts file
				last;
			}
		}
		if ($term_io->{KnownHostsFile}) {
			my $retVal = deleteSshKnownHostEntry($db, $hostname);
			if ($retVal) { # 1
				cmdMessage($db, "Entry for $hostname removed from SSH $KnownHostsFile file\n");
			}
			elsif (defined $retVal) { # 0
				cmdMessage($db, "No entry for $hostname found in SSH $KnownHostsFile file\n");
			}
			else { # undef
				cmdMessage($db, "Unable to read/modify SSH $KnownHostsFile file\n");
			}
		}
		else {
			cmdMessage($db, "No SSH $KnownHostsFile file\n");
		}
		$command = '';
	};
	#
	# &Status command
	#
	$command eq 'status' && do {
		if ($host_io->{Connected}) {
			if ($host_io->{TcpPort}) {
				cmdMessage($db, "Connected to $host_io->{Name} via $host_io->{ComPort} on tcp port $host_io->{TcpPort}\n");
			}
			elsif ($host_io->{ComPort} !~ /^(?:TELNET|SSH)$/ && defined $host_io->{Baudrate}) {
				cmdMessage($db, "Connected to $host_io->{Name} via $host_io->{ComPort} at baudrate $host_io->{Baudrate}\n");
			}
			else {
				cmdMessage($db, "Connected to $host_io->{Name} via $host_io->{ComPort}\n");
			}
			if ($peercp_io->{Connected}) {
				if ($peercp_io->{Connect_OOB}) {
					cmdMessage($db, "Directly connected to Peer CPU on OOB IP $peercp_io->{Connect_IP}\n");
				}
				else {
					cmdMessage($db, "Connected to Peer CPU via shadow connection to $host_io->{Name}\n");
				}
			}
		}
		else {
			cmdMessage($db, "Not connected\n");
		}
		$command = '';
	};
	#
	# &Terminal command
	#
	$command eq 'terminal hidetimestamp disable' && do {
		$term_io->{HideTimeStamps} = 0;
		$command = '';
	};
	$command eq 'terminal hidetimestamp enable' && do {
		$term_io->{HideTimeStamps} = 1;
		$command = '';
	};
	$command eq 'terminal highlightcmd disable' && do {
		$term_io->{HlEnteredCmd} = 0;
		$command = '';
	};
	$command eq 'terminal highlightcmd enable' && do {
		$term_io->{HlEnteredCmd} = 1;
		$command = '';
	};
	$command eq 'terminal info' && do {
		cmdOutput($db, "ACLI terminal settings:\n");
		cmdOutput($db, "	AutoDetect Host Type      : ". ($term_io->{AutoDetect} ? "enable\n" : "disable\n"));
		cmdOutput($db, "	Terminal Mode             : ". $term_io->{Mode}. "\n");
		cmdOutput($db, "	Host Capability Mode      : ". (defined $host_io->{CapabilityMode} ? $host_io->{CapabilityMode} : ''). "\n");
		cmdOutput($db, "	Host Type                 : ". $host_io->{Type}. "\n");
		cmdOutput($db, "	Host Model                : ". $host_io->{Model}. "\n");
		cmdOutput($db, "	ACLI(NNCLI)               : ". (defined $term_io->{AcliType} ? ($term_io->{AcliType} ? "yes" : "no") : ''). "\n");
		cmdOutput($db, "	Prompt Match              : '". ($prompt->{Match} ? $prompt->{Match} : ''). "'\n");
		cmdOutput($db, "	More Prompt Match         : '". ($prompt->{More} ? $prompt->{More} : ''). "'\n");
		cmdOutput($db, "	Suffix Prompt ". $Default{prompt_suffix_str}. "          : ". ($term_io->{LtPrompt} ? "enable\n" : "disable\n"));
		cmdOutput($db, "	Toggle CTRL character     : ". $term_io->{CtrlInteractPrn}. "\n");
		cmdOutput($db, "	Config indentation        : ". $term_io->{GrepIndent}. " space characters\n");
		cmdOutput($db, "	Host Error detection      : ". ($host_io->{ErrorDetect} ? "enable\n" : "disable\n"));
		cmdOutput($db, "	Host Error level	  : ". $host_io->{ErrorLevel}. "\n");
		cmdOutput($db, "	Keep Alive Timer          : ". ($host_io->{KeepAliveTimer} == 0 ? '0 (disabled)' : stringTimer($host_io->{KeepAliveTimer})). "\n");
		cmdOutput($db, "	Transparent Keep Alive    : ". ($host_io->{TranspKeepAlive} ? "enable\n" : "disable\n"));
		cmdOutput($db, "	Session Timeout	          : ". stringTimer($host_io->{SessionTimeout}). "\n");
		cmdOutput($db, "	Connection Timeout        : ". $host_io->{ConnectTimeout}. " seconds\n");
		cmdOutput($db, "	Login Timeout             : ". $host_io->{LoginTimeout}. " seconds\n");
		cmdOutput($db, "	Interact Timeout          : ". $host_io->{Timeout}. " seconds\n");
		cmdOutput($db, "	Newline sequence          : ". ($term_io->{Newline} eq "\n" ? "Carriage Return + Line Feed (CR+LF)\n" : "Carriage Return (CR)\n"));
		cmdOutput($db, "	Negotiate Terminal Type   : ". (defined $term_io->{TerminalType} ? $term_io->{TerminalType} : 'not set'. $term_io->{TermTypeNotNego} ? " (next connection)" : ''). "\n");
		cmdOutput($db, "	Negotiate Window Size     : ". (@{$term_io->{WindowSize}} ? join(' x ', @{$term_io->{WindowSize}})." (width/height)" : 'not set'. $term_io->{TermWinSNotNego} ? " (next connection)" : ''). "\n");
		cmdOutput($db, "	Hide Device Time Stamps   : ". ($term_io->{HideTimeStamps} ? "enable\n" : "disable\n"));
		cmdOutput($db, "	Highlight Entered Command : ". ($term_io->{HlEnteredCmd} ? "enable\n" : "disable\n"));
		cmdOutput($db, "	Port ranges span slots    : ". ($term_io->{PortRngSpanSlot} ? "enable\n" : "disable\n"));
		cmdOutput($db, "	Default port range mode   : ". $term_io->{DefaultPortRng}. " (e.g. ". ($term_io->{DefaultPortRng} == 0 ? 'no ranges' : ($term_io->{DefaultPortRng} == 1) ? '1/1-48' : ($term_io->{DefaultPortRng} == 2) ? '1/1-1/48' : 'invalid'). ")\n");
		cmdOutput($db, "	Port ranges unconstrain   : ". ($host_io->{PortUnconstrain} ? "enable\n" : "disable\n"));
		$command = '';
	};
	$command eq 'terminal ini' && do {
		cmdOutput($db, "ACLI terminal INI settings:\n");
		for my $inikey (sort {$a cmp $b} keys %Default) {
			if ( ref($Default{$inikey}) eq 'HASH') {
				for my $subkey (sort {$a cmp $b} keys %{$Default{$inikey}}) {
					cmdOutput($db, sprintf "  %-45s = %s\n", "$inikey:$subkey", iniValue($inikey, $Default{$inikey}{$subkey}));
				}
			}
			else {
				cmdOutput($db, sprintf "  %-45s = %s\n", $inikey, iniValue($inikey, $Default{$inikey}));
			}
		}
		$command = '';
	};
	$command eq 'terminal portrange spanslots disable' && do {
		$term_io->{PortRngSpanSlot} = 0;
		$command = '';
	};
	$command eq 'terminal portrange spanslots enable' && do {
		$term_io->{PortRngSpanSlot} = 1;
		$command = '';
	};
	$command eq 'terminal portrange default ?' && do {
		cmdMessage($db, "Syntax: terminal portrange default [0 = no ranges; 1 = range format 1/1-24; 2 = range foramt 1/1-1/24]\n");
		$command = '';
	};
	$command =~ /^terminal portrange default (\d+)/ && do {
		$term_io->{DefaultPortRng} = $1;
		$command = '';
	};
	$command eq 'terminal portrange unconstrain disable' && do {
		$host_io->{PortUnconstrain} = 0;
		$command = '';
	};
	$command eq 'terminal portrange unconstrain enable' && do {
		$host_io->{PortUnconstrain} = 1;
		$command = '';
	};
	#
	# &Vars command
	#
	$command eq 'vars attribute ?' && do {
		cmdMessage($db, "Syntax: ${at}vars attribute [<pattern>]\n");
		$command = '';
	};
	$command =~ /^vars attribute(?: (.*))?/ && do {
		if ($host_io->{Connected} || $term_io->{PseudoTerm}) { # This is skipped in PseudoTerm
			my $varpat = $1;
			my ($indx, $vpregex);
			if (defined $varpat) {
				$indx = $1 if $varpat =~ s/\[(\d+)\]$//;	# Remove index if supplied
				($vpregex = $varpat) =~ s/^\$?_?//;
			}
			my $attribs = $term_io->{PseudoTerm}	? [keys %{$term_io->{PseudoAttribs}}]
								: $host_io->{CLI}->attribute(Attribute => 'all', Blocking => 1);
			my $matchFlag;
			foreach my $attrib (@$attribs) {
				next if defined $varpat && $attrib !~ /$vpregex/;
				$matchFlag = 1;
				cmdOutput($db, sprintf "\$_%-20s = %s\n", $attrib, replaceAttribute($db, $attrib, $indx));
			}
			if ($varpat && !$matchFlag) {
				cmdMessage($db, "No attribute variables found matching $varpat\n");
			}
		}
		else {
			cmdMessage($db, "No attribute variables are set if not connected\n");
		}
		$command = '';
	};
	$command eq 'vars clear' && do {
		%$vars = ();
		cmdOutput($db, "Variables cleared\n");
		$command = '';
	};
	$command eq 'vars clear dictionary' && do {
		foreach my $var (keys %$vars) {
			next unless $vars->{$var}->{dictscope};
			delete $vars->{$var};
		}
		cmdOutput($db, "Dictionary variables cleared\n");
		$command = '';
	};
	$command eq 'vars clear script' && do {
		foreach my $var (keys %$vars) {
			next unless $vars->{$var}->{script} || $vars->{$var}->{myscope};
			delete $vars->{$var};
		}
		cmdOutput($db, "Variables set in script or as \@my scope cleared\n");
		$command = '';
	};
	$command eq 'vars echo disable' && do {
		$term_io->{VarsEcho} = 0;
		$command = '';
	};
	$command eq 'vars echo enable' && do {
		$term_io->{VarsEcho} = 1;
		$command = '';
	};
	$command eq 'vars info' && do {
		cmdOutput($db, "Vars echoing	: " . ($term_io->{VarsEcho} ? "enable\n" : "disable\n"));
		cmdOutput($db, "Variables File	: " . $host_io->{VarsFile} . "\n");
		$command = '';
	};
	$command eq 'vars raw ?' && do {
		cmdMessage($db, "Syntax: ${at}vars raw [all|dictionary|script] [<pattern>]\n");
		$command = '';
	};
	$command eq 'vars show ?' && do {
		cmdMessage($db, "Syntax: ${at}vars show [all|dictionary|script] [<pattern>]\n");
		$command = '';
	};
	$command =~ /^vars (show|raw)(?: (all|dictionary|script))?(?: (.*))?/ && do {
		if (scalar keys %$vars) {
			my ($raw, $type, $varpat) = ($1 eq 'raw' ? $1 : '', defined $2 ? $2 : '', $3);
			(my $vpregex = $varpat) =~ s/^\$// if defined $varpat;
			my $matchFlag;
			foreach my $var (sort {$a cmp $b} keys %$vars) {
				if ($type eq 'dictionary') { # Only show dictionary vars
					next unless $vars->{$var}->{dictscope};
				}
				elsif ($type eq 'script') { # Only show script variables declared with @my
					next unless $vars->{$var}->{myscope};
				}
				elsif ($type eq 'all') {} # Show all variables
				else { # Show only user variables
					next if $vars->{$var}->{myscope} || $vars->{$var}->{dictscope}; # Skip vars declared with @my or dictionary scope
				}
				next if defined $varpat && $var !~ /$vpregex/;
				$matchFlag = 1;
				cmdOutput($db, printVar($db, $var, $raw));
			}
			cmdOutput($db, "\nUnsaved variables exist\n") if !$varpat && %{$host_io->{UnsavedVars}};
			if ($varpat && !$matchFlag) {
				cmdMessage($db, "No variables found matching $varpat\n");
			}
		}
		else {
			cmdMessage($db, "No variables are set\n");
		}
		$command = '';
	};

	return length $command ? $at.$command : '';
}


sub processControlCommand { # Process a command under ACLI Control
	my ($db, $controlCmd) = @_;
	my $cacheMode = $db->[1];
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $peercp_io = $db->[5];
	my $socket_io = $db->[6];
	my $prompt = $db->[7];
	my $annexData = $db->[13];
	my $serialData = $db->[14];

	print "\n";
	$controlCmd =~ s/^\s+//; # Remove spaces from the front
	if ($controlCmd eq '') { # Nothing entered, revert to host
		return 1 if $host_io->{Connected} || $term_io->{PseudoTerm};
		print $ACLI_Prompt;
		return;
	}
	my ($command, $list) = tabExpand($ControlCmds, $controlCmd, 1);
	debugMsg(1,"ProcessControlCommand - tabExpand returned: >", \$command, "<\n");
	if (defined $list) {
		print $list, "\n";
	}
	elsif (!length $command) {
		print "Invalid Command. type ?/help for help\n";
	}

	#
	# Help command
	#
	($command eq 'help' || $command eq '?') && do {
		print "Commands may be abbreviated. Commands are:\n\n";
		print "alias           manage alias functionality\n";
		print "cd              change working directory\n";
		print "clear / cls     clear the screen\n";
		print "close           close current connection\n";
		print "ctrl            set special CTRL characters\n";
		print "debug           enable terminal debugging\n";
		print "dictionary      manage loaded dictionary\n";
		print "dir             list working directory\n";
		print "echo            control echo to terminal\n";
		print "flush           flush cached credentials\n";
		print "highlight       text formatting for highlights\n";
		print "history         manage history functionality\n";
		print "log             capture output to file\n";
		print "ls              list working directory\n";
		print "mkdir           create new directory\n";
		print "more            configure local more paging\n";
		print "open            connect to a host device\n";
		print "peercp          manage connection to peer CPU\n";
		print "ping            embedded ping\n";
		print "pseudo          enable/disable pseudo terminal\n";
		print "pwd             print working directory\n";
		print "quit            exit $ScriptName\n";
		print "reconnect       reconnect previous connection\n";
		print "rmdir           delete directory\n";
		print "save            save device variables and data\n";
		print "send            transmit special characters\n";
		print "serial          set serial port parameters\n";
		print "socket          link this terminal instance to others\n";
		print "ssh             ssh, info and install keys on host\n";
		print "status          print status information\n";
		print "telnet          alias of open, to connect with telnet\n";
		print "terminal        set terminal control modes\n";
		print "trmsrv          manage terminal server list\n";
		print "vars            manage variable functionality\n";
		print "version         script & module versions\n";
		print "?/help          print help information\n";
		print "<return>        return to connected device\n";
		print "\nFor more details on a command, enter command ?\n";
		$command = '';
	};
	#
	# Alias command
	#
	$command =~ /^alias load .*\?$/ && do {
		print "Syntax: alias load <alias-file>\n";
		$command = '';
	};
	$command =~ /^alias load (.+)/ && do {
		my $aliasFile = $1;
		if ( loadAliasFile($db, $aliasFile) ) {
			$term_io->{AliasFile} = File::Spec->canonpath($aliasFile);
			$term_io->{AliasMergeFile} = '';
			print "Successfully loaded alias file\n";
		}
		else {
			$term_io->{AliasFile} = '';
			print "Error loading alias file\n";
		}
		$command = '';
	};
	$command =~ /^alias merge .*\?$/ && do {
		print "Syntax: alias merge <alias-file>\n";
		$command = '';
	};
	$command =~ /^alias merge (.+)/ && do {
		my $aliasFile = $1;
		if (length $term_io->{AliasFile}) {
			if ( loadAliasFile($db, $aliasFile, 1) ) {
				$term_io->{AliasMergeFile} = File::Spec->canonpath($aliasFile);
				print "Successfully merged alias file\n";
			}
			else {
				$term_io->{AliasMergeFile} = '';
				print "Error merging alias file\n";
			}
		}
		else {
			print "No alias file is loaded to merge with. Please load an alias file first\n";
		}
		$command = '';
	};
	#
	# Close command
	#
	$command eq 'close' && do {
		if ($host_io->{Connected}) {
			disconnect($db);
			print "Connection to ", $host_io->{Name}, " closed\n";
		}
		else {
			print "No active connection to close\n";
		}
		$command = '';
	};
	#
	# Ctrl command
	#
	$command eq 'ctrl clear-screen ?' && do {
		print "Syntax: ctrl clear-screen ^<char>|none\n";
		$command = '';
	};
	$command =~ /^ctrl clear-screen (\^?(.))$/ && do {
		my ($charPrn, $char) = (uc $1, $2);
		$charPrn = '^'.$charPrn unless $charPrn =~ /^\^/;
		if ($term_io->{CtrlAllocated}->{$charPrn}) {
			print "$charPrn is already allocated\n";
		}
		else {
			delete($term_io->{CtrlAllocated}->{$term_io->{CtrlClsPrn}});
			$term_io->{CtrlAllocated}->{$charPrn} = 1;
			$term_io->{CtrlClsPrn} = $charPrn;
			$term_io->{CtrlClsChr} = chr(ord($char) & 31);
		}
		$command = '';
	};
	$command eq 'ctrl clear-screen none' && do {
		delete($term_io->{CtrlAllocated}->{$term_io->{CtrlClsPrn}});
		$term_io->{CtrlClsPrn} = 'none';
		$term_io->{CtrlClsChr} = '';
		$command = '';
	};
	$command eq 'ctrl debug ?' && do {
		print "Syntax: ctrl debug ^<char>|none\n";
		$command = '';
	};
	$command =~ /^ctrl debug (\^?(.))$/ && do {
		my ($charPrn, $char) = (uc $1, $2);
		$charPrn = '^'.$charPrn unless $charPrn =~ /^\^/;
		if ($term_io->{CtrlAllocated}->{$charPrn}) {
			print "$charPrn is already allocated\n";
		}
		else {
			delete($term_io->{CtrlAllocated}->{$term_io->{CtrlDebugPrn}});
			$term_io->{CtrlAllocated}->{$charPrn} = 1;
			$term_io->{CtrlDebugPrn} = $charPrn;
			$term_io->{CtrlDebugChr} = chr(ord($char) & 31);
		}
		$command = '';
	};
	$command eq 'ctrl debug none' && do {
		delete($term_io->{CtrlAllocated}->{$term_io->{CtrlDebugPrn}});
		$term_io->{CtrlDebugPrn} = 'none';
		$term_io->{CtrlDebugChr} = '';
		$command = '';
	};
	$command eq 'ctrl escape ?' && do {
		print "Syntax: ctrl escape ^<char>|none\n";
		$command = '';
	};
	$command =~ /^ctrl escape (\^?(.))$/ && do {
		my ($charPrn, $char) = (uc $1, $2);
		$charPrn = '^'.$charPrn unless $charPrn =~ /^\^/;
		if ($term_io->{CtrlAllocated}->{$charPrn}) {
			print "$charPrn is already allocated\n";
		}
		else {
			delete($term_io->{CtrlAllocated}->{$term_io->{CtrlEscapePrn}});
			$term_io->{CtrlAllocated}->{$charPrn} = 1;
			$term_io->{CtrlEscapePrn} = $charPrn;
			$term_io->{CtrlEscapeChr} = chr(ord($char) & 31);
		}
		$command = '';
	};
	$command eq 'ctrl escape none' && do {
		delete($term_io->{CtrlAllocated}->{$term_io->{CtrlEscapePrn}});
		$term_io->{CtrlEscapePrn} = 'none';
		$term_io->{CtrlEscapeChr} = '';
		$command = '';
	};
	$command eq 'ctrl info' && do {
		print "CTRL characters:\n";
		printf "	Escape character     : %s\n", $term_io->{CtrlEscapePrn};
		printf "	Quit character       : %s\n", $term_io->{CtrlQuitPrn};
		printf "	Terminal mode toggle : %s\n", $term_io->{CtrlInteractPrn};
		printf "	More paging toggle   : %s\n", $term_io->{CtrlMorePrn};
		printf "	Send Break           : %s\n", $term_io->{CtrlBrkPrn};
		printf "	Clear Screen         : %s\n", $term_io->{CtrlClsPrn};
		printf "	Debug                : %s\n", $term_io->{CtrlDebugPrn};
		$command = '';
	};
	$command eq 'ctrl more-paging-toggle ?' && do {
		print "Syntax: ctrl more-paging-toggle ^<char>|none\n";
		$command = '';
	};
	$command =~ /^ctrl more-paging-toggle (\^?(.))$/ && do {
		my ($charPrn, $char) = (uc $1, $2);
		$charPrn = '^'.$charPrn unless $charPrn =~ /^\^/;
		if ($term_io->{CtrlAllocated}->{$charPrn}) {
			print "$charPrn is already allocated\n";
		}
		else {
			delete($term_io->{CtrlAllocated}->{$term_io->{CtrlMorePrn}});
			$term_io->{CtrlAllocated}->{$charPrn} = 1;
			$term_io->{CtrlMorePrn} = $charPrn;
			$term_io->{CtrlMoreChr} = chr(ord($char) & 31);
			($term_io->{LocalMorePrompt} = $LocalMorePrompt) =~ s/\Q$CtrlMorePrn\E/$term_io->{CtrlMorePrn}/;
			($term_io->{DeleteMorePrompt} = $term_io->{LocalMorePrompt}) =~ s/./\cH \cH/g;
		}
		$command = '';
	};
	$command eq 'ctrl more-paging-toggle none' && do {
		delete($term_io->{CtrlAllocated}->{$term_io->{CtrlMorePrn}});
		$term_io->{CtrlMorePrn} = 'none';
		$term_io->{CtrlMoreChr} = '';
		$command = '';
	};
	$command eq 'ctrl quit ?' && do {
		print "Syntax: ctrl quit ^<char>|none\n";
		$command = '';
	};
	$command =~ /^ctrl quit (\^?(.))$/ && do {
		my ($charPrn, $char) = (uc $1, $2);
		$charPrn = '^'.$charPrn unless $charPrn =~ /^\^/;
		if ($term_io->{CtrlAllocated}->{$charPrn}) {
			print "$charPrn is already allocated\n";
		}
		else {
			delete($term_io->{CtrlAllocated}->{$term_io->{CtrlQuitPrn}});
			$term_io->{CtrlAllocated}->{$charPrn} = 1;
			$term_io->{CtrlQuitPrn} = $charPrn;
			$term_io->{CtrlQuitChr} = chr(ord($char) & 31);
		}
		$command = '';
	};
	$command eq 'ctrl quit none' && do {
		delete($term_io->{CtrlAllocated}->{$term_io->{CtrlQuitPrn}});
		$term_io->{CtrlQuitPrn} = 'none';
		$term_io->{CtrlQuitChr} = '';
		$command = '';
	};
	$command eq 'ctrl send-break ?' && do {
		print "Syntax: ctrl send-break ^<char>|none\n";
		$command = '';
	};
	$command =~ /^ctrl send-break (\^?(.))$/ && do {
		my ($charPrn, $char) = (uc $1, $2);
		$charPrn = '^'.$charPrn unless $charPrn =~ /^\^/;
		if ($term_io->{CtrlAllocated}->{$charPrn}) {
			print "$charPrn is already allocated\n";
		}
		else {
			delete($term_io->{CtrlAllocated}->{$term_io->{CtrlBrkPrn}});
			$term_io->{CtrlAllocated}->{$charPrn} = 1;
			$term_io->{CtrlBrkPrn} = $charPrn;
			$term_io->{CtrlBrkChr} = chr(ord($char) & 31);
		}
		$command = '';
	};
	$command eq 'ctrl send-break none' && do {
		delete($term_io->{CtrlAllocated}->{$term_io->{CtrlBrkPrn}});
		$term_io->{CtrlBrkPrn} = 'none';
		$term_io->{CtrlBrkChr} = '';
		$command = '';
	};
	$command eq 'ctrl term-mode-toggle ?' && do {
		print "Syntax: ctrl term-mode-toggle ^<char>|none\n";
		$command = '';
	};
	$command =~ /^ctrl term-mode-toggle (\^?(.))$/ && do {
		my ($charPrn, $char) = (uc $1, $2);
		$charPrn = '^'.$charPrn unless $charPrn =~ /^\^/;
		if ($term_io->{CtrlAllocated}->{$charPrn}) {
			print "$charPrn is already allocated\n";
		}
		else {
			delete($term_io->{CtrlAllocated}->{$term_io->{CtrlInteractPrn}});
			$term_io->{CtrlAllocated}->{$charPrn} = 1;
			$term_io->{CtrlInteractPrn} = $charPrn;
			$term_io->{CtrlInteractChr} = chr(ord($char) & 31);
		}
		$command = '';
	};
	$command eq 'ctrl term-mode-toggle none' && do {
		delete($term_io->{CtrlAllocated}->{$term_io->{CtrlInteractPrn}});
		$term_io->{CtrlInteractPrn} = 'none';
		$term_io->{CtrlInteractChr} = '';
		$command = '';
	};
	#
	# Debug command
	#
	$command eq 'debug info' && do {
		print "Debug level               : ", $::Debug, "\n";
		print "Debug file path           : ", $host_io->{DebugFilePath}, "\n";
		print "Debug input log           : ", $host_io->{InputLog}, "\n";
		print "Debug output log          : ", $host_io->{OutputLog}, "\n";
		print "Debug dump log            : ", $host_io->{DumpLog}, "\n";
		print "Debug telnet options log  : ", $host_io->{TelOptLog}, "\n";
		if ($peercp_io->{Connected}) {
			print "Debug peercp input log    : ", $peercp_io->{InputLog}, "\n";
			print "Peercp output log         : ", $peercp_io->{OutputLog}, "\n";
			print "Peercp dump log           : ", $peercp_io->{DumpLog}, "\n";
			print "Peercp telnet options log : ", $peercp_io->{TelOptLog}, "\n";
		}
		print "Debug script log          : ", defined $DebugLog ? $DebugLog : '', "\n";
		print "CTRL character            : ", $term_io->{CtrlDebugPrn}, "\n";
		print "Debug.pm package          : ", $DebugPackage ? 'Loaded' : 'not loaded', "\n\n";
		debugLevels;
		print "\n";
		$command = '';
	};
	$command eq 'debug off' && do { # Needs to be before debug level cmd
		$command = 'debug level 0';
	};
	$command eq 'debug level ?' && do {
		print "Syntax: debug level <0-9999>\n";
		$command = '';
	};
	$command =~ /^debug level (\d{1,4})/ && do {
		my $newDebugLevel = $1;
		if ($::Debug && !$newDebugLevel) { # disable debug logging if it was enabled but no longer with new level
			if ($host_io->{Connected}) {
				if ($peercp_io->{Connected}) {
					$peercp_io->{InputLog} = '';
					$peercp_io->{OutputLog} = '';
					$peercp_io->{DumpLog} = '';
					$peercp_io->{TelOptLog} = '';
					$peercp_io->{CLI}->input_log($peercp_io->{InputLog});
					$peercp_io->{CLI}->output_log($peercp_io->{OutputLog});
					$peercp_io->{CLI}->dump_log($peercp_io->{DumpLog});
					$peercp_io->{CLI}->parent->option_log('') if $host_io->{ComPort} eq 'TELNET';
					$peercp_io->{CLI}->debug(0);
					$peercp_io->{CLI}->debug_file('');
				}
				close $host_io->{CLI}->input_log if $host_io->{InputLog};
				close $host_io->{CLI}->output_log if $host_io->{OutputLog};
				close $host_io->{CLI}->dump_log if $host_io->{DumpLog};
				close $host_io->{CLI}->parent->option_log if $host_io->{TelOptLog} && $host_io->{ComPort} eq 'TELNET';
				$host_io->{InputLog} = '';
				$host_io->{OutputLog} = '';
				$host_io->{DumpLog} = '';
				$host_io->{TelOptLog} = '';
				$host_io->{CLI}->input_log('');
				$host_io->{CLI}->output_log('');
				$host_io->{CLI}->dump_log('');
				$host_io->{CLI}->parent->option_log('') if $host_io->{ComPort} eq 'TELNET';
				$host_io->{CLI}->debug(0);
				$host_io->{CLI}->debug_file('');
			}
			$DebugLog = '';
			$host_io->{DebugFilePath} = '';
			close $DebugLogFH if $DebugLogFH;
			undef $DebugLogFH;
		}
		elsif (!$::Debug && $newDebugLevel) { # enable debug logging if it was disabled but no longer with new level
			require Data::Dumper; # Only load this module if debug enabled
			$host_io->{DebugFilePath} = File::Spec->rel2abs(cwd);
			my $filePrefix;
			if ($host_io->{Connected}) {
				$filePrefix = $host_io->{Name} =~/^serial:/ ? $host_io->{ComPort} : $host_io->{Name};
				$filePrefix =~ s/:/_/g;	# Produce a suitable filename for serial ports & IPv6 addresses
				$filePrefix =~ s/[\/\\]/-/g;	# Produce a suitable filename for serial ports (on unix systems)
				$host_io->{InputLog} = $filePrefix . $DebugInFile;
				$host_io->{OutputLog} = $filePrefix . $DebugOutFile;
				$host_io->{DumpLog} = $filePrefix . $DebugDumpFile;
				$host_io->{TelOptLog} = $filePrefix . $DebugTelOptFile if $host_io->{ComPort} eq 'TELNET';
				$host_io->{CLI}->input_log($host_io->{DebugFilePath} .'/'. $host_io->{InputLog});
				$host_io->{CLI}->output_log($host_io->{DebugFilePath} .'/'. $host_io->{OutputLog});
				$host_io->{CLI}->dump_log($host_io->{DebugFilePath} .'/'. $host_io->{DumpLog});
				$host_io->{CLI}->parent->option_log($host_io->{DebugFilePath} .'/'. $host_io->{TelOptLog}) if $host_io->{ComPort} eq 'TELNET';
				if ($peercp_io->{Connected}) {
					$peercp_io->{InputLog} = $filePrefix . '-peercp' . $DebugInFile;
					$peercp_io->{OutputLog} = $filePrefix . '-peercp' . $DebugOutFile;
					$peercp_io->{DumpLog} = $filePrefix . '-peercp' . $DebugDumpFile;
					$peercp_io->{TelOptLog} = $filePrefix . '-peercp' . $DebugTelOptFile if $host_io->{ComPort} eq 'TELNET';
					$peercp_io->{CLI}->input_log($host_io->{DebugFilePath} .'/'. $peercp_io->{InputLog});
					$peercp_io->{CLI}->output_log($host_io->{DebugFilePath} .'/'. $peercp_io->{OutputLog});
					$peercp_io->{CLI}->dump_log($host_io->{DebugFilePath} .'/'. $peercp_io->{DumpLog});
					$peercp_io->{CLI}->parent->option_log($host_io->{DebugFilePath} .'/'. $peercp_io->{TelOptLog}) if $host_io->{ComPort} eq 'TELNET';
					my $debugLog = $host_io->{DebugFilePath} .'/'. $filePrefix . '-peercp' . $DebugFile;
					$peercp_io->{CLI}->debug_file($debugLog);
				}
				# These debug levels, set every time
				my ($cli_debug, $cli_errmode);
				$cli_debug |= $newDebugLevel & 8 ? $DebugCLIExtreme : 0;
				$cli_debug |= $newDebugLevel & 16 ? $DebugCLIExtremeSerial : 0;
				if ($newDebugLevel & 64) {
					$cli_errmode = 'die';
				}
				elsif ($newDebugLevel & 32) {
					$cli_errmode = 'croak';
				}
				else {
					$cli_errmode = [\&connectionError, $db];
				}
				# Debug level 8 & 16
				$peercp_io->{CLI}->debug($cli_debug) if $peercp_io->{Connected};
				$host_io->{CLI}->debug($cli_debug);
				# Debug level 32 & 64
				$peercp_io->{CLI}->errmode($cli_errmode) if $peercp_io->{Connected};
				$host_io->{CLI}->errmode($cli_errmode);
			}
			elsif ($term_io->{PseudoTerm}) {
				$filePrefix = 'pseudo';
				$filePrefix .= $term_io->{PseudoTerm} if $term_io->{PseudoTerm} < 100;
			}
			if (length $filePrefix) {
				$DebugLog = $filePrefix . $DebugFile;
				if ( open($DebugLogFH, '>', $DebugLog) ) {
					$host_io->{CLI}->debug_file($DebugLogFH) if $host_io->{Connected};
				}
				else {
					undef $DebugLogFH;
					print "Unable to open debug file $DebugLog : $!\n";
				}
			}
		}
		$::Debug = $newDebugLevel;
		$DebugPackage = eval { require $ScriptDir . 'Debug.pm' } if $::Debug && !$DebugPackage;
		$command = '';
	};
	$command eq 'debug run ?' && do {
		print "Syntax: debug run [<optional arguments to pass on to Debug.pm package run method>]\n";
		$command = '';
	};
	$command =~ /^debug run(?: (.*))?/ && do {
		my @args = split(/\s/, $1) if length $1;
		$DebugPackage = eval { require $ScriptDir . 'Debug.pm' } unless $DebugPackage;
		if ($DebugPackage) {
			Debug::run($db, @args) if $DebugPackage;
		}
		else {
			print "No Debug.pm loaded\n";
		}
		$command = '';
	};
	#
	# Flush command
	#
	$command eq 'flush' && do {
		if (defined $host_io->{Username} || defined $host_io->{Password}) {
			$host_io->{Username} = $host_io->{Password} = undef;
			print "Login credentials have been flushed\n";
		}
		else {
			print "There are no cached login credentials\n";
		}
		$command = '';
	};
	#
	# Open command
	#
	$command !~ /^(?:open|telnet|ssh connect) \?$/ && $command =~ /^(open|telnet|ssh connect) (.+)/ && do {
		if ($host_io->{Connected}) {
			if ($host_io->{TcpPort}) {
				print "Already connected to $host_io->{Name} via $host_io->{ComPort} on tcp port $host_io->{TcpPort}\n";
			}
			else {
				print "Already connected to $host_io->{Name} via $host_io->{ComPort}\n";
			}
			$command = '';
		}
		else {
			my $cmd = $1;
			my @args = split(/ /, quoteCurlyMask($2, ' '));
			@args = map { quoteCurlyUnmask($_, ' ') } @args;	# Needs to re-assign, otherwise quoteCurlyUnmask won't work
			my (@opts, $logfileSeen, $sshPublicKey, $annexConnect, $serialConnect, $listenSockets, $relayHost, $relayHostSeen, $termSrvFlag);
			($host_io->{Name}, $host_io->{TcpPort}, $host_io->{RelayHost}, $host_io->{RelayUsername}, $host_io->{RelayPassword}, $host_io->{ComPort}, $host_io->{TerminalSrv}) = ();
			$host_io->{ComPort} = 'SSH' if $cmd eq 'ssh connect'; # Force SSH
			$term_io->{AutoDetect} = 1;
			$script_io->{OverWrite} = '>>'; # Default is append; -o will change it to overwrite.
			OPENARGS: while (my $arg = quotesRemove(shift @args)) {
				if ($arg =~ /\?$/) { # Request syntax
					$command = "$cmd ?";
					last OPENARGS;
				}
				elsif ($arg =~ /^-(\w+)/) {
					@opts = split(//, $1);
					foreach my $opt (@opts) {
						if ($opt eq 'c') {
							if (($arg = quotesRemove(shift @args)) =~ /^(?:CRLF|CR)$/) {
								$term_io->{Newline} = $arg =~ /^CRLF$/i ? "\n" : "\r";
							}
							else {
								$command = "$cmd ?";
								last OPENARGS;
							}
						}
						elsif ($opt eq 'i') {
							if ($arg = quotesRemove(shift @args)) {
								if (-e $arg && -d $arg) {
									$script_io->{LogDir} = File::Spec->rel2abs($arg);
								}
								else {
									print "Log path (-i) is not a valid directory!\n";
									print $ACLI_Prompt;
									return;
								}
							}
							else {
								$command = "$cmd ?";
								last OPENARGS;
							}
						}
						elsif ($opt eq 'j') {
							$script_io->{AutoLog} = 1;
						}
						elsif ($opt eq 'k') {
							$sshPublicKey = shift @args;
						}
						elsif ($opt eq 'l') {
							if ($host_io->{Username} = shift @args) {
								if ($host_io->{Username} =~ /^([^:\s]+):(\S*)$/) {
									$host_io->{Username} = quotesRemove($1);
									$host_io->{Password} = quotesRemove($2);
								}
								else {
									$host_io->{Username} = quotesRemove($host_io->{Username});
								}
								$host_io->{ComPort} = 'SSH';
							}
							else {
								$command = "$cmd ?";
								last OPENARGS;
							}
						}
						elsif ($opt eq 'm') {
							if ($arg = quotesRemove(shift @args)) {
								my ($ok, $err) = readSourceFile($db, $arg, \@RunFilePath);
								unless ($ok) {
									print "$err\n", $ACLI_Prompt;
									return;
								}
							}
							else {
								$command = "$cmd ?";
								last OPENARGS;
							}
						}
						elsif ($opt eq 'n') {
							$term_io->{AutoDetect} = 0;
							debugMsg(1,"AutoDetect = false\n");
						}
						elsif ($opt eq 'o') {
							$script_io->{OverWrite} = '>';
						}
						elsif ($opt eq 'p') {
							$term_io->{AutoLogin} = 1;
							debugMsg(1,"AutoLogin = true\n");
							$host_io->{Password} = undef;
							$host_io->{Username} = undef unless defined $host_io->{ComPort} && $host_io->{ComPort} eq 'SSH'; # (bug11)
						}
						elsif ($opt eq 'r') {
							$relayHost = 1;
						}
						elsif ($opt eq 's') {
							$listenSockets = quotesRemove(shift @args);
						}
						elsif ($opt eq 't') {
							$termSrvFlag = 1;
						}
						elsif ($opt eq 'y') {
							unless ($term_io->{TerminalType} = quotesRemove(shift @args)) {
								$command = "$cmd ?";
								last OPENARGS;
							}
						}
						elsif ($opt eq 'z') {
							if (($arg = quotesRemove(shift @args)) =~ /^(\d+)\s*x\s*(\d+)$/) {
								$term_io->{WindowSize} = [$1, $2];
							}
							elsif ($arg eq '') {
								$term_io->{WindowSize} = [];
							}
							else {
								$command = "$cmd ?";
								last OPENARGS;
							}
						}
						else {
							$command = "$cmd ?";
							last OPENARGS;
						}
					}
				}
				elsif (!$host_io->{Name}) {
					if ($arg =~/^(?:([^:]+)(?::(\S*))?@)?(serial:(.*?))(?:@(\d+))?$/i) {
						$host_io->{Username} = quotesRemove($1);
						$host_io->{Password} = quotesRemove($2);
						($host_io->{Name}, $host_io->{ComPort}, $host_io->{Baudrate}) = ($3, $4, $5);
						unless ($host_io->{ComPort}) {
							$host_io->{Name} = '';
							$serialConnect = '';
						} 
					}
					elsif ($arg =~/^(?:([^:]+)(?::(\S*))?@)?((?:annex|trmsrv):(.*))$/i) {
						$host_io->{Username} = quotesRemove($1);
						$host_io->{Password} = quotesRemove($2);
						$host_io->{Name} = $3;
						$annexConnect = $4 || '';
						$host_io->{TerminalSrv} = 1;
					}
					else {
						$host_io->{Name} = $arg;
						if ($host_io->{Name} =~ s/^([^:]+)(?::(\S*))?@(\S+)$/$3/) { # Process embedded username/password
							$host_io->{Username} = quotesRemove($1);
							$host_io->{Password} = quotesRemove($2);
						}
						else {
							$host_io->{Name} = quotesRemove($host_io->{Name});
						}
					}
					$host_io->{ComPort} = 'TELNET' unless $host_io->{ComPort};
					debugMsg(1,"ComPort = $host_io->{ComPort}\n");
				}
				elsif (!$host_io->{TcpPort} && $arg =~ /^\d+$/) {
					if ($arg < 1) {
						print "Invalid telnet port number\n";
						print $ACLI_Prompt;
						return;
					}
					$host_io->{TcpPort} = $arg;
					if ($host_io->{ComPort} eq 'TELNET') {
						# Automatically convert port numbers 1-16 into TCP port numbers 5001-5016
						$host_io->{TcpPort} += $RemoteAnnexBasePort if ($host_io->{TcpPort} && $host_io->{TcpPort} <= 16);
					}
					$host_io->{TerminalSrv} = $termSrvFlag || !$term_io->{AutoDetect}; # If a TCP port is set and either -t or -n flag
				}
				elsif (!$relayHostSeen && $relayHost) {
					$relayHostSeen = 1;
					# Move across details which are thus for the Relay connection
					($host_io->{RelayHost}, $host_io->{Name})		= ($host_io->{Name}, undef);
					($host_io->{RelayTcpPort}, $host_io->{TcpPort})		= ($host_io->{TcpPort}, undef);
					($host_io->{RelayUsername}, $host_io->{Username})	= ($host_io->{Username}, undef);
					($host_io->{RelayPassword}, $host_io->{Password})	= ($host_io->{Password}, undef);
					($host_io->{RelayBaudrate}, $host_io->{Baudrate})	= ($host_io->{Baudrate}, undef);

					# Process the target host
					$host_io->{RelayCommand} = $arg;
					if ($host_io->{RelayCommand} =~ s/(\s+\-l\s+([^:\s]+))(?::(\S+))?/$1/) { # Remove embedded credentials from SSH -l switch
						$host_io->{Username} = quotesRemove($2);
						$host_io->{Password} = quotesRemove($3);
					}
					elsif ($host_io->{RelayCommand} =~ s/([^:\s]+)(?::(\S+))?@(\S+)/$3/) { # Remove embedded credentials from IP
						$host_io->{Username} = quotesRemove($1);
						$host_io->{Password} = quotesRemove($2);
					}
					else {
						$host_io->{RelayCommand} = quotesRemove($host_io->{RelayCommand});
					}

					if ($host_io->{RelayCommand} =~ /^\S+$/) { # Just an IP address / hostname
						$host_io->{RelayCommand} = 'telnet ' . $host_io->{RelayCommand}; # prepend with telnet (for backward compatibility)
					}
					if ($host_io->{RelayCommand} =~ /^\S+\s+-l\s+\S+\s+(\S+)\s*$/
					 || $host_io->{RelayCommand} =~ /^\S+\s+(\S+)\s+-l\s+\S+\s*$/
					 || $host_io->{RelayCommand} =~ /^\S+\s+(\S+)\s*$/) {
						# We expect something like: telnet|ssh -l <user>|rlogin|etc <hostname|IP>
						$host_io->{Name} = $1;
					}
					else {
						print "Relay command not of form: <command> <target>\n\n";
						$command = "$cmd ?";
						last OPENARGS;
					}
					debugMsg(1,"RelayHost = $host_io->{RelayHost}\n") if $host_io->{RelayHost};
					debugMsg(1,"RelayTcpPort = $host_io->{RelayTcpPort}\n") if $host_io->{RelayTcpPort};
					debugMsg(1,"RelayUsername = $host_io->{RelayUsername}\n") if $host_io->{RelayUsername};
					debugMsg(1,"RelayPassword = $host_io->{RelayPassword}\n") if $host_io->{RelayPassword};
					debugMsg(1,"RelayBaudrate = $host_io->{RelayBaudrate}\n") if $host_io->{RelayBaudrate};
					debugMsg(1,"RelayCommand = $host_io->{RelayCommand}\n") if $host_io->{RelayCommand};
				}
				elsif (!$logfileSeen) {
					if ($script_io->{AutoLog}) { # -j flag not allowed with logfile
						print "Cannot specify a capture-file with Auto-Logging enabled\n\n";
						$command = "$cmd ?";
						last OPENARGS;
					}
					$logfileSeen = 1;
					$script_io->{LogFile} = $arg;
				}
				else { # Unexpected argument
					$command = "$cmd ?";
					last OPENARGS;
				}
			} # OPENARGS

			# Process ssh options if set
			if ($sshPublicKey) {
				if ($host_io->{ComPort} eq 'SSH') {
					unless (verifySshKeys($host_io, $sshPublicKey)) {
						print "SSH keys not found\n";
						print $ACLI_Prompt;
						return;
					}
				}
				else {
					$command = "$cmd ?";
				}
			}
			# Check essential info set
			$command = 'open ?' unless ($host_io->{ComPort} && $host_io->{Name}) || defined $annexConnect || defined $serialConnect;
			unless ($command eq 'open ?') { # We can connect...
				if (defined $listenSockets) { # Handle request to open listening sockets from command line
					if (!$term_io->{SocketEnable}) { # We can't
						print "Socket functionality is disabled; cannot open sockets!\n";
						print $ACLI_Prompt;
						return;
					}
					else { # We can
						my @sockets = split(',', $listenSockets);
						my ($success, @failedSockets) = openSockets($socket_io, @sockets);
						if (!$success) {
							print "Unable to allocate socket numbers\n";
						}
						elsif (@failedSockets) {
							print "Failed to create sockets: " . join(', ', @failedSockets) . "\n";
						}
						else {
							print "Listening on sockets: " . join(',', sort {$a cmp $b} keys %{$socket_io->{ListenSockets}}) . "\n";
						}
					}
				}
				if (defined $annexConnect) { # Handle connection to known remote annex port
					loadTrmSrvConnections($db, $annexConnect) or do {
						print $ACLI_Prompt;
						return;
					};
					# If we get here, there are 2 possible outcomes:
					# - $host_io->{Name} has been set, so we fall through below
					# - $host_io->{Name} is empty, so we handle this now
					unless ($host_io->{Name}) {
						$script_io->{AcliControl} = 3;
						return;
					}
				}
				elsif (defined $serialConnect) { # Handle connection to local serial port
					my $retVal = readSerialPorts($serialData);
					unless (defined $retVal) { # Not able to check for them
						print "Unable to read serial ports";
						print " from Registry; try running with administrator rights" if $^O eq 'MSWin32';
						print "\n", $ACLI_Prompt;
						return;
					}
					unless ($retVal) { # Able to check, but none found
						print "No serial ports found\n", $ACLI_Prompt;
						return;
					}
					# Some serial ports found
					$script_io->{AcliControl} = 5;
					return;
				}
				debugMsg(1,"Host = $host_io->{Name}\n");
				debugMsg(1,"Port = $host_io->{TcpPort}\n") if $host_io->{TcpPort};
				return 1;
			}
		}
	};
	$command eq 'open ?' && do { # Must come after open command with args
		print "Syntax: open [-ckijlmnoprstyz] [<user>:<pwd>@]<host/IP> [<tcp-port>] [<capture-file>]\n";
		print "    or: open [-cijmnoprs]      [<user>:<pwd>@]serial:[<com-port>[@<baudrate>]] [<capture-file>]\n";
		print "    or: open [-cijmnoprsyz]    [<user>:<pwd>@]trmsrv:[<device-name> | <host/IP>#<port>] [<capture-file>]\n";
		print "    or: open -r <host/IP or serial or trmsrv syntaxes above> <\"relay cmd\" | IP> [<capture-file>]\n\n";
		print " <host/IP>        : Hostname or IP address to connect to; for telnet can use <user>:<pwd>@<host/IP>\n";
		print " <tcp-port>       : TCP port number to use\n";
		print " <com-port>       : Serial Port name (COM1, /dev/ttyS0, etc..) to use\n";
		print " <capture-file>   : Optional output capture file of CLI session\n";
		print " -c <CR|CRLF>     : For newline use CR+LF (default) or just CR\n";
		print " -i <log-dir>     : Path to use when logging to file\n";
		print " -j               : Automatically start logging to file (<host/IP> used as filename)\n";
		print " -k <key_file>    : SSH private key to load; public key implied <key_file>.pub\n";
		print " -l user[:<pwd>]  : SSH username[& password] to use; this option produces an SSH connection\n";
		print " -m <script>      : Once connected execute script (if no path included will use \@run search paths)\n";
		print " -n               : Do not try and auto-detect & interact with device\n";
		print " -o               : Overwrite <capture-file> instead of appending to it\n";
		print " -p               : Use factory default credentials to login automatically\n";
		print " -r               : Connect via Relay; append telnet/ssh command to use on Relay to reach host\n";
		print " -s <sockets>     : List of socket names for terminal to listen on\n";
		print " -t               : When tcp-port specified, flag to say we are connecting to a terminal server\n";
		print " -y <term-type>   : Negotiate terminal type (e.g. vt100)\n";
		print " -z <w>x<h>       : Negotiate window size (width x height)\n";
		$command = '';
	};
	$command eq 'ssh connect ?' && do { # Must come after open command with args
		print "Syntax: ssh connect [-ckijlmnoprstyz] <host/IP> [<tcp-port>] [<capture-file>]\n";
		print "    or: ssh connect -r <host/IP> <\"relay cmd\" | IP> [<capture-file>]\n\n";
		print " <host/IP>        : Hostname or IP address to connect to\n";
		print " <tcp-port>       : TCP port number to use\n";
		print " <capture-file>   : Optional output capture file of CLI session\n";
		print " -c <CR|CRLF>     : For newline use CR+LF (default) or just CR\n";
		print " -k <key_file>    : SSH private key to load; public key implied <key_file>.pub\n";
		print " -i <log-dir>     : Path to use when logging to file\n";
		print " -j               : Automatically start logging to file (<host/IP> used as filename)\n";
		print " -l user[:<pwd>]  : SSH username[& password] to use\n";
		print " -m <script>      : Once connected execute script (if no path included will use \@run search paths)\n";
		print " -n               : Do not try and auto-detect & interact with device\n";
		print " -o               : Overwrite <capture-file> instead of appending to it\n";
		print " -p               : Use factory default credentials to login automatically\n";
		print " -r               : Connect via Relay; append telnet/ssh command to use on Relay to reach host\n";
		print " -s <sockets>     : List of socket names for terminal to listen on\n";
		print " -t               : When tcp-port specified, flag to say we are connecting to a terminal server\n";
		print " -y <term-type>   : Negotiate terminal type (e.g. vt100)\n";
		print " -z <w>x<h>       : Negotiate window size (width x height)\n";
		$command = '';
	};
	$command eq 'telnet ?' && do { # Must come after open command with args
		print "Syntax: telnet [-cijmnoprstyz] [<user>:<pwd>@]<host/IP> [<tcp-port>] [<capture-file>]\n";
		print "    or: telnet -r <host/IP> <\"relay cmd\" | IP> [<capture-file>]\n\n";
		print " <host/IP>        : Hostname or IP address to connect to; can use <username>:<password>@<host/IP>\n";
		print " <tcp-port>       : TCP port number to use\n";
		print " <capture-file>   : Optional output capture file of CLI session\n";
		print " -c <CR|CRLF>     : For newline use CR+LF (default) or just CR\n";
		print " -i <log-dir>     : Path to use when logging to file\n";
		print " -j               : Automatically start logging to file (<host/IP> used as filename)\n";
		print " -m <script>      : Once connected execute script (if no path included will use \@run search paths)\n";
		print " -n               : Do not try and auto-detect & interact with device\n";
		print " -o               : Overwrite <capture-file> instead of appending to it\n";
		print " -p               : Use factory default credentials to login automatically\n";
		print " -r               : Connect via Relay; append telnet/ssh command to use on Relay to reach host\n";
		print " -s <sockets>     : List of socket names for terminal to listen on\n";
		print " -t               : When tcp-port specified, flag to say we are connecting to a terminal server\n";
		print " -y <term-type>   : Negotiate terminal type (e.g. vt100)\n";
		print " -z <w>x<h>       : Negotiate window size (width x height)\n";
		$command = '';
	};
	#
	# Pseudo command
	#
	$command eq 'pseudo disable' && do {
		if ($term_io->{PseudoTerm}) {
			$term_io->{PseudoTerm} = 0;
			$host_io->{Type} = '';
			$term_io->{Mode} = 'transparent';
			$prompt->{Match} = $prompt->{Regex} = undef;
		}
		else {
			print "Pseudo Terminal is not enabled\n";
		}
		$command = '';
	};
	$command eq 'pseudo enable ?' && do {
		print "Syntax: pseudo enable [name or number 1-99]\n";
		$command = '';
	};
	$command =~ /^pseudo enable(?: (\S+))?/ && do {
		unless ($host_io->{Connected}) {
			enablePseudoTerm($db, $1  || 100);
			return 1; # This will trigger entering it
		}
		print "Cannot enable Pseudo Terminal if connected to a device\n";
		$command = '';
	};
	$command =~ /^pseudo load (.+)/ && do {
		unless ($host_io->{Connected}) {
			enablePseudoTerm($db, $1);
			return 1; # This will trigger entering it
		}
		print "Cannot enable Pseudo Terminal if connected to a device\n";
		$command = '';
	};
	#
	# Quit command
	#
	$command eq 'quit' && do {
		disconnect($db);
		quit(0, undef, $db);
		$command = '';
	};
	#
	# Reconnect command
	#
	$command eq 'reconnect' && do {
		if ($host_io->{Connected}) {
			disconnect($db, 1);
			print "Existing connection to ", $host_io->{Name}, " closed\n";
		}
		if ($host_io->{Name}) {
			if (@{$term_io->{CredentHistory}}) { # if doing reconnect in the middle of telnet hopping..
				# .. preserve the original credentials
				($host_io->{Username}, $host_io->{Password}) = @{ ${$term_io->{CredentHistory}}[0] };
				$term_io->{ConnectHistory} = []; # Empty this stack
				$term_io->{CredentHistory} = []; # Empty this stack
				$term_io->{VarsHistory} = []; # Empty this stack
			}
			return 1; # This will trigger a connection
		}
		else {
			print "No lost connection to reconnect to\n";
		}
		$command = '';
	};
	#
	# Serial command
	#
	$command =~ /^serial baudrate (\d+)$/ && do {
		my $baudrate = $1;
		if ( !$host_io->{Connected} || ($host_io->{Connected} && $host_io->{ComPort} =~ /^(?:TELNET|SSH)$/) ) {
			print "No serial port connection active!\n";
		}
		elsif ( $baudrate == $host_io->{CLI}->baudrate ) {
			print "Baudrate already set to $baudrate\n";
		}
		elsif ( $host_io->{CLI}->Control::CLI::change_baudrate(Baudrate => $baudrate, Blocking => 1) ) {
			$host_io->{Baudrate} = $baudrate;
			print "Baudrate changed to $baudrate\n";
		}
		else {
			print "Failed to change baudrate: ", $host_io->{CLI}->errmsg, "\n";
		}
		$command = '';
	};
	$command eq 'serial databits ?' && do {
		print "Syntax: serial databits <5-8>\n";
		$command = '';
	};
	$command =~ /^serial databits (\d)$/ && do {
		my $databits = $1;
		if ( !$host_io->{Connected} || ($host_io->{Connected} && $host_io->{ComPort} =~ /^(?:TELNET|SSH)$/) ) {
			print "No serial port connection active!\n";
		}
		elsif ( $databits eq $host_io->{CLI}->databits ) {
			print "Databits already set to $databits\n";
		}
		elsif ( $host_io->{CLI}->Control::CLI::change_baudrate(Databits => $databits) ) {
			print "Databits changed to $databits\n";
		}
		else {
			print "Failed to change databits: ", $host_io->{CLI}->errmsg, "\n";
		}
		$command = '';
	};
	$command =~ /^serial handshake (\w+)$/ && do {
		my $handshake = $1;
		if ( !$host_io->{Connected} || ($host_io->{Connected} && $host_io->{ComPort} =~ /^(?:TELNET|SSH)$/) ) {
			print "No serial port connection active!\n";
		}
		elsif ( $handshake eq $host_io->{CLI}->handshake ) {
			print "Handshake already set to $handshake\n";
		}
		elsif ( $host_io->{CLI}->Control::CLI::change_baudrate(Handshake => $handshake) ) {
			print "Handshake changed to $handshake\n";
		}
		else {
			print "Failed to change handshake: ", $host_io->{CLI}->errmsg, "\n";
		}
		$command = '';
	};
	$command eq 'serial info' && do {
		if ( !$host_io->{Connected} || ($host_io->{Connected} && $host_io->{ComPort} =~ /^(?:TELNET|SSH)$/) ) {
			print "No serial port connection active!\n";
		}
		else {
			print "Current Serial Connection details:\n";
			printf "	COM port   : %s\n", $host_io->{ComPort};
			printf "	Baudrate   : %s\n", $host_io->{CLI}->baudrate;
			printf "	Parity     : %s\n", $host_io->{CLI}->parity;
			printf "	Databits   : %s\n", $host_io->{CLI}->databits;
			printf "	Stopbits   : %s\n", $host_io->{CLI}->stopbits;
			printf "	Handshake  : %s\n", $host_io->{CLI}->handshake;
		}
		$command = '';
	};
	$command =~ /^serial parity (\w+)$/ && do {
		my $parity = $1;
		if ( !$host_io->{Connected} || ($host_io->{Connected} && $host_io->{ComPort} =~ /^(?:TELNET|SSH)$/) ) {
			print "No serial port connection active!\n";
		}
		elsif ( $parity eq $host_io->{CLI}->parity ) {
			print "Parity already set to $parity\n";
		}
		elsif ( $host_io->{CLI}->Control::CLI::change_baudrate(Parity => $parity) ) {
			print "Parity changed to $parity\n";
		}
		else {
			print "Failed to change parity: ", $host_io->{CLI}->errmsg, "\n";
		}
		$command = '';
	};
	$command eq 'serial stopbits ?' && do {
		print "Syntax: serial stopbits < 1 | 1.5 | 2 >\n";
		$command = '';
	};
	$command =~ /^serial stopbits (\S+)$/ && do {
		my $stopbits = $1;
		if ( !$host_io->{Connected} || ($host_io->{Connected} && $host_io->{ComPort} =~ /^(?:TELNET|SSH)$/) ) {
			print "No serial port connection active!\n";
		}
		elsif ( $stopbits eq $host_io->{CLI}->stopbits ) {
			print "Stopbits already set to $stopbits\n";
		}
		elsif ( $host_io->{CLI}->Control::CLI::change_baudrate(Stopbits => $stopbits) ) {
			print "Stopbits changed to $stopbits\n";
		}
		else {
			print "Failed to change stopbits: ", $host_io->{CLI}->errmsg, "\n";
		}
		$command = '';
	};
	#
	# Socket command
	#
	$command eq 'socket names clear' && do {
		$socket_io->{Port} = $Default{socket_names_val}; # Reset to defaults
		saveSocketNames($socket_io);
		print "Reset sockets to defaults\n";
		$command = '';
	};
	$command eq 'socket names reload' && do {
		if (loadSocketNames($socket_io)) {
			print "Loaded socket names from ", $socket_io->{SocketFile}, "\n";
		}
		else {
			print "Unable to load socket file\n";
		}
		$command = '';
	};
	$command eq 'socket ping ?' && do {
		print "Syntax: socket ping [<socket name>]\n";
		$command = '';
	};
	$command eq 'socket ping' && do {
		if (!$term_io->{SocketEnable}) {
			print "Socket functionality is disabled\n";
		}
		elsif (!$socket_io->{Tie}) {
			print "Not tied to any socket\n";
		}
		else {
			# Case where echo mode is disabled, we need to enable it for ping responses
			my $cacheEcho = $socket_io->{TieEchoMode} = 1 if $socket_io->{TieEchoMode} == 0;
			# Call tieSocketEcho() only if the echo mode was none
			if ($cacheEcho && !tieSocketEcho($socket_io) ) { # Set up the Echo mode RX socket if necessary
				print "Unable to create echo mode socket\n";
				$socket_io->{TieEchoMode} = 0 if $cacheEcho;
			}
			else {
				socketBufferPack($socket_io, '', 6); # Send a ping
				# Call handleSocketIO a 1st time to send the ping
				handleSocketIO($db);
				# Wait a safe time more than the main loop timer (to make sure any responding terminal has time to respond)
				Time::HiRes::sleep($MainloopTimer * 10);
				# Call handleSocketIO a 2nd time to read in the responses, if any
				handleSocketIO($db);
				# Print out the responses
				my $count = 0;
				foreach my $echoBuffer (keys %{$socket_io->{TieEchoBuffers}}) {
					if ($socket_io->{TieEchoSeqNumb}->{$echoBuffer} == 0) { # A complete buffer
						print $socket_io->{TieEchoBuffers}->{$echoBuffer};
						delete($socket_io->{TieEchoBuffers}->{$echoBuffer});
						delete($socket_io->{TieEchoSeqNumb}->{$echoBuffer});
						$count++;
					}
				}
				print "Echo received from ", $count, " terminals\n";
			}
		}
		$command = '';
	};
	$command =~ /^socket ping (\S+)/ && do {
		my $sockName = $1;
		if (!$term_io->{SocketEnable}) {
			print "Socket functionality is disabled\n";
		}
		else {
			my $cacheTie;
			if ($cacheTie = $socket_io->{Tie}) {
				untieSocket($socket_io, 1);
			}
			if ( tieSocket($socket_io, $sockName, 1) ) { # Success
				# Case where echo mode is disabled, we need to enable it for ping responses
				my $cacheEcho = $socket_io->{TieEchoMode} = 1 if $socket_io->{TieEchoMode} == 0;
				# Call tieSocketEcho() only if we were not already tied before OR the echo mode was none
				if ((!$cacheTie || $cacheEcho) && !tieSocketEcho($socket_io) ) { # Set up the Echo mode RX socket if necessary
					print "Unable to create echo mode socket\n";
					$socket_io->{TieEchoMode} = 0 if $cacheEcho;
					tieSocket($socket_io, $cacheTie, 1) if $cacheTie; # Re-tie to previous
				}
				else {
					socketBufferPack($socket_io, '', 6); # Send a ping
					# Call handleSocketIO a 1st time to send the ping
					handleSocketIO($db);
					# Wait a safe time more than the main loop timer (to make sure any responding terminal has time to respond)
					Time::HiRes::sleep($MainloopTimer * 10);
					# Call handleSocketIO a 2nd time to read in the responses, if any
					handleSocketIO($db);
					# Print out the responses
					my $count = 0;
					foreach my $echoBuffer (keys %{$socket_io->{TieEchoBuffers}}) {
						if ($socket_io->{TieEchoSeqNumb}->{$echoBuffer} == 0) { # A complete buffer
							print $socket_io->{TieEchoBuffers}->{$echoBuffer};
							delete($socket_io->{TieEchoBuffers}->{$echoBuffer});
							delete($socket_io->{TieEchoSeqNumb}->{$echoBuffer});
							$count++;
						}
					}
					print "Echo received from ", $count, " terminals\n";
					if ($cacheTie) { # We need to restore a cached socket which was tied before
						untieSocket($socket_io, 1);
						tieSocket($socket_io, $cacheTie, 1);
					}
					else {
						untieSocket($socket_io);
					}
				}
			}
			else { # Fail
				print "Unable to create socket $sockName for ping\n";
				tieSocket($socket_io, $cacheTie, 1) if $cacheTie; # Re-tie to previous
			}
		}
		$command = '';
	};
	$command =~ /^socket send .*\?$/ && do {
		print "Syntax: socket send <socket name> <command>\n";
		$command = '';
	};
	$command =~ /^socket send (\S+)(?:\s+(.+))?/ && do {
		my $sockName = $1;
		my $sendCmd = quotesRemove($2) || '';
		if (!$term_io->{SocketEnable}) {
			print "Socket functionality is disabled\n";
		}
		else {
			my $cacheTie;
			if ($cacheTie = $socket_io->{Tie}) {
				untieSocket($socket_io, 1);
			}
			if ( tieSocket($socket_io, $sockName, 1) ) { # Success
				socketBufferPack($socket_io, $sendCmd."\n", 4); # Send the command (mode 4 will not embed echo mode)
				handleSocketIO($db);
				if ($cacheTie) { # We need to restore a cached socket which was tied before
					untieSocket($socket_io, 1);
					tieSocket($socket_io, $cacheTie, 1);
				}
				else {
					untieSocket($socket_io);
				}
			}
			else { # Fail
				print "\nUnable to create socket $sockName for send\n";
				tieSocket($socket_io, $cacheTie, 1) if $cacheTie; # Re-tie to previous
			}
		}
		$command = '';
	};
	#
	# Ssh command
	#
	$command eq 'ssh known-hosts clense' && do {
		unless ($term_io->{KnownHostsFile}) { # Try and locate it
			foreach my $path (@SshKeyPath) {
				my $known_hosts = File::Spec->canonpath("$path/$KnownHostsFile");
				next unless -e $known_hosts;
				$term_io->{KnownHostsFile} = $known_hosts;
				$term_io->{KnownHostsDummy} = File::Spec->canonpath("$path/$KnownHostsDummy"); # In same path as real known_hosts file
				last;
			}
		}
		if ($term_io->{KnownHostsFile}) {
			my ($duplicate, $corrupted, $modified) = clenseSshKnownHostFile($db);
			if ($duplicate || $corrupted || $modified) {
				cmdMessage($db, "Successfully updated SSH $KnownHostsFile file with the following changes:\n");
				if ($duplicate) {
					cmdMessage($db, "- Deleted $duplicate duplicate entries\n");
				}
				if ($corrupted) {
					cmdMessage($db, "- Deleted $corrupted corrupted entries\n");
				}
				if ($modified) {
					cmdMessage($db, "- Modified (made lower case or changed to IPv6 compact notation) $modified entries\n");
				}
			}
			else {
				cmdMessage($db, "SSH $KnownHostsFile file is clean (has no duplicate or corrupted or invalid entries)\n");
			}
		}
		else {
			cmdMessage($db, "No SSH $KnownHostsFile file\n");
		}
		$command = '';
	};
	#
	# Terminal command
	#
	$command eq 'terminal autodetect enable' && do {
		$term_io->{AutoDetect} = 1;
		$command = '';
	};
	$command eq 'terminal autodetect disable' && do {
		$term_io->{AutoDetect} = 0;
		$command = '';
	};
	$command eq 'terminal configindent ?' && do {
		print "Syntax: terminal configindent <0-99>\n";
		$command = '';
	};
	$command =~ /^terminal configindent (\d\d?)/ && do {
		$term_io->{GrepIndent} = $1;
		$command = '';
	};
	$command eq 'terminal hosterror disable' && do {
		$host_io->{ErrorDetect} = 0;
		$command = '';
	};
	$command eq 'terminal hosterror enable' && do {
		$host_io->{ErrorDetect} = 1;
		$command = '';
	};
	$command eq 'terminal hosterror level error' && do {
		$host_io->{ErrorLevel} = 'error';
		$command = '';
	};
	$command eq 'terminal hosterror level warning' && do {
		$host_io->{ErrorLevel} = 'warning';
		$command = '';
	};
	$command eq 'terminal hostmode transparent' && do {
		$host_io->{CapabilityMode} = 'transparent';
		if ($term_io->{Mode} eq 'interact') { # Shut it down now
			$term_io->{Mode} = 'transparent';
			if (defined $script_io->{CmdLogFH}) {
				close $script_io->{CmdLogFH};
				$script_io->{CmdLogFH} = $script_io->{CmdLogFile} = $script_io->{CmdLogOnly} = $script_io->{CmdLogFlag} = undef;
			}
			$host_io->{OutBuffer} = ''; # Flush BufferedOutput buffer, in case it's not empty
			$host_io->{SendBuffer} .= $term_io->{Newline};	# Send a carriage return to host
			# Change the cache mode directly
			changeMode($cacheMode, {term_in => 'sh', dev_inp => 'rd', dev_del => 'ds', dev_fct => 'ds', dev_out => 'ub', buf_out => 'ds'}, '#C17');
		}
		$command = '';
	};
	$command eq 'terminal hostmode interact' && do {
		$host_io->{CapabilityMode} = 'interact';
		print "Return to host and issue CTRL $term_io->{CtrlInteractPrn} to activate interact mode\n" if $host_io->{Connected};
		$command = '';
	};
	$command eq 'terminal newline cr' && do {
		$term_io->{Newline} = "\r";
		$host_io->{CLI}->output_record_separator($term_io->{Newline}) if $host_io->{Connected};
		$peercp_io->{CLI}->output_record_separator($term_io->{Newline}) if $peercp_io->{Connected};
		$command = '';
	};
	$command eq 'terminal newline crlf' && do {
		$term_io->{Newline} = "\n";
		$host_io->{CLI}->output_record_separator($term_io->{Newline}) if $host_io->{Connected};
		$peercp_io->{CLI}->output_record_separator($term_io->{Newline}) if $peercp_io->{Connected};
		$command = '';
	};
	$command eq 'terminal promptsuffix disable' && do {
		$term_io->{LtPrompt} = 0;
		$command = '';
	};
	$command eq 'terminal promptsuffix enable' && do {
		$term_io->{LtPrompt} = 1;
		$command = '';
	};
	$command eq 'terminal size clear' && do {
		if ($host_io->{Connected} && @{$term_io->{WindowSize}}) {
			print "New window size will only take effect on re-connect\n";
			$term_io->{TermTypeNotNego} = 1;
		}
		$term_io->{WindowSize} = [];
		$command = '';
	};
	$command eq 'terminal size set ?' && do {
		print "Syntax: terminal type set <width> x <height>\n";
		$command = '';
	};
	$command =~ /^terminal size set (\d+)\s*x\s*(\d+)/ && do {
		my ($width, $height) = ($1, $2);
		if ($host_io->{Connected} && ($width != $term_io->{WindowSize}-[0] || $height != $term_io->{WindowSize}->[1])) {
			print "New window size will only take effect on re-connect\n";
			$term_io->{TermWinSNotNego} = 1;
		}
		$term_io->{WindowSize} = [$width, $height];
		$command = '';
	};
	$command eq 'terminal timers connection ?' && do {
		print "Syntax: terminal timers connection <timeout in seconds>\n";
		$command = '';
	};
	$command =~ /^terminal timers connection (\d+)/ && do {
		my $newValue = $1;
		if ($newValue == 0) {
			print "Timeout cannot be null\n";
		}
		else {
			$host_io->{ConnectTimeout} = $newValue;
		}
		$command = '';
	};
	$command eq 'terminal timers interact ?' && do {
		print "Syntax: terminal timers interact <timeout in seconds>\n";
		$command = '';
	};
	$command =~ /^terminal timers interact (\d+)/ && do {
		my $newValue = $1;
		if ($newValue == 0) {
			print "Timeout cannot be null\n";
		}
		else {
			$host_io->{Timeout} = $newValue;
		}
		$command = '';
	};
	$command eq 'terminal timers login ?' && do {
		print "Syntax: terminal timers login <timeout in seconds>\n";
		$command = '';
	};
	$command =~ /^terminal timers login (\d+)/ && do {
		my $newValue = $1;
		if ($newValue == 0) {
			print "Timeout cannot be null\n";
		}
		else {
			$host_io->{LoginTimeout} = $newValue;
		}
		$command = '';
	};
	$command eq 'terminal timers keepalive ?' && do {
		print "Syntax: terminal timers keepalive <timer in minutes; 0 = disable>\n";
		$command = '';
	};
	$command =~ /^terminal timers keepalive (\d+)/ && do {
		my $newValue = $1;
		if ($newValue >= $host_io->{SessionTimeout}) {
			print "Keepalive timer must be smaller than session timer\n";
		}
		else {
			$host_io->{KeepAliveTimer} = $newValue;
		}
		$command = '';
	};
	$command eq 'terminal timers session ?' && do {
		print "Syntax: terminal timers session <timeout in minutes; 0 = disable>\n";
		$command = '';
	};
	$command =~ /^terminal timers session (\d+)/ && do {
		my $newValue = $1;
		if ($newValue == 0) {
			print "Timeout cannot be null\n";
		}
		elsif ($newValue <= $host_io->{KeepAliveTimer}) {
			print "Session timer must be greater than keepalive timer\n";
		}
		else {
			$host_io->{SessionTimeout} = $newValue;
		}
		$command = '';
	};
	$command eq 'terminal timers transparent-keepalive disable' && do {
		$host_io->{TranspKeepAlive} = 0;
		$command = '';
	};
	$command eq 'terminal timers transparent-keepalive enable' && do {
		$host_io->{TranspKeepAlive} = 1;
		$command = '';
	};
	$command eq 'terminal type clear' && do {
		if ($host_io->{Connected} && defined $term_io->{TerminalType}) {
			print "New terminal type will only take effect on re-connect\n";
			$term_io->{TermTypeNotNego} = 1;
		}
		$term_io->{TerminalType} = undef;
		$command = '';
	};
	$command eq 'terminal type set ?' && do {
		print "Syntax: terminal type set <vt; e.g. vt100>\n";
		$command = '';
	};
	$command =~ /^terminal type set (\S+)/ && do {
		my $vterm = $1;
		if ($host_io->{Connected} && $vterm ne $term_io->{TerminalType}) {
			print "New terminal type will only take effect on re-connect\n";
			$term_io->{TermTypeNotNego} = 1;
		}
		$term_io->{TerminalType} = $vterm;
		$command = '';
	};
	#
	# Trmsrv command
	#
	$command =~ /^trmsrv add .*\?$/ && do {
		print "Syntax: trmsrv add telnet|ssh <IP/hostname> <TCP-port> <Device-Name> [<Comments>]\n";
		$command = '';
	};
	$command =~ /^trmsrv add (telnet|ssh) (\S+) (\d+) (\S+)(?: (.+))?/ && do {
		my ($com, $ip, $port, $name, $comments) = ($1, $2, $3, quotesRemove($4), defined $5 ? quotesRemove($5):'');
		loadTrmSrvStruct($db);
		addTrmSrvListEntry($db, $ip, $com eq 'ssh' ? 's':'t', $port, $name, '', $comments);
		if (saveTrmSrvList($db)) {
			print "Saved updated terminal-server file\n";
		}
		else {
			print "Unable to save terminal-server file\n";
		}
		$command = '';
	};
	$command =~ /^trmsrv connect .*\?$/ && do {
		print "Syntax: trmsrv connect <entry-index-number>\n";
		$command = '';
	};
	$command =~ /^trmsrv connect (\d+)/ && do {
		my $selection = $1;
		if ($host_io->{Connected}) {
			if ($host_io->{TcpPort}) {
				print "Already connected to $host_io->{Name} via $host_io->{ComPort} on tcp port $host_io->{TcpPort}\n";
			}
			else {
				print "Already connected to $host_io->{Name} via $host_io->{ComPort}\n";
			}
		}
		else {
			loadTrmSrvStruct($db) unless $host_io->{AnnexFile};
			if ($selection >= 1 && $selection <= scalar @{$annexData->{List}}) { # Number in range entered
				$host_io->{Name} = $annexData->{List}->[$selection - 1][0];
				$host_io->{ComPort} = $annexData->{List}->[$selection - 1][1] eq 's' ? 'SSH' : 'TELNET';
				$host_io->{TcpPort} = $annexData->{List}->[$selection - 1][2];
				$term_io->{AutoDetect} = 0; # Always disable auto-detect when using this command
				$host_io->{TerminalSrv} = 1;
				return 1;
			}
			else {
				print "Index $selection is outside range of available terminal-server connections\n";
			}
		}
		$command = '';
	};
	$command eq 'trmsrv delete file' && do {
		loadTrmSrvStruct($db) unless $host_io->{AnnexFile};
		if ( index($host_io->{AnnexFile}, $ScriptDir) == 0) { # We are using the file in ACLI install directory
			print "No personal terminal-server file to delete\n";
			print "The currently loaded terminal-server file is located in the ACLI install directory\n";
			print $host_io->{AnnexFile}, "\n";
		}
		elsif ( $host_io->{AnnexFile} eq $annexData->{MasterFile}) { # We are using the Master file, cannot delete this one
			print "No personal terminal-server file to delete\n";
			print "The currently loaded terminal-server file is the master terminal-server file\n";
			print $annexData->{MasterFile}, "\n";
		}
		elsif (unlink $host_io->{AnnexFile}) {
			print "Deleted terminal-server file: $host_io->{AnnexFile}\n";
			$host_io->{AnnexFile} = '';
		}
		else {
			print "Failed delete terminal-server file: $!\n";
		}
		$command = '';
	};
	$command eq 'trmsrv info' && do {
		loadTrmSrvStruct($db) unless $host_io->{AnnexFile};
		print "Master terminal-server File : ", ($annexData->{MasterFile} ? $annexData->{MasterFile} : 'not set'), "\n";
		print "In use terminal-server File : ", $host_io->{AnnexFile}, "\n";
		print "Sort mode                   : ", (defined $annexData->{Sort} ? $annexData->{Sort} : 'not set'), "\n";
		print "Static mode                 : ", ($annexData->{Static} ? 'enabled' : 'disabled'), "\n";
		$command = '';
	};
	$command eq 'trmsrv list ?' && do {
		print "Syntax: trmsrv list [<pattern>]\n";
		$command = '';
	};
	$command =~ /^trmsrv list(?: (.*))?/ && do {
		my $pattern = $1;
		# load
		if (loadTrmSrvStruct($db)) {
			printTrmSrvList($annexData, $pattern, 1);
		}
		else {
			print "Unable to read terminal-server file\n";
		}
		$command = '';
	};
	$command =~ /^trmsrv remove .*\?$/ && do {
		print "Syntax: trmsrv remove telnet|ssh <IP/hostname> <TCP-port>\n";
		$command = '';
	};
	$command =~ /^trmsrv remove (telnet|ssh) (\S+) (\d+)/ && do {
		my ($com, $ip, $port) = ($1, $2, $3);
		loadTrmSrvStruct($db);
		my $delIndex;
		for my $i ( 0..$#{$annexData->{List}} ) {
			my $entry = $annexData->{List}->[$i];
			next unless $entry->[0] eq $ip && $com =~ /^$entry->[1]/i && $entry->[2] eq $port;
			$delIndex = $i;
			last;
		}
		if (defined $delIndex) {
			splice(@{$annexData->{List}}, $delIndex, 1);
			if (saveTrmSrvList($db)) {
				print "Saved updated terminal-server file\n";
			}
			else {
				print "Unable to save terminal-server file\n";
			}
		}
		else {
			print "No matching entry to delete\n";
		}
		$command = '';
	};
	$command =~ /^trmsrv sort (disable|ip|name|cmnt)/ && do {
		my $sortby = $1;
		loadTrmSrvStruct($db);
		$annexData->{Sort} = $sortby ne 'disable' ? $sortby : undef;
		if (saveTrmSrvList($db)) {
			print "Saved updated terminal-server file with sort mode set to '$sortby'\n" if defined $annexData->{Sort};
			print "Saved updated terminal-server file with sort mode disabled\n" unless defined $annexData->{Sort};
		}
		else {
			print "Unable to save terminal-server file\n";
		}
		$command = '';
	};
	$command eq 'trmsrv static disable' && do {
		loadTrmSrvStruct($db);
		$annexData->{Static} = undef;
		if (saveTrmSrvList($db)) {
			print "Saved updated terminal-server file with static mode disabled\n";
		}
		else {
			print "Unable to save terminal-server file\n";
		}
		$command = '';
	};
	$command eq 'trmsrv static enable' && do {
		loadTrmSrvStruct($db);
		$annexData->{Static} = 1;
		if (saveTrmSrvList($db)) {
			print "Saved updated terminal-server file with static mode enabled\n";
		}
		else {
			print "Unable to save terminal-server file\n";
		}
		$command = '';
	};
	#
	# Version command
	#
	$command eq 'version' && do {
		versionInfo;
		$command = '';
	};
	$command eq 'version all' && do {
		versionInfo('all');
		$command = '';
	};

	# Process Common Commands
	$command = processCommonCommand($db, $command) if length $command;

	if (length $command) {
		print "Invalid Command. type ?/help for help\n";
	}

	print $ACLI_Prompt;
	return;
}


sub processEmbeddedCommand { # Process an embedded command available as if on connected host
	my ($db, $embeddedCmd) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $socket_io = $db->[6];
	my $vars = $db->[12];
	my $varscope = $db->[15];
	my $dictscope= $db->[17];

	my ($command, $list);

	return if $embeddedCmd =~ /^\s*$/; # Nothing entered
	$script_io->{EmbCmdSpacing} = undef;

	if ($embeddedCmd =~ /^\s*\$($VarUser)?\s*(\.?=)\s*(\'[^\']*\'|\"[^\"]*\"|.*?)\s*$/o) { # Variable set
		if (defined $1 && $1 eq 'ALL') {
			$command = '$ALL'; # We don't set this reserved variable
		}
		else {
			$command = assignVar($db, '', $1, $2, $3);
		}
	}
	elsif ($embeddedCmd =~ /^\s*\$($VarScript)\[\]\s*(\.?=)\s*(.*?)\s*$/o) { # Variable list set
		$command = assignVar($db, 'list', $1, $2, $3);
	}
	elsif ($embeddedCmd =~ /^\s*\$($VarScript)\[(\d+)\]\s*(\.?=)\s*(.*?)\s*$/o) { # Variable list element set
		$command = assignVar($db, 'list', $1, $3, $4, $2);
	}
	elsif ($embeddedCmd =~ /^\s*\$($VarScript)\{\}\s*(\.?=)\s*(.*?)\s*$/o) { # Variable hash set
		$command = assignVar($db, 'hash', $1, $2, $3);
	}
	elsif ($embeddedCmd =~ /^\s*\$($VarScript)\{($VarHashKey)\}\s*(\.?=)\s*(.*?)\s*$/o) { # Variable hash element set
		$command = assignVar($db, 'hash', $1, $3, $4, $2);
	}
	elsif ($embeddedCmd =~ /^\s*\$([#\'])?($VarSlotAll)\s*$/o) { # Variable show $1/ALL, $2:ALL, etc..
		my $mode = $1 || '';
		my $var = $2 || '_';
		$command = "\$$mode$var";
	}
	elsif ($embeddedCmd =~ /^\s*\$([#\'])?($VarAny(?:\[\d*\]|\{(?:$VarHashKey)?\})?)?\s*$/o) { # Variable show compact/size/raw
		my $mode = $1 || '';
		my $var = $2 || '_';
		$command = "\$$mode$var";
	}
	elsif ($embeddedCmd =~ /^\s*\%\s*$/o) { # Variable '%' show
		$command = "\$%";
	}
	else {
		($command, $list) = tabExpand($EmbeddedCmds, $embeddedCmd, 1);
		debugMsg(4,"=processEmbeddedCommand - tabExpand returned command: >", \$command, "<\n");
		if (defined $list || $command =~ /\?$/) { # Not valid command based on tabExpand return values
			stopSourcing($db);
			debugMsg(4,"=processEmbeddedCommand - halting sourcing\n");
		}
		if (defined $list) {
			debugMsg(4,"=processEmbeddedCommand - tabExpand returned list: >", \$list, "<\n");
			printOut($script_io, "\n$list\n\n");
			$host_io->{OutBuffer} .= $host_io->{Prompt};
			return 1;
		}
		return unless length $command;
	}
	debugMsg(4,"=processEmbeddedCommand - command to process = >", \$command, "<\n");
	# Below, use:
	# cmdMessage($db, "text"); for warning, syntax and error messages (will never be grep-able, or more paged)
	# cmdOutput($db, "text");  for useful output content (will be grep-able & more paged)

	if ($term_io->{EchoOff} && $term_io->{Sourcing} && length $host_io->{CommandCache}) {
		$host_io->{CommandCache} .= "\n";
		debugMsg(4,"=adding to CommandCache:\n>",\$host_io->{CommandCache}, "<\n");
	}
	else {
		printOut($script_io, "\n");
		$script_io->{CmdLogFlag} = 1 if defined $script_io->{CmdLogFlag}; # Can start logging now
	}
	#
	# @help command
	#
	($command eq '@help' || $command eq '@?') && do {
		cmdOutput($db, "Embedded Commands available in interactive mode (%):\n\n");
		cmdOutput($db, "\@acli                                               enter ACLI control\n");
		cmdOutput($db, "\@alias disable|echo|enable|info|list|reload|show    show current connection aliases\n");
		cmdOutput($db, "\@cat (or \@type) <filename>                          display contents of file\n");
		cmdOutput($db, "\@cd <relative or new directory>                     change directory\n");
		cmdOutput($db, "\@cls or \@clear                                      clear the screen\n");
		cmdOutput($db, "\@dictionary echo|info|list|load|path|port-range|reload|unload\n");
		cmdOutput($db, "                                                    manage loaded dictionary\n");
		cmdOutput($db, "\@dir (or \@ls)                                       print directory\n");
		cmdOutput($db, "\@echo on|off [output on|off]|info                   turns on or off displaying commands while sourcing\n");
		cmdOutput($db, "\@error disable|enable|info|level                    set host error detection mode\n");
		cmdOutput($db, "\@help or @?                                         this output\n");
		cmdOutput($db, "\@highlight background|bright|disable|foreground|info|reverse|underline\n");
		cmdOutput($db, "                                                    text formatting for ^<pattern> highlights\n");
		cmdOutput($db, "\@history [clear|device-sent|echo|info|user-entered] view or clear history\n");
		cmdOutput($db, "\@launch                                             spawn a new ACLI session\n");
		cmdOutput($db, "\@log auto-log|info|path|start|stop                  enable/disable session logging\n");
		cmdOutput($db, "\@ls (or \@dir)                                       print directory\n");
		cmdOutput($db, "\@mkdir <new directory to create>                    create a directory\n");
		cmdOutput($db, "\@more disable|enable|info|lines                     enable/disable more paging\n");
		cmdOutput($db, "\@peercp [connect|disconnect]                        view & manage peer CPU connection\n");
		cmdOutput($db, "\@ping <hostname|ip>                                 embedded ping from ACLI terminal\n");
		cmdOutput($db, "\@print [<text>]                                     print some text; useful when sourcing and \@echo off\n");
		cmdOutput($db, "\@printf \"<formatting>\", <value1>[,<value2>..]       print text/values with formatting (same syntax as Perl's printf)\n");
		cmdOutput($db, "\@pseudo attribute|echo|info|list|load|name|port-range|prompt|type\n");
		cmdOutput($db, "                                                    pseudo terminal settings\n");
		cmdOutput($db, "\@put [<text>]                                       print some text; unlike \@print, has no trailing carriage return\n");
		cmdOutput($db, "\@pwd                                                print working directory\n");
		cmdOutput($db, "\@quit                                               quit terminal\n");
		cmdOutput($db, "\@rediscover                                         force a full rediscovery of device\n");
		cmdOutput($db, "\@resume [buffer]                                    resume previously interrputed sourcing or view buffer\n");
		cmdOutput($db, "\@rmdir <directory to delete>                        delete a directory\n");
		cmdOutput($db, "\@run <runscript> [\$1, \$2, ...args]                  run script runscript.run from ACLI install or private path\n");
		cmdOutput($db, "\@run list|path                                      list available run scripts, or view run script paths\n");
		cmdOutput($db, "\@save all|delete|info|reload|sockets|vars|workdir   save device variables and data\n");
		cmdOutput($db, "\@sed colour|info|input|output|reload|reset          stream editor of input/output to/from device\n");
		cmdOutput($db, "\@send brk|char|ctrl|string                          send special character or raw string to host\n");
		cmdOutput($db, "\@sleep <time-in-seconds>                            pause for specified number of seconds\n");
		cmdOutput($db, "\@socket allow|bind|disable|echo|enable|info|ip|listen|names|ping|send|tie|untie|username\n");
		cmdOutput($db, "                                                    link this terminal instance to others\n");
		cmdOutput($db, "\@source <filename> [\$1, \$2, ...args]                source commands from file\n");
		cmdOutput($db, "\@source <.ext> [\$1, \$2, ...args]                    source commands from file switchname.ext\n");
		cmdOutput($db, "\@ssh device-keys|info|keys|known-hosts              manage SSH keys on terminal and connected switch\n");
		cmdOutput($db, "\@status                                             show connection information\n");
		cmdOutput($db, "\@terminal hidetimestamp|info|portrange              set selected terminal settings\n");
		cmdOutput($db, "\@timestamp                                          print out local client's date and time\n");
		cmdOutput($db, "\@type (or \@cat) <filename>                          display contents of file\n");
		cmdOutput($db, "\@vars [attribute|clear|echo|info|prompt|raw|show]   display, clear or prompt for variables\n");
		cmdOutput($db, "\@\$ [raw|show]                                       display stored variables\n");
		cmdOutput($db, "\nEmbedded Commands available only in sourced scripts:\n\n");
		cmdOutput($db, "\@if <cond>, \@elsif <cond>, \@else, \@endif            if / elsif / else conditional operators\n");
		cmdOutput($db, "\@while <cond>, \@endloop                             while loop construct\n");
		cmdOutput($db, "\@loop, \@until <cond>                                loop until construct\n");
		cmdOutput($db, "\@my <\$variable> [= <init value>]                    declare a variable which will be available only during script execution\n");
		cmdOutput($db, "\@my <\$variable1> [, <\$variable2> ...]               declare multiple variables only available in script\n");
		cmdOutput($db, "\@my <\$pre_*>                                        declare variable name mask of variables only available in script\n");
		cmdOutput($db, "\@for <\$var> &<start>..<end>[:<step>], \@endfor       for loop construct using range input\n");
		cmdOutput($db, "\@for <\$var> &[']<comma-separated-list>, \@endfor     for loop construct using list input (set ' to expand ranges)\n");
		cmdOutput($db, "\@next [if <cond>]                                   jump to next value in a for loop construct\n");
		cmdOutput($db, "\@last [if <cond>]                                   break out of a while, until or for loop construct\n");
		cmdOutput($db, "\@exit [if <cond>]                                   break out of sourced script\n");
		cmdOutput($db, "\@stop [\"stop-message\"]                              break out of sourced script and halts sourcing mode\n");
		cmdOutput($db, "\nUser defined variables:\n\n");
		cmdOutput($db, "\$<name> = <value>                                   Simple flat variable\n");
		cmdOutput($db, "\$<name>[] = (<val1>; <val2>)                        List/Array type variable\n");
		cmdOutput($db, "\$<name>[<index>]                                    De-references as value held in array index (<index> is 1-based)\n");
		cmdOutput($db, "\$<name>[1]                                          De-references as value held in first array element\n");
		cmdOutput($db, "\$<name>[0] or \$<name>[\$#<name>]                     De-references as value held in last array element\n");
		cmdOutput($db, "\$<name>[]                                           De-references as list of array indexes if included in a command\n");
		cmdOutput($db, "\$<name>{} = (<key1> => <val1>; <key2> => <val2>)    Hash type variable\n");
		cmdOutput($db, "\$<name>{<key>}                                      De-references as value held in hash key element\n");
		cmdOutput($db, "\$<name>{}                                           De-references as list of hash keys if included in a command\n");
		cmdOutput($db, "\$'<name> or \$'<name>[<idx>] or \$'<name>{<key>}      De-references raw variable (without compacting into a numerical/port range)\n");
		cmdOutput($db, "\$#<name> or \$#<name>[<idx>] or \$#<name>{<key>}      De-references as number of comma separated values held in variable\n");
		cmdOutput($db, "\$#<name-of-list-or-hash>                            De-references as number of elements or keys held in array or hash\n");
		cmdOutput($db, "\nSpecial/Reserved variables:\n\n");
		cmdOutput($db, "\$_    (or simply '\$')                               Convenience variable; can be used for transient storage; never saved\n");
		cmdOutput($db, "\$%    (or simply '%')                               When tie-ed and switch name ends in a number, will be set to that number\n");
		cmdOutput($db, "\$\$                                                  Device system name\n");
		cmdOutput($db, "\$\@                                                  If preceding switch command generated an error, holds that error message\n");
		cmdOutput($db, "\$\>                                                  Holds last CLI prompt from device\n");
		cmdOutput($db, "\$<number>                                           When sourcing a script with \@source or \@run, holds optional arguments\n");
		cmdOutput($db, "\$*                                                  When sourcing a script with \@source or \@run, holds concatenated arguments\n");
		cmdOutput($db, "\$ALL                                                Returns all ports of connected device\n");
		cmdOutput($db, "\$1/ALL, \$2:ALL, etc..                               Returns all ports for given slot of connected device\n");
		cmdOutput($db, "\nSwitch CLI extensions:\n\n");
		cmdOutput($db, "<CLI command> -o[n]                                 while socket tied and sourcing, send command to socket with optional [n] delay\n");
		cmdOutput($db, "<CLI command> -y                                    automatic Yes at Y/N prompts\n");
		cmdOutput($db, "<CLI command> -n                                    automatic No at Y/N prompts\n");
		cmdOutput($db, "<CLI command>; <CLI command>; ...                   concatenate more commands on same line\n");
		cmdOutput($db, "<CLI command> @[<delay-in-seconds>]                 repeat the command with optional delay\n");
		cmdOutput($db, "<CLI command> &<start>..<end>[:<step>] ...          for loop; embed command with sprintf %s,%d,etc; 1 or more ranges/lists\n");
		cmdOutput($db, "<CLI command> &[']<comma-separated-list> ...        as above but with comma separated list of values; set ' to expand ranges\n");
		cmdOutput($db, "<CLI command> > <filename>  [-e]                    redirect output to file (over-write)\n");
		cmdOutput($db, "<CLI command> >> <filename> [-e]                    redirect output to file (append)\n");
		cmdOutput($db, "<CLI command> >|>> <.ext>   [-e]                    redirect output to file switchname.ext\n");
		cmdOutput($db, "                             -e                     when redirecting to file, echo to terminal\n");
		cmdOutput($db, "<CLI command> > \$variable  [-g]                     capture ports from output and assign to variable\n");
		cmdOutput($db, "<CLI command> >> \$variable [-g]                     capture ports from output and append to variable\n");
		cmdOutput($db, "                            -g                      capture multiple times per line of output\n");
		cmdOutput($db, "<CLI command> > \$variable '\%<n>'                    capture to variable value in output column <n>\n");
		cmdOutput($db, "<CLI command> >> \$variable '\%<n>'                   append to variable value in output column <n>\n");
		cmdOutput($db, "<CLI command> > \$var1,\$var2... '\%<n1>,\%<n2>...'     capture to multiple variables value in many output columns\n");
		cmdOutput($db, "<CLI command> >> \$var1,\$var2... '\%<n1>,\%<n2>...'    append to multiple variables value in many output columns\n");
		cmdOutput($db, "<CLI command> > \$var1 '\%<n1>,\%<n2>-[\%<n3>]'         capture many output column values to one variable\n");
		cmdOutput($db, "<CLI command> >> \$var1 '\%<n1>,\%<n2>-[\%<n3>]'        append many output column values to one variable\n");
		cmdOutput($db, "<CLI command> > \$variable 'regex'[i]                capture anything to variable; can use capturing () in regex\n");
		cmdOutput($db, "<CLI command> >> \$variable 'regex'[i]               capture anything to append to variable; can use () in regex\n");
		cmdOutput($db, "<CLI command> > \$var1,\$var2... 'regex'[ig]          capture to many variables; must use as many capturing () in regex\n");
		cmdOutput($db, "<CLI command> >> \$var1,\$var2... 'regex'[ig]         append to many variables; must use as many capturing () in regex\n");
		cmdOutput($db, "                                        i           make capture regex case insensitive; default is case sensitive\n");
		cmdOutput($db, "                                         g          capture multiple times per line of output\n");
		cmdOutput($db, "[<CLI command>] < <filename> [\$1, \$2, ...args]      execute command then source commands from file\n");
		cmdOutput($db, "[<CLI command>] < <.ext> [\$1, \$2, ...args]          execute command then source commands from file switchname.ext\n");
		cmdOutput($db, "<CLI command> ^ <match string> [-s]                 highlight matched string in output stream\n");
		cmdOutput($db, "<CLI command> | <grep string> [-s]                  simple line grep\n");
		cmdOutput($db, "<CLI command> ! <grep string> [-s]                  simple line negative grep\n");
		cmdOutput($db, "<CLI command> | <str1> | <str2> ... [-s]            multple grep strings\n");
		cmdOutput($db, "<CLI command> || <grep string> [-s]                 advanced grep\n");
		cmdOutput($db, "<CLI command> !! <grep string> [-s]                 advanced negative grep\n");
		cmdOutput($db, "                                -s                  do a case sensitive grep\n");
		cmdOutput($db, "<CLI command> || <str1> || <str2> ...               multiple advanced grep strings\n");
		cmdOutput($db, "<CLI command> [|| <str> ...] !                      trailing bang (!) removes all empty lines from output\n");
		cmdOutput($db, "<CLI command> //                                    execute CLI command and just send carriage return if it asks for input\n");
		cmdOutput($db, "<CLI command> [-hf] // <input>                      execute CLI command and feed it <input> if it asks for input\n");
		cmdOutput($db, "<CLI command> [-hf] // <input1> // <input2> ...     execute CLI command and feed it <input(s)> if it asks for them\n");
		cmdOutput($db, "               -h                                   cache input(s) against host device for future invocation of command\n");
		cmdOutput($db, "                -f                                  cache input(s) against family type for future invocation of command\n");
		cmdOutput($db, "<CLI command> -peercpu                              execute CLI command on peer CPU\n");
		cmdOutput($db, "<CLI command> -bothcpus                             execute CLI command on both connected CPU & peer CPU\n");
		cmdOutput($db, "show config [-b]                                    options to reformat non-ACLI config\n");
		cmdOutput($db, "show running [-bi[n]]                               options to reformat ACLI config\n");
		cmdOutput($db, "              -b                                    remove banner lines\n");
		cmdOutput($db, "               -i[n]                                add n (default=3) spaces of indentation to ACLI config\n");
		cmdOutput($db, "show running ||<port-list,range>                    grep on port config contexts\n");
		cmdOutput($db, "show running ||vlan [<vid-or-name-list>]            grep on vlan config contexts\n");
		cmdOutput($db, "show running ||mlt [<mltid-list>]                   grep on mlt config contexts\n");
		cmdOutput($db, "show running ||loopback [<CLIPid-list>]             grep on loopback config contexts\n");
		cmdOutput($db, "show running ||<ospf|rip|isis|bgp list>             grep on well known router config contexts\n");
		cmdOutput($db, "show running ||router <protocol-list>               grep on any router config context\n");
		cmdOutput($db, "show running ||vrf [<vrfname-list>]                 grep on router vrf config contexts\n");
		cmdOutput($db, "show running ||route-map [<routemap-list>]          grep on route-map config contexts\n");
		cmdOutput($db, "show running ||i-sid [<isid-list>]                  grep on i-sid config contexts\n");
		cmdOutput($db, "show running ||acl [<acl-id-list>]                  grep on filter acl ids\n");
		cmdOutput($db, "show running ||logical-intf [<intf-list>]           grep on ISIS logical interfaces\n");
		cmdOutput($db, "show running ||lintf|lisis|isl [<intf-list>]        same as above for logical-intf grep\n");
		cmdOutput($db, "show running ||mgmt [<port-list or id-list>]        grep on Mgmt interfaces\n");
		cmdOutput($db, "show running ||ssid [<ssid-name-list>]              grep on WLAN SSIDs\n");
		cmdOutput($db, "show running ||ovsdb                                grep on ovsdb config context\n");
		cmdOutput($db, "show running ||app                                  grep on application config context\n");
		cmdOutput($db, "show running ||dhcp-server [<subnet-list>]          grep on dhcp-server config context\n");
		cmdOutput($db, "show running ||dhcp-srv|dhcpsrv|dhcps [<snet-list>] same as above for dhcp-server grep\n");
		cmdOutput($db, "show log [-i]                                       unwrap logfile on: ERS stackables, ISW\n");
		$command = '';
	};
	#
	# $var command
	#
	$command eq '$$' && do {
		my $switchName = switchname($host_io);
		cmdOutput($db, sprintf "\$%-12s = %s\n", '$', defined $switchName ? $switchName : '<undefined>');
		$command = '';
	};
	$command eq '$@' && do {
		cmdOutput($db, sprintf "\$%-12s = %s\n", '@', defined $host_io->{LastCmdError} ? $host_io->{LastCmdError} : '<undefined>');
		$command = '';
	};
	$command eq '$>' && do {
		cmdOutput($db, sprintf "\$%-12s = %s\n", '>', defined $host_io->{Prompt} ? $host_io->{Prompt} : '<undefined>');
		$command = '';
	};
	$command =~ /^\$($VarAttrib)$/o && do { # Handles also ports structure followed by [indx] or, ISW case, {key}
		my ($vardisp, $var, $indx) = ($1, $2, $3);
		cmdOutput($db, sprintf "\$%-12s = %s\n", $vardisp, replaceAttribute($db, $var, $indx));
		$command = '';
	};
	$command =~ /^\$([#\'])?($VarSlotAll)$/o && do { # $ALL, $1/ALL, $2:ALL, etc...
		my $mode = $1 || '';
		my $var = $2;
		$mode = 'size' if $mode eq '#';
		$mode = 'raw' if $mode eq "'";
		cmdOutput($db, printVar($db, $var, $mode));
		$command = '';
	};
	$command =~ /^\$(?:($VarNormal)(?:\[\]|\{\})?)?$/o && do { # $var / $var[] / $var{}
		my $var = $1 || '_';
		cmdOutput($db, printVar($db, $var));
		$command = '';
	};
	$command =~ /^\$($VarScript)\[(\d+)\]$/o && do { # $var[idx]
		cmdOutput($db, printVar($db, $1, 0, $2));
		$command = '';
	};
	$command =~ /^\$($VarScript)\{($VarHashKey)\}$/o && do { # $var{key}
		cmdOutput($db, printVar($db, $1, 0, $2));
		$command = '';
	};
	$command =~ /^\$([#\'])($VarScript)\[(\d+)\]$/o && do { # $#var[idx]
		cmdOutput($db, printVar($db, $2, $1 eq '#' ? 'size':'raw', $3));
		$command = '';
	};
	$command =~ /^\$([#\'])($VarScript)\{($VarHashKey)\}$/o && do { # $#var{key}
		cmdOutput($db, printVar($db, $2, $1 eq '#' ? 'size':'raw', $3));
		$command = '';
	};
	$command =~ /^\$([#\'])($VarAny)?$/o && do { # $#var, $'var
		cmdOutput($db, printVar($db, $2 || '_', $1 eq '#' ? 'size':'raw'));
		$command = '';
	};
	#
	# @$ command
	#
	$command eq '@$' && do {
		$command = '@vars';	# Same as @vars command
	};
	$command eq '@$ show ?' && do {
		cmdMessage($db, "Syntax: \@\$ show <pattern>\n");
		$command = '';
	};
	$command eq '@$ raw ?' && do {
		cmdMessage($db, "Syntax: \@\$ raw <pattern>\n");
		$command = '';
	};
	$command =~ /^\@\$ (show|raw)/ && do {
		$command = "\@vars $1";	# Same as @vars command
	};
	#
	# @acli command
	#
	($command eq '@acli') && do {
		$socket_io->{SendBuffer} = ''; # Never send this command on other terminals!
		$script_io->{AcliControl} = 1;
		$host_io->{OutBuffer} = '';
		print $ACLI_Prompt;
		return '@acli';
	};
	#
	# @cat & @type command
	#
	$command =~ /^\@cat .*\?$/ && do {
		cmdMessage($db, "Syntax: \@cat <file on terminal>\n");
		$command = '';
	};
	$command =~ /^\@type .*\?$/ && do {
		cmdMessage($db, "Syntax: \@type <file on terminal>\n");
		$command = '';
	};
	$command =~ /^\@(?:cat|type)(?: (.+))/ && do {
		$command = $^O eq "MSWin32" ? 'type' : 'cat';
		$command .= " $1" if defined $1;
		cmdOutput($db, join('', qx/$command/));
		$command = '';
	};
	#
	# @else command
	#
	$command eq '@else' && do {
		if ($term_io->{Sourcing}) {
			my $block = $term_io->{BlockStack}->[$#{$term_io->{BlockStack}}];
			if (defined $block && $block->[0] eq '@if') { # We are in a @if block
				if ($block->[1] == 0) { # No match in previous @if or @elsif statements
					# Do nothing, keep sourcing
					$block->[1] = 2;   # Mark the block 2 = an else has been processed
				}
				elsif ($block->[1] == 1) { # There already was a match in a previous @if or @elsif block
					# Empty buffer, until we find final endif
					unless ( endofBlock($db, ['@endif']) ) {
						cmdMessage($db, "Error in script file; \@endif for \@else block not found\n");
						stopSourcing($db);
					}
				}
				else { # == 2; An else following another else..
					cmdMessage($db, "Error on line '$command' -> cannot have more than 1 \@else in same \@if block\n");
					stopSourcing($db);
				}
			}
			else { # We are not in an @if block
				cmdMessage($db, "Error on line '$command' -> no active \@if block\n");
				stopSourcing($db);
			}
		}
		else {
			cmdMessage($db, "\@if, \@elsif, \@else, \@endif can only be processed when sourcing commands\n");
		}
		$command = '';
	};
	#
	# @elsif command
	#
	$command =~ /^\@elsif .*\?$/ && do {
		cmdMessage($db, "Syntax: \@elsif <condition>\n");
		$command = '';
	};
	$command =~ /^\@elsif (.+)/ && do {
		if ($term_io->{Sourcing}) {
			my $block = $term_io->{BlockStack}->[$#{$term_io->{BlockStack}}];
			if (defined $block && $block->[0] eq '@if') { # We are in a @if block
				if ($block->[1] == 0) { # No match in previous @if or @elsif statements
					my $varError;
					my $condition = derefConditionSection($db, $1, \$varError);
					$host_io->{OutBuffer} .= echoPrompt($term_io, appendPrompt($host_io, $term_io), 'vars') . $varError. "\n" if $varError && !$term_io->{EchoOff};
					my ($result, $evalError) = evalCondition($condition); # This evaluates the resulting condition
					if (!defined $result) { # Condition Syntax error
						cmdMessage($db, "Error on line '$command' -> $evalError\n");
						stopSourcing($db);
					}
					elsif ($result) { # Condition True
						# Do nothing, keep sourcing
						$block->[1] = 1;
					}
					else { # Condition False
						# Empty buffer, until we find another else or endif
						unless ( endofBlock($db, ['@elsif', '@else', '@endif']) ) {
							cmdMessage($db, "Error in script file; end of '$command' block not found\n");
							stopSourcing($db);
						}
					}
				}
				else { # There already was a match in a previous @if or @elsif block
					# Empty buffer, until we find final endif
					unless ( endofBlock($db, ['@endif']) ) {
						cmdMessage($db, "Error in script file; \@endif for '$command' block not found\n");
						stopSourcing($db);
					}
				}
			}
			else { # We are not in an @if block
				cmdMessage($db, "Error on line '$command' -> no active \@if block\n");
				stopSourcing($db);
			}
		}
		else {
			cmdMessage($db, "\@if, \@elsif, \@else, \@endif can only be processed when sourcing commands\n");
		}
		$command = '';
	};
	#
	# @endfor command
	#
	$command eq '@endfor' && do {
		if ($term_io->{Sourcing}) {
			my $block = $term_io->{BlockStack}->[$#{$term_io->{BlockStack}}];
			if (defined $block && $block->[0] eq '@for') { # We are in a @for block
				if (@{$block->[2]}) { # If we still have values to set the for $variable
					appendInputBuffer($db, $block->[4], $block->[3], 1, 1);
				}
				else { # If not, pop the block and we come out
					pop(@{$term_io->{BlockStack}});
				}
			}
			else {
				cmdMessage($db, "Error on line '$command' -> no active \@for block\n");
				stopSourcing($db);
			}
		}
		else {
			cmdMessage($db, "\@for, \@endfor can only be processed when sourcing commands\n");
		}
		$command = '';
	};
	#
	# @endif command
	#
	$command eq '@endif' && do {
		if ($term_io->{Sourcing}) {
			my $block = $term_io->{BlockStack}->[$#{$term_io->{BlockStack}}];
			if (defined $block && $block->[0] eq '@if') { # We are in a @if block
				pop(@{$term_io->{BlockStack}});
			}
			else {
				cmdMessage($db, "Error on line '$command' -> no active \@if block\n");
				stopSourcing($db);
			}
		}
		else {
			cmdMessage($db, "\@if, \@elsif, \@else, \@endif can only be processed when sourcing commands\n");
		}
		$command = '';
	};
	#
	# @endloop command
	#
	$command eq '@endloop' && do {
		if ($term_io->{Sourcing}) {
			my $block = $term_io->{BlockStack}->[$#{$term_io->{BlockStack}}];
			if (defined $block && $block->[0] eq '@while') { # We are in a @while block
				if (@{$block->[1]}) { # While condition was true, we need to re-inject the loop commands
					appendInputBuffer($db, $block->[2], $block->[1], 1, 1);
				}
				# In either true or false case, we pop the block here
				pop(@{$term_io->{BlockStack}});
			}
			else {
				cmdMessage($db, "Error on line '$command' -> no active \@while block\n");
				stopSourcing($db);
			}
		}
		else {
			cmdMessage($db, "\@while, \@endloop can only be processed when sourcing commands\n");
		}
		$command = '';
	};
	#
	# @error command
	#
	$command eq '@error disable' && do {
		$host_io->{ErrorDetect} = 0;
		$command = '';
	};
	$command eq '@error enable' && do {
		$host_io->{ErrorDetect} = 1;
		$command = '';
	};
	$command eq '@error info' && do {
		if ($host_io->{ErrorDetect}) {
			cmdOutput($db, "Host error detection       : enable\n");
		}
		else {
			cmdOutput($db, "Host error detection       : disable\n");
		}
		cmdOutput($db, "Host error level detection : $host_io->{ErrorLevel}\n");
		$command = '';
	};
	$command eq '@error level error' && do {
		$host_io->{ErrorLevel} = 'error';
		$command = '';
	};
	$command eq '@error level warning' && do {
		$host_io->{ErrorLevel} = 'warning';
		$command = '';
	};
	#
	# @exit command
	#
	$command =~ /^\@exit if .*\?$/ && do {
		cmdMessage($db, "Syntax: \@exit if <condition>\n");
		$command = '';
	};
	$command =~ /^\@exit(?: if (.+))?/ && do {
		if ($term_io->{Sourcing}) {
			my ($result, $varError, $evalError);
			if ($1) {
				my $condition = derefConditionSection($db, $1, \$varError);
				$host_io->{OutBuffer} .= echoPrompt($term_io, appendPrompt($host_io, $term_io), 'vars') . $varError. "\n" if $varError && !$term_io->{EchoOff};
				($result, $evalError) = evalCondition($condition); # This evaluates the resulting condition
			}
			else {
				$result = 1;
			}
			if (!defined $result) { # Condition Syntax error
				cmdMessage($db, "Error on line '$command' -> $evalError\n");
				stopSourcing($db);
			}
			elsif ($result) { # Condition True
				endofBlock($db, []); # Empty the whole buffer
			}
			# Condition False, do nothing
		}
		else {
			cmdMessage($db, "\@exit can only be processed when sourcing commands\n");
		}
		$command = '';
	};
	#
	# @for command
	#
	$command eq '@for ?' && do {
		cmdMessage($db, "Syntax: \@for <\$variable> &<start>..<end>[:<step>]\n        \@for <\$variable> &<comma-separated-list>\n        \@for <\$variable> &<list \$variable[]>\n        \@for <\$variable> &<hash \$variable{}>\n");
		$command = '';
	};
	$command =~ /^\@for \$($VarUser)\s+&(\')?(.+)/o && do {
		if ($term_io->{Sourcing}) {
			my ($var, $raw, $range) = ($1, $2, $3);
			my $block = $term_io->{BlockStack}->[$#{$term_io->{BlockStack}}];
			if (defined $block && $block->[0] eq '@for' && $block->[1] eq $var) { # We are in our @for block
				setvar($db, $var => shift(@{$block->[2]}), script => 1);
			}
			else { # We open a new @for block
				my $varError;
				$range = derefVarSection($db, $range, 0, undef, \$varError);
				$host_io->{OutBuffer} .= echoPrompt($term_io, appendPrompt($host_io, $term_io), 'vars') . $varError. "\n" if $varError && !$term_io->{EchoOff};
				my @rangeList;
				if ($range =~ /^(\d+)\.\.(\d+)(?::(\d+))?$/) { # 0..10[:2] syntax
					my ($start, $end, $step) = ($1, $2, $3||1);
					my $cycles = abs($end - $start) / $step;
					if ($start == $end) {
						cmdMessage($db, "Error on line '$command' -> empty range\n");
						stopSourcing($db);
					}
					elsif ($cycles != int $cycles) {
						cmdMessage($db, "Error on line '$command' -> end of range cannot be hit with step provided\n");
						stopSourcing($db);
					}
					else { # We are good
						$step *= -1 if $start > $end; # Make step negative
						for (my $i = $start; $i <= $end; $i += $step) {
							push(@rangeList, $i);
						}
					}
				}
				else { # List syntax
					if ($raw) { # We only call generatePortList if in raw mode
						my $rawlist = generatePortList($host_io, $range); # we could have port ranges in there..
						$range = $rawlist if length $rawlist;
					}
					@rangeList = split(',', $range) if length $range && $range ne "''";
				}
				if (@rangeList) { # Cache all commands inside the loop block
					if (my $loopCmds = cacheBlock($db, ['@endfor']) ) {
						setvar($db, $var => shift(@rangeList), script => 1);
						push(@{$term_io->{BlockStack}}, ['@for', $var, \@rangeList, [$command, @$loopCmds], $term_io->{InputBuffQueue}->[0]]);
						# Need to cache $term_io->{InputBuffQueue}->[0] into BlockStack in case @endfor is last command in source/paste
					}
					else {
						cmdMessage($db, "Error in script file; end of '$command' block not found\n");
						stopSourcing($db);
					}
				}
				else { # Empty buffer, until we find final @endfor
					push(@{$term_io->{BlockStack}}, ['@for', $var, \@rangeList]); # Push an empty block; @endfor will pop it and continue
					unless ( endofBlock($db, ['@endfor'], 1) ) {
						cmdMessage($db, "Error in script file; \@endfor for \@for block not found\n");
						stopSourcing($db);
					}
				}
			}
		}
		else {
			cmdMessage($db, "\@for, \@endfor can only be processed when sourcing commands\n");
		}
		$command = '';
	};
	#
	# @history command
	#
	$command eq '@history' && do {
		$command = 'history recall';		# Same as history recall
	};
	$command eq '@history clear' && do {
		$command = 'history clear recall';	# Same as history clear recall
	};
	#
	# @if command
	#
	$command =~ /^\@if .*\?$/ && do {
		cmdMessage($db, "Syntax: \@if <condition>\n");
		$command = '';
	};
	$command =~ /^\@if (.+)/ && do {
		if ($term_io->{Sourcing}) {
			my $varError;
			my $condition = derefConditionSection($db, $1, \$varError);
			$host_io->{OutBuffer} .= echoPrompt($term_io, appendPrompt($host_io, $term_io), 'vars') . $varError. "\n" if $varError && !$term_io->{EchoOff};
			my ($result, $evalError) = evalCondition($condition); # This evaluates the resulting condition
			if (!defined $result) { # Condition Syntax error
				cmdMessage($db, "Error on line '$command' -> $evalError\n");
				stopSourcing($db);
			}
			elsif ($result) { # Condition True
				# Do nothing, keep sourcing
				push(@{$term_io->{BlockStack}}, ['@if', 1]);
			}
			else { # Condition False
				# Empty buffer, until we find an else or endif
				if ( endofBlock($db, ['@elsif', '@else', '@endif']) ) {
					push(@{$term_io->{BlockStack}}, ['@if', 0]);
				}
				else {
					cmdMessage($db, "Error in script file; end of '$command' block not found\n");
					stopSourcing($db);
				}
			}
		}
		else {
			cmdMessage($db, "\@if, \@elsif, \@else, \@endif can only be processed when sourcing commands\n");
		}
		$command = '';
	};
	#
	# @last command
	#
	$command =~ /^\@last if .*\?$/ && do {
		cmdMessage($db, "Syntax: \@last if <condition>\n");
		$command = '';
	};
	$command =~ /^\@last(?: if (.+))?/ && do {
		if ($term_io->{Sourcing}) {
			my ($result, $varError, $evalError);
			if ($1) {
				my $condition = derefConditionSection($db, $1, \$varError);
				$host_io->{OutBuffer} .= echoPrompt($term_io, appendPrompt($host_io, $term_io), 'vars') . $varError. "\n" if $varError && !$term_io->{EchoOff};
				($result, $evalError) = evalCondition($condition); # This evaluates the resulting condition
			}
			else {
				$result = 1;
			}
			if (!defined $result) { # Condition Syntax error
				cmdMessage($db, "Error on line '$command' -> $evalError\n");
				stopSourcing($db);
			}
			elsif ($result) { # Condition True
				my $block = $term_io->{BlockStack}->[$#{$term_io->{BlockStack}}];
				if (defined $block && nestedBlock($term_io->{BlockStack}, '@while') ) { # We are in a @while block
					# Empty buffer, until we find final @endloop
					unless ( endofBlock($db, ['@endloop'], 1) ) {
						cmdMessage($db, "Error in script file; \@endloop for \@while block not found\n");
						stopSourcing($db);
					}
					$block = $term_io->{BlockStack}->[$#{$term_io->{BlockStack}}];
					@{$block->[1]} = ();	# Make sure @endloop will pop block
				}
				elsif (defined $block && nestedBlock($term_io->{BlockStack}, '@loop') ) { # We are in a @loop block
					# Empty buffer, until we find final @until
					unless ( endofBlock($db, ['@until'], 1) ) {
						cmdMessage($db, "Error in script file; \@until for \@loop block not found\n");
						stopSourcing($db);
					}
					$block = $term_io->{BlockStack}->[$#{$term_io->{BlockStack}}];
					@{$block->[1]} = ();	# Make sure @until will pop block
				}
				elsif (defined $block && nestedBlock($term_io->{BlockStack}, '@for') ) { # We are in a @for block
					# Empty buffer, until we find final @endfor
					unless ( endofBlock($db, ['@endfor'], 1) ) {
						cmdMessage($db, "Error in script file; \@endfor for \@for block not found\n");
						stopSourcing($db);
					}
					$block = $term_io->{BlockStack}->[$#{$term_io->{BlockStack}}];
					@{$block->[2]} = ();	# Make sure @endfor will pop block
				}
				else {
					cmdMessage($db, "Error on line '$command' -> no active \@while block\n");
					stopSourcing($db);
				}
			}
			# Condition False, do nothing
		}
		else {
			cmdMessage($db, "\@last can only be processed when sourcing commands\n");
		}
		$command = '';
	};
	#
	# @launch command
	#
	$command =~ /^\@launch/ && $^O ne "MSWin32" && $^O ne "darwin" && do {
		cmdMessage($db, "\@launch command is only available on Microsoft Windows and Apple MAC OS\n");
		$command = '';
	};
	$command ne '@launch ?' && $command =~ /^\@launch(?: (.+))?/ && do {{
		my $arguments = $1 || '';
		my $execTemplate = readAcliSpawnFile($db);
		unless (defined $execTemplate) { # Come out if no spawn file
			stopSourcing($db);
			$command = '';
			last;
		}

		# We parse the arguments, because we want to catch syntax errors here (not after spawning)
		my @args = split(/ /, quoteCurlyMask($arguments, ' '));
		@args = map { quoteCurlyUnmask($_, ' ') } @args;	# Needs to re-assign, otherwise quoteCurlyUnmask won't work
		my (@opts, $logfileSeen, $relayHost, $relayHostSeen, $hostNameSeen, $tcpPortSeen, $windowTitle, $tabName, $hostName);
		$arguments = ''; # We re-build it
		$arguments .= " -d $::Debug" if $::Debug;	# Inherit debug level
		OPENARGS: while (my $arg = quotesRemove(shift @args)) {
			if ($arg =~ /\?$/) { # Request syntax
				$command = '@launch ?';
				last OPENARGS;
			}
			elsif ($arg =~ /^-(\w+)/) {
				@opts = split(//, $1);
				foreach my $opt (@opts) {
					if ($opt =~ /^[jnopx]$/) { # Single switches accepted
						$arguments .= " -$opt";
						next;
					}
					if ($opt eq 'c' && ($arg = quotesRemove(shift @args)) =~ /^(?:CRLF|CR)$/) {
						$arguments .= " -$opt $arg";
						next;
					}
					if ($opt =~ /^[eq]$/ && ($arg = quotesRemove(shift @args)) =~ /^\^[A-Za-z\[\\\]\^_]$/) {
						$arguments .= " -$opt $arg";
						next;
					}
					if ($opt eq 'k' && ($arg = quotesRemove(shift @args))) {
						if (verifySshKeys(my $hash, $arg)) {
							$arguments .= " -$opt \"$arg\"";
							next;
						}
						cmdMessage($db, "SSH keys not found\n");
					}
					if ($opt eq 'i' && length ($arg = quotesRemove(shift @args)) && -e $arg && -d $arg) {
						$arguments .= " -$opt \"$arg\"";
						next;
					}
					if ($opt =~ /^[ls]$/ && ($arg = quotesRemove(shift @args)) =~ /^\S+$/) {
						$arguments .= " -$opt $arg";
						next;
					}
					if ($opt eq 'm' && length ($arg = quotesRemove(shift @args))) {
						my ($ok, $err) = readSourceFile($db, $arg, \@RunFilePath);
						next if $ok;
						cmdMessage($db, "$err\n\n"); # otherwise
					}
					if ($opt eq 'r') {
						$arguments .= " -$opt";
						$relayHost = 1;
						next;
					}
					if ($opt eq 't' && length ($arg = quotesRemove(shift @args))) {
						$tabName = $arg;
						next;
					}
					if ($opt eq 'u' && length ($arg = quotesRemove(shift @args))) {
						$windowTitle = $arg;
						next;
					}
					if ($opt =~ /^[wy]$/ && length ($arg = quotesRemove(shift @args))) {
						$arguments .= " -$opt \"$arg\"";
						next;
					}
					if ($opt eq 'z' && ($arg = quotesRemove(shift @args)) =~ /^\d+\s*x\s*\d+$/) {
						$arguments .= " -$opt \"$arg\"";
						next;
					}
					# Unexpected switch or switch syntax
					$command = '@launch ?';
					last OPENARGS;
				}
			}
			elsif (!$relayHostSeen && $relayHost) {
				debugMsg(1,"Launch RelayHost = $arg\n");
				$arguments .= " $arg";
				$relayHostSeen = 1;
			}
			elsif (!$hostNameSeen) {
				debugMsg(1,"Launch HostName = $arg\n");
				if ($relayHostSeen) {
					my $relayHost = $arg;
					$relayHost =~ s/(\s+\-l\s+([^:\s]+))(?::(\S+))?/$1/;	# Remove embedded credentials from SSH -l switch
					$relayHost =~ s/([^:\s]+)(?::(\S+))?@(\S+)/$3/;		# Remove embedded credentials from IP
					unless ($relayHost =~ /^\S+$/				# Just an IP address / hostname
					     || $relayHost =~ /^\S+\s+-l\s+\S+\s+(\S+)\s*$/	# command -l user host
					     || $relayHost =~ /^\S+\s+(\S+)\s+-l\s+\S+\s*$/	# command host -l user
					     || $relayHost =~ /^\S+\s+(\S+)\s*$/) {		# command host
						cmdMessage($db, "Relay command not of form: <command> <target>\n\n");
						$command = '@launch ?';
						last OPENARGS;
					}
				     	$tabName = (defined $1 ? $1 : $arg) unless $tabName;
				     	$hostName = defined $1 ? $1 : $arg;
				}
				$arguments .= $relayHostSeen && $arg =~ /\s/ ? " \\\"$arg\\\"" : " $arg";
				$tabName = $arg unless defined $tabName;
				$hostName = $arg unless defined $hostName;
				$hostNameSeen = 1;
				next;
			}
			elsif (!$tcpPortSeen && $arg =~ /^\d+$/) {
				debugMsg(1,"Launch TcpPort = $arg\n");
				$arguments .= " $arg";
				$tcpPortSeen = 1;
				next;
			}
			elsif (!$logfileSeen) {
				debugMsg(1,"Launch LogFile = $arg\n");
				if ($arguments =~ /\s-j\s/) { # -j flag not allowed with logfile
					cmdMessage($db, "Cannot specify a capture-file with Auto-Logging enabled (-j switch)\n\n");
					$command = '@launch ?';
					last OPENARGS;
				}
				$arguments .= " \\\"$arg\\\"";
				$logfileSeen = 1;
			}
			else { # Unexpected argument
				$command = '@launch ?';
				last OPENARGS;
			}
		} # OPENARGS
		if (!defined $hostName) { # Check for invalid switches
			$command = '@launch ?' if $arguments =~ /\s-[lr]\s/;
		}
		elsif ($hostName =~/^serial:/) {
			$command = '@launch ?' if $arguments =~ /\s-[klyz]\s/;
		}
		elsif ($hostName =~/^(?:annex|trmsrv):/) {
			$command = '@launch ?' if $arguments =~ /\s-[kl]\s/;
		}
		elsif ($hostName =~/^pseudo:/) {
			$command = '@launch ?' if $arguments =~ /\s-[cijklnprxyz]\s/;
		}
		if ($command eq '@launch ?') { # If error..
			stopSourcing($db);
		}
		else { # If no error, we spawn the new terminal
			$arguments =~ s/^\s+//; # Remove preceding spaces
			unless( launchNewTerm($execTemplate, $arguments, $windowTitle, $tabName, File::Spec->rel2abs(cwd)) ) {
				cmdMessage($db, "Failed to launch new ACLI terminal");
			}
			$command = '';
		}
	}};
	$command eq '@launch ?' && do { # Must come after @launch command with args
		cmdMessage($db, "Syntax: \@launch [-ceijknopqstwxyz]\n");
		cmdMessage($db, "    or: \@launch [-ceijklmnopqrstwxyz] <host/IP> [<tcp-port>] [<capture-file>]\n");
		cmdMessage($db, "    or: \@launch [-ceijmnopqrstwx]     serial:[<com-port>[@<baudrate>]] [<capture-file>]\n");
		cmdMessage($db, "    or: \@launch [-ceijmnopqrstwxyz]   trmsrv:[<device-name> | <host/IP>#<port>] [<capture-file>]\n");
		cmdMessage($db, "    or: \@launch [-emoqstw]            pseudo[1-99]:[<prompt>] [<capture-file>]\n");
		cmdMessage($db, "    or: \@launch -r <host/IP or serial or trmsrv syntaxes above> <\"relay cmd\" | IP> [<capture-file>]\n\n");
		cmdMessage($db, " <host/IP>        : Hostname or IP address to connect to; can use <username>:<password>@<host/IP>\n");
		cmdMessage($db, " <tcp-port>       : TCP port number to use\n");
		cmdMessage($db, " <com-port>       : Serial Port name (COM1, /dev/ttyS0, etc..) to use\n");
		cmdMessage($db, " <capture-file>   : Optional output capture file of CLI session\n");
		cmdMessage($db, " -c <CR|CRLF>     : For newline use CR+LF (default) or just CR\n");
		cmdMessage($db, " -e escape_char   : CTRL+<char> for escape sequence; default is \"$CtrlEscapePrn\"\n");
		cmdMessage($db, " -i <log-dir>     : Path to use when logging to file\n");
		cmdMessage($db, " -j               : Automatically start logging to file (<host/IP> used as filename)\n");
		cmdMessage($db, " -k <key_file>    : SSH private key to load; public key implied <key_file>.pub\n");
		cmdMessage($db, " -l user[:<pwd>]  : SSH username[& password] to use; this option produces an SSH connection\n");
		cmdMessage($db, " -m <script>      : Once connected execute script (if no path included will use \@run search paths)\n");
		cmdMessage($db, " -n               : Do not try and auto-detect & interact with device\n");
		cmdMessage($db, " -o               : Overwrite <capture-file> instead of appending to it\n");
		cmdMessage($db, " -p               : Use factory default credentials to login automatically\n");
		cmdMessage($db, " -q quit_char     : CTRL+<char> for quit sequence; default is \"$CtrlQuitPrn\"\n");
		cmdMessage($db, " -r               : Connect via Relay; append telnet/ssh command to use on Relay to reach host\n");
		cmdMessage($db, " -s <sockets>     : List of socket names for terminal to listen on\n");
		cmdMessage($db, " -t <tab-name>    : ACLI Tab name to use on launched terminal instead of host/IP\n");
		cmdMessage($db, " -u <window-title>: Sets the containing window title into which launched terminal will be opened\n");
		cmdMessage($db, " -w <work-dir>    : Run on provided working directory\n");
		cmdMessage($db, " -x               : If connection lost, exit instead of offering to reconnect\n");
		cmdMessage($db, " -y <term-type>   : Negotiate terminal type (e.g. vt100)\n");
		cmdMessage($db, " -z <w>x<h>       : Negotiate window size (width x height)\n");
		$command = '';
	};
	#
	# @loop command
	#
	$command eq '@loop' && do {
		if ($term_io->{Sourcing}) {
			# Cache all commands inside the loop block
			if (my $loopCmds = cacheBlock($db, ['@until']) ) {
				push(@{$term_io->{BlockStack}}, ['@loop', [$command, @$loopCmds], $term_io->{InputBuffQueue}->[0]]);
				# Need to cache $term_io->{InputBuffQueue}->[0] into BlockStack in case @until is last command in source/paste
			}
			else {
				cmdMessage($db, "Error in script file; end of '$command' block not found\n");
				stopSourcing($db);
			}
		}
		else {
			cmdMessage($db, "\@loop, \@until can only be processed when sourcing commands\n");
		}
		$command = '';
	};
	#
	# @my command
	#
	$command =~ /^\@my .*\?$/ && do {
		cmdMessage($db, "Syntax: \@my <\$variable> [ = <init value> ]\n");
		cmdMessage($db, "Syntax: \@my <\$variable1> [, <\$variable1> ...]\n");
		$command = '';
	};
	$command =~ /^\@my (\$$VarScript\*?(?:\[\]|\{\})?(?:\s*,\s*\$$VarScript\*?(?:\[\]|\{\})?)*)$/ && do {
		if ($term_io->{Sourcing}) {
			my $scope = $term_io->{DictSourcing} ? $dictscope : $varscope;
			my @varList = map {s/^\$//r} split(/\s*,\s*/, $1);
			foreach my $var (@varList) {
				$var =~ s/^\$//;
				$var =~ s/(\[\]|\{\})$//;
				if ($var =~ s/\*$/.*/) {
					push(@{$scope->{wildcards}}, $var);
					debugMsg(1,"\@my setting var wildcard = ", \$var, "\n");
				}
				else {
					$scope->{varnames}->{$var} = 1;
					debugMsg(1,"\@my setting var name = ", \$var, "\n");
				}
			}
		}
		else {
			cmdMessage($db, "\@my can only be processed when sourcing commands\n");
		}
		$command = '';
	};
	$command =~ /^\@my \$($VarScript)(\[\]|\{\})?(?:\s*=\s*(\'[^\']*\'|\"[^\"]*\"|.+))?/ && do {
		if ($term_io->{Sourcing}) {
			my $scope = $term_io->{DictSourcing} ? $dictscope : $varscope;
			$scope->{varnames}->{$1} = 1;
			debugMsg(1,"\@my setting var name = ", \$1, "\n");
			my $type = $2 || '';
			if ($type eq '[]') {
				assignVar($db, 'list', $1, '=', $3, undef);
			}
			elsif ($type eq '{}') {
				assignVar($db, 'hash', $1, '=', $3, undef);
			}
			else {
				assignVar($db, '', $1, '=', $3, undef);
			}
		}
		else {
			cmdMessage($db, "\@my can only be processed when sourcing commands\n");
		}
		$command = '';
	};
	#
	# @next command
	#
	$command =~ /^\@next if .*\?$/ && do {
		cmdMessage($db, "Syntax: \@next if <condition>\n");
		$command = '';
	};
	$command =~ /^\@next(?: if (.+))?/ && do {
		if ($term_io->{Sourcing}) {
			my ($result, $varError, $evalError);
			if ($1) {
				my $condition = derefConditionSection($db, $1, \$varError);
				$host_io->{OutBuffer} .= echoPrompt($term_io, appendPrompt($host_io, $term_io), 'vars') . $varError. "\n" if $varError && !$term_io->{EchoOff};
				($result, $evalError) = evalCondition($condition); # This evaluates the resulting condition
			}
			else {
				$result = 1;
			}
			if (!defined $result) { # Condition Syntax error
				cmdMessage($db, "Error on line '$command' -> $evalError\n");
				stopSourcing($db);
			}
			elsif ($result) { # Condition True
				my $block = $term_io->{BlockStack}->[$#{$term_io->{BlockStack}}];
				if (defined $block && nestedBlock($term_io->{BlockStack}, '@for') ) { # We are in a @for block
					# Empty buffer, until we find final @endfor
					unless ( endofBlock($db, ['@endfor'], 1) ) {
						cmdMessage($db, "Error in script file; \@endfor for \@for block not found\n");
						stopSourcing($db);
					}
				}
				else {
					cmdMessage($db, "Error on line '$command' -> no active \@for block\n");
					stopSourcing($db);
				}
			}
			# Condition False, do nothing
		}
		else {
			cmdMessage($db, "\@next can only be processed when sourcing commands\n");
		}
		$command = '';
	};
	#
	# @peerCP command
	#
	$command eq '@peercp' && do {
		$command = 'peercp info';	# Same as peercp info
	};
	#
	# @print command
	#
	$command =~ /^\@print .*\?$/ && do {
		cmdMessage($db, "Syntax: \@print [\"text\"]\n");
		$command = '';
	};
	$command =~ /^\@print(?: (.+))?$/ && do {
		my $text = defined $1 ? $1 : '';
		if ($text =~ /^(?:\'[^\']*\'|\"[^\"]*\")$/) { # Text is quoted
			$text = quotesRemove($text) || '';	# Remove quotes
			$text =~ s/\\n/\n/g;			# Process newlines "\n"
		}
		cmdMessage($db, "$text\n"); # This will print even if echo output is off
		$command = '';
	};
	#
	# @printf command
	#
	$command =~ /^\@printf .*\?$/ && do {
		cmdMessage($db, "Syntax: \@printf \'<single-quoted-formatting>\', <value1>[,<value2>..]\n");
		$command = '';
	};
	$command =~ /^\@printf ('[^\']+'|"[^\"]+")\s*,\s*(.*)/ && do {
		my ($fmtString, $fmtValueList) = (quotesRemove($1), $2);
		$fmtString =~ s/\\n/\n/g;
		my @fmtValues = map {s/^\s+//; s/\s+$//; quotesRemove($_)} split(/,\s+/, $fmtValueList); # split on ',\s' as ',' alone might be in variables
		my $output;
		eval {
			local $SIG{__WARN__} = sub { die shift }; # Turn every warning into an exception
			$output = sprintf($fmtString, @fmtValues);
		};
		if ($@) {
			(my $message = $@) =~s/;.*$//;
			$message =~ s/ at .+ line .+$//; # Delete file & line number info
			$message =~ s/sprintf/\@printf/; # Show @printf in error message
			cmdMessage($db, $message);
			stopSourcing($db);
		}
		else {
			cmdMessage($db, sprintf($fmtString, @fmtValues)); # This will print even if echo output is off
		}
		$command = '';
	};
	#
	# @pseudo command
	#
	$command =~ /^\@pseudo load (.+)/ && do {
		if ($host_io->{Connected}) {
			cmdMessage($db, "Cannot enable Pseudo Terminal if connected to a device\n");
		}
		else {
			enablePseudoTerm($db, $1);
		}
		$command = '';
	};
	#
	# @put command
	#
	$command =~ /^\@put .*\?$/ && do {
		cmdMessage($db, "Syntax: \@put [\"text\"]\n");
		$command = '';
	};
	$command =~ /^\@put(?: (.+))?$/ && do {
		my $text = defined $1 ? $1 : '';
		if ($text =~ /^(?:\'[^\']*\'|\"[^\"]*\")$/) { # Text is quoted
			$text = quotesRemove($text) || '';	# Remove quotes
			$text =~ s/\\n/\n/g;			# Process newlines "\n"
		}
		cmdMessage($db, "$text"); # This will print even if echo output is off (no trailing \n)
		$command = '';
	};
	#
	# @quit command
	#
	$command eq '@quit' && do {
		quit(0, undef, $db);
		$command = '';
	};
	#
	# @rediscover command
	#
	$command eq '@rediscover' && do {
		return '@rediscover' unless $term_io->{PseudoTerm};
		$command = '';
	};
	#
	# @resume command
	#
	$command eq '@resume' && do {
		if ($term_io->{SaveBuffQueue}) {
			releaseInputBuffer($term_io);
			$term_io->{SourceNoHist} = $term_io->{InputBuffQueue}->[0] eq 'paste' ? 0 : 1;	# Disable history, except for paste buffer
		}
		else {
			cmdMessage($db, "Resume buffer is empty\n");
		}
		$command = '';
	};
	$command eq '@resume buffer' && do {
		if ($term_io->{SaveBuffQueue}) {
			foreach my $buff (@{$term_io->{SaveBuffQueue}}) {
				last unless $buff;	# '' is last
				if ($buff eq 'RepeatCmd') {
					cmdOutput($db, "------ Repeated command (@)------\n");
					cmdOutput($db, $term_io->{RepeatCmd});
					cmdOutput($db, ';') if $term_io->{RepeatCmd} =~ /[^\\];/;
					cmdOutput($db, ' @' . $term_io->{RepeatDelay} . "\n");
				}
				elsif ($buff eq 'SleepCmd') {
					cmdOutput($db, "------ \@sleep command ------\n");
					cmdOutput($db, '@sleep ' . $term_io->{SleepDelay} . "\n");
				}
				elsif ($buff eq 'ForLoopCmd') {
					cmdOutput($db, "------ For-Loop command (&)------\n");
					cmdOutput($db, $term_io->{ForLoopCmd});
					cmdOutput($db, ';') if $term_io->{ForLoopCmd} =~ /[^\\];/;
					cmdOutput($db, ' &');
					my ($i, $l) = (0, 0); # Indexes to traverse ranges ($i) and lists ($l)
					foreach my $type (@{$term_io->{ForLoopVarType}}) { # traverse vars types
						if ($type) { # List type
							cmdOutput($db, join(',', @{$term_io->{ForLoopVarList}[$l++]}) . ' ');
						}
						else { # Range type
							cmdOutput($db, ($term_io->{ForLoopVar}[$i] + $term_io->{ForLoopVarStep}[$i]));
							cmdOutput($db, '..' . ($term_io->{ForLoopVar}[$i] + $term_io->{ForLoopVarStep}[$i] * $term_io->{ForLoopCycles})) if $term_io->{ForLoopCycles} > 1;
							cmdOutput($db, ':' . $term_io->{ForLoopVarStep}[$i]) if $term_io->{ForLoopCycles} > 1 && $term_io->{ForLoopVarStep}[$i] != 1;
							cmdOutput($db, ' ');
							$i++;
						}
					}
					cmdOutput($db, "\n");
				}
				else {
					cmdOutput($db, "------ STDIN pasted buffer ------\n") if $buff eq 'paste';
					cmdOutput($db, "------ File sourced buffer ------\n") if $buff eq 'source';
					cmdOutput($db, "------ Expanded cmd buffer ------\n") if $buff eq 'semiclnfrg';
		 			foreach my $cmd (@{$term_io->{InputBuffer}->{$buff}}) {
		 				next if $cmd =~ /^\x00/; # Hide these markers
						cmdOutput($db, "$cmd\n");
					}
					cmdOutput($db, "$term_io->{SaveCharBuffer}\n") if length $term_io->{SaveCharBuffer};
				}
			}
			cmdOutput($db, "------ End of resume buffer -----\n");
		}
		else {
			cmdMessage($db, "Resume buffer is empty\n");
		}
		$command = '';
	};
	#
	# @run command
	#
	$command eq '@run ?' && do { # If user enters @run script ?; we need the ? to be fed to script
		cmdMessage($db, "Syntax: \@run <runscript> [\$1, \$2, ...args]\n        \@run list|path\n");
		$command = '';
	};
	$command eq '@run list' && do {
		my %list;
		foreach my $path (@RunFilePath) {
			my $globrun = $path . ($^O eq "MSWin32" ? '\\' : '/') . '*.run';
			foreach my $file (glob $globrun) {
				my $basefile = File::Basename::basename($file);
				$list{$basefile} = $path unless grep($_ eq $basefile, keys %list);
			}
		}
		if (%list) { # We found some run scripts
			cmdMessage($db, "Available Run Scripts:\n\n");
			cmdMessage($db, "   Name         Origin    Version  Description\n");
			cmdMessage($db, "   ----         ------    -------  -----------\n");
			foreach my $file (sort { $a cmp $b } keys %list) {
				(my $basefile = $file) =~ s/\.run$//;
				cmdOutput($db, sprintf "   %-12s %s ", $basefile, $list{$file} eq File::Spec->canonpath($ScriptDir) ? 'package' : 'private');
				my $runfile = $list{$file} . ($^O eq "MSWin32" ? '\\' : '/') . $file;
				if ( open(RUNFILE, '<', $runfile) ) {
					my ($version, $description);
					while (<RUNFILE>) {
						if (!defined $version && /^#\s*Version\s*=\s*(\d+\.\d+)\s*$/) {
							$version = $1;
						}
						elsif (!defined $description && /^#\s*(.+)$/) {
							$description = $1;
						}
						last if length $version && length $description;
					}
					close RUNFILE;
					$description = File::Spec->rel2abs($runfile) unless length $description;
					if (length $version) {
						cmdOutput($db, sprintf "%9s  %s\n", $version, $description);
					}
					else {
						cmdOutput($db, sprintf "%9s  %s\n", "n/a", $description);
					}
				}
				else {
					cmdOutput($db, "Error, unable to read this file!\n");
				}
			}
		}
		else {
			cmdMessage($db, "No run scripts found\n");
		}
		$command = '';
	};
	$command eq '@run path' && do {
		cmdOutput($db, "Paths for Run Scripts:\n\n");
		cmdOutput($db, "   Origin    Path\n");
		cmdOutput($db, "   ------    ----\n");
		foreach my $path (@RunFilePath) {
			cmdOutput($db, sprintf "   %s   %s\n", $path eq File::Spec->canonpath($ScriptDir) ? 'package' : 'private', File::Spec->rel2abs($path));
		}
		$command = '';
	};
	$command =~ /^\@run (.+)/ && do { # Needs to come last so as not to match @run list|path
		$host_io->{SyntaxError} = 0;	# If argument was '?', stopSourcing() will have been called earlier in this sub
		my ($ok, $err) = readSourceFile($db, $1, \@RunFilePath);
		cmdMessage($db, "$err\n\n") unless $ok;
		cmdOutput($db, $host_io->{Prompt});
		return '@run';
	};
	#
	# @sleep command
	#
	$command eq '@sleep ?' && do {
		cmdMessage($db, "Syntax: \@sleep <time-in-seconds>\n");
		$command = '';
	};
	$command =~ /^\@sleep (\d+)/ && do {
		$term_io->{SleepDelay} = $1;
		$term_io->{SleepUpTime} = time + $term_io->{SleepDelay};
		appendInputBuffer($db, 'SleepCmd');
		return '@sleep';
	};
	#
	# @socket command
	#
	$command eq '@socket ping ?' && do {
		cmdMessage($db, "Syntax: \@socket ping [<socket name>]\n");
		$command = '';
	};
	$command eq '@socket ping' && do {
		$socket_io->{SendBuffer} = ''; # Never send this command on other terminals!
		if (!$term_io->{SocketEnable}) {
			cmdMessage($db, "Socket functionality is disabled\n");
		}
		elsif (!$socket_io->{Tie}) {
			cmdMessage($db, "Not tied to any socket\n");
		}
		else {
			# Case where echo mode is disabled, we need to enable it for ping responses
			$socket_io->{ResetEchoMode} = $socket_io->{TieEchoMode} = 1 if $socket_io->{TieEchoMode} == 0;
			# Call tieSocketEcho() only if the echo mode was none
			if ($socket_io->{ResetEchoMode} && !tieSocketEcho($socket_io) ) { # Set up the Echo mode RX socket if necessary
				cmdMessage($db, "Unable to create echo mode socket\n");
				$socket_io->{TieEchoMode} = 0 if $socket_io->{ResetEchoMode};
			}
			else {
				socketBufferPack($socket_io, '', 6); # Send a ping
				$socket_io->{GrepRecycle} = $socket_io->{SummaryCount} = 1;
			}
		}
		$command = '';
	};
	$command =~ /^\@socket ping (\S+)/ && do {
		my $sockName = $1;
		$socket_io->{SendBuffer} = ''; # Never send this command on other terminals!
		if (!$term_io->{SocketEnable}) {
			cmdMessage($db, "Socket functionality is disabled\n");
		}
		else {
			if ($socket_io->{CachedTieName} = $socket_io->{Tie}) {
				untieSocket($socket_io, 1);
			}
			if ( tieSocket($socket_io, $sockName, 1) ) { # Success
				# Case where echo mode is disabled, we need to enable it for ping responses
				$socket_io->{ResetEchoMode} = $socket_io->{TieEchoMode} = 1 if $socket_io->{TieEchoMode} == 0;
				# Call tieSocketEcho() only if we were not already tied before OR the echo mode was none
				if ((!$socket_io->{CachedTieName} || $socket_io->{ResetEchoMode}) && !tieSocketEcho($socket_io) ) { # Set up the Echo mode RX socket if necessary
					cmdMessage($db, "Unable to create echo mode socket\n");
					$socket_io->{TieEchoMode} = 0 if $socket_io->{ResetEchoMode};
					tieSocket($socket_io, $socket_io->{CachedTieName}, 1) if $socket_io->{CachedTieName}; # Re-tie to previous
					$socket_io->{CachedTieName} = undef;
				}
				else {
					socketBufferPack($socket_io, '', 6); # Send a ping
					$socket_io->{UntieOnDone} = 1;
					$socket_io->{SocketWait} = 1;
					$socket_io->{GrepRecycle} = $socket_io->{SummaryCount} = 1;
				}
			}
			else { # Fail
				cmdMessage($db, "Unable to create socket $sockName for ping\n");
				tieSocket($socket_io, $socket_io->{CachedTieName}, 1) if $socket_io->{CachedTieName}; # Re-tie to previous
				$socket_io->{CachedTieName} = undef;
			}
		}
		$command = '';
	};
	$command =~ /^\@socket send .*\?$/ && do {
		cmdMessage($db, "Syntax: \@socket send <socket name> [<wait-time-secs>] <command>\n");
		$command = '';
	};
	$command =~ /^\@socket send (\S+)(?:\s+(\d+))?(?:\s+(.+))?/ && do {
		my ($sockName, $waitTime) = ($1, $2);
		my $sendCmd = quotesRemove($3) || '';
		$socket_io->{SendBuffer} = ''; # Never send this command on other terminals!
		if (!$term_io->{SocketEnable}) {
			cmdMessage($db, "Socket functionality is disabled\n");
		}
		else {
			if ($socket_io->{CachedTieName} = $socket_io->{Tie}) {
				untieSocket($socket_io, 1);
			}
			if ( tieSocket($socket_io, $sockName, 1) ) { # Success
				# Call tieSocketEcho() only if we were not already tied before
				if (!$socket_io->{CachedTieName} && !tieSocketEcho($socket_io) ) { # Set up the Echo mode RX socket if necessary
					cmdMessage($db, "Unable to create echo mode socket\n");
					stopSourcing($db);
				}
				socketBufferPack($socket_io, $sendCmd."\n", length $sendCmd ? 3 : 1); # Send the command
				$socket_io->{UntieOnDone} = 1;
				$socket_io->{SocketWait} = 1;
				$socket_io->{TimerOverride} = $waitTime if length $waitTime;
				$socket_io->{GrepRecycle} = 1;
				$host_io->{LastCmdError} = $host_io->{LastCmdErrorRaw} = undef; # Clear $@ variable
			}
			else { # Fail
				cmdMessage($db, "Unable to create socket $sockName for send\n");
				tieSocket($socket_io, $socket_io->{CachedTieName}, 1) if $socket_io->{CachedTieName}; # Re-tie to previous
				$socket_io->{CachedTieName} = undef;
				stopSourcing($db);
			}
		}
		$command = '';
	};
	#
	# @source command
	#
	$command =~ /^\@source .*\?$/ && do {
		cmdMessage($db, "Syntax: \@source <filename> [\$1, \$2, ...args]\n");
		$command = '';
	};
	$command =~ /^\@source (.+)/ && do {
		my ($ok, $err) = readSourceFile($db, $1);
		cmdMessage($db, "$err\n\n") unless $ok;
		$command = '';
	};
	#
	# @ssh command
	#
	$command eq '@ssh device-keys delete ?' && do {
		cmdMessage($db, "Syntax: \@ssh device-keys delete <switch-ssh-file> [<key index>]\n\n");
		cmdMessage($db, " - Specify the SSH switch file as shown by '\@ssh device-keys list' command\n");
		cmdMessage($db, " - If an index is not provided, the switch SSH file will be deleted\n");
		cmdMessage($db, " - If an index is provided, only the key will be deleted from within the SSH file\n");
		$command = '';
	};
	$command =~ /^\@ssh device-keys delete (\S+)(?: (\d+))?/ && do {
		my ($file, $index) = ($1, $2);
		if ($host_io->{Connected}) {
			if ($host_io->{Type} eq 'PassportERS') {
				if ($index) {
					cmdMessage($db, "Deleting SSH Public key index $index in file .ssh/$file ");
				}
				else {
					cmdMessage($db, "Deleting SSH Public key file .ssh/$file ");
				}
				my $sshkeys = readDeviceSshKeys($db);
				if (defined $sshkeys) { # No error; ssh files may have been found or not
					if (defined $sshkeys->{$file}) { # File exists
						my $retVal;
						if ($index) {
							if (defined $sshkeys->{$file}->{keys}->[$index - 1]) { # Key index within file exists
								$retVal = deviceSshKeyDelete($db, $file, $sshkeys, $index);
								cmdMessage($db, "Failed to delete key") unless $retVal;
							}
							else {
								cmdMessage($db, "done!\n\nThere is no key with index $index within SSH file .ssh/$file\n");
							}
						}
						else {
							$retVal = deviceDeleteSshFile($db, $file);
							cmdMessage($db, "Failed to delete SSH keys file") unless $retVal;
						}
						cmdMessage($db, "done!\n") if $retVal;
					}
					else {
						cmdMessage($db, "done!\n\nSSH Public key file .ssh/$file does not exist on device\n");
					}
				}
				else {
					cmdMessage($db, "Unable to read ssh files on device\n");
				}
			}
			else {
				cmdMessage($db, "Can only manage SSH keys on PassportERS / VOSS-VSP devices\n");
			}
		}
		else {
			cmdMessage($db, "No device connected\n");
		}
		$command = '';
	};
	$command =~ /^\@ssh device-keys install (.+)/ && do {
		my $level = $1;
		my $publicKey;
		if ($host_io->{SshPublicKey} && ( $publicKey = readSshPublicKeyFile($host_io->{SshPublicKey}) ) ) {
			if ($host_io->{Connected}) {
				if ($host_io->{Type} eq 'PassportERS') {
					cmdMessage($db, "Installing SSH Public key on switch ");
					my $sshkeys = readDeviceSshKeys($db);
					if (defined $sshkeys) { # No error; ssh files may have been found or not
						my ($retVal, $index, $infile);
						my (undef, $type, undef, undef, $myPubKey) = @{inspectSshPublicKeys($publicKey)->[0]};
						if (%$sshkeys) { # If ssh files found...
							foreach my $sshfile (keys %$sshkeys) { # ... make sure our key not already there
								next if $sshkeys->{$sshfile}->{level} ne $level;
								for my $i (0 .. $#{$sshkeys->{$sshfile}->{keys}}) {
									my $key = $sshkeys->{$sshfile}->{keys}->[$i];
									if ($myPubKey eq $key->[4]) {
										$index = $i + 1;
										$infile = $sshfile;
									}
								}
							}
						}
						if ($index) {
							if ($index == 1) {
								cmdMessage($db, "done!\n\nKey was already installed for access level $level\n");
							}
							else { # The key is there, but not at the top; so we delete it first
								$retVal = deviceSshKeyDelete($db, $infile, $sshkeys, $index);
								if ($retVal) {
									$index = undef; # Fall through below
								}
								else {
									cmdMessage($db, "Failed to delete key which was present but not 1st in file");
								}
							}
						}
						unless ($index) {
							my ($file, $go);
							if ($type eq 'ssh-rsa') { # RSA key, add to file rsa_key_<level>
								$file = 'rsa_key_' . $level;
								$go = 1;
							}
							elsif ($type eq 'ssh-dss') { # DSA key...
								my $mocana = determineSshStack($db);
								if ($mocana) { # New VOSS Mocana SSH stack
									$file = 'dsa_key_' . $level;
									$go = 1;
									if (defined $sshkeys->{$file}->{keys}) { # We have at least 1 entry
										if ($sshkeys->{$file}->{keys}->[0]->[0] eq 'openssh') { # Format of 1st entry is openssh
											cmdMessage($db, "error!\nPublic key file .ssh/$file exists and has entries in openssh format\nCan only add keys in IETF format\n");
											$go = undef;
										}
									}
								}
								elsif (defined $mocana) { # Old 8600 SSH stack
									$file = 'dsa_key_' . $level . '_ietf';
									$go = 1;
								}
								# Else ($mocana undef) fall through below as $go is undef
							}
							else {
								cmdMessage($db, "error\n\nInvalid local public key type '$type'");
							}
							if ($go) {
								$retVal = deviceAddSshKey($db, $file, 'ietf', $publicKey);
								if ($retVal) {
									cmdMessage($db, "done!\n");
								}
								else {
									cmdMessage($db, "Failed to add SSH key to file .ssh/$file");
								}
							}
						}
					}
					else {
						cmdMessage($db, "Unable to read ssh files on device\n");
					}
				}
				else {
					cmdMessage($db, "Can only read SSH keys on PassportERS / VOSS-VSP devices\n");
				}
			}
			else {
				cmdMessage($db, "No device connected\n");
			}
		}
		else {
			cmdMessage($db, "No SSH keys loaded\n");
		}
		$command = '';
	};
	$command eq '@ssh device-keys list' && do {
		if ($host_io->{Connected}) {
			if ($host_io->{Type} eq 'PassportERS') {
				cmdMessage($db, "Retrieving SSH Public keys on switch ");
				my $sshkeys = readDeviceSshKeys($db);
				if (defined $sshkeys) { # No error; ssh files may have been found or not
					cmdMessage($db, "done!\n\n");
					if (%$sshkeys) {
						cmdOutput($db, sprintf "%-16s  %3s  %-8s  %-7s  %-7s  %4s  %-23s  %s\n", 'File', 'Idx', 'Acc Levl', 'Format', 'Type', 'Bits', 'Fingerprint', 'Comments');
						cmdOutput($db, sprintf "%-16s  %3s  %-8s  %-7s  %-7s  %4s  %-23s  %s\n", '-' x 16, '---', '-' x 8, '-' x 7, '-' x 7, '----', '-' x 23, '-' x 30);
						foreach my $sshfile (keys %$sshkeys) {
							for my $i (0 .. $#{$sshkeys->{$sshfile}->{keys}}) {
								my $key = $sshkeys->{$sshfile}->{keys}[$i];
								cmdOutput($db, sprintf "%-16s  %3s  %-8s  %-7s  %-7s  %4s  %-23s  %s%s%s\n",
									($i > 0 ? '' : $sshfile),		# File
									$i+1,					# Idx
									$sshkeys->{$sshfile}->{level},		# Acc Levl
									$key->[0],				# Format
									$key->[1],				# Type
									$key->[2],				# Bits
									' ' x 11,				# blank
									$key->[3],				# Comments
									$::Debug ? "	".$key->[6] : '',	# Line number
									$::Debug ? "	".$key->[7] : '',	# Line of next key
								);
								cmdOutput($db, sprintf "%33s%s\n", '', $key->[5]);
							}
						}
					}
					else {
						cmdOutput($db, "No ssh public keys stored on switch\n");
					}
				}
				else {
					cmdMessage($db, "Unable to read ssh files on device\n");
				}
			}
			else {
				cmdMessage($db, "Can only read SSH keys on PassportERS / VOSS-VSP devices\n");
			}
		}
		else {
			cmdMessage($db, "No device connected\n");
		}
		$command = '';
	};
	#
	# @stop command
	#
	$command eq '@stop ?' && do {
		cmdMessage($db, "Syntax: \@stop [\"Message to display\"]\n");
		$command = '';
	};
	$command =~ /^\@stop(?: (.+))?/ && do {
		if ($term_io->{Sourcing}) {
			my $message = defined $1 ? quotesRemove($1) : '';
			cmdMessage($db, $message. "\n") if length $message;
			endofBlock($db, []); # Empty the whole buffer (like @exit)
			stopSourcing($db);
		}
		else {
			cmdMessage($db, "\@stop can only be processed when sourcing commands\n");
		}
		$command = '';
	};
	#
	# @timestamp command
	#
	$command eq '@timestamp' && do {
		cmdOutput($db, sprintf "=~=~=~=~=~=~=~=~=~=~= %s =~=~=~=~=~=~=~=~=~=~=\n", scalar localtime);
		$command = '';
	};
	#
	# @until command
	#
	$command =~ /^\@until .*\?$/ && do {
		cmdMessage($db, "Syntax: \@until <condition>\n");
		$command = '';
	};
	$command =~ /^\@until (.+)/ && do {
		if ($term_io->{Sourcing}) {
			my $block = $term_io->{BlockStack}->[$#{$term_io->{BlockStack}}];
			if (defined $block && $block->[0] eq '@loop') { # We are in a @loop block
				if (@{$block->[1]}) { # Normally always true, as set by @loop (only fasle if we hit a @last)
					my $varError;
					my $condition = derefConditionSection($db, $1, \$varError);
					$host_io->{OutBuffer} .= echoPrompt($term_io, appendPrompt($host_io, $term_io), 'vars') . $varError. "\n" if $varError && !$term_io->{EchoOff};
					my ($result, $evalError) = evalCondition($condition); # This evaluates the resulting condition
					if (!defined $result) { # Condition Syntax error
						cmdMessage($db, "Error on line '$command' -> $evalError\n");
						stopSourcing($db);
					}
					unless ($result) { # Condition False
						# We need to re-inject the loop commands
						appendInputBuffer($db, $block->[2], $block->[1], 1, 1);
					}
				}
				# We do this for either $result true or false case, and if @{$block->[1]} is empty indicating we hit a @last
				pop(@{$term_io->{BlockStack}});
			}
			else {
				cmdMessage($db, "Error on line '$command' -> no active \@while block\n");
				stopSourcing($db);
			}
		}
		else {
			cmdMessage($db, "\@loop, \@until can only be processed when sourcing commands\n");
		}
		$command = '';
	};
	#
	# @vars command
	#
	$command eq '@vars' && do {
		if (scalar keys %$vars) {
			foreach my $var (sort {$a cmp $b} keys %$vars) {
				next if $vars->{$var}->{myscope} && !$term_io->{Sourcing}; # Skip vars declared with @my
				next if $vars->{$var}->{dictscope}; # Skip dictionary variables
				cmdOutput($db, printVar($db, $var));
			}
			cmdOutput($db, "\nUnsaved variables exist\n") if %{$host_io->{UnsavedVars}};
		}
		else {
			cmdMessage($db, "No variables are set\n");
		}
		$command = '';
	};
	$command =~ /^\@vars prompt(?: optional)?(?: ifunset)?(?: \$(?:$VarUser(?:\[\d+\]|\{$VarHashKey\})?))? \?$/ && do {
		cmdMessage($db, "Syntax: \@vars prompt [optional] [ifunset] <\$variable> [\"Text to prompt user with\"]\n");
		$command = '';
	};
	($command =~ /^\@vars prompt( optional)?( ifunset)? (\$($VarUser)(\[(\d+)\])?)(?:\s+(.+))?$/o  ||
	 $command =~ /^\@vars prompt( optional)?( ifunset)? (\$($VarUser)(\{($VarHashKey)\})?)(?:\s+(.+))?$/o) && do {
		my ($optional, $ifunset, $displayVar, $var, $type, $koi, $prompt) = ($1, $2, $3, $4, $5, $6, $7);
		$type = '' unless defined $type;
		$type = 'list' if $type =~ /^\[/;
		$type = 'hash' if $type =~ /^\{/;
		my $varExists;
		if ($type eq 'list') {
			$varExists = defined $vars->{$var} && defined $vars->{$var}->{value}->[$koi - 1];
		}
		if ($type eq 'hash') {
			$varExists = defined $vars->{$var} && defined $vars->{$var}->{value}->{$koi};
		}
		else { # Normal variable
			$varExists = defined $vars->{$var};
		}
		unless ($varExists && $ifunset) {
			my $genericprompt;
			if ($prompt) {
				$prompt =~ s/\s+$//;		# Remove trailing spaces
				$prompt = quotesRemove($prompt);
				$prompt .= ' : ' unless $prompt =~/[:\?]\s*$/;
				$prompt .= ' ' unless $prompt =~/ $/;
			}
			else {
				$prompt = "Please enter a value for $displayVar : ";
				$genericprompt = 1;
			}
			if ($optional && $genericprompt) {
				if ($varExists) {
					$prompt =~ s/([\?:]\s*)$/[enter to unset]$1 /;
				}
				else {
					$prompt =~ s/([\?:]\s*)$/[enter to skip]$1 /;
				}
			}
			cmdMessage($db, $prompt);
			$term_io->{VarPrompt} = $var;
			$term_io->{VarPromptType} = $type;
			$term_io->{VarPromptKoi} = $koi;
			$term_io->{VarPromptOpt} = $optional;
			return '@varsprompt';
		}
		$command = '';
	};
	#
	# @while command
	#
	$command =~ /^\@while .*\?$/ && do {
		cmdMessage($db, "Syntax: \@while <condition>\n");
		$command = '';
	};
	$command =~ /^\@while (.+)/ && do {
		if ($term_io->{Sourcing}) {
			my $varError;
			my $condition = derefConditionSection($db, $1, \$varError);
			$host_io->{OutBuffer} .= echoPrompt($term_io, appendPrompt($host_io, $term_io), 'vars') . $varError. "\n" if $varError && !$term_io->{EchoOff};
			my ($result, $evalError) = evalCondition($condition); # This evaluates the resulting condition
			if (!defined $result) { # Condition Syntax error
				cmdMessage($db, "Error on line '$command' -> $evalError\n");
				stopSourcing($db);
			}
			elsif ($result) { # Condition True
				# Cache all commands inside the loop block
				if (my $loopCmds = cacheBlock($db, ['@endloop']) ) {
					push(@{$term_io->{BlockStack}}, ['@while', [$command, @$loopCmds], $term_io->{InputBuffQueue}->[0]]);
					# Need to cache $term_io->{InputBuffQueue}->[0] into BlockStack in case @endloop is last command in source/paste
				}
				else {
					cmdMessage($db, "Error in script file; end of '$command' block not found\n");
					stopSourcing($db);
				}
			}
			else { # Condition False
				# Empty buffer, until we find an endloop
				if ( endofBlock($db, ['@endloop']) ) {
					push(@{$term_io->{BlockStack}}, ['@while', []]);
				}
				else {
					cmdMessage($db, "Error in script file; end of '$command' block not found\n");
					stopSourcing($db);
				}
			}
		}
		else {
			cmdMessage($db, "\@while, \@endloop can only be processed when sourcing commands\n");
		}
		$command = '';
	};

	# Process Common Commands
	$command = processCommonCommand($db, $command) if length $command;

	if (length $command) {
		if ($host_io->{CommandCache}) {
			printOut($script_io, $host_io->{CommandCache});
			debugMsg(4,"=flushing CommandCache:\n>", \$host_io->{CommandCache}, "<\n");
			$host_io->{CommandCache} = '';
		}
		printOut($script_io, "Unable to process embedded command: $command\n");
		stopSourcing($db);
	}
	$host_io->{OutBuffer} .= "\n" if $script_io->{EmbCmdSpacing};
	$host_io->{OutBuffer} .= $host_io->{Prompt};
	return 1;
}

1;
