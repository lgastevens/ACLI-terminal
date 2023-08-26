# ACLI sub-module
package AcliPm::Dictionary;
our $Version = "1.04";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(loadDictionary dictionaryMatch dictionaryLookup setMapHashData);
}
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::GeneratePortListRange;
use AcliPm::GlobalConstants;
use AcliPm::GlobalDefaults;
use AcliPm::GlobalDeviceSettings;
use AcliPm::GlobalMatchingPatterns;
use AcliPm::DebugMessage;
use AcliPm::MaskUnmaskChars;
use AcliPm::ParseCommand;
use AcliPm::Print;
use AcliPm::Prompt;
use AcliPm::Sed;
use AcliPm::Sourcing;
use AcliPm::Variables;

my $Marker = "\x00";



sub deconstructCmd { # Breaks up the line into composing words and populates the dictionary input hash
	my ($inputHash, $idx, $line) = @_;
	debugMsg(1,"=deconstructCmd / line = ", \$line, "\n");
	my @hashRefList = ($inputHash);
	my @wordList = split(/\s+/, quoteCurlyMask($line, $Space));
	while (length (my $word = shift @wordList)) {
		$word = quoteCurlyUnmask($word, $Space);
		debugMsg(1,"=deconstructCmd / word = ", \$word, "\n");
		my @mandatoryWordList = grep {!/^\[[^\]]+\]$/} @wordList;
		#debugMsg(1,"=deconstructCmd / mandatoryWordList = ", \join(',', @mandatoryWordList), "\n");
		if ($word =~ s/^\[([^\]]+)\]$/$1/) { # Optional word/section in command
			my @iterHashRefList = @hashRefList;	# Make a copy from which we can iterate over
			my @sectWordList = split(/\s+/, $word); # In case section was = [word <value>]
			while (my $sectWord = shift @sectWordList) {
				debugMsg(1,"=deconstructCmd / sectWord = ", \$sectWord, "\n");
				my @newHashRefList; # Will replace @iterHashRefList for next cycle
				for my $hashRef (@iterHashRefList) {
					$hashRef->{$sectWord} = {} unless exists $hashRef->{$sectWord}; # Create new empty hash, unless one already existed
					if (@sectWordList || @wordList) { # This is not the final word in the section/command
						push(@newHashRefList, $hashRef->{$sectWord});	# Add this word's hashRef for next cycle
					}
					unless (@sectWordList || @mandatoryWordList) { # This is a valid final word in the section + command
						$hashRef->{$sectWord}->{$Marker} = $idx;	# Add marker and lookup index
					}
				}
				@iterHashRefList = @newHashRefList;
			}
			push(@hashRefList, @iterHashRefList);	# Append hasref lists following optional section
		}
		elsif ($word =~ /^\[/ || $word =~ /\]$/) { # Syntax error, come out with error
			return "Unmatched '[' ']'";
		}
		else { # Mandatory word in command
			my @newHashRefList; # Will replace @hashRefList for next cycle
			for my $hashRef (@hashRefList) {
				$hashRef->{$word} = {} unless exists $hashRef->{$word};	# Create new empty hash, unless one already existed
				if (@wordList) { # This is not the final word in the command
					push(@newHashRefList, $hashRef->{$word});	# Add this word's hashRef for next cycle
				}
				unless (@mandatoryWordList) { # This is a valid final word in the command
					$hashRef->{$word}->{$Marker} = $idx;		# Add marker and lookup index
				}
			}
			@hashRefList = @newHashRefList;
		}
	}
}


sub dereferenceCmd { # Adds a dictionary dereferenced translation
	my ($outputList, $idx, $cndIdxRef, $line) = @_;

	$line =~ /^\s+;\s*(.+?)\s*$/ && $$cndIdxRef >= 0 && do { # Semicolon fragmented translation
		$outputList->[$idx]->[$$cndIdxRef]->{CMD} .= "; $1";
		return;
	};
	$line =~ /^\s+(.+?)\s+=\s+(.+?)\s*$/ && do { # New conditional translation
		$outputList->[$idx]->[++$$cndIdxRef] = {CND => $1, CMD => $2};
		return;
	};
	return 'Invalid translation'
}


sub loadDictionary { # Reads a dictionary file into the dictionary data structure
	my ($db, $dictName) = @_;
	my $term_io = $db->[2];
	my $vars = $db->[12];
	my $dictionary = $db->[16];
	my $dictscope= $db->[17];
	my $dictFile;
	$dictName .= '.dict' if $dictName !~ /\./;

	%$dictionary = (input => {}, output => []);	# Wipe it clean
	#dictionary-hash = (
	#	input	=> {
	#		no	=> {},
	#		vlan	=> {
	#			create	=> {
	#				<vid:2-4050>	=> {
	#						type	=> {
	#							port	=> {x00 => 3},
	#							},
	#						},
	#				},
	#			delete	=> {
	#				<vid:2-4050>	=> {x00 => 4},
	#				},
	#			},
	#		etc..	=> {},
	#	},
	#	output	=> [
	#		[],
	#		[],
	#		[ # 3
	#			{
	#				CND	=> <condition_x>, # e.g. is_voss
	#				CMD	=> <command to execute if condition_x true>,
	#			},
	#			{
	#				CND	=> <condition_y>, # e.g. ix_xos
	#				CMD	=> <command to execute if condition_y true>,
	#			},
	#			...
	#		],
	#		[],
	#	],
	#	commnt => '<comment character>'
	#);

	# Find the dictionary file
	foreach my $path (@DictFilePath) {
		if (-e "$path/$dictName") {
			$dictFile = "$path/$dictName";
			last;
		}
	}
	unless (defined $dictFile) {
		cmdMessage($db, "Unable to locate dictionary file $dictName\n");
		return;
	}

	debugMsg(1,"-> Source input from dictionary file $dictFile\n");
	if ($term_io->{SourceActive}->{file}->{$dictFile}) {
		stopSourcing($db);
		cmdMessage($db, "Cannot recursively source same file");
		return;
	}
	$term_io->{DictionaryFile} = File::Spec->canonpath($dictFile);

	open(DICT, '<', $dictFile) or do {
		cmdMessage($db, "Unable to open dictionary file " . File::Spec->canonpath($dictFile) . "\n");
		return;
	};
	cmdMessage($db, "Loading dictionary file: " . File::Spec->rel2abs($dictFile) . "\n");

	my $lineNumber = 0;
	my $outputIndex = -1;
	my $conditionIndex = -1;
	my (@scriptLines, $dictBegin, $synErr, $varPrefix);
	while (<DICT>) {
		chomp;
		s/\x0d+$//g; # Remove trailing CRs (DOS files read on Unix OS)
		$lineNumber++;
		next if /^\s*$/; # skip empty lines
		next if /^\s*#/; # skip comment lines
		next if /^\s*\$VERSION/i; # skip version line
		$_ = quoteCurlyMask($_, '#'); # Mask comment character in case it appears inside quotes or brackets
		s/\s+#.*$//; # Remove comments on same line
		$_ = quoteCurlyUnmask($_, '#'); # Unmask
		/^\s*DICT_BEGIN/ && do {
			$dictBegin = 1;
			next;
		};
		if ($varPrefix) {
			s/\$\*($VarNormal)/\$$varPrefix$1/g; # Replace all $*vars if we saw a @my $<prefix>
		}
		elsif (/\$\*($VarNormal)/) { # If we did not see a @my $<prefix> throw an error
			$synErr = 'Variable in $*name format but no @my $prefix* found in script section';
		}
		unless ($synErr) {
			unless ($dictBegin) { # Script section
				$varPrefix = $1 if /^\s*\@my\s+\$($VarScript)\*/;
				debugMsg(1,"=loadDictionary / script line = ", \$_, "\n");
				push( @scriptLines, $_);
				next;
			}
			/^\s*DICT_COMMENT_LINE = (?|"(.)"|'(.)')\s*$/ && do {
				$dictionary->{commnt} = $1;
				next;
			};
			/^\S/ && do {
				if ($outputIndex == -1 || defined $dictionary->{output}->[$outputIndex]) {
					$synErr = deconstructCmd($dictionary->{input}, ++$outputIndex, $_);
					$conditionIndex = -1;
					next unless $synErr;
				}
				else {
					$synErr = 'Previous dictionary command had no translations'
				}
			};
			/^\s/ && do {
				if ($outputIndex >= 0) {
					$synErr = dereferenceCmd($dictionary->{output}, $outputIndex, \$conditionIndex, $_);
					next unless $synErr;
				}
				else {
					$synErr = 'translation requires definition first'
				}
			};
		}
		cmdMessage($db, "- syntax error on line $lineNumber" . (defined $synErr ? ": $synErr" : '') . "\n");
		cmdMessage($db, "Unable to read dictionary file " . File::Spec->canonpath($dictFile) . "\n");
		close DICT;
		return;
	}
	close DICT;

	# Finish processing script section
	if (@scriptLines && !$::TestScript) {
		push( @scriptLines, "\x00file:".$dictFile); # Encoded line to know when to clear $term_io->{SourceActive}->{file}->{$source}
		appendInputBuffer($db, 'source', \@scriptLines, 1);
		$term_io->{SourceActive}->{file}->{$dictFile} = 1; # Make sure we don't source this file again, till we empty buffers
		debugMsg(4,"=loadDictionary setting SourceActive: file / ", \$dictFile, "\n");
		# Clear out the save buffers
		$term_io->{SaveCharBuffer} = '';
		$term_io->{SaveSourceActive} = {};
		$term_io->{SaveEchoMode} = [];
		$term_io->{SaveSedDynPats} = [];
		$term_io->{SourceNoHist} = 1;	# Disable history
		$term_io->{DictSourcing} = 1;	# Remember we are sourcing script from a dictionary file
		# Clear positional arguments, if some were set
		foreach my $var (keys %{$vars}) {
			next unless $vars->{$var}->{argument}; # Only delete numerical keys and $*
			delete($vars->{$var});
		}
		$dictscope->{varnames} = {};
		$dictscope->{wildcards} = [];
	}

	return 1;
}


sub mapPortList { # Performs dictionary port mapping
	my ($mapHash, $inPortList) = @_;
	my @outPortList;
	debugMsg(1,"-> mapPortList input = ", \$inPortList, "\n");
	for my $inPort (sortByPort split(',', $inPortList)) {
		next unless exists $mapHash->{$inPort};
		push(@outPortList, $mapHash->{$inPort});
	}
	debugMsg(1,"-> mapPortList output = ", \join(',', @outPortList), "\n") if $::Debug;
	return \@outPortList;
}


sub argRegexVar { # Produce a regex and return the variable name for the various <argument:formats>
	my $arg = shift;
	my ($regex, $varName, $min, $max, $list);
	$arg =~ /<([^>]+)>/ && do {
		my $argSection = $1;
		if ($argSection =~ /^ports?$/) {
			$varName = lc $argSection;
			$regex = '^((?:\d{1,2}(?:\-\d{1,2})?,)*\d{1,2}(?:\-\d{1,2})?|(?:\d{1,3}[\/:](?:ALL|s\d|\d{1,2}(?:\/\d{1,2})?)(?:\-\d{1,3}(?:[\/:](?:s\d|\d{1,2}(?:\/\d{1,2})?))?)?,)*\d{1,3}[\/:](?:ALL|s\d|\d{1,2}(?:\/\d{1,2})?)(?:\-\d{1,3}(?:[\/:](?:s\d|\d{1,2}(?:\/\d{1,2})?))?)?|ALL)$';
			debugMsg(4, "argRegexVar : arg = $arg / port-regex >", \$regex, "< / varName = $varName\n");
		}
		elsif ($argSection =~ /^([\d\w\-_]+):(\d+)-(\d+)(,)?$/) {
			($varName, $min, $max, $list) = ($1, $2, $3, $4);
			if ($list) {
				$regex = '(\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*)';
			}
			else {
				$regex = '(\d+)';
			}
			debugMsg(4, "argRegexVar : arg = $arg / number-regex >", \$regex, "< / varName = $varName\n");
		}
		elsif ($argSection =~ /^([\d\w\-_]+):((?:[^,]+,)*.+)$/) {
			$varName = $1;
			$regex = [split(',', $2)];
			debugMsg(4, "argRegexVar : arg = $arg / list-regex >", \join('.', @$regex), "< / varName = $varName\n");
		}
		elsif ($argSection =~ /^([\d\w\-_]+)$/) {
			$varName = $1;
			$regex = '^(\S+|\'[^\']+\'|\"[^\"]+\")$';
			debugMsg(4, "argRegexVar : arg = $arg / anytext-regex >", \$regex, "< / varName = $varName\n");
		}
	};
	return ($regex, $varName, $min, $max);
}


sub matchDictWord { # Matches a word entered by user with a list of available dictionary next valid words/arguments
	my ($db, $entered, $available, $varHash) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $dictionary = $db->[16];
	return ([]) unless length $entered && $entered ne '?';
	my @match;

	# Split the available into <arguments> and fixed words 
	my $regexArg = qr/<[^>]+>/;
	my @arguments = grep(/$regexArg/, @$available);
	my @cmdwords = grep(!/$regexArg/, @$available);

	# Check if we have a full match of fixed word
	my $regexFull = qr/^\Q$entered\E$/i;
	@match = grep(/$regexFull/, @cmdwords);
	return (\@match) if scalar @match == 1;

	# If not, then try a partial match
	my $regexPart = qr/^\Q$entered\E/i;
	@match = grep(/$regexPart/, @cmdwords);
	return (\@match) if @match; # Return the list, whatever it may be

	# Else, check if we match the <arguments>
	for my $arg (@arguments) {
		my ($regex, $varName, $min, $max) = argRegexVar($arg);
		if (ref($regex) eq 'ARRAY') { # Regex is infact a listRef
			# Check if we have a full match of fixed word
			@match = grep(/$regexFull/, @$regex);
			if (scalar @match == 1) {
				$varHash->{$varName} = $match[0];
				return (\@match, $arg);
			}
			# If not, then try a partial match
			@match = grep(/$regexPart/, @$regex);
			$varHash->{$varName} = $match[0] if scalar @match == 1;
			return (\@match, $arg) if @match; # Return the list, whatever it may be
		}
		elsif ($entered =~ /^$regex$/) { # Else is a regex
			my $match = $1;
			if ($varName =~ /^port(s)?$/) {
				my $many = $1;
				my $portList = generatePortList($host_io, $match, undef, $dictionary->{prtinp});
				next if $portList =~ /,/ && !$many;
				$portList = mapPortList($dictionary->{prtmap}, $portList) if defined $dictionary->{prtinp};
				$match = generateRange($db, $portList, $DevicePortRange{$host_io->{Type}} || $term_io->{DefaultPortRng});
			}
			elsif (defined $min && defined $max) {
				my $valListRef = generateVlanList($match, 1);
				next if grep {$_ < $min} @$valListRef;
				next if grep {$_ > $max} @$valListRef;
			}
			$varHash->{$varName} = $match;
			return ([$entered], $arg);
		}
	}

	# If nothing matches
	return ([]);
}


sub dictionaryMatch { # Searches for command into dictionary (modified tabExpand)
	# If it's recognized it is expanded and returned with a trailing space; otherwise nothing is returned
	# Returns: (
	#		parsed command if command complete, empty string otherwise,
	#		index if parsed command complete, undef otherwise,
	#		arg var ref if parsed command complete, undef otherwise,
	#		list ref of avail syntax if parsed command incomplete, undef otherwise
	#	)
	my ($db, $cmdHash, $cliCmd) = @_;
	my $varHash = {};
	my $idx;

	debugMsg(4, "=dictionaryMatch : called with >$cliCmd<\n");
	# Process the input command to clean it up
	$cliCmd =~ s/\s+$//;			# Remove trailing spaces
	$cliCmd =~ s/^\s+//;			# Remove leading spaces
	$cliCmd =~ s/([^\s@])\?$/$1 ?/;		# If command ends with ? make sure space before ? (except for @?)
	$cliCmd = quoteCurlyMask($cliCmd, ' ');	# Mask spaces inside quotes
	my @cliCmd = split(/\s+/, $cliCmd);	# Split it into an array
	@cliCmd = map { quoteCurlyUnmask($_, ' ') } @cliCmd;	# Needs to re-assign, otherwise quoteCurlyUnmask won't work
	$cliCmd[0] = '' unless $cliCmd[0];	# First word must be defined
	debugMsg(4, "\ndictionaryMatch : command split into array : ", \join(',', @cliCmd), "\n");

	my $cmdWord = shift @cliCmd;
	my ($parsed, $dictEntry) = ('', '');
	while (length $cmdWord && ref $cmdHash eq 'HASH') {
		my ($cmdList, $cmdNextHash) = matchDictWord($db, $cmdWord, [keys %$cmdHash], $varHash);
		debugMsg(4, join('', "dictionaryMatch : number of matched commands = ", scalar @$cmdList, " / list = ", join(',', @$cmdList), "\n"));
		last unless @$cmdList; # No match, come out
		if (scalar @$cmdList == 1) { # Exact (single) command matched; continue while loop
			$cmdWord = $cmdList->[0];
			$parsed .= (length($parsed) ? ' ':'') . $cmdWord;
			$dictEntry .= ' ' if length $dictEntry;
			if (defined $cmdNextHash) { # We matched an <arg:values>
				$cmdHash = $cmdHash->{$cmdNextHash};
				$cmdNextHash =~ s/^<[\d\w\-_]+\K:[^:]+(?=>$)//; # Remove :values and leave <arg>
				$dictEntry .= $cmdNextHash;
			}
			else {
				$cmdHash = $cmdHash->{$cmdWord};
				$dictEntry .= $cmdWord;
			}
			$cmdWord = shift @cliCmd;
			$cmdWord = '' unless defined $cmdWord;
		}
		else { # More than one match; return the list
			debugMsg(4, "dictionaryMatch - more than 1 match : returning null string\n");
			return ('', undef, undef, undef, $cmdList);
		}
	}
	debugMsg(4, "dictionaryMatch : parsed command : >$parsed<\n");
	debugMsg(4, "dictionaryMatch : dictionary entry : >$dictEntry<\n");
	debugMsg(4, "dictionaryMatch : residual cmdWord : >", \$cmdWord, "<\n");
	unless (length $parsed) { # If no match at all come out
		debugMsg(4, "dictionaryMatch - no match at all\n");
		return ('', undef, undef, undef, undef);
	}
#	my $remaining = join(' ', $cmdWord, @cliCmd);
#	debugMsg(4, "dictionaryMatch : remaining unmatched input : >", \$remaining, "<\n");
	debugMsg(4, "dictionaryMatch : what cmd points to in hash structure(cmdHash) : >", \$cmdHash, "<\n");
	$idx = $cmdHash->{$Marker} if exists $cmdHash->{$Marker};
	debugMsg(4, "dictionaryMatch : index = >$idx<\n") if defined $idx;
	$parsed .= ' ';
	if (defined $idx && length $cmdWord) { # Complete match, optional keywords remain
		if ($cmdWord eq '?') { # We have possible optional words other then just the marker
			debugMsg(4, "dictionaryMatch - complete match but with optional keywords remaining\n");
			return ($parsed, undef, undef, undef, [keys %$cmdHash]);
		}
		else {
			debugMsg(4, "dictionaryMatch - complete match but with excessive input from user\n");
			return ('', undef, undef, undef, undef);
		}
	}
	if (length $cmdWord) { # Partial match, provide available syntax list
		if ($cmdWord eq '?') { # We have possible optional words other then just the marker
			debugMsg(4, "dictionaryMatch - partial match but with optional keywords remaining\n");
			return ('', undef, undef, undef, [keys %$cmdHash]);
		}
		else {
			debugMsg(4, "dictionaryMatch - partial match but with excessive input from user\n");
			return ('', undef, undef, undef, undef);
		}
	}
	debugMsg(4, "dictionaryMatch - complete and full match\n");
	return ($parsed, $idx, $varHash, $dictEntry, undef);
}


sub deRefDictVar { # Replace dictionary variables
	my ($inputVars, $varField, $varName) = @_;

	if (defined $inputVars->{$varName}) { # Value was entered in the command line
		debugMsg(4,"=deRefDictVar: De-RefVar: <$varName> / >$varField< ");
		$varField =~ s/<$varName>/$inputVars->{$varName}/;
		$varField =~ s/[\[\]]//g;
		debugMsg(4,"to >$varField<\n");
		return $varField;
	}
	# Mandatory or optional field, replace with nothing...
	return '';
}


sub replaceDictVar { # Replace alias variable
	my ($inputVars, $varName) = @_;
	my $varValue = '';
	$varValue = "'".$inputVars->{$varName}."'" if defined $inputVars->{$varName}; # in between single quotes
	return $varValue;
}


sub dictionaryLookup { # Lookup entered command in dictionary
	my ($db, $cmdParsed, $syntax) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $dictionary = $db->[16];
	my $dictscope= $db->[17];

	return unless length $cmdParsed->{command}->{str};
	my $command = $cmdParsed->{command}->{str}; # Make a copy before making mods

	# Prepare the prompt and alias echo header
	my $prompt = appendPrompt($host_io, $term_io);
	my $dictEcho = echoPrompt($term_io, $prompt, 'dict');

	# Verify for comment line first
	if (defined $dictionary->{commnt} && $command =~ /^\Q$dictionary->{commnt}/) {
		debugMsg(4,"=dictionaryLookup: comment line :>", \$command, "<\n");
		if (length $host_io->{CommandCache} && $term_io->{EchoOff} == 2) { # Echo mode "sent", and dictionary command was pasted/sourced
			printOut($script_io, $host_io->{CommandCache});
			debugMsg(4,"=flushing CommandCache - echo sent - dict comment:\n>", \$host_io->{CommandCache}, "<\n");
			$host_io->{CommandCache} = '';
		}
		printOut($script_io, "\n$prompt");
		return 0;
	}
	my ($dictcmd, $idx, $inputVars, $dictEntry, $syntaxList) = dictionaryMatch($db, $dictionary->{input}, $command);
	#                   ^ Hash ref with all variable values inside entered command
	#             ^ Index into dictionary output
	#   ^ Full expanded command; can be used for tab expansion

	if ($syntax && (length $dictcmd || defined $syntaxList) ) { # We are syntax checking only and we have a possible dictionary command
		my ($hon, $hoff) = returnHLstrings({bright => 1, underline => 1});
		printOut($script_io, "\n$hon$term_io->{Dictionary} dictionary available syntax$hoff\n");
		if (length $dictcmd) {
			printOut($script_io, "  <cr>\n");
		}
		foreach my $syntax (@$syntaxList) {
			next if $syntax eq $Marker;
			printOut($script_io, "  $syntax\n");
		}
		chop $command if $term_io->{PseudoTerm}; # Remove the trailing '?' if in pseudo mode
		printOut($script_io, "\n$prompt$command");
		return 1;
	}

	return unless length $dictcmd;
	unless (defined $idx) {
		debugMsg(4,"=dictionaryLookup: ERROR! / \$idx is undef<\n");
		return;
	}

	$dictcmd =~ s/\s+$//; # Remove trailing space
	debugMsg(4,"=dictionaryLookup:>$dictcmd<\n");

	# Now check its de-reference conditions
	my ($expression, $lookupcmd);
	CONDITIONS: for my $c (0 .. $#{$dictionary->{output}->[$idx]}) { # For every condition for alias
		$expression = $dictionary->{output}->[$idx]->[$c]->{CND};
		$expression =~ s/{([\w_]+)(?:\[(\d+)\])?}/replaceAttribute($db, $1, $2, 1)/ge;
		$expression =~ s/\$([\d\w\-_]+)/replaceDictVar($inputVars, $1)/ge;
		debugMsg(4,"=dictionaryLookup: $dictcmd / expression to eval:>", \$expression, "<\n");
		{
			local $SIG{__WARN__} = sub { }; # Disable warnings for the eval below (bug7)
			if (eval $expression) {
				debugMsg(4,"=dictionaryLookup: $dictcmd / expression >", \$dictionary->{output}->[$idx]->[$c]->{CND}, "< is TRUE\n");
				$lookupcmd = $dictionary->{output}->[$idx]->[$c]->{CMD};
				last CONDITIONS;
			}
		}
	}
	unless ($lookupcmd) {
		printOut($script_io, "\n$dictEcho$dictcmd <no conditions match>\n$prompt");
		return;
	}

	if ( (exists $inputVars->{port} && !length $inputVars->{port})   ||
	     (exists $inputVars->{ports} && !length $inputVars->{ports}) ) {
		debugMsg(4,"=dictionaryLookup: empty <port> or <ports> / treat as &ignore<\n");
		$lookupcmd = '&ignore "Ignoring dictionary command due to empty <port(s)> after applying dictionary input port-range"';
	}
	debugMsg(4,"=dictionaryLookup: $dictcmd / lookup cmd: ", \$lookupcmd, "\n");

	# Check if command is just a local instruction
	if ((my $instrMsg = $lookupcmd) =~ s/^&(\S+)\s*//) {
		my $dictdo = $1;
		if ($dictdo eq 'ignore') {
			if (length $host_io->{CommandCache} && $term_io->{EchoOff} == 2) { # Echo mode "sent", and dictionary command was pasted/sourced
				printOut($script_io, $host_io->{CommandCache});
				debugMsg(4,"=flushing CommandCache - echo sent - dict &ignore:\n>", \$host_io->{CommandCache}, "<\n");
				$host_io->{CommandCache} = '';
			}
			$instrMsg =~ s/"//g; # Remove " quotes
			$instrMsg =~ s/\\n/\n/g; # Restore newlines
			$instrMsg =~ s/\\t/\t/g; # Restore tabs
			printOut($script_io, "\n$instrMsg") if length $instrMsg;
			printOut($script_io, "\n$prompt");
			debugMsg(4,"=dictionaryLookup: &ignore\n");
			return 0;
		}
		if ($dictdo eq 'error') {
			if (length $host_io->{CommandCache} && $term_io->{EchoOff} == 2) { # Echo mode "sent", and dictionary command was pasted/sourced
				printOut($script_io, $host_io->{CommandCache});
				debugMsg(4,"=flushing CommandCache - echo sent - dict &error:\n>", \$host_io->{CommandCache}, "<\n");
				$host_io->{CommandCache} = '';
			}
			$instrMsg =~ s/"//g; # Remove " quotes
			$instrMsg =~ s/\\n/\n/g; # Restore newlines
			$instrMsg =~ s/\\t/\t/g; # Restore tabs
			printOut($script_io, "\n$instrMsg") if length $instrMsg;
			printOut($script_io, "\n$prompt");
			debugMsg(4,"=dictionaryLookup: &error\n");
			stopSourcing($db);
			return 0;
		}
		elsif ($dictdo eq 'same') { # Skip translation and send to host as is
			debugMsg(4,"=dictionaryLookup: &same\n");
			return unless $dictEntry =~ /<ports?>/;
			debugMsg(4,"=dictionaryLookup: &same - falling through as <port(s)> arg in use\n");
		}
		else {
			printOut($script_io, "\n$dictEcho$dictcmd <&$dictdo is unrecognized>\n$prompt");
			stopSourcing($db);
			return;
		}
	}

	# Now de-reference any variables embedded in the de-referenced command
	$lookupcmd =~ s/(?:^|;\s*)\K&same(?=[\s;]|$)/$dictEntry/;					# Replace original command for &same
	$lookupcmd =~ s/\s*\K(\[[^\[\]]*?<([\d\w\-_]+)>.*?\])/deRefDictVar($inputVars, $1, $2)/ge;	# Optional <var>
	$lookupcmd =~ s/\s*\K(<([\d\w\-_]+)>)/deRefDictVar($inputVars, $1, $2)/ge;			# Mandatory <var>

	$lookupcmd =~ s/^;\s*//;	# Ensure no leading ';'
	$lookupcmd =~ s/\s*;$//;	# Ensure no trailing ';'
	$lookupcmd =~ s/;\s*;/;/g;	# Ensure no empty sections between ';'
	debugMsg(4,"=dictionaryLookup: $dictcmd / replace with: ", \$lookupcmd, "\n");

	# Merge in and remember we are processing a dictionary, to prevent loops
	mergeCommand($cmdParsed, $lookupcmd, 'dict');
	$term_io->{SourceActive}->{dict} = 1;
	debugMsg(4,"=dictionaryLookup setting SourceActive: dict / 1\n");

	# Show alias de-referencing on output
	if ( ($term_io->{DictionaryEcho} == 1 || ($term_io->{DictionaryEcho} == 2 && $cmdParsed->{semicln}->{lst}->[0] =~ /^\x00/) )
	    && !($term_io->{InputBuffQueue}->[0] eq 'RepeatCmd') ) {
		if ($term_io->{EchoOff} && $term_io->{Sourcing}) {
			$host_io->{CommandCache} .= "\n$dictEcho" . $cmdParsed->{fullcmd};
			debugMsg(4,"=adding to CommandCache:\n>",\$host_io->{CommandCache}, "<\n");
		}
		else {
			printOut($script_io, "\n$dictEcho" . $cmdParsed->{fullcmd});
			--$term_io->{PageLineCount};
		}
	}
	return 1;
}


sub setMapHashData { # Updates the dictionary port mapping hash and produces output information
	my $db = shift;
	my $host_io = $db->[3];
	my $dictionary = $db->[16];
	my %data;
	my $allPortList = [split(',', scalar generatePortList($host_io, 'ALL'))];
	my $outPortList = defined $dictionary->{prtout} ? [split(',', scalar generatePortList($host_io, $dictionary->{prtout}))] : $allPortList;
	if (defined $dictionary->{prtinp}) {
		my $inpPortList = [split(',', scalar generatePortList($host_io, 'ALL', undef, $dictionary->{prtinp}))];
		my (%mappingHash, %hostPortsMapped, @hostPortsMapped, @inPortsNotMapped, @hostPortsNotMapped);
		for my $i (0 .. $#{$inpPortList}) {
			if (defined $outPortList->[$i]) {
				$mappingHash{$inpPortList->[$i]} = $outPortList->[$i];
				$hostPortsMapped{$outPortList->[$i]} = 1;
				push(@hostPortsMapped, $outPortList->[$i]);
			}
			else {
				push(@inPortsNotMapped, $inpPortList->[$i]);
			}
		}
		$dictionary->{prtmap} = \%mappingHash;
		for my $port (@$allPortList) {
			push(@hostPortsNotMapped, $port) unless exists $hostPortsMapped{$port};
		}
		$data{inputPortCount} = scalar @$inpPortList;
		$data{mappedPortCount} = scalar @hostPortsMapped;
		$data{unusedInputPortCount} = scalar @inPortsNotMapped;
		$data{unusedHostPortCount} = scalar @hostPortsNotMapped;
		$data{inputPortRange} = generateRange($db, $inpPortList, $DevicePortRange{$host_io->{Type}}, $dictionary->{prtinp});
		$data{mappedPortRange} = generateRange($db, \@hostPortsMapped, $DevicePortRange{$host_io->{Type}});
		$data{unusedInputPorts} = generateRange($db, \@inPortsNotMapped, $DevicePortRange{$host_io->{Type}}, $dictionary->{prtinp});
		$data{unusedHostPorts} = generateRange($db, \@hostPortsNotMapped, $DevicePortRange{$host_io->{Type}});
	}
	else {
		$data{mappedPortRange} = generateRange($db, $outPortList, $DevicePortRange{$host_io->{Type}});
		$data{mappedPortCount} = scalar @$outPortList;
	}
	return \%data;
}


1;
