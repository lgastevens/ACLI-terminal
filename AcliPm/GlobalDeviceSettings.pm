# ACLI sub-module
package AcliPm::GlobalDeviceSettings;
our $Version = "1.02";

use strict;
use warnings;


############################
# Global Device Settings   #
############################

our %DeviceMorePaging = ( # These settings determine the more paging mode per device
				# [ "model pattern match", setting for telnet/ssh, setting for console or annex]
				# setting values: 0 = static disable; 1 = static enable; 2 = sync mode; undef = paging not configurable
		BaystackERS	=> [
					["VSP",		0, 1],
					["ERS-48",	0, 1],
					["ERS-[45]9",	0, 1],
					["ERS-3[56]",	0, 1],
					[".",		1, 1],
		],
		PassportERS	=> [
					[".",		0, 1],
		],
		ExtremeXOS	=> [
					[".",		0, 1],
		],
		ISW		=> [
					[".",		0, 1],
		],
		Series200	=> [
					[".",		0, 1],
		],
		Wing	=> [
					[".",		0, 1],
		],
		SLX	=> [
					[".",		0, 1],
		],
		HiveOS	=> [
					[".",		0, 1],
		],
		Ipanema	=> [
					undef, # Is Linux, there is no paging of output
		],
		SecureRouter	=> [
					[".",		1, 1],
		],
		WLAN2300	=> [
					[".",		1, 1],
		],
		WLAN9100	=> [
					[".",		0, 1],
		],
		Accelar		=> [
					[".",		1, 1],
		],
);

our %DeviceComment = ( # This structure holds the character which acts as comment in ascii config
		BaystackERS	=> '!',
		PassportERS	=> '#',
		ExtremeXOS	=> '#',
		ISW		=> '!',
		Series200	=> '!',
		Wing		=> '!',
		SLX		=> '!',
		HiveOS		=> '#',
		Ipanema		=> ';',
		SecureRouter	=> '#',
		WLAN2300	=> '#',
		WLAN9100	=> '!',
		Accelar		=> '#',
);

our %DeviceCfgParse = ( # True for device types where we need to track config contexts in order to add indent and do grep properly
		BaystackERS	=> 1,
		PassportERS	=> 1,
		ExtremeXOS	=> 0,	# No configuration contexts (like PPCLI)
		ISW		=> 0,	# Uses indentation on config file, so we leverage that
		Series200	=> 1,	# No indentation on show run, we have to add that
		Wing		=> 0,	# Indentation is provided in show run
		SLX		=> 0,	# Indentation is provided in show run
		HiveOS		=> 0,	# No configuration contexts (like PPCLI)
		Ipanema		=> 0,	# Config cannot be dumped via CLI
		SecureRouter	=> 0,	# Uses indentation on config file, so we leverage that
		WLAN2300	=> 0,	# No configuration contexts (like PPCLI)
		WLAN9100	=> 0,	# Uses indentation on config file, so we leverage that
		Accelar		=> 0,	# who cares..
);

our %DevicePortRange = ( # Determines whether and how the device consolidates consecutive ports into a range format
			# Bit0 = compact ranges 1/1-24
			# Bit1 = non-compact ranges 1/1-1/24
			# Bit2 = ranges can span slots 1/1-2/24
		BaystackERS	=> 1,	# Baystack will list port ranges like this: 1/1-24
		PassportERS	=> 6,	# VOSS will list port ranges like this: 1/1-1/24
		ExtremeXOS	=> 5,	# XOS can list port ranges in both ways: 4:4-4:14 & 4:4-14
		ISW		=> 1,	# ISW will list port ranges like this: 1/1-8
		Series200	=> 2,	# Port ranges in this format 0/1-0/5
		Wing		=> 0,	# n/a
		SLX		=> 1,	# SLX seems to accept 1/1-5 as range, but no lists 1/1,4/1 are supported, bah..
		HiveOS		=> 0,	# n/a
		Ipanema		=> 0,	# n/a
		SecureRouter	=> 0,	# No support for port ranges
		WLAN2300	=> 0,	# n/a
		WLAN9100	=> 0,	# n/a
		Accelar		=> 2,	# Sames as PassportERS
);

our %DeviceSlotPortSep = ( # Determines the slot/port or slot:port separator used
		BaystackERS	=> '/',
		PassportERS	=> '/',
		ExtremeXOS	=> ':',
		ISW		=> '/',
		Series200	=> '/',
		Wing		=> '/', # n/a
		SLX		=> '/',
		HiveOS		=> '/', # n/a
		Ipanema		=> '/', # n/a
		SecureRouter	=> '/',
		WLAN2300	=> '/',
		WLAN9100	=> '/', # n/a
		Accelar		=> '/',
);

our %TabSynMode = ( # How to behave for tab expansions and syntax? [non-acli, acli]
		# bit0 (1) = match prompt; a prompt is expected in front of tab expanded command
		# bit1 (2) = match tail; on CLIs which wrap long commands, need to match tail of command (tab+syn)
		# bit2 (4) = delete 1st line (ending in \n)
		# bit3 (8) = apply dev_del 'te': everything before \e\[K -or- \e[\dD +\e[\dD -or- up_to+prompt
		# bit4(16) = add newline after '?' for syntax prompts
		BaystackERS	=> [undef,  7],
		PassportERS	=> [16,     7],
		ExtremeXOS	=> [9,  undef],
		SecureRouter	=> [undef,  0],
		ISW		=> [undef,  8],
		Series200	=> [undef,  0],
		Wing		=> [undef,  0],
		SLX		=> [undef,  0],
		HiveOS		=> [5,  undef],
		Ipanema		=> [16, undef],
		WLAN2300	=> [undef,  0],
		WLAN9100	=> [undef,  0],
		Accelar		=> [16, undef],
);

our %DefaultCredentials = (
	Username	=> {
		PassportERS	=> 'rwa',
		ExtremeXOS	=> 'admin',
		ISW		=> 'admin',
		Series200	=> 'admin',
		Wing		=> 'admin',
		SLX		=> 'admin',
		HiveOS		=> 'admin',
		IPanema		=> 'ipanema',
		SecureRouter	=> 'admin',
		WLAN2300	=> 'admin',
		fallback	=> 'rwa',
	},
	Password	=> {
		PassportERS	=> 'rwa',
		ExtremeXOS	=> '',
		ISW		=> '',
		Series200	=> '',
		Wing		=> 'admin123',
		SLX		=> 'password',
		HiveOS		=> 'aerohive',
		IPanema		=> 'ipanema',
		SecureRouter	=> 'setup',
		WLAN2300	=> 'admin',
		fallback	=> 'rwa',
	},
);

our %PseudoSelectionAttributes = ( # These are the pseudo switch-type selections
	voss	=> {
		family_type	=> 'PassportERS',
		is_acli		=> 1,
		is_voss		=> 1,
		is_master_cpu	=> 1,
		is_dual_cpu	=> 0,
		cpu_slot	=> 1,
		is_ha		=> 0,
	},
	xos	=> {
		family_type	=> 'ExtremeXOS',
		is_acli		=> 0,
		is_xos		=> 1,
	},
	boss	=> {
		family_type	=> 'BaystackERS',
		is_acli		=> 1,
	},
	slx	=> {
		family_type	=> 'SLX',
		is_acli		=> 1,
		is_slx		=> 1,
	},
);


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
