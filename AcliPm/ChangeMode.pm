# ACLI sub-module
package AcliPm::ChangeMode;
our $Version = "1.01";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(changeMode);
}
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::DebugMessage;


sub changeMode { # Change main operational mode flags
	my ($curMode, $newMode, $debugContext) = @_;

	$debugContext .= " /" if $::Debug;
	foreach my $hdl ('term_in', 'dev_inp', 'dev_del', 'dev_fct', 'dev_cch', 'dev_out', 'buf_out') {
		$debugContext .= "  $hdl:$curMode->{$hdl}" if $::Debug;
		if ($newMode->{$hdl} && $newMode->{$hdl} ne $curMode->{$hdl}) {
			$curMode->{$hdl} = $newMode->{$hdl};
			$debugContext .= "=>$newMode->{$hdl}" if $::Debug;
		}
	}
	debugMsg(1,"(".(caller 1)[3].")-> $debugContext\n") if $::Debug;
}

1;
