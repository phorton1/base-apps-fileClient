#!/usr/bin/perl
#-------------------------------------------------------------
# fileClientResources.pm
#-------------------------------------------------------------
# All appBase applications may provide resources that contain the
# app_title, main_menu, command_data, notebook_data, and so on.
# Derived classes should merge their values into the base
# class $resources member.

package apps::fileClient::Resources;
use strict;
use warnings;
use threads;
use threads::shared;
use Pub::WX::Resources;

BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = ( qw(

		$COMMAND_PREFS
		$COMMAND_CONNECT
		$ID_CLIENT_WINDOW

		$COMMAND_CHOWN
		$COMMAND_CHMOD
        $COMMAND_XFER
        $COMMAND_DELETE
        $COMMAND_RENAME
        $COMMAND_REFRESH
        $COMMAND_MKDIR
        $COMMAND_RECONNECT
        $COMMAND_DISCONNECT
	),
	@Pub::WX::Resources::EXPORT );
}


# derived class decides if wants viewNotebook
# commands added to the view menu, by setting
# the 'command_id' member on the notebook info.

our (
	$COMMAND_PREFS,
	$COMMAND_CONNECT,

	$ID_CLIENT_WINDOW,

	$COMMAND_CHOWN,
	$COMMAND_CHMOD,
    $COMMAND_XFER,
    $COMMAND_DELETE,
    $COMMAND_RENAME,
    $COMMAND_MKDIR,
    $COMMAND_REFRESH,
    $COMMAND_RECONNECT,
	$COMMAND_DISCONNECT )= (10000..11000);


# Command data for this application.
# Notice the merging that takes place

my %command_data = (%{$resources->{command_data}},

	# app commands

	$COMMAND_PREFS 		=> ['Preferences', 'Edit global Preferences' ],
	$COMMAND_CONNECT 	=> ['Connect', 'Connect to a Host' ],

	# context menu commands

	$COMMAND_CHOWN		=> ['Owner',	'chown on files and directories' ],
	$COMMAND_CHMOD		=> ['Mode',		'chmod on files and directories' ],
    $COMMAND_XFER       => ['Transfer', 'Upload/Download file/directories'],
    $COMMAND_DELETE     => ['Delete',   'Delete files/directories'],
    $COMMAND_RENAME     => ['Rename',   'Rename files/directories'],
    $COMMAND_REFRESH    => ['Refresh',  'Refresh the contents of this pane'],
    $COMMAND_MKDIR      => ['New Folder','Create a new folder'],
    $COMMAND_RECONNECT  => ['Reconnect',  'Connect to the server'],
    $COMMAND_DISCONNECT => ['Disconnect','Disconnect from the server'],
);


#-------------------------------------
# Menus
#-------------------------------------

my @main_menu = ('view_menu,&View' );

unshift @{$resources->{view_menu}},$ID_SEPARATOR;
unshift @{$resources->{view_menu}},$COMMAND_PREFS;
unshift @{$resources->{view_menu}},$COMMAND_CONNECT;


my @win_context_menu = (
    $COMMAND_XFER,
       $ID_SEPARATOR,
    $COMMAND_DELETE,
    $COMMAND_RENAME,
       $ID_SEPARATOR,
    $COMMAND_REFRESH,
       $ID_SEPARATOR,
    $COMMAND_MKDIR,
       $ID_SEPARATOR,
    $COMMAND_RECONNECT,
    $COMMAND_DISCONNECT,
);

my @unix_context_menu = (
    $COMMAND_XFER,
       $ID_SEPARATOR,
    $COMMAND_DELETE,
    $COMMAND_RENAME,
	$COMMAND_CHMOD,
	$COMMAND_CHOWN,
       $ID_SEPARATOR,
    $COMMAND_REFRESH,
       $ID_SEPARATOR,
    $COMMAND_MKDIR,
       $ID_SEPARATOR,
    $COMMAND_RECONNECT,
    $COMMAND_DISCONNECT,
);


#-----------------------------------------
# Merge and reset the single public object
#-----------------------------------------

$resources = { %$resources,
    app_title => 'fileCllient',
    main_menu => \@main_menu,
    command_data => \%command_data,
    win_context_menu => \@win_context_menu,
    unix_context_menu => \@unix_context_menu,
};


1;
