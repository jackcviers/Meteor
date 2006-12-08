#!/usr/bin/perl -w
###############################################################################
#   Meteor
#   An HTTP server for the 2.0 web
#   Copyright (c) 2006 contributing authors
#
#   Subscriber.pm
#
#	Description:
#	A Meteor Subscriber
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

package Meteor::Subscriber;
###############################################################################
# Configuration
###############################################################################
	
	use strict;
	
	use Meteor::Connection;
	use Meteor::Channel;
	use Meteor::Document;
	
	@Meteor::Subscriber::ISA=qw(Meteor::Connection);
	
	our %PersistentConnections=();

###############################################################################
# Factory methods
###############################################################################
sub newFromServer {
	my $class=shift;
	
	my $self=$class->SUPER::newFromServer(shift);
	
	$self->{'headerBuffer'}='';
	$self->{'MessageCount'}=0;
	$self->{'MaxMessageCount'}=0;
	
	$self->{'ConnectionStart'}=time;
	my $maxTime=$::CONF{'MaxTime'};
	if($maxTime>0)
	{
		$self->{'ConnectionTimeLimit'}=$self->{'ConnectionStart'}+$maxTime;
	}
	
	$self;
}

###############################################################################
# Class methods
###############################################################################
sub deleteSubscriberWithID {
	my $class=shift;
	my $id=shift;
	
	if(exists($PersistentConnections{$id}))
	{
		$PersistentConnections{$id}->close(1);
	}
}

sub pingPersistentConnections {
	my $class=shift;
	
	my $msg=$::CONF{'PingMessage'};
	my @cons=values %PersistentConnections;
	
	map { $_->write($msg) } @cons;
}

sub checkPersistentConnectionsForMaxTime {
	my $class=shift;
	
	my $time=time;
	my @cons=values %PersistentConnections;
	
	map { $_->checkForMaxTime($time) } @cons;
}

###############################################################################
# Instance methods
###############################################################################
sub processLine {
	my $self=shift;
	my $line=shift;
	
	# Once the header was processed we ignore any input
	return unless(exists($self->{'headerBuffer'}));
	
	if($line ne '')
	{
		#
		# Accumulate header
		#
		$self->{'headerBuffer'}.="$line\n";
	}
	else
	{
		#
		# Empty line signals end of header.
		# Analyze header, register with appropiate channel
		# and send pending messages.
		#
		# GET $::CONF{'SubscriberDynamicPageAddress'}?channel=ml123&restartfrom=1 HTTP/1.1
		#
		# Find the 'GET' line
		#
		if($self->{'headerBuffer'}=~/GET\s+$::CONF{'SubscriberDynamicPageAddress'}\?(\S+)/)
		{
			my @formData=split('&',$1);
			my $channelName=undef;
			my $startIndex=undef;
			my $backtrack=undef;
			my $persist=1;
			my $subscriberID=undef;
			foreach my $formElement (@formData)
			{
				if($formElement=~/^channel=(.+)$/)
				{
					$channelName=$1;
				}
				elsif($formElement=~/^restartfrom=(\d*)$/)
				{
					$startIndex=$1;
					$startIndex='' unless(defined($startIndex));
				}
				elsif($formElement=~/^backtrack=(\d+)$/)
				{
					$backtrack=$1;
					$backtrack=0 unless(defined($backtrack));
				}
				elsif($formElement=~/^persist=(?i)(yes|true|1|no|false|0)$/)
				{
					$persist=0 if($1=~/(no|false|0)/i);
				}
				elsif($formElement=~/^id=(.+)$/)
				{
					$subscriberID=$1;
				}
				elsif($formElement=~/^maxmessages=(\d+)$/i)
				{
					$self->{'MaxMessageCount'}=$1;
				}
				elsif($formElement=~/^template=(\d+)$/i)
				{
					$self->{'HeaderTemplateNumber'}=$1;
				}
				elsif($formElement=~/^maxtime=(\d+)$/i)
				{
					my $clientRequest=$1;
					my $serverDefault=$::CONF{'MaxTime'};
					
					if($serverDefault==0 || $serverDefault>$clientRequest)
					{
						$self->{'ConnectionTimeLimit'}=$self->{'ConnectionStart'}+$clientRequest;
					}
				}
			}
						
			delete($self->{'headerBuffer'});
			
			if(defined($startIndex) && defined($backtrack))
			{
				$self->emitHeader("404 Cannot use both 'restartfrom' and 'backtrack'");
				$self->close();
				
				return;
			}
			
			if(defined($subscriberID) && $persist)
			{
				$self->{'subscriberID'}=$subscriberID;
				$self->deleteSubscriberWithID($subscriberID);
				$PersistentConnections{$subscriberID}=$self;
			}
			
			if(defined($channelName))
			{
				$self->emitOKHeader();
				
				$startIndex=-$backtrack if(!defined($startIndex) && defined($backtrack));
				
				$self->setChannelName($channelName,$startIndex,$persist);
				
				$self->close(1) unless($persist);
				
				return;
			}
		}
		elsif($self->{'headerBuffer'}=~/GET\s+([^\s\?]+)/)
		{
			Meteor::Document->serveFileToClient($1,$self);
			
			$self->close(1);
			
			return;
		}
		
		#
		# If we fall through we did not understand the request
		#
		$self->emitErrorHeader();
	}
}

sub setChannelName {
	my $self=shift;
	my $channelName=shift;
	my $startIndex=shift;
	my $persist=shift;
	
	my $channel=Meteor::Channel->channelWithName($channelName);
	$self->{'channel'}=$channel if($persist);
	
	$channel->addSubscriber($self,$startIndex,$persist);
}

sub emitOKHeader {
	my $self=shift;
	
	$self->emitHeader('200 OK');
}

sub emitErrorHeader {
	my $self=shift;
	
	$self->emitHeader('404 Not Found');
	
	# close up shop here!
	$self->close();
}

sub emitHeader {
	my $self=shift;
	my $status=shift;
	
	my $header=undef;
	if(exists($self->{'HeaderTemplateNumber'}))
	{
		my $hn='HeaderTemplate'.$self->{'HeaderTemplateNumber'};
		
		$header=$::CONF{$hn};
	}
	$header=$::CONF{'HeaderTemplate'} unless(defined($header));
	
	$header=~s/~([^~]+)~/
		if(!defined($1) || $1 eq '')
		{
			'~';
		}
		elsif($1 eq 'server')
		{
			$::PGM;
		}
		elsif($1 eq 'status')
		{
			$status;
		}
		elsif($1 eq 'servertime')
		{
			time;
		}
		else
		{
			'';
		}
	/gex;
	
	$self->write($header);
}

sub sendMessage {
	my $self=shift;
	my $msg=shift;
	
	$self->write($msg);
	
	my $msgCount=++$self->{'MessageCount'};
	
	my $maxMsg=$::CONF{'MaxMessages'};
	if(defined($maxMsg) && $maxMsg>0 && $msgCount>=$maxMsg)
	{
		$self->close(1);
	}
	
	if($self->{'MaxMessageCount'}>0 && $msgCount>=$self->{'MaxMessageCount'})
	{
		$self->close(1);
	}
}

sub close {
	my $self=shift;
	my $noShutdownMsg=shift;
	
	$self->{'channel'}->removeSubscriber($self) if($self->{'channel'});
	delete($self->{'channel'});
	
	if(exists($self->{'subscriberID'}))
	{
		delete($PersistentConnections{$self->{'subscriberID'}});
	}
	
	#
	# Send shutdown message unless remote closed or
	# connection not yet established
	#
	unless($noShutdownMsg || $self->{'remoteClosed'} || exists($self->{'headerBuffer'}))
	{
		my $msg=$::CONF{'SubscriberShutdownMsg'};
		if(defined($msg) && $msg ne '')
		{
			$self->write($msg);
		}
	}
	
	$self->SUPER::close();
}

sub checkForMaxTime {
	my $self=shift;
	my $time=shift;
	
	$self->close(1) if(exists($self->{'ConnectionTimeLimit'}) && $self->{'ConnectionTimeLimit'}<$time);
}

1;
############################################################################EOF