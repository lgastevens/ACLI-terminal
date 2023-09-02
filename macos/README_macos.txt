$Version = 1.00

Install instructions
====================

1 - Install all the required software, modules and dependencies (non trivial..)
    Refer to: Installing_ACLI_required_libraries_xxxx.txt

2 - Unzip this file into a "ACLI" install directory of your choosing

3 - add ACLI install dir to $PATH

4 - set $ACLIDIR env variable to same ACLI install dir

5 - Optionally create desktop shortcuts (aliases) for the files: xmcacli & acligui


Points 3&4 above can be done by adding the lines to .bash_profile :

	PATH=<ACLI-directory>:$PATH:.
	export PATH
	export ACLIDIR=<ACLI-directory>



MAC-OS Distribution
===================
ACLI on MACOS can be used either in the default Terminal application or you can also use it with iTerm2 app (available on app store)


Everything should work as on the ACLI Windows distribution, except these:
- Updates: update script not currently supported with MAC OS. If a new ACLI version exists, simply expand new zip file ontop of existing ACLI directory.



Connecting to a switch with ACLI
================================

Launch ACLI from Terminal or iTerm2:

iMac:~ $ acli -h
iMac:~ $ acli

ACLI> help

ACLI> open ?

ACLI> open <ip address>

...

The following syntaxes will produce a TELNET connection:

	iMac:~ $ acli <ip address>
	ACLI> open <ip address>
	ACLI> telnet <ip address>

The following syntaxes will produce an SSH connection:

	iMac:~ $ acli -l <username> <ip address>
	ACLI> open -l <username> <ip address>
	ACLI> ssh connect <ip address>

The following syntax will produce a Serial Port connection:

	iMac:~ $ acli serial:<COM-port>
	ACLI> open serial:<COM-port>

Open a new tab (with Terminal or iTerm2):
	iMac:~ $ ttab


Customizing
===========

The ACLI for MAC OS distribution includes a ttab script which allows ACLI applications (like @launch embedded command and ACLIGUI and XMCACLI applications) to automatically open new tabs within the Terminal or iTerm2 applications.
For this to work though, you will need to do the following:
System Preferences > Security & Privacy, tab Privacy, select Accessibility, unlock, and make sure Terminal.app / iTerm.app is in the list on the right and has a checkmark.


If when running the ACLIGUI and XMCACLI applications you see this error message:

	Fontconfig warning: ignoring UTF-8: not a valid region tag

To suppress this, open Terminal / Preferences... / Profiles / Basic(Default) / Advanced / International   then uncheck "Set locale environment variables on startup".
Restart the Terminal app.




acli.pl command line options:
----------------------------
iMac:~ $ acli -h
acli.pl version 4.00

Usage:
 acli.pl [-cehijkmnopqswxyz]
 acli.pl [-ceijklmnopqrstwxyz] <host/IP> [<tcp-port>] [<capture-file>]
 acli.pl [-ceijmnopqrswx]      serial:[<com-port>[@<baudrate>]] [<capture-file>]
 acli.pl [-ceijmnopqrswxyz]    trmsrv:[<device-name> | <host/IP>#<port>] [<capture-file>]
 acli.pl [-eimoqsw]            pseudo[1-99]:[<prompt>] [<capture-file>]
 acli.pl -r <host/IP or serial or trmsrv syntaxes above> <"relay cmd" | IP> [<capture-file>]
 acli.pl [-f] -g <acli grep pattern> [<cfg-file or wildcard>] [<2nd file>] [...]

 <host/IP>        : Hostname or IP address to connect to; for telnet can use <user>:<pwd>@<host/IP>
 <tcp-port>       : TCP port number to use
 <com-port>       : Serial Port name (COM1, /dev/ttyS0, etc..) to use
 <"relay-cmd"/IP> : To execute on relay in form: "telnet|ssh [-l <user[:<pwd>]>] <[user[:<pwd>]@]IP>"
                    If single IP/Hostname provided then "telnet IP/Hostname" will be executed
 <capture-file>   : Optional output capture file of CLI session
 -c <CR|CRLF>     : For newline use CR+LF (default) or just CR
 -e escape_char   : CTRL+<char> for escape sequence; default is "^]"
 -f <type>        : Used with -g to force the Control::CLI::Extreme family_type
 -g               : Perform ACLI grep on offline config file or from STDIN (pipe)
 -h               : Help and usage (this output)
 -i <log-dir>     : Path to use when logging to file
 -j               : Automatically start logging to file (<host/IP> used as filename)
 -k <key_file>    : SSH private key to load; public key implied <key_file>.pub
 -l user[:<pwd>]  : SSH username[& password] to use; this option produces an SSH connection
 -m <script>      : Once connected execute script (if no path included will use @run search paths)
 -n               : Do not try and auto-detect & interact with device
 -o               : Overwrite <capture-file> instead of appending to it
 -p               : Use factory default credentials to login automatically
 -q quit_char     : CTRL+<char> for quit sequence; default is "^Q"
 -r               : Connect via Relay; append telnet/ssh command to use on Relay to reach host
 -s <sockets>     : List of socket names for terminal to listen on
 -t               : When tcp-port specified, flag to say we are connecting to a terminal server
 -w <work-dir>    : Run on provided working directory
 -x               : If connection lost, exit instead of offering to reconnect
 -y <term-type>   : Negotiate terminal type (e.g. vt100)
 -z <w>x<h>       : Negotiate window size (width x height)

So, for example, for a simple Telnet connection:

iMac:~ $ acli 192.168.10.10

And if you wanted to provide the credentials on the command line:

iMac:~ $ acli username:password@192.168.10.10

For an SSH connection the -l option must be used:

iMac:~ $ acli -l username 192.168.10.10

SSH can do either publickey authentication or password (also keyboard-interactive) authentication.

The ACLI Terminal will automatically look for known_hosts file and load SSH Private & Public keys if these are found in one of these directories:
 - ENV path %ACLI%/.ssh (if you defined it)
 - ENV path $HOME/.ssh (on Unix systems)
 - ENV path %USERPROFILE%\.ssh (on Windows)
 - ENV path %ACLIDIR%/.ssh 

If a known_hosts file is not found, one will be created in the 1st existing path of the above.
If no entry exists in the known_hosts file for the host we are SSH connecting to, an entry will automatically be created without any need for user confirmation.
If an entry exists but the key does not match, then the connection will fail as this indicates that the host key has changed (potentially a man in the middle attack).

For SSH keys, the expected filename is 'id_rsa' or 'id_dsa' respectively for RSA and DSA private keys.
The corresponding public key (which is also required) is expected with filenames 'id_rsa.pub' and 'id_dsa.pub'.
If SSH keys are loaded, then publickey authentication is always attempted.
If no SSH keys are loaded, or if the publickey authentication attempt failed, then password (or keyboard-interactive) authentication is performed.

If you wanted to provide the SSH password to use from the command line:

iMac:~ $ acli -l username:password 192.168.10.10

While if you wanted to load some other SSH keys for publickey authentication use the -k switch:

iMac:~ $ acli -l username -k id_dsa 192.168.10.10


To connect via Serial port COM1:

iMac:~ $ acli -n serial:COM1

(Serial port communication is slow; the -n switch will prevent the ACLI terminal from discovering the device to enter interactive mode, which can take a few seconds; you can enter interactive mode once connected by using CTRL-T)

If not sure what serial port to use:

iMac:~ $ acli -n serial:

This will show the available serial ports, and you can select the desired one.

Connecting via a terminal server, simply provide the TCP port and set the -t flag:

iMac:~ $ acli -nt 192.168.10.10 5010

(Serial port communication is slow; the -n switch will prevent the ACLI terminal from discovering the device to enter interactive mode, which can take a few seconds; you can enter interactive mode once connected by using CTRL-T)

The ACLI terminal is able to keep track of previous connections via terminal servers and the information is cached for ease of retrieval:

iMac:~ $ acli -nt trmsrv:

This will provide a list of cached terminal server connections; any entry can be selected by number or switch name

Or, if you know the switch name in advance:

iMac:~ $ acli -nt trmsrv:VSP9000-1

instead of having to remember the terminal server IP and TCP port number...


It is also possible to connect to a target device via a relay device (telnet/SSH hopping)

iMac:~ $ acli -r 10.134.10.10 192.168.10.10

The above will telnet to 10.134.10.10 (e.g. a VSP switch via OOB) and from there telnet to 192.168.10.10 (e.g. a Stackable ERS with no OOB)

If you wanted to supply credentials on the command line:

iMac:~ $ acli -r rwa:rwa@10.134.10.10 username:password@192.168.10.10

The above examples could also have been written as:

iMac:~ $ acli -r 10.134.10.10 "telnet 192.168.10.10"
iMac:~ $ acli -r rwa:rwa@10.134.10.10 "telnet username:password@192.168.10.10"

NOTE: Embedded credentials within the quotes will be removed, before executing the command on the Relay host

To perform SSH on the 2nd hop (e.g. to reach a WLAN9100 AP):

iMac:~ $ acli -r rwa:rwa@10.134.10.10 "ssh 192.168.10.10 -l admin"

NOTE: The syntax within the quotes has to correspond to whatever command syntax applies on the Relay host (ssh <ip> -l <username> is the synax used by SSH client on VOSS VSPs)

And to embed credentials:

iMac:~ $ acli -r rwa:rwa@10.134.10.10 "ssh 192.168.10.10 -l admin:admin"

NOTE: Embedded SSH password within the quotes will be removed, before executing the command on the Relay host

And if one wanted to use SSH to also connect to the Relay host:

iMac:~ $ acli -r -l rwa:rwa 10.134.10.10 "ssh 192.168.10.10 -l admin:admin"




Running acli directly from terminal
===================================
You can also invoke acli (or any of the other tools supplied: acligui, grep, aftp) from any directory in any DOS box or cmd.exe session.
This is useful is you want to leverage the ACLI terminal's ability to perform advanced greps on offline configuration files:

C:\offline-configs>acli -g "router isis" config_VSP-1.cfg
config terminal
router isis
   spbm 1
   spbm 1 nick-name 0.40.01
   spbm 1 b-vid 4051-4052 primary 4051
   spbm 1 smlt-virtual-bmac b4:a9:5a:40:01:01
   spbm 1 smlt-peer-system-id b4a9.5a40.0300
exit
router isis
   sys-name VSP-1
   is-type l1
   system-id b4a9.5a40.0100
   manual-area 49.0001
exit
router isis enable
end


Or with pipe:


C:\offline-configs>type config_VSP-1.cfg | acli -g "router isis"
config terminal
router isis
   spbm 1
   spbm 1 nick-name 0.40.01
   spbm 1 b-vid 4051-4052 primary 4051
   spbm 1 smlt-virtual-bmac b4:a9:5a:40:01:01
   spbm 1 smlt-peer-system-id b4a9.5a40.0300
exit
router isis
   sys-name VSP-1
   is-type l1
   system-id b4a9.5a40.0100
   manual-area 49.0001
exit
router isis enable
end


Or for multiple files:


C:\offline-configs>dir *.cfg

 Directory of C:\offline-configs

05/06/2015  16:58             8,135 config_VSP-1.cfg
05/06/2015  16:59             7,163 config_VSP-2.cfg
05/06/2015  16:59             8,056 config_VSP-3.cfg
05/06/2015  16:59             7,286 config_VSP-4.cfg
               4 File(s)         30,640 bytes
               0 Dir(s)  397,588,967,424 bytes free

C:\offline-configs>acli -g "router isis||nick-name" config_VSP*.cfg

config_VSP-1.cfg :

config terminal
router isis
   spbm 1 nick-name 0.40.01
exit
end


config_VSP-2.cfg :

config terminal
router isis
   spbm 1 nick-name 0.40.02
exit
end


config_VSP-3.cfg :

config terminal
router isis
   spbm 1 nick-name 0.40.03
exit
end


config_VSP-4.cfg :

config terminal
router isis
   spbm 1 nick-name 0.40.04
exit
end





Other tools included in the ACLI distribution
=============================================
Also supplied in the distribution zip file are these other tools..


iMac:~ $ aftp
aftp.pl version 1.00

 Simultaneously transfers files to/from 1 or more devices using either FTP or SFTP
 When GETting the same file from many devices, prepends device hostname/IP to filename
 When PUTting the same file back to many devices, only specify the file without prepend

Usage:
 aftp.pl [-l <user>] [-p <path>] <host/IP/list> [<ftp|sftp>] <get|put> <file-list/glob>

 aftp.pl -f <hostfile> [-l <user>] [-p <path>] [<ftp|sftp>] <get|put> <file-list/glob>

 -f <hostfile>    : File containing a list of hostnames/IPs to connect to
 -l <user>        : Use non-default credentials; password will be prompted
 -p <path>        : Path on device
 <host/IP/list>   : Hostname or IP address or list of IP addresses to connect to
 <ftp|sftp>       : Protocol to use; if omitted will default to FTP
 <get|put>        : Whether we get files from device, or we put files to it
 <file-list/glob> : Filename or glob matching multiple files or space separated list


The latter can FTP/SFTP put or get 1 or more files to/from 1 or many switches simultaneously.
The switches need to have FTP or SFTP Server functionality activated.
For example, to recover the config.cfg file from several switches you can do:

iMac:~ $ aftp 10.134.169.91-92,81-84,171-172 get config.cfg
Connecting to hosts:
  1 - 10.134.169.91
  2 - 10.134.169.92
  3 - 10.134.169.81
  4 - 10.134.169.82
  5 - 10.134.169.83
  6 - 10.134.169.84
  7 - 10.134.169.171
  8 - 10.134.169.172

Copying files ...............<5>.<6>.......<8>....<3>.......<1>.<7>.<4>..........<2>


iMac:~ $ dir *.cfg
 Volume in drive C is Avaya eSOE
 Volume Serial Number is C87E-793B

 Directory of C:\Users\ludovicostev\Downloads

28/04/2016  22:29            14,796 10.134.169.171_config.cfg
28/04/2016  22:29            14,223 10.134.169.172_config.cfg
28/04/2016  22:29            19,348 10.134.169.81_config.cfg
28/04/2016  22:29            18,347 10.134.169.82_config.cfg
28/04/2016  22:29            18,463 10.134.169.83_config.cfg
28/04/2016  22:29            16,649 10.134.169.84_config.cfg
28/04/2016  22:29            29,930 10.134.169.91_config.cfg
28/04/2016  22:29            37,833 10.134.169.92_config.cfg
10/02/2016  17:06               477 default.cfg
               9 File(s)        170,066 bytes
               0 Dir(s)  367,696,596,992 bytes free


Note that if the same file is fetched from more than one switch, then the switch IP address is pre-pended to the file recovered, as shown above.
Now you can edit all the above files using your preferred text editor.
Once done, you can push the updated files back to their originating switch in one shot like this:

iMac:~ $ aftp 10.134.169.91-92,81-84,171-172 put config.cfg
Connecting to hosts:
  1 - 10.134.169.91
  2 - 10.134.169.92
  3 - 10.134.169.81
  4 - 10.134.169.82
  5 - 10.134.169.83
  6 - 10.134.169.84
  7 - 10.134.169.171
  8 - 10.134.169.172

Copying files ..................<4>..<6><8>......<5>.<3><7><2><1>


iMac:~ $ 

----------------

iMac:~ $ cfm-test
cfm-test.pl version 1.2

Usage:
 cfm-test.pl <ssh|telnet> <[username[:password]@]seed-IP> <ping|tracert>


Provide this tool with the IP inband address and login credentials of a switch in an SPB Fabric. The script will then:
 - discover every other node in the Fabric
 - connect to all nodes in the Fabric
 - perform on ALL nodes simultaneously the requested CFM test (currently L2 traceroute or L2 ping)
 - verify the result of such tests
 - only reports tests which failed

----------------

iMac:~ $ acmd
acmd.pl version 0.02

 Execution of CLI commands/script in bulk to many Extreme Networks devices using SSH or Telnet

Usage:
 acmd.pl [-agoty] [-l <user>] <host/IP/list> <telnet|ssh> "semicolon-separated-cmds" [<output-file>]
 acmd.pl [-agoty] [-l <user>] -s <script-file> <host/IP/list> <telnet|ssh> [<output-file>]
 acmd.pl [-agoty] [-l <user>] -f <hostfile> <telnet|ssh> "semicolon-separated-cmds" [<output-file>]
 acmd.pl [-agoty] [-l <user>] -f <hostfile> -s <script-file> <telnet|ssh> [<output-file>]

 -a               : In staggered mode (-g) abort further iterations if at least one host fails
 -f <hostfile>    : File containing a list of hostnames/IPs to connect to (format = IP hosts file)
 -g <number-N>    : Stagger job over more iterations each for a maximum of N hosts;
                    if not specified, job is performed against all hosts in a single cycle
 -l <user>        : Specify user credentials to use (password will be prompted)(default = rwa/rwa)
 -o               : Overwrite <output-file>; default is to append
 -s <script-file> : File containing list of commands to be executed against all hosts
 -t <timeout>     : Timeout value in seconds to use (default = 20secs)
 -y               : Skip job detailed summary and user confirmation prompt
 <host/IP/list>   : Hostname or IP address or list of IP addresses to connect to
 <telnet|ssh>     : Protocol to use
 <output-file>    : Output will be saved to this file


If you don’t use the –g flag, the script will attack all nodes in one go; with SSH this will be slow initially as the SSH authentications are blocking calls.
If you use the –g flag, you can stagger it to do N switches at a time; with SSH it is best to stagger around 10 switches at a time.
The critical thing when working with many switches is keeping track of when things go wrong (if you can’t connect to 1 switch, or some switch does not like one of your commands).
The approach taken is that if a command or the connection fails to all switches in the 1st iteration, then the script bombs out => changes were not made on any switch (unless 1 command gave an error across all switches, in which case all preceding commands in your script will have executed).
If instead only a few switches fail during an iteration (and you are using the staggered mode with –g) you can control whether you would like to carry on with subsequent iterations (default) or not (set the –a flag for abort).
In any case, if the script succeeds on some switches, but fails on others or is not executed on others because the last iterations were skipped (-g + -a)  the list of all switches for which the script was not executed will be stored in a file <hostfile>.retry ; that way you can easily re-trigger the same script for just those switches which are remaining (after you’ve fixed the problem, whatever that was..).
The <hostfile>.retry file will also include information about the error which each host failed on.
And anyway you get a detailed summary of what the script is setting off to do, and you need to confirm before it gets going (unless you force an immediate start with –y)

The <hostfile> can take the same syntax as an IP hosts file; for example:

10.134.161.41
10.134.161.42
10.134.161.43
10.134.161.44
10.134.161.81   vsp8000-1
10.134.161.82   vsp8000-2

So you can list just the IP addresses or hostnames; in the former case, you can provide a switch name in the same file, as in example above for .81 & .82, then these switches will be referred to by name in output dialogue.

A sample <script-file> file, which sets the SNMP location/contact and changes the CLI passwords for ro user:

config term
snmp-server location "test test"
snmp-server contact "Ludovico"
username ro level ro // ro // newro // newro
show cli password
end


This is the output of it running:

iMac:~ $ acmd.pl -o -f myhosts -s myscript ssh output.log
================================================================================
Identified 33 hosts to run job against
Job consists of pushing CLI script contained in file: myscript
Performing job over single iteration
-> job will be performed by connecting to all 33 hosts at the same time
SSH will be used with default credentials: rwa/rwa
Any output received from hosts will be collected in file: output.log
-> output file 'output.log' already exists and will be overwritten!
If the script succeeds on some hosts but fails on others
-> list of hosts which failed will be listed in file: myhosts.retry
-> file 'myhosts.retry' already exists and will be overwritten!
================================================================================
OK to proceed [Y = yes; any other key = no] ? y
Connecting to 33 hosts ....................................................<7>.<10><12>....<13><14>.<18>.<20>.<25>...<26>............<27><28>..<29><32>.......<33> done!
Entering PrivExec on 33 hosts <6>....<19>..<26>.<33> done!
Executing CLI script on 33 hosts
- config term   ...<6>.<13>.<15>.<21>.<33> done!
- snmp-server location "test test"   ...<7>.<11>..<19>.<21>..<23>.<30>.<32>..............<33> done!
- snmp-server contact "Ludovico"   ....<8>.<13>.<19>.<22>.<27>.<28>.<33> done!
- end   ...<7>.<13>.<14>.<21>.<33> done!
Disconnecting from 33 hosts
Output saved to file output.log

----------------

iMac:~ $ acligui -h
acligui.pl version 1.04

Usage:
 acligui.pl [-impsuw] [<hostname/IP list>]
 acligui.pl [-impsuw] -f <hostfile>

 <host/IP list>   : List of hostnames or IP addresses
                  : Note that valid IP lists can be written as: 192.168.10.1-10,40-45,51
                  : IPv6 addresses are also supported: 2000:10::1-10 (decimal range 1-10)
                  : 2000:20::01-10 (hex range 1,2,3,4,5,6,7,8,9,a,b,c,d,e,f,10)
 -f <hostfile>    : File containing a list of hostnames/IPs to connect to
 -g               : Show GUI even if host/IP and credentials provided
 -h               : Help and usage (this output)
 -i <log-dir>     : Path to use when logging to file
 -m <script>      : Once connected execute script (if no path included will use @run search paths)
 -p ssh|telnet    : Protocol to use; can be either SSH or Telnet (case insensitive)
 -s <sockets>     : List of socket names for terminals to listen on
 -u user[:<pwd>]  : Specify username[& password] to use
 -w <work-dir>    : Working directory to use (including for <hostfile>)

This tool is a helper to allow you to launch ACLI tabs against a shorthand list of IP addresses (or from a -f hosts file) without having to manually open a new tab in the ACLI window and "open" against each IP address.
At the same time the tabs will be named using the IP address (or the switch name, if this was provided in the -f hosts file).
This script has a a GUI window which will launch if only partial information is provided on the command line (or always ig the -g switch is set).
If for example you just execute acligui without any arguments this will launch the ACLI GUI Launcher window (for which you should also have a shortcut under Start / ACLI).
The window also allows you to set all the same arguments (IP address list, username, password, SSH or Telnet, working and logging directories, socket names and run script) that you can specify via the command line.
And if you did specifiy some options via the command line, these will automatically appear as pre-populated once the window is opened.
Here are some examples..

You want to connect to a bunch of switches, for which the IP addresses are 192.168.10.10-15,22,24

iMac:~ $ acligui 192.168.10.10-15,22,24

This will open up the ACLI GUI Launcher window, from where you can populate the username & password fields and then click on "Launch" which will then open 8 ACLI Tabs and connect to each of the switches. Note the shorthand way that IP addresses can be listed.

Or you could already specify the username to use:

iMac:~ $ acligui -u rwa 192.168.10.10-15,22,24

In this case the ACLI GUI Launcher window will still open, but now you only need to provide the password and then click "Launch"

If instead both username and password are provided on the command line:

iMac:~ $ acligui -u rwa:rwa 192.168.10.10-15,22,24

In this case the ACLI GUI Launcher window will not open and you will directly get the desired Console Window with 8 ACLI Tabs each connected to the selected IPs.
However, in this latter case you had to type the password in clearcase on the command line, which may be undesireable.

If you wanted the above to still open the GUI window (so that logging & working directory can be set) then add the -g switch:

iMac:~ $ acligui -g -u rwa:rwa 192.168.10.10-15,22,24

An alternative way to launch acligui, is via Start / Run, using the same command line syntax as above, but specifying acligui.vbs instead of just acligui:

acligui.vbs -u rwa 192.168.10.10-15,22,24

And finally, if you wanted to share an ACLI shortcut to connect to a bunch of switches, you can do the following:

1 - Create a batch file (.bat extension) containing:

	@echo off
	acligui.vbs -p ssh -u <username>[:<password>] -w "%CD%" -f %0
	exit
	
	# List hosts below
	<IP-1>		<Hostname-1>
	<IP-2>		<Hostname-2>
	<IP-3>		<Hostname-3>
	...

2 - Place the file in the directory you wish to be used as working directory once connected to switches

3 - Run the batch file directly, or make a shortcut to it and run that

----------------

iMac:~ $ spb-ect
Specify number of paths to compare[default = 2] :
Specify number of BVLANs in use[default = 2] :
Comma separated list of nodes on path 1 :aa,bb,cc,dd
Comma separated list of nodes on path 2 :aa,01,02,dd

Lexicographic ordering done AFTER applying ECT Masks
====================================================

 Processing for BVLAN1, after applying ECT Mask 00
                XORed Path 1 : aa,bb,cc,dd
                XORed Path 2 : aa,01,02,dd
                Sorted XORed Path 1 : aa,bb,cc,dd
                Sorted XORed Path 2 : 01,02,aa,dd <-- chosen

 Processing for BVLAN2, after applying ECT Mask ff
                XORed Path 1 : 55,44,33,22
                XORed Path 2 : 55,fe,fd,22
                Sorted XORed Path 1 : 22,33,44,55 <-- chosen
                Sorted XORed Path 2 : 22,55,fd,fe

SUMMARY
=======
        Path 1 used by BVIDs: 2
        Path 2 used by BVIDs: 1

This script allows comparing a number of SPB equal shortest paths to better understand how the SPB algorithm decides which path to program into each BVLAN.
The paths can be enteres as lists of BMACs, or simly as the relevant octets which differ.
See also the ACLI manual.
