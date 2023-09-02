#!/bin/perl
#
$Version = "2.3";
#
# Written by Ludovico Stevens (lstevens@extremenetworks.com)
#
# Grep, which I can use on DOS..
#
# 1.0	- Initial version
# 1.1	- Some cleanup...
# 2.0	- Enhanced to take wild cards
#	  Ported debug function from log.pl
# 2.1	- Now can also grep output from STDIN, so can be piped to
# 2.2	- Switched to bsd_glob due to warnings: File::Glob::glob() will disappear in perl 5.30. Use File::Glob::bsd_glob() instead.
# 2.3	- Using /^pat/ only works if pattern entered quoted "/^pat/"; added a debug line and updated syntax
#
# Syntax:
#
# grep.pl [-iv] "pattern"|/pattern/ [<file or wildcard>] [<2nd file>] [<3rd file>] [...]
#

#############################
# STANDARD MODULES          #
#############################

use Getopt::Std;
use File::Basename;
use File::Glob ':bsd_glob';

############################
# GLOBAL VARIABLES         #
############################

$Greppl = basename($0);


#############################
# FUNCTIONS                 #
#############################


sub printSyntax {
	print "$Greppl version $Version".($debug ? " running on $^O" : "")."\n";
	print "\nUsage: $greppl [-iv] \"pattern\" [<file or wildcard>] [<2nd file>] [<3rd file>] [...]\n\n";
	print "	-i: Case insensitive pattern match\n";
	print "	-v: Return non matching lines\n\n";
	print "	Pattern syntax for logical operators:\n";
	print "	 <str1>and<str2> = \"<str1>&<str2>\"\n";
	print "	 <str1>or<str2>  = \"<str1>|<str2>\"\n";
	print "	Alternatively, use standard perl pattern match: \"/pattern/\"\n\n";
	exit 1;
}


sub debugMsg {
	if ($debug && shift() <= $debug) {
		print shift;
	}
}

sub exitError {
	print "\n$Greppl: ",shift(),"\n";
	exit 1;
}


sub formatPat {
	my $pat = shift;
	my $i = "i" if $opt_i;
	debugMsg(1,"Pattern entered :$pat\n");

	if ($pat !~ /^\/.+\/i*$/) { #if pattern entered in short format, reformat it
		debugMsg(2,"Entered pattern			:$pat\n");
		$pat =~ s/([\\\/\(\)\[\{\^\$\*\+\?\.])/\\$1/g;
		debugMsg(2,"Special chars back-slashed	:$pat\n");
		$pat =~ s/\|/\/$i||\//g;
		debugMsg(2,"Or| replaced with \||\		:$pat\n");
		$pat =~ s/\&/\/$i&&\//g;
		debugMsg(2,"And& replaced with \&&\		:$pat\n");
		$pat = join('', "/", $pat, "/", $i);
	}
	debugMsg(1,"Final pattern match to use	:$pat\n");

	return $pat;
}


sub grepFile {
	my ($file, $pattern, $prependFilename) = @_;
	$prependFilename &&= $prependFilename.": ";

	unless ( open(FILE, $file) ) {
		print "Cannot open file \"$file\": $!\n";
		return;
	}

	while (<FILE>) {
		if ($opt_v) {
			(not eval ($pattern)) && print "$prependFilename$_";
		}
		else {
			eval ($pattern) && print "$prependFilename$_";
		}
	}
	close FILE;
}

sub grepStdIn {
	my $pattern = shift;

	while (<STDIN>) {
		my $done = s/\cZ$//;
		if ($opt_v) {
			(not eval ($pattern)) && print;
		}
		else {
			eval ($pattern) && print;
		}
		last if $done;
	}
}


#############################
# MAIN                      #
#############################

my @file, $fileglob, $file;

getopts('d12iv');

if ($opt_d) {
	$debug = 1; # Default debug level
	$debug = 1 if ($opt_1);
	$debug = 2 if ($opt_2);
}

printSyntax unless @ARGV;

my $pattern = formatPat(shift(@ARGV));

if (scalar @ARGV > 1) { # Multiple filenames (no wildcard)
	@file = @ARGV;
	debugMsg(1,"Multiple files; no wildcard\n");
}
elsif (scalar @ARGV == 1) { # Single filename or wildcard
	if ( ($fileglob = $ARGV[0]) =~ /[\*?\[\]]/) { # Wildcard
		debugMsg(1,"Wildcard = $fileglob\n");
		@file = bsd_glob("$fileglob");
		unless (@file) { exitError "No files found matching \"$fileglob\"" }
		foreach $file (@file) {
			debugMsg(1,"Globbed file = $file\n");
		}
	}
	else { # Single filename (no wildcard)
		$file = $ARGV[0];
		debugMsg(1,"Sinlge file = $file\n\n");
		grepFile($file, $pattern);
	}
	if (@file) { # We have more than one file or input was a wildcard
		foreach $file (@file) {
			grepFile($file, $pattern, basename($file));
		}
	}
}
else { # No files, read and grep from STDIN
	grepStdIn($pattern);
}

exit;