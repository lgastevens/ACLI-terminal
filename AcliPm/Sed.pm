# ACLI sub-module
package AcliPm::Sed;
our $Version = "1.02";

use strict;
use warnings;
use re 'eval'; # required for use of regex code assertions potentially used in @sed: https://stackoverflow.com/questions/16320545/how-to-eval-regular-expression-with-embedded-perl-code
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(loadSedFile returnHLstrings setHLstrings displayColourConfig validateQrPattern sedPatternReplace popSedScriptPats addSedScriptPats);
}
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::DebugMessage;
use AcliPm::GlobalDefaults;
use AcliPm::QuotesRemove;
use AcliPm::Print;


my %Hlcolours	= (black => 0, red => 1, green => 2, yellow => 3, blue => 4, magenta => 5, cyan => 6, white => 7, disable => undef, none => undef);


sub loadSedFile { # Reads in acli.sed file, if one exists
	my $db = shift;
	my $term_io = $db->[2];
	my $sedFile;

	# Determine which acli.sed file to work with
	foreach my $path (@AcliFilePath) {
		if (-e "$path/$SedFileName") {
			$sedFile = "$path/$SedFileName";
			last;
		}
	}
	return unless defined $sedFile;
	$term_io->{SedFile} = File::Spec->canonpath($sedFile);
	cmdMessage($db, "Loading sed file: " . File::Spec->rel2abs($sedFile) . "\n");
	open(SED, '<', $sedFile) or do {
		cmdMessage($db, "Unable to open sed file " . File::Spec->canonpath($sedFile) . "\n");
		return;
	};
	my $lineNumber = 0;
	my ($inputSedId, $outputSedId, $colourSedId) = (1,1,1);
	my ($inputSedMaxId, $outputSedMaxId, $colourSedMaxId) = (1,1,1);
	my @categories = ('global');
	while (<SED>) {
		chomp;
		$lineNumber++;
		next if /^\s*$/; # skip empty lines
		next if /^\s*#/; # skip comment lines
		/^\s*colour\s+(\S+)\s+(.+)$/ && do {
			my ($profile, $data) = (quotesRemove($1), $2);
			if ($profile =~ /^\w+$/) { # Valid profile name
				my %colourHash;
				$colourHash{$1} = $2 if $data =~ s/(foreground)\s+(black|blue|cyan|green|magenta|red|white|yellow)//;
				$colourHash{$1} = $2 if $data =~ s/(background)\s+(black|blue|cyan|green|magenta|red|white|yellow)//;
				$colourHash{$1} = 1 if $data =~ s/(bright)//;
				$colourHash{$1} = 1 if $data =~ s/(reverse)//;
				$colourHash{$1} = 1 if $data =~ s/(underline)//;
				$data =~ s/\s+//g; # Remove all spaces left
				unless (length $data) {
					$term_io->{ColourProfiles}->{$profile} = \%colourHash;
					next;
				}
			}
			# Any problem, fall through and report syntax error
		};
		/^\s*category\s+(\S.*)$/ && do {
			@categories = split(',', $1);
			map(s/^\s*(\S+)\s*$/$1/, @categories); # Remove spaces
			if ($#categories && grep($_ eq 'global', @categories) ) { # More than 1 category listed and global listed
				print File::Spec->canonpath($sedFile), " cannot list 'global' with family type category list at line ", $lineNumber, "\n";
				@categories = grep($_ ne 'global', @categories);
			}
			next;
		};
		/^\s*start-id\s*=\s*(\d+)\s*$/ && !%{$term_io->{SedInputPats}} && !%{$term_io->{SedOutputPats}} && !%{$term_io->{SedColourPats}} && do {
			$inputSedId = $outputSedId = $colourSedId = $inputSedMaxId = $outputSedMaxId = $colourSedMaxId = $1;
			next;
		};
		/^\s*max-id\s*=\s*(\d+)\s*$/ && do {
			$MaxSedPatterns = $1; # We allow override to default value
			next;
		};
		/\s*input\s+(?|"([^\"]+)"|'([^\']+)')\s+(?:(?|"([^\"]*)"|'([^\']*)')|\{(.+)\})\s*(?:$|\#)/ && do {
			my ($pattern, $replace, $code) = ($1, $2, $3);
			if ($inputSedMaxId > $MaxSedPatterns) {
				print File::Spec->canonpath($sedFile), " exhausted Max Sed input patterns = $MaxSedPatterns\n";
			}
			else {
				my ($qrPattern, $message) = validateQrPattern($pattern);
				if ($message) {
					print File::Spec->canonpath($sedFile), " invalid regular expression: ", $message;
				}
				else {
					my ($replfmt, $replaceSub);
					$inputSedMaxId++;
					if (defined $code) {
						$replaceSub = sub { eval $code };
					}
					else {
						($replfmt = $replace) =~ s/\"/\\"/g; #";
					}
					foreach my $category (@categories) {
						my $cat = $category eq 'global' ? undef : $category;
						if (defined $code) {
							$term_io->{SedInputPats}->{$inputSedId++} = [$cat, $pattern, $qrPattern, $code, $replaceSub];
						}
						else {
							$term_io->{SedInputPats}->{$inputSedId++} = [$cat, $pattern, $qrPattern, $replace, qq{"$replfmt"}, 1];
						}
					}
					next;
				}
			}
		};
		/\s*(?:output\s+)?(?|"([^\"]+)"|'([^\']+)')\s+(?:(?|"([^\"]*)"|'([^\']*)')|\{(.+)\})\s*(?:$|\#)/ && do {
			my ($pattern, $replace, $code) = ($1, $2, $3);
			if ($outputSedMaxId > $MaxSedPatterns) {
				print File::Spec->canonpath($sedFile), " exhausted Max Sed output patterns = $MaxSedPatterns\n";
			}
			else {
				my ($qrPattern, $message) = validateQrPattern($pattern);
				if ($message) {
					print File::Spec->canonpath($sedFile), " invalid regular expression: ", $message;
				}
				else {
					my ($replfmt, $replaceSub);
					$outputSedMaxId++;
					if (defined $code) {
						$replaceSub = sub { eval $code };
					}
					else {
						($replfmt = $replace) =~ s/\"/\\"/g; #";
					}
					foreach my $category (@categories) {
						my $cat = $category eq 'global' ? undef : $category;
						if (defined $code) {
							$term_io->{SedOutputPats}->{$outputSedId++} = [$cat, $pattern, $qrPattern, $code, $replaceSub];
						}
						else {
							$term_io->{SedOutputPats}->{$outputSedId++} = [$cat, $pattern, $qrPattern, $replace, qq{"$replfmt"}, 1];
						}
					}
					next;
				}
			}
		};
		/\s*(?:output\s+)?(?|"([^\"]+)"|'([^\']+)')\s+colour\s+(?|"([^\"]+)"|'([^\']+)'|(\w+))\s*(?:$|\#)/ && do {
			my ($pattern, $profile) = ($1, $2);
			if ($colourSedMaxId > $MaxSedPatterns) {
				print File::Spec->canonpath($sedFile), " exhausted Max Sed output colour patterns = $MaxSedPatterns\n";
			}
			elsif (!defined $term_io->{ColourProfiles}->{$profile}) {
				print File::Spec->canonpath($sedFile), " colour profile '$profile' not defined\n";
			}
			else {
				my ($qrPattern, $message) = validateQrPattern($pattern);
				if ($message) {
					print File::Spec->canonpath($sedFile), " invalid regular expression: ", $message;
				}
				else {
					my ($hlOn, $hlOff) = returnHLstrings($term_io->{ColourProfiles}->{$profile});
					my $replace = $hlOn . '$&' . $hlOff;
					$colourSedMaxId++;
					foreach my $category (@categories) {
						my $cat = $category eq 'global' ? undef : $category;
						$term_io->{SedColourPats}->{$colourSedId++} = [$cat, $pattern, $qrPattern, $replace, qq{"$replace"}, $profile];
					}
					next;
				}
			}
		};
		print File::Spec->canonpath($sedFile), " syntax error on line ", $lineNumber, "\n";
	}
	close SED;
	return 1;
}


sub returnHLstrings { # Returns a 2 element array with escape sequece to start the colouring and stop the colouring
	my $colourHashRef = shift;
	my ($hlOn, $hlOff) = ('', '');
	# Start highlight string
	$hlOn .= "\e[1m" if $colourHashRef->{bright};
	$hlOn .= "\e[4m" if $colourHashRef->{underline};
	$hlOn .= "\e[7m" if $colourHashRef->{reverse};
	$hlOn .= "\e[3" . $Hlcolours{$colourHashRef->{foreground}} . "m" if defined $colourHashRef->{foreground};
	$hlOn .= "\e[4" . $Hlcolours{$colourHashRef->{background}} . "m" if defined $colourHashRef->{background};
	# End highlight string
	$hlOff .= "\e[49m" if defined $colourHashRef->{background};
	$hlOff .= "\e[39m" if defined $colourHashRef->{foreground};
	$hlOff .= "\e[0m" if $colourHashRef->{bright} || $colourHashRef->{underline} || $colourHashRef->{reverse};
	return ($hlOn, $hlOff);
}

sub setHLstrings { # Initialize $term_io HLon & HLoff keys
	my $term_io = shift;
	$term_io->{HLfgcolour} = undef if defined $term_io->{HLfgcolour} && $term_io->{HLfgcolour} eq 'disable';
	$term_io->{HLbgcolour} = undef if defined $term_io->{HLbgcolour} && $term_io->{HLbgcolour} eq 'disable';
	($term_io->{HLon}, $term_io->{HLoff}) = returnHLstrings(
		{
			foreground	=> $term_io->{HLfgcolour},
			background	=> $term_io->{HLbgcolour},
			bright		=> $term_io->{HLbright},
			underline	=> $term_io->{HLunderline},
			reverse		=> $term_io->{HLreverse},
		}
	);
	$term_io->{HLon} = "\e[49m\e[39m\e[0m" . $term_io->{HLon}; # Wipe out any pre-existing sed re-colouring
}


sub displayColourConfig { # Generates a printable colour config for @sed colour info
	my $colourHashRef = shift;
	my $string;
	$string .= "foreground = " . (defined $colourHashRef->{foreground} ? $colourHashRef->{foreground} : 'none');
	$string .= ", background = " . (defined $colourHashRef->{background} ? $colourHashRef->{background} : 'none');
	$string .= ", bright" if $colourHashRef->{bright};
	$string .= ", reverse" if $colourHashRef->{reverse};
	$string .= ", underline" if $colourHashRef->{underline};
	$string .= sprintf(" : %sSAMPLE%s", returnHLstrings($colourHashRef));
	return $string;
}


sub validateQrPattern { # Error checking on @sed regex patterns
	my $pattern = shift;
	my $qrPattern;
	eval {
		local $SIG{__WARN__} = sub { die shift }; # Turn every warning into an exception
		$qrPattern = qr/$pattern/;
	};
	if ($@) {
		(my $message = $@) =~s/;.*$//;
		$message =~ s/ at .+ line .+$//; # Delete file & line number info
		return (undef, $message);
	}
	return ($qrPattern);
}


sub sedPatternReplace { # Given a line of text (could be input or output) applies the relevant sed replacement patterns
	my ($host_io, $patHash, $lineRef) = @_;
	return unless %$patHash;
	no warnings;
	for my $idx (sort {$a <=> $b} keys %$patHash) {
		next if defined $patHash->{$idx}->[0] && $patHash->{$idx}->[0] ne $host_io->{Type};
		if ($patHash->{$idx}->[5]) { # Replace string
			# https://www.perlmonks.org/?node_id=234769
			if ($$lineRef =~ s/$patHash->{$idx}->[2]/$patHash->{$idx}->[4]/mgee) {
				debugMsg(1, "sedPatternReplace after pattern $idx :\n>", $lineRef, "<\n");
			}
		}
		else { # Execute code
			eval {
				local $SIG{__WARN__} = sub { die shift }; # Turn every warning into an exception
				if ($$lineRef =~ s/$patHash->{$idx}->[2]/&{$patHash->{$idx}->[4]}/mge) {
					debugMsg(1, "sedPatternReplace after pattern $idx :\n>", $lineRef, "<\n");
				}
			};
		}
	}
}


sub popSedScriptPats { # Clears and returns the dynamic SED patterns (above $MaxSedPatterns id)
	my $term_io = shift;
	my @patList;
	for my $patHash ($term_io->{SedInputPats}, $term_io->{SedOutputPats}, $term_io->{SedColourPats}) {
		my @list;
		my $idx = $MaxSedPatterns + 1;
		while (defined $patHash->{$idx}) {
			push(@list, $patHash->{$idx});
			delete $patHash->{$idx++};
		}
		push(@patList, \@list);
	}
	return \@patList;
}


sub addSedScriptPats { # Re-adds dynamic SED patterns (above $MaxSedPatterns id)
	my ($term_io, $patList) = @_;
	return unless @$patList;
	for my $patHash ($term_io->{SedInputPats}, $term_io->{SedOutputPats}, $term_io->{SedColourPats}) {
		my $listRef = shift(@$patList);
		next unless @$listRef;
		my $idx = (sort { $a <=> $b } keys %$patHash)[-1] + 1; # Next unused index number
		$idx = $MaxSedPatterns + 1 if $idx <= $MaxSedPatterns; # Starting from $MaxSedPatterns + 1
		for my $pat (@$listRef) {
			$patHash->{$idx++} = $pat;
		}
	}
}

1;
