# ACLI-terminal
Active CLI (ACLI) is an SSH, Telnet and Serial Port terminal with advanced features for interacting with Extreme Networking products

The main features are:
* Grep capability on output of any command; works properly with context-based switch configuration; simple grep, advanced grep, negative grep and no limit on chain of grep sequences (always better than switch own grep!)
* Alias capability: define aliases for the commands you use most of the time; comes with many pre-defined in acli.alias file which you can edit, or you can place yours in merge.alias
* Run multiple terminal sessions, and tie them together with sockets; issue commands in one and they get executed in all others as well
* Output redirect to, and input source from files directly from your local file system (no more hassle of getting the files to/from the switch or the inconvenience of ERS Stackables which have no file system)
* Set variables per device; capture port lists/ranges from output; embed same variables in any commands you issue; save variables and have them automatically reloaded when connecting to same switch
* Enhanced history of commands (no more pathetic 15 commands of ERS Stackable history); because of alias and variable support, 2 histories are held: commands typed by user & commands actually sent to switch
* Localized more paging, makes session seem more responsive on slow connections/switches; terminal obtains full output in the background while user pages through output at a slower rate
* Unlimited commands can be copy-pasted into terminal; each line is fed at every prompt; terminal is capable of making difference between user typing and user pasting
* When pasting or sourcing, commands which prompt for confirmation (y/n) are automatically confirmed without having to remember to add a 'y' + Carriage return to CLI script
* When pasting or sourcing, if an error is encountered, sourcing will stop there; + ability to resume from where we left, as pasting/sourcing buffer can be recalled with @resume command
* Ability to repeat a command at configurable regular intervals, indefinitely or until user tries to interact again with CLI session
* Ability to repeat a command and replace fields within it at each iteration with list or range of values
* Ability to issue multiple commands on same line separated by semi-colon ';', which allows above functions as well as alias to be used to send multiple commands to the switch
* Automatically unwraps annoying wrapped long lines from ERS Stackable/ISW show running-config and log file
* Suppresses annoying escape characters from stackable login; so that when capturing to log file, the file is readable afterwards (ERS Stackable banner is reformatted and maintained)
* Ability to maintain a cache of past terminal server connections for ease of recall by mapping IP & TCP port to Switch name, model & MAC address
* The same grep capability can be leveraged on offline config files by invoking the acli command with -g switch to a single file or file wildcard or piping to acli -g
* For SSH publickey authentication, ability to view installed public keys on switch as well as plant own public key in the right file in the right format for the right user access
* Do not get disconnected by switch after a few minutes inactivity; ACLI terminal holds its own session timer and will generate regular keep alives to hold the session up until its own session timer expires
* Ability to highlight (e.g. in red bold) any string or pattern in output stream; handy for inspecting large log files for certain keywords
* Ability to modify and/or recolour selected output from device using sed patterns which can be defined in an offline file
* Scripting support with the ability to use control structures, error detection, user input, and controlled output
* Ability to push(put) or pull(get) with FTP or SFTP one or many files from one or many switches simultaneously using supplied aftp command tool
* Ability to launch many ACLI sessions from a command line using IP/hostname lists, or from a hosts file, or from a batch file; using the ACLI GUI Launcher tool
* Ability to extract device information from XMC/XIQ-SE via GraphQl API, in order to easily launch many ACLI sessions against XMC discovered devices; using the XMC ACLI Launcher tool
* Dictionary functionality to translate CLI commands from one switch OS to another. Currently only an ERS/BOSS dictionary is provided with translations of selected ERS config sections to both VOSS/EXOS.
* Ability to cache and automatically re-use device passwords which might be required everytime one access debug/shell; passwords can be cached per device or per family type
* ACLI Session Manager application, by Marlon Scheid, is included in the ACLI Windows installer

ACLI Terminal is written in Perl. The Windows installer includes [ConsoleZ](https://github.com/cbucher/console) which is an improved DOS box window for use on Microsoft Windows.

# Change Log

[Change log](https://github.com/lgastevens/ACLI-terminal/blob/main/Changes)

1.00_019
* Stackable message "Failed retries since last login" now shows on login
* Command line -o switch was appending instead of over-writing
* open -l for SSH was not working with -p switch
* Was still missing some stackable more prompts and freezing on output

1.00_020
* Added @cls / @clear embedded command to clear the screen
* ACLI> 'term mode' now is 'term hostmode', and works properly
* &<> for loop mode was not suppressing alias echo on last iteration
* &<> for loop mode now accepts mixed ranges: <cmd with %s embeded> &51-53,90,94,100
* &<> for loop mode now accepts mixed port ranges: <cmd with %s embeded> &5/1-10,1-3/12
* &<> for loop mode now accepts single value: <cmd with %s embeded> &<1 value only>
* updated error pattern matches when sourcing/pasting to host
* update script 1.01

1.00_021
* Default supplied acli.alias file now has a Version number and can be loaded with it
* Added ability to supply custom regex when capturing to variables from device output
* No more popup message about Perl Interpreter stopped working, when closing ConsoleZ

1.00_022
* Saving command output to invalid filename was genrating messages: print() on closed filehandle __ANONIO__
* It is now possible to use $vars on repeat options '@' and '&'
* Capturing variables with custom regex; now list generated has no duplicates and is alphabeticaly ordered
* Update script 1.02: changes to make update script always update itself first; persistent update logs
* Update script 1.02: No more popup message about Perl Interpreter stopped working, when closing ConsoleZ
* Changes to accommodate VOSS 4.2 40GbE channelized ports
* Connection, login, and interact timeouts are now configurable; default login timeout increased to 30secs

1.00_023
* Custom regex to capture variables can now be set to '$<n>' where n is the column number of the output
* Changed script syntax for SSH publickey auth; now supply private key with -k option; public key implied as .pub
* Advanced (|| or !!) grep patterns including ospf|rip|bgp|isis will automatically trigger 'router <prot>' context
  so you can now extract the complete SPB configuration with : cfg||spb,isis,cfm,i-sid

1.00_024
* Some extra fixes to work with 40GbE channelized port ranges
* Repeat (@) and ForLoop (&) commands are now properly processed even if invoked within a sourced/pasted script
* Show run advanced grep (||) for vlan, mlt, loopback, i-sid, & acl, now accept id ranges as well as perl regex
* Listening terminal paused on more prompt now behaves correctly when a new command is issued on tied terminal
* Fixed capture to variable port lists from output, which got partially broken in 1.00_023 changes
* Changes in 1.00_022 prevented $vars from derefencing on concatenated ';' commands on old 8600 PPCLI

1.00_025
* New queuing system for input buffer; now multiple commands separated by ';' or for loop commands (&) can be
  embedded into pasted commands or sourced commands and work as expected; enhanced @resume buffer command
* Improved behaviour for UnbufferPatterns; now terminal behaves correctly when dropping into shell or editing files
* Acli.alias 1.02: in 1.01 had made alias 'mlt [$id]' but this conflicts when creating an mlt; so reverted to 'mlt'
* Remote Annex functionality no longer makes assumptions of TCP port ranges; now an SSH or TELNET connection
  to the non 22 or 23 default port number, is assumed to be a terminal server connection, and if an Avaya switch
  is detected there, then an entry is created in the Annex table, which can be called with ACLI Annex tab
* Switch -p to use factory default credentials with Telnet now has fallback password which is set to rwa/rwa;
  means that telnet to a PassportERS which has a modified banner now will work (banner is not used with -p & SSH)
* Added @error embedded command to control whether or not pasted/sourced commands should stop when an error is seen
* Host error detection now also can set a level to either error or warning (latter will apply to errors + warnings)
  though note that host warning message patterns are not fully defined yet...
* Added @timestamp embedded command to print out client date and time stamp

1.00_026
* Grep for vlan X on output of show running-config was picking up also IP addresses which did not belong the the VLAN

1.00_027
* Fix in 1.00_026 failed; 2nd try

1.01  2015-05-18
* Advanced Grep (|| or !!) is now able to infer context from output indentation; this allows grep to work nicely
  on output such as 'show running config' of Secure Router or WLAN9100 as well as 'show isis lsdb detail'
* Advanced grep on show commands, summary of listed records was not working with multiple grep strings
* Empty lines on show commands are now stripped out by the grepping function
* Improved code to detect banners when doing advanced grep (|| or !!) on show commands
* When trying to save output to file and the file could not be created, this was not handled correctly
* Internal changes to how embedded @commands are handled; syntax is now automatically generated from tree
* Faster switch between Transparent and Interact mode when switching modes with CTRL-T, provided that same prompt
  seen; otherwise old behaviour of fully rediscovering device on transparent -> interact transition remains
* New @rediscover command to force a full device rediscovery (now that CTRL-T does not necessarily do so)
* Ability to set newline to just Carriage Return (CR); default remains Carriage Return + Line Feed (CR+LF)
* To change the CR / CR+LF setting once already connected, use ACLI> terminal newline
* To change the CR / CR+LF setting before connection or startup use new open and command line -c switch
* The backspace key is now processed when entering username/password, so corrections can be made before submitting
* Fixed crash when attempting to connect to peercp using "peercp connect" on single CPU systems
* Connection via serial port or via terminal server without -n switch was failing to discover device; fixed
* When connected via terminal server or serial port, console messages no longer mess up the active command prompt
* Modified code which extracts stackable banner to work nicely not just on default banners but custom ones also
* Several peercp fixes to ensure that any error from peercp will result in a closed connection and no stuck state
* Fixed condition which could result in unitialized value messages when doing @resume of for loop command (&) 

1.01_001
* Some tuning for grep indentation processing of 'show isis lsdb detail'

1.02  2015-06-09
* Changes in 1.01 could lead to non-responsive terminal under certain conditions when doing tab or syntax expand
* Picked up more recent version 1.13.0.15044 of ConsoleZ
* Update script 1.05: Able to take care of updating exe files (ConsoleZ update requires new Console.exe)
* Installer now creates a shortcut for ACLI Update script (also Uninstaller) under Start Menu Folder

1.03  2015-06-17
* Command line -g switch now allows the acli config grep capability to be piped from an offline config file
  hence one can for example do from unix/dos shell: % cat myconfig.cfg | acli -g "-ib ||spbm"
  or directly with offline config files: % acli -g "-ib ||spbm" myconfig1.cfg [myconfig2.cfg] ...
  the latter form will also work with wildcards over many files: % acli -g "-ib ||spbm" *.cfg
  grep requires correct family_type to function; BaystackERS is detected for stackables and assumed to be
  PassportERS/VOSS otherwise, for other family types need to manually set using the command line -f switch
* grep version 2.1: supplied grep now works on STDIN so can be piped to as well
* Fixed uninitialized error when aliases like 'pcap clear' executed in config context; introduced in 1.00_025
* Appending a ';' to command to prevent it being de-referenced as an alias, was no longer working; fixed
* Added ability to have a merge.alias file containing a personal set of aliases which are automatically merged with
  the ones provided in the default acli.alias file; merge.alias file should be created in path %USERPROFILE%\.acli
* Restored the ability to set the indentation spaces directly on the -i switch and added it to @? documentation
* Autogenerated syntax of embedded commands was giving a syntax error for a complete valid command appended with ?
* ERS8k config context 'wireless' was not handled properly, as the context pattern was missing; fixed
* Repeat (@) command was mis-behaving over large output and combined with tied terminals
* 1.01 changes resulted in trying to preserve prompt even during unbuffered output (like reboot on console session)
* Fixed issue where messages about 'uninitialized value $command in substitution' were displayed
* On large outputs when grep processing time exceeded the loop time, was not printing out any output; now at
  the very least the first line of available output is printed at every cycle
* Acli.alias 1.07: made changes to trace alias as it was preventing non-aliased trace commands from working
* Aftp version 0.08: reformatting of error messages

1.04  2015-07-27
* @log start <file> [-o|overwrite] overwrite switch was not working; now accepts -o, -overwrite or overwrite
* @log start <file> [-o|overwrite], executed while logging is already active, will now close the previous log file
  and start logging on the newly provided log file; previously only an error message was shown and no action taken
* Output logging would incorrectly re-start after a reconnect, even if it had been stopped before the reconnect
* Connection via a telnet relay host, will now fail and not be left on relay host if target host connection fails
* @source and '<' now accept arguments after the filename; the arguments are available as $1, $2, etc.. inside
  the script being sourced; $* is also accepted as a concatenation (separated by spaces) of all arguments
* @source and '<' now also work with filenames or arguments containing spaces, as long as they are quoted
* Variable $$ now always holds the switch name as extracted from the last prompt; use when saving output to $$.log
* Variables $_<name> now return Control:CLI:AvayaData attribute of the same name
* Command line -g switch was not working properly with small offline config snippets
* For loop command (&) on alias which required config mode and already in config mode, was failing on last sequence
* Output of "@alias show" is now more readable
* Saved @resume buffer was not being cleared correctly when a new input buffer was being generated
* For loop command (&) now works even if a single value is provided after the ampersand
* Captured $variables, which are not ports, are now sorted numerically if all values are numeric
* New command "@save reload" to reload device terminal settings from saved values

1.05  2015-08-07
* @rediscover command was producing unexpected prompts when terminal tied
* Terminal now makes use of new Control::CLI data_with_error option during login
* @vars show and @$ now list variables in alphanumeric order
* open annex: and open serial: menu now can be escaped with CTRL-] and an empty input does not close the terminal
* New command @vars prompt [optional] [ifunset] <$variable> ["Text to prompt user with"]
* Improved embedded command parsing code
* New command @echo on|off [output on|off]|info to disable echo of prompt, commands & output while sourcing/pasting
* New command @print to print text while sourcing
* Some fixes for command line -g offline grep not working well on non-config CLI output dumps
* Installer now sets startup directory for ACLI tab to %USERPROFILE%; otherwise it would default to %ACLIDIR%

1.06  2015-08-13
* Flush command to flush login credentials so that they are not automatically tried on new connection in same terminal
* Changed the way command output redirection works; now even embedded (e.g. @print) command output can be redirected
* Fixed detection of error patterns when sourcing commands which got broken for Stackables with changes made in 1.05
* Alias file syntax modified to accept semicolon (;) fragmented commands to be placed over separate lines

1.06_001
* Fixes error messages "Use of uninitialized value $1 in concatenation" appearing via terminal server / console

1.06_002
* If $variables are present in de-aliased commands (e.g. @vars prompt $var) they are no longer clobbered by the
  de-aliasing; only the $arguments declared for the alias will now be replaced in the resulting de-aliased command

1.06_003
* Adjusted cache timers for operation with ERS4000 when dumping commands, was failing to lock on device more prompt

1.06_004
* An SSH connection, when prompting for password, was restoring Term::ReadKey ReadMode; which meant that CTRL-C would
  thereafter be interpreted by Windows and would kill the program; this is now fixed and CTRL-C can be used on device 

1.07  2015-10-23
* Interactive mode optimized tab command expansion and syntax prompting; tab expansion will not dereference $variables
* Interactive mode tab command expansion and syntax prompting now also work with WLAN9100, WLAN2300 and Secure Router
* Connection to WLAN9100/2300 now defaults to interactive mode
* Grep with port ranges/lists is now more selective as to what constitutes a port list/range and will not try and
  expand as port range any numerical string
* Port ranges are now handled in grep offline (-g) mode on offline config files
* Syntax errors on @embedded commands now halt command script execution
* @alias, @history and @vars embedded commands now have option to enable/disable echo-ing which previously could only
  be set from the ACLI> prompt
* \$variables holding port lists, when captured, or shown with @vars or @ $ embedded commands are now displayed as
  more readable compacted port ranges but remain held as port lists internally just as before for dereferencing;
  to view the actual port list held in the variable use the new '@vars raw' and '@$ raw' commands
* Added new @run <script> command which works like existing @source command but sources <script>.run files which
  are loaded always from these paths, in this order: %ACLI% (if you defined it), ENV path $HOME/.acli (on Unix systems),
  %USERPROFILE%\.acli (on Windows) or in the ACLI install directory (%ACLIDIR%). The '.run' extension is implied.
  A '@run list' command displays available run scripts. Over time run scripts will be distributed with the ACLI
  distribution as well as updates and will appear in the ACLI instal directory. Hence customized run scripts
  should be placed in the $HOME/.acli or %USERPROFILE%\.acli directories
* Added @if, @elsif, @else, @endif; @while, @endloop; @loop, @until; @for, @endfor; @last, @next, @exit embedded
  commands; to be used only inside @run (or @source) scripts
* When telnet or ssh hopping, listening sockets are now restored when returning to a previous connection
* For loop command (&) now processes any list provided (not just port lists)
* Terminal server (annex) entries with no MAC are now updated if a new entry with the same Sysname is added
* Custom regex syntax to capture column number of output changed to '%<n>' [old syntax '$<n>' still works]

1.08  2015-12-06
* Run scripts listed by "@run list" are now listed in alphanumeric order
* Username & Password can now be specified on the command line for all of Telnet, SSH, and Relay Host connections
* New relay connection syntax allows connection to relay host to be any valid connection (ssh or telnet or serial)
  and the actual command to execute on the relay host (to attain the target host) can be fully specified, so an ssh
  second hop connection is now possible. Original syntax (which only worked with telnet) is still compatible.
  Hence to connect to a WLAN9100 AP from a VSP switch use: acli -r rwa:rwa@<VSP-IP> "ssh <9100-IP> -l admin[:admin]"
  and if you also want to use SSH for the 1st hop use: acli -r -l rwa:rwa <VSP-IP> "ssh <9100-IP> -l admin[:admin]"
  Original syntax for telnet on both hops still works: acli -r rwa:rwa@<VSP-IP> <stackable-IP>
  but this could now also be done with: acli -r rwa:rwa@<VSP-IP> "telnet [RW[:RW]]<stackable-IP>"
  which allows the target host username/password credentials to be specified as well
* Overdue cleanup of package supplied acli.alias file; moved away (to my own personal alias file!) aliases trace,
  default & delta; some of these were causing undesired behaviour in some cases
* Grep patterns used on alias which dereferences into a semicolon fragmented list of commands are now appended to
  every command in the list
* Added "@socket send <socket name> <command>" to send individual command to any terminal listening on socket name
* Added "@socket ping [<socket name>]" which easily allows to see what terminals are listening on a given socket name
* ACLI> "socket reload" changed to "socket names reload"
* Terminal server (annex) entries with no discovered MAC were still purging the annex file; should be fixed now
* With socket tied terminals, in error echo mode, late errors from slave terminals which did not make it in time
  to be displayed on the driving terminal before the prompt after the offending command is displayed, are now
  diplayed immediately upon arrival (and do not have to wait for the next prompt on driving terminal)
* Acli and open command line syntax for remote annex is now "annex:[<device-name> | <host/IP>#<port>]"
* Fixed an issue which could still result in failure to connect to a device requiring newline set to just Carriage
  Return (CR), using -c command line switch
* Grep filtering using "i-sid <number/list>" was not working properly, fixed; also now isid & i-sid are both accepted
* Socket echo modes were not working properly with peercp output (commands with switches -bothcpus & -peercpu) 

1.08_001
* Grep with large numbers (>99) was not working if the numbers sought in the output were followed by '('

1.08_002
* Some escape sequences from the login banner were getting through on some stackable beta loads

1.09  2016-02-08
* Grep with numbers or slot/port numbers will always match the entire number specified; hence 55 will not match 20055
  and 1/1 will not match 1/12; however if you really did want to match the string provided (and it happens to be only
  numbers) you can now quote the number and then it will be treated as a string; now "55" will match 20055
* Now the terminal is able to negotiate term type and window size; by default it will negotiate vt100 and 132x80;
  these settings are only negotiated during connection and are static (window size does not reflect the size of the
  current ConsoleZ window); also added command line -y & -z switches to set term type and window size
* Keyboard reading on unix (with readkey) enhanced to handle escape sequences on multiple reads if necessary
* Grep was not working on the output of some VOSS show commands (show ip ospf ase; show isis lsdb ip-unicast)
* Resolved minor issue with local terminal, when requesting command syntax (?) from the middle of the command buffer
* Was not switching to unbuffered mode when entering 'dbg enable' and getting the password prompt
* Repeat (@) command was not processing correctly a list of non-numeric values if they included the '-' character
* Quitting --more-- paged output will now disable sourcing mode, if that was enabled (e.g. ';' chained commands)
* Picked up more recent version 1.15.0.15253 of ConsoleZ
* With socket tied terminals, in echo modes 'error' and 'all', if a terminal connection is lost a message is now
  shown on the driving terminal
* Breaking out of a repeated (@) command no longer wipes the @repeat buffer if the repeated command was pasted or
  part of a script file
* Requesting syntax (?) of an embedded command beginning with @ which does not actually exist now behaves correctly
* Automatically responding 'Y' to yes/no prompts (when pasting commands or using an alias with semi-colon separated
  commands) is now not performed if the prompt contains 'reset' or 'reboot' unless user actually fed a -y switch
* Config grep was not handling correctly the new VOSS5.0 "logical-intf isis <id> vid <vids>" config context
* Optimized control and embedded command processing code (removed 600 lines)

1.09_001
* Relay connection now detects if target host has exhausted sessions and will fail the connection without
  completing login on relay host
* Negative Grep (!!) on VRF was failing to suppress route-map configuration for the VRF

1.09_002
* Some updates to banner patterns
* Fixed i-sid greps to also work with config lines for ip isid-list entries

2.00  2016-04-23
* Variables set for the 1st time within a @run (or @source) script can now be cleared with "@vars clear script"
* Enhanced Pseudo Terminal with configurable prompt, up to 99 terminals and ability to use @save commands with it
* Ability to view and manipulate remote annex file from ACLI control interface
* SSH keys are now always pre-loaded if found in the %ACLI%\.ssh (if you defined it), ENV path $HOME/.ssh
  (on Unix systems), %USERPROFILE%\.ssh (on Windows) or %ACLIDIR%\.ssh (the ACLI install directory); expected
  filename is 'id_rsa' or 'id_dsa' respectively for RSA and DSA private keys; the corresponding public key (which
  is also required) is expected with filenames 'id_rsa.pub' and 'id_dsa.pub'; the command line -k argument can
  still be used to override the default filename keys
* New SSH commands to load, unload and inspect the SSH keys used by the ACLI terminal
* SSH now fully supports use of known_hosts file which is looked for in %ACLI%\.ssh (if you defined it),
  ENV path $HOME/.ssh (on Unix systems), %USERPROFILE%\.ssh (on Windows) or %ACLIDIR%\.ssh (the ACLI install
  directory); if a known_hosts file is not found, one will be created in the 1st existing path of the above;
  If no entry exists in the known_hosts file for the host we are SSH connecting to, an entry will automatically
  be created without any need for user confirmation; if an entry exists but the key does not match, then the
  connection will fail as this indicates that the host key has changed (potentially a man in the middle attack)
* New SSH commands to list and delete entries in the known_hosts file
* New SSH commands to list and manage the SSH key files on the switch holding the Public keys used to authenticate
  incoming connections. It is now possible from the ACLI terminal (if it has SSH keys loaded) to install the
  public key directly onto the correct switch SSH file for the desired access level, and in the correct format
  (openssh or IETF). Commands are also available to delete the SSH files or just keys within those files
* New @launch command allows an existing ACLI terminal to spawn an additional ACLI terminal; this becomes useful
  with @run scripts so that the script driving the parent terminal can spawn a connection to another device
  (e.g. IST peer switch) and drive commands to the child terminal via the socket functionality (@socket send)
* New @quit command which does the same as CTRL-Q; however this can now be fed to a @launch-ed session with
  "@socket send" once that session is no longer required
* Grep streaming (-g) of offline config snippets not starting with 'config term' were not working properly
* Modified the way ACLI configuration contexts are traversed during configuration grep to better support nesting
* Default keep alive timer lowered from 10min to 4min, as some devices (WLAN9100) have a default timeout of 5min
* Session timeout now no longer does a definitive quit; instead the option to reconnect is offered
* Introduction of acli.ini file where default settings for the terminal can be permanently changed
* Keep alive and session timeouts can now be set via acli.ini and if set to 0, will disable them
* Serial port detection now handles case where registry could be accessed, but no serial ports found on system
* Variables can now be assigned an empty value '' as well as a value with leading or trailing spaces
* New highlight capability to easily spot a matched port or string in command output: command^<pattern>

2.01  2016-05-17
* If a password provided on command line contains characters '@' or ':' it can now be single quoted
* Perl expressions inside curlies where no longer executed if there was no variable in the expression
* Config port grep now works if Stackable uses "interface Ethernet" instead of "interface fastEthernet"
* Added embedded @sleep command to pause command execution for specified number of seconds
* Updated installer with Start Menu and Quick Launch paths for Windows versions after Vista
* Bundled aftp script v1.0 (for bulk file transfers to Avaya switches) now supports SFTP in addition to FTP

2.02  2016-06-25
* Embedded conditional operators were no longer able to dereference variables; got broken in 2.00
* @for command was not behaving correctly if fed an empty or undefined list
* @for, @while, @loop constructs were not working if their termination (@endfor, @endloop, @until) was last line
  in source file (or pasted sequence)
* Grep on igmp was not showing content of Stackable ip igmp profile range configuration
* All of perl metacharacters are now allowed in grep expression (with the exception of '?' which triggers syntax)
* "@ssh key info" now also shows the key's comment text

2.03  2016-09-05
* Fixed issue where a grep on a config context with sub configuration contexts within was not showing all the sub contexts
  E.g. a "cfg||vrf vrf1", where vrf1 has a route-map sequence 1 & 2, would only show the route-map sequence 1
* Doing a highlight of a protocol name string (such as ^bgp or ^ospf) was causing errors on terminal
* Using a highlight string (^text) was not preserving empty lines in output
* Socket tie with echo output all, to recover all output from tied terminals, was sometimes getting stuck and not
  recovering all output from some of the tied terminals; this would happen if the output was large and requiring packet
  fragmentation and no further output generated on tied terminal to trigger the sending of the subsequent fragment
* Output of command "@socket ping" now includes a summary line indicating how many socket ping responses were received
* It is now possible to perform grep on output of "@socket send" and "@socket ping" commands; in the former case
  syntax: ' @socket send <socket> "<cmd> || <grep>" ' will have the remote terminal execute "<cmd> || <grep>" while
  syntax: ' @socket send <socket> "<cmd>" || <grep> ' will now result in all output being sent back to driving terminal
  and local grep applied here
* Now possible to feed arguments to a switch command on the same command line with: switch-cmd // <input> [// <input>]..
  For instance, instead of sending command 'config term' (to avoid the interactive prompt asking for network|terminal)
  it is now possible to do 'config//term' or just 'config//'; in both cases the switch will prompt as usual for user
  input, in the first case the terminal will feed 'term' + carriage return, in the second case it will just feed carriage
  return; this example to enter config mode is not very useful as there was a way of avoiding the interactive prompt,
  however there are many other Stackable commands (e.g. commands to create users and set passwords) where there is no
  way to avoid the interactive prompt; for these this capability now allows the commands to be scripted inside run files
* Was not possible to delete device .ssh/ publickey files ending with _ietf with command "@ssh device-keys delete"
* Was not possible to delete device .ssh/ publickey files on 8600s in PPCLI mode with command "@ssh device-keys delete"
* Command "@ssh device-keys install" now always installs DSA keys in IETF format (like it already did for RSA keys);
  previously DSA keys were installed in openssh format but this was not working because the VOSS/PassportERS edit
  command cannot handle lines with more than 256 characters
* No syntax was available for embedded @sleep command
* Installer on Windows versions after Vista was not correctly installing the ACLI folder under Start Menu

2.04  2016-12-15
* Output of command "@run list" was not showing origin "package" for run scripts delivered in distribution
* Socket changes in 2.03 introduced a minor problem where <... missing output ...> warning is sometimes displayed
* Capture to variable syntax can now be used to capture output to more than 1 variable with the same command
  These syntaxes are new:
  <CLI command> > $var1,$var2... '%<n1>,%<n2>...'     capture to multiple variables value in many output columns
  <CLI command> >> $var1,$var2... '%<n1>,%<n2>...'    append to multiple variables value in many output columns
  <CLI command> > $var1,$var2... 'regex'[i]           capture to many variables; must use as many capturing () in regex
  <CLI command> >> $var1,$var2... 'regex'[i]          append to many variables; must use as many capturing () in regex
* Grep of a list or range of MLT ids was not working (got broken in version 2.00); now fixed
* Added new variable $@ which holds error of last switch command executed (or remains undefined if there was no error)
* Enhanced error detection logic in general; also now variable capture will not occur in the presence of an error
* Update script 1.10: When default ZIP download directory does not exist, user is asked to provide a valid directory
* Terminal was not working on Stackables where the "serial-secure" setting was enabled; this is because that setting
  results in the switch generating every second a Query Device Status escape sequence, to which the terminal must
  respond with a Report Device OK escape sequence, which was not happening before.
* If @echo is turned off in sourcing mode, it is now automatically reset to ON when exiting scripting mode
* Capturing variable or output to file on alias commands which chain multiple commands with ";" now works correctly
* Modified debugging logic to allow a customized Debug.pm module to be supplied
* Quiting a terminal with a failed Serial port connection could cause an error message
* Restarting a serial port connection (after pulling and re-inserting USB serial port) was generating an error
* When socket tie-ing a terminal to other terminals with echo mode 'all' output, sometimes the output on the driving
  terminal would lock as if one of the tied terminal did never return complete output; this should be fixed now
* Underlying error now always printed when connection fails (handy to check if PC firewall is blocking the connection)
* Added more intuitive 'ssh connect' and 'telnet' as aliases to the regular 'open' command
* History device-sent now also works in pseudo mode
* Formatting of BaystackERS banner now displays custom banner, messages about build info, last login and failed retries
* Variables are preserved if reconnecting after being disconnected by session timeout

2.04_001
* If username/password was requested on a Telnet connection to a BaystackERS, banner formatting changes made in 2.04
  did not working properly and failed to strip all escape sequences from the banner, resulting in a messed up font

2.04_002
* Inserted new debug level 16 for activating Control::CLI::AvayaData debug level 2 for debugging SerialPort issues

2.05  2017-02-09
* Timestamps on capture logs now work also when logging was started from command line and when closing terminal
* Added auto-log functionality whereby session logging is automatically started and stopped for each connection.
  The functionality can be enabled via the @log command, via ACLI control interface, command line switch (-j) and
  via the acli.ini file. The filename used is the IP address or hostname used for the connection which can be
  pre-pended with a timestamp string. The use and format of the timestamp string can be set in acli.ini via the
  auto_log_filename_str setting.
* Added the ability to set a logging path directory; if set, any logging (including the new auto-log functionality)
  will create the session log file in the provided path and not in the working directory. The logging directory can
  be set via the @log command, via ACLI control interface, command line switch (-i) and via the acli.ini file.
* Session logging now also works in pseudo terminal mode (but not auto-log functionality)
* Working directory and Quit_on_Disconnect can now also be set in the acli.ini file
* SSH known_hosts table is now listed in alpha-numerical order
* Relay host command line syntax with "relay cmd" syntax was not working in some formats; now this format works:
  acli -r <relay-ip> "ssh <host> -l <username>[:<password]"
* The @launch command now works correctly when provided with relay host syntax
* Acli.ini file was not working correctly for some settings
* Tied terminals in error echo mode would sometimes cause additional prompts to appear on the driving terminal at
  the end of a command output
* Added support for Avaya Private Label Switches (APLS), these are now recognized as VOSS devices
* New version of Control::CLI::AvayaData with new attributes 'is_voss', 'is_apls', 'apls_box_type' and 'brand_name'
  which can be leveraged in alias files and run scripts
* Enhanced grep streaming (-g) of offline configs by only displaying output for files where there is some output
* Fixed problem where terminal was unable to correctly set the Baud Rate on some USB Serial ports (issue seen
  with Ronald's Targus PA088)

2.06  2017-06-28
* Connection to a serial port was not possible if auto-log was enabled; the auto-log filename for serial
  connections is now "serial_<COM-port>"; on Unix systems a COM port like /dev/ttyS0 will have '/' '\' characters
  replaced with '-'
* On serial port connections, command tab expansion was not working properly anymore; this got broken in 2.04; fixed
* Doing ssh/telnet from connected host, when this connection is lost, the initial connection is no longer dropped
* Output from stackable command "ping <ip> continuous" now displays correctly in interactive mode
* Added ability to grep logical ISIS interfaces using any of these syntaxes:
  show running-config ||logical-intf [<intf-list>]
  show running-config ||lintf [<intf-list>]
  show running-config ||lisis [<intf-list>]
* Added support for VOSS mgmt Linux IP Stack show running-config configuration
* Added ability to grep management configuration using: show running-config ||mgmt [<port-list or id-list>]
* Variables consisting of port lists will now resolve with ranges applied, where possible, to ensure that we do not
  exceed the command maximum length of a command; for example a variable like $acc = 1/1-48,2/1-48,3/1-48 on a stack
  was expanding to a very large port list and this was resulting in config lines like "interface ethernet $acc"
  exceeding the maximum allowed command length
* Some fixes to stackable banner formatting on login
* Fixed issues with not being able to use certain characters (like ^) on French AZERTY keyboard as well as improving
  how CTRL characters are handled.
* Doing advanced grep (show run -ib|| route-map <name>) was not working if <name> contained spaces and was quoted
* Rebooting a switch into factory defaults from a serial/terminal server connection, and then try-ing to re-enter
  interactive mode by hitting CTRL-T was causing uninitialized value perl errors
* Doing a repeat command (@) where the command ended with the default variable $ (like: if $ @2) was failing
* ACLI version information now also reports the version of libssh2 used by underlying Net::SSH2
* Fixed memory leak when connecting via SSH. The leak was slow but noticeable if 10 or more SSH connections were kept
  running for a full day. The memory leak is fixed by using a later version of Net::SSH2 (0.63) and libssh2 (1.7.0)
* When an entry is added to SSH known_hosts file, the script name and version number are now set in the comment column
* Picked up more recent version 1.18.1.17087 of ConsoleZ
* More paging prompts and reconnect prompts used to only accept a lower case 'q' to quit, and would appear not to
  work if the CAPS Lock was accidentally enabled; now uppercase 'Q' is also accepted
* When output is logged to file, any highlight escape sequences present in the output are now removed
* Variable $$ was not always correctly set to the switch name, if the switch name contained '/' characters
* Applying grep to Stackable "show port-statistics port <list>" was omitting the port number header
* Hitting ALT key + mouse right click was causing error message: uninitialized value $event[6] in bitwise and (&)

2.06_001
* When connecting to a Standby CPU, during device detection, the following error was thrown:
  Control::CLI::AvayaData::attribute is trampling over existing poll structure of Control::CLI::AvayaData::attribute
* acli.alias v1.25: Some aliases have been removed; in particular the 'factory' alias which would result in an
  immediate switch reboot into factory defaults 

2.06_002
* On Darwin Perl 5.18 was throwing errors "uninitialized value $escHold in numeric eq" at every keyboard stroke
* Some modifications to support CLI syntax changes for VOSS mgmt Linux IP Stack (coming in VOSS7.0)

2.06_003
* Telnet login to ERS stackables was incorrectly detecting the same password prompt twice and thus sending the
  password a second time which would result in the password being echoed back in cleartext on the session

2.06_004
* Stackable banner was messed up when doing a telnet login from VSP to ERS
* acli.alias v1.26: ifname alias adjusted to work even if port names contain spaces

2.06_005
* Grep "show running-config ||mgmt" was not picking up "sys mgmt-virtual-ip" on dual CPU systems
* Changes to handle new timestamp banner added to all CLI show command output on VSP9000 rel4.2
* Picked up more recent version 1.18.2.17272 of ConsoleZ

3.00  2017-12-10
* Replaced module Control::CLI::AvayaData with drop in replacement Control::CLI::Extreme
* Now also supporting ExtremeXOS switches (currently only tested with Extreme Summit range)
* @socket ping enhanced so that the slave terminals will not respond unless their CLI is ready to take commands;
  also includes information as to whether slave terminal is in the midst of --more-- paged output
* Initial @socket tie command now is able to bump slave terminal off --more-- paged output
* Special characters '$%?@&;><|!^-/' used by ACLI can now be backslashed so that they are not processed but passed on
* All references to "Remote Annex" changed to "Terminal Server"; annex control command is now terminal-srv;
  connecting to a cached terminal server entry is now done with "trmsrv:" (older "annex:" still works though) 
* Capture to variable syntax can now be used to capture many column values per line into the same variable
  These syntaxes are new:
  <CLI command> > $var1 '%<n1>,%<n2>-[%<n3>]'         capture many output column values to one variable
  <CLI command> >> $var1 '%<n1>,%<n2>-[%<n3>]'        append many output column values to one variable
* Sourcing (@source/@run) a script within an already sourced script was not working properly
* Reserved variable $% (or % for short), which gets set when the terminal tied, now will always set itself to
  trailing number in switch name even if not in format '-<n>'
* The shorthand % for variable $% is no longer accepted inside curly brackets, as % is a valid Perl expression
3.012018-03-17
* When sourcing (@run, @source or pasting to terminal) scripts now run faster
* Added curlies to special characters '$%?@&;><|!^-/{}' used by ACLI which can now be backslashed; curlies can now be
  used as perl regular expressions in grep strings (but need to be backslashed)
* Backslashing of '^' in grep expressions was not working properly, e.g. to match all characters except: [\^<chars>]
* Added ability to synchronize ACLI's local more paging with more paging setting on underlying switch
  (@more sync enable|disable); useful when dumping huge tables and one wants to quit after just a few pages
* Ability to disable/enable more paging via CTRL-P now works across tied terminals
* Summary of displayed lines now updates to actually printed lines even if output is interrupted while more paging
* Added ability to provide empty password on connections, as this is often the case on defaulted ExtremeXOS switches
  Either of these syntaxes can now be used to provide a username + an empty password (':' following <username>)
  - Telnet syntax : "open <username>:@<IP or hostname>"
  - SSH syntax : "open -l <username>: <IP or hostname>"
* New variant of simple negative grep; a trailing '!' on a command will result in all empty lines to be removed from
  the command output. Can only be combined with other greps if it is the rightmost
* Made some changes to facilitate ACLI integration into mRemoteNG (when no TCP port number is specified in mRemoteNG
  connection profile the mRemoteNG %PORT% variable is always set to'0'; ACLI will ignore 0 tcp port numbers now);
  see README.txt file on how to integrate in mRemoteNG
* On stackables (BaystackERS) some lines in show running-config are always commented out, in some cases because the
  config line is redundant (setting was dynamically assigned, not user configured), in other cases because the config
  line contains passwords which have been blanked out (***) and in some cases it happens for no valid reason. In the
  latter case ACLI will now uncomment these lines so that they will appear in the displayed config. Right now, the
  only known line of this type which is handled is "! eapol enable"; others can be added on request
* SSH known_hosts is now able to add and delete entries on non default TCP port 22
* Previously, if connecting via Telnet or SSH to a non default TCP port, it was assumed that the connection was to a
  terminal server and hence after device discovery an entry would be added to the terminal-srv list. This assumption
  is now only still made if auto-detect is disabled (-n flag set) but is otherwise no longer made. Instead a new -t
  flag is introduced to force such a connection to be considered as a terminal server connection.
* Can now connect to ExtremeXOS switch configured with a 'before-login' banner which has to be acknowledged
* When running ACLI on a remote machine via an RDP session it was possible for special characters typed (like
  backspaces) to not get processed correctly if followed in quick succession by a Carriage Return
* Tab and syntax expansions were not working properly with backslashed pipe \| (i.e. pipe to be processed by switch)
* Special variable $$ was not being set properly on ExtremeXOS switch with unsaved config (dirty bit, * before prompt)
* Text in quotes printed by @print command no longer has multiple spaces replaced with a single space
* A socket listening terminal now alerts the controlling terminal if it is unable to process the commands sent to it
* Executing "peer telnet" on VSP8600 standby CP was giving an error and not automatically completing the login
* Added support for VOSS7.0 OVSDB configuration contexts, so that these can be viewed as expected in config greps
* Auto-log generated logging filename now replaces ':' characters in an IPv6 address with underscore
* Added new ACLI GUI Launcher script/app to automatically launch ACLI Tab sessions against a list of IP addresses.
  There is a new shortcut icon installed for this under Start/ACLI menu; the same app can also be launched by issuing
  'acligui' on a cmd session or 'acligui.vbs' in Start/Run; more details in README.txt

3.01_001
* ExtremeXOS switches spit out some escape sequences on some show commands which cause output to be unbuffered;
  these escape sequences are now removed from the output
* Scripts now continue correctly if the output of one command becomes unbuffered, provided user does not interact
  with the output by sending some characters
* acligui version 1.02: Fixed problem where uninitialized value error was displayed on command prompt

3.01_002
* Fix in previous patch (scripts if command becomes unbuffered) broke something else; the terminal stopped processing
  user input if output arriving after a local more prompt become unbuffered
* acligui version 1.03: Path argument -w can now also used to find the -f hostfile if the latter includes no path
* acligui version 1.03: Launch was failing if -w <work-dir> or -i <log-dir> path included spaces
* acligui version 1.03: Can now read hosts out of batch file

4.00  2019-02-09
* Windows distribution of ACLI now uses latest Strawberry Perl v5.26.1 (previously was using ActiveState)
* Windows distribution of ACLI now works with IPv6 (on Linux/Solaris it already did)
* Socket functionality for tie-ing terminals together now by default binds to just the loopback address 127.0.0.1
  (previously it would bind to all local IP interfaces)
* A new set of "@socket bind" commands is introduced to control socket binding
* A new socket_bind_ip_str key is introduced in acli.ini to control socket binding on startup
* Connection via relay host now works even if publickey SSH authentication is used to connect to the relay host
* New -m command line switch to automatically run a script once connected (added field to acligui also)
* Default character sent to host for newline is now Carriage Return (CR) to be consistent with most other terminals;
  previously was Carriage Return + Line Feed (CR+LF); either can still be set via -c switch or ACLI> terminal newline
* Added support for ISW (Extreme Networks industrial switch range)
* Doing "open -n serial:" (which lists all available serial ports) now works without Administrator rights and is
  able to display a description of the COM port
* acligui version 1.04: Ability to specify listening socket names (-s)
* acligui version 1.04: Ability to launch script on connections (-m)
* acligui version 1.04: Gui can be forced with -g switch even if credentials all set
* acligui version 1.04: Clear button was not working for logging directory field
* Pseudo mode is now configurable for port-range format and port-model (for offline config geenration)
* Keepalive timer can now be set to 0 (disabled); in which case it is the host switch which will timeout the session
  as with other non-ACLI terminals (i.e. the session timer will no longer work without keepalives)
* Socket disabled state (terminal will not listen to any sockets and cannot tie to any) can now be saved with @save
* When doing a grep "||vlan <id>" on a device showing lines containing "vlan 1-4095" was badly slowing down ACLI;
  the reason is that ACLI was expanding the range to "1,2,3,4,5...4095" before doing the grep match on the result;
  this issue was particularly visible on the ISW when doing grep on the verbose(all-defaults) running-config;
  so now the expansion for ranges is constrained to what the user is seeking to match; i.e. if user does
  "vlan||10,12" and we encounter a line with "vlan 1-4095", now the range is simply expanded to "10,12".
  The same optimization is now also applied to port ranges; so for a grep of "1/1,2/2,3/3", a range of 2/1-8/24
  will only expand to "2/2,3/3"; and if the grep ports are all outside the range then an empty range is used
* Using experimental version 1.18.4.18176 of ConsoleZ; this is now a 64bits version executable; it also supports
  the new ability to -reuse ConsoleZ windows in conjunction with a window identifier -i which was kindly added by
  the ConsoleZ author; see https://github.com/cbucher/console/issues/487
* acligui version 1.05: added -t argument and ability to specify containing window (leveraging above new ConsoleZ
  functionality)
* Added new XMC ACLI GUI Launcher app which is able to pull information about all discovered devices in Extreme
  Management Center (XMC) using the XMC North Bound Interface(NBI) which is available since XMC v8.1.2; information
  pulled can be customized in files xmcacli.graphql & xmcacli.ini to be rendered in a tabular output reflecting the
  XMC sites structure. The CLI credentials are also pulled, which means that ACLI can then be executed against any
  selected devices without having to specify the CLI credentials. Like for the regular ACLI GUI launcher, there is
  a new shortcut icon installed for this new app under Start/ACLI menu; the same app can also be launched by issuing
  'xmcacli' on a cmd session or 'xmcacli.vbs' in Start/Run; more details in README.txt
* When using the -n flag to connect, ACLI was behaving as purely a transparent terminal (like any other), and user
  would have to manually login when presented with username/password prompts, even if user had provided the username
  and password in the command line (with the exception of SSH, where the credentials would have been used for the
  connect stage); now, if credentials are supplied on the command line, with -n mode, ACLI will attempt to
  automatically log into the device. This enhancement allows ACLI to work with the new xmcacli GUI in such a way
  that user can connect to any XMC discovered device (even devices that ACLI does not support in interactive mode)
  without having to login on the devices (much like the embedded terminal available in XMC which we seek to replace!)
* ACLI conditional operators were not working properly if an undefined $variables was used on the right hand side of
  the operator
* Grep and highlight were not working on aliases of @embedded commands
* Grep of "cfg||vlan 2" would incorrectly show lines like "vlan ports 2/22 pvid 8"
* Capture to variable syntax using output column number values no longer requires %<n> values to be in single quotes:
  <CLI command> > $var1 %<n1>[,%<n2>-[%<n3>]]           capture many output column values to one variable
  <CLI command> >> $var1 %<n1>[,%<n2>-[%<n3>]]          append many output column values to one variable
  <CLI command> > $var1[,$var2...] %<n1>[,%<n2>...]     capture to multiple variables value in many output columns
  <CLI command> >> $var1[,$var2...] %<n1>[,%<n2>...]    append to multiple variables value in many output columns
* All @socket commands now display socket names alphabetically
* Doing a @socket tie for the very first time was not causing a new prompt on listening ACLI sessions
* A terminal stuck in local more paging, was no longer processing commands received from listening sockets
  (got broken due to changes in 3.01)
* Doing a @socket ping from a non tied terminal was giving an incorrect summary count of ping responses received
* When pasting a script on a socket tied terminal, script execution was not always stopping if an error was
  encountered on a listening terminal
* ACLI used to try and update any lines from switch stating "x out of y records displayed", based on the records
  actually printed out by ACLI (as opposed to what switch might have sent). But this could be misleading and
  suggest a problem on the switch CLI when in fact ACLI was maybe not counting the lines correctly. The new
  approach is that summary lines from the connected switch are not modified anymore and instead ACLI will add
  an extra line offering the record count as counted by ACLI.
* After using the @cls or @clear command, when output was paged to the screen, the line following the local
  more prompt, was starting with first two characters at the end of the previous line.
* A socket listening terminal now will report back to the controlling socket tied terminal if it is unable to
  execute the command sent to it via the socket. Previously such reporting was limited. In addition, the driving
  tied terminal, if in scripting mode, will also come out of scripting if it receives such a notification.
* Added embedded commands '@alias enable' & '@alias disable' to disable ACLI aliasing; these commands always
  existed under ACLI control interface, they have simply been added as embedded as well.
* Added new embedded commands to create & delete directories within ACLI (@mkdir, @rmdir); also added an 'mcd'
  predefined alias which allows creation of a new directory and changing into it immediately afterwards
* Terminal-server cached entries file is now acli.trmsrv (will still load existing old filename acli.annex)
* Terminal-server commands under ACLI control interface renamed from 'terminal-srv' to 'trmsrv'
* Terminal-server command 'flush' is now renamed to 'trmsrv delete file'
* Terminal-server cached file now supports SSH entries and a t/s column after the IP address identifies whether
  the connection is to be performed via SSH or Telnet; entries without the t/s identifier will default to
  Telnet as before
* Terminal-server cached file now includes an optional comments column
* Terminal-server cached file (acli.trmsrv) can now have its entries sorted by 3 different criterias:
  - ip: entries are sorted by IP address (or hostname) and then by port number
  - name: entries are sorted by recorded switch name
  - cmnt: entries are sorted by alphanumeric comparison of the comments field
  The sorting scheme can be set via new ACLI control 'trmsrv sort' command and can also be set directly in the
  acli.trmsrv file, by adding a line ":sort = ip|name|cmnt".
  If no sort method is set, then the old behaviour still applies where terminal-server entries will not be
  sorted and new additions will simply be appended to the list.
* Terminal-server cached file (acli.trmsrv) can now have a static flag set. The old behaviour when a new
  entry was added to the file, following device auto-discovery, was to automatically delete any other existing
  entries in the file where the same device MAC was recorded or, if no MAC recorded, where the switch name is
  the same. This behaviour still applies if the new static flag is not set. If instead the static flag is set
  then no entry will be deleted from the file.
  The static flag can be set via new ACLI control 'trmsrv static' command and can also be set directly in the
  acli.trmsrv file, by adding a line ":static = 1".
* A terminal-server list file (acli.trmsrv) can now be manually placed in the ACLI install directory. In shared
  installations, the file will be visible by all users and will immediately pre-populate a personal acli.trmsrv
  copy. The 'trmsrv delete file' command will not delete the acli.trmsrv file located in the ACLI install path.
* When a terminal-server entry is added/updated following device auto-discovery, a timestamp date is now also
  included in the extra data details added to the entry.
* Terminal-server pattern to filter entries in the cached file now operates in case insensitive mode and will
  search for a match across all of switch name, recorded details, and comments field.
* New terminal-server 'trmsrv connect' command under ACLI control interface offers an alternative way to start
  a connection from the cached list, instead of using the 'open trmsrv:' command.
* Performing variable capture for multiple variables with a regex was generating errors if the no captured
  value was obtained from the regex for one of the variables.
* The regex supplied for capturing to variables now works if it contains backslashed '(' & ')' characters
* Switched to bsd_glob due to warnings:
  File::Glob::glob() will disappear in perl 5.30. Use File::Glob::bsd_glob() instead.
* ACLI command "send" as well as embedded command "@send" has a new subcommand "send line" to send a string
  followed by carriage return to the connected host, without waiting for a prompt back; the existing command
  "send string" has also been enhanced to accept "\n" in the string indicating a carriage return.
* Semi-colon ';' fragmented lines are now processed across all switches supported in ACLI interactive mode.
  Previously, older PassportERS devices in PPCLI mode, would natively support ';' between commands and so
  ACLI would not split the commands in that case; to stop ACLI from fragmenting semi-colon separated lines
  place a backslash in front of the semi-colon ';'.
* These capture to variable syntaxes:
  <CLI command> > $var1,$var2... 'regex'[i]   capture to many variables; must use as many capturing () in regex
  <CLI command> >> $var1,$var2... 'regex'[i]  append to many variables; must use as many capturing () in regex
  Can now be used to capture multiple values per line into the respective variables. See manual.
* Reserved variable $$ , which holds the switch name as extracted from the last prompt, now correctly discards
  '\<level-X\>' string appended by TACACS (on BaystackERS platforms). Also, from now on, the $$ variable will
  ensure that the switch name only contains characters which can be used in a filename; any character which
  cannot be used in a filename (/\:*?"<>|) will be replaced with an underscore '_'. This is because usually
  the $$ variable is used to redirect output to a file named after the switch. So, for instance, if the switch
  prompt was 'JOL_Server-1/A1#%', the retained $$ name will be 'JOL_Server-1_A1'. To obtain the actual switch
  name the $_sysname attribute variable can still be used.
* ACLI distribution now includes a manual / help file for which a shortcut is installed under Start / ACLI

4.01  2018-11-03
* The -m switch to execute a run script was not working on ACLI control commands 'open', 'telnet' and 'ssh connect'
  and was also not working on the embedded '@launch' command.
* Embedded @launch command now accepts a -u switch to specify the ConsoleZ containing window.
* Embedded @launch command enhanced to also work with MAC OS distribution, both with Terminal app and iTerm2
* Embedded commands could crash terminal if entered with too many arguments
* Backspace key is now properly read on MAC OS
* Minor updates to applications xmcacli, acligui and aftp to work on MAC OS 
* Use of ACLI sockets by multiple users on the same machine (e.g. RDP server) could result in clashes, where a command
  executed by one user gets executed on ACLI sessions of a different user if using the same socket. This is now
  resolved by encoding the username in socket datagrams. New commands are added to enable/disable the functionality
  '@socket username enable/disable' and 'socket username enable/disable' under the ACLI control interface. Also a
  new key 'socket_send_username_flg' is available in ACLI ini file to control this. By default the username is used.
* Repeating a command with '&<comma-separated-list>' was not working with slot/port ranges
* Executing "acli serial:" was no longer working; was not showing available serial COM ports

4.01_001
* Simple positive and negative grep was not expanding port ranges in output to filter
* Keepalive switch prompts were not properly suppressed in scripting mode during @var prompt
* Keepalive switch prompts were not always suppressed on XOS
* Performing command syntax expansion in interactive mode was not working properly if @alias was disabled
* Adding regular expressions to a MAC address in ACLI grep was not always working correctly
* Changes to terminal-server cached file (acli.trmsrv) introduced in 4.00 broke the way this was working before;
  when connecting to an existing entry, this would delete that entry from the file; also the file was getting
  saved upside down; this is corrected now.

4.02  2019-05-08
* Enhanced \$variable support to now support array and hash type variables; ACLI now supports the following variables:
  - \$\<name\> = \<value\>                                  Simple flat variable (only type previously supported)
  - $\<name\>[] = (\<val1\>; \<val2\>)                       List/Array type variable
  - $\<name\>[\<index\>]                                   De-references as value held in array index (\<index\> is 1-based)
  - $\<name\>[1]                                         De-references as value held in first array element
  - $\<name\>[0] or $\<name\>\[$\#\<name\>\]                    De-references as value held in last array element
  - $\<name\>[]                                          De-references as list of array indexes if included in a command
  - $\<name\>{} = (\<key1\> =\> \<val1\>; \<key2\> =\> \<val2\>)   Hash type variable
  - $\<name\>{\<key\>}                                     De-references as value held in hash key element
  - $\<name\>{}                                          De-references as list of hash keys if included in a command
  - $\'\<name\> or $\'\<name\>\[\<idx\>\] or $\'\<name\>\{\<key\>\}     De-references raw variable (without compacting into a range)
  - $\#\<name\> or $\#\<name\>\[\<idx\>\] or $\#\<name\>\{\<key\>\}     De-references as number of comma separated values held in variable
  - $\#\<name-of-list-or-hash\>                           De-references as number of elements or keys held in array or hash
* Capture to variable now by default will only capture the 1st occurrence in each line of output. In the case of
  capturing port numbers, if port numbers appear twice on the same line of output, only the 1st occurrence will get
  captured (which is usually the desired behaviuor). To capture multiple times per line of output a new -g flag is
  introduced which can be placed after the variable capture syntax, in either of these forms:
  \<CLI command\> \> $variable  [-g]
  \<CLI command\> \> $var1,$var2... 'regex'[g]
  \<CLI command\> \> $var1,$var2... 'regex' [-g]
* New @my embedded command can be used to declare variables in a script context so that they do not pollute the
  variable space of the device. The following syntaxes are allowed:
    @my $var=1/1
    @my $var1, $var2, $h{}, $l[]
    @my $pre_*
  The first syntax allows declaring one variable only and at the same time initializes a value in the variable.
  The second syntax allows declaration of a comma separated list of variables.
  The last syntax defined a variable prefix match pattern, where variable names beginning with '$pre_', in this case,
  are automatically declared; for example if script's variables are named $pre_var1, $pre_var2, etc...
* Ability to automatically execute a script upon connection (-m switch) was not working
* A message is now displayed indicating which terminal-server cache file is being loaded
* New @printf embedded command: @printf "<formatting>", <value1>[,<value2>..]
  Allows printing of text with embedded variables; <formatting> string takes Perl's printf/sprinf syntax
  Carriage return sequences "\n" can be included in the <formatting string>
* Existing @print embedded command now also accepts carriage return sequences "\n" provided the text supplied is
  single or double quoted
* New @put embedded command which is identical to @print except that no carriage return is appended to the supplied
  text
* Change made in 3.01 to run ACLI faster during scripting mode (@run, @source, pasting to terminal, repeating command)
  were letting the mainloop run flat out which was too aggressive (CPU up to 100% if 10+ ACLI terminals in use);
  now in scripting mode the mainloop is allowed to run faster only by a factor of 5 (not exceeding 20% CPU); only
  scripting mode in pseudo terminal mode is still allowed to run at full speed
* Additional fixes to make sure we always come out of scripting mode under all conditions (interactive, transparent
  and pseudo modes) when script completes or is interrupted or when @vars prompt is used
* Minor updates to applications aftp and acmd to accept IPv6 addresses; acmd can now also take a password from
  command line
* A new master_trmsrv_file_str key is introduced in acli.ini to set a master terminal-server file. This key should
  either point to a filename under the ACLI install directory or to the full path to any other file (if not located
  in the ACLI directory). If set and the file exists, the date of the file will be compared with the date of the
  user's personal terminal-server file (%USERPROFILE%\.acli\acli.trmsrv), if it exists, and whichever is the most
  recent will be used. Setting this key allows any modification of the master terminal-server file to automatically
  result in it being used next time without having to execute 'trmsrv delete file' under the ACLI control interface
* New '@alias list' embedded command allows listing a summary of available aliases; the acli.alias file syntax is
  changed to allow a description summary line for the alias; see the acli.alias file for syntax
* If listening sockets were provided via the ACLI -s command line switch, it was not possible to reload listening
  sockets defined for device in the saved vars file (@save info); now if the embedded '@save reload' command is
  executed the saved sockets will be applied to the device
* In scripting mode, if a command generated an error, the script would halt and sometimes the error message would
  print twice, instead of once
* The graphql definitions of the XMC ACLI GUI Launcher app (xmcacli) are now modified to correctly function with
  XMC version 8.2.x which is now GA; if still using XMC 8.1.x please modify the graphql keys as explained in the
  manual / help file
* ACLI summary count of displayed lines from a show command was not always working properly
* History recall of past command using cursor up/down keys, is now correctly reset if the command line is cleared
  using the CTRL-U sequence
* Attribute variable $_sysname was not correctly reading BaystackERS sysname if this contained spaces
* Changes to ensure ACLI handles correctly connecting to Insight VM console (virtual-service <name> console)
* Changes to ensure ACLI correctly handles new VSP7400 Insight ports 1/s1 & 1/s2
* Port ranges were not being compressed correctly in presence of channelized ports
* Generation of port ranges was not working across slots
* Updates to ExtremXOS error patterns
* Quotes were not properly handled if grep string was comma separated and only a portion of the string was quoted
* Some fixes around interactive use on ExtremeXOS; in some cases when hitting tab command expansion ACLI was losing
  track to the device prompt
* Custom regex for capturing to variables now also works if using double quotes instead of single quotes
* When providing multiple grep patterns, these can be comma separated. This was also working if the patterns was
  enclosed by quotes; both these examples worked in the same way:
  show sys software |^Slot# :,^Version
  show sys software |'^Slot# :,^Version'
  .. by providing output lines which matched either '^Slot# :' or '^Version'.
  However, the second form prevented matching patterns which contain the comma character (without backslashing it).
  So from this version onwards only the first syntax will work, while the second syntax will now instead look for
  a single pattern '^Slot# :,^Version'. There were a number of pre-defined aliases which were using the second form
  and these have all been modified in the updated acli.alias file (you might need to check your merge.alias file)
* XMC ACLI GUI Launcher app (xmcacli) was not correctly displaying the 1st device output column (Sysname) if no
  XMC username/password or grep/site filtering entries were defined in the xmcacli.ini file

4.02_001
* @printf would fail if a listed variable was replaced with a comma separated value
* Update to XOS y/n confirmation prompts
* @save info was not working after reconnecting to same device

4.02_002
* Paging through --more-- output on XOS console port could throw error "uninitialized value in regexp compilation"

4.02_003
* Offline grep (-g) of VSP9k show run sometimes unable to remove empty configuration contexts if trailing spaces
  present on some configuration lines (if offline dumps were taken by holding space bar to skip --more-- prompts)
* Was not possible to use the command repeat operator (&) as part of a semi-colon fragmented command
* Variable was not dereferenced if immediately followed by backslash character
* Connecting to VSP8600 standby CPU via "peer telnet" command was causing device discovery continuously
* Highlight was not working if a second match was just one space after a previous match
* Terminals which are listening on a socket but never succeeded connection, no longer produce error:
  "Error from : Cannot process command as no connection"

4.02_004
* Update to VSP config grep patters to work with new "endpoint-tracking" commands

4.03  2020-02-29
* Socket listen/tie functionality is re-written to use IP Multicast. The old implementation used to use broadcasts
  on the loopback interface which worked fine on Windows, but this cannot work on MAC OS as it does not allow
  broadcast on lo0. The new Multicast implementation by default also runs on the loopback interface 127.0.0.1,
  but can be configured to work on any other interface
* Ability to provide empty password on -n (transparent) connections for non-Extreme recognized devices
* Capturing variables with syntax "> $var %n-" will now capture all columns from n to 299 (previously max was 99)
* Embedded commands @ls,@dir,@mkdir,@rmdir are now also available under ACLI control interface
* Interactive mode was not working well on ExtremeXOS via serial port when using '?' syntax help
* Embedded commands "@socket send" and "@socket ping" were not receiving socket output in scripting mode
* Embedded commands "@socket send" now leverages delay prompt timer to wait for complete socket output
* Summary count of displayed records was not detected, and acli's count added, if it also matched a banner pattern
* Added support for Extreme Network product family_type: SLX, Wing, Series200
* SLX is annoying in that it enforces no show commands in config mode, unless preceeded by "do"; which would be ok
  if it also tolerated the use of "do" outside of config mode, so then one could simply prepend "do" to all alias
  commands; but no, SLX does not allow "do" outside of config mode. Hence, added logic to automatically remove "do"
  from commands executed outside of config mode; this way one can simply use "do" in all alias commands and they
  will work in both config mode and outside config mode.
* New hide_timestamps_flg key is introduced in acli.ini which will hide from the ACLI display window any timestamp
  banner which some switches produce before show commands. The timestamp banners will however still be recorded in
  file logging, if enabled, or when redirecting output to file. The same feature can also be enabled/disabled in
  ACLI control interface using "terminal hidetimestamp" command.
* Redefined how repeat options '@' and '&' behave in conjunction with semicolon fragmented commands:
   a - <cmd1> &<range-list>Same as before; will repeat cmd1 inserting values for %s at every iteration
   b - <cmd1>; &<range-list>New, but same as above
   c - <cmd1>; <cmd2> &<range-list>Executes cmd1 once, then repeats cmd2
   d - <cmd1>; <cmd2>; &<range-list>Will repeat cmd1 + cmd2
   e - <cmd1> &<range-list>; <cmd2>Repeats cmd1, then executes cmd2 once
  Previously only syntaxes a,c,e were allowed but syntax c would behave like syntax d.
* Connection via relay (-r) credentials with empty password for final host can now be included on command line used
* New Serial EDiting functionality (SED) allows to set patterns and their replacement to be applied either to input
  or output stream to/from device. For the output direction only, this functionality also includes the ability to
  re-colour the output stream. This functionality is available via the embedded "@sed" command or the equivalent
  "sed" command under ACLI control interface, as well as via file "acli.sed" which can be either placed in the ACLI
  install directory or the user's home directory. A default acli.sed file is provided which offers default patterns
  and examples to re-colour certain message keywords (error, warning, up, down, etc) or addresses (MAC, IPv4, IPv6,
  etc). Refer to the acli.sed file for further information.
* Because of the new SED re-colouring in use, the default highlight formatting is changed to a red background
  instead of foreground. Unless you had customized the highlight in acli.ini in which case nothing will change.
* In scripting mode, when executing a script with @run or @source, and the terminal is socket tied, the listening
  terminals will also get instructed to execute the very same script. However, thereafter, commands inside the
  script file will no longer be sent over the socket (there is normally no need, as the listening terminals are
  also running the same script. However in some scripting applications it becomes useful if the script can be
  executed on one terminal instance only, and then that script initiates "@socket tie" and "@socket echo all" and
  then can decide exactly which commands to execute locally + over the socket. For this purpose a new '-o' switch
  is introduced which can be appended to any CLI or embedded command and will ensure it gets sent over the socket
  in scripting mode. The same switch will ensure that the command is sent with socket echo mode "all", even if the
  globally set echo mode is "none" or "error". The -o switch can only be applied on the command before any
  redirection (to file or variable) and before any repeat option; any variables in the command will also be
  dereferenced before the command is sent to the socket. The -o switch can also be immediately followed by a number
  which will add a delay time to wait for output from the sockets: -o[N]
* Assigning an empty string '' to a variable will now delete that variable, just like when assigning nothing to it.
  Both these forms are now equivalent:
     $var = ''
     $var =
  Previously it was possible to assign the empty string to a variable; but this caused problems in scripts, where
  such a variable would de-reference to nothing (quotes are removed from '') and cause errors on commands expecting
  a value. Whereas a non-defined variable automatically gets replaced with '' (without removing the quotes) and so
  we don't have that problem.
* Repeat command (@) was not working if applied on multiple commands (e.g. semicolon fragmented or sourced file)
  and a @sleep command was within.
* Increased default interact timeout value from 15 to 22 secs; this is for SLX9850 chassis which takes an eternity
  to execute command "show system" during initial ACLI detection phase.
* Changed syntax of embedded command from "@socket send <socket name> <command>" to
  "@socket send <socket name> [<wait-time-secs>] <command>"; the optional timer allows the controlling terminal to
  wait longer than it would normally (half a sec).
* Last error $@ variable is now reset before executing a "@socket send" command; previously it would only reset
  before sending a new CLI command to the local switch.
* On SLX commands referencing urls like flash://<file> now are not interpreted as additional arguments after '//'
* Updated VOSS config patterns to correctly grep new VOSS8.1 "router bfd" configuration context
* Capturing to hash variable using custom regex with alternate captures on different output lines was failing if
  the 1st captured value was for the hash value rather than the hash key:
  show isis lsdb tlv 135 detail |Prefix Length:,IP Address: > $ipMask{%2} 'Length: (\d+)|Address: (\S+)'
* Capturing command output to file was not behaving correctly (aborting) if the output was immediately switched to
  unbuffered mode; now, when capturing to file the output of "show run", if the output is "Another show or save in
  progress" output to file is aborted and the output is visible on session terminal.
* Update to ERS port-statistics patterns to easy greping output
* In version 4.02 port ranges were enhanced to produce ranges spanning slots, e.g. 1/1-2/48; however this was a
  problem with BaystackERS which does support port ranges but not if they span slots. ACLI is now updated so that
  port ranges spanning slots are automatically not used for BaystackERS. At the same time the ability to create
  port ranges spanning more than 1 slot has been made configurable and by default disabled. In short, by default,
  ACLI 4.03 will behave the same as pre-4.02 with regards to port ranges. However the option to re-enable port
  ranges spanning slots can be turned back on either under the ACLI control interface (using command 'terminal
  portrange spanslots') or by setting the 'port_ranges_span_slots_flg' in the ACLI.ini file. An additional key 
  'default_port_range_mode_val' is provided to control how ACLI will display port ranges in variables when
  connected to a device which does not support any port ranges at all (typically Wireless APs).
* Ability to unconstrain port ranges from actual switch ports. If 'ALL' or something like 1/1-3/1 is seen, grepped
  or captured to a $var, ACLI will know exactly to what port numbers that will refer to. However in some script
  applications it can be useful to capture output from other switches tied via the socket functionality, and in
  this case any port ranges captured from that output need to be unconstrained from whatever ports the locally
  connect switch may have. To enable this feature either use 'terminal portrange unconstrain enable' from the
  ACLI control interface, or to activate the feature directly in the script, the 'terminal' command and all of
  the portrange options is now also exposed as an embedded command '@terminal'. Key 'port_ranges_unconstrain_flg' is
  also added to acli.ini.
* Commands 'status' and 'terminal hidetimestamp' are now also exposed as embedded commands to be used in scripts.
* In ACLI 4.01, repeating a command with '&<comma-separated-list>' was enhanced to automatically expand slot/port
  ranges; but this change broke the functionality for lists not consisting of ports (e.g. file names). Working
  with SLX now (where port ranges within the same slot are allowed, but not across slots) it becomes useful if
  the repeat command functionality, as well as the @for command, do not automatically expand port ranges into
  port lists. For example an SLX9850 port range such as 1/10-13,4/10-13 used in repeat command '&' or @for loop
  can simply execute 2 cycles (as the SLX can then handle 1/10-13 alone on the first iteration and 4/10-13 on
  the second iteration; whereas expanding the port ranges into port lists would necessitate more iterations).
  So from now on both repeat command '&' and the @for command will not automatically expand port ranges. For both
  however, a new syntax is now available to force a port range expansion into a full port list by adding the "'"
  character immediately following the '&' character:
     <command-to-execute> &'<port-range-or-list>
     @for <$var> &'<port-range-or-list>
  The original problem, when supplying a list not consisting of ports (e.g file names) is also solved, for both
  syntaxes.
* Fixed issue where port ranges were not working correctly on XOS with VPEX slot number 100 and over.
* XMC ACLI GUI Launcher app (xmcacli) v1.04 updated to support XA1400 XMC new family type 'Extreme Access Series'
* A new spb-ect.pl script is added to the distribution; can be useful to understand how SPB will allocate paths
  to BVLANs. Execute it as 'sbp-ect' in any DOS box.
* ACLI was crashing when dealing with port ranges on ISW
* ACLI discovery was crashing if ISW was already in config mode
* Flag -g in variable capture syntax was not working properly: <CLI command> > $variable [-g]
* In sourcing mode, undefined $variables included in comma separated lists now disappear without affecting the
  list
* Variables will now be dereferenced in variable capture regex: <cmd> > $captureVar "($otherVar)"
* Appending an undefined variable to an already defined variable no longer undefines the latter
* Simultaneously launching many ACLI instances (via acligui or xmcacli) to connect with SSH and where the
  device's SSH key was not already stored in the known_hosts file could result in the known_hosts file getting
  corrupted as multiple instances of ACLI try updating the same file. The problem is that creation of the
  new or updated known_hosts file is handed off to Net::SSH2::KnownHosts module's writefile() method which does
  not perform any file locking. ACLI now performs file locking on a dummy file (.known_hosts.acli) which will
  be located in the same path as the known_hosts file but will remain empty. Any read/write operation to the
  real known_hosts file will now be sandwitched with file lock of the dummy file to prevent any corruption. 

4.04  2020-05-02
* Upon connection, when loading a var file which contains listening sockets, if there is a problem opening some of
  those sockets a message is now displayed on screen.
* Modification of VSP config context patterns to accommodate XA1400 logical-intf isis lines which now include the mtu
  size.
* Optimized and better integrated code which applies @sed output patterns.
* Error detection on VOSS CLI commands was sometimes failing because only the 1st four lines of output were inspected
  but since the addition of the VOSS timestamp on show commands the error message could be 3 lines deeper in the
  output; error checking now looks at 1st seven lines.
* Highlight of a port in the output of show-run was no longer expanding port ranges correctly to highlight the port
  (got broken in 4.00 when grep was optimized to expand port ranges constrained to grep-ed ports only)
* Highlight (^) of a string already re-coloured by @sed now takes precedence over @sed colouring
* When tie-ing to a socket, a carriage return is sent to listening terminals, but this is now no longer done if the
  socket tie command was executed in scripting mode.
* Capturing to an invalid variable name could result in ACLI going into an infinite loop on a subsequent command and
  displaying forever error 'Use of uninitialized value in splice'
* Aliases which resolved to a command including ACLI variables (not alias variables) would result in those variables
  not getting dereferenced. This was because ACLI variable dereferencing was only performed before checking for
  aliases, not after. Command processing now runs as a loop; if an alias is resolved, command processing restarts
  from the scratch. This resolves the above problem and also means that now aliases are recursive (i.e. an alias can
  use other aliases). Checks are in place to prevent alias dereferencing loops.
* Listening sockets blocked in a --more-- prompt or executing commands in sourcing mode can now be unblocked/stopped
  by hitting the Return key in quick succession from the controlling tied terminal.
* Update to acli.sed file: IPv6 address and port highlighting pattern updates
* Addition of SSH hostnames to the known_hosts file was done without first putting the hostname into lowercase. This
  could result in the same hostname appearing multiple times in the known_hosts file, depending if it was provided to
  ACLI with some uppercase characters or not. The same applied to compact vs. expanded IPv6 addresses which could
  result in the same IPv6 address appearing twice (compact + full notation). The following changes are made:
  - New entries added to known_hosts file are always added as lowercase (same as OpenSSH does)
  - New IPv6 address entries added to known_hosts file are always added in IPv6 compact notation
  - Before hostnames are checked against known_hosts file they are converted to lowercase
  - Before IPv6 addresses are checked against known_hosts file they are converted to IPv6 compact notation
  - Deletion of a hostname from known_hosts file will now delete all matching entries regardless of upper/lower case
  - Deletion of an IPv6 address from known_hosts file will delete the compact notation entry in the file even if the
    address was not given in compact notation
  - A new "ssh known-hosts clense" command is provided under ACLI control interface which will parse the SSH
    known_hosts file and delete any duplicate or corrupted entries (corrupted entries could have been produced by
    ACLI versions prior to 4.03), will reformat to lowercase any hostname entries containing uppercase characters
    and will convert to IPv6 compact notation any IPv6 address found in full notation. A report is provided on
    completion.
* Tab expansion and syntax output was not working properly on SLX via serial port. Major overhaul of the tab &
  syntax functionality and re-tested with all the family types still available.
* Output of VOSS show running-config can now be grepped for application (restconf & cloudiq): cfg||app
* CLI syntax error message pointer '    ^' was not synchronized with ACLI prompt suffix on XOS
* A control character is added to clear the screen and by default it is CTRL-L, but can be changed under ACLI control
  interface or via acli.ini with key 'ctrl_clear_screen'
* Control characters can now be deleted under ACLI control interface or by setting them to the empty string in
  acli.ini; also some fixes with setting the control characters.
* For this version of ACLI, module Control::CLI must be updated to version 2.09
* Feeding arguments via // was not working on XOS on Y/N prompts; new default 'sv' alias now allows saving config to
  a file by answering Y to the first prompt and N to the second prompt (where it asks whether to change the default
  database) by issuing "save configuration <name> // y // n"
* ACLI grep patterns no longer process Perl regular expression metacharacters when enclosed by single quotes; if
  using regular expressions for grep enclose the patterns in double quotes (or no quotes at all).

4.05  2020-07-12
* ACLI Summary count of record lines was sometimes printed twice.
* In sourcing mode, undefined variables are dereferenced with '' but if now '' appears in a comma separated value
  it is removed, except for @printf.
* Variable capture -g switch for capturing multiple matches was not processed if some variables dereferenced from
  command line.
* Tab expansion on ISW was not working properly if the expanded command was not the same case as what entered
* Changes in 4.04 had broken preserving of embedded variables in partial command followed by '?' for syntax checking
* Alias was failing to get loaded correctly if it mapped to an acli script semi-colon fragmented over multiple lines
  where a line was a $variable assignment 
* Capture to variable was failing to capture XOS VPEX ports on slot numbers 100 and higher (3 digit slots)
* Update to BaystackERS and Passport ERS VOSS error patterns
* Was not locking correctly onto BaystackERS CLI prompts with the TACACS suffix "<level-XX>"
* Insight ports were not highlighted by @sed colour patterns
* Insight ports were not captured to variable
* Some fixes to show command banner re-formatting

5.00  2020-12-07
* ACLI is now broken into a number of Perl module files for easier maintenance going forward
* The way ACLI commands are parsed and processed in interactive mode has completely changed in favour of a more
  robust approach which will be easier to maintain and enhance going forward
* Update to VOSS error patterns
* Attribute detection now works correctly with new dual persona 5520 switches
* OOB attributes work correctly with new VSP segmented management stack
* Hitting CTRL-C on ACLI would sometime result in "Terminating on signal SIGINT(2), Terminate batch job (Y/N)?"
  This was only happening if the ACLI screen had been previously cleared either with the embedded @cls/@clear
  commands or the CTRL-L sequence, and is now fixed.
* Hitting CTRL-L to clear the screen now behaves correctly even in scripting/sourcing mode.
* Alias commads which dereference to a semicolon separated list of commands can now take a ':' marker at the end
  of those commands which will act as a hint on which commands to append any grep strings and/or variable/file
  capture options which may have been suplied on the initial alias command; for more details read the acli.alias file
* Highlighting of multiple patterns was corrupting output if those patterns appeared on same line of output
* Scripts acligui (v1.11), xmcacli (v1.05) and the ACLI embedded @launch command use a new acli.spawn file to
  determine how to spawn new ACLI terminal windows or tabs within. This now allows Linux support in addition to
  Windows and MACOS
* Scripts acligui (v1.11), acmd (v1.02) and aftp (v1.09), the -f hostfile now accepts IPs/Hostnames + TCP port number
  in format [<ip/hostname>]:<port>
* Scripts acligui (v1.11) and xmcacli (v1.05) now have a checkbox on GUI to force connections in Transparent mode
* Script xmcacli (v1.05) updated with new XMC families "Unified Switching VOSS" and "Unified Switching EXOS" which
  are used by XMC for new unified hardware models 5520,5420,etc.
* Script aftp (v1.09) now accepts absolute filepaths but only for put mode

5.01  2021-03-05
* Dictionary funcionality. Ability to load dictionary files so as to accept input commands in the syntax of a
  different product and to have those commands translated on the fly into the dialect of the connected switch.
  Shipping initially with an ERS (BOSS) dictionary which translates into both VOSS and XOS.
* Extra logic added to prevent alias loops, which were still possible in previous ACLI versions since 4.04
* Adding '-y' to an alias command not working if that alias command produced a semicolon fragmented list of commands
  where the first fragment is 'config term' but this is removed if the CLI context is already in config mode.
* On standalone units where port numbers have no slot (ERS, XOS) port numbers 1/x are now automatically converted
  to x if port x is a valid port on the switch.
* Some fixes to how port lists and port ranges are processed when constrained to available ports on connected
  device. Adding a port from a non-existent slot was sometimes processed generating an error on the terminal.
* Some fixes to how embedded commands are processed for syntax and tab expansion.
* Default connection timeout is increased from 25 to 35 seconds, so that SSH connections can succeed even with VOSS
  RADIUS authentications where the RADIUS server times out before local failsafe authentication is performed
* XMC ACLI GUI Launcher app (xmcacli v1.06) default HTTP timeout increased from 5 to 20 seconds and the same HTTP
  timeout can now be overridden in the xmcacli.ini file
* Added Dictionary port-range support. An input port-range can be defined to limit the ports which will get
  translated in dictionary commands. The input ports will automatically map to available ports on the connected
  switch, but can also be manually mapped to a subset of the available connected ports.
* Dictionary echoing mode is modified to support 3 levels: always, disable, single; the new mode, single, is made
  default and will only echo dictionary translation if the dictionary command resulted in a single output command
  translation; if instead the translation was a semicolon fragmented list of many commands, this is not echoed
  as it results in a lot of clutter on the screen and in any case one can see the resulting commands executing.
* @echo command has a new setting "@echo sent" which is automatically set when loading a dictionary file. In this
  mode embedded commands are not echoed to the screen anymore, but only commands to the switch are. This reduces
  the screen clutter when using dictionary commands which would otherwise echo all the @if, @else, @endif statements
* Pseudo terminal is enhanced to emulate device types: boss|slx|voss|xos, which allows pseudo terminal to emulate
  such a device with regards to how port list/ranges are handled as well as device attributes (under @vars
  attributes). A valid port-range can also be assigned to match the target emulated device. And pseudo terminal
  profiles can now be named, saved, and recalled either on startup or via new @pseudo list/load commands.
* Capturing command output to ('>') file now does not abort if error patterns are seen inside the output.
* ACLI GUI (acligui v1.12) and XMC ACLI (xmcacli v1.07) no longer set sockets when transparent (-n) flag set.
* Acli.spawn key <ACLI-PL-PATH> was not replaced with "acli.pl" but just "acli"
* Grep of a non existent port number was resulting in all output shown (e.g. from show run)
* Now if disabling error detection (@error disable) grep functions can be performed while doing more of files
  which contain errors, such as the ZTP agent file cc/cc_logs/ztp_plus_commands.txt
* New @stop embedded command is like @exit but in addition to coming out of currently running script will also
  halt sourcing mode as if an error had been detected. And a message can be displayed at same time.

5.02  2021-08-21
* Commands typed by user are now made bright once the ENTER key has been hit; this allows them to be more easily
  identified when scrolling back in the output buffer.
* Repeat command '@' entered alone with no number of secs following was not working since version 5.00; now fixed
* acmd v1.03: timeout on commands was never timing out due to flawed poll time crediting mechanism
* acmd v1.04: now possible to use a $$ variable in CLI script which replaces switch name from hostnames file
* acmd v1.05: now possible to feed in a spreadsheet for list of hosts as well table of variables which can be
  embedded in the CLI script
* Update to VOSS context patterns to support for new Multi-Area configuration contexts.
* Beta version of rosetta.pl script
* Acli.ini file key auto_log_filename_str can now include "<>" for the base filename so that the timestamp can be
  appended as well as pre-pended.
* On VOSS command tab expansion was not working properly if one quote only present on input command
* History recall was not working properly on tied terminals; got broken in 5.01; fixed now
* Sending characters in paced mode in a listening terminal from a tied terminal was not working anymore since 5.01
* Alias commands consisting of "config term; <single command>; end" where not echoed in config mode due to suppression
  of unnecessary "config term" and "end"; was broken since 5.01
* Was not possible to paste multilines while editing a text file (VOSS or XOS) in interactive mode
* Unwrapping of BaystackERS long lines was not always working, since ACLI version 4.04
* Fixed some problems interacting with syntax and tab expansion with Wing CLI
* Fixed some problems interacting with syntax and tab expansion with ExtremeXOS CLI
* Command -switches were not working if immediately followed by semicolon ';'
* Generation of keepalive carriage returns can now also be activated in transparent mode. To this effect a new command
  is added to the ACLI control interface: 'terminal timers transparent-keepalive enable|disable' and a new key
  transparent_keepalive_flg is added to the acli.ini file

5.02_001
* Variable de-referencing was not working in some scenarios, like: vlan i-sid $vlan 2200{$vlan}
* xmcacli.pl v1.08; updated to work with XIQ-SE 21.9 which no longer reports itself as Extreme Management Centre
* aftp.pl v1.10; now accepts a password on the command line with the -u username switch
* aftp.pl v1.11; now accepts -x switch to read in host IPs from spreadsheet file
* Changed the generic prompt regex in underlying Control::CLI and Control::CLI::Extreme modules to accomodate some
  Linux distributions where the prompt is coloured using ANSI escape sequences

5.03  2021-12-30
* Selection from known list of serial ports was not allowing selections in format glob or <entry>@<baudrate>
* VOSS onboarding I-SID now shows with associated VLAN in vlan grep of show running config
* Input switch -s to provide socket names to listen on, now can be supplied with just "0" and will globally shutdown
  the socket functionality instead. The same can also be done on the same -s switch of acligui.pl and xmcacli.pl
* Changed the login sequence to handle new VOSS8.5 behaviour of asking user to change the password on first login
* Enhanced SSH server key verification against know_hosts file. Earlier verisons would automatically add the server
  key to konwn_hosts if this was not already known, while a connection to a host where the server key was found to
  be different from the key cached in the known_hosts file, would be aborted and the user would have to manually go and
  delete the existing key in the known_hosts file and then reconnect. These behaviours are now configurable via two
  new acli.ini settings:
  * SSH known hosts missing key behaviour : ssh_known_hosts_key_missing_val
    - 0 : SSH connection is refused
    - 1 : User gets interactively prompted whether to add the key for the host in the known_hosts file, or to connect
          once without adding the key to known_hosts, or to abort the connection (this is the default behaviour)
    - 2 : The key is automatically added to known_hosts file and a message is displayed to this effect (this used to
          be the default behaviour in ACLI versions up to 5.02 before this ini key was implemented)
  * SSH known hosts failure check behaviour : ssh_known_hosts_key_changed_val
    - 0 : SSH connection is refused (this used to be the default behaviour in ACLI versions up to 5.02 before this
          ini key was implemented)
    - 1 : User gets interactively prompted whether to update the key for the host in the known_hosts file, or to
          connect once without updating the key in known_hosts, or to abort the connection (this is the default
          behaviour)
    - 2 : The key is automatically updated with the new key in the known_hosts file and a message is displayed to
          this effect (Note, this is not a safe option)
  Note that the default behaviours mentioned earlier have changed. To keep the same default behaviuor of ACLI
  versions 5.02 and earlier, the above ini keys would need to be set to ssh_known_hosts_key_missing_val = 2 and
  ssh_known_hosts_key_changed_val = 0
* The above new ini keys ssh_known_hosts_key_missing_val and ssh_known_hosts_key_changed_val, if left at default
  or if set to value 1 will now prompt the user to decide what to do during the connection phase. In this case
  the SSH host's server key details and MD5 fingerprint are shown so that the user can make an informed decision
* SSH key MD5 fingerprint is now also displayed for the current SSH session (@ssh info), the local ssh user public
  key (@ssh keys info), all cached SSH known_hosts (@ssh known-hosts), and for user public keys placed on a VOSS
  device (@ssh device-keys list)
* Updated sed colouring patterns for MAC address detection (not to trigger on SSH MD5 fingerprint)
* The auto-log acli.ini auto_log_filename_str key can now include sub-directory separators ('/' or '\') and allows
  log files to be automatically created under sub-directories off the root logging directory (set via log_path_str)
* Semi-colon line with config term as first command and just one other command was giving uninitialized value error
  when execute in config mode
* VOSS running config grep was not suppressing isis logical-intf context if these had no name assigned
* Grep streaming (-g) of offline config files now also works with UTF-16 encoded text files
* Repeating a semi-colon fragmented line of commands with '&' was not working; was broken since version 5.00
* Repeating a semi-colon fragmented line of commands with '&' ot '@' was not preserving grep, -options, etc of first
  fragment
* Fixed issue where using command repeat (@) on a command with a grep string would result in the command being
  repeated without the grep string

5.04  2022-01-23
* Device detection during login phase could crash ACLI if the switch discovery mis-detects the switch as a stack and
  no slots are there. The mis-detection can happen if TACACS is in use and the necessary discovery CLI show commands
  are not in the authorized TACACS commands list
* ACLI GUI (acligui v1.15) and XMC ACLI (xmcacli v1.11) now pass on switch -s 0 (disable sockets) even if the -n
  switch is set
* VOSS show run greps were always returning "logical-intf isis" lines if thess existed in the switch config and were
  configured on an MLT, instead of a port
* Capturing an insight port (e.g. 1/s1) to variable was giving "Argument "1/s1" isn't numeric" errors
* ACLI Session Manager version 1.0.0.018, by Marlon Scheid (mscheid@net-select.de), is now included in the ACLI
  Windows installer 
* ACLI now immediately checks if the user's ACLI settings directory exists, and if not tries to create it. Which
  means that if an %ACLI% ($ACLI on Unix sytems) path was not set, then the following directory will be created:
  - %USERPROFILE%\.acli (on Windows) 
  - $HOME/.acli (on Unix systems)
* When connecting with the -n switch and providing CLI login credentials ACLI will attempt to login, in spite of
  being in transparent mode. This enhancement was added in version 4.00. In case of telnet, this can come useful
  to automatically log into a device via a terminal server (via acligui.pl batch file). However, to wake up the 
  connected host so that it sends its login sequence requires sending some character sequence. This sequence was 
  using the same character used by ACLI for newline, which is configurable between Carriage Return (CR) or
  Carriage Return + Line Feed (CR+LF), and defaults to the former. But a CR is not seen by some devices as a newline
  hence the fix is to now always use CR+LF for the wake character sequence
* ACLI GUI (acligui v1.15) now immdiately launches the connection (without calling the GUI window) if the -n
  transparent switch is set and the -u login credentials are not provided

5.05  2022-03-05
* Changes to correctly detect FabricEngine Universal Hardware VOSS 8.6.0.0
* Changes to correctly detect SwitchEngine Universal Hardware EXOS 31.7
* Added "vr" to restricted commands which cannot be aliased in command syntax "?"
* Was getting "Nested use of '&' repeat is not supported" on some dictionary commands using the '&' repeat function
  when executed a second time
* Updates to ExtremeXOS show command banner patterns
* When doing SSH from one VSP to another VSP with a different SSH password the first login fails as it tries to use
  the same SSH password of the first VSP; but when user manually enters the correct password, the connection now
  establishes correctly in interactive mode (this was working ok with telnet but not with SSH). Worse, if a logout
  was done on the second VSP, returning to the first VSP would result in the first VSP's SSH password being printed
  in cleartext on the terminal. This is now also fixed.
* Pasting config lines where the last line does not have a trailing carriage return, could cause the last 2 lines
  to get garbled up on devices with a slow CLI, like the ISW or a switch VM

5.05_001
* Script xmcacli (v1.12) updated with new XMC families 'Universal Platform Fabric Engine' & 'Universal Platform
  Switch Engine' families used in XIQ-SE 22.3 for universal hardware running VOSS8.6 or EXOS31.6 or later
* Updated rosetta voss and boss c2j encoder files

5.06  2022-05-13
* When launching many instances of ACLI to connect with SSH to as many switches, and none of the switches public ssh
  keys are in the known_hosts file, when each instance updates the known_hosts file, it undoes the key addition just
  performed by the previous ACLI instance. Changed code to place a lock during the known_hosts file update and a
  re-read of the known_hosts file is performed before updating it (in case an other instances added new keys while
  this instance was waiting).
* Updated rosetta voss and boss c2j encoder files
* Variables containing "/" character(s) and other Perl metacharacters, when de-referenced inside a pattern matching
  perl expression like:
  @if { "string" =~ /$var/ }
  ...now have those characters automatically backslashed. In this case the variable is not processed for port ranges
  but is dereferenced with its raw value
* ACLI GUI (acligui v1.16) and XMC ACLI (xmcacli v1.13) can now correctly launch ACLI even if the password contains
  special characters like *,&,etc.. as the credentials are now double quoted on the ACLI calls
* The Visual Basic helper scripts acligui.vbs and xmcacli.vbs also required same changes to make the above work with
  Windows batch files.
* Updates to ExtremeXOS grep patterns; output of BGP routing table, route entries are no longer seen as indented
  records if the routes don't have any flags set at the beginning of the line.
* Fixed issue which could result in ACLI suddenly dying with: Can't use an undefined value as a SCALAR reference at
  C:/Strawberry/perl/site/lib/Control/CLI/Extreme.pm line 2145
* Script xmcacli (v1.14) updated with new XMC families 'Universal Platform Fabric Engine' & 'Universal Platform
  Switch Engine' families used in XIQ-SE 22.3 for universal hardware running VOSS8.6 or EXOS31.6 or later
* Issuing a command which prompts for input (like password) while socket tied to other ACLI instances, was not
  displaying the prompt.

5.07  2022-09-17
* Changes to handle new EXOS 5720 channelized port format <slot>:<port>:<channel> or <port>:<channel> on standalone
* Changes to handle new VOSS8.8 logical-intf syntax in show running-config grep
* ACLI's own summary of counted records in show commands is now only shown once, in commands which have multiple
  counts of their own (like ISIS interfaces, Home & Remote..)
* Enhanced ACLI grep to work better on EXOS "show netlogin session"
* Fix to command parsing in presence of "@" character used in the middle of the command, like on ExtremeXOS
  "scp2 <username>@<IP>:<path>" request for command syntax "?" was not working properly
* Pasting config lines where the last line does not have a trailing carriage return and one of the previous commands
  is slow to produce a prompt (e.g. save config), was causing the last line to get inserted before the next command
  in the wrong order. Version 5.05 had made a fix by just increasing a timer, but that only bought some time.
  That timer is now restored and now a separate character buffer is held for the last, incomplete, line when pasting
  multi-lines into the terminal. This ensures that on resumption of sourcing the paste buffer, the order does not get
  mixed up anymore
* Username and password can now be fed on command line when opening connection to trmsrv: or serial:
* Tweaked sockets used to send commands on tied terminals. Now sending a command from tied terminal will wipe any
  sourcing buffer on listening terminals. Also the listening terminal now only queues echo output after the command
  sent from tied terminal actually gets executed; previously the listening terminal might have sent to tied terminal
  the output of a previous command from the one sent to it by the tied terminal
* In "@socket echo all" mode, tied terminal was delaying the prompt processing even if nothing was sent over the
  socket; no longer now
* Script xmcacli (v1.15) site filter pull down was matching other sites if other sites had longer names containing
  the selected site
* Script xmcacli (v1.15) site filter pull down was causing application to crash with:
  "Tk_FreeCursor received unknown cursor argument"
* Scripts acligui (v1.17), xmcacli (v1.15) setting the Logging or Working directory from GUI, the directory chooser
  now starts from the directory which was specified with command line switches or from the very top "This PC"
* Scripts acligui (v1.17), xmcacli (v1.15) last Logging or Working directory selected from directory chooser is
  remembered and offered as default in subsequent executions of the script
* VOSS show run grep of a VLAN was not picking up the IPv6 DHCP relay configuration of that VLAN

5.08  2023-03-25
* VOSS grep running-config patterns were not working if logical-intf name included spaces
* ConsoleZ default settings now have checkbox "Start Windows console hidden" enabled. It seems this is required on
  Windows11 to prevent duplicate windows being opened for every ACLI tab
* VOSS grep running-config patterns were not working if route-map names contained characters "<" or ">"
* @sed patterns can now be associated with the product family group, via the category identifier in the acli.sed file
  This allows sed patterns to be more efficient (no need to check patterns specific to one product family when
  connected to a different product family device); see the acli.sed file for more details.
* @sed input and output (but not colouring output) patterns can now use a Perl code snippet as replacement string
  In this case the replacement code string must be enclosed in curlies {} in the acli.sed file and enclosed in '{}'
  if using the @sed embedded command to add the input or output pattern
* Loaded acli.sed file is now displayed in "@sed info" command output
* New default sed output pattern, allows a more readable output of VOSS ACL filter config
* Changes to correctly detect new ISW models: ISW-4W-4WS-4X & ISW-24W-4X
* Created reserved variables $ALL (also $1/ALL or $2/ALL or $3:ALL, etc..) which will automatically translate to
  all ports or all ports for given slot on connected device (except for the ISW)
* VOSS show running config advanced grep on VRF names "show running ||vrf [<vrfname-list>]" now does exact matches
  on the supplied VRF names (previously "vrf red" would also match "vrf shared")
* EXOS command "download url file:///usr/local/ext/test.xos" was not processed correctly; the double "/" were
  incorrectly used as if to feed an argument "//usr/local/ext/test.xos" to the command ""download url file:/"
* When tie-ing or listening to socket names, a purely numerical name is now treated as a string. Previously doing
  "@socket tie 22" would result in the socket being actually tied to UDP port 22; same thing for "@socket listen".
  Now "22" is considered a string and it will get allocated a UDP port above 50000, as was already done for socket
  names containing characters other than digits. To actually force a specific socket number it is now necessary to
  use a socket number preceded by "%", like "@socket tie %20000" will actually use UDP port 20000.
* Variable capture on output echoed from tied terminals no longer tries to capture on error message lines indicating
  that the tied device is not connected

6.00  2023-06-24
* Added support for HiveOS Cloud APs
* Added support for SD-WAN IP Engine (IPE) appliance
* Windows distribution upgraded to Strawberry 64bit Perl v5.32.1 (MSWin32-x64-multi-thread)
* Windows distribution upgraded to libssh2 v1.11.0 which now supports latest SSH cyphers e.g. rsa-sha2-512 and
  rsa-sha2-256 required for SSH into SD-WAN IP Engine (IPE) appliance
* Version now displays 64bit and threads support in addition to Perl version
* Added support for new Control-CLI-Extreme attributes "is_fabric_engine" and "is_switch_engine"
* The syntax for supplying command prompted inputs on the command's command line now can take two optional switches:
  <CLI command> [-hf] // <input1> // <input2> ...
  The -h switch will cache those inputs for future invocation of that same command on same host
  The -f switch will cache those inputs for future invocation of that same command on any device of same family type
  The cached inputs are held in a JSON file acli.cache under the .acli directory
* Manually setting the default variable ($=<value>) was giving error: "use of uninitialized value $1 in string"
* Reserved variable $$ now is set from Control-CLI-Extreme's attribute "sysname" and is only extracted from the CLI
  prompt on PassportERS Standby CPUs, where the former attribute is not available
* New reserved variable $> holds last received CLI prompt from device; useful to create logic to move between
  different CLI exec levels using ACLI scripts
* Connecting to serial COM port via command line was not working and always invoking the COM port select menu
* Embedded command "@run list" was not working on Linux/MacOS systems

6.01  2023-08-03
* Sed colouring and output patterns now also work with offline grep (-g)
* Sed output pattern allowing more readable output of VOSS ACL filter config was not working properly with IPv6 ACLs
* Ini flag ctrl_clear_screen is now renamed to ctrl_clear_screen_chr
* New ACLI control command "terminal ini" and embedded "@terminal ini" shows settings of all ini keys which can be
  set via the acli.ini file
* Added support for new SD-WAN Ipanema "router 1-3" CLI contexts
* Improved CLI tab expanson support for SD-WAN Ipanema family type
* Windows installer now automatically launches uninstaller of previous version if already installed
* Windows uninstaller now deletes any residual updates directory, so these do not interfere with a new installation
* Control ACLI> interface was not able to set debug level > 999
* More paging output with error patters was producing unexpected lines between --more-- prompts
* Script xmcacli (v1.17) updated with missing XMC family "200 Series" for Series200 support
