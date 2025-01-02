#!/usr/bin/perl

our $Version = "5.12";
our $Debug = 0;	# Bit values: 1024=printOut 512=loadAliasFile 256=tabExpand/quoteCurlyBackslashMask 128=historyDump 64=Errmode-Die 32=Errmode-Croak 16=ControlCLI(Serial) 8=ControlCLI 4=Input 2=output 1=basic
BEGIN {	our $Sub = ''; } # Load all AcliPm modules from a subdirectory

#
# Written by Ludovico Stevens (lstevens@extremenetworks.com)
#

use strict;
use warnings;
#use 5.010; # was required for state declaration in readKeyPress (now moved to Acli sub-module); actually Perl::MinimumVersion says this script requires 5.013002 because of use of s///r
#             but use of anything greater than 5.011 adds in Perl Unicode features which means \w regex matches a lot more stuff beyond standard ASCII; too risky a change here

#############################
# STANDARD MODULES          #
#############################

use Cwd;
use File::Spec;
use File::Glob ':bsd_glob';
use Getopt::Std;
use Term::ReadKey;
use Time::HiRes;

if ($^O eq "MSWin32") {
	# This is for suppressing windows message about Perl Interpreter stopped working, when closing Window
	unless (eval "require Win32API::File") { die "Cannot find module Win32API::File" }
	Win32API::File::SetErrorMode(2);

	# This is for being able to print correctly vt100 terminal escape chars, when in transparent mode
	unless (eval "require Win32::Console::ANSI") { die "Cannot find module Win32::Console::ANSI" }
}

#############################
# ACLI LOCAL MODULES        #
#############################

use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::Alias;
use AcliPm::CacheFeedInputs;
use AcliPm::ChangeMode;
use AcliPm::CommandProcessing;
use AcliPm::ConnectDisconnect;
use AcliPm::DebugMessage;
use AcliPm::ExitHandlers;
use AcliPm::GlobalConstants;
use AcliPm::GlobalDefaults;
use AcliPm::GlobalDeviceSettings;
use AcliPm::HandleBufferedOutput;
use AcliPm::HandleDeviceOutput;
use AcliPm::HandleDevicePeerCP;
use AcliPm::HandleDeviceSend;
use AcliPm::HandleTerminalInput;
use AcliPm::Logging;
use AcliPm::ParseCommand;
use AcliPm::Print;
use AcliPm::Prompt;
use AcliPm::QuotesRemove;
use AcliPm::Sed;
use AcliPm::SerialPort;
use AcliPm::Socket;
use AcliPm::Sourcing;
use AcliPm::Ssh;
use AcliPm::TerminalServer;
use AcliPm::Variables;
use AcliPm::Version;


#############################
# Variables                 #
#############################

our ($opt_c, $opt_d, $opt_e, $opt_f, $opt_g, $opt_h, $opt_i, $opt_j, $opt_k, $opt_l, $opt_m, $opt_n, $opt_o, $opt_p, $opt_q, $opt_r, $opt_s, $opt_t, $opt_w, $opt_x, $opt_y, $opt_z);


#############################
# FUNCTIONS                 #
#############################

sub printSyntax {
	if ($Debug) {
		versionInfo;
		debugLevels;
		exit 1;
	}
	printf "%s version %s%s\n\n", $ScriptName, $VERSION, ($Debug ? " running on $^O perl version $]" : "");
	print "Usage:\n";
	print " $ScriptName [-cehijkmnopqswxyz]\n";
	print " $ScriptName [-ceijklmnopqrstwxyz] [<user>:<pwd>@]<host/IP> [<tcp-port>] [<capture-file>]\n";
	print " $ScriptName [-ceijmnopqrswx]      [<user>:<pwd>@]serial:[<com-port>[@<baudrate>]] [<capture-file>]\n";
	print " $ScriptName [-ceijmnopqrswxyz]    [<user>:<pwd>@]trmsrv:[<device-name> | <host/IP>#<port>] [<capture-file>]\n";
	print " $ScriptName [-eimoqsw]            pseudo:[<name>] [<capture-file>]\n";
	print " $ScriptName -r <host/IP or serial or trmsrv syntaxes above> <\"relay cmd\" | IP> [<capture-file>]\n";
	print " $ScriptName [-f] -g <acli grep pattern> [<cfg-file or wildcard>] [<2nd file>] [...]\n\n";
	print " <host/IP>        : Hostname or IP address to connect to; for telnet can use <user>:<pwd>@<host/IP>\n";
	print " <tcp-port>       : TCP port number to use\n";
	print " <com-port>       : Serial Port name (COM1, /dev/ttyS0, etc..) to use\n";
	print " <\"relay-cmd\"/IP> : To execute on relay in form: \"telnet|ssh [-l <user[:<pwd>]>] <[user[:<pwd>]@]IP>\"\n";
	print "                    If single IP/Hostname provided then \"telnet IP/Hostname\" will be executed\n";
	print " <capture-file>   : Optional output capture file of CLI session\n";
	print " <name>           : Loads up pseudo mode profile name (or legacy number 1-99)\n";
	print " -c <CR|CRLF>     : For newline use CR+LF (default) or just CR\n";
	print " -e escape_char   : CTRL+<char> for escape sequence; default is \"$CtrlEscapePrn\"\n";
	print " -f <type>        : Used with -g to force the Control::CLI::Extreme family_type\n";
	print " -g <grep-string> : Perform ACLI grep on offline config file or from STDIN (pipe)\n";
	print " -h               : Help and usage (this output)\n";
	print " -i <log-dir>     : Path to use when logging to file\n";
	print " -j               : Automatically start logging to file (<host/IP> used as filename)\n";
	print " -k <key_file>    : SSH private key to load; public key implied <key_file>.pub\n";
	print " -l user[:<pwd>]  : SSH username[& password] to use; this option produces an SSH connection\n";
	print " -m <script>      : Once connected execute script (if no path included will use \@run search paths)\n";
	print " -n               : Do not try and auto-detect & interact with device\n";
	print " -o               : Overwrite <capture-file> instead of appending to it\n";
	print " -p               : Use factory default credentials to login automatically\n";
	print " -q quit_char     : CTRL+<char> for quit sequence; default is \"$CtrlQuitPrn\"\n";
	print " -r               : Connect via Relay; append telnet/ssh command to use on Relay to reach host\n";
	print " -s <sockets>     : List of socket names for terminal to listen on (0 to disable sockets)\n";
	print " -t               : When tcp-port specified, flag to say we are connecting to a terminal server\n";
	print " -w <work-dir>    : Run on provided working directory\n";
	print " -x               : If connection lost, exit instead of offering to reconnect\n";
	print " -y <term-type>   : Negotiate terminal type (e.g. vt100)\n";
	print " -z <w>x<h>       : Negotiate window size (width x height)\n";
	exit 1;
}


sub ctrlPrint { # Returns ctrl printable string
	my $ctrl = shift;
	return length($ctrl) ? '^' . chr(ord($ctrl)+64) : 'none';
}


sub readIniFile { # Reads in acli.ini file, if one exists; changes are made to $Default hash
	my $iniFile;

	# Determine which acli.ini file to work with
	foreach my $path (@AcliFilePath) {
		if (-e "$path/$IniFileName") {
			$iniFile = "$path/$IniFileName";
			last;
		}
	}
	return unless defined $iniFile;
	debugMsg(1,"ACLI.INI: File: ", \$iniFile, "\n");

	open(INI, '<', $iniFile) or do {
		print "Unable to open ini file ", File::Spec->canonpath($iniFile), "\n";
		return;
	};
	my $lineNumber = 0;
	while (<INI>) {
		chomp;
		$lineNumber++;
		next if /^\s*$/; # skip empty lines
		next if /^\s*#/; # skip comment lines
		(/^\s*(\S+)\s+\'([^\']*)\'\s*$/ ||		# Single quoted value
		 /^\s*(\S+)\s+\"([^\"]*)\"\s*$/ ||		# Double quoted value
		 /^\s*(\S+)\s+(\[[^\[\]]+\])\s*$/ ||		# List value inside []
		 /^\s*(\S+)\s+(\S+)\s*$/			) && do { # Valid setting
			my ($setting, $value, $key, $type, $size) = ($1, $2);
			($setting, $key) = ($1, $2) if $setting =~ /^([^:]+):([^:]+)$/;
			if ($setting =~ /_(val|str|chr|flg|lst(?:\d+)?)$/) {
				$type = $1;
				$size = $1 if $type =~ s/^lst(\d+)$/lst/;
				$type eq 'chr' && do {
					if ($value =~ /^\^([A-Za-z\[\\\]\^_])$/) {
						$value = chr(ord($1) & 31);
					}
					elsif ($value =~ /^\\n$/) {
						$value = "\n";
					}
					elsif ($value =~ /^\\r$/) {
						$value = "\r";
					}
					elsif ($value !~ /^.?$/) { # Empty string allowed
						print File::Spec->canonpath($iniFile), " expected character value for $setting on line ", $lineNumber, "\n";
						next;
					}
				};
				$type eq 'val' && $value !~ /^\d+$/ && do {
					print File::Spec->canonpath($iniFile), " expected numerical value for $setting on line ", $lineNumber, "\n";
					next;
				};
				$type eq 'flg' && $value !~ /^[01]$/ && do {
					print File::Spec->canonpath($iniFile), " expected flag (0 or 1) value for $setting on line ", $lineNumber, "\n";
					next;
				};
				$type eq 'lst' && do {
					if ($value =~ s/^\[(.+)\]$/$1/) { # We have a valid input value
						my @list = map { s/^\s+//; s/\s+$//; quotesRemove($_) } split(',', $value);	# Remove spaces, then quotes, of elements
						if (defined $size && scalar @list != $size) {
							print File::Spec->canonpath($iniFile), " expected list size of $size for $setting on line ", $lineNumber, "\n";
							next;
						}
						$value = \@list; # Value becomes array ref
					}
					else {
						print File::Spec->canonpath($iniFile), " expected array list inside [] for $setting on line ", $lineNumber, "\n";
						next;
					}
				};
			}
			else {
				print File::Spec->canonpath($iniFile), " invalid $setting on line ", $lineNumber, "\n";
				next;
			}
			if (exists $Default{$setting}) {
				if (defined $key) {
					if (exists $Default{$setting}{$key}) {
						$Default{$setting}{$key} = $value;
						debugMsg(1,"ACLI.INI: $setting:$key = >", \$value, "<\n") unless ref $value;
						debugMsg(1,"ACLI.INI: $setting:$key = [", \join(', ', @$value), "]\n") if ref $value;
					}
					else {
						print File::Spec->canonpath($iniFile), " unknown key $key for $setting on line ", $lineNumber, "\n";
					}
					next;
				}
				$Default{$setting} = $value;
				debugMsg(1,"ACLI.INI: $setting = >", \$value, "<\n") unless ref $value;
				debugMsg(1,"ACLI.INI: $setting = [", \join(', ', @$value), "]\n") if ref $value;
				next;
			}
			else {
				print File::Spec->canonpath($iniFile), " unknown $setting on line ", $lineNumber, "\n";
				next;
			}
		};
		print File::Spec->canonpath($iniFile), " syntax error on line ", $lineNumber, "\n";
	}
	close INI;
	return 1;
}


sub mainLoop { # Mainloop
	my $args = shift;

	# The following hash definitions allow a number of variables, bundled within a hash, to be easily
	# passed from one method to the next by simply passing the hash reference
	my $mode = { # Control hash for mainloop operational mode
		term_in_cache => undef,				# Used to cache previous term_in value in some transitions
		connect_stage => 0,				# Number to keep up with connection stage
		peer_cp_stage => 0,				# Number to keep up with connection to peer CPU

		term_in => 'sh',				# This controls the way in which the keyboard is read
								# 'qs' = reconnect pause; q to quit; Space to reconnect
								# 'rk' = read key
								# 'ib' = input buffer (buffer key reads)
								# 'sh' = send to host
								# 'ps' = paced send (send one line at a time, at each prompt)
								# 'tm' = local term
								# 'us' = username input
								# 'pw' = password input
								# 'ds' = disable reading terminal input

		dev_inp => 'rd',				# This controls initial login to host
								# 'ct' = connection stages - from start (connect_stage = 1)
								# 'lg' = connection stages - from login (connect_stage = 4)
								# 'cp' = change of prompt requiring login() to lock onto new prompt
								# 'ld' = login delayed - when unrecognized login output received (XOS before-login banner)
								# 'rd' = normal use of read()
								# 'sb' = log into peer CPU
								# 'si' = read from STDIN (grep steaming mode)
								# 'ds' = disabled; we don't read from device

		dev_del => 'ds',				# This controls which patterns need deleting after reading from host
								# 'fl' = delete first line + print carriage return on terminal
								# 'ft' = delete first line but do not print carriage return on terminal
								# 'fb' = delete first blank lines following echo-ed command
								# 'te' = delete first line + some escape sequence
								# 'bs' = delete backspace+space sequences
								# 'bt' = delete backspace+space sequences with some post tab processing
								# 'bx' = delete backspace+space sequences for post ?syntax processing
								# 'kp' = delete keepalive sequence
								# 'yd' = delete Y (or N) response after y/n prompt
								# 'ds' = delete nothing

		dev_fct => 'ds',				# This controls handling of special events/functions
								# 'tb' = tab key press expansion - ACLI
								# 'sx' = acli syntax following '?'
								# 'st' = acli syntax following tab expansion and backspacedelete
								# 'yp' = Automatically answer 'y' at y/n? prompts
								# 'ds' = no function to process

		dev_cch => 'ds',				# This controls handling of delayed more prompt handling in cache
								# 'fs' = Fast track release from cache; used to delay lastline output by 1 cycle
								# 'md' = Delayed more-prompt handling, by 1 cycle
								# 'ds' = no function to process

		dev_out => 'ub',				# This controls how final device output is dished out on screen
								# 'ub' = unbuffered; printed out immediately
								# 'bf' = buffered; buffered so we implement our own grep & paging

		buf_out => 'ds',				# This controls how buffered output is dished out
								# 'eb' = empty buffer; line by line with grep if applicable
								# 'mp' = more pause; we have paused output with --more--
								# 'qp' = quit pause; user has pressed 'q' to quit output
								# 'se' = socket echo ouptut pause
								# 'so' = print to STDOUT (grep streaming mode)
								# 'ds' = disable; output is held in buffer indefinitely
	};
	my $cacheMode = {};	# Stores $mode hash while in Acli Control interface

	my $term_io = { # Terminal IO storage hash
		Key		=> undef,			# Holds char of last key press
		SingleChar	=> undef,			# Used to sync $singleChar across tied terminals
		CharBuffer	=> [],				# Buffer for individual keyboard reads characters
		CharPBuffer	=> '',				# Storage of above CharBuffer as string if InputBuffer paste has started filling 
		InputBuffer	=> {				# Buffers, by type, for complete lines stored for processing at next available prompt
					'paste'		=> [],		# Pasted from terminal STDIN
					'source'	=> [],		# Via @source <file> OR < <file>
					'semiclnfrg'	=> [],		# Commands separated by semicolons, once expanded into separate lines
					'RepeatCmd'	=> undef,	# This list will always stay empty; data held in other structure
					'SleepCmd'	=> undef,	# This list will always stay empty; data held in other structure
					'ForLoopCmd'	=> undef,	# This list will always stay empty; data held in other structure
		},
		InputBuffQueue	=> [''],			# If above buffers exist, this array hold the queuing position of the above; else empty string
		SourceActive	=> {},				# Hash of source origin (file, alias, dict) names which have been loaded into InputBuffer
		SaveBuffQueue	=> undef,			# Used to save InputBuffQueue array so as to restore it in @resume
		SaveCharBuffer	=> '',				# Save Buffer for individual characters read from keyboard
		SaveCharPBuffer	=> '',				# Save CharPBuffer separately
		SaveSourceActive=> {},				# Save Hash of source file names which have been loaded into InputBuffer
		SaveEchoMode	=> [],				# Stores EchoOff and EchoOutputOff settings from this hash
		SaveSedDynPats	=> [],				# Save the SED dynamic [output, input] patterns above $MaxSedPatterns
		BuffersCleared	=> 0,				# Flag indicating whether buffers were cleared and all was read from keyboard
		QuietInputDelay	=> 0,				# Delay to wait after detecting a syntax error, before resuming keyboard reads
		DelayCharProcTm	=> 0,				# Delay to wait before starting to process chars from CharBuffer in 'tm' mode
		DelayCharProcPs	=> 0,				# Delay to wait before starting to process chars from CharBuffer in 'ps' mode
		DelayCharProcDF	=> undef,			# Debug flag for both above timers
		DelayPrompt	=> undef,			# Delay sending out local prompt, if we expect socket echo output
		DelayPromptDF	=> undef,			# Debug flag for above timer
		TermReadFlag	=> undef,			# Flag which indicates whether we read something from keyboard on last read
		BufMoreAction	=> $Space,			# In buffered mode, char to send if we hit a more prompt
		MorePaging	=> $Default{more_paging_flg},	# Whether local more paging is enabled or not
		PageLineCount	=> $Default{more_paging_lines_val},	# More page line count down; when at 0 we print a more prompt
		MorePageLines	=> $Default{more_paging_lines_val},	# Number of lines per more page
		CmdOutputLines	=> 0,				# Keeps track whether a command generated at least 1 line of output
		CtrlEscapeChr	=> $args->{CtrlEscapeChr},	# CTRL-char to enter control mode
		CtrlEscapePrn	=> $args->{CtrlEscapePrn},	# CTRL-char printable string
		CtrlQuitChr	=> $args->{CtrlQuitChr},	# CTRL-char to quit program
		CtrlQuitPrn	=> $args->{CtrlQuitPrn},	# CTRL-char printable string
		CtrlInteractChr	=> $Default{ctrl_interact_toggle_chr},	# CTRL-char to toggle between interactive/transparent modes
		CtrlInteractPrn	=> ctrlPrint($Default{ctrl_interact_toggle_chr}),
		CtrlMoreChr	=> $Default{ctrl_more_toggle_chr},	# CTRL-char to toggle more paging on/off
		CtrlMorePrn	=> ctrlPrint($Default{ctrl_more_toggle_chr}),
		CtrlBrkChr	=> $Default{ctrl_break_chr},	# CTRL-char to send the break signal
		CtrlBrkPrn	=> ctrlPrint($Default{ctrl_break_chr}),
		CtrlClsChr	=> $Default{ctrl_clear_screen_chr},	# CTRL-char to clear the screen
		CtrlClsPrn	=> ctrlPrint($Default{ctrl_clear_screen_chr}),
		CtrlDebugChr	=> $Default{ctrl_debug_chr},	# CTRL-char for debugging
		CtrlDebugPrn	=> ctrlPrint($Default{ctrl_debug_chr}),
		CtrlAllocated	=> {},				# Gets initialized below
		AutoDetect	=> defined $args->{AutoDetect} ? $args->{AutoDetect} : $Default{auto_detect_flg},
								# Whether script should automatically go into intercative mode
		Mode		=> 'transparent',		# Current mode: interactive or transparent
		AcliType	=> undef,			# Flag matching Control::CLI::Extreme is_acli attribute
		LtPrompt	=> $Default{prompt_suffix_flg},	# Flag; do we append our own prompt to host device prompt ?
		LtPromptSuffix	=> $Default{prompt_suffix_str},	# Prompt to append to host device prompt in interactive mode
		SyntaxAcliMode	=> $Default{syntax_acli_mode_flg},	# Does '?' behave like in acli/nncli or like with Passport CLI
		AutoLogin	=> $args->{AutoLogin},		# Try and login using provided credentials
		GrepIndent	=> $Default{grep_indent_val},	# Number of SPACE chars to use when indenting an ACLI config
		LocalMorePrompt	=> $LocalMorePrompt,		# Local More prompt
		DeleteMorePrompt=> $DeleteMorePrompt,		# Delete above
		ConnectHistory	=> [],				# History of variables of previous connections during telnet hopping
		CredentHistory	=> [],				# History of username/passwords of previous connections during telnet hopping
		VarsHistory	=> [],				# History of vars structures of previous connections during telnet hopping
		SocketHistory	=> [],				# History of listening sockets of previous connections during telnet hopping
		AliasEnable	=> $Default{alias_enable_flg},	# Whether aliasing functionality is enabled or not
		AliasEcho	=> $Default{alias_echo_flg},	# Whether we echo what an aliased command corresponds to
		AliasFile	=> '',				# Holds filename of last alias file loaded
		AliasMergeFile	=> '',				# Holds filename of merge alias file if it was loaded
		VarsEcho	=> $Default{vars_echo_flg},	# Whether we echo a command which included %variables
		HistoryEcho	=> $Default{history_echo_flg},	# Whether we echo what a !bang command corresponds to
		YnPrompt	=> '',				# When set to 'y' we send Y to Y/N prompts; if 'n' we send N
		YnPromptForce	=> 0,				# True if a -y or -n was specifically placed on the command
		VarCapture	=> [],				# List of variable names which need capturing
		VarCaptureNumb	=> undef,			# Holds number of capture values (including hash keys)
		VarCaptureVals	=> {},				# Hash holding captured elements (values); key is variable name
		VarCaptureType	=> {},				# Hash holding variable type (''|'list'|'hash'); key is variable name
		VarCapIndxVals	=> {},				# Hash holding the mapped index of captured values from the regex; empty hash if capturing > 1 values into single var
		VarCaptureKoi	=> {},				# If capturing to an element of a list or hash variable, this hash will hold the Key or Index; undef otherwise
		VarCapHashKeys	=> {},				# For variables of type 'hash', this hash will hold the index of the captured value to use as hash key
		VarCaptureFlag	=> 0,				# Flag which is set once some elements are captured
		VarRegex	=> '',				# Holds the regex pattern to use to capture
		VarCustomRegex	=> 0,				# Flag which is true when a user defined capture regex is supplied
		VarHeldKey	=> undef,			# When capturing to a hash via regex and the regex captures a key but no value and viceversa, we remember the key for next value
		VarHeldValue	=> undef,			# Opposite of above, for scenarios where we get the value capture first (key undef) and then key on following line
		VarKeyThenValue	=> undef,			# For above 2 keys; this one locks the way keys or values are cached as either key then value (1) or the opposite (0)
		VarGRegex	=> undef,			# If set, sets the regex /g modifier to capture all occurrencies instead of single occurrence
		SourceNoHist	=> 0,				# True when sourcing a file or processing a ;frag command & disables history
		SourceNoAlias	=> 0,				# True when sourcing sequence of ';' cmds which we don't want de-aliased; obsoleted in 4.04
		RepeatCmd	=> undef,			# Command to repeat
		RepeatDelay	=> 0,				# Delay in secs to wait between repeating same command
		RepeatUpTime	=> 0,				# Actual timestamp when we can send next repeated command
		SleepDelay	=> 0,				# Delay in secs to wait for @sleep
		SleepUpTime	=> 0,				# Actual timestamp when @sleep command has finished
		ForLoopCmd	=> undef,			# Command to cycle
		ForLoopVarType	=> undef,			# Array of type of Var; 0=range 1=list
		ForLoopVar	=> undef,			# List of variable values which change at every cycle
		ForLoopVarN	=> undef,			# Number of sprintf vars in command, if we only entered one range
		ForLoopVarStep	=> undef,			# List of steps to be applied to each variable at each cycle
		ForLoopVarList	=> undef,			# List of arrays holding list of values
		ForLoopCycles	=> 0,				# Counter for number of cycles
		SocketEnable	=> $Default{socket_enable_flg},	# Whether or not inter-terminal sockets are enabled
		PseudoTerm	=> $args->{PseudoTerm},		# Pseudo Terminal mode & number (for testing when no switch connection available)
		PseudoTermName	=> undef,			# Pseudo profile name
		PseudoTermEcho	=> 0,				# Flag to echo commands (for debugging grep and local command processing)
		PseudoAttribs	=> {},				# Alternative attributes hash used in pseudo mode
		PathSetSwitch	=> $args->{PathSetSwitch},	# Set if the working directory was set when script was launched
		SockSetSwitch	=> 0,				# Set if listening sockets were defined when script was launched
		BannerDetected	=> 1,				# Flag set true when a BannerHardPattern seen; determines when BannerSoftPatterns are processed
		BannerCacheLine	=> '',				# Used to cache a recent banner line, either for suppressing spaces or double banner lines
		BannerEmptyLine	=> 0,				# Flag set when we hit an empty line inside the banner which we consider suppressing
		RecordsMatched	=> 0,				# Keeps track of the number of non-banner lines matches; used to update "x out y"
		RecordCountFlag	=> 0,				# Flag to ensure we only print ACLI's count of records once only per command
		InteractRestore	=> undef,			# Set for fast revert to interact mode with CTRL-T
		Newline		=> $args->{Newline},		# Newline used to send commands to host; can be set to "\n", "\r"
		VarPrompt	=> undef,			# Name of $variable we are currently prompting user for
		VarPromptType	=> undef,			# Type (list/hash/'') of variable we are prompting value for
		VarPromptKoi	=> undef,			# If a list/hash, contains the index we are prompting value for
		VarPromptOpt	=> undef,			# Var prompt is for an optional variable ? If so, entering nothing clears the variable
		EchoOff		=> 0,				# When enabled, while sourcing, commands & prompts are not printed out
		EchoOutputOff	=> 0,				# When enabled, while sourcing, output of commands are not printed out
		EchoReset	=> 0,				# Enabled when echo is turned off in sourcing mode, to ensure that echo is restored when exiting sourcing mode
		Sourcing	=> undef,			# Flag, true while sourcing commands (paste, source, semiclnfrg, ForLoopCmd)
		VarPromptSrcing => undef,			# Caches above Sourcing key during user input of @vars prompt
		BlockStack	=> [],				# Stack of block operators when sourcing files
		RunSyntax	=> undef,			# Holds "run <script> " if it was entered with ?; so that input buffer can be restored after passing to script
		TerminalType	=> $args->{TerminalType},	# Holds terminal type to negotiate during connection, like vt100
		WindowSize	=> $args->{WindowSize},		# Holds window size to negotiate during connection
		TermTypeNotNego	=> undef,			# Set, if the terminal type changed while connected
		TermWinSNotNego	=> undef,			# Set, if the window size changed while connected
		HLfgcolour	=> $Default{highlight_fg_colour_str},	# Foreground colour
		HLbgcolour	=> $Default{highlight_bg_colour_str},	# Background colour
		HLbright	=> $Default{highlight_text_bright_flg},		# Bright text
		HLunderline	=> $Default{highlight_text_underline_flg},	# Underline text
		HLreverse	=> $Default{highlight_text_reverse_flg},	# Reverse text
		HLon		=> '',				# Escape string activating highlight formatting (set by &setHLstrings below)
		HLoff		=> '',				# Escape string de-activating highlight formatting (set by &setHLstrings below)
		HLgrep		=> undef,			# Highlight is moved away from grepOutput and after applying sed colour patterns
		KnownHostsFile	=> '',				# SSH known_hosts file in use
		KnownHostsDummy	=> '',				# Dummy known_hosts file used for flock; always set with above
		FeedInputs	=> undef,			# List of inputs to feed to command generated prompts
		CacheInputCmd	=> undef,			# Cache FeedInputs, command to cache in acli.cache
		CacheInputKey	=> undef,			# Cache FeedInputs, key (MAC or FamilyType) to cache in acli.cache
		CacheFeedInputs	=> undef,			# Cache FeedInputs, list of inputs which were actually fed to host
		StartScriptOnTm	=> undef,			# Used to automatically run/resume script upon conection after entering interactive mode
		HideTimeStamps	=> $Default{hide_timestamps_flg},	# Hide timestamp banners
		CompletLineMrkr	=> 0,				# Remembers if last line of output was marked as complete, without trailing \n
		PortRngSpanSlot	=> $Default{port_ranges_span_slots_flg},	# Port ranges to span slots or not
		DefaultPortRng	=> $Default{default_port_range_mode_val},	# How to display port list if device does not support port ranges
		SedFile		=> '',				# Holds filename of last sed file loaded
		SedInputPats	=> {},				# Holds sed input patterns and replacements  {idx [<disp-pat>, <qr-pat>, <disp-repl>, <qq-repl>],}
		SedOutputPats	=> {},				# Holds sed output patterns and replacements {idx [<disp-pat>, <qr-pat>, <disp-repl>, <qq-repl>],}
		SedColourPats	=> {},				# Holds sed output patterns and replacements {idx [<disp-pat>, <qr-pat>, <disp-repl>, <qq-repl>, <colour-profile>],}
		ColourProfiles	=> {},				# Holds colour profiles for @sed: {profile {foreground <red|blue>, background <red|blue>, bright 0|1, reverse 0|1, underline 0|1}}
		BackSpaceMode	=> undef,			# BackSpaceMode within code to remove backspaces, used in 'bt' mode
		Dictionary	=> undef,			# Holds loaded dictionary name
		DictionaryEcho	=> $Default{dictionary_echo_flg},	# Whether we echo what a dictionary command corresponds to
		DictionaryFile	=> '',				# Holds filename of loaded dictionary file
		DictSourcing	=> undef,			# Flag, set when a script is sourced from loading a dictionary file, for processing @my as dictscope
		HlEnteredCmd	=> $Default{highlight_entered_command_flg},	# Highlight entered command
	};
	($term_io->{LocalMorePrompt} = $LocalMorePrompt) =~ s/\Q$CtrlMorePrn\E/$term_io->{CtrlMorePrn}/;
	($term_io->{DeleteMorePrompt} = $term_io->{LocalMorePrompt}) =~ s/./\cH \cH/g;
	$term_io->{CtrlAllocated} = { # Hash of all ctrl keys allocated
		$term_io->{CtrlEscapePrn}	=> 1,
		$term_io->{CtrlQuitPrn}		=> 1,
		$term_io->{CtrlInteractPrn}	=> 1,
		$term_io->{CtrlMorePrn}		=> 1,
		$term_io->{CtrlBrkPrn}		=> 1,
		$term_io->{CtrlClsPrn}		=> 1,
		$term_io->{CtrlDebugPrn}	=> 1,
	};
	setHLstrings($term_io); # Initialize HLon & HLoff keys above

	my $host_io = { # Host IO storage hash; varialbles that apply to a host; might extend to multiple hosts in future
		OutCache	=> '',				# Output cache used in Buffered mode if last line has no prompt
		OutBuffer	=> '',				# Output buffer used in Buffered mode
		GrepBuffer	=> '',				# Output buffer used when grep string used
		DeltaBuffer	=> '',				# Holds each cycle's delta buffer added to GrepBuffer or OutBuffer
		GrepCache	=> '',				# Output cache buffer used by grep when a pattern astride two reads
		FragmentCache	=> '',				# Caches an incomplete last line printed out to the terminal
		SendBuffer	=> '',				# Centralized send buffer for all transmission/commands to host
		SendBufferDelay	=> '',				# Used to send a portion of characters at cycle+1
		PacedSentChars	=> '',				# Characters sent to host in 'ps' mode; might show up after prompt
		ComPort		=> $args->{ComPort},		# Name of communication port (serial port name, or SSH or TELNET)
		Name		=> $args->{Host},		# Device hostname|IP address
		TcpPort		=> $args->{TcpPort},		# TCP port for SSH or Telnet connection
		Username	=> $args->{Username},		# Username for connection (required for SSH connection)
		Password	=> $args->{Password},		# Password for connection
		Baudrate	=> $args->{Baudrate},		# Serial port baudrate to use
		SshPrivateKey	=> undef,			# SSH Private key (set by &verifySshKeys below)
		SshPublicKey	=> undef,			# SSH Public Key (set by &verifySshKeys below)
		RelayHost	=> $args->{RelayHost},		# Relay hostname|IP address
		RelayTcpPort	=> $args->{RelayTcpPort},	# Relay TCP port for SSH or Telnet connection
		RelayUsername	=> $args->{RelayUsername},	# Relay Username for connection
		RelayPassword	=> $args->{RelayPassword},	# Relay Password for connection
		RelayBaudrate	=> $args->{RelayBaudrate},	# Relay Serial port baudrate to use
		RelayCommand	=> $args->{RelayCommand},	# Command to execute on Relay host
		SshKnownHost	=> '',				# Holds whether SSH host was verified in known_hosts file
		SshKeySrvFingPr	=> '',				# SSH server concatenated type, length md5 figerprint
		EraseEchoedCmd	=> undef,			# Flag to erase echoed command from host device output
		TabCommand	=> undef,			# Flag to intercept device output following a tab expansion
		CacheTimeout	=> 0,				# OutCache timeout
		CacheTimeoutDF	=> undef,			# OutCache timeout debug flag show message once
		CLI		=> undef,			# Control::CLI::Extreme object
		Prompt		=> '',				# Cached CLI prompt last seen from device
		Timeout		=> $Default{timeout_val},	# Timeout used in Control::CLI::Extreme
		ConnectTimeout	=> $Default{connect_timeout_val},	# Timeout used for TCP Connection setup
		LoginTimeout	=> $Default{login_timeout_val},	# Timeout used for initial login
		MorePagingInit	=> undef,			# Stores the static mode more paging initially set to on host during connection (undef in sync mode)
		MorePaging	=> undef,			# Stores how we set more paging locally on switch during connection
		KeepAliveTimer	=> $Default{keepalive_timer_val},		# Timer value in min after which to trigger client based keepalive
		KeepAliveUpTime	=> time + $Default{keepalive_timer_val}*60,	# Actual timestamp when to trigger client based keepalive
		TranspKeepAlive	=> $Default{transparent_keepalive_flg},		# Should local session timeout & keepalive work on transparent sessions
		SessionTimeout	=> $Default{session_timeout_val},		# Timer value in minutes after which session is timed out
		SessionUpTime	=> time + $Default{session_timeout_val}*60,	# Actual timestamp when to declare session timeout
		Type		=> '',				# Control::CLI::Extreme family_type attribute
		Model		=> '',				# Control::CLI::Extreme model attribute
		VOSS		=> '',				# Control::CLI::Extreme is_voss attribute
		APLS		=> '',				# Control::CLI::Extreme is_apls attribute
		SyncMorePaging	=> undef,			# undef = no sync done (static mode); 0 no sync needed; 1 = sync at next prompt
		DeviceReadFlag	=> undef,			# Flag which indicates whether we read data from device on last read
		BackspaceCount	=> 0,				# Number of backspace+space sequences to delete from host stream
		PacedSentPendng	=> 0,				# Number of outstanding pacedSentChars which we expect to receive before calculated backspace sequence
		DebugFilePath	=> '',				# File path were debug files are located
		InputLog	=> '',				# Filename for debug input logging
		OutputLog	=> '',				# Filename for debug output logging
		DumpLog		=> '',				# Filename for debug dump logging
		TelOptLog	=> '',				# Filename for debug telnet options logging
		ErrorDetect	=> $Default{source_error_detect_flg},	# Determines whether or not we want to pause sourcing commands in case of an error
		ErrorLevel	=> $Default{source_error_level_str},	# Determines whether we look at error messages only or error and warning messages
		SyntaxError	=> 0,				# Flag indicating whether the last command generated an error 
		OutputSinceCmd	=> undef,			# Flag which indicates that some output is received since last command sent
		OutputSinceSend	=> 0,				# Flag which keeps track if we received output since we sent something; was used to allow CTRL-T; not anymore
		Connected	=> undef,			# Flag which indicates whether connection is established or not
		ConnectionError	=> 0,				# Flag which indicates whether a connection error has occurred
		Login		=> 0,				# Flag which indicates whether an initial login has occurred or not
		Slots		=> undef,			# Local storage of slot list for device
		Ports		=> undef,			# Local storage of per slot array of ports lists
		Console		=> undef,			# True if we have a Console connecton (via serial or telnet on remote annex)
		RemoteAnnex	=> undef,			# True if we have a connection via remote anex
		DualCP		=> undef,			# True if device has dual CPUs
		Sysname		=> '',				# System name of device
		BaseMAC		=> undef,			# Base MAC address of device
		PreviousMAC	=> '',				# Caches MAC of previuos connection, to detemrine if var file needs reading
		CpuSlot		=> undef,			# CPU slot if connected to a PassportERS device
		MasterCpu	=> undef,			# Whether CPU is Master CPU on PassportERS device
		SwitchMode	=> undef,			# Switch mode if connected to a BaystackERS device
		UnitNumber	=> undef,			# Unit Number if connected to a BaystackERS stack
		OOBconnected	=> undef,			# True if out-of-band connected to host switch
		SendMasterCP	=> 1,				# Normally always set, except when -peercpu local option set
		SendBackupCP	=> 0,				# Only on DualCP devices, only set when -peercpu, -bothcpus options set
		UnsavedVars	=> {},				# Hash to keep track of $vars which have not been saved yet
		VarsFile	=> '',				# Holds filename of variable file loaded
		AnnexFile	=> '',				# Holds filename of remote annex file
		LoopbackConnect => undef,			# Flag which keeps track of debug connections via 127.x.x.x to IO cards or Peer CPU
		CapabilityMode	=> undef,			# Will be set to either 'interact' or 'transparent' depending on family_type detected
		Discovery	=> undef,			# Set once device dicovery has been performed for the 1st time
		CommandCache	=> '',				# Holds the current command (and dealias or var deref) during @echo off, in case of error
		LastCommand	=> '',				# 1st word of last command sent to host
		LastCmdError	=> undef,			# Holds error message from last command; gets reset at every new switch commands
		LastCmdErrorRaw	=> undef,			# Holds raw error message from last command; in case it needs to be re-printed on screen
		TerminalSrv	=> $args->{TerminalSrv},	# Terminal Server flag
		UnrecogLogins	=> $UnrecognizedLogins,		# Holds count of unrecognized login outputs to let user interact with during login phase
		PortUnconstrain	=> $Default{port_ranges_unconstrain_flg},	# Unconstrain processing of port ranges from actual ports on connected switch
		DotActivityCnt	=> 0,				# Holds count of times we received just dots '.' as output, to switch to unbuffered mode
		
	};
	verifySshKeys($host_io, $args->{SshKey});	# Load SSH keys

	my $peercp_io = { # Peer CPU IO storage hash; varialbles that apply to the peer CPU of connected host
		CLI		=> undef,			# Control::CLI::Extreme object for connection to peer CPU
		OOB_IP		=> undef,			# OOB IP address
		Connect_IP	=> undef,			# IP address to use for peer CPU (might be same as $host_io->{Name})
		Connect_OOB	=> undef,			# Flag which indicates whether we are to connect directly to peer CPU OOB IP
		Connected	=> undef,			# Flag which indicates whether connection is established or not to the peer CPU
		ConnectionError	=> 0,				# Flag which indicates whether a connection error has occurred
		Timeout		=> $Default{peercp_timeout_val},# Timeout used in Control::CLI::Extreme for connecting to peer CPU
		SendBuffer	=> '',				# Centralized send buffer for all transmission/commands to peer CPU
		InputLog	=> '',				# Filename for debug input logging
		OutputLog	=> '',				# Filename for debug output logging
		DumpLog		=> '',				# Filename for debug dump logging
		TelOptLog	=> '',				# Filename for debug telnet options logging
	};
	my $script_io = { # Script IO storage hash; variables which will stay common even if multiple hosts
		OverWrite	=> $args->{OverWrite},		# If logging output to file, do we overwrite or append ?
		LogFile		=> $args->{LogFile},		# Filename used for output logging
		LogFullPath	=> undef,			# Holds the full path to the opened log file
		LogFH		=> undef,			# Logging file handle
		LogDir		=> $args->{LogDir},		# Path where log files are created, if set; otheriwse working directory is used
		AutoLog		=> $args->{AutoLog},		# Is logging automatic
		AutoLogFail	=> 0,				# Set when auto-log enabled and we failed to open a log file for active connection
		CmdLogFile	=> undef,			# Filename used for logging output of single command
		CmdLogFullPath	=> undef,			# Holds the full path to the opened command log file
		CmdLogMode	=> undef,			# Determines whether the capture mode is overwrite '>' or append '>>'
		CmdLogOnly	=> undef,			# Determines whether the output is only sent to file or also echoed to terminal
		CmdLogFH	=> undef,			# Command logging file handle
		CmdLogFlag	=> undef,			# Set true, when we are ready for output
		DebugLog	=> '',				# Filename used for debug logging
		DebugLogFH	=> undef,			# Debug logging file handle
		AcliControl	=> 0,				# Flag indicating whether we are in Acli Control mode (bit1=ACLI; bit2=Annex; bit4=Serial, bit8=VarPrompt) or not (0)
		QuitOnDisc	=> $args->{QuitOnDisc},		# Whether script exits upon disconnect
		DotPaceTime	=> 0,				# Holds timestamp since last activity dot was printed
		ConnectFailMode	=> 0,				# 0=connection lost prompt; 1=connection fail prompt; 2=msg & return to ACLI
		TermModeSet	=> undef,			# Keeps track whether we have set Term::Readkey mode, to restore it when exiting
		GrepStream	=> $args->{GrepStream},		# Grep Stream mode
		GrepStrmParsed	=> undef,			# Holds the cmdParsed structure of the grepstr
		ConfigFileList	=> $args->{ConfigFileList},	# List of offline config files to use for performing Grep stream on
		GrepMultiple	=> $args->{GrepMultiple},	# Flag which is true when we have more than 1 file in above ConfigFileList
		GrepForceType	=> $args->{FamilyType},		# Family Type set via -f switch
		EmbCmdSpacing	=> undef,			# Allows proper spacing for embedded command output
		PrintFlag	=> 0				# Set whenever some output is printed out
	};
	my $prompt = { # Prompt storage hash
		Match		=> undef,			# Prompt match string
		Regex		=> undef,			# Regex of prompt match string
		More		=> undef,			# More prompt match string
		MoreRegex	=> undef,			# Regex of more prompt match string
	};
	my $termbuf = { # Terminal buffer storage
		Linebuf1	=> '',		# Local term buffer of chars from beginning of line up to cursor position
		Linebuf2	=> '',		# Local term buffer of chars from cursor position up to end of line
		Bufback1	=> '',		# Chain of backspace chars, enough to completely delete on screen Linebuf1
		Bufback2	=> '',		# Chain of backspace chars, enough to completely delete on screen Linebuf2
		TabOptions	=> undef,	# Grep (|!), redirect (<>), repeat (@), forloop (&) etc.. stripped before sending tab expansion
		TabBefoVar	=> undef,	# Portion of command before dereferencing $vars or removing backslashes (only set if some vars were actually deref-ed or backslashes removed)
		TabCmdSent	=> undef,	# Portion of command actually sent to switch for tab expansion
		TabMatchSent	=> undef,	# quotemeta of TabCmdSent, used for matching in received output
		TabMatchTail	=> undef,	# Ending portion of command we need to match against, on switches which scroll input over 80 chars max
		SynCmdMatch	=> '',		# Portion of command we need to match against in received output from syntax display
		SynBellSilent	=> undef,	# Suppress bell character from syntax output if a valid dictionary syntax is offered
		SedInputApplied	=> undef,	# This marks whether or not a sed input pattern was applied to tab or syntax expansion (only then will output patterns be applied)
		SynMatchSent	=> undef,	# Same as TabMatchSent for syntax, used for matching in received output
	};
	my $history = {
		Current		=> undef,	# History pointer for current mode; points either to Host or ACLI arrays below
		HostRecall	=> [],		# History of commands array which can be recalled with cursor keys or !
		UserEntered	=> [],		# History of commands array of commands as entered by user
		DeviceSent	=> [],		# History of commands array as sent to the host device
		DeviceSentNoErr	=> [],		# History of commands array as sent to the host device which did not error
		ACLI		=> [],		# History of commands array sent to Acli Control interface (recall type)
		Index		=> -1,		# Current index within current array pointed to by Current above
	};
	my $grep = {
		String		=> 0,		# Grep string entered in Local Term mode; flag
		Advanced	=> [],		# Flag which is true when grep mode is euither || or !!
		KeepBanner	=> 1,		# Whether banner lines are preserved in advanced grep ||, !!; flag
		BannerDetected	=> [],		# Flag set true when a BannerHardPattern seen; determines when BannerSoftPatterns are processed
		Indent		=> '',		# If indenting will hold a number of space chars to use to indent ACLI configs
		Mode		=> [],		# Grep mode: '|'=(matching lines) or '!'=(non-matching lines); array
		Instance	=> [],		# Whether grep string is a config instance; e.g. list of ports, vrf, etc..
		RangeList	=> [],		# For instance greps, this will point either to an array ref of ids, or a hash ref of port numbers
		Regex		=> [],		# Regex of grep string; array
		MultiLine	=> [],		# Whether grep mode is operating on multiline output or not; flag
		KeepInstanceCfg	=> [],		# Determines whether we are in an instance config context and need to preserve lines
		DelInstanceCfg	=> [],		# Determines whether we are in a negated instance config context and need skip contained lines
		InsertIndent	=> 0,		# Determines whether we are in an instance config context and need to insert indentation
		EnableSeen	=> undef,	# Keeps track of enable mode, to prevent duplicate enable lines
		ConfigSeen	=> undef,	# Keeps track of config mode, to prevent duplicate config term lines
		ConfigTermSeen	=> undef,	# Keeps track of config mode (in ACLI), to add final end if missing
		EndSeen		=> undef,	# Keeps track of end of config, to ensure that an end statement present at the end
		ConfigACLI	=> 0,		# Set once 'config' seen on output and DeviceCfgParse is true for device; prevents indentProcessing
		CfgContextLvl	=> 0,		# Keeps track of depth within an ACLI config context
		CfgContextTyp	=> [],		# Keeps track of the current config context type (to prevent nesting of same type)
		BufferThreshold	=> 1,		# Keeps track of whether Grep Threshold needs to be checked or not
		KeepIndented	=> [],		# Determines whether we are to print all lines with a greater indentation level than IndentLevel
		DelIndented	=> [],		# Determines whether we are to suppress all lines with a greater indentation level than IndentLevel
		IndentAdd	=> undef,	# Holds number of spaces to increase indentation of lines (not in ConfigACLI mode)
		IndentLevel	=> [],		# Keeps track, per grep string, of the current indentation level
		IndentParents	=> [],		# Array, per grep string, of 2 element array holding line and its indentation level
		IndentNestMatch	=> [],		# Keeps track if last match was indented (triggered submit parent lines) or not
		IndentExit	=> [],		# True if line was detected as valid exit line from indented output
		IndentExitLevel	=> [],		# Holds the last exit line indent when backtracking through exit index contexts
		ShowCommand	=> [],		# True for show commands; used to suppress blank lines in output
		CompleteOutput	=> undef,	# Flag set to true in Grep Stream mode; so as not to have to see a prompt at end of output
		EmptyLineSupres	=> [],		# Set if an empty line was suppressed (we might yet resore it depending on what next line is)
		NoEmptyLineLast	=> [],		# Set if last line was not empty
		GrepStreamFile	=> undef,	# Holds the current filename of the output to process in grep, to be pre-pended to any no-null output
	};
	my $socket_io = {
		Tie		=> undef,		# Port name of socket used to send to; undef if not in use
		TieTxSocket	=> undef,		# Socket handle we are tied to for sending; undef if not in use
		TieRxSocket	=> undef,		# Socket handle we are tied to for receiving (in echo modes); undef if not in use
		TieRxSelect	=> undef,		# IO::Select object monitoring the Tie Rx socket ('error' and 'all' echo modes)
		TieTxLocalPort	=> undef,		# Local port number used by Tied Tx socket as source UDP port
		TieRxLocalPort	=> undef,		# Local port number used by Tied Rx socket used in echo modes
		TieEchoMode	=> $Default{socket_echo_mode_val},# Whether we handle output from other terminal instances we are tied to
		TieEchoBuffers	=> {},			# Hash of buffers to hold output from every terminal instance we are tied to
		TieEchoSeqNumb	=> {},			# Maintains sequence number of expected datagram (same keys as hash above)
		TieEchoPartial	=> undef,		# Set to a key in above hashes for an incomplete buffer we started outputting
		TieEchoFlush	=> 0,			# Set if we no longer want the echo from other terminals, so we flush reads instead
		ListenSockets	=> {},			# Hash of all open sockets we are listening to; key=name & value=handle
		ListenEchoMode	=> undef,		# On listening terminals gets set to whatever TieEchoMode is on Tied terminal
		ListenSelect	=> undef,		# IO::Select object monitoring Listening sockets
		ListenTieRxPort	=> undef,		# Source port of command received from commanding terminal
		ListenSrcIP	=> undef,		# Source IP of command received from commanding terminal
		ListenErrMsg	=> undef,		# Error message to display on listening terminal if something with sockets went wrong
		EchoSocket	=> undef,		# Echo socket used by listening terminals ('error' and 'all' echo modes)
		EchoDstPort	=> undef,		# Destination port used by Echo Socket
		EchoDstIP	=> undef,		# Destination IP used by Echo Socket
		EchoSeqNumb	=> 0,			# On large outputs requirung multiple datagrams keeps track of sequence number
		BindLocalAddr	=> $Default{socket_bind_ip_str},	# Normally we bind to just the loopback IP
		SendIP		=> $Default{socket_send_ip_str},	# Now a multicast IP address
		IPTTL		=> $Default{socket_send_ttl_val},	# Normally 0 if used on the loopback
		SendUsername	=> $Default{socket_send_username_flg},	# Whether or not the username is encoded in socket datagrams
		AllowedSrcIPs	=> $Default{socket_allowed_source_ip_lst},	# Array of source IPs from which sockets are accepted
		Port		=> $Default{socket_names_val},	# Hash mapping portnames to UDP port numbers
		SocketFile	=> '',			# Holds filename of socket names file
		SendBuffer	=> '',			# Buffer of commands to send to tied socket; also single packet buffer send for echo mode replies
		OutBuffer	=> '',			# Holds output buffer to be sent over echo socket; last line is always a complete line
		LastLine	=> '',			# Holds last, incomplete line, which we do not hold in above OutBuffer
		CmdComplete	=> 0,			# Flag which is true when the contents of above OutBuffer are the complete output
		HoldIncLines	=> 1,			# Incomplete lines are not printed unless they are a prompt or YNprompt; with exceptions hence this flag
		PauseBuffLen	=> undef,		# Gets set to length of OutBuffer fragment, while we are pausing socket-echo output till prompt received
		UntieOnDone	=> undef,		# Gets set for socket send and ping, when we want the socket to close after the single command
		SocketWait	=> undef,		# Set when we want to wait for any output from socket
		TimerOverride	=> undef,		# User supplied override timer to %SocketDelayPrompt values
		CachedTieName	=> undef,		# When doing a socket send on an already tied terminal, we want to restore the tie after the socket send
		ResetEchoMode	=> undef,		# Flag used by socket ping when the current echo mode is none, as we need to enable an echo for replies
		GrepRecycle	=> 0,			# Flag; if set results in echo output from tied terminals being processed through local grep processing
		SummaryCount	=> 0,			# Flag; if set results in a summary line counting the number of tied terminals which provided output
		EchoOutCounter	=> undef,		# If SummaryCount is set, keeps track of the number of echo buffers which were sent to output
		FirstDataMode3	=> undef,		# True first time listening socket receives a command with dataMode = 3
		EchoSendFlag	=> undef,		# Flag which controls when listening terminal starts appending output to DeltaBuffer
		TiedSentFlag	=> undef,		# Flag which tracks whether some command was actually sent on the socket by tied term
	};

	my $annexData = {
		Sort		=> undef,		# Defines how the list will be sorted: 'ip' = by IP then Port; 'name' = by switch name; undef = no sorting, entries appended
		Static		=> undef,		# Defines whether an existing entry is deleted if the MAC it had moves: 0 = delete; 1 = don't delete
		MasterFile	=> $Default{master_trmsrv_file_str},	# Master terminal-server file
		List		=> [],			# List of terminal server entries: [0:ip, 1:ssh/telnet, 2:port, 3:switch-name, 4:details, 5:comments]
	};

	my $serialData = [];
	my $alias = {};
	my $vars = {};
	#  $vars = { # Variable assignments done by sub setvar
	#	<varname> => {
	#		type		=> '' = scalar; 'list' = array ref; 'hash' = hash ref
	#		value		=> <value>,# for list or hash type, this is a ref
	#		nosave		=> <flag>, # true if cannot be saved
	#		argument	=> <flag>, # true for @source & @run arguments
	#		script		=> <flag>, # true if was set while sourcing
	#		myscope		=> <flag>, # true if variable was declared in a script with @my
	#		dictscope	=> <flag>, # true if variable was declared in a dictionary file with @my
	#	},
	#  };
	my $varscope = { # This structure holds variable names or wildcards as declared by @my statements
		varnames  => {},
		wildcards => [],
	};
	my $dictionary = {};
	#  $dictionary = {
	#	input	=> {},	# Hash chain of input commands
	#	output	=> [],	# List of conditional translations
	#	prtinp	=> [SlotsRef, PortsRef]	# Slot/Port struct for dictionary input
	#	prtout	=> <port-list-range>
	#	prtmap	=> {<inport1> => <outport1>, etc..} # Hash
	#	commnt	=> Comment line character
	#};
	my $dictscope = { # This structure holds variable names or wildcards as declared by @my statements in loaded dictionary file
		varnames  => {},
		wildcards => [],
	};
	my $cacheInputs = { # This structure holds data read from acli.cache file
		timestamp	=> undef,
		data		=> {
		#		'command'	=> {
		#				'familyType'	=> [feed inputs]
		#				'BaseMAC'	=> [feed inputs]
		#		}
		}
	};

	# Instead of feeding all the above structures to functions, we just pass a single $db array of pointers (maybe I should bless it ?)
	my $db = [
		$mode,		# 0
		$cacheMode,	# 1
		$term_io,	# 2
		$host_io,	# 3
		$script_io,	# 4
		$peercp_io,	# 5
		$socket_io,	# 6
		$prompt,	# 7
		$termbuf,	# 8
		$history,	# 9
		$grep,		# 10
		$alias,		# 11
		$vars,		# 12
		$annexData,	# 13
		$serialData,	# 14
		$varscope,	# 15
		$dictionary,	# 16
		$dictscope,	# 17
		$cacheInputs,	# 18
	];

	mkdir $AcliFilePath[0] unless -e $AcliFilePath[0] && -d $AcliFilePath[0]; # Touch .acli directory if it does not yet exist
	loadSedFile($db); # Read in acli.sed file
	if ($script_io->{GrepStream}) {
		if ($Debug) {
			my $filePrefix = 'grepstream';
			$host_io->{DebugFilePath} = File::Spec->rel2abs(cwd);
			$DebugLog = $filePrefix . $DebugFile;
			unless ($DebugLogFH) {
				open($DebugLogFH, '>', $DebugLog) or do {
					undef $DebugLogFH;
					print "Unable to open debug file $DebugLog : $!\n";
				};
			}
		}
		$host_io->{Type} = $script_io->{GrepForceType};
		$script_io->{GrepStream} = '-ib||' . $script_io->{GrepStream} if $script_io->{GrepStream} !~ /^[|!-]/;
		$script_io->{GrepStream} = ' ' . $script_io->{GrepStream} if $script_io->{GrepStream} =~ /^-/;
		$script_io->{GrepStrmParsed} = parseCommand('bogus' . $script_io->{GrepStream}); # Add a bogus command not to confuse parseCommand
		$term_io->{LtPrompt} = 0; # In case of errors in prepGrepStructure()
		$grep->{BufferThreshold} = 0;
		$term_io->{Sourcing} = 1; # We run at higher speed
		debugMsg(1,"=sourcing mode ENABLED in grepStreaming mode\n");
		changeMode($mode, {term_in => 'ds', dev_inp => 'si', buf_out => 'so'}, '#999');
	}
	else {
		loadDefaultAliasFiles($db);
		if (defined $args->{ListenSockets}) { # Handle request to open listening sockets from command line
			if (!$term_io->{SocketEnable}) { # We can't
				print "Socket functionality is disabled; cannot open sockets!\n";
			}
			elsif ($args->{ListenSockets} eq '0') {
				$term_io->{SocketEnable} = 0;
			}
			else { # We can
				my @sockets = split(',', $args->{ListenSockets});
				my ($success, @failedSockets) = openSockets($socket_io, @sockets);
				if (!$success) {
					print "Unable to allocate socket numbers\n";
				}
				elsif (@failedSockets) {
					print "Failed to create sockets: " . join(', ', @failedSockets) . "\n";
				}
				else {
					print "Listening on sockets: " . join(',', sort {$a cmp $b} keys %{$socket_io->{ListenSockets}}) . "\n";
					$term_io->{SockSetSwitch} = 1;
				}
			}
		}
		if (defined $args->{RunScript}) { # Handle request to run a script upon connection
			my ($ok, $errOrSrc) = readSourceFile($db, $args->{RunScript}, \@RunFilePath);
			quit(1, "$errOrSrc", $db) unless $ok;
			$term_io->{StartScriptOnTm} = $errOrSrc; # If $ok true then $errOrSrc folds the script filename
		}
		if (defined $args->{AnnexConnect}) { # Handle connection to known remote annex port
			loadTrmSrvConnections($db, $args->{AnnexConnect}) or quit(1, "No cached Terminal Server file exists!", $db);
			# If we get here, there are 2 possible outcomes:
			# - $host_io->{Name} has been set, so we fall through *if* below
			# - $host_io->{Name} is empty, so we fall through *else* below
		}
		elsif (defined $args->{SerialConnect}) { # Handle connection to an available serial port on this machine
			my $retVal = readSerialPorts($serialData);
			quit(1, "Unable to read serial ports", $db) if !defined $retVal && $^O eq 'MSWin32';
			quit(1, "Unable to read serial ports from Registry; try running with administrator rights", $db) if !defined $retVal;
			quit(1, "No serial ports found", $db) unless $retVal;
			# If we get here, some serial ports were found, so now we fall through as below:
			# - $host_io->{Name} is empty, so we fall through *else* below
		}
		if ($host_io->{Name}) { # Start telnet or SSH or Serial
			$history->{Current} = $history->{HostRecall};
			$script_io->{ConnectFailMode} = 1;
			connectToHost($db) and do{
				if ($term_io->{AutoDetect}) {
					changeMode($mode, {term_in => 'rk', dev_inp => 'ct'}, '#1');
				}
				else {
					changeMode($mode, {term_in => 'sh', dev_inp => 'ct'}, '#11');
				}
			};
		}
		elsif ($term_io->{PseudoTerm}) { # Set up the Pseudo Terminal mode
			enablePseudoTerm($db, $args->{PseudoName});
			$history->{Current} = $history->{HostRecall};
			printOut($script_io, appendPrompt($host_io, $term_io));
			changeMode($mode, {term_in => 'tm', dev_inp => 'ds'}, '#111');
		}
		else {
			if (defined $args->{AnnexConnect}) {
				$script_io->{AcliControl} = 2;
			}
			elsif (defined $args->{SerialConnect}) {
				$script_io->{AcliControl} = 4;
			}
			else {
				$script_io->{AcliControl} = 1;
			}
			$history->{Current} = $history->{ACLI};
			%$cacheMode = %$mode;	# Cache mode settings
			changeMode($mode, {term_in => 'tm', dev_inp => 'ds'}, '#91');
			print "\n", $ACLI_Prompt if $script_io->{AcliControl} == 1;
		}

		$| = 1; # Flush STDOUT buffer
		ReadMode('raw');
		$script_io->{TermModeSet} = 1;
	}
	
	my ($mainLoopSleep, $mainLoopTime, $accelerationFactor) = (0, 0, 1);

	MAINLOOP: while(1) { # Mainloop
		# Record time before going over loop below
		$mainLoopTime = Time::HiRes::time;

		# Read the keyboard for any key presses and process accordingly (non-blocking read)
		handleTerminalInput($db);

		# Either send out to tied socket or read in from controlling socket 
		handleSocketIO($db) if $term_io->{SocketEnable};

		# Send commands or char sequences to host device 
		handleDeviceSend($db);

		# Handles connection to Peer CPU on systems with DualCPU
		handleDevicePeerCP($db) if $mode->{peer_cp_stage};

		# Reads (non-blocking read) device output, processes accordingly, and either prints it out at terminal or buffers it 
		handleDeviceOutput($db) unless $mode->{peer_cp_stage};

		# Prints buffered output to terminal, localy handling more paging and grep strings
		handleBufferedOutput($db, $mainLoopTime);

		# Cycle counter printed out on all debug messages
		Debug::loop($db) if $Debug && $DebugPackage;
		$DebugCycleCounter = 1 if ++$DebugCycleCounter == $DebugCycleMax;

		# Fraction of a sec sleep (otherwise CPU gets hammered..)
		next if $term_io->{PseudoTerm} && $term_io->{Sourcing};						# Only in pseudoterm + sourcing mode run full speed
		$accelerationFactor = $term_io->{Sourcing} ? $SourcingAccelerationFactor : 1;			# In sourcing mode we apply an acceleration factor
		$mainLoopSleep = ($MainloopTimer / $accelerationFactor) - (Time::HiRes::time - $mainLoopTime);	# $MainLoopTimer less time it took to run through loop
		Time::HiRes::sleep($mainLoopSleep) if $mainLoopSleep > 0;					# Only if positive
	}
}


#############################
# MAIN                      #
#############################

MAIN:{
	$SIG{__DIE__}  = 'dieHandler' if $^O eq "MSWin32" && $Win32PauseOnQuit;

	$ARGV[$#ARGV] =~ s/\r$// if @ARGV; # Seen issue when executing via acligui on Linux, last ARGV element has a '\r' appended if acli.spawn was saved as a DOS text file
	debugMsg(1,"Full Args: ", \join(' ', @ARGV), "\n") if scalar @ARGV;
	getopts('c:d:e:f:g:hi:jk:l:m:nopq:rs:tw:xy:z:');

	$Debug = $opt_d if defined $opt_d && $opt_d =~ /^\d+$/;
	require Data::Dumper if $Debug; # Only load this module if debug enabled
	$DebugPackage = $Debug && eval { require $ScriptDir . 'Debug.pm' };

	# Start by reading the ini file
	readIniFile;
	$KeepAliveSequence = $Default{newline_chr} if $KeepAliveSequence eq "\n"; #Make sure KeepAliveSequence in synch with newline char
	for my $key (%Default) {# Make sure ctrl_ keys are valid CTRL chars 0-31
		next unless $key =~ /^ctrl_/;
		next unless length($Default{$key}); # If empty string skip
		$Default{$key} = chr(ord($Default{$key}) & 31);
	}

	my $args = { # Arguments fed to mainLoop
		# Direct connection args
		ComPort		=> undef,
		Host		=> undef,
		TcpPort		=> undef,
		Username	=> undef,
		Password	=> undef,
		Baudrate	=> undef,
		SshKey		=> $opt_k,
		# Relay connection args
		RelayHost	=> undef,
		RelayTcpPort	=> undef,
		RelayUsername	=> undef,
		RelayPassword	=> undef,
		RelayBaudrate	=> undef,
		RelayCommand	=> undef,
		# Other args
		LogFile		=> undef,
		OverWrite	=> $opt_o ? '>' : '>>',
		CtrlEscapeChr	=> $Default{ctrl_escape_chr},
		CtrlEscapePrn	=> ctrlPrint($Default{ctrl_escape_chr}),
		CtrlQuitChr	=> $Default{ctrl_quit_chr},
		CtrlQuitPrn	=> ctrlPrint($Default{ctrl_quit_chr}),
		AutoLogin	=> $opt_p,
		AutoDetect	=> !$opt_n,
		QuitOnDisc	=> $opt_x || $Default{quit_on_disconnect_flg},
		AnnexConnect	=> undef,
		SerialConnect	=> undef,
		ListenSockets	=> $opt_s,
		PathSetSwitch	=> undef,
		PseudoTerm	=> 0,
		PseudoName	=> undef,
		GrepStream	=> $opt_g,
		FamilyType	=> $opt_f,
		ConfigFileList	=> undef,
		GrepMultiple	=> undef,
		Newline		=> $opt_c && $opt_c =~ /^CRLF$/i ? "\n" :
					$opt_c && $opt_c =~ /^CR$/i ? "\r" :
						$Default{newline_chr},
		TerminalType	=> $Default{terminal_emulation_str},
		WindowSize	=> $Default{terminal_window_size_lst2},
		LogDir		=> File::Spec->rel2abs(defined $opt_i ? $opt_i : $Default{log_path_str}),
		AutoLog		=> $opt_j || $Default{auto_log_to_file_flg},
		TerminalSrv	=> undef,
		RunScript	=> $opt_m,
	};
	printSyntax if $opt_h || ($ARGV[0] && $ARGV[0] eq '?');

	if ($opt_g) {
		printSyntax if $opt_c || $opt_e || $opt_i || $opt_j || $opt_k || $opt_l || $opt_n || $opt_o
		            || $opt_p || $opt_q || $opt_r || $opt_s || $opt_w || $opt_x || $opt_y || $opt_z; # -ceijklnopqrswxyz flags not allowed here
		quit(1, "Invalid family_type supplied with -f flag") if $opt_f && !defined $DeviceComment{$opt_f};
		debugMsg(1,"GrepStream >", \$args->{GrepStream}, "<\n");
		if (scalar @ARGV > 1) { # Multiple filenames (no wildcard)
			@{$args->{ConfigFileList}} = @ARGV;
			$args->{GrepMultiple} = 1;
			debugMsg(1,"Multiple files; no wildcard\n");
		}
		elsif (scalar @ARGV == 1) { # Single filename or wildcard
			if ( (my $fileglob = $ARGV[0]) =~ /[\*?\[\]]/) { # Wildcard
				debugMsg(1,"Wildcard = $fileglob\n");
				@{$args->{ConfigFileList}} = bsd_glob("$fileglob");
				unless (@{$args->{ConfigFileList}}) { quit(1, "No files found matching \"$fileglob\"") }
				$args->{GrepMultiple} = 1;
				foreach my $file (@{$args->{ConfigFileList}}) {
					debugMsg(1,"Globbed file = $file\n");
				}
			}
			else { # Single filename (no wildcard)
				@{$args->{ConfigFileList}} = ($ARGV[0]);
				$args->{GrepMultiple} = 0;
				debugMsg(1,"Sinlge file = $ARGV[0]\n\n");
			}
		}
		mainLoop($args); # In grep stream mode go stright into loop
	}
	printSyntax if scalar @ARGV > 3;

	# Set working directory if provided ...
	debugMsg(1,"Script started on working directory: ", \File::Spec->rel2abs(cwd), "\n");
	if ($opt_w) { # ... via -w switch
		quit(1, "Invalid directory supplied with -w flag") unless chdir $opt_w;
		debugMsg(1,"Applied working directory from -w arg: ", \File::Spec->rel2abs(cwd), "\n");
		$args->{PathSetSwitch} = 1;
	}
	elsif (length $Default{working_directory_str}) { # ... via acli.ini
		quit(1, "Invalid working directory (working_directory_str) supplied in acli.ini") unless chdir $Default{working_directory_str};
		debugMsg(1,"Applied working directory from acli.ini: ", \File::Spec->rel2abs(cwd), "\n");
	}
	# Check logging directory if provided ...
	if ($args->{LogDir} && !(-e $args->{LogDir} && -d $args->{LogDir})) { # If an invalid logging path
		quit(1, "Invalid logging directory supplied with -i flag") if $opt_i;
		quit(1, "Invalid logging directory (log_path_str) supplied in acli.ini");
	}

	if ($opt_e) {
		if ($opt_e =~ /^\^([A-Za-z\[\\\]\^_])$/) {
			$args->{CtrlEscapeChr} = chr(ord($1) & 31);
			$args->{CtrlEscapePrn} = uc($opt_e);
		}
		else {
			print "Specify character as \"^X\" (in quotes)\n\n";
			printSyntax;
		}
	}
	if ($opt_q) {
		if ($opt_q =~ /^\^([A-Za-z\[\\\]\^_])$/) {
			$args->{CtrlQuitChr} = chr(ord($1) & 31);
			$args->{CtrlQuitPrn} = uc($opt_q);
		}
		else {
			print "Specify character as \"^X\" (in quotes)\n\n";
			printSyntax;
		}
	}
	if (defined $opt_y) {
		$args->{TerminalType} = length $opt_y ? $opt_y : undef; 
	}
	if (defined $opt_z) {
		if ($opt_z =~ /^(\d+)\s*x\s*(\d+)$/) {
			$args->{WindowSize} = [$1, $2];
		}
		elsif ($opt_z eq '') {
			$args->{WindowSize} = [];
		}
		else {
			print "Specify window size as \"<width> x <height>\"\n\n";
			printSyntax;
		}
	}

	$args->{Host} = shift(@ARGV) || "";
	if ($args->{Host} =~/^(?:([^:]+)(?::(\S*))?@)?(serial:(.*?))(?:@(\d+))?$/i) {
		printSyntax if $opt_k || $opt_l || $opt_y || $opt_z; # -k,-l,-y,-z flags not allowed here
		$args->{Username} = quotesRemove($1);
		$args->{Password} = quotesRemove($2);
		($args->{Host}, $args->{ComPort}, $args->{Baudrate}) = ($3, $4, $5);
		unless ($args->{ComPort}) {
			$args->{SerialConnect} = '';
			$args->{Host} = '';
		}
	}
	elsif ($args->{Host} =~/^(?:([^:]+)(?::(\S*))?@)?(?:annex|trmsrv):(.*)$/i) {
		printSyntax if $opt_k || $opt_l; # -k,-l flags not allowed here
		$args->{Username} = quotesRemove($1);
		$args->{Password} = quotesRemove($2);
		$args->{AnnexConnect} = $3 || '';
	}
	elsif ($args->{Host} =~/^pseudo(\d\d?)?:(.+)?$/i) {
		printSyntax if !$Debug && ($opt_j || $opt_k || $opt_l || $opt_n || $opt_p || $opt_r || $opt_x || $opt_y || $opt_z); # -jklnprxyz flags not allowed here
		$args->{Host} = '';
		$args->{PseudoTerm} = 1;
		$args->{PseudoName} = defined $2 ? $2 : defined $1 ? $1 : 100;
	}
	else {
		if (@ARGV && $ARGV[0] =~ /^\d+$/) {
			my $tcpPort = shift(@ARGV);
			unless ($tcpPort == 0) { # Ignore a zero value (mRemoteNG integration)
				$args->{TcpPort} = $tcpPort;
				quit(1, "Invalid tcp port number") if $args->{TcpPort} > 65535;
			}
		}
		if ($opt_l) { # SSH connection
			printSyntax unless length $args->{Host};
			if ($opt_l =~ /^([^:\s]+):(\S*)$/) {
				$args->{Username} = quotesRemove($1);
				$args->{Password} = quotesRemove($2);
			}
			else {
				$args->{Username} = quotesRemove($opt_l);
			}
			$args->{ComPort} = 'SSH';
		}
		else { # Telnet connection
			$args->{ComPort} = 'TELNET';
		}
		if ($args->{Host} =~ s/^([^:]+)(?::(\S*))?@(\S+)$/$3/) { # Process embedded username/password
			printSyntax if $opt_l;
			$args->{Username} = quotesRemove($1);
			$args->{Password} = quotesRemove($2);
		}
		$args->{Host} =~ s/^:@//; # For a telnet connection with no username/password provided (mRemoteNG integration)
	}
	# Terminal Server flag
	$args->{TerminalSrv} = defined $args->{AnnexConnect} || ($args->{TcpPort} && ($opt_t || $opt_n)); # Either annexConnect OR if (a TCP port is set and either -t or -n flag)

	# Process relay host
	if ($opt_r) {
		unless (@ARGV) { # Make sure we have the target host
			print "\nMissing target host for Relay connection\n\n";
			printSyntax;
		}
		# Move across details which are thus for the Relay connection
		($args->{RelayHost}, $args->{Host})		= ($args->{Host}, undef);
		($args->{RelayTcpPort}, $args->{TcpPort})	= ($args->{TcpPort}, undef);
		($args->{RelayUsername}, $args->{Username})	= ($args->{Username}, undef);
		($args->{RelayPassword}, $args->{Password})	= ($args->{Password}, undef);
		($args->{RelayBaudrate}, $args->{Baudrate})	= ($args->{Baudrate}, undef);

		# Process the target host
		$args->{RelayCommand} = shift(@ARGV);
		$args->{RelayCommand} =~ s/^\s+//;
		$args->{RelayCommand} =~ s/\s+$//;
		if ($args->{RelayCommand} =~ s/(\s+\-l\s+([^:\s]+))(?::(\S+))?/$1/) { # Remove embedded credentials from SSH -l switch
			$args->{Username} = quotesRemove($2);
			$args->{Password} = quotesRemove($3);
		}
		elsif ($args->{RelayCommand} =~ s/([^:\s]+)(?::(\S*))?@(\S+)/$3/) { # Remove embedded credentials from IP
			$args->{Username} = quotesRemove($1);
			$args->{Password} = quotesRemove($2);
		}
		if ($args->{RelayCommand} =~ /^\S+$/) { # Just an IP address / hostname
			$args->{RelayCommand} = 'telnet ' . $args->{RelayCommand}; # prepend with telnet (for backward compatibility)
		}
		if ($args->{RelayCommand} =~ /^\S+\s+-l\s+\S+\s+(\S+)\s*$/
		 || $args->{RelayCommand} =~ /^\S+\s+(\S+)\s+-l\s+\S+\s*$/
		 || $args->{RelayCommand} =~ /^\S+\s+(\S+)\s*$/) {
			# We expect something like: telnet|ssh -l <user>|rlogin|etc <hostname|IP>
			$args->{Host} = $1;
		}
		else {
			print "\nRelay command not of form: <command> <target>\n\n";
			printSyntax;
		}
	}

	if (@ARGV) { # Log file
		if ($args->{AutoLog}) { # -j/ini AutoLog flag not allowed with logfile
			print "\nCannot specify a capture-file with Auto-Logging enabled (-j switch)\n\n" if $opt_j;
			print "\nCannot specify a capture-file with Auto-Logging enabled in acli.ini (auto_log_to_file_flg)\n\n" unless $opt_j;
			printSyntax;
		}
		$args->{LogFile} = shift(@ARGV) || "";
	}
	printSyntax if @ARGV; # If still more unexpected args

	debugMsg(1,"Args: COM Port = $args->{ComPort}\n") if $args->{ComPort};

	debugMsg(1,"Args: Relay Host = $args->{RelayHost}\n") if $args->{RelayHost};
	debugMsg(1,"Args: Relay TCP Port = $args->{RelayTcpPort}\n") if $args->{RelayTcpPort};
	debugMsg(1,"Args: Relay Username = $args->{RelayUsername}\n") if $args->{RelayUsername};
	debugMsg(1,"Args: Relay Password = $args->{RelayPassword}\n") if $args->{RelayPassword};
	debugMsg(1,"Args: Relay Baudrate = $args->{RelayBaudrate}\n") if $args->{RelayBaudrate};
	debugMsg(1,"Args: Relay Command = \"$args->{RelayCommand}\"\n") if $args->{RelayCommand};

	debugMsg(1,"Args: Host = $args->{Host}\n") if $args->{Host};
	debugMsg(1,"Args: TCP Port = $args->{TcpPort}\n") if $args->{TcpPort};
	debugMsg(1,"Args: Username = $args->{Username}\n") if $args->{Username};
	debugMsg(1,"Args: Password = $args->{Password}\n") if defined $args->{Password};
	debugMsg(1,"Args: Baudrate = $args->{Baudrate}\n") if $args->{Baudrate};
	debugMsg(1,"Args: SSH Key = $args->{SshKey}\n") if $args->{SshKey};
	debugMsg(1,"Args: Terminal Server Flag is set\n") if $args->{TerminalSrv};

	debugMsg(1,"Args: Outfile = $args->{LogFile}\n") if $args->{LogFile};
	debugMsg(1,"Args: Annex Connection = $args->{AnnexConnect}\n") if $args->{AnnexConnect};
	debugMsg(1,"Args: Annex Connection set\n") if defined $args->{AnnexConnect} && !$args->{AnnexConnect};
	debugMsg(1,"Args: Serial Connection set\n") if defined $args->{SerialConnect};
	debugMsg(1,"Args: Pseudo Terminal = $args->{PseudoName}\n") if $args->{PseudoTerm};
	debugMsg(1,"Args: Listen on Sockets Script = $args->{ListenSockets}\n") if defined $args->{ListenSockets};
	debugMsg(1,"Args: Run Script = $args->{RunScript}\n") if defined $args->{RunScript};

	# Enter Mainloop
	mainLoop($args);
}
