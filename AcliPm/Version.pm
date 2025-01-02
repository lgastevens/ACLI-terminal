# ACLI sub-module
package AcliPm::Version;
our $VERSION = "6.04"; # This version is the ACLI release version

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw($VERSION versionInfo);
}
use Config;
use Control::CLI::Extreme qw(:use);
use FindBin;
use lib $FindBin::Bin.$::Sub;
use AcliPm::GlobalConstants;


sub versionInfo { # Print out all versions of Script, Perl and underlying modules
	my $all = shift;
	printf "ACLI release %s (written by Ludovico Stevens)\n", $VERSION;
	printf "%s Perl version %s %s %s\n\n", $^O, $^V,
		$Config{use64bitint} eq 'define' ? "64bit" : "32bit",
		$Config{usethreads} eq 'define' ? 'thread support' : '';
	if ($all) {
		print "ACLI module versions:\n";
		printf "	%-30s version %s\n", $ScriptName, $::Version;
		my @pmFiles = sort { $a cmp $b } grep ( -f ,<"$FindBin::Bin$::Sub/AcliPm/*.pm">);
		foreach my $file (@pmFiles) {
			(my $mod = $file) =~ s/^.*\/([^.]+)\.pm$/$1/;
			next if $mod eq 'Version';
			no strict 'refs';
			my $version = ${"AcliPm::".$mod."::Version"};
			printf "	AcliPm::%-22s version %s\n", $mod, defined $version ? $version : '<not used>';
		}
		print "\n";
	}
	print "Perl Standard Modules used by this script:\n";
	printf "	%-30s version %s\n", 'Control::CLI', $Control::CLI::VERSION;
	printf "	%-30s version %s\n", 'Control::CLI::Extreme', $Control::CLI::Extreme::VERSION;
	printf "	%-30s version %s\n", 'IO::Socket::INET', $IO::Socket::INET::VERSION;
	printf "	%-30s version %s\n", 'IO::Socket::IP', $IO::Socket::IP::VERSION;
	printf "	%-30s version %s\n", 'IO::Socket::Multicast', $IO::Socket::Multicast::VERSION;
	printf "	%-30s version %s\n", 'IO::Select', $IO::Select::VERSION;
	printf "	%-30s version %s\n", 'MIME::Base64', $MIME::Base64::VERSION;
	printf "	%-30s version %s\n", 'Net::Ping::External', $Net::Ping::External::VERSION;
	printf "	%-30s version %s\n", 'Net::SSH2', $Net::SSH2::VERSION if useSsh;
	printf "	%-30s version %s\n", 'Net::SSH2 libssh2', scalar &Net::SSH2::version if useSsh;
	printf "	%-30s version %s\n", 'Net::Telnet', $Net::Telnet::VERSION if useTelnet;
	printf "	%-30s version %s\n", 'Term::ReadKey', $Term::ReadKey::VERSION;
	printf "	%-30s version %s\n", 'Time::HiRes', $Time::HiRes::VERSION;
	if ($^O eq 'MSWin32') {
		printf "	%-30s version %s\n", 'Win32::Console', $Win32::Console::VERSION;
		printf "	%-30s version %s\n", 'Win32::Console::ANSI', $Win32::Console::ANSI::VERSION;
		printf "	%-30s version %s\n", 'Win32::Process', $Win32::Process::VERSION;
		printf "	%-30s version %s\n", 'Win32::SerialPort', $Win32::SerialPort::VERSION if useSerial;
		printf "	%-30s version %s\n", 'Win32API::CommPort', $Win32API::CommPort::VERSION;
		printf "	%-30s version %s\n", 'Win32API::File', $Win32API::File::VERSION;
	}
	else {
		printf "	%-30s version %s\n", 'Device::SerialPort', $Device::SerialPort::VERSION if useSerial;
	}
	print "\n";
}

1;
