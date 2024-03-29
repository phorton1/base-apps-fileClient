#---------------------------------------
# apps::fileClient::fcPrefs
#---------------------------------------
# Note that this is entirely different than Pub::Prefs

package apps::fileClient::fcPrefs;
use strict;
use warnings;
use threads;
use threads::shared;
use Pub::Utils;
use Pub::WX::Dialogs;


my $dbg_prefs = -1;
	# 0 = initFCPrefs and savePrefs calls
	# -1 = read/write details
my $dbg_sem = 1;
	#  0 = show initial create/open
	# -1 = show wait and release details

our $fc_prefs_filename;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = (

		'$fc_prefs_filename',		# set at top of fileClient.pm
		'getFCPref',				# returns a unary preference with no checking

		'initFCPrefs',			# called near top of fileClient.pm AppFrame::onInit()

		'parseCommandLine',
			# called from fileClient.pm AppFrame::onInit()
			# internally calls waitFCPrefs() and releaseFCPrefs()
			# parses command line and returns populated Connection
			# 	if such is specified on command line

		'waitFCPrefs',			# called before connection loop in fileClient.pm and at top of ConnectionDialog and PrefsDialog
		'getFCPrefs',				# called for connection loop and by ConnectionDialog and PrefsDialog
		'releaseFCPrefs',			# called after connection loop in fileClient.pm and at bottom of ConnectionDialog and PrefsDialog
		'writeFCPrefs',			# called by PrefsDialog or ConnectionDialog if prefs changed

		'getEffectiveDir',		# resolves the dir for Connecton Params
		'getPrefConnection',	# returns a non-shared copy of Connection by ID
		'defaultConnection',	# returns empty Connection
    );
};


my $PREFS_MUTEX_NAME =  'fileClientPrefsMutex';
	# set to '' to turn feature off
my $PREFS_SEM;

# The ONLY reason prefs need to be shared is for
# the date-time check to read them from another thread.
# In the app, they are always used from the main thread.

my $prefs_dt:shared;
my $default_prefs = {
	restore_startup 	=> 0,
	default_local_dir 	=> "/",
	default_remote_dir 	=> "/",
	ssl_cert_file		=> '',
	ssl_key_file		=> '',
	ssl_ca_file			=> '',
	debug_ssl			=> '',
	connections		 	=> shared_clone([]),
	connectionById 		=> shared_clone({}),
};

my $prefs:shared = shared_clone($default_prefs);


my @header_fields = qw(
	restore_startup
    default_local_dir
    default_remote_dir
	ssl_cert_file
	ssl_key_file
	ssl_ca_file
	debug_ssl );

my @connection_fields = qw(
	connection_id
	auto_start );

my @param_fields = qw(
	dir
	port
	host
	ssl );


#----------------------------------------------------
# Mutex
#----------------------------------------------------

sub startPrefSemaphore
{
	my ($dbg_level) = @_;
	return if !$PREFS_MUTEX_NAME;
	$PREFS_SEM = Win32::Mutex->new(0,$PREFS_MUTEX_NAME);
	if ($PREFS_SEM)
	{
		display($dbg_sem+$dbg_level,0,"MUTEX ".($^E?"OPENED":"CREATED"));
	}
	else
	{
		error("Could not OPEN or CREATE $PREFS_MUTEX_NAME SEMAPHORE");
	}
}


sub waitFCPrefs
{
	return if !$PREFS_MUTEX_NAME;
	startPrefSemaphore(0) if !$PREFS_SEM;
		# start the semaphore on the first call

	my $rslt = $PREFS_SEM->wait(1000);
	if (!defined($rslt))
	{
		# forks/threads apparently close the semaphore.
		# we detect that with !defined($rslt) and restart it

		display($dbg_sem+1,0,"restarting PREFS_SEM");
		startPrefSemaphore(1);
		$rslt = $PREFS_SEM->wait(1000);
		display($dbg_sem+1,0,"restarted PREFS_SEM got "._def($rslt));
	}

	if (!$rslt)
	{
		my $continue = yesNoDialog(undef,
			"Another process has opened $fc_prefs_filename.\n".
			"Do you wish to continue waiting (indefinitely)??\n\n".
			"Pressing 'No' will abandon this process.",
			"$fc_prefs_filename locked");
		$rslt = $PREFS_SEM->wait() if $continue;
	}
	display($dbg_sem+1,0,"waitFCPrefs()="._def($rslt));
	return $rslt;
}


sub releaseFCPrefs
{
	return if !$PREFS_MUTEX_NAME;
	my $rslt = $PREFS_SEM->release();
	display($dbg_sem+1,0,"releaseFCPrefs()="._def($rslt));
	return $rslt;
}



#----------------------------------------------------
# Client API
#----------------------------------------------------

sub getFCPrefs
{
	return $prefs;
}


sub getFCPref
	# should only be used for unary prefs
{
	my ($id) = @_;
	return defined($prefs->{$id}) ?
		$prefs->{$id} : '';
}


sub getEffectiveDir
{
	my ($params) = @_;
	my $dir = $params->{dir};
	$dir ||= $params->{port} ?
		$prefs->{default_remote_dir} :
		$prefs->{default_local_dir};
	$dir ||= '/';
	return $dir;
}


sub defaultParams
{
	my $retval = {
		dir => '',
		host => '',
		port => '',
		ssl  => '' };
	return $retval;
}


sub defaultConnection
{
	my $retval = {
		connection_id => '',
		auto_start => 0,
		params => [
			defaultParams(),
			defaultParams() ] };
	return $retval;
}


sub getPrefConnection
{
	my ($connection_id) = @_;
	my $retval = defaultConnection();
	if ($connection_id)
	{
		my $connection = $prefs->{connectionById}->{$connection_id};
		if (!$connection)
		{
			error("Could not find Connection($connection)");
			return '';
		}
		$retval->{connection_id} = $connection->{connection_id};
		$retval->{auto_start} = $connection->{auto_start};
		mergeHash($retval->{params}->[0],$connection->{params}->[0]);
		mergeHash($retval->{params}->[1],$connection->{params}->[1]);
	}
	return $retval;
}



#---------------------------------------------
# parseCommandLine()
#---------------------------------------------

sub argError
{
	my ($msg) = @_;
	error($msg);
	releaseFCPrefs();
	return 0;
}


sub argOK
{
	my ($connection,$what,$psession_num,$got_arg,$lval,$rval) = @_;
	if ($got_arg->{$lval})
	{
		$$psession_num++;
		display($dbg_prefs+1,0,"ADVANCE PANE_NUM($$psession_num)");
	}
	return argError("Too many command line parameters '$lval'")
		if $$psession_num > 1;
	$got_arg->{$lval} = 1;
	$connection->{sessions}->[$$psession_num]->{$what} = $rval;
	return $connection->{sessions}->[$$psession_num];
}


sub parseCommandLine
	# Cannot currently invoke SSL from command line, except by
	# using existing named connections.
	#
	# returns undef if could not waitFCPrefs()
	# returns 0 if there's no command line, or an error was reported
	# returns a $connection on success.
{
	return 0 if !@ARGV;
	return undef if !waitFCPrefs();

	my $retval = defaultConnection();

	my $i = 0;
	my %got_arg;
	my $session_num = 0;
	while ($i<@ARGV)
	{
		my $lval = $ARGV[$i++];
		my $rval = $ARGV[$i++];
		return argError("invalid command line: "._def($lval)." = '"._def($rval)."'")
			if !$lval || !defined($rval);

		if ($lval eq '-buddy')
		{
			$retval->{connection_id} = 'buddy';
			$retval->{params}->[1]->{port} = $rval
		}
		elsif ($lval eq '-c')
		{
			if ($rval ne 'local')
			{
				$retval = getPrefConnection($rval);
				return 0 if !$retval;
			}
		}
		elsif ($lval eq '-cid')
		{
			$retval->{connection_id} = $rval;
		}
		elsif ($lval eq '-d')
		{
			if ($rval !~ /^\//)
			{
				warning($dbg_prefs+1,0,"fixing relative dir '$rval'");
				$rval = '/'.$rval;
			}
			return if !argOK($retval,'dir',\$session_num,\%got_arg,$lval,$rval);
		}
		elsif ($lval eq '-h')
		{
			my $session = argOK($retval,'host',\$session_num,\%got_arg,$lval,$rval);
			return if !$session;

			if ($session->{host} =~ s/:(.*)$//)
			{
				$session->{port} = $1;
				$got_arg{'-p'} = 1;
			}
		}
		elsif ($lval eq '-p')
		{
			return if !argOK($retval,'port',\$session_num,\%got_arg,$lval,$rval);
		}
		else
		{
			return argError("Unknown command line params: '$lval $rval'");
		}
	}
	releaseFCPrefs();
	return $retval;
}


#-----------------------------------------------------
# initFCPrefs()
#-----------------------------------------------------

# use Data::Dumper;

sub initFCPrefs()
	# returns 0 if could not waitFCPrefs()
	# returns 1 otherwise
{
	my ($multi_process) = @_;

	display($dbg_prefs,0,"init_prefs()");

	return 1 if !$fc_prefs_filename;
	return 0 if !waitFCPrefs();

	my $text = getTextFile($fc_prefs_filename);
	if ($text)
	{
		$prefs = shared_clone($default_prefs);

		my $connection;
		my $param_num = 0;
		my $thing = $prefs;
		my @lines = split(/\n/,$text);
		for my $line (@lines)
		{
			$line =~ s/^\s+|\s$//g;
			if ($line =~ /^connection$/)
			{
				display($dbg_prefs+1,1,"connection");
				$connection = shared_clone({
					params => shared_clone([
						shared_clone({}),
						shared_clone({})  ]) });
				push @{$prefs->{connections}},$connection;
				$thing = $connection;
				$param_num = 0;
			}
			elsif ($line =~ /^params$/)
			{
				display($dbg_prefs+1,2,"params($param_num)");
				$thing = $connection->{params}->[$param_num++];
			}
			elsif ($line =~ /^(.+?)\s*=\s*(.*)$/)
			{
				my ($lvalue,$rvalue) = ($1,$2);
				display($dbg_prefs+1,3,"$lvalue <= $rvalue");

				$rvalue ||= '';
				$thing->{$lvalue} = $rvalue;
				if ($lvalue eq 'connection_id')
				{
					display($dbg_prefs+1,4,"connectionById($rvalue)");
					$prefs->{connectionById}->{$rvalue} = $connection;
				}
			}
		}
	}
	else
	{
		warning($dbg_prefs,-1,"Empty or missing $fc_prefs_filename");
	}

	$prefs->{default_local_dir} ||= '/';
	$prefs->{default_remote_dir} ||= '/';

	# print Dumper($prefs);
	# writeFCPrefs();

	releaseFCPrefs();
	return 1;
}



sub writeFCPrefs
	# returns undef if could not waitFCPrefs()
	# returns 0 if it could not write the prefs file
	# reeturns 1 on success.
{
	display($dbg_prefs,0,"write_prefs()");
	return undef if !waitFCPrefs();

	my $text = '';
	for my $key (@header_fields)
	{
		$text .= "$key = $prefs->{$key}\n";
	}
	for my $connection (@{$prefs->{connections}})
	{
		$text .= "connection\n";
		for my $key (@connection_fields)
		{
			$text .= "    $key = $connection->{$key}\n";
		}
		for my $param_num (0..1)
		{
			$text .= "    params\n";
			my $params = $connection->{params}->[$param_num];
			for my $key (@param_fields)
			{
				$text .= "        $key = $params->{$key}\n";
			}
		}
	}
	if (!printVarToFile(1,$fc_prefs_filename,$text))
	{
		releaseFCPrefs();
		error("Could not write to $fc_prefs_filename");
		return 0;
	}
	releaseFCPrefs();
	return 1;

}



1;
