# ACLI sub-module
package AcliPm::GlobalConstants;
our $Version = "1.02";

use strict;
use warnings;
use File::Spec;
use File::Basename ();


#############################
# GLOBAL CONSTANT VARIABLES #
#############################
# do not edit:
our ($ScriptName, $ScriptDir) = File::Basename::fileparse(File::Spec->rel2abs($0));
our $AcliUsername = getlogin || getpwuid($<);
our $CTRL_A	= "\cA"; # Input ==> go beginning of line
our $CTRL_B	= "\cB"; # Input alternative to $CrsrLeft
our $CTRL_C	= "\cC"; # Input ==> abort line with new prompt
our $CTRL_D	= "\cD"; # Input alternative to $Delete / ==> Overridden for Debug
our $CTRL_E	= "\cE"; # Input ==> go end of line
our $CTRL_F	= "\cF"; # Input alternative to $CrsrRight
our $CTRL_G	= "\cG"; # Bell
our $CTRL_H	= "\cH"; # Input alternative to $BackSpace
our $CTRL_I	= "\cI";
our $CTRL_J	= "\cJ";
our $CTRL_K	= "\cK"; # Input ==> redisplay line (same as $CTRL_R)
our $CTRL_L	= "\cL"; # Input ==> clear screen
our $CTRL_M	= "\cM";
our $CTRL_N	= "\cN"; # Input alternative to $CrsrDown
our $CTRL_O	= "\cO";
our $CTRL_P	= "\cP"; # Input alternative to $CrsrUp / ==> Toggle more paging
our $CTRL_Q	= "\cQ"; # Input ==> quit script
our $CTRL_R	= "\cR"; # Input ==> redisplay line (same as $CTRL_K)
our $CTRL_S	= "\cS"; # Input ==> send break signal
our $CTRL_T	= "\cT"; # Input ==> toggle between transparent & interact modes
our $CTRL_U	= "\cU"; # Input ==> abort line without new prompt
our $CTRL_V	= "\cV";
our $CTRL_W	= "\cW"; # Input ==> delete word left of cursor
our $CTRL_X	= "\cX"; # Input ==> delete all chars left of cursor
our $CTRL_Y	= "\cY";
our $CTRL_Z	= "\cZ";
our $Bell	= $CTRL_G;
our $Escape	= "\e";
our $CrsrUp	= "\e\x5b\x41";
our $CrsrDown	= "\e\x5b\x42";
our $CrsrRight	= "\e\x5b\x43";
our $CrsrLeft	= "\e\x5b\x44";
our $Delete	= "\x7f";
our $BackSpace	= "\x08";
our $Return	= "\n";
our $Space	= " ";
our $Tab	= "	";
our $CarrReturn	= "\x0d";
our $LineFeed	= "\x0a";



sub import { # Want to import all above variables into main context
	no strict 'refs';
	my $caller = caller;

	while (my ($name, $symbol) = each %{__PACKAGE__ . '::'}) {
		next if      $name eq 'BEGIN';   # don't export BEGIN blocks
		next if      $name eq 'import';  # don't export this sub
		next if      $name eq 'Version'; # don't export this package version
		#printf "Name = %s  /  Symbol = %s\n", $name,$symbol;
		my $imported = $caller . '::' . $name;
		*{ $imported } = \*{ $symbol };
	}
}

1;
