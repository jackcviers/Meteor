#!/usr/bin/perl -w
###############################################################################
#   Meteor
#   An HTTP server for the 2.0 web
#   Copyright (c) 2006 contributing authors
#
#   Subscriber.pm
#
#	Description:
#	A Meteor Channel
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

package Meteor::Channel;
###############################################################################
# Configuration
###############################################################################
	
	use strict;
	
	use Meteor::Message;
	
	our %Channels=();
	our $MessageID=0;

###############################################################################
# Class methods
###############################################################################
sub channelWithName {
	my $class=shift;
	my $channelName=shift;
	my $avoidCreation=shift;
	
	unless(exists($Channels{$channelName}))
	{
		return undef if($avoidCreation);
		#
		# Create new channel
		#
		$Channels{$channelName}=$class->newChannel($channelName);
		
		&::syslog('debug',"New channel $channelName");
	}
	
	return $Channels{$channelName};
}

sub listChannels {
	my $class=shift;
	
	my $list='';
	foreach my $channelName (sort keys %Channels)
	{
		my $channel=$Channels{$channelName};
		
		$list.=$channelName.'('.$channel->messageCount().'/'.$channel->subscriberCount().")$::CRLF";
	}
	
	$list;
}

sub deleteChannel {
	my $class=shift;
	my $channelName=shift;
	
	delete($Channels{$channelName});
}

sub trimMessageStoresByTimestamp {
	my $class=shift;
	my $minTimeStamp=shift;
	
	return unless($minTimeStamp);
	
	map { $_->trimMessageStoreByTimestamp($minTimeStamp) } (values %Channels);
}

sub clearAllBuffers {
	my $class=shift;
	
	map { $_->clearBuffer() } (values %Channels);
}

###############################################################################
# Factory methods
###############################################################################
sub new {
	#
	# Create a new empty instance
	#
	my $class=shift;
	
	my $obj={};
	
	bless($obj,$class);
}
	
sub newChannel {
	#
	# new instance from new server connection
	#
	my $self=shift->new();
	
	my $name=shift;
	$self->{'name'}=$name;
	
	$self->{'subscribers'}=[];
	$self->{'messages'}=[];
	
	$self;
}

sub DESTROY {
	my $self=shift;
	
	my @subscribers=@{$self->{'subscribers'}};
	map { $_->close() } @subscribers;
}

###############################################################################
# Instance methods
###############################################################################
sub name {
	shift->{'name'};
}

sub addSubscriber {
	my $self=shift;
	my $subscriber=shift;
	my $startId=shift;
	my $persist=shift;
	
	# Note: negative $startId means go back that many messages
	
	push(@{$self->{'subscribers'}},$subscriber) if($persist);
	
	my $startIndex=$self->indexForMessageID($startId);
	return unless(defined($startIndex));
	
	my $msgCount=scalar(@{$self->{'messages'}});
	my $txt='';
	
	$startIndex=0 if($startIndex<0);
	
	while($startIndex<$msgCount)
	{
		my $message=$self->{'messages'}->[$startIndex++];
		
		$txt.=$message->message();
	}
	
	$subscriber->sendMessage($txt);
}

sub removeSubscriber {
	my $self=shift;
	my $subscriber=shift;
	
	my $idx=undef;
	for(my $i=0;$i<scalar(@{$self->{'subscribers'}});$i++)
	{
		if($self->{'subscribers'}->[$i]==$subscriber)
		{
			$idx=$i;
			last;
		}
	}
	
	if(defined($idx))
	{
		splice(@{$self->{'subscribers'}},$idx,1);
	}
	
	$self->checkExpiration();
}

sub subscriberCount {
	my $self=shift;
	
	scalar(@{$self->{'subscribers'}});
}

sub addMessage {
	my $self=shift;
	my $messageText=shift;
	
	my $message=Meteor::Message->newWithID($MessageID++);
	$message->setText($messageText);	
	push(@{$self->{'messages'}},$message);
	
	$self->trimMessageStoreBySize();
	
	my $text=$message->message();
	map { $_->sendMessage($text) } @{$self->{'subscribers'}};
}

sub messageCount {
	my $self=shift;
	
	scalar(@{$self->{'messages'}});
}

sub trimMessageStoreBySize {
	my $self=shift;
	
	my $numMessages=scalar(@{$self->{'messages'}});
	
	if($numMessages>$::CONF{'MaxMessagesPerChannel'})
	{
		splice(@{$self->{'messages'}},0,-$::CONF{'MaxMessagesPerChannel'});
	}
}

sub trimMessageStoreByTimestamp {
	my $self=shift;
	my $ts=shift;
	
	while(scalar(@{$self->{'messages'}})>0 && $self->{'messages'}->[0]->timestamp()<$ts)
	{
		my $msg=shift(@{$self->{'messages'}});
	}
	
	$self->checkExpiration();
}

sub clearBuffer {
	my $self=shift;
	
	$self->{'messages'}=[];
	
	$self->checkExpiration();
}

sub checkExpiration {
	my $self=shift;
	
	if($self->messageCount()==0 && $self->subscriberCount()==0)
	{
		my $name=$self->name();
		&::syslog('debug',"Channel expired: $name");
		$self->deleteChannel($name);
	}
}

sub indexForMessageID {
	my $self=shift;
	my $id=shift;
	
	# the messages is always sorted by ID, so we can
	# use a binary search to find the message.
	# return undef if there are no messages or the
	# ID is that of the last message.
	# Otherwise return the ID of the found message
	# of if no message with that ID exists the one
	# with the next higher ID
	#
	return undef unless(defined($id));
	
	my $numMessages=scalar(scalar(@{$self->{'messages'}}));
	
	return undef unless($numMessages);
	return -1 unless($id ne '');
	
	# Note: negative $id means go back that many messages
	return $numMessages+$id if($id<0);
	
	my $low=0;
	my $high=$numMessages-1;
	my $mid;
	my $cond;
	while($low<=$high)
	{
		$mid=($low+$high)>>1;
		$cond=$id <=> $self->{'messages'}->[$mid]->id();
		if($cond<0)
		{
			$high=$mid-1;
		}
		elsif($cond>0)
		{
			$low=$mid+1;
		}
		else
		{
			return $mid;
		}
	}
	
	return undef if($low>=$numMessages);
	
	return $low;
}

1;
############################################################################EOF