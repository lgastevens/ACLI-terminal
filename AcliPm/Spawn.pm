# ACLI sub-module
package AcliPm::Spawn;
our $Version = "1.01";

use strict;
use warnings;
use Exporter 'import';
BEGIN { # https://www.perlmonks.org/?node_id=322823
	our @EXPORT = qw(readAcliSpawnFile launchNewTerm);
}
use FindBin;

if ($^O eq "MSWin32") {
	# This is for being able to spawn (@launch) a new instance of this terminal
	unless (eval "require Win32::Process") { die "Cannot find module Win32::Process" }
	Win32::Process->import ( 'NORMAL_PRIORITY_CLASS' );
}

use lib $FindBin::Bin.$::Sub;
use AcliPm::GlobalDefaults;
use AcliPm::DebugMessage;
use AcliPm::Print;


sub readAcliSpawnFile { # Reads in acli.spawn file with command to execute based on local OS
	my $db = shift;
	my $spawnFile;

	foreach my $path (@AcliFilePath) {
		if (-e "$path/$AcliSpawnFile") {
			$spawnFile = "$path/$AcliSpawnFile";
			last;
		}
	}
	unless (defined $spawnFile) {
		cmdMessage($db, "Unable to locate ACLI spawn file $AcliSpawnFile");
		return;
	}
	open(SPAWN, '<', $spawnFile) or do {
		cmdMessage($db, "Unable to open ACLI spawn file " . File::Spec->canonpath($spawnFile));
		return;
	};

	my $lineNumber = 0;
	my %execTemplate;
	while (<SPAWN>) {
		chomp;
		$lineNumber++;
		next if /^\s*$/; # skip empty lines
		next if /^\s*#/; # skip comment lines
		next unless s/^(\S+)\s+//; # Grab 1st word (OS)
		next unless $1 eq $^O;
		debugMsg(1,"ACLI.SPAWN: Entry for OS $^O found in line ", \$lineNumber, "\n");
		%execTemplate = (timer1 => 0, timer2 => 0);
		s/^(?:(\d{1,4}):)?(\d{1,4})\s+// && do {
			$execTemplate{timer1} = defined $1 ? $1 : $2;
			$execTemplate{timer2} = $2;
			debugMsg(1,"ACLI.SPAWN: Timer1 = ", \$execTemplate{timer1}, " / Timer2 = $execTemplate{timer2}\n");
		};
		next unless s/^(\S+)\s+//; # Grab 2nd word (executable)
		$execTemplate{executable} = $1;
		$execTemplate{arguments} = $_;
		debugMsg(1,"ACLI.SPAWN: Executable = ", \$execTemplate{executable}, "\n");
		debugMsg(1,"ACLI.SPAWN: Arguments = ", \$execTemplate{arguments}, "\n");
	}
	close SPAWN;
	unless (defined $execTemplate{executable} && defined $execTemplate{arguments}) {
		print "Error: Unable to extract $^O executable + arguments from ACLI spawn file ", File::Spec->canonpath($AcliSpawnFile), "\n";
		return;
	}
	return \%execTemplate;
}


sub substituteExecArgs { # Substitutes values into the arguments template obtained from acli.spawn file for the OS at hand
	my ($template, $windowName, $instanceName, $tabName, $cwd, $acliProfile, $acliPath, $acliPlPath, $acliArgs) = @_;

	# Replace values
	$template =~ s/<WINDOW-NAME>/$windowName/g if defined $windowName;
	$template =~ s/<INSTANCE-NAME>/$instanceName/g if defined $instanceName;
	$template =~ s/<TAB-NAME>/$tabName/g if defined $tabName;
	$template =~ s/<CWD>/$cwd/g if defined $cwd;
	$template =~ s/<ACLI-PROFILE>/$acliProfile/g if defined $acliProfile;
	$template =~ s/<ACLI-PATH>/$acliPath/g if defined $acliPath;
	$template =~ s/<ACLI-PL-PATH>/$acliPlPath/g if defined $acliPlPath;
	$template =~ s/<ACLI-ARGS>/$acliArgs/g if defined $acliArgs;

	# Remove unused value markers
	$template =~ s/(?:-[a-z]|--\w[\w-]+)(?:\s+|=)\"<[A-Z-]+>\"\s*//g;	# Double quoted with preceding -switch
	$template =~ s/(?:-[a-z]|--\w[\w-]+)(?:\s+|=)\'<[A-Z-]+>\'\s*//g;	# Single quoted with preceding -switch
	$template =~ s/(?:-[a-z]|--\w[\w-]+)(?:\s+|=)<[A-Z-]+>\s*//g;		# Non quoted with preceding -switch
	$template =~ s/\"<[A-Z-]+>\"\s*//g;					# Double quoted with no preceding -switch
	$template =~ s/\'<[A-Z-]+>\'\s*//g;					# Single quoted with no preceding -switch
	$template =~ s/<[A-Z-]+>\s*//g;						# Non quoted with no preceding -switch

	return $template;
}


sub launchNewTerm { # Spawn a new independant ACLI terminal; use Win32/Process instead of exec to avoid annoying DOS box
	my ($execTemplate, $acliArgs, $windowTitle, $tabName, $workDir) = @_;
	my $containingWindow = length $windowTitle ? $windowTitle : $ConsoleWinTitle;

	my $executeArgs = substituteExecArgs( # Substitutes values into the executable arguments template
		$execTemplate->{arguments},	# Template
		$containingWindow,		# <WINDOW-NAME>
		$containingWindow,		# <INSTANCE-NAME>
		$tabName,			# <TAB-NAME>
		$workDir, 			# <CWD>
		$ConsoleAcliProfile,		# <ACLI-PROFILE>
		$ScriptDir . 'acli',		# <ACLI-PATH>
		$ScriptDir . 'acli.pl',		# <ACLI-PL-PATH>
		$acliArgs,			# <ACLI-ARGS>
	);
	debugMsg(1,"launchNewTerm / execuatable = ", \$execTemplate->{executable}, "\n");
	debugMsg(1,"launchNewTerm / arguments = ", \$executeArgs, "\n");

	if ($^O eq "MSWin32") { # Windows
		my $processObj;
		(my $executable = $execTemplate->{executable}) =~ s/\%([^\%]+)\%/defined $ENV{$1} ? $ENV{$1} : $1/ge;
		debugMsg(1,"launchNewTerm / execuatable after resolving %ENV = ", \$executable, "\n");
		Win32::Process::Create($processObj, $executable, $executeArgs, 0, &NORMAL_PRIORITY_CLASS, $workDir) or return;
		return $processObj;
	}
	else { # Any other OS (MAC-OS and Linux...)
		my $executable = join(' ', $execTemplate->{executable}, $executeArgs);
		debugMsg(1,"launchNewTerm / execuatable after joining = ", \$executable, "\n");
		return system($executable) == 0 ? 1 : 0;
	}
}

1;
