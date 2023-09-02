# ACLI sub-module
package AcliPm::MaskUnmaskChars;
our $Version = "1.01";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(quoteCurlyMask quoteCurlyUnmask quoteSlashMask quoteSlashUnmask singleQuoteMask singleQuoteUnmask doubleQuoteMask doubleQuoteUnmask curlyMask curlyUnmask backslashMask backslashUnmask);
}
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::DebugMessage;


sub quoteCurlyMask { # Returns a new string where all occurrences of char(s) are replaced inside quoted (or curlies) sections with ASCII code OR 128
	my ($string, $char) = @_;
	my @chars = split(//, $char);
	map(s/([|!^\$\%{}\(\)])/\\$1/, @chars); # Characters which need backslashing; need to use substr below to get ascii value of last char
	my ($quote, $i);
	$string =~ s/(\".*?\"|\'.*?\'|\{.*?\}|\(.*?\)|\[.*?\])/$quote = $1; foreach $i (0..$#chars) {$quote =~ s!$chars[$i]!chr(ord(substr $chars[$i], -1)|128)!ge}; $quote/ge;
	debugMsg(256,"-> String double/single quotes and curlies masked for '$char' : $string\n");
	return $string;
}


sub quoteCurlyUnmask { # Restores all occurrences of char(s) inside quoted (or curlies) sections if these were previously masked with ASCII code OR 128
	my ($string, $char) = @_;
	my @chars = split(//, $char);
	my ($quote, $i);
	$string =~ s/(\".*?\"|\'.*?\'|\{.*?\}|\(.*?\)|\[.*?\])/$quote = $1; foreach $i (0..$#chars) {my $c = chr(ord($chars[$i])|128); $quote =~ s!$c!$chars[$i]!g}; $quote/ge;
	debugMsg(256,"-> String double/single quotes and curlies UN-masked for '$char' : $string\n");
	return $string;
}


sub quoteSlashMask { # Returns a new string where all occurrences of char(s) are replaced inside quoted (or //) sections with ASCII code OR 128
	my ($string, $char) = @_;
	my @chars = split(//, $char);
	map(s/([|!^\$\%{}\(\)])/\\$1/, @chars); # Characters which need backslashing; need to use substr below to get ascii value of last char
	my ($quote, $i);
	$string =~ s/(\".*?\"|\'.*?\'|\/.*?\/)/$quote = $1; foreach $i (0..$#chars) {$quote =~ s!$chars[$i]!chr(ord(substr $chars[$i], -1)|128)!ge}; $quote/ge;
	debugMsg(256,"-> String double/single quotes and slashes masked for '$char' : $string\n");
	return $string;
}


sub quoteSlashUnmask { # Restores all occurrences of char(s) inside quoted (or //) sections if these were previously masked with ASCII code OR 128
	my ($string, $char) = @_;
	my @chars = split(//, $char);
	my ($quote, $i);
	$string =~ s/(\".*?\"|\'.*?\'|\/.*?\/)/$quote = $1; foreach $i (0..$#chars) {my $c = chr(ord($chars[$i])|128); $quote =~ s!$c!$chars[$i]!g}; $quote/ge;
	debugMsg(256,"-> String double/single quotes and slashes UN-masked for '$char' : $string\n");
	return $string;
}


sub singleQuoteMask { # Returns a new string where all occurrences of char(s) are replaced inside single quoted sections with ASCII code OR 128
	my ($string, $char) = @_;
	my @chars = split(//, $char);
	map(s/([|!^\$\%{}\(\)])/\\$1/, @chars); # Characters which need backslashing; need to use substr below to get ascii value of last char
	my ($quote, $i);
	$string =~ s/(\'.*?\')/$quote = $1; foreach $i (0..$#chars) {$quote =~ s!$chars[$i]!chr(ord(substr $chars[$i], -1)|128)!ge}; $quote/ge;
	debugMsg(256,"-> String single-quotes masked for '$char' : $string\n");
	return $string;
}


sub singleQuoteUnmask { # Restores all occurrences of char(s) inside single quoted sections if these were previously masked with ASCII code OR 128
	my ($string, $char) = @_;
	my @chars = split(//, $char);
	my ($quote, $i);
	$string =~ s/(\'.*?\')/$quote = $1; foreach $i (0..$#chars) {my $c = chr(ord($chars[$i])|128); $quote =~ s!$c!$chars[$i]!g}; $quote/ge;
	debugMsg(256,"-> String single-quotes UN-masked for '$char' : $string\n");
	return $string;
}


sub doubleQuoteMask { # Returns a new string where all occurrences of char(s) are replaced inside double quoted sections with ASCII code OR 128
	my ($string, $char) = @_;
	my @chars = split(//, $char);
	map(s/([|!^\$\%{}\(\)])/\\$1/, @chars); # Characters which need backslashing; need to use substr below to get ascii value of last char
	my ($quote, $i);
	$string =~ s/(\".*?\")/$quote = $1; foreach $i (0..$#chars) {$quote =~ s!$chars[$i]!chr(ord(substr $chars[$i], -1)|128)!ge}; $quote/ge;
	debugMsg(256,"-> String double-quotes masked for '$char' : $string\n");
	return $string;
}


sub doubleQuoteUnmask { # Restores all occurrences of char(s) inside double quoted sections if these were previously masked with ASCII code OR 128
	my ($string, $char) = @_;
	my @chars = split(//, $char);
	my ($quote, $i);
	$string =~ s/(\".*?\")/$quote = $1; foreach $i (0..$#chars) {my $c = chr(ord($chars[$i])|128); $quote =~ s!$c!$chars[$i]!g}; $quote/ge;
	debugMsg(256,"-> String double-quotes UN-masked for '$char' : $string\n");
	return $string;
}


sub curlyMask { # Returns a new string where all occurrences of char(s) are replaced inside curlies with ASCII code OR 128
	my ($string, $char) = @_;
	my @chars = split(//, $char);
	map(s/([|!^\$\%{}\(\)])/\\$1/, @chars); # Characters which need backslashing; need to use substr below to get ascii value of last char
	my ($quote, $i);
	$string =~ s/(\{.*?\})/$quote = $1; foreach $i (0..$#chars) {$quote =~ s!$chars[$i]!chr(ord(substr $chars[$i], -1)|128)!ge}; $quote/ge;
	debugMsg(256,"-> String curly section masked for '$char' : $string\n");
	return $string;
}


sub curlyUnmask { # Restores all occurrences of char(s) inside curly sections if these were previously masked with ASCII code OR 128
	my ($string, $char) = @_;
	my @chars = split(//, $char);
	my ($quote, $i);
	$string =~ s/(\{.*?\})/$quote = $1; foreach $i (0..$#chars) {my $c = chr(ord($chars[$i])|128); $quote =~ s!$c!$chars[$i]!g}; $quote/ge;
	debugMsg(256,"-> String curly section UN-masked for '$char' : $string\n");
	return $string;
}


sub backslashMask { # Returns a new string where all backslashed occurrences of char(s) are replaced with ASCII code OR 128
	my ($string, $char) = @_;
	my @chars = split(//, $char);
	map(s/([|!^\$\%{}\(\)])/\\$1/, @chars); # Characters which need backslashing; need to use substr below to get ascii value of last char
	my $backs;
	foreach my $i (0..$#chars) {
		$string =~ s/\\$chars[$i]/$backs = "\\" . chr(ord(substr $chars[$i], -1)|128); $backs/ge;
	}
	debugMsg(256,"-> String backslash masked for '$char' : $string\n");
	return $string;
}


sub backslashUnmask { # Restores all occurrences of char(s) behind a backslash, if these were previously masked with ASCII code OR 128
	my ($string, $char, $removeBackslash) = @_;
	my @chars = split(//, $char);
	my $backslash = $removeBackslash ? '' : "\\";
	my $backs;
	foreach my $i (0..$#chars) {
		my $c = chr(ord($chars[$i])|128);
		$string =~ s/\\$c/$backs = $backslash . $chars[$i]; $backs/ge;
	}
	debugMsg(256,"-> String backslash UN-masked for '$char'" . ($removeBackslash ? ' (with delete)' : '') . " : $string\n");
	return $string;
}

1;
