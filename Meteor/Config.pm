#!/usr/bin/perl -w
###############################################################################
#   Meteor
#   An HTTP server for the 2.0 web
#   Copyright (c) 2006 contributing authors
#
#   Subscriber.pm
#
#	Description:
#	Meteor Configuration handling.
#
#	Main program should call Meteor::Config::setCommandLineParameters(@ARGV),.
#	Afterwards anybody can access $::CONF{<parameterName>}, where
#	<parameterName> is any valid parameter (except 'Help') listed in the
#	@DEFAULTS array below.
#
###############################################################################
#
#   This program is free software; you can redistribute it and/or modify it
#   under the terms of the GNU General Public License as published by the Free
#   Software Foundation; either version 2 of the License, or (at your option)
#   any later version.
#
#   This program is distributed in the hope that it will be useful, but WITHOUT
#   ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
#   FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
#   more details.
#
#   You should have received a copy of the GNU General Public License along
#   with this program; if not, write to the Free Software Foundation, Inc.,
#   59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#
#   For more information visit www.meteorserver.org
#
###############################################################################

package Meteor::Config;
###############################################################################
# Configuration
###############################################################################
	
	use strict;
	
	our @DEFAULTS=(
'Configuration file location on disk (if any)',
	ConfigFileLocation		=> '/etc/meteord.conf',

'IP address for controller server (leave empty for all local addresses)',
	ControllerIP			=> '',

'Port number for controller connections',
	ControllerPort			=> 4671,

'Controller Shutdown message, sent when the controller server shuts down (leave empty for no message)',
	ControllerShutdownMsg	=> '',

'Debug Flag, when set daemon will run in foreground and emit debug messages',
	Debug					=> 0,
	
'Name of index file to serve when a directory is requested from the static file web server',
	DirectoryIndex	=> 'index.html',

'Header to be served with static documents. ~server~ and ~status~ will be replaced by the appropriate values',
	DocumentHeaderTemplate			=> 'HTTP/1.1 ~status~\r\nServer: ~server~\r\nContent-Type: text/html; charset=utf-8\r\n\r\n',

'Header template, ~server~, ~servertime~ and ~status~ will be replaced by the appropriate values.  **NOTE**: It is possible to define more than one HeaderTemplate by appending a number at the end, for example *HeaderTemplate42*. Clients can request a specific header to be used by adding the parameter template=<number> to their GET request. If *HeaderTemplate<number>* is not found, the system will use the default HeaderTemplate (no number)',
	HeaderTemplate			=> 'HTTP/1.1 ~status~\r\nServer: ~server~\r\nContent-Type: text/html; charset=utf-8\r\nPragma: no-cache\r\nCache-Control: no-cache, no-store, must-revalidate\r\nExpires: Thu, 1 Jan 1970 00:00:00 GMT\r\n\r\n<html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8">\r\n<meta http-equiv="Cache-Control" content="no-store">\r\n<meta http-equiv="Cache-Control" content="no-cache">\r\n<meta http-equiv="Pragma" content="no-cache">\r\n<meta http-equiv="Expires" content="Thu, 1 Jan 1970 00:00:00 GMT">\r\n<script type="text/javascript">\r\nwindow.onError = null;\r\nvar domainparts = document.domain.split(".");\r\ndocument.domain = domainparts[domainparts.length-2]+"."+domainparts[domainparts.length-1];\r\nparent.Meteor.register(this);\r\nparent.Meteor.setServerTime(~servertime~);\r\n</script>\r\n</head>\r\n<body onload="r()">\r\n',

'Print out this help message',
	Help					=> '',

'Maximum age of a message in seconds',
	MaxMessageAge			=> 7200,

'Maximum number of messages to send to a subscriber before forcing their connection to close. Use 0 to disable',
	MaxMessages				=> 0,

'Maximum number of stored messages per channel',
	MaxMessagesPerChannel	=> 250,

'Maximum duration in seconds for a subscriber connection to exist before forcing a it to close. Note that the server checks for expired connections in 60 second intervals, so small changes to this value will not have much of an effect. Use 0 to disable',
	MaxTime					=> 0,

'Message template, ~text~, ~id~ and ~timestamp~ will be replaced by the appropriate values',
	MessageTemplate			=> '<script>p(~id~,"~text~");</script>\r\n',

'Interval at which PingMessage is sent to all persistent and identified subscriber connections (ie those including id=someuniqueidentifier in their request, and not specifying persist=0). Must be at least 3 if set higher than zero. Set to zero to disable.',
	PingInterval			=> 5,

'Message to be sent to all persistent and identified subscriber connections (see above) every PingInterval seconds',
	PingMessage				=> '<script>p(-1,"");</script>\r\n',

'IP address for subscriber server (leave empty for all local addresses)',
	SubscriberIP			=> '',

'Port number for subscriber connections',
	SubscriberPort			=> 4670,

'Subscriber Shutdown message, sent when the subscriber server shuts down (leave empty for no message)',
	SubscriberShutdownMsg		=> '<script>eof();</script>\r\n',

'An absolute filesystem path, to be used as the document root for Meteor\'s static file web server. If left empty, no documents will be served.',
	SubscriberDocumentRoot	=> '/usr/local/meteor/public_html',

'Since Meteor is capable of serving static pages from a document root as well as streaming events to subscribers, this paramter is used to specify the URI at which the event server can be reached. If set to the root, Meteor will lose the ability to serve static pages.',
	SubscriberDynamicPageAddress	=> '/push',

'The syslog facility to use',
	SyslogFacility			=> 'daemon',
	);
	
	our %ConfigFileData=();
	our %CommandLine=();
	our %Defaults=();
	our %ExtraKeys=();
	
	for(my $i=0;$i<scalar(@DEFAULTS);$i+=3)
	{
		$Defaults{$DEFAULTS[$i+1]}=$DEFAULTS[$i+2];
	}

###############################################################################
# Class methods
###############################################################################
sub updateConfig {
	my $class=shift;
	
	%::CONF=();
	
	my $debug=$class->valueForKey('Debug');
	
	print STDERR '-'x79 ."\nParamters:\nSource \tName and Value\n".'-'x79 ."\n" if($debug);
	
	my @keys=();
	
	for(my $i=0;$i<scalar(@DEFAULTS);$i+=3)
	{
		next if($DEFAULTS[$i+1] eq 'Help');
		push(@keys,$DEFAULTS[$i+1]);
	}
	push(@keys,keys %ExtraKeys);
	
	foreach my $key (@keys)
	{		
		if(exists($CommandLine{$key}))
		{
			print STDERR "CmdLine" if($debug);
			$::CONF{$key}=$CommandLine{$key};
		}
		elsif(exists($ConfigFileData{$key}))
		{
			print STDERR "CnfFile" if($debug);
			$::CONF{$key}=$ConfigFileData{$key};
		}
		elsif(exists($Defaults{$key}))
		{
			print STDERR "Default" if($debug);
			$::CONF{$key}=$Defaults{$key};
		}
		
		print STDERR "\t$key\t$::CONF{$key}\n" if($debug);
		
		# Take care of escapes
		$::CONF{$key}=~s/\\(.)/
			if($1 eq 'r')
			{
				"\r";
			}
			elsif($1 eq 'n')
			{
				"\n";
			}
			elsif($1 eq 's')
			{
				' ';
			}
			elsif($1 eq 't')
			{
				"\t";
			}
			else
			{
				$1;
			}
		/gex;
	}
	
	print STDERR '-'x79 ."\n" if($debug);
}

sub valueForKey {
	my $class=shift;
	my $key=shift;
	
	return $CommandLine{$key} if(exists($CommandLine{$key}));
	return $ConfigFileData{$key} if(exists($ConfigFileData{$key}));
	
	$Defaults{$key};
}

sub setCommandLineParameters {
	my $class=shift;
	
	while(my $cnt=scalar(@_))
	{
		my $k=shift(@_);
		&usage("'$k' invalid") unless($k=~s/^\-(?=.+)//);
		
		$k='Debug' if($k eq 'd');
		
		my $key=undef;
		my $kl=length($k);
		my $kOrig=$k;
		$k=lc($k);
		
		for(my $i=0;$i<scalar(@DEFAULTS);$i+=3)
		{
			my $p=$DEFAULTS[$i+1];
			my $pl=length($p);
			
			next if($kl>$pl);
			
			#print "$kl $pl $k $p\n";
			
			if($kl==$pl && $k eq lc($p))
			{
				$key=$p;
				last;
			}
			
			my $ps=lc(substr($p,0,$kl));
			
			if($k eq $ps)
			{
				if(defined($key))
				{
					&usage("Ambigous parameter name '$kOrig'");
				}
				$key=$p;
			}
		}
		
		if($k=~/^HeaderTemplate(\d+)$/i)
		{
			$key="HeaderTemplate$1";
			$ExtraKeys{$key}=1;
		}
			
		&usage("Unknown parameter name '$kOrig'") unless(defined($key));
		
		&usage() if($key eq 'Help');
		
		#print "$kOrig: $key\n";
		
		$CommandLine{$key}=1;
		
		if($cnt>1 && $_[0]!~/^\-(?!\-)/)
		{
			my $param=shift;
			$param=~s/^\-\-/\-/;
			$CommandLine{$key}=$param;
		}
	}
	
	$class->readConfig();
	
	$class->updateConfig();
}

sub readConfig {
	my $class=shift;
	
	%ConfigFileData=();
	
	my $path=$class->valueForKey('ConfigFileLocation');
	return unless(defined($path) && -f $path);
	
	open(CONFIG,"$path") or &usage("Config file '$path' for read: $!\n");
	while(<CONFIG>)
	{
		next if(/^\s*#/);
		next if(/^\s*$/);
		
		s/[\r\n]*$//;
		
		unless(/^(\S+)\s*(.*)/)
		{
			&usage("Invalid configuration file parameter line '$_'");
		}
		
		my $key=$1;
		my $val=$2;
		$val='' unless(defined($val));
		
		if($key=~/^HeaderTemplate\d+$/)
		{
			$ExtraKeys{$key}=1;
		}
		else
		{
			unless(exists($Defaults{$key}))
			{
				&usage("Unknown configuration file parameter name '$key'");
			}
			if($key eq 'ConfigFileLocation')
			{
				&usage("'ConfigFileLocation' parameter not allowed in configuration file!");
			}
		}
		
		$val=~s/^--/-/;
		
		$ConfigFileData{$key}=$val;
	}
	close(CONFIG);
}

sub usage {
	my $msg=shift || '';
	
	if($msg) {
		print STDERR <<"EOT";
$msg;
For further help type $::PGM -help
or consult docs at http://www.meteorserver.org/
EOT

	} else {

	
		print STDERR <<"EOT";

Meteor server v1.0 (release date: 1 Dec 2006)
Licensed under the terms of the GNU General Public Licence (2.0)

Usage:

	$::PGM [-parameter [value] [-parameter [value]...]]

Accepted command-line parameters:

EOT
	
		for(my $i=0;$i<scalar(@DEFAULTS);$i+=3)
		{
			print STDERR "-$DEFAULTS[$i+1]\n$DEFAULTS[$i].\n\n";
		}
		
		print STDERR <<"EOT";	
	
Any of the parameters listed above can also be configured in the
configuration file. The default location for this file is:

	$Defaults{'ConfigFileLocation'}

For more information and complete documentation, see the Meteor
website at http://www.meteorserver.org/
EOT

	}
	exit(1);
}

1;
############################################################################EOF