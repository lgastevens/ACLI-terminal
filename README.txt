$Version = 6.00

Install instructions
====================

If installing over an existing installation, before moving to the install steps below do the following:
- Run the application one last time, and under Edit / Settings..., make sure "Save settings to user directory" checkbox is checked, and then close the application; this will ensure that the ConsoleZ preferences and tab profiles will be saved in your home directory (C:\Users\<username>\AppData\Roaming\Console\console.xml) and can thus be picked up by the new installation

Run the ACLI-Install.exe installer. The installer offers two installation modes: Install for all users (requires Administrator rights) or install for me only.


Uninstall instructions
======================

Go under Control Panel / Programs and Features.
Locate and select the ACLI program in the list then click Uninstall.



Updates
=======
Under Start Menu / ACLI, launch the ACLI Update shortcut (or alternatively launch the UPDATE.BAT file in the directory where you installed ACLI).
This will launch an update script which will automatically check to see if there are any newer versions available for the distribution.
If so, the newer versions available will be displayed and you will have the choice to go ahead with the update.
The same update script can be used to rollback from the last update performed, if that caused problems.

The ACLI Session Manager, by Marlon Scheid, has its own update capabilty ("check for update" button) and will thus not be updated by the ACLI update script.


Connecting to a switch with ACLI
================================

Launch the ACLI shortcut then...

ACLI> help

ACLI> open ?

ACLI> open <ip address>

...

The following syntaxes will produce a TELNET connection:

	ACLI> open <ip address>
	ACLI> telnet <ip address>

The following syntaxes will produce an SSH connection:

	ACLI> open -l <username> <ip address>
	ACLI> ssh connect <ip address>

The following syntax will produce a Serial Port connection:

	ACLI> open serial:<COM-port>



Customizing
===========

The ACLI Terminal program is a Perl script (acli.pl)

Console.exe is ConsoleZ; this is simply a freeware improved DOS box for use under Windows

ConsoleZ is just a wrapper though; it does not have to run cmd.exe

So we use ConsoleZ to invoke "perl.exe acli.pl" (instead of cmd.exe)

Under Console menu Edit / Settings / Tabs there are 4 predefined Tabs:
 - ACLI                  : this launches perl.exe onto acli.pl
 - ConsoleZ              : this launches a regular DOS box (cmd.exe)
 - ACLI Serial Port      : this launches a list of available serial ports to chose from
 - ACLI Terminal Servers : this launches a list of known terminal server connections to chose from


You can add additional tabs to connect to your favourite switches
For example, a new tab:

 - Title: "My Switch"
 - Shell: "%ACLIDIR%\acli.bat" -p 192.168.10.1

will automatically start the connection to the switch IP address (or hostname); the -p flag will automaticaly login, if the switch is VOSS using default credentials (e.g. rwa/rwa)

NOTE: It is recommended that under the Console menu Edit / Settings, you check the box "Save settings to user directory"; the ConsoleZ profile will then be saved here: C:\Users\<username>\AppData\Roaming\Console\console.xml
If you do not do this, the ConsoleZ profile will be saved in the ACLI install directory, with these consequences:
- If you installed ACLI "for me only": will still work fine; but next time you install a new version of ACLI you will lose those profiles
- If you installed ACLI "for all users" and you have Admin rights: the profile will be saved and used by all users
- If you installed ACLI "for all users" and you do not have Admin rights: you will not be able to make changes to the profile settings


You can also make ConsoleZ automatically start with selected Tabs open (and hence automatically connect to those switches) by adding the Tab names in the shortcut target using the -t flag; for example:

"C:\Program Files\ACLI\Console.exe" -w "ACLI" -t ACLI -t "My Switch"

will start ConsoleZ with both the ACLI and the "My Switch" tabs open


acli.pl command line options:
----------------------------
C:\>acli -h
acli.pl version 6.00

Usage:
 acli.pl [-cehijkmnopqswxyz]
 acli.pl [-ceijklmnopqrstwxyz] [<user>:<pwd>@]<host/IP> [<tcp-port>] [<capture-file>]
 acli.pl [-ceijmnopqrswx]      [<user>:<pwd>@]serial:[<com-port>[@<baudrate>]] [<capture-file>]
 acli.pl [-ceijmnopqrswxyz]    [<user>:<pwd>@]trmsrv:[<device-name> | <host/IP>#<port>] [<capture-file>]
 acli.pl [-eimoqsw]            pseudo:[<name>] [<capture-file>]
 acli.pl -r <host/IP or serial or trmsrv syntaxes above> <"relay cmd" | IP> [<capture-file>]
 acli.pl [-f] -g <acli grep pattern> [<cfg-file or wildcard>] [<2nd file>] [...]

 <host/IP>        : Hostname or IP address to connect to; for telnet can use <user>:<pwd>@<host/IP>
 <tcp-port>       : TCP port number to use
 <com-port>       : Serial Port name (COM1, /dev/ttyS0, etc..) to use
 <"relay-cmd"/IP> : To execute on relay in form: "telnet|ssh [-l <user[:<pwd>]>] <[user[:<pwd>]@]IP>"
                    If single IP/Hostname provided then "telnet IP/Hostname" will be executed
 <capture-file>   : Optional output capture file of CLI session
 <name>           : Loads up pseudo mode profile name (or legacy number 1-99)
 -c <CR|CRLF>     : For newline use CR+LF (default) or just CR
 -e escape_char   : CTRL+<char> for escape sequence; default is "^]"
 -f <type>        : Used with -g to force the Control::CLI::Extreme family_type
 -g <grep-string> : Perform ACLI grep on offline config file or from STDIN (pipe)
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
 -s <sockets>     : List of socket names for terminal to listen on (0 to disable sockets)
 -t               : When tcp-port specified, flag to say we are connecting to a terminal server
 -w <work-dir>    : Run on provided working directory
 -x               : If connection lost, exit instead of offering to reconnect
 -y <term-type>   : Negotiate terminal type (e.g. vt100)
 -z <w>x<h>       : Negotiate window size (width x height)

So, for example, for a simple Telnet connection:

C:\>acli 192.168.10.10

And if you wanted to provide the credentials on the command line:

C:\>acli username:password@192.168.10.10

For an SSH connection the -l option must be used:

C:\>acli -l username 192.168.10.10

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

C:\>acli -l username:password 192.168.10.10

While if you wanted to load some other SSH keys for publickey authentication use the -k switch:

C:\>acli -l username -k id_dsa 192.168.10.10


To connect via Serial port COM1:

C:\>acli -n serial:COM1

(Serial port communication is slow; the -n switch will prevent the ACLI terminal from discovering the device to enter interactive mode, which can take a few seconds; you can enter interactive mode once connected by using CTRL-T)

If not sure what serial port to use:

C:\>acli -n serial:

This will show the available serial ports, and you can select the desired one.

Connecting via a terminal server, simply provide the TCP port and set the -t flag:

C:\>acli -nt 192.168.10.10 5010

(Serial port communication is slow; the -n switch will prevent the ACLI terminal from discovering the device to enter interactive mode, which can take a few seconds; you can enter interactive mode once connected by using CTRL-T)

The ACLI terminal is able to keep track of previous connections via terminal servers and the information is cached for ease of retrieval:

C:\>acli -nt trmsrv:

This will provide a list of cached terminal server connections; any entry can be selected by number or switch name

Or, if you know the switch name in advance:

C:\>acli -nt trmsrv:VSP9000-1

instead of having to remember the terminal server IP and TCP port number...


It is also possible to connect to a target device via a relay device (telnet/SSH hopping)

C:\>acli -r 10.134.10.10 192.168.10.10

The above will telnet to 10.134.10.10 (e.g. a VSP switch via OOB) and from there telnet to 192.168.10.10 (e.g. a Stackable ERS with no OOB)

If you wanted to supply credentials on the command line:

C:\>acli -r rwa:rwa@10.134.10.10 username:password@192.168.10.10

The above examples could also have been written as:

C:\>acli -r 10.134.10.10 "telnet 192.168.10.10"
C:\>acli -r rwa:rwa@10.134.10.10 "telnet username:password@192.168.10.10"

NOTE: Embedded credentials within the quotes will be removed, before executing the command on the Relay host

To perform SSH on the 2nd hop (e.g. to reach a WLAN9100 AP):

C:\>acli -r rwa:rwa@10.134.10.10 "ssh 192.168.10.10 -l admin"

NOTE: The syntax within the quotes has to correspond to whatever command syntax applies on the Relay host (ssh <ip> -l <username> is the synax used by SSH client on VOSS VSPs)

And to embed credentials:

C:\>acli -r rwa:rwa@10.134.10.10 "ssh 192.168.10.10 -l admin:admin"

NOTE: Embedded SSH password within the quotes will be removed, before executing the command on the Relay host

And if one wanted to use SSH to also connect to the Relay host:

C:\>acli -r -l rwa:rwa 10.134.10.10 "ssh 192.168.10.10 -l admin:admin"



ConsoleZ command line options:
-----------------------------

-c <configuration file>
Specifies a configuration file.

-w <main window title>
Sets main window title. This option will override all other main window title settings (e.g. 'use tab titles' setting)

-t <tab name>
Specifies a startup tab. Tab must be defined in ConsoleZ settings.

-n <tab name>
Rename the tab to the name provided

-d <directory>
Specifies a startup directory. If you want to parametrize startup dirs, you need to specify startup directory parameter as "%1"\ (backslash is outside of the double quotes)

-r <command>
Specifies a startup shell command.

-p <base priority>
Specifies shell base priority.

-ts <sleep time in ms>
Specifies sleep time between starting next tab if multiple -t's are specified.

-reuse
Reuses another instance, if any exists, instead of starting a new one. 


For more details view the ConsoleZ Help


Invoking ACLI application from another program which supplies the IP address
----------------------------------------------------------------------------
You can use either of these formats:

<your ACLI install directory>\Console.exe -t ACLI -r "<optional switches> <IP address>"

e.g.: "%ACLIDIR%\Console.exe" -t ACLI -r "-l rwa 10.134.169.91"

- or -

<your ACLI install directory>\Console.exe -t ConsoleZ -r "/k%ACLIDIR%\acli <optional switches> <IP address>"

e.g.: "%ACLIDIR%\Console.exe" -t ConsoleZ -r "/k%ACLIDIR%\acli -l rwa 10.134.169.91"


The former runs perl.exe directly; the latter starts with cmd.exe and then invokes acli.bat file.


Integrating ACLI into mRemoteNG
-------------------------------
Create these two entries under "External Tools":

Display Name     = ACLI Telnet
Filename         = %ACLIDIR%\Console.exe
Arguments        = -t ACLI -n %NAME% -r "%USERNAME%:%PASSWORD%@%HOSTNAME% %PORT%"
Try to Integrate = checked

Display Name     = ACLI SSHv2
Filename         = %ACLIDIR%\Console.exe
Arguments        = -t ACLI -n %NAME% -r "-l %USERNAME%:%PASSWORD% %HOSTNAME% %PORT%"
Try to Integrate = checked

Display Name     = ACLI TermServ
Filename         = %ACLIDIR%\Console.exe
Arguments        = -t ACLI -n %NAME% -r "-n %USERNAME%:%PASSWORD%@%HOSTNAME% %PORT%"
Try to Integrate = checked

Display Name     = ACLI Stored TermServ
Filename         = %ACLIDIR%\Console.exe
Arguments        = -t "ACLI Terminal Servers"
Try to Integrate = checked


Then new connections can be assigned to Protocol = Ext.App & External Tool = one of the above entries for either Telnet or SSH access


Running acli.pl directly from cmd.exe
=====================================
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


Notes on using Tab Profiles with Administrator rights
=====================================================
If you have enabled the ConsoleZ Tab option to run as Administrator you will most likely get a Windows User Account Control (UAC) popup every time asking you whether you "want to allow this app from an unknown publisher to make changes to your device".
In order to get rid of these warnings, without disabling UAC, you can run the windows task scheduler, create a task, making sure the checkbox "Run with highest privileges" is enabled, in the Action tab select the Console.exe application and under Conditions tab deselect all options related to power and under Settings tab deselect the option to stop task if it runs more than a set limit. Then replace the ACLI ConsoleZ Shortcut to now point to: C:\Windows\System32\schtasks.exe /RUN /TN "taskname-you-used"
Now every time you open the ConsoleZ tab you will no longer get the annoying popup.


Notes on using sockets for tie-ing terminals together
=====================================================
When tie-ing a terminal to other terminals (so that a command made on the driving terminal gets pushed to the other terminals) sockets are used on the internal loopback interface.
If you have Windows Firewall enabled, the 1st time you use this functionality you might get a popup asking whether to allow Perl to communicate over the loopback network interface.
Select allow if you want to use this functionality


Notes on using ACLI's highlight and sed re-colouring capability
===============================================================
With ACLI terminal it is possible to highlight any text in the switch output:

  <switch command> ^ <pattern to highlight>

By default the highlight is rendered in bright red (this can be changed using the ACLI> highlight commands, or in the acli.ini file)

The @sed command also allows certain patterns to be automatically recoloured.

These highlights and re-colouring are done using ANSI Escape sequences.

Note that if, under ConsoleZ settings / Appearance / Font, you enable a "Custom color", the ACLI highlight capability will appear to not work anymore.
This is becasue ConsoleZ is now re-colouring all output in the window to the new custom colour you have set.
If you want to change your default font colour, you should do this under the setting of your system's cmd window settings (ConsoleZ will then use that as default).
See also the ACLI manual, Highlight section.


Other tools included in the ACLI distribution
=============================================
Also supplied in the distribution zip file are these other tools..

C:\>grep
grep.pl version 2.3

Usage:  [-iv] "pattern" [<file or wildcard>] [<2nd file>] [<3rd file>] [...]

        -i: Case insensitive pattern match
        -v: Return non matching lines

        Pattern syntax for logical operators:
         <str1>and<str2> = "<str1>&<str2>"
         <str1>or<str2>  = "<str1>|<str2>"
        Alternatively, use standard perl pattern match: "/pattern/"

----------------

C:\>aftp
aftp.pl version 1.11

 Simultaneously transfers files to/from 1 or more devices using either FTP or SFTP
 When GETting the same file from many devices, prepends device hostname/IP to filename
 When PUTting the same file back to many devices, only specify the file without prepend

Usage:
 aftp.pl [-l <user>] [-p <path>] <host/IP/list> [<ftp|sftp>] <get|put> <file-list/glob>
 aftp.pl -f <hostfile> [-l <user>] [-p <path>] [<ftp|sftp>] <get|put> <file-list/glob>
 aftp.pl -x <spreadsheet>[:<sheetname>]!<column-label> [-l <user>] [-p <path>] [<ftp|sftp>] <get|put> <file-list/glob>

 -f <hostfile>     : File containing a list of hostnames/IPs to connect to; valid lines:
                   :   <IP/hostname>         [<unused-display-name>] [# Comments]
                   :  [<IP/hostname>]:<port> [<unused-display-name>] [# Comments]
 -l <user>[:<pwd>] : Use non-default credentials; password will be prompted if not provided
 -p <path>         : Path on device
 -x <spreadsheet>[:<sheetname>]!<column-label>  : Spreadsheet file (Microsoft Excel, OpenOffice, CSV)
                    Spreadsheet must be a simple table where every row is a device with a number
                    of parameters. The first row of the table must be a label for the column values.
                    The label corresponding to the column with the switch IP/hostnames must be
                    supplied in <column-label>.
                    The <sheetname> is optional; if not supplied the first sheet of the spreadsheet
                    will be used
 <host/IP list>    : List of hostnames or IP addresses
                   : Note that valid IP lists can be written as: 192.168.10.1-10,40-45,51
                   : IPv6 addresses are also supported: 2000:10::1-10 (decimal range 1-10)
                   : 2000:20::01-10 (hex range 1,2,3,4,5,6,7,8,9,a,b,c,d,e,f,10)
 <ftp|sftp>        : Protocol to use; if omitted will default to FTP
 <get|put>         : Whether we get files from device, or we put files to it
 <file-list/glob>  : Filename or glob matching multiple files or space separated list


The latter can FTP/SFTP put or get 1 or more files to/from 1 or many switches simultaneously.
The switches need to have FTP or SFTP Server functionality activated.
For example, to recover the config.cfg file from several switches you can do:

C:\>aftp 10.134.169.91-92,81-84,171-172 get config.cfg
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


C:\>dir *.cfg
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

C:\>aftp 10.134.169.91-92,81-84,171-172 put config.cfg
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


C:\>

----------------

C:\>cfm-test
cfm-test.pl version 1.3

Usage:
 cfm-test.pl <ssh|telnet> <[username[:password]@]seed-IP> <ping|tracert>


Provide this tool with the IP inband address and login credentials of a switch in an SPB Fabric. The script will then:
 - discover every other node in the Fabric
 - connect to all nodes in the Fabric
 - perform on ALL nodes simultaneously the requested CFM test (currently L2 traceroute or L2 ping)
 - verify the result of such tests
 - only reports tests which failed

----------------

C:\>acmd
acmd.pl version 1.07

 Execution of CLI commands/script in bulk to many Extreme Networks devices using SSH or Telnet

Usage:
 acmd.pl [-agiopty] [-l <user>] <host/IP/list> <telnet|ssh> "semicolon-separated-cmds" [<output-file>]
 acmd.pl [-agiopty] [-l <user>] -s <script-file> <host/IP/list> <telnet|ssh> [<output-file>]
 acmd.pl [-agiopty] [-l <user>] -f <hostfile> <telnet|ssh> "semicolon-separated-cmds" [<output-file>]
 acmd.pl [-agiopty] [-l <user>] -f <hostfile> -s <script-file> <telnet|ssh> [<output-file>]
 acmd.pl [-agiopty] [-l <user>] -x <spreadsheet>[:<sheetname>]!<column-label> <telnet|ssh> "semicolon-separated-cmds" [<output-file>]
 acmd.pl [-agiopty] [-l <user>] -x <spreadsheet>[:<sheetname>]!<column-label> -s <script-file> <telnet|ssh> [<output-file>]

 -a               : In staggered mode (-g) abort further iterations if at least one host fails
 -f <hostfile>    : File containing a list of hostnames/IPs to connect to; valid lines:
                  :   <IP/hostname>         [<display-name>] [# Comments]
                  :  [<IP/hostname>]:<port> [<display-name>] [# Comments]
 -g <number-N>    : Stagger job over more iterations each for a maximum of N hosts;
                    if not specified, job is performed against all hosts in a single cycle
 -i               : Create output file per-host, using filename <host/IP>[_<output-file>]
 -l <user>        : Specify user credentials to use (password will be prompted)(default = rwa/rwa)
 -o               : Overwrite <output-file>; default is to append
 -p <password>    : Specify a password via command line (instead of being prompted for it)
 -s <script-file> : File containing list of commands to be executed against all hosts
 -t <timeout>     : Timeout value in seconds to use (default = 20secs)
 -x <spreadsheet>[:<sheetname>]!<column-label>  : Spreadsheet file (Microsoft Excel, OpenOffice, CSV)
                    Spreadsheet must be a simple table where every row is a device with a number
                    of parameters. The first row of the table must be a label for the column values.
                    The label corresponding to the column with the switch IP/hostnames must be
                    supplied in <column-label>. The other column labels can be embedded as variables
                    $<label-name> in the supplied CLI commands or script file.
                    The <column-label> and $<label-name> names are case insensitive and any spaces used
                    within them in the spreadsheet will be replaced with the '_' underscore character.
                    The <sheetname> is optional; if not supplied the first sheet of the spreadsheet
                    will be used
 -y               : Skip job detailed summary and user confirmation prompt
 <host/IP list>   : List of hostnames or IP addresses
                  : Note that valid IP lists can be written as: 192.168.10.1-10,40-45,51
                  : IPv6 addresses are also supported: 2000:10::1-10 (decimal range 1-10)
                  : 2000:20::01-10 (hex range 1,2,3,4,5,6,7,8,9,a,b,c,d,e,f,10)
 <telnet|ssh>     : Protocol to use
 <output-file>    : Output file (and suffix with -i) for output filenames
 

If you don’t use the –g flag, the script will attack all nodes in one go; with SSH this will be slow initially as the SSH authentications are blocking calls.
If you use the –g flag, you can stagger it to do N switches at a time; with SSH it is best to stagger around 10 switches at a time.
The critical thing when working with many switches is keeping track of when things go wrong (if you can’t connect to 1 switch, or some switch does not like one of your commands).
The approach taken is that if a command or the connection fails to all switches in the 1st iteration, then the script bombs out => changes were not made on any switch (unless 1 command gave an error across all switches, in which case all preceding commands in your script will have executed).
If instead only a few switches fail during an iteration (and you are using the staggered mode with –g) you can control whether you would like to carry on with subsequent iterations (default) or not (set the –a flag for abort).
In any case, if the script succeeds on some switches, but fails on others or is not executed on others because the last iterations were skipped (-g + -a) the list of all switches for which the script was not executed will be stored in a file <hostfile>.retry ; that way you can easily re-trigger the same script for just those switches which are remaining (after you’ve fixed the problem, whatever that was..).
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
Also if a switch name is provided, it will replace any occurrences of $$ in the CLI script.

A sample <script-file> file, which sets the SNMP location/contact and changes the CLI passwords for ro user:

config term
snmp-server location "test test"
snmp-server contact "Ludovico"
username ro level ro // ro // newro // newro
show cli password
end


This is the output of it running:

C:\>acmd.pl -o -f myhosts -s myscript ssh output.log
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


Using $$ variable:

acmd -l rwa -p rwa -f hosts.txt ssh "enable; config term; prompt $$; router isis; sys-name $$"

And <script-file> has:

10.7.6.8   BEB-608
10.7.6.9   BEB-609
10.7.6.14  BEB-614
10.7.6.15  BEB-615
10.7.6.20  BEB-620
10.7.6.21  BEB-621


Using a spreadsheet file (xls, xlsx, xlsm, csv, ods, sxc):

Switch		Name	Nickname	Bmac
10.7.6.8	BEB-608	0.00.01		02bb00000081
10.7.6.9	BEB-609	0.00.02		02bb00000081


C:\Users\lstevens\Scripts\acli\working-dir>acmd -l rwa -p rwa -x excel.csv!Switch ssh "enable; config term; prompt $name; router isis; sys-name $name; spbm 1 nickname $nickname"
================================================================================
Identified 2 hosts to run job against
Job consists of pushing CLI commands provided in command line (5 commands)
Performing job over single iteration
-> job will be performed by connecting to all 2 hosts at the same time
SSH will be used with 'rwa' username and password provided
Any output received from hosts will be discarded (config only script)
If the script succeeds on some hosts but fails on others
-> list of hosts which failed will be listed in file: acmd.retry
-> file 'acmd.retry' already exists and will be overwritten!
================================================================================
OK to proceed [Y = yes; any other key = no] ? y
Connecting to 2 hosts ..............................<1>.<2> done!
Entering PrivExec on 2 hosts ..<2> done!
Executing CLI script on 2 hosts
- config term   ..<2> done!
- prompt $name   ..<2> done!
- router isis   ..<2> done!
- sys-name $name   ..<2> done!
Disconnecting from 2 hosts



----------------

C:\>acligui -h
acligui.pl version 1.17

Usage:
 acligui.pl [-gimnpstuw] [<hostname/IP list>]
 acligui.pl [-gimnpstuw] -f <hostfile>

 <host/IP list>   : List of hostnames or IP addresses
                  : Note that valid IP lists can be written as: 192.168.10.1-10,40-45,51
                  : IPv6 addresses are also supported: 2000:10::1-10 (decimal range 1-10)
                  : 2000:20::01-10 (hex range 1,2,3,4,5,6,7,8,9,a,b,c,d,e,f,10)
                  : As well as IP:Port ranges: [<hostname/IPv4/IPv6>]:20000-20010
 -f <hostfile>    : File containing a list of hostnames/IPs to connect to; valid lines:
                  :   <IP/hostname>         [<name-for-ACLI-tab>] [-n|-t] [# Comments]
                  :  [<IP/hostname>]:<port> [<name-for-ACLI-tab>] [-n|-t] [# Comments]
                  : The -n or -t flags will be passed onto ACLI when connecting to that host
 -g               : Show GUI even if host/IP and credentials provided
 -h               : Help and usage (this output)
 -i <log-dir>     : Path to use when logging to file
 -m <script>      : Once connected execute script (if no path included will use @run search paths)
 -n               : Launch terminals in transparent mode (no auto-detect & interact)
 -p ssh|telnet    : Protocol to use; can be either SSH or Telnet (case insensitive)
 -s <sockets>     : List of socket names for terminals to listen on (0 to disable sockets)
 -t <window-title>: Sets the containing window title into which all connections will be opened
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

C:\>acligui 192.168.10.10-15,22,24

This will open up the ACLI GUI Launcher window, from where you can populate the username & password fields and then click on "Launch" which will then open 8 ACLI Tabs and connect to each of the switches. Note the shorthand way that IP addresses can be listed.

Or you could already specify the username to use:

C:\>acligui -u rwa 192.168.10.10-15,22,24

In this case the ACLI GUI Launcher window will still open, but now you only need to provide the password and then click "Launch"

If instead both username and password are provided on the command line:

C:\>acligui -u rwa:rwa 192.168.10.10-15,22,24

In this case the ACLI GUI Launcher window will not open and you will directly get the desired Console Window with 8 ACLI Tabs each connected to the selected IPs.
However, in this latter case you had to type the password in clearcase on the command line, which may be undesireable.

If you wanted the above to still open the GUI window (so that logging & working directory can be set) then add the -g switch:

C:\>acligui -g -u rwa:rwa 192.168.10.10-15,22,24

An alternative way to launch acligui, is via Start / Run, using the same command line syntax as above, but specifying acligui.vbs instead of just acligui:

acligui.vbs -u rwa 192.168.10.10-15,22,24

And finally, if you wanted to share an ACLI shortcut to connect to a bunch of switches, you can do the following:

1 - Create a batch file (.bat extension) containing:

	@echo off
	acligui.vbs -p ssh -u "<username>[:<password>]" -w "%CD%" -f %0 -t "Window Title"
	exit
	
	# List hosts below
	<IP-1>		<Hostname-1>
	<IP-2>		<Hostname-2>
	<IP-3>		<Hostname-3>	-n
	[<IP-4>]:<PORT>	<Hostname-4>	-t
	...

Notes:
 - Always place double quotes around the credentials as shown, in case of special characters
 - If the '%' character is present in the credentials, it will need to be escaped by entering it twice '%%'
 - Tested with password containing all of these special characters: £$%^&*_+-=<>#/\|[]{}!;:@~
 - Always place double quotes around any value containing the space character, as seen above for "Window Title"
 - The per entry -n and -t flags are supported and will be placed on the ACLI command invoked for the entry

2 - Place the file in the directory you wish to be used as working directory once connected to switches

3 - Run the batch file directly, or make a shortcut to it and run that

----------------

C:\>spb-ect
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
