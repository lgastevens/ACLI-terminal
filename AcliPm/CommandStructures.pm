# ACLI sub-module
package AcliPm::CommandStructures;
our $Version = "1.06";

use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::GlobalMatchingPatterns;


######################
# Command structures #
######################
our $ControlCmds = { # Hash of commands available under ACLI control mode
	'?'								=> '',
	alias		=> {
			disable						=> '',
			echo		=> {
					disable				=> '',
					enable				=> '',
			},
			enable						=> '',
			info						=> '',
			list						=> '.*',
			load						=> '.+',
			merge						=> '.+',
			reload						=> '',
			show						=> '\S*',
	},
	cd								=> '.+',
	clear								=> '',
	close								=> '',
	cls								=> '',
	ctrl		=> {
			'clear-screen'	=> {
					''				=> '\^?[A-Za-z\[\\\\\]\^_]',
					none				=> '',
			},
			debug		=> {
					''				=> '\^?[A-Za-z\[\\\\\]\^_]',
					none				=> '',
			},
			escape		=> {
					''				=> '\^?[A-Za-z\[\\\\\]\^_]',
					none				=> '',
			},
			info						=> '',
			'more-paging-toggle'=> {
					''				=> '\^?[A-Za-z\[\\\\\]\^_]',
					none				=> '',
			},
			quit		=> {
					''				=> '\^?[A-Za-z\[\\\\\]\^_]',
					none				=> '',
			},
			'send-break'	=> {
					''				=> '\^?[A-Za-z\[\\\\\]\^_]',
					none				=> '',
			},
			'term-mode-toggle'=> {
					''				=> '\^?[A-Za-z\[\\\\\]\^_]',
					none				=> '',
			},
	},
	debug		=> {
			info						=> '',
			level						=> '\d{1,4}',
			off						=> '',
			run						=> '.*',
	},
	dictionary	=> {
			echo		=> {
					always				=> '',
					disable				=> '',
					single				=> '',
			},
			info						=> '',
			list						=> '',
			load						=> '.+',
			path						=> '',
			'port-range'	=> {
					info				=> '',
					input		=> {
							''		=> '\d[\d\/:,-]+\d',
							clear		=> '',
					},
					mapping		=> {
							''		=> '\d[\d\/:,-]+\d',
							clear		=> '',
					},
			},
			reload						=> '',
			unload						=> '',
	},
	dir								=> '.*',
	echo		=> {
			info						=> '',
			off		=> {
					''				=> '',
					output		=> {
							off		=> '',
							on		=> '',
					},
			},
			on						=> '',
			sent						=> '',
	},
	flush								=> '',
	help								=> '',
	highlight	=> {
			background	=> {
					black				=> '',
					blue				=> '',
					cyan				=> '',
					disable				=> '',
					green				=> '',
					magenta				=> '',
					red				=> '',
					white				=> '',
					yellow				=> '',
			},
			bright		=> {
					disable				=> '',
					enable				=> '',
			},
			disable						=> '',
			foreground	=> {
					black				=> '',
					blue				=> '',
					cyan				=> '',
					disable				=> '',
					green				=> '',
					magenta				=> '',
					red				=> '',
					white				=> '',
					yellow				=> '',
			},
			info						=> '',
			reverse		=> {
					disable				=> '',
					enable				=> '',
			},
			underline	=> {
					disable				=> '',
					enable				=> '',
			},
	},
	history		=> {
			clear		=> {
					all				=> '',
					'device-sent'			=> '',
					'no-error-device'		=> '',
					recall				=> '',
					'user-entered'			=> '',
			},
			'device-sent'					=> '',
			'no-error-device'				=> '',
			echo		=> {
					disable				=> '',
					enable				=> '',
			},
			info						=> '',
			recall						=> '',
			'user-entered'					=> '',
	},
	log		=> {
			'auto-log'	=> {
					disable				=> '',
					enable				=> '',
					retry				=> '',
			},
			info						=> '',
			path		=> {
					set				=> '.+',
					clear				=> '',
			},
			start						=> '\S+(?: (?:-o|-?overwrite)?)?',
			stop						=> '',
	},
	ls								=> '.*',
	mkdir								=> '.+',
	more		=> {
			disable						=> '',
			enable						=> '',
			info						=> '',
			lines						=> '\d+',
			sync		=> {
					disable				=> '',
					enable				=> '',
			},
	},
	open								=> '.+',
	peercp		=> {
			connect						=> '',
			disconnect					=> '',
			info						=> '',
	},
	ping								=> '\S+',
	pseudo		=> {
			attribute	=> {
					clear				=> '\w+',
					info				=> '',
					set				=> '\w+\s*=\s*\S+',
			},
			disable						=> '',
			echo		=> {
					disable				=> '',
					enable				=> '',
			},
			enable						=> '\S*',
			info						=> '',
			name						=> '\S+',
			list						=> '',
			load						=> '\S+',
			prompt						=> '.+',
			'port-range'	=> {
					''				=> '\d[\d\/:,-]+\d',
					clear				=> '',
			},
			type		=> {
					voss				=> '',
					xos				=> '',
					boss				=> '',
					slx				=> '',
			},
	},
	pwd								=> '',
	quit								=> '',
	reconnect							=> '',
	rmdir								=> '.+',
	save		=> {
			all						=> '',
			delete						=> '',
			info						=> '',
			reload						=> '',
			sockets						=> '',
			vars						=> '',
			workdir						=> '',
	},
	sed		=> {
			colour => {'regex:(?:\'[^\']+\'|\"[^\"]+\"|\w+)' => {
					background	=> {
							black		=> '',
							blue		=> '',
							cyan		=> '',
							green		=> '',
							magenta		=> '',
							none		=> '',
							red		=> '',
							white		=> '',
							yellow		=> '',
							},
					bright		=> {
							disable		=> '',
							enable		=> '',
							},
					delete				=> '',
					foreground	=> {
							black		=> '',
							blue		=> '',
							cyan		=> '',
							green		=> '',
							magenta		=> '',
							none		=> '',
							red		=> '',
							white		=> '',
							yellow		=> '',
							},
					reverse		=> {
							disable		=> '',
							enable		=> '',
							},
					underline	=> {
							disable		=> '',
							enable		=> '',
							},
					},
					info				=> '',
					},
			info						=> '',
			input		=> {
					add				=> '(?:[1-9]\d*\s+)?(?:\'[^\']+\'|\"[^\"]+\")\s+(?:\'[^\']*\'|\"[^\"]*\")',
					delete				=> '[1-9]\d*',
			},
			output		=> {
					add		=> {
							''		=> '(?:[1-9]\d*\s+)?(?:\'[^\']+\'|\"[^\"]+\")\s+(?:\'[^\']*\'|\"[^\"]*\")',
							colour		=> '(?:[1-9]\d*\s+)?(?:\'[^\']+\'|\"[^\"]+\")\s+(?:\'[^\']+\'|\"[^\"]+\"|(\w+))',
					},
					delete		=> {
							''		=> '[1-9]\d*',
							colour		=> '[1-9]\d*',
					},
			},
			reload						=> '',
			reset						=> '',
	},
	send		=> {
			brk						=> '',
			char						=> '\d+',
			ctrl						=> '\^?[@A-Za-z\[\\\\\]\^_]',
			line						=> '.+',
			string						=> '.+',
	},
	serial		=> {
			baudrate	=> {
					110				=> '',
					300				=> '',
					600				=> '',
					1200				=> '',
					2400				=> '',
					4800				=> '',
					9600				=> '',
					14400				=> '',
					19200				=> '',
					38400				=> '',
					57600				=> '',
					115200				=> '',
					230400				=> '',
					460800				=> '',
			},
			databits					=> '[5-8]',
			handshake	=> {
					none				=> '',
					rts				=> '',
					xoff				=> '',
					dtr				=> '',
			},
			info						=> '',
			parity		=> {
					none				=> '',
					odd				=> '',
					even				=> '',
					mark				=> '',
					space				=> '',
			},
			stopbits					=> '(?:1(?:\.5)?|2)',
	},
	socket		=> {
			allow		=> {
					add				=> '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}',
					remove				=> '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}',
					reset				=> '',
			},
			bind		=> {
					all				=> '',
					ip				=> '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}',
					reset				=> '',
			},
			disable						=> '',
			echo		=> {
					none				=> '',
					error				=> '',
					all				=> '',
			},
			enable						=> '',
			info						=> '',
			ip						=> '\S+',
			listen		=> {
					''				=> '',
					add				=> '(?:[^\s,]+(?:\s*,\s*)?)+',
					clear				=> '',
					remove				=> '(?:[^\s,]+(?:\s*,\s*)?)+',
			},
			names		=> {
					''				=> '',
					clear				=> '',
					numbers				=> '',
					reload				=> '',
			},
			ping						=> '\S*',
			send						=> '[^\s\"\']+(?:\s+.+)?',
			tie						=> '\S*',
			ttl						=> '\d+',
			untie						=> '',
			username	=> {
					disable				=> '',
					enable				=> '',
			},
	},
	ssh		=> {
			connect						=> '.+',
			info						=> '',
			keys		=> {
					info				=> '',
					load				=> '.+',
					unload				=> '',
			},
			'known-hosts'	=> {
					''				=> '',
					clense				=> '',
					delete				=> '.+',
			},
	},
	status								=> '',
	telnet								=> '.+',
	terminal	=> {
			autodetect	=> {
					disable				=> '',
					enable				=> '',
			},
			configindent					=> '\d\d?',
			hidetimestamp	=> {
					disable				=> '',
					enable				=> '',
			},
			highlightcmd	=> {
					disable				=> '',
					enable				=> '',
			},
			hosterror	=> {
					disable				=> '',
					enable				=> '',
					level		=> {
							error		=> '',
							warning		=> '',
					},
			},
			hostmode	=> {
					interact			=> '',
					transparent			=> '',
			},
			info						=> '',
			ini						=> '',
			newline		=> {
					cr				=> '',
					crlf				=> '',
			},
			portrange	=> {
					spanslots	=> {
							disable		=> '',
							enable		=> '',
					},
					default				=> '[012]',
					unconstrain	=> {
							disable		=> '',
							enable		=> '',
					},
			},
			promptsuffix	=> {
					disable				=> '',
					enable				=> '',
			},
			size		=> {
					clear				=> '',
					set				=> '\d+\s*x\s*\d+',
			},
			timers		=> {
					connection			=> '\d+',
					keepalive			=> '\d+',
					interact			=> '\d+',
					login				=> '\d+',
					session				=> '\d+',
					'transparent-keepalive'	=> {
							disable		=> '',
							enable		=> '',
					},
			},
			type		=> {
					clear				=> '',
					set				=> '\S+',
			},
	},
	trmsrv	=> {
			add		=> {
					telnet				=> '\S+ \d+ \S+(?: .+)?',
					ssh				=> '\S+ \d+ \S+(?: .+)?',
			},
			connect						=> '\d+',
			delete		=> {
					file				=> '',
			},
			info						=> '',
			list						=> '\S*',
			remove		=> {
					telnet				=> '\S+ \d+',
					ssh				=> '\S+ \d+',
			},
			sort		=> {
					cmnt				=> '',
					disable				=> '',
					ip				=> '',
					name				=> '',
			},
			static		=> {
					disable				=> '',
					enable				=> '',
			},
	},
	vars		=> {
			attribute					=> '\S*',
			clear		=> {
					''				=> '',
					dictionary			=> '',
					script				=> '',
			},
			echo		=> {
					disable				=> '',
					enable				=> '',
			},
			info						=> '',
			raw		=> {
					''				=> '\S*',
					all				=> '\S*',
					dictionary			=> '\S*',
					script				=> '\S*',
			},
			show		=> {
					''				=> '\S*',
					all				=> '\S*',
					dictionary			=> '\S*',
					script				=> '\S*',
			},
	},
	version		=> {
			''						=> '',
			all						=> '',
	},
};

our $EmbeddedCmds = {	# Hash of local acli commands available under regular host CLI, in interact mode only
	'@?'								=> '',
	'@$'		=> {
			''						=> '',
			raw						=> '\S*',
			show						=> '\S*',
	},
	'@acli'								=> '',
	'@alias'	=> {
			disable						=> '',
			echo		=> {
					disable				=> '',
					enable				=> '',
			},
			enable						=> '',
			info						=> '',
			list						=> '.*',
			reload						=> '',
			show						=> '\S*',
	},
	'@cat'								=> '.+',
	'@cd'								=> '.+',
	'@clear'							=> '',
	'@cls'								=> '',
	'@dictionary'	=> {
			echo		=> {
					always				=> '',
					disable				=> '',
					single				=> '',
			},
			info						=> '',
			list						=> '',
			load						=> '.+',
			path						=> '',
			'port-range'	=> {
					info				=> '',
					input		=> {
							''		=> '\d[\d\/:,-]+\d',
							clear		=> '',
					},
					mapping		=> {
							''		=> '\d[\d\/:,-]+\d',
							clear		=> '',
					},
			},
			reload						=> '',
			unload						=> '',
	},
	'@dir'								=> '.*',
	'@echo'		=> {
			info						=> '',
			off		=> {
					''				=> '',
					output		=> {
							off		=> '',
							on		=> '',
					},
			},
			on						=> '',
			sent						=> '',
	},
	'@else'								=> '',
	'@elsif'							=> '.+',
	'@endfor'							=> '',
	'@endif'							=> '',
	'@endloop'							=> '',
	'@error'	=> {
			disable						=> '',
			enable						=> '',
			info						=> '',
			level		=> {
					error				=> '',
					warning				=> '',
			},
	},
	'@exit'		=> {
			''						=> '',
			if						=> '.+',
	},
	'@for'								=> "\$$VarUser\\s+&\\S+",
	'@if'								=> '.+',
	'@help'								=> '',
	'@highlight'	=> {
			background	=> {
					black				=> '',
					blue				=> '',
					cyan				=> '',
					disable				=> '',
					green				=> '',
					magenta				=> '',
					red				=> '',
					white				=> '',
					yellow				=> '',
			},
			bright		=> {
					disable				=> '',
					enable				=> '',
			},
			disable						=> '',
			foreground	=> {
					black				=> '',
					blue				=> '',
					cyan				=> '',
					disable				=> '',
					green				=> '',
					magenta				=> '',
					red				=> '',
					white				=> '',
					yellow				=> '',
			},
			info						=> '',
			reverse		=> {
					disable				=> '',
					enable				=> '',
			},
			underline	=> {
					disable				=> '',
					enable				=> '',
			},
	},
	'@history'	=> {
			''						=> '',
			clear		=> {
					''				=> '',
					all				=> '',
					'device-sent'			=> '',
					'no-error-device'		=> '',
					'user-entered'			=> '',
			},
			'device-sent'					=> '',
			'no-error-device'				=> '',
			echo		=> {
					disable				=> '',
					enable				=> '',
			},
			info						=> '',
			'user-entered'					=> '',
	},
	'@last'		=> {
			''						=> '',
			if						=> '.+',
	},
	'@launch'							=> '.*',
	'@log'		=> {
			'auto-log'	=> {
					disable				=> '',
					enable				=> '',
					retry				=> '',
			},
			info						=> '',
			path		=> {
					set				=> '.+',
					clear				=> '',
			},
			start						=> '\S+(?: (?:-o|-?overwrite)?)?',
			stop						=> '',
	},
	'@loop'								=> '',
	'@ls'								=> '.*',
	'@mkdir'							=> '.+',
	'@more'		=> {
			disable						=> '',
			enable						=> '',
			info						=> '',
			lines						=> '\d+',
			sync		=> {
					disable				=> '',
					enable				=> '',
			},
	},
	'@my'								=> "\\\$$VarScript\\\*?(?:\\\[\\\]|\\\{\\\})?(?:\\s*=\\s*(?:\'[^\']*\'|\"[^\"]*\"|.+)|(?:\\s*,\\s*\\\$$VarScript\\\*?(?:\\\[\\\]|\\\{\\\})?)+)?",
	'@next'		=> {
			''						=> '',
			if						=> '.+',
	},
	'@peercp'	=> {
			''						=> '',
			connect						=> '',
			disconnect					=> '',
	},
	'@ping'								=> '\S+',
	'@print'							=> '.*',
	'@printf'							=> '(?:\'[^\']+\'|"[^"]+")\s*,\s*.*',
	'@pseudo'	=> {
			attribute	=> {
					clear				=> '\w+',
					info				=> '',
					set				=> '\w+\s*=\s*\S+',
			},
			echo		=> {
					disable				=> '',
					enable				=> '',
			},
			info						=> '',
			list						=> '',
			load						=> '\S+',
			name						=> '\S+',
			prompt						=> '.+',
			'port-range'	=> {
					''				=> '\d[\d\/:,-]+\d',
					clear				=> '',
			},
			type		=> {
					voss				=> '',
					xos				=> '',
					boss				=> '',
					slx				=> '',
			},
	},
	'@pwd'								=> '',
	'@put'								=> '.*',
	'@quit'								=> '',
	'@read'	=> {
			''						=> '',
			unbuffer					=> '',
	},
	'@rediscover'							=> '',
	'@resume'	=> {
			''						=> '',
			buffer						=> '',
	},
	'@rmdir'							=> '.+',
	'@run'		=> {
			''						=> '.+',
			list						=> '',
			path						=> '',
	},
	'@save'		=> {
			all						=> '',
			delete						=> '',
			info						=> '',
			reload						=> '',
			sockets						=> '',
			vars						=> '',
			workdir						=> '',
	},
	'@sed'		=> {
			colour => {'regex:(?:\'[^\']+\'|\"[^\"]+\"|\w+)' => {
					background	=> {
							black		=> '',
							blue		=> '',
							cyan		=> '',
							green		=> '',
							magenta		=> '',
							none		=> '',
							red		=> '',
							white		=> '',
							yellow		=> '',
							},
					bright		=> {
							disable		=> '',
							enable		=> '',
							},
					delete				=> '',
					foreground	=> {
							black		=> '',
							blue		=> '',
							cyan		=> '',
							green		=> '',
							magenta		=> '',
							none		=> '',
							red		=> '',
							white		=> '',
							yellow		=> '',
							},
					reverse		=> {
							disable		=> '',
							enable		=> '',
							},
					underline	=> {
							disable		=> '',
							enable		=> '',
							},
					},
					info				=> '',
					},
			info						=> '',
			input		=> {
					add				=> '(?:[1-9]\d*\s+)?(?:\'[^\']+\'|\"[^\"]+\")\s+(?:\'[^\']*\'|\"[^\"]*\")',
					delete				=> '[1-9]\d*',
			},
			output		=> {
					add		=> {
							''		=> '(?:[1-9]\d*\s+)?(?:\'[^\']+\'|\"[^\"]+\")\s+(?:\'[^\']*\'|\"[^\"]*\")',
							colour		=> '(?:[1-9]\d*\s+)?(?:\'[^\']+\'|\"[^\"]+\")\s+(?:\'[^\']+\'|\"[^\"]+\"|(\w+))',
					},
					delete		=> {
							''		=> '[1-9]\d*',
							colour		=> '[1-9]\d*',
					},
			},
			reload						=> '',
			reset						=> '',
	},
	'@send'		=> {
			brk						=> '',
			char						=> '\d+',
			ctrl						=> '\^?[@A-Za-z\[\\\\\]\^_]',
			line						=> '.+',
			string						=> '.+',
	},
	'@sleep'							=> '\d+',
	'@socket'	=> {
			allow		=> {
					add				=> '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}',
					remove				=> '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}',
					reset				=> '',
			},
			bind		=> {
					all				=> '',
					ip				=> '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}',
					reset				=> '',
			},
			disable						=> '',
			echo		=> {
					all				=> '',
					error				=> '',
					none				=> '',
			},
			enable						=> '',
			info						=> '',
			ip						=> '\S+',
			listen		=> {
					''				=> '',
					add				=> '(?:[^\s,]+(?:\s*,\s*)?)+',
					clear				=> '',
					remove				=> '(?:[^\s,]+(?:\s*,\s*)?)+',
			},
			names		=> {
					''				=> '',
					numbers				=> '',
			},
			ping						=> '\S*',
			send						=> '[^\s\"\']+(?:\s+.+)?',
			tie						=> '\S*',
			ttl						=> '\d+',
			untie						=> '',
			username	=> {
					disable				=> '',
					enable				=> '',
			},
	},
	'@source'							=> '.+',
	'@ssh'		=> {
			'device-keys'	=> {
					delete				=> '[rd]sa_key_(?:ro|rw|rwa|rwl[123]|admin|auditor|operator|privilege|security)(?:_ietf)?(?: [1-9]\d*)?',
					install		=> {
							admin		=> '',
							auditor		=> '',
							operator	=> '',
							privilege	=> '',
							ro		=> '',
							rw		=> '',
							rwa		=> '',
							rwl1		=> '',
							rwl2		=> '',
							rwl3		=> '',
							security	=> '',
					},
					list				=> '',
			},
			info						=> '',
			keys		=> {
					info				=> '',
					load				=> '.+',
					unload				=> '',
			},
			'known-hosts'	=> {
					''				=> '',
					delete				=> '.+',
			},
	},
	'@status'							=> '',
	'@stop'								=> '.*',
	'@terminal'	=> {
			hidetimestamp	=> {
					disable				=> '',
					enable				=> '',
			},
			info						=> '',
			ini						=> '',
			portrange	=> {
					spanslots	=> {
							disable		=> '',
							enable		=> '',
					},
					default				=> '[012]',
					unconstrain	=> {
							disable		=> '',
							enable		=> '',
					},
			},
	},
	'@timestamp'							=> '',
	'@type'								=> '.+',
	'@until'							=> '.+',
	'@vars'		=> {
			''						=> '',
			attribute					=> '\S*',
			clear		=> {
					''				=> '',
					dictionary			=> '',
					script				=> '',
			},
			echo		=> {
					disable				=> '',
					enable				=> '',
			},
			info						=> '',
			prompt		=> {
					''				=> "\$$VarUser(?:\\s+.+)?",
					ifunset				=> "\$$VarUser(?:\\s+.+)?",
					optional	=> {
							''		=> "\$$VarUser(?:\\s+.+)?",
							ifunset		=> "\$$VarUser(?:\\s+.+)?",
					},
			},
			raw		=> {
					''				=> '\S*',
					all				=> '\S*',
					dictionary			=> '\S*',
					script				=> '\S*',
			},
			show		=> {
					''				=> '\S*',
					all				=> '\S*',
					dictionary			=> '\S*',
					script				=> '\S*',
			},
	},
	'@while'							=> '.+',
};


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
