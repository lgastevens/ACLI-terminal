#!/usr/bin/perl
# Written by Ludovico Stevens (lstevens@extremenetworks.com)
my $Version = "2.00";

use strict;
use warnings;

my @EctMasks = ('00','ff','88','77','44','33','cc','bb','22','11','66','55','aa','99','dd','ee');

sub prompt { # For interactive testing to prompt user
	my $varRef = shift;
	my $message = shift;
	my $default = shift;
	my $userInput;
	print $message;
	print "[default = ", $default, "]" if $default;
	print " :";
	chomp($$varRef = <STDIN>);
	unless ($$varRef) {
		if (defined $default) {
			$$varRef = $default;
			return;
		}
	}
}

sub by_pathid { # shortest then lowest pathid wins
	length($a) == length($b) ? $a cmp $b : length($a) <=> length($b)
}

sub chosenPath { # Given a list of pathids, returns the chosen one
	my @path = @_;
	my %pathList;

	for my $i (1 .. $#path+1) {
		$pathList{join('', @{$path[$i-1]})} = $i;
	}
	return $pathList{(sort by_pathid keys %pathList)[0]};
}


MAIN:{
	my ($numberPaths, $numberBVIDs, @pathList, @pathIDs, @bvidPath, @pathBvid);

	prompt(\$numberPaths, "Specify number of paths to compare", 2);
	prompt(\$numberBVIDs, "Specify number of BVLANs in use", 2);
	for my $i (1 .. $numberPaths){
		prompt(\$pathList[$i-1], "Comma separated list of nodes on path $i");
		push(@{$pathIDs[$i-1]}, split(',',$pathList[$i-1]));
		foreach my $bid (@{$pathIDs[$i-1]}) {
			if ($bid !~ /^[\da-fA-F]+$/) {
				print "This is not a valid hex value : ", $bid;
				exit;
			}
		}
	}

	print "\nLexicographic ordering done AFTER applying ECT Masks\n====================================================\n";
	for my $v (1 .. $numberBVIDs){
		print "\n Processing for BVLAN", $v, ", after applying ECT Mask ", $EctMasks[$v-1], "\n";

		my @xorPath;
		for my $i (1 .. $numberPaths){
			@{$xorPath[$i-1]} = map {sprintf("%02x", hex($_) ^ hex($EctMasks[$v-1]))} @{$pathIDs[$i-1]};
			print "		XORed Path $i : ", join(',', @{$xorPath[$i-1]}), "\n";
		}

		my @sortIDs;
		for my $i (1 .. $numberPaths){
			@{$sortIDs[$i-1]} = sort @{$xorPath[$i-1]}; # Lexicographic sorting
		}

		$bvidPath[$v] = chosenPath(@sortIDs);
		push(@{$pathBvid[$bvidPath[$v]]}, $v);
		for my $i (1 .. $numberPaths){
			print "		Sorted XORed Path $i : ", join(',', @{$sortIDs[$i-1]});
			print " <-- chosen" if $i == $bvidPath[$v];
			print "\n";
		}
	}

	print "\nSUMMARY\n=======\n";
	for my $i (1 .. $numberPaths){
		print "	Path $i used by BVIDs: ";
		print join(',', @{$pathBvid[$i]}) if defined $pathBvid[$i];
		print "\n";
	}
}
