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
	our $NumAcceptedConnections=0;

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
	
	$::Statistics->{'current_subscribers'}++;
	$::Statistics->{'subscriber_connections_accepted'}++;
	
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
	
	map { $_->write($msg.chr(0)) } @cons;
}

sub checkPersistentConnectionsForMaxTime {
	my $class=shift;
	
	my $time=time;
	my @cons=values %PersistentConnections;
	
	map { $_->checkForMaxTime($time) } @cons;
}

sub numSubscribers {
	
	return scalar(keys %PersistentConnections);
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
		# GET $::CONF{'SubscriberDynamicPageAddress'}/hostid/streamtype/channeldefs HTTP/1.1
		#
		# Find the 'GET' line
		#
		if($self->{'headerBuffer'}=~/GET\s+$::CONF{'SubscriberDynamicPageAddress'}\/([0-9a-z]+)\/([0-9a-z]+)\/(\S+)/i)
		{
			my $subscriberID=$1;
			my $persist=0;
			$self->{'mode'}=$2;
			if ($self->{'mode'} eq "xhrinteractive" || $self->{'mode'} eq "iframe" || $self->{'mode'} eq "serversent" || $self->{'mode'} eq "longpoll") {
				$persist=1;
				$self->{'MaxMessageCount'}=1 unless(!($self->{'mode'} eq "longpoll"));
			}
			if ($self->{'mode'} eq "iframe") {
				$self->{'HeaderTemplateNumber'}=1;
			} else {
				$self->{'HeaderTemplateNumber'}=2;
			}
			my @channelData=split('/',$3);
			my $channels={};
			my $channelName;
			my $offset;
			foreach my $chandef (@channelData) {
				if($chandef=~/^([a-z0-9]+)(.(r|b|h)([0-9]*))?$/i) {
					$channelName = $1;
					$channels->{$channelName}->{'startIndex'} = undef;
					if ($3) {
					   $offset = $4;
					   if ($3 eq 'r') { $channels->{$channelName}->{'startIndex'} = $offset; }
					   if ($3 eq 'b') { $channels->{$channelName}->{'startIndex'} = -$offset; }
					   if ($3 eq 'h') { $channels->{$channelName}->{'startIndex'} = 0; }
					}
				}
			}
			
			delete($self->{'headerBuffer'});
			
			if($persist)
			{
				$self->{'subscriberID'}=$subscriberID;
				$self->deleteSubscriberWithID($subscriberID);
				$PersistentConnections{$subscriberID}=$self;
			}
			
			if(scalar(keys %{$channels}))
			{
				$self->emitOKHeader();
				$self->setChannels($channels,$persist);
				$self->close(1) unless($persist);
				return;
			}
		}
		elsif($self->{'headerBuffer'}=~/GET\s+\/disconnect\/(\S+)/)
		{
			$self->deleteSubscriberWithID($1);
			$self->emitOKHeader();
			$self->close(1);
			return;
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

sub setChannels {
	my $self=shift;
	my $channels=shift;
	my $persist=shift;
	
	foreach my $channelName (keys %{$channels})
	{
		my $startIndex=$channels->{$channelName}->{'startIndex'};
		
		my $channel=Meteor::Channel->channelWithName($channelName);
		
		$self->{'channels'}->{$channelName}=$channel if($persist);
		
		$channel->addSubscriber($self,$startIndex,$persist);
	}
}

sub emitOKHeader {
	my $self=shift;
	
	$self->emitHeader('200 OK');
}

sub emitErrorHeader {
	my $self=shift;
	
	$self->emitHeader('404 Not Found');
	$::Statistics->{'errors_served'}++;
	
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
	
	$self->write($header.chr(0));
}

sub sendMessage {
	my $self=shift;
	my $msg=shift;
	my $numMsgInThisBatch=shift;
	
	$numMsgInThisBatch=1 unless(defined($numMsgInThisBatch));
	
	$self->write($msg.chr(0));
	
	$::Statistics->{'messages_served'}+=$numMsgInThisBatch;
	
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

sub closeChannel {
	my $self=shift;
	my $channelName=shift;
	
	return unless(exists($self->{'channels'}->{$channelName}));
	
	my $channel=$self->{'channels'}->{$channelName};
	$channel->removeSubscriber($self);
	
	delete($self->{'channels'}->{$channelName});
	
	$self->close() if(scalar(keys %{$self->{'channels'}})==0);
}

sub close {
	my $self=shift;
	my $noShutdownMsg=shift;
	
	foreach my $channelName (keys %{$self->{'channels'}})
	{
		my $channel=$self->{'channels'}->{$channelName};
		$channel->removeSubscriber($self);
	}
	delete($self->{'channels'});
	
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
	
	$::Statistics->{'current_subscribers'}--;
	
	$self->SUPER::close();
}

sub checkForMaxTime {
	my $self=shift;
	my $time=shift;
	
	$self->close(1) if(exists($self->{'ConnectionTimeLimit'}) && $self->{'ConnectionTimeLimit'}<$time);
}

1;
############################################################################EOF