# ACLI sub-module
package AcliPm::Sourcing;
our $Version = "1.06";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(stopSourcing appendInputBuffer saveInputBuffer releaseInputBuffer shiftInputBuffer inputBufferIsVoid readSourceFile);
}
use Time::HiRes;
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::DebugMessage;
use AcliPm::GlobalDefaults;
use AcliPm::MaskUnmaskChars;
use AcliPm::Print;
use AcliPm::Prompt;
use AcliPm::QuotesRemove;
use AcliPm::Sed;
use AcliPm::Variables;


sub stopSourcing { # Sets flags to to stop command sourcing
	my $db = shift;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	$term_io->{Sourcing} = undef;
	debugMsg(1,"=sourcing mode DISABLED in stopSourcing\n");
	$host_io->{SyntaxError} = 1;
	($term_io->{QuietInputDelay}, $term_io->{DelayCharProcDF}) = (Time::HiRes::time + $QuietInputDelay, 1);
	debugMsg(4,"=Set QuietInputDelay expiry time = ", \$term_io->{QuietInputDelay}, "\n");
	$term_io->{BuffersCleared} = 0;
}


sub appendInputBuffer { # Add a line or more lines to the desired Input Buffer
	my ($db, $buffer, $listRef, $unshift, $noReset, $skipResetKey) = @_;
	my $term_io = $db->[2];
	my $script_io = $db->[4];
	my $vars = $db->[12];
	my $varscope = $db->[15];

	unless ($term_io->{InputBuffQueue}->[0] || $noReset) { 		# If we are loading empty buffers and noReset is not set
		$term_io->{SaveBuffQueue} = undef;			# Wipe the save buffer if any
		@{$term_io->{BlockStack}} = ();				# Clear out the block stack used by @if, @else, etc..
		debugMsg(4,"=InputBuffer resetting SaveBuffQueue & BlockStack\n");
		printOut($script_io, "\nWarning: Entering source mode and \@echo is off !\n") if $term_io->{EchoOff} == 1 && !defined $noReset;
		$script_io->{PrintFlag} = 0 if $buffer eq 'paste';
	}
	unless ($term_io->{InputBuffQueue}->[0] eq $buffer) {		# Bringing buffer at front of queue
		unshift(@{$term_io->{InputBuffQueue}}, $buffer);	# Front of queue
		@{$term_io->{InputBuffer}->{$buffer}} = ();		# Empty buffer, in case it had old entries in it
		debugMsg(4,"=InputBuffer New Queuing order: ", \join(' -> ', @{$term_io->{InputBuffQueue}}), "''\n");
	}
	unless ($term_io->{Sourcing}) { # We are about to enter Sourcing mode; delete any previously held @my variables & wipe out $varscope structure
		debugMsg(4,"=InputBuffer clearing \@my local scope variable\n");
		foreach my $var (keys %$vars) {
			next unless $vars->{$var}->{myscope};
			delete $vars->{$var};
		}
		$varscope->{varnames} = {};
		$varscope->{wildcards} = [];
		$term_io->{Sourcing} = 1;
		$term_io->{DictSourcing} = undef;
		$term_io->{RepeatCmd} = undef unless $skipResetKey && $buffer eq 'RepeatCmd';
		$term_io->{ForLoopCmd} = undef unless $skipResetKey && $buffer eq 'ForLoopCmd';
		debugMsg(1,"=sourcing mode ENABLED in appendInputBuffer\n");
	}
	return unless defined $listRef;
	if ($unshift) { # For source & semiclnfrg buffer types
		unless (@{$term_io->{InputBuffer}->{$buffer}}) {
			push( @$listRef, "\x00") unless $listRef->[-1] =~ /^\x00/; # End of buffer marker, except if already added
		}
		unshift @{$term_io->{InputBuffer}->{$buffer}}, @$listRef;	# Pre-pend the commands onto the input buffer
	}
	else { # Push; RepeatCmd, SleepCmd, ForLoopCmd, paste and scripting @blocks
		push( @$listRef, "\x00") unless $listRef->[-1] =~ /^\x00/; # End of buffer marker, except if already added
		# helps ensure that $term_io->{Sourcing} does not get reset until next cycle after last command in buffer
		pop @{$term_io->{InputBuffer}->{$buffer}} while @{$term_io->{InputBuffer}->{$buffer}} && $term_io->{InputBuffer}->{$buffer}->[-1] eq "\x00";
		push @{$term_io->{InputBuffer}->{$buffer}}, @$listRef;		# Append the command onto the input buffer
	}
}


sub saveInputBuffer { # Save contents of the input buffer, and then clear the buffers
	my ($term_io, $clearRptCmd) = @_;

	shift @{$term_io->{InputBuffQueue}} if $clearRptCmd &&
		('RepeatCmd' eq $term_io->{InputBuffQueue}->[0] || 'SleepCmd' eq $term_io->{InputBuffQueue}->[0]); # We never want to resume repeatCmd
	if ($term_io->{InputBuffQueue}->[0]) { # A queue is set
		@{$term_io->{SaveBuffQueue}} = @{$term_io->{InputBuffQueue}};
		@{$term_io->{InputBuffQueue}} = ('');
		debugMsg(4,"=saveInputBuffer: Saved InputBuffer\n");
	}
	if (@{$term_io->{CharBuffer}}) { # Chars to cache; applies only to paste mode
		$term_io->{SaveCharBuffer} .= join('', @{$term_io->{CharBuffer}});
		@{$term_io->{CharBuffer}} = (); # Empty the character buffer
		debugMsg(4,"=saveInputBuffer: Saved CharBuffer: >", \$term_io->{SaveCharBuffer}, "<\n");
	}
	if (length $term_io->{CharPBuffer}) {
		$term_io->{SaveCharPBuffer} .= $term_io->{CharPBuffer};
		debugMsg(4,"=saveInputBuffer: Saved CharPBuffer: >", \$term_io->{SaveCharPBuffer}, "<\n");
	}
	$term_io->{SaveSourceActive} = $term_io->{SourceActive};
	$term_io->{SaveEchoMode} = [$term_io->{EchoOff}, $term_io->{EchoOutputOff}];
	$term_io->{SaveSedDynPats} = popSedScriptPats($term_io);
	$term_io->{SourceActive} = {};
	$term_io->{Sourcing} = undef;
	debugMsg(1,"=sourcing mode DISABLED in saveInputBuffer\n");
}


sub releaseInputBuffer { # Release the input buffers so that they can resume execution
	my $term_io = shift;

	if (defined $term_io->{SaveBuffQueue}) {
		@{$term_io->{InputBuffQueue}} = @{$term_io->{SaveBuffQueue}};
		debugMsg(4,"=Releasing InputBuffer with Queuing order: /", \join(' -> ', @{$term_io->{InputBuffQueue}}), "''\n");
		$term_io->{Sourcing} = 1;
		debugMsg(1,"=sourcing mode ENABLED in releaseInputBuffer\n");
	}
	if (length $term_io->{SaveCharBuffer}) {
		push( @{$term_io->{CharBuffer}}, split(//, $term_io->{SaveCharBuffer}) );
		debugMsg(4,"=Releasing CharBuffer with in it: /", \$term_io->{SaveCharBuffer}, "/\n");
	}
	if (length $term_io->{SaveCharPBuffer}) {
		$term_io->{CharPBuffer} = $term_io->{SaveCharPBuffer};
	}
	$term_io->{SourceActive} = $term_io->{SaveSourceActive} if scalar keys %{$term_io->{SaveSourceActive}};
	$term_io->{EchoOff} = $term_io->{SaveEchoMode}->[0];
	$term_io->{EchoOutputOff} = $term_io->{SaveEchoMode}->[1];
	addSedScriptPats($term_io, $term_io->{SaveSedDynPats});
	# Clear out the save buffers
	$term_io->{SaveBuffQueue} = undef;
	$term_io->{SaveCharBuffer} = $term_io->{SaveCharPBuffer} = '';
	$term_io->{SaveSourceActive} = {};
	$term_io->{SaveEchoMode} = [];
	$term_io->{SaveSedDynPats} = [];
}


sub shiftInputBuffer { # Used to shift out next command from source, paste, semiclnfrg buffer; also used for RepeatCmd and SleepCmd with @sleep, and ForLoopCmd
	my $db = shift;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $script_io = $db->[4];
	my $termbuf = $db->[8];
	my $vars = $db->[12];
	my $queue = $term_io->{InputBuffQueue}->[0];
	my $command;
	while (1) {
		$command = shift @{$term_io->{InputBuffer}->{$queue}};
		last unless defined $command && $command =~ /^\x00(\w*)(?::(.*))?$/;
		if ($1 && $2) { # Encoded source file/alias name
			$term_io->{SourceActive}->{$1}->{$2} = 0;
			debugMsg(4,"=shiftInputBuffer clearing SourceActive: $1 / ", \$2, "\n");
		}
		elsif ($1) { # Encoded dict
			$term_io->{SourceActive}->{$1} = 0;
			debugMsg(4,"=shiftInputBuffer clearing SourceActive: $1\n");
		}
	}
	if (!@{$term_io->{InputBuffer}->{$queue}}) {	# If no more commands...
		if ($term_io->{InputBuffQueue}->[0]) {	# ... and queue is still set
			shift @{$term_io->{InputBuffQueue}};
			if ($queue eq 'source') {
				%{$term_io->{SourceActive}} = ();
				debugMsg(4,"=shiftInputBuffer clearing SourceActive hash\n");
				foreach my $var (keys %{$vars}) {
					next unless $vars->{$var}->{argument}; # Only delete numerical keys and $*
					delete($vars->{$var});
				}
				if ($term_io->{RunSyntax}) { # Restore input buffer
					$termbuf->{Linebuf1} = $term_io->{RunSyntax};
					($termbuf->{Bufback1} = $termbuf->{Linebuf1}) =~ s/./\cH/g;
					$term_io->{RunSyntax} = undef;
				}
			}
		}
		unless ($term_io->{InputBuffQueue}->[0]) {
			if (length $host_io->{CommandCache}) {
				printOut($script_io, $host_io->{CommandCache});
				debugMsg(4,"=flushing CommandCache:\n>", \$host_io->{CommandCache}, "<\n");
				$host_io->{CommandCache} = '';
				$script_io->{PrintFlag} = 0;
			}
			$term_io->{Sourcing} = undef;
			popSedScriptPats($term_io);
			debugMsg(1,"=sourcing mode DISABLED in shiftInputBuffer\n");
		}
	}
	return $command;
}


sub inputBufferIsVoid { # Determines if the buffer is actually void before we actually empty at at next cycle(s) (might have final \x00 markers only)
	my $db = shift;
	my $term_io = $db->[2];
	my $localDebug = 1; # Could not have chosen a more complicated data structure for inputBuffers !...
	#Debug::run($db) if $DebugPackage && $localDebug;
	if (scalar @{$term_io->{InputBuffQueue}} > 2) {
		debugMsg(1,"=inputBufferIsVoid = 0 / buffer not void, more than 1 queue is set\n") if $localDebug;
		return 0;
	}
	elsif (scalar @{$term_io->{InputBuffQueue}} == 2) {
		my $queue = $term_io->{InputBuffQueue}->[0];
		if ($queue) { # Non-empty queue
			if (defined $term_io->{InputBuffer}->{$queue}->[0]) { # Queue with input buffer (paste, source, semiclnfrg)
				if ($term_io->{InputBuffer}->{$queue}->[0] =~ /^\x00/) { # Source Active marker
					debugMsg(1,"=inputBufferIsVoid = 1 / buffer void, found source-active marker in queue: ", \$queue, "\n");
					return 1;
				}
				else { # No source active marker
					debugMsg(1,"=inputBufferIsVoid = 0 / buffer not void, found data in queue: ", \$queue, "\n") if $localDebug;
					return 0;
				}
			}
			else { # Queue with no input buffer (RepeatCmd, ForLoopCmd, SleepCmd)
				debugMsg(1,"=inputBufferIsVoid = 0 / bufferless queue: ", \$queue, "\n") if $localDebug;
				return 0;
			}
		}
		else { # Empty '' queue; should never happen, in this case we would be in <= 1 below
			debugMsg(1,"=inputBufferIsVoid = 1 / buffer is void, UNEXPECTED empty queue first queue with others behind it\n");
			return 1;
		}
	}
	else { # <= 1
		debugMsg(1,"=inputBufferIsVoid = 1 / buffer is void, no queues\n") if $localDebug;
		return 1;
	}
}


sub readSourceFile { # Read in a file for sourcing, for @source, @run or '<'
	my ($db, $args, $runPaths) = @_;
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $vars = $db->[12];

	# Format source string
	$args =~ s/^\s+//;		# Remove leading spaces
	$args =~ s/\s+$//;		# Remove trailing spaces
	$args = quoteCurlyMask($args, ' ');	# Mask spaces inside quotes
	my @args = split(' ', $args);		# Split args
	@args = map { quoteCurlyUnmask($_, ' ') } @args;	# Needs to re-assign, otherwise quoteCurlyUnmask won't work
	map { quotesRemove(\$_) } @args;	# Remove quotes
	my $source = shift @args;
	if ($source =~ /^\.[\w\d]+$/) { # .xxx -> switchname.xxx
		$source = switchname($host_io) . $source;
	}
	if (defined $runPaths) { # @run processing
		$source .= '.run' if $source !~ /\./;
		# Determine where the desired run file is
		foreach my $path (@$runPaths) {
			if (-e "$path/$source") {
				$source = "$path/$source";
				last;
			}
		}
	}
	debugMsg(1,"-> Source input from file $source\n");
	if ($term_io->{SourceActive}->{file}->{$source}) {
		stopSourcing($db);
		return (0, "Cannot recursively source same file");
	}
	open(FILE, '<', $source) or do {
		return (0, "Cannot open input file \"$source\": $!");
	};
	my @cmdLines;
	while (<FILE>) {
		chomp;
		s/\x0d+$//g; # Remove trailing CRs (had this reading text files created on Solaris)
		s/^\s+//;    # Remove indentation, if any
		push( @cmdLines, $_);
	}
	close FILE;
	push( @cmdLines, "\x00file:".$source); # Encoded line to know when to clear $term_io->{SourceActive}->{file}->{$source}
	appendInputBuffer($db, 'source', \@cmdLines, 1) if @cmdLines;
	$term_io->{SourceActive}->{file}->{$source} = 1; # Make sure we don't source this file again, till we empty buffers
	debugMsg(4,"=readSourceFile setting SourceActive: file / ", \$source, "\n");
	# Clear out the save buffers
	$term_io->{SaveCharBuffer} = $term_io->{SaveCharPBuffer} = '';
	$term_io->{SaveSourceActive} = {};
	$term_io->{SaveEchoMode} = [];
	$term_io->{SaveSedDynPats} = [];
	$term_io->{SourceNoHist} = 1;	# Disable history
	# Clear positional arguments, if some were set
	foreach my $var (keys %{$vars}) {
		next unless $vars->{$var}->{argument}; # Only delete numerical keys and $*
		delete($vars->{$var});
	}
	# Check for extra arguments and this time set them afresh
	for my $i (0 .. $#args) {
		setvar($db, $i + 1 => $args[$i], argument => 1, nosave => 1);
	}
	setvar($db, '*' => join(' ', @args), argument => 1, nosave => 1);
	return (1, File::Spec->rel2abs($source));
}

1;
