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

# Download

[download link](https://github.com/lgastevens/ACLI-terminal/releases)

