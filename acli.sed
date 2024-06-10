##############################
# SED file for ACLI Terminal #
##############################
# Version = 1.12
#
# This file is read when a new ACLI Terminal is launched and can be used to define SED (serial editor) patterns
# It can be located in any of these directories in the following order:
# - ENV path %ACLI% (if you defined it)
# - ENV path $HOME/.acli (on Unix systems)
# - ENV path %USERPROFILE%\.acli (on Windows)
# - Same directory where acli.pl resides (ENV path %ACLIDIR%)
#
# NOTE: This file can get updated by the update script if located in the same directory where acli.pl resides (ENV path %ACLIDIR%)
#       if you wish to modify it, place it in one of the other above mentioned directories (or give it a Version = 999)

# This file allows automatic setting of editing patterns which can be applied either on output from the host device or on the input
# stream sent to it. It provides the same functionality as the @sed embedded commands without having to execute those commands.
# For both input and output, a pattern match string can be supplied with a replacement string; this is implemented using Perl's
# s/PATTERN/REPLACEMENT/mgee operator, so capturing parentheses are allowed in the regex PATTERN and can be re-used in the REPLACEMENT string.
# The REPLACEMENT string can also be a Perl code snippet.
# For output only, it is also possible to associate a pattern with a re-colouring profile which can also be defined in this file.
# Re-colouring is implemented using s/PATTERN/<start-ANSI-colour-sequence>$&<stop-ANSI-colour-sequence>/mgee so PATTERN can make full use of
# Perl's lookbehind and lookahead assertions as well as code assertions which can allow matching patterns immediatley before or immediately
# after the actual pattern we want to recolour.
# Only the 8 standard colours are supported, for either foreground or background as well as the ability to set any of bright, underline and reverse.
# You can thus use these patterns to automatically re-colour the output for certain keywords, like make ERROR appear in red, or WARNING
# appear in yellow. Some patterns are supplied by default below.

# Syntax:
#	Lines commencing with '#' are comment lines and are ingnored
#	Comments can also be applied at the end of data line
#
#	A start-id can be supplied, but it needs to be specified before any sed patterns. It will not be processed otherwise.
#	If not supplied 1 is assumed.
#	Every pattern is assigned an id which determines the order in which the patterns are applied. Ids are uniquely allocated for each pattern
#	type (output, output re-colouring, input); patterns read in from this file will be applied with sequential ids starting from start-id.
#	By setting a value > 1 it is possible to reserve ids from 1 to X
#	for interactive use via the @sed embedded command.
#
start-id = 5
#
#
#	A max-id can be supplied to override the default value of 20 which is otherwise hardcoded in ACLI terminal.
#	It is not a good idea to have too many sed patterns, this can affect performance. Up to 30 seems ok.
#
max-id = 30
#
#
#	A colour profle is defined with the following syntax.
#	colour <profile-name> [foreground <black|blue|cyan|green|magenta|red|white|yellow>] [background <black|blue|cyan|green|magenta|red|white|yellow>] [bright] [reverse] [underline]
#	Where <profile-name> can be optionally enclosed in quotes.
#
colour green foreground green bright
colour red foreground red bright
colour blue foreground blue bright
colour yellow foreground yellow bright
colour error foreground red
colour warning foreground yellow
colour ip foreground cyan
colour mac foreground magenta bright
colour sysid foreground magenta
colour port foreground cyan bright
#
#
#	All patterns defined below (Input, Output and Output Colour) can be categorized as either global or against any of the Conrrol::CLI family types.
#	This allows to reduce the number of patterns checked against any family device type. The order of patterns can however remain important, so the
#	applicable category can be set at any time and all subsequent pattern definitions will apply to that category, until a new category is set.
#	If no category is set, global will apply as default for all patterns.
#	A list of family types can also be specified ("global" must not be in the list) in which case subsequent patterns are enumerated sequentially
#	for each family type listed.
#
#	category global
#		or
#	category [list of: BaystackERS|PassportERS|ExtremeXOS|ISW|Series200|Wing|SLX|SecureRouter|WLAN9100|Accelar]
#
#
#	Output colour patterns are defined with the following syntax.
#	[output] '<pattern>' colour '<profile-name>' [# <optional comments>]
#	Where:
#		'output' keyword is optional and can be omitted
#		<pattern> regular expression pattern; must be enclosed in single or double quotes
#		<profile-name> must be a previously defined colour profile name from this file; can be quoted.
#
category global
'(?i)\b(?:up|success)\b'														colour green
'(?i)\b(?:down|failed)\b'														colour red

category PassportERS
'smlt   \Ksmlt'																colour green
'smlt   \Knorm'																colour red
'\d{8,} \w{3} +\d+ [\d:]+  \K\S+?\.(?:tgz|voss|xos)'											colour red	# Highlight VOSS image files

category BaystackERS,ISW
'(?i)active(?=     (?:client|proxy|radius|ring))'											colour green
'(?i)reject(?=     (?:client|proxy|radius|ring))'											colour red

category ExtremeXOS
'(?:Client|Proxy|Radius|(?:Static|Dynamic) +\d+) +\KActive'										colour green
'(?:Client|Proxy|Radius|(?:Static|Dynamic) +\d+) +\KRejected'										colour red
'Ring \(\KComplete'															colour green
'Ring \(\KSevered'															colour red

category ISW
'Ring \(\KComplete'															colour green	# VPEX
'Ring \(\KConfiguring'															colour warning	# VPEX
'Ring \(\KSevered'															colour red	# VPEX
',\K\d\d?(?:-\d\d?)?'															colour port	# Complements global port pattern below

category global
'(?i)(?:error|fatal)\b'															colour error
'(?i)warning\b'																colour warning
'(?:^|[^:-](?:[a-fA-F\d]{2}[:-]){2}|[^:-])\K(?:[a-fA-F\d]{2}[:-]){5}[a-fA-F\d]{2}(?=(?:[^:-]|(?:[:-][a-fA-F\d]{2}){4}[^:-]|$))'		colour mac	# Highlight MAC addresses (anchored to right side for bridge id, and left side for FA elem id)
'\b(?:[a-fA-F\d]{4}\.){2}[a-fA-F\d]{4}\b'												colour sysid	# Highlight ISIS SysIDs
"(?:[\s\(\)]|^)\K(\d{1,3})\.\d{1,3}\.\d{1,3}\.\d{1,3}(?=[\s:\/,]|$)(??{$^N == 255 || $^N == 0 ? '^':''})"				colour ip	# Highlight IPv4 addresses (not masks)
"(?:[\s\(\)]|^)\K([\da-f]{1,4})(?:(?::[\da-f]{1,4}){7}|(?::[\da-f]{1,4})+:(?::[\da-f]{1,4})*|(?::[\da-f]{1,4})*:(?::[\da-f]{1,4})+|::)(?=[\s\/]|$)(??{$^N =~ /^0/ ? '^':''})"	colour ip	# Highlight IPv6 addresses (compact/full notation)
'(?:[>,\s\(\-t]|[^\d:]:|c\d+:|^)\K\d{1,3}[/:](?:\d{1,3}|ALL|s\d)(?:[/:]\d)?(?:-(?:\d{1,3}[/:])?(?:\d{1,2}|s\d)(?:[/:]\d)?)?(?=[,\s\)\(]|$)'	colour port	# Highlight port numbers
#
#
#	Output patterns are defined with the following syntax.
#	[output] '<pattern>' '<replacement>' [# <optional comments>]
#	[output] '<pattern>' {<replacecode>} [# <optional comments>]
#	Where:
#		'output' keyword is optional and can be omitted
#		<pattern> regular expression pattern; must be enclosed in single or double quotes
#		<replacement> replacement string; must also be enclosed in single or double quotes
#		<replacecode> replacement Perl code to execute inside s/// replace; muast be enclosed in {}
#
category PassportERS
'filter acl ace\K( [a-z]+\d?)?'			{defined $1 ? $1 . " "x(9-length($1)) : " "x9}			# Nicely indent VOSS ACL config lines


#category global
#'ERROR'													'Bloody ERROR'		# Funny
#'\s\K([a-fA-F\d]{2}):([a-fA-F\d]{2}):([a-fA-F\d]{2}):([a-fA-F\d]{2}):([a-fA-F\d]{2}):([a-fA-F\d]{2})(?=\s)'	'$1-$2-$3-$4-$5-$6'	# Convert all macs to format xx-xx-xx-xx-xx-xx
#
#
#	Input patterns are defined with the following syntax.
#	input '<pattern>' '<replacement>' [# <optional comments>]
#	input '<pattern>' {<replacecode>} [# <optional comments>]
#	Where:
#		'input' keyword must be specified
#		<pattern> regular expression pattern; must be enclosed in single or double quotes
#		<replacement> replacement string; must also be enclosed in single or double quotes
#		<replacecode> replacement Perl code to execute inside s/// replace; muast be enclosed in {}
#
#	Input sed patterns can be dangerous; they can result in ACLI becomming inoperable in interactive mode.
#
#
# Author's reminder.. from https://perldoc.perl.org/perlre
# - positive lookbehind: (?<=pattern) or \K;	variable length lookbehind is unimplemented, but works with \K
# - negative lookbehind: (?<!pattern)		variable length lookbehind is unimplemented
# - positive lookahead:  (?=pattern)
# - negative lookahead:  (?!pattern)
