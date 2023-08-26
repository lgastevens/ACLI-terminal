# ACLI sub-module
package AcliPm::QuotesRemove;
our $Version = "1.00";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(quotesRemove listQuotesRemove);
}
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::MaskUnmaskChars;


sub quotesRemove { # Remove quotes from argument; if scalar supplied, scalar without quotes returned; if ref supplied, remove quotes but only return flag
	my ($string, $quoteMeta) = @_;
	my $quotesRemovedFlag = 0;
	return unless defined $string;
	if (ref $string) {
		if ($quoteMeta) {
			$quotesRemovedFlag = 1 if $$string =~ s/^'([^']*)'$/quotemeta($1)/e;	# Remove ' quotes & quotemeta string
		}
		else {
			$quotesRemovedFlag = 1 if $$string =~ s/^'([^']*)'$/$1/;	# Remove ' quotes
		}
		$quotesRemovedFlag = 1 if $$string =~ s/^"([^"]*)"$/$1/;	# Remove " quotes
		return $quotesRemovedFlag;
	}
	else {
		if ($quoteMeta) {
			$string =~ s/^'([^']*)'$/quotemeta($1)/e;	# Remove ' quotes & quotemeta string
		}
		else {
			$string =~ s/^'([^']*)'$/$1/;	# Remove ' quotes
		}
		$string =~ s/^"([^"]*)"$/$1/;	# Remove " quotes
		return $string;
	}
}


sub listQuotesRemove { # Remove quotes from any comma separated argument in a comma separated string list; return flag if quotes were removed
	my $stringRef = shift;
	my $stringOrig = $$stringRef;
	$$stringRef = join(',', map(quotesRemove($_, 1), split(',', quoteCurlyMask($stringOrig, ','))) );
	return $stringOrig ne $$stringRef;
}

1;
