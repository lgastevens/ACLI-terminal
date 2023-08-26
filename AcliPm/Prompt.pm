# ACLI sub-module
package AcliPm::Prompt;
our $Version = "1.02";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(lastLine checkFragPrompt checkForPrompt switchname appendPrompt echoPrompt setPromptSuffix);
}
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::ChangeMode;
use AcliPm::DebugMessage;
use AcliPm::GlobalConstants;
use AcliPm::GlobalDefaults;


sub lastLine { # If string ref does not end with \n, returns the last line (unlike Control::CLI's stripLastLine does not strip it from string ref provided)
	my $dataRef = shift;
	$$dataRef =~ /(.*)\z/;
	return defined $1 ? $1 : '';
}

sub checkFragPrompt { # Takes into account fragment cache and paced chars sent for checking presence of prompt
	my ($db, $outRef) = @_;
	my $mode = $db->[0];
	my $term_io = $db->[2];
	my $host_io = $db->[3];
	my $prompt = $db->[7];
	my $termbuf = $db->[8];

	my ($lastLine, $charsSent, $charsMatch, $charsOutstanding);

	#Clear fragment cache if newlines in buffer
	$host_io->{FragmentCache} = '' if $$outRef =~ /[\n\x0d]/;

	# Come out if we don't have a line not ending with \n
	$lastLine = lastLine($outRef);
	return 0 unless length $lastLine;

	# Update fragmentCache if necessary
	$host_io->{FragmentCache} .= $lastLine;
	debugMsg(2,"=FragmentCache1:>", \$host_io->{FragmentCache}, "<\n") unless defined $term_io->{DelayPrompt} && !$term_io->{DelayPromptDF};

	if (length $host_io->{PacedSentChars}) {
		$charsSent = $host_io->{PacedSentChars};
		$charsOutstanding = '';
		while (length $charsSent) { # Some chars were sent, they might appear after prompt
			$charsMatch = quotemeta($charsSent);
			last if $prompt->{Match} =~ / $/ && $charsSent eq ' '; # Don't strip single space, if prompt regex expects a trailing space
			last if $host_io->{FragmentCache} =~ s/$charsMatch$//; # We strip them
			$charsOutstanding = chop($charsSent) . $charsOutstanding;
		}
		debugMsg(2,"FragmentCache2:>", \$host_io->{FragmentCache}, "<\n");
	}

	if ($host_io->{FragmentCache} =~ /$prompt->{Regex}/) {
		$host_io->{Prompt} = $1;
		$host_io->{FragmentCache} = '';
		if (length $charsSent) { # Populate the term buffer
			($termbuf->{Linebuf1} = $charsSent) =~ s/^\s+//; # Without any spaces in front
			($termbuf->{Bufback1} = $termbuf->{Linebuf1}) =~ s/./\cH/g;
			debugMsg(2,"PacedSentChars - stripped >$charsSent< / retained >$charsOutstanding<\n");
			debugMsg(2,"FragmentCache3:>", \$host_io->{FragmentCache}, "<\n");
			$$outRef =~ s/$charsMatch$//; # Need to strip it off outref also
			$host_io->{BackspaceCount} = length $host_io->{PacedSentChars};	# Number of backspaces we expect, after CTRL-U; includes both charsSent & charsOutstanding
			debugMsg(2,"BackspaceCount:>", \$host_io->{BackspaceCount}, "<\n");
			$host_io->{PacedSentPendng} = length $charsOutstanding;
			debugMsg(2,"PacedSentPendng:>", \$host_io->{PacedSentPendng}, "<\n");
			$host_io->{PacedSentChars} = $charsOutstanding;
			$host_io->{SendBuffer} .= $CTRL_U; # And remove it from device's buffer
			changeMode($mode, {dev_del => 'bs'}, '#311');
		}
		return 1;
	}
	else {
		$host_io->{FragmentCache} .= $charsSent if length $charsSent; # What chars we stripped above we re-add here
		return 0;
	}
}


sub checkForPrompt { # Matches output reference for presence of a prompt without changing buffer contents
	my ($host_io, $outRef, $prompt) = @_;
	my ($lastLine, $charsSent);

	return 0 unless length $$outRef;
	return 0 unless $lastLine = lastLine($outRef); # Need a line not ending with \n

	$charsSent = $host_io->{PacedSentChars};
	while (length $charsSent) { # Some chars were sent, they might appear after prompt
		last if $prompt->{Match} =~ / $/ && $charsSent eq ' '; # Don't strip single space, if prompt regex expects a trailing space
		last if $lastLine =~ s/\Q$charsSent\E$//; # We stripped them
		chop $charsSent;
	}
	debugMsg(2,"=checkForPrompt on lastLine: >", \$lastLine, "<\n");
	return $lastLine =~ /$prompt->{Regex}/ ? 1 : 0;
}


sub switchname { # Extract switchname from prompt and ensure resulting name can be used as a filename, with none of these: /\:*?"<>|
	my $host_io = shift;
	my $switchName;

	if (defined $host_io->{Sysname}) { # On Standby CPUs this will not be defined...
		$switchName = $host_io->{Sysname};
	}
	else {
		$switchName = $host_io->{Prompt};
		# As we now use $host_io->{Sysname}, below code is probably useless... as we would only come here on PassportERS Standby CPU...
		$switchName =~ s/^(?:@|(?:! )?(?:\* )?(?:\([^\)]+\) )?)?([^\(<>#:]+)[\(<>#:].*$/$1/; # ((Software Update Required) X460G2-2.8 #% -> X460G2-2.8 / ! Slot-1 VPEX X670G2-3.19 #% -> Slot-1 VPEX X670G2-3.19)
		if ($host_io->{Type} eq 'ExtremeXOS') {
			$switchName =~ s/^Slot-\d+\s*//;			 # 		(Slot-1 X460-Stack.7 -> X460-Stack.7)
			$switchName =~ s/^VPEX\s*//;				 # 		(VPEX X670G2-3.19 -> X670G2-3.19)
			$switchName =~ s/\.\d+\s*$//;				 # 		(X460-Stack.7  -> X460-Stack)
		}
	}
	$switchName =~ s/[\/\\\:\*\?\"\<\>\|]/_/g; # Characters not allowed in filenames, replace with underscore
	return $switchName;
}


sub appendPrompt { # Returns an offline prompt of the connected device, based on last prompt seen from it
	my ($host_io, $term_io) = @_;
	my $prompt = $host_io->{Prompt};
	$prompt =~ s/ ?$/$term_io->{LtPromptSuffix}/ if $term_io->{LtPrompt};
	return $prompt;
}


sub echoPrompt { # Prepare the echo prompt
	my ($term_io, $prompt, $echoPrompt) = @_;
	my $promptLength = length($prompt);
	return sprintf("%${promptLength}s", $echoPrompt . $term_io->{LtPromptSuffix});
}


sub setPromptSuffix { # Updates the $term_io->{LtPromptSuffix}
	my $db = shift;
	my $term_io = $db->[2];
	my $socket_io = $db->[6];
	$term_io->{LtPromptSuffix} = join('', 
		(defined $term_io->{Dictionary} ? '{'.$term_io->{Dictionary}.'}' : ''),
		(defined $socket_io->{Tie} ? '['.$socket_io->{Tie}.']' : ''),
		$Default{prompt_suffix_str}
	);
}


1;
