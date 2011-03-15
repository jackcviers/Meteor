#!/usr/bin/perl -w
###############################################################################
#   Meteor
#   An HTTP server for the 2.0 web
#   Copyright (c) 2006 contributing authors
#
#   Subscriber.pm
#
#	Description:
#	Convenience interface to syslog
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

package Meteor::Syslog;
###############################################################################

	use strict;
	use Sys::Syslog;
	use IO::File;

###############################################################################
# Configuration
###############################################################################

	$Meteor::Syslog::DEFAULT_FACILITY='daemon';

	$Meteor::Syslog::_lasttimestamp=0;
	$Meteor::Syslog::_lasttimestring="";
	$Meteor::Syslog::_open=0;		# set to 1 by _open
	$Meteor::Syslog::_logFileHandle = 0;
	
###############################################################################
# Implementation
###############################################################################
sub ::syslog {

	if ($Meteor::Syslog::_logFileHandle eq 0) 
	{
		$Meteor::Syslog::_default_filename=$::CONF{'LogFilename'} || "/dev/stdout";
		$Meteor::Syslog::_logFileHandle = &createLogFileHandle($Meteor::Syslog::_default_filename);
	}

	my $debug=$::CONF{'Debug'};

	my $priority=shift;
	return if($priority eq 'debug' && !$debug); 

	my $format=shift;
	my @args=@_;
	
	if($format eq '')
	{
		my $txt=join("\t",@args);
		$format='%s';
		@args=($txt);
	}
	
	my $facility=$::CONF{'SyslogFacility'} || $Meteor::Syslog::DEFAULT_FACILITY;
	
	if($debug || $facility eq 'none')
	{
		$format=~s/\%m/$!/g;
				
		my $time = time;
		if ($::CONF{'LogTimeFormat'} ne 'unix') {
			if ($Meteor::Syslog::_lasttimestamp != time) {
				$Meteor::Syslog::_lasttimestring = localtime(time);
				$Meteor::Syslog::_lasttimestamp = time;
			}
			$time = $Meteor::Syslog::_lasttimestring;
		}

		$Meteor::Syslog::_logFileHandle->print("$time\t$priority\t");
		$Meteor::Syslog::_logFileHandle->print(sprintf($format,@args));
		$Meteor::Syslog::_logFileHandle->print("\n") if (substr($format,-1) ne "\n");
		
		return;
	}
	
	unless($Meteor::Syslog::_open)
	{
		my $facility=$::CONF{'SyslogFacility'} || $Meteor::Syslog::DEFAULT_FACILITY;
		openlog($::PGM,0,$facility);
		$Meteor::Syslog::_open=1;
	}
	
	syslog($priority,$format,@args);
}

sub myWarn {
	local $SIG{'__DIE__'}='';
	local $SIG{'__WARN__'}='';
	
	&::syslog('warning',$_[0]);
}

sub myDie {
	local $SIG{'__DIE__'}='';
	local $SIG{'__WARN__'}='';
		
	my $inEval=0;
	my $i=0;
	my $sub;
	while((undef,undef,undef,$sub)=caller(++$i))
	{
		$inEval=1, last if $sub eq '(eval)';
	}
	
	unless($inEval)
	{
		&::syslog('err',$_[0]);
		$Meteor::Socket::NO_WARN_ON_CLOSE=1;
		exit;
	}
}

sub createLogFileHandle {
	my $fn = shift;
	my $fh = new IO::File($fn,"a") or die "Could not open $fn \n"; 
	return $fh;
}

sub cycleLogFileHandle{
	$Meteor::Syslog::_logFileHandle->print("Cycling Filehandle\n");
	$Meteor::Syslog::_logFileHandle->close();
	$Meteor::Syslog::_default_filename=$::CONF{'LogFilename'} || "/dev/stdout";
	$Meteor::Syslog::_logFileHandle->open($Meteor::Syslog::_default_filename,"a");
	return 0 if $Meteor::Syslog::_logFileHandle;
}

1;
############################################################################EOF
