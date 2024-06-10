# ACLI sub-module
package AcliPm::GlobalDefaults;
our $Version = "1.10";

use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::GlobalConstants;


############################
# GLOBAL DEFAULT VARIABLES #
############################
# can be edited:
our $MainloopTimer = .01;			# Main loop timer in secs; default ~10ms
our $SourcingAccelerationFactor = 5;		# This value divides $MainloopTimer to obtain a reduced mainloop timer to use in sourcing mode (10 is too aggressive, 100%cpu; 9 gives 30%; 5-8 gives 20%)
our $ACLI_Prompt = 'ACLI> ';			# Prompt of telnet control CLI
our $RemoteAnnexBasePort = 5000;			# Base TCP port numbers when connecting to Remote Annex box
our $TermWidth = 131; 				# Baystack Terminal width is usually 79 characters; we max it out for performance 
our $OutputCacheTimeout = 3.5;			# How long (secs) to hold on (and not print) last line, not a recognized prompt
our $OutputCacheFastTimeout = 1.5;		# How long (secs) to hold patterns in fast cache; 5600TOR gave delay up to 22 cycles in 10.134.169.51-acli-dev.pl.debug-keep
						# - Ronald's 4800 gave delay up to 102 cycles in 10.134.172.210-acli.pl.debug.ronald
our $KeepAliveSequence = "\n";			# We use a carriage return as this is the only thing that counts for the 8600
our $GrepBufferThreshold = 620;			# In absence of prompt, minimum size of buffer before we start performing grep on it
our @LoginReadAttempts = (11, 1);		# Initial connection & subsequent; do not decrease below 9!
our @AnnexPortRange = (5001, 5016);		# TCP port range used by remote annex boxes
our $Win32PauseOnQuit = 1;			# Determines whether on Win32 script should pause before quit-ing on error
our $QuietInputDelay = 0.05;			# Cycles to delay keyboard reads after we detected a syntax error from device
our $DelayCharProcTm = 0.50;			# Cycles to delay processing characters from CharBuffer in 'tm' mode immediately after getting prompt
our $DelayCharProcPs = 0.50;			# Cycles to delay processing characters from CharBuffer in 'ps' mode immediatley after hitting carriage return
our %SocketDelayPrompt = (			# Cycles to delay before printing out device prompt if we are expecting socket echo output
	1	=>	0.24,			# - in "error" Echo mode
	2	=>	0.50,			# - in "all" Echo mode
);
our $SocketMaxMsgLen = 1024;			# This is the mandatory MAXLEN we pass to socket->recv($data, $MAXLEN)
our $MaxPromptLength = 40;			# In case of socket echo, we make assumption on maximum socket length when preventing fragments be printed
our $DebugCLIExtreme = 13;			# If debug enabled on module, what debug level to use
our $DebugCLIExtremeSerial = 2;			# If debug enabled on module, what debug level to use (extra debug for SerialPort module)
our $SummaryTailLinesLimit = 10;		# Number of lines from end of output to look at for summary lines to keep, when pruning output buffer
our $UnrecognizedLogins = 1;			# How many unrecognized logins to let user interact with before bailing out of login() and using transparent mode
our $VarRangeUnboundMax = 299;			# When capturing > $var %n-  ; max range of columns to capture
our $MaxSedPatterns = 20;			# We want to limit this (this default can be overridden in acli.sed file)
our $CompleteLineMarker = "\x00";		# Marker we use for complete lines on which we have to cache the last \n
our $HighlightMarkerBeg = "\x01";		# Beginning marker for highlight text, while applying sed output patterns
our $HighlightMarkerEnd = "\x02";		# Ending marker for highlight text, while applying sed output patterns
our $PseudoDefaultSelection = 'voss';		# Pseudo default selection in %PseudoSelectionAttributes hash
our $DotActivityUnbufferThreshold = 3;		# Number of consecutive only dots received from host which will make us switch to unbuffered mode


our %Default = ( # Hash of default settings; these are mostly user modifiable from within the script
	timeout_val			=> 22,			# Default timeout value in secs; used by CLI object (occasionally switch discovery was timing out; so increased it from 10 to 15; increased to 22 for SLX9850)
	connect_timeout_val		=> 35,			# SSH & Telnet connection timeout (requires Control::CLI 1.05) - for establishing TCP connection
	login_timeout_val		=> 30,			# Timeout in secs to apply to initial login (was 10 before raising it to 30; VSP8400 4.2 slow login sometimes..)
	peercp_timeout_val		=> 4,			# Default timeout value in secs for peer CPU connection
	auto_detect_flg			=> 1,			# If true, script tries to detect HostType, and sets Mode according to family_type_interact_flg below
	family_type_interact_flg => {				# Whether we should interact with these HostTypes: 1 = 'interact'; 0 or undefined = 'transparent'
		BaystackERS		=> 1,
		PassportERS		=> 1,
		ExtremeXOS		=> 1,
		SLX			=> 1,
		ISW			=> 1,
		ISWmarvell		=> 1,
		Series200		=> 1,
		Wing			=> 1,
		HiveOS			=> 1,
		Ipanema			=> 1,
		SecureRouter		=> 1,
		WLAN2300		=> 1,
		WLAN9100		=> 1,
		Accelar			=> 1,
	},
	prompt_suffix_flg		=> 1,			# 0 = off; 1 = on; prompt_suffix_str added to host prompt in 'interact' mode
	prompt_suffix_str		=> '% ',		# Appended to host prompt in 'interact' mode if LtPrompt is true
	more_paging_flg			=> 1,			# 0 = off; 1 = on; by default we handle more paging
	more_paging_lines_val		=> 22,			# Default number of lines to print per more page; can be set with setmode cmd
	alias_enable_flg		=> 1,			# 0 = disabled; 1 = enabled
	alias_echo_flg			=> 1,			# 0 = off; 1 = on; Echo the de-aliased command of an alias
	vars_echo_flg			=> 1,			# 0 = off; 1 = on; Echo the de-aliased command containing %variables
	history_echo_flg		=> 1,			# 0 = off; 1 = on; Echo the history recalled command
	ctrl_escape_chr			=> "\c]",		# By default same as real telnet; can be changed through command line
	ctrl_quit_chr			=> $CTRL_Q,		# Shortcut to quit and exit
	ctrl_interact_toggle_chr	=> $CTRL_T,		# Toggle between interact & transparent mode
	ctrl_more_toggle_chr		=> $CTRL_P,		# Toggle more paging
	ctrl_break_chr			=> $CTRL_S,		# Send break signal
	ctrl_clear_screen_chr		=> $CTRL_L,		# Clear the screen
	ctrl_debug_chr			=> "\c[",		# Only works when debug is enabled
	grep_indent_val			=> 3,			# Number of SPACE chars to use when indenting an ACLI config
	syntax_acli_mode_flg		=> 1,			# Does '?' behave like in acli/nncli or like with Passport CLI
	keepalive_timer_val		=> 4,			# Default timer for handleDeviceSend keepalives (4min here)
	transparent_keepalive_flg	=> 0,			# Should local session timeout & keepalive work on transparent sessions ? 1=yes; 0=no
	session_timeout_val		=> 600,			# Default timer for handleDeviceSend session timeout (600 mins or 10hours here)
	socket_enable_flg		=> 1,			# Global switch to control wheather or not inter terminal sockets are enabled
	socket_names_val 	=> {				# Default socket portname to port number
		all			=> 50000,
	},
	socket_bind_ip_str		=> '127.0.0.1',		# Normally the loopback address
	socket_send_ip_str		=> '239.255.255.255',	# Now a multicast IP address
	socket_send_ttl_val		=> 0,			# Normally 0 as we only use it on the loopback address
	socket_send_username_flg	=> 1,			# Determines whether we encode the username in socket datagrams
	socket_allowed_source_ip_lst	=> ['127.0.0.1'],	# Array of source IPs from which sockets are accepted
	socket_echo_mode_val		=> 1,			# Local echo in Socket tied terminal: 0 = no echo; 1 = errors only; 2 = everything
	pseudo_prompt_str		=> 'PSEUDO#',		# Prompt used by Pseudo Terminal
	source_error_detect_flg		=> 1,			# Determines whether or not we want to pause sourcing commands in case of an error
	source_error_level_str		=> 'error',		# Determines whether we look at error messages only or error and warning messages
	newline_chr			=> "\r",		# Newline on connection; can be set to "\n" (CR+LF) or "\r"(CR)
	terminal_emulation_str		=> 'vt100',		# Default terminal type (does not really matter for Extreme devices)
	terminal_window_size_lst2	=> [132, 24],		# Default window size; matters on WLAN9100, which uses it for command line scrolling
	highlight_fg_colour_str		=> 'disable',		# Highlight foreground colour: black|red|green|yellow|blue|magenta|cyan|white|disable
	highlight_bg_colour_str		=> 'red',		# Highlight background colour
	highlight_text_bright_flg	=> 1,			# Highlight increase text brightness
	highlight_text_underline_flg	=> 1,			# Highlight underline text
	highlight_text_reverse_flg	=> 0,			# Highlight reverse text colours
	ssh_default_keys_lst		=> ['id_rsa', 'id_dsa'],# We prefer RSA, then DSA
	quit_on_disconnect_flg		=> 0,			# 0 = off; 1 = on (same as -x command line switch)
	working_directory_str		=> '',			# Working directory (same as -w command line switch)
	auto_log_to_file_flg		=> 0,			# Auto-log session to file
	log_path_str			=> '',			# Auto-log directory (where auto-log files will be created)
	auto_log_filename_str		=> '%Y_%m_%d-%Hh%Mm%Ss-<>', # POSIX strftime date format appended to auto-log filename
	master_trmsrv_file_str		=> '',			# Master terminal-server file
	hide_timestamps_flg		=> 0,			# Hide banner time stamps from output (but not from logging)
	port_ranges_span_slots_flg	=> 0,			# Determines whether generateRange() will return ranges spanning different slots
	default_port_range_mode_val	=> 1,			# On products which do not support port ranges, determines mode to compress ranges: 0 = no range; 1 = 1/1-24; 2 = 1/1-1/24
	port_ranges_unconstrain_flg	=> 0,			# If enabled, processing of port ranges will no longer be constrained by actual ports on connected switch
	dictionary_echo_flg		=> 2,			# 0 = off; 1 = on; 2 = single; Echo the translation of a dictionary command
	highlight_entered_command_flg	=> 1,			# 0 = off; 1 = on; if enabled user typed/pasted commands in interactive mode are made bright
	ssh_known_hosts_key_missing_val	=> 1,			# 0 = SSH connection closed; 1 = User prompted; 2 = SSH key added automatically
	ssh_known_hosts_key_changed_val	=> 1,			# 0 = SSH connection closed; 1 = User prompted; 2 = SSH key updated automatically
);

our %BlockTypes = (	# Hash of block types and corresponding closing block keyword
	'@if'		=> '@endif',
	'@while'	=> '@endloop',
	'@loop'		=> '@until',
	'@for'		=> '@endfor',
);

# do not edit:
our $CtrlEscapePrn	= '^' . chr(ord($Default{ctrl_escape_chr})+64);
our $CtrlQuitPrn		= '^' . chr(ord($Default{ctrl_quit_chr})+64);
our $CtrlInteractPrn	= '^' . chr(ord($Default{ctrl_interact_toggle_chr})+64);
our $CtrlMorePrn		= '^' . chr(ord($Default{ctrl_more_toggle_chr})+64);
our $CtrlBrkPrn		= '^' . chr(ord($Default{ctrl_break_chr})+64);
our $CtrlClsPrn		= '^' . chr(ord($Default{ctrl_clear_screen_chr})+64);
our $CtrlDebugPrn	= '^' . chr(ord($Default{ctrl_debug_chr})+64);

# can be edited:
our $LocalMorePrompt = "--More (q=Quit, space/return=Continue, $CtrlMorePrn=Toggle on/off)--";
our $EchoMorePrompt = "--Some Echo Output incomplete (q=Quit, space=Retry, return=Skip)--";
our $MorePromptDelay = "--More--";
# do not edit:
(our $DeleteMorePrompt = $LocalMorePrompt) =~ s/./\cH \cH/g;
(our $DeleteEchoPrompt = $EchoMorePrompt) =~ s/./\cH \cH/g;

# do not edit:
our $IniFileName = 'acli.ini';
our $SedFileName = 'acli.sed';
our $AliasFileName = 'acli.alias';
our $AliasMergeFileName = 'merge.alias';
our @AnnexFileName = ('acli.trmsrv', 'acli.annex');
our $SocketFileName = 'acli.sockets';
our $VarFileExt = '.vars';
our $KnownHostsFile = 'known_hosts';
our $KnownHostsDummy = '.known_hosts.acli'; # We use this dummy file to perform flock, as Net::SSH2::KnownHosts does not
our $ConsoleExe = $ScriptDir eq 'C:\\Users\\lstevens\\Scripts\\acli\\' ? 'C:\Program Files\ConsoleZ\Console.exe' : $ScriptDir . 'Console.exe';
our $AcliSpawnFile = 'acli.spawn';
our $AcliCacheFile = 'acli.cache';
our $ConsoleWinTitle = "ACLI Terminal Launched Sessions";
our $ConsoleAcliProfile = 'ACLI';

# do not edit:
our $DebugInFile = "-$ScriptName.debug.in";
our $DebugOutFile = "-$ScriptName.debug.out";
our $DebugDumpFile = "-$ScriptName.debug.dump";
our $DebugTelOptFile = "-$ScriptName.debug.telopt";
our $DebugFile = "-$ScriptName.debug";
our $DebugPackage;	# True if Debug.pm loaded
our ($DebugCycleCounter, $DebugCycleMax) = (1, 1000);
our ($DebugLog, $DebugLogFH);

# do not edit:
our $AcliDir = '/.acli';
our $VarDir  = '/.vars';
our $SshDir  = '/.ssh';
our (@AcliFilePath, @AcliMergeFilePath, @VarFilePath, @SshKeyPath, @RunFilePath, @DictFilePath);

# Environment variables we use as path base:
# - ACLI        : Needs to be manually set
# - HOME        : Usualy set on Unix systems
# - USERPROFILE : Usually set on Windows systems

if (defined(my $path = $ENV{'ACLI'})) {
	push(@AcliFilePath,      File::Spec->canonpath($path));
	push(@AcliMergeFilePath, File::Spec->canonpath($path));
	push(@VarFilePath,       File::Spec->canonpath($path.$VarDir));
	push(@SshKeyPath,        File::Spec->canonpath($path.$SshDir));
	push(@RunFilePath,       File::Spec->canonpath($path));
	push(@DictFilePath,      File::Spec->canonpath($path));
}
if (defined(my $path = $ENV{'HOME'})) {
	push(@AcliFilePath,      File::Spec->canonpath($path.$AcliDir));
	push(@AcliMergeFilePath, File::Spec->canonpath($path.$AcliDir));
	push(@VarFilePath,       File::Spec->canonpath($path.$AcliDir.$VarDir));
	push(@SshKeyPath,        File::Spec->canonpath($path.$SshDir));
	push(@RunFilePath,       File::Spec->canonpath($path.$AcliDir));
	push(@DictFilePath,      File::Spec->canonpath($path.$AcliDir));
}
if (defined(my $path = $ENV{'USERPROFILE'})) {
	push(@AcliFilePath,      File::Spec->canonpath($path.$AcliDir));
	push(@AcliMergeFilePath, File::Spec->canonpath($path.$AcliDir));
	push(@VarFilePath,       File::Spec->canonpath($path.$AcliDir.$VarDir));
	push(@SshKeyPath,        File::Spec->canonpath($path.$SshDir));
	push(@RunFilePath,       File::Spec->canonpath($path.$AcliDir));
	push(@DictFilePath,      File::Spec->canonpath($path.$AcliDir));
}
# Last resort, script directory
push(@AcliFilePath, File::Spec->canonpath($ScriptDir));
push(@VarFilePath,  File::Spec->canonpath($ScriptDir.$VarDir));
push(@SshKeyPath,   File::Spec->canonpath($ScriptDir.$SshDir));
push(@RunFilePath,  File::Spec->canonpath($ScriptDir));
push(@DictFilePath, File::Spec->canonpath($ScriptDir));


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
