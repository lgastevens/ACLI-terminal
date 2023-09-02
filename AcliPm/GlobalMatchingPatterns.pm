# ACLI sub-module
package AcliPm::GlobalMatchingPatterns;
our $Version = "1.11";

use strict;
use warnings;
use Control::CLI::Extreme;


############################
# Global Matching patterns #
############################
our %ErrorPatterns = %{Control::CLI::Extreme::ErrorPatterns};
our %MoreSkipWithin = %{Control::CLI::Extreme::MoreSkipWithin};
our $CmdConfirmPrompt = $Control::CLI::Extreme::CmdConfirmPrompt;
our $CmdInitiatedPrompt = $Control::CLI::Extreme::CmdInitiatedPrompt;

#my $VarCapturePortRegex = '(?:^|\s|Port\-?)((?:\d{1,2}\/\d{1,2}(?:\-\d{1,2}(?:\/\d{1,2})?)?,)*\d{1,2}\/\d{1,2}(?:\-\d{1,2}(?:\/\d{1,2})?)?)(?:\s|$)';
#my $VarCapturePortRegex = '(?:^|\s|Port\-?)((?:\d{1,2}\/\d{1,2}(?:\/\d{1,2})?(?:\-\d{1,2}(?:\/\d{1,2}(?:\/\d{1,2})?)?)?,)*\d{1,2}\/\d{1,2}(?:\/\d{1,2})?(?:\-\d{1,2}(?:\/\d{1,2}(?:\/\d{1,2})?)?)?)(?:\s|$)'; # Channelized support
#my $VarCapturePortRegex = '(?:^|\s|Port\-?)((?:\d{1,2}\/\d{1,2}(?:\/\d{1,2})?(?:\-\d{1,2}(?:\/\d{1,2}(?:\/\d{1,2})?)?)?,)*\d{1,2}\/\d{1,2}(?:\/\d{1,2})?(?:\-\d{1,2}(?:\/\d{1,2}(?:\/\d{1,2})?)?)?|(?:Unit|Slot):\d+ Port: ?\d+)(?:\s|$)'; # Channelized support
#my $VarCapturePortRegex = '(?:^|\s|Port\-?)((?:\d{1,2}\/\d{1,2}(?:\/\d{1,2})?(?:\-\d{1,2}(?:\/\d{1,2}(?:\/\d{1,2})?)?)?,)*\d{1,2}\/\d{1,2}(?:\/\d{1,2})?(?:\-\d{1,2}(?:\/\d{1,2}(?:\/\d{1,2})?)?)?|(?:Unit|Slot):\d+ Port: ?\d+|\d\/ \d)(?:\s|$)'; # Accepts port like '1/ 2' as seen in stk tdp
#my $VarCapturePortRegex = '(?:^|\s|Port\-?)((?:\d{1,2}[\/:]\d{1,2}(?:\/\d{1,2})?(?:\-\d{1,2}(?:[\/:]\d{1,2}(?:\/\d{1,2})?)?)?,)*\d{1,2}[\/:]\d{1,2}(?:\/\d{1,2})?(?:\-\d{1,2}(?:[\/:]\d{1,2}(?:\/\d{1,2})?)?)?|(?:Unit|Slot):\d+ Port: ?\d+|\d\/ \d)(?:\s|$)'; # XOS port format support
#my $VarCapturePortRegex = '(?:^|\s|Port\-?)\K((?:\d{1,2}[\/:]\d{1,2}(?:\/\d{1,2})?(?:\-\d{1,2}(?:[\/:]\d{1,2}(?:\/\d{1,2})?)?)?,)*\d{1,2}[\/:]\d{1,2}(?:\/\d{1,2})?(?:\-\d{1,2}(?:[\/:]\d{1,2}(?:\/\d{1,2})?)?)?|(?:Unit|Slot):\d+ Port: ?\d+|\d\/ \d)(?=\s|$)'; # Using assertions
#my $VarCapturePortRegex = '(?:^|\s|Port\-?)\K((?:\d{1,3}[\/:]\d{1,2}(?:\/\d{1,2})?(?:\-\d{1,3}(?:[\/:]\d{1,2}(?:\/\d{1,2})?)?)?,)*\d{1,3}[\/:]\d{1,2}(?:\/\d{1,2})?(?:\-\d{1,3}(?:[\/:]\d{1,2}(?:\/\d{1,2})?)?)?|(?:Unit|Slot):\d+ Port: ?\d+|\d\/ \d)(?=\s|$)'; # VPEX slot numbers > 99
#our $VarCapturePortRegex = '(?:^|\s|Port\-?)\K((?:\d{1,3}[\/:](?:ALL|s\d|\d{1,2}(?:\/\d{1,2})?)(?:\-\d{1,3}(?:[\/:](?:s\d|\d{1,2}(?:\/\d{1,2})?))?)?,)*\d{1,3}[\/:](?:ALL|s\d|\d{1,2}(?:\/\d{1,2})?)(?:\-\d{1,3}(?:[\/:](?:s\d|\d{1,2}(?:\/\d{1,2})?))?)?|(?:Unit|Slot):\d+ Port: ?\d+|\d\/ \d)(?=[\s-]|$)'; # Insight ports & ALL & end with '-' case "show vlan members"
our $VarCapturePortRegex = '(?:^|\s|Port\-?)\K((?:\d{1,3}[\/:](?:ALL|s\d|\d{1,2}(?:[\/:]\d{1,2})?)(?:\-\d{1,3}(?:[\/:](?:s\d|\d{1,2}(?:[\/:]\d{1,2})?))?)?,)*\d{1,3}[\/:](?:ALL|s\d|\d{1,2}(?:[\/:]\d{1,2})?)(?:\-\d{1,3}(?:[\/:](?:s\d|\d{1,2}(?:[\/:]\d{1,2})?))?)?|(?:Unit|Slot):\d+ Port: ?\d+|\d\/ \d)(?=[\s-]|$)'; # Insight ports & ALL & end with '-' case "show vlan members"
our $VarCapturePortFormatRegex = '(?:Unit|Slot):(\d+) Port: ?(\d+)';

# Patterns for valid $variables; since these are scattered about and subject to change..
our $VarNormal = '[\%\*]|[\w_\d]+';			# Matches valid user variable names + $_ + $\d + $% + $* (but not $)
our $VarNormalAugm = '[\%\*]|\d+[\/:]ALL|[\w_\d]+';	# Same as above, but matches also $ALL, $1/ALL, $2:ALL, etc...
our $VarSlotAll = '(?:\d+[\/:])?ALL';			# Matches $ALL, $1/ALL, $2:ALL, etc...
our $VarUser = '_|[^_\s\.\#\'][\w_\d]*';		# Matches only valid user variable names + $_
our $VarScript = '[^_\s\.\#\'][\w_\d]*';		# Matches only valid variable names (excluding $_ and which can only be declared in a script with @my)
our $VarAttrib = '_([\w_\d]+)(?|\[(\d+)\]|\{(\w+)\})?';	# Matches only $_attribute
our $VarAny = '[\$\@\%\*\>]|[\w_\d]+(?:\[\d+\])?';	# Matches any of above (except $1/ALL, $2:ALL) + $_attribute + $$ + $@ + $> (but not $)
our $VarDelim = '(?=[\s;:,|!\.\/\\\"\+\-\*\%\)\}\]\$\>\<\?]|$)'; # Matches at the end of a valid variable
our $VarHashKey = '[\w\d\-_\/:\.]+';			# Matches valid hash variable keys

our %Grep = (
	SocketEchoBanner	=> '^Output from [^\s:]+:$',
	SocketEchoBannerExc	=> '^Response from ',
	BannerHardPatterns	=> { # Patterns which are undeniably banner lines (following which we accept BannerSoftPatterns)
		BaystackERS	=> '^(?:[-=_!\*]'
					. '|\s*Command Execution Time:'
					. '|Unit: \d  Port: \d+'			# show port-statistics
					. '|   MAC Address    Vid '			# fdb
					. '| +\d\d? +\d\d? +\d\d?'			# show qos diag
				. ')',
		PassportERS	=> '^(?:[-=\*]{2,}|[#\*]'
					. '|\t*Command Execution Time:'
					. '|c: customer vid\s+u: untagged-traffic'	# show vlan mac-address-entry
					. '|(?:VRF\s+VRF|NAME\sID)'			# show ip vrf
				. ')',
		ExtremeXOS	=> '^(?:[-=]{2,}|#)',
		ISW		=> '^(?:[-=]{2,}|[#!])',
		Series200	=> '^(?:[-=!])',
		Wing		=> '^(?:[-=\*]{2,}|[!])',
		SLX		=> '^(?:[-=]|\s*!'
					. '|Flags:'
					. '|\s*\(\w\)-'
					. '|Total Number of .+\s+: \d+$'
				. ')',
		HiveOS		=> '^(?:[-]{2,}'
					. '|(?:[A-Za-z\.\(\)]+\s*)+$'
				. ')',
		SecureRouter	=> '^#',
		WLAN9100	=> '^(?:\s*!|[-])',
		Accelar		=> '^[-=#\*]',
	},
	BannerSoftPatterns	=> { # Patterns which could be part of banner lines, but we only accept them immediately after BannerHardPatterns
		BaystackERS	=> '^(?: *(?:[A-Z][A-Za-z]+[\s\/]*)+$'	# neaps gives banner: Unit/Port Client MAC Address State; ipfi: Unit/Port	IPFIX
					. '|(?:Unit|Port|\s?I-SID)\s+[A-Z]'# show poe-port-status / show fa assignments
					. '|[A-Z]=[A-Z][A-Za-z]'	# Stk ipr legend: B=BGP,  C=Local, I=ISIS, O=OSPF,  R=RIP, S=Static
					. '|IP Address      Age \(min\)'# show ip arp
					. ')',
		PassportERS	=> '^(?:[A-Z]| +[A-Z]| +software releases in /intflash)',
		ExtremeXOS	=> '^(?:[A-Z]|#? +\/?[A-Z]'
					. '|\s{40,}\S'			# show inline-power info ports 2:*
					. ')',
		ISW		=> '^(?:[A-Z]|#? +\/?[A-Z])',
		Series200	=> '^ *(?:[A-Z][A-Za-z]+[\s\/]*)+$',
		Wing		=> '^ *(?:[A-Z]{2,}[\s\/]*)+$',
		SLX		=> '^(?:\s{2,})?[A-Z][A-Za-z]+(?: \w+)*(?:(?:\s{2,})?[A-Za-z]+(?: \w+)*)+$', # show interface stats brief
		HiveOS		=> '^ *(?:[A-Za-z\.\(\)]+\s*)+$',
		SecureRouter	=> '^(?:[A-Z][A-Za-z]| +[A-Z\*])',
		WLAN9100	=> '^(?:\s*[A-Z])',
		Accelar		=> '^(?:[A-Z]| +[A-Z])',
	},
	BannerExceptions	=> { # Exception patterns form above BannerSoftPatterns which must not be treated as banner lines
		BaystackERS	=> '(?:\d{2,}|^(?:'			# any line with 2 or more consecutive digits
					. 'MLT\d'			# show fa elements
					. '|(?:Received|Transmitted)$'	# show port-statistics
#					. '|Level-1	LspID:'
#					. '|User Name:  '		# show snmp-server user||<user>
#					. '|Port: '			# show lldp neighbor vendor-specific avaya fabric-attach
#					. '|Lockout timeout: '		# show user ; 1st line
#					. '|Role name:          '	# show user ; 1st line after hard banner
				. '))',
		PassportERS	=> '(?:(?:^|[^\(\d -]|[^:] )\d{2,}|^(?:'	# any line with 2 or more consecutive digits; except these banners:
										# from ipa: IP_ADDRESS      MAC_ADDRESS        VLAN  PORT                 TYPE    TTL(10 Sec) TUNNEL
										# from show isis spbm ip-multicast-route vrf green detail: SPBM IP-MULTICAST ROUTE INFO - VRF NAME : green, VSN-ISID : 30001
					. '(?:Port(?::? )?|Mlt|Vlan|Clip)\d'
					. '|[VP]\d'
					. '|CPU?\d'
					. '|(?:IO|SF)\d'
					. '|GRT'
					. '|MgmtVirtIp'
					. '|[d-](?:[r-][w-][x-]){3}\s'
					. '|Level-1	LspID:'
					. '|\S+\s+[\da-f]{32}\s'	# macsec
					. '|AsExternal'			# show ip ospf ase
					. '|[A-Z][\w ]+: ?$'		# sys||temperature
					. '|GlobalRouter '		# show ip vrf
				. '))',
		ExtremeXOS	=> '(?:\d{2,}|\d \/\d|\t: |: +\S)',	# any line with 2 or more cosecutive digits, or '3 /3' (from show vlan), or a line with "<tab>: ", or a line with ": "
		ISW		=> '(?:\d{2,}|\d\/\d|\S: +)',		# any line with 2 or more cosecutive digits, or '3 /3' (from show vlan), or a line with "text: "
#		Series200	=> '',
#		Wing		=> '',
		SLX		=> '(?:\d{2,}|^(?:'			# any line with 2 or more cosecutive digits
					. '(?:Po|Lo|Eth)\s?\d'		# show interface stats brief
				. '))',
#		HiveOS		=> '',
		WLAN9100	=> '(?:Enabled|Disabled|On|Off|yes|no)',
	},
	BannerLessShowCommand => { # 1st line of output of a banner-less commands
		PassportERS	=> '^(?:General Info :$)',		# show sys-info
	},
	ConfigUncomment => { # Config lines which are commented out in output of show running-config, and we want to uncomment
		BaystackERS	=> '^! (?:eapol enable|eapol multihost fail-open-vlan)',
	},
	SummaryPatterns	=> {
		BaystackERS	=> '\d+ out of',
		PassportERS	=> '(?:\d+ out of \d+'
					. '|Total number of Displayed Flows on Slot \d+ : \d+'
					. '| Total Num of Entries: \d+'				# show isis spbm nick-name
					. '| Records Displayed \d+/\d+'				# show ip spb-pim-gw foreign-source
					. '| Total [Nn]umber of \S.*\S [Ee]ntries:? \d+'	# show isis spbm multicast-fib / show isis spbm ip-multicast-route detail
				. ')',
	},
	PrivExec		=> '^enable$',
	EnterConfig		=> '^config$',
	EnterConfigTerm		=> '^(?:config(?:ure)? t|configure$)',
	EndConfig		=> '^end\b',
	ContextPatterns	=> { # Only required for family types set to true in %DeviceCfgParse
		# Have seen VSP9k put trailing spaces at end of some config lines, like "router isis     "; so include \s* in patterns below
		BaystackERS	=> [
				'^(?:interface |router \w+\s*$|route-map (?:\"[\w\d\s\.\+<>-]+\"|[\w\d\.-]+) \d+\s*$|ip igmp profile \d+\s*$|wireless|application|ipv6 dhcp guard policy |ipv6 nd raguard policy )', # level0
				'^(?:security|crypto|ap-profile |captive-portal |network-profile |radio-profile )',	# level1
				'^(?:locale)',	# level2
				],
		PassportERS	=> [
				'^ *(?:interface |router \w+(?:\s+r\w+)?\s*$|router vrf|route-map (?:\"[\w\d\s\.\+<>-]+\"|[\w\d\.-]+) \d+\s*$|application|i-sid \d+|wireless|logical-intf isis \d+|mgmt [\dcvo]|ovsdb\s*$)', # level0
				'^ *(?:route-map (?:\"[\w\d\s\.\+<>-]+\"|[\w\d\.-]+) \d+\s*$)',	# level1
				],
		Series200	=> [
				'^ *(?:line |vlan database|interface |route-map (?:\"[\w\d\s\.\+<>-]+\"|[\w\d\.-]+) (?:permit|deny) \d+\s*$)', # level0
				],
	},
	ContextPatternsExcept => { # Contexts which we must not check at previous level
		PassportERS	=> '^ *(?:i-sid \d+)',
	},
	InstanceContext	=> { # These patterns are used with the corresponding advanced grep type used $grep->{Instance}
		Port		=> '^(?:interface (?:GigabitEthernet |fastEthernet |mgmtEthernet |ethernet )?\d|logical-intf isis \d+)', # \d to prevent it matching an ALL
		Vlan		=> '^interface vlan ',
		Mlt		=> '^interface mlt ',
		Loopback	=> '^interface loopback ',
		Router		=> '^router ',
		Vrf		=> '^router vrf ',
		RouteMap	=> '^ *route-map ',
		Isid		=> '^i-sid \d+',
		Igmp		=> '^ip igmp profile ',
		LogicalIntf	=> '^logical-intf isis \d+',
		Mgmt		=> '^(?:mgmt [\dcvo]|interface mgmtEthernet|router vrf MgmtRouter)',
		Ovsdb		=> '^ovsdb\s*$',
		Application	=> '^application$',
	},
	CreateContext		=> '^(?:route-map |ip igmp profile |i-sid \d+|logical-intf isis \d+|ipv6 dhcp guard policy |ipv6 nd raguard policy |mgmt [\dcvo])',
	ExitInstance		=> '^ *(?:exit|back|end)\b',
	DeltaPattern => {	# These patterns can capture and add to the current grep search patterns
		PassportERS	=> {
			Vlan		=> [
						['vlan create (\d+) name',
							'(?:(?:vlan(?:-id)?|vid ?) (?:[\w\-]+ (?:remove )?(?:[,\d\-]+?[,\-])?)?|ip rsmlt peer-address [\d\.]+ [\d\w:]+ )', '(?:[^\d]|$)'],
						['^\s*ip address (\d+\.\d+\.\d+\.\d+)\s', ' ', '(?:[^\d]|$)'],
						['^vlan \d+ ip create (\d+\.\d+\.\d+\.\d+)\/', ' ', '(?:[^\d]|$)'],
						['^vlan i-sid \d+ (\d+)', 'onboarding i-sid ', '(?:[^\d]|$)'],
						['^\s*ipv6 interface address ([\da-f]{1,4}(?::[\da-f]{1,4}){7})/', ' ', '(?:\s|$)'],
			],
		},
		ExtremeXOS	=> {
			Vlan		=> [
						['configure vlan [\w-]+ tag (\d+)', 'vlan ', '(?:[^\d]|$)'],	# Add vlan number grep
						['configure vlan ([\w-]+) tag \d+', 'vlan \"?', '\"?(?:[^\w]|$)'],	# Add vlan name grep
			],
		},
		WLAN9100	=> {
			Vlan		=> [
						['^\s+add  ("[^"]+")  number  \d+$', 'vlan\s+', '$'],
			],
		},
	},
	IndentAdd => { # Marker lines which need intermediate lines to be indented further
				# Each array holds: pattern / number of spaces to add to subsequent lines
		ISW		=> [
					['^ringv2 protect group\d', 1],		# ISW does not indent its ringv2 config, so we fix it..
					['^profile alarm', 0],			# ..part of above fix; profile alarm comes after ringv2 config lines
				],
	},
	IndentSkip => { # Special lines where we do not want to calculate any indentation, and leave them at indent = 0
		ExtremeXOS	=> '^(?: [ >][ei?]  \d)', # show bgp route all: otherwise absence of flags results in indented records
	},
	IndentAdjust => { # Lines which need special indentation adjustment for correct processing
				# Each array holds: pattern / level adjustment / flag for newline to be inserted
		BaystackERS	=> [
					['^Level-1	LspID:', -2, 1],
					['^	Host_name:', -9], # Tab is 8, -9 = -1
					['Metric:\s*\d+\s*	Prefix Length:', -2],
					['UP/Down Bit:', -1],
					['BVID:', -1],
					['^User Name:  ', -2],			# show snmp-server user||<user>
					['^Username:           ', -2],		# show user||<user>
					['^(?:Unit|Port): \d', -3],		# show port-statistics port <list>||<a stat name>
					['^--------+$', -2],			# show port-statistics port <list>||<a stat name>
					['^(?:Received|Transmitted)$', -1],	# show port-statistics port <list>||<a stat name>
				],
		PassportERS	=> [
					['^Level-1	LspID:', -2, 1],
					['^	Host_name:', -9], # Tab is 8, -9 = -1
					['Metric:\s*\d+\s*	Prefix Length:', -2],
					['UP/Down Bit:', -1],
					['B-MAC: ', -2, 1],
					['BVID:', -1],
					['VSN ISID:', -1],
					['IP Source Address:', -2],
					['Group Address    :', -1],
					['TX               :', +1],
					['^[\da-f]{1,4}(?::[\da-f]{1,4}){7}                     \d+$', +1],	# 2nd line of entries from cmd "show ipv6 route static
				],
		WLAN9100	=> [
					['^ *exit', +2],
				],
		ExtremeXOS	=> [
					['^ *(?:Status  VlanID  NSI|------  ------  --------)', +2],	# show lldp neighbors detailed ||Fabric Attach
					['Port            : ', -7, 1],					# show netlogin session
					['Auth status     : ', -6],					# "
					['Agent type      : ', -5],					# "
					['Server type     : ', -4],					# "
					['Policy index    : ', -3],					# "
					['Session timeout : ', -2],					# "
					['Idle timeout    : ', -1],					# "
				],
	},
	IndentExit => { # Lines which need special indent processing to be preserved
		SecureRouter	=> '^ *exit',
		WLAN9100	=> '^ *exit',
	},

	EmptyContexts	=> { # Only required for family types set to true in %DeviceCfgParse
		# Have seen VSP9k put trailing spaces at end of some config lines, like "exit     "; so include \s* in patterns below
		BaystackERS	=> [
				'^interface \w+\s+[\w\d\\-/,]+\s*\n\n?exit\s*\n',
				'^router \w+\s*\n\n?exit\s*\n',
				'^router vrf .+\n\n?exit\s*\n',
				'^route-map (?:\"[\w\d\s\.\+<>-]+\"|[\w\d\.-]+) \d+\s*\n\n?exit\s*\n',
				'^ip igmp profile \d+\s*\n\n?exit\s*\n',
				'^security\s*\n\n?exit\s*\n',
				'^locale\s*\n\n?exit\s*\n',
				'^captive-portal profile \d+\s*\n\n?exit\s*\n',
				'^network-profile \d+\s*\n\n?exit\s*\n',
				'^radio-profile \d+ [\w-]+ .+\n\n?exit\s*\n',
				'^ap-profile \d+\s*\n\n?exit\s*\n',
				'^application\s*\n\n?exit\s*\n',
				'^ipv6 dhcp guard policy (?:\"[\w\d\s\.-]+\"|[\w\d\.-]+)\s*\n\n?exit\s*\n',
				'^ipv6 nd raguard policy (?:\"[\w\d\s\.-]+\"|[\w\d\.-]+)\s*\n\n?exit\s*\n',
				],
		PassportERS	=> [
				'^ *route-map (?:\"[\w\d\s\.\+<>-]+\"|[\w\d\.-]+) \d+\s*\n\n? *exit\s*\n', # order is important!
				'^interface \w+ [\w\d\\-/,]+\s*\n\n?exit\s*\n',
				'^router \w+\s*\n\n?exit\s*\n',
				'^router vrf .+\s*\n\n?exit\s*\n',
				'^router isis remote\n\n?exit\s*\n',
				'^interface loopback \d+\s*\n\n?exit\s*\n',
				'^application\s*\n\n?exit\s*\n',
				'^i-sid \d+(?: [\w-]+)?\s*\n\n?exit\s*\n',
				'^wireless\s*\n\n?exit\s*\n',
				'^logical-intf isis \d+ dest-ip \d+\.\d+\.\d+\.\d+(?: mtu \d+)?(?: src-ip \d+\.\d+\.\d+\.\d+(?: vrf \S+)?)?(?: name "?[\w\d\._ -]+"?)?\s*\n\n?exit\s*\n',
				'^logical-intf isis \d+ vid (?:\d+[,\-])+\d+ primary-vid \d+ (?:port \d+/\d+(?:/\d+)?|mlt \d+)(?: name "?[\w\d\._ -]+"?)?\s*\n\n?exit\s*\n',
				'^mgmt (?:\d )?(?:.+)?\n\n?exit\s*\n',
				'^ovsdb\s*\n\n?exit\s*\n',
				],
		Series200	=> [
				'^line \w+\s*\n\n?exit\s*\n',
				'^vlan database\s*\n\n?exit\s*\n',
				'^interface [\d\\-/,]+\s*\n\n?exit\s*\n',
				'^interface \w+ \d+\s*\n\n?exit\s*\n',
				],
	},
	MultilineBanner	=> {
		BaystackERS	=> '^\s*[A-Z].+\n(?:.*\n)*?-+[\s-]*?-$',
#		PassportERS	=> '^=+\n.+\n=+\n(?:.*\n)+?-+$',
#		PassportERS	=> '^(?:[=\*]+\n.+\n[=\*]+\n(?:.*\n)*?|(?:.*\n)*?-+)$',
		PassportERS	=> '^(?:\*+\n.+\n\*+\n\n)?(?:=+\n.+\n=+\n)?(?:.*\n)*?-+$',
		Accelar		=> '(?:=+\n.+\n=+\n)?(?:.*\n)*?-+$',
#		Accelar		=> '^=+\n.+\n=+\n(?:.*\n)+?-+$',
	},
	MultilineRecord	=> {
#		BaystackERS	=> '(?:\G\n?\d.+\n(?:.+\n){0,3}(\n|-+[\s-]*?-\n))+',
		BaystackERS	=> '(?:\G\n?\d.+\n(?:[^\d].*\n)*(\n|-+[\s-]*?-\n))+',
#		PassportERS	=> '(?:\G\n?\d.+\n(?:.+\n){0,3}\n)+',
#		PassportERS	=> '(?:\G\n?\d.+\n(?:[^\d].*\n)*\n)+',		# failed: ipff||<ip>
#		PassportERS	=> '(?:\G\n?(?:\d.+\n(?:[^\d].*\n)*|\d+\/\d+.*\n(?:[^\/]{3}.*\n)*)\n)+', #line ^\d followed by ^[^\d]; or line ^x/y followed by no port
#		PassportERS	=> '(?:\G\n?(?:\d.+\n(?:[^\n\d].*\n)+|\d+\/\d+.*\n(?:[^\/]{3}.*\n)+)\n)+', #line ^\d followed by ^[^\d]; or line ^x/y followed by no port
		PassportERS	=> '(?:\G\n?(?:\d.+\n(?:[^\n\d].*\n)+|\d+\/\d+.*\n(?:[^\/\n=-]{3}.*\n)+)\n)+', #line ^\d followed by ^[^\d]; or line ^x/y followed by no port, no banner
		Accelar		=> '(?:\G\n?\d.+\n(?:.+\n){0,3}\n)+',
	},
	MultilineApply	=> {
		BaystackERS	=> '(?:\d.+\n\t.+\n|[0-9a-f]{12}\s.+\n[0-9a-f]{12}\s.+\n {59}\d[\d\/]+\n)', # show vlan; ipff
	},
	UnwrapAnchors		=> '^(?:no|default|interface|router|exit|[A-Z])$',
);

our %RecordCountSkip = ( # Patterns which define outputlines which must not be counted towards $term_io->{RecordsMatched}
	PassportERS	=>	'(?:'
				. '^[\da-f]{1,4}(?::[\da-f]{1,4}){7}                     \d+$'	# 2nd line of entries from cmd "show ipv6 route static"
				. '|^\s{55,}\S'							# 2nd line of entries from cmd "show ipv6 ospf interface"
			. ')',
);

our %BannerPatterns = ( # Patterns to check for during device login; originally copied from Control::CLI::Extreme
	SecureRouter	=>	'\((?:Secure Router|VSP4K)',
	PassportERS	=>	'(?:\x0d\\*{36}\n|\x0d\\* Ethernet Routing Switch|\x0d\\* Passport [18]|\n\x0d?(?:AVAYA|NORTEL|EXTREME NETWORKS)(?: VOSS)? COMMAND LINE INTERFACE\n|VSP[49]000)',
	ExtremeXOS	=>	'ExtremeXOS',
	ISW		=>	'Product: ISW',
);

our %WarningPatterns = ( # Patterns to check to determine if previous command generated a warning = command executed but with warnings
	BaystackERS	=> '^% ',
	PassportERS	=> '',
	ExtremeXOS	=> '',
	SecureRouter	=> '',
	WLAN2300	=> '',
	WLAN9100	=> '',
	Accelar		=> '',
);

our %ChangePromptCmds = ( # Commands which change the device prompt; for which we need to re-lock onto the new prompt
	BaystackERS	=> '^\s*snm(?:p(?:-(?:s(?:e(?:r(?:v(?:er?)?)?)?)?)?)?)? +na',		# snmp-server name
	PassportERS	=> '^\s*(?:(?:(?:con(?:f(?:ig?)?)?)? +)?(?:cli +pr|sys? +set? +n)|snmp-(?:s(?:e(?:r(?:v(?:er?)?)?)?)?) +na)|pr(?:o(?:m(?:pt?)))',
												# PPCLI: config cli prompt OR config sys set name
												# ACLI:  snmp-server name OR prompt
	ExtremeXOS	=> '^\s*co(?:n(?:f(?:i(?:g(?:u(?:re?)?)?)?)?)?)? +snmp +sysn',		# configure snmp sysname
	ISW		=> '^\s*ho',								# hostname
	Series200	=> '^\s*(?:(?:no )?ho|set +p)',						# hostname / set prompt (both in privExec only)
	Wing		=> '^\s*com',								# commit (hostname is the command, but it gets applied after commit, so does not work)
	SLX		=> '^\s*sw(?:i(?:t(?:c(?:h(?:-(?:a(?:t(?:t(?:r(?:i(?:b(?:u(?:t(?:es?)?)?)?)?)?)?)?)?)?)?)?)?)?)? +h',	# switch-attributes host-name
	HiveOS		=> '^\s*hos',								# hostname
	SecureRouter	=> '^\s*ho',								# hostname
	WLAN2300	=> '^\s*set? +pr',							# set prompt
	WLAN9100	=> '^\s*ho',								# hostname
	Accelar		=> '^\s*(?:(?:con(?:f(?:ig?)?)?)? +)?(?:cli +pr|sys? +set? +n)',	# config cli prompt OR config sys set name
);

# Patterns to re-trigger device detection when seen
our $NewConnectionPatterns = 'Connected to ';
our %NewConnectionPatterns = ( # These patterns have to match complete ^line$
	ssh		=> '\*? ?Copyright ?\(c\) \d{4}(?:-\d{4})? (?:Avaya|Nortel|Extreme Networks).*\.',
	telnet		=> '\*? ?Copyright ?\(c\) \d{4}(?:-\d{4})? (?:Avaya|Nortel|Extreme Networks).*\.',
	peer		=> '\*? ?Copyright ?\(c\) \d{4}(?:-\d{4})? (?:Avaya|Nortel|Extreme Networks).*\.',
);

our $ReleaseConnectionPatterns = '(?:Closed connection\.|Connection closed by foreign host\.|\s?Connection to .+? closed by (?:foreign|remote) host)';
our $RelayAgentFailPatterns = '(?:'
			. 'telnet: Unable to connect to remote host:'		# As returned by Vulcano (Solaris)
			. '|telnet: could not connect to host'			# As returned by a PassportERS device
			. '|Host .+? is not reachable\.'			# VSP SSH Client
			. '|Connection to .* closed by remote host'	#(bug16)# VSP SSH Client fails with error: ssh_client/1219: SSHC_connect Fails, status = -6912
			. '|Sorry, session limit reached\.\s*\n+Closed connection' # To a Stackable ERS with no more Telnet sessions
		. ')';

# Patterns which if seen, make us switch from buffered (grep & more processing) to unbuffered (no caching either)
our %UnbufferPatterns = (
	BaystackERS	=> '(?:(?:^|\n).*' . $CmdConfirmPrompt		# Covers: prompt ending in (y/n)?
			 . '|\e'
			 . '|(?:^|\n).+\[[^\n\[\]]+] ?[\?:] $'		# Covers: something]? / Configuring from terminal or network [terminal]?
			 . '|(?:^|\n)Enter .+?(?:\([^\n\(\)]+\))? ?: $'	# ERS4800: fa authentication-key / Enter authentication key (length - 1..32): 
			 . '|(?:^|\n)Rebooting'
			 . '|(?:^|\n)Downloading (?:Diag )?Image'
			 . '|^\n?[.!]{2,}'				# Stackable ping with 'continuous' argument
			 . ')',
	PassportERS	=> '(?:(?:^|\n).*' . $CmdConfirmPrompt		# Covers: prompt ending in (y/n)?
			 . '|(?:^|\n).+\[[^\n\[\]]+] ?[\?:] $'		# Covers: something]? / Configuring from terminal or network [terminal]?
			 . '|(?:^|\n)Password: $'			# VOSS with no rc.0: dbg enable 
			 . '|(?:^|\n)".+?" \d+ lines, \d+ characters\n'	# edit <file>
			 . '|(?:^|\n)-> $'				# shell
			 . '|(?:^|\n)Another show or save in progress\.  Please try the command later\.'
			 . '|(?:^|\n)Executing software activate'
			 . '|(?:^|\n)Checking relationships and calculating order of application'
			 . '|(?:^|\n)Connected to 127\.'
			 . '|(?:^|\n)U-Boot \d+'
			 . '|(?:^|\n)Booting...'
			 . '|(?:^|\n)[^\[\]\n]+\s\[[^\[\]\n]*\]:\s?$'	# run spbm script or other; prompts ending in [something or nothing]:
			 . '|(?:^|\n)Connected to domain \S'		# Insight VM, connecting to console
			 . '|^ \*$'					# Timing out ip traceroute
			 . ')',
	ExtremeXOS	=> '(?:(?:^|\n).*' . $CmdConfirmPrompt		# Covers: prompt ending in (y/n)?
			 . '|\e'
			 . '|^BusyBox .+? built-in shell \(ash\)'	# XOS: run script shell.py
			 . ')',
	SLX		=> '(?:(?:^|\n).*' . $CmdConfirmPrompt		# Covers: prompt ending in (y/n)?
			 . ')',
	ISW		=> '(?:(?:^|\n).*' . $CmdConfirmPrompt		# Covers: prompt ending in (y/n)?
			 . ')',
	Series200	=> '(?:(?:^|\n).*' . $CmdConfirmPrompt		# Covers: prompt ending in (y/n)?
			 . ')',
	Wing		=> '(?:(?:^|\n).*' . $CmdConfirmPrompt		# Covers: prompt ending in (y/n)?
			 . ')',
	HiveOS		=> '(?:(?:^|\n).*' . $CmdConfirmPrompt		# Covers: prompt ending in (y/n)?
			 . ')',
	Ipanema		=> '(?:(?:^|\n).*' . $CmdConfirmPrompt		# Covers: prompt ending in (y/n)?
			 . ')',
	SecureRouter	=> '(?:(?:^|\n).*' . $CmdConfirmPrompt		# Covers: prompt ending in (y/n)?
			 . ')',
	WLAN2300	=> '(?:(?:^|\n).*' . $CmdConfirmPrompt		# Covers: prompt ending in (y/n)?
			 . ')',
	WLAN9100	=> '(?:(?:^|\n).*' . $CmdConfirmPrompt		# Covers: prompt ending in (y/n)?
			 . ')',
	Accelar		=> '(?:(?:^|\n).*' . $CmdConfirmPrompt		# Covers: prompt ending in (y/n)?
			 . '|(?:^|\n)Booting...'
			 . ')',
);

our %UnbufPatExceptions = ( # Family exception to above %UnbufferPatterns
	ExtremeXOS	=> '\n\e.*$',					# Partial more prompt: [7mPress ...
);

# Commands where a -y flag can be used with natively on the switch, so we don't process -y in this script
our %YflagCommands = (
	PassportERS =>	'^\s*(?:rese|cop|del|rm)',	# reset, copy, delete, rm (latter was on PPCLI)
);

# Timestamp banner patterns
our %TimeStampBanner = (
	BaystackERS	=> '^(?:\*{78}$|\s+Command Execution Time:)',
	PassportERS	=> '^(?:\*{79}$|\*{84}$|\s+Command Execution Time:)',
);

# Login delay patterns
our $LoginDelayPatterns = '(?:Enter|Re-enter) the New password[: ]+$';

# Patterns to detect connection to Remote Annex
our $RemoteAnnex = 'Enter Annex port name or number: $';
our $RemoteAnnexPort = 'Attached to port (\d+)$';

# Patters of common switch commands we never want de-Aliasing to overrule for ? syntax
our $AliasPreventSyntax = '^(?:show|default|no|sys|fa|mlt|poe|dvr|eap|vr)$';

# ACLI valid -options to be extracted by parseCommand()
our $AcliMinusOptions = '(?:[oynegsbihf]+|[oi]\d+|peer(?:c(?:pu?)?)?|both(?:c(?:p(?:us?)?)?)?)'; # Initial '-' is already matched


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
