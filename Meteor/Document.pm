#!/usr/bin/perl -w
###############################################################################
#   Meteor
#   An HTTP server for the 2.0 web
#   Copyright (c) 2006 contributing authors
#
#   Subscriber.pm
#
#	Description:
#	Cache and serve static documents
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

package Meteor::Document;
###############################################################################
# Configuration
###############################################################################
	
	use strict;
	
	our %Documents=();

###############################################################################
# Class methods
###############################################################################
sub serveFileToClient {
	my $class=shift;
	my $relPath=shift;
	my $client=shift;

	&::syslog('debug',"Meteor::Document: Request received for '%s'",$relPath);
	
	my $doc=$class->documentForPath($relPath);
	
	unless(defined($doc))
	{
		$class->emitHeaderToClient($client,'404 Not Found');
		
		return undef;
	}
	
	$doc->serveTo($client);
	
	$doc;
}

sub emitHeaderToClient {
	my $self=shift;
	my $client=shift;
	my $status=shift;
	
	my $header=$::CONF{'DocumentHeaderTemplate'};
	
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
		else
		{
			'';
		}
	/gex;
	
	$client->write($header);
}

sub documentForPath {
	my $class=shift;
	my $relPath=shift;
	
	unless(exists($Documents{$relPath}))
	{
		my $path=$class->pathToAbsolute($relPath);
		
		return undef unless(defined($path));
		
		my $doc=$class->newDocument($path);
		
		return undef unless(defined($doc));
		
		$Documents{$relPath}=$doc;
	}
	
	$Documents{$relPath};
}

sub clearDocuments {
	%Documents=();
}

sub pathToAbsolute {
	my $class=shift;
	my $relPath=shift;
	
	# Don't serve documents unless SubscriberDocumentRoot is set 
	unless(exists($::CONF{'SubscriberDocumentRoot'})
		&& $::CONF{'SubscriberDocumentRoot'} ne ''
		&& $::CONF{'SubscriberDocumentRoot'} ne '/'
	)
	{
		return undef;
	}
	
	#
	# Verify if name is legal
	#
	# Strip leading and trailing slashes
	$relPath=~s/^[\/]*//;
	$relPath=~s/[\/]*$//;
	
	# split into path components
	my @pathComponents=split(/[\/]+/,$relPath);
	
	# Check components
	foreach (@pathComponents)
	{
		# Very strict: We only allow alphanumric characters, dash and
		# underscore, followed by any number of extensions that also
		# only allow the above characters.
		unless(/^[a-z0-9\-\_][a-z0-9\-\_\.]*$/i)
		{
			&::syslog('debug',
				"Meteor::Document: Rejecting path '%s' due to invalid component '%s'",
				$relPath,$_
			);
			
			return undef;
		}
	}
	
	my $path=$::CONF{'SubscriberDocumentRoot'}.'/'.join('/',@pathComponents);
	
	# If it is a directory, append DirectoryIndex config value
	$path.='/'.$::CONF{'DirectoryIndex'} if(-d $path);
	
	# Verify file is readable
	return undef unless(-r $path);
	
	$path;
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
	
sub newDocument {
	#
	# new instance from new server connection
	#
	my $self=shift->new();
	
	my $path=shift;
	$self->{'path'}=$path;
	
	# Read file
	{
	    local $/; # enable localized slurp mode
		open(IN,$path) or return undef;
		$self->{'document'}=<IN>;
		close(IN);
	}
	
	$self->{'size'}=length($self->{'document'});
	
	$self;
}

###############################################################################
# Instance methods
###############################################################################
sub serveTo {
	my $self=shift;
	my $client=shift;
	
	$self->emitHeaderToClient($client,'200 OK');
	
	$client->write($self->{'document'});
}

sub path {
	shift->{'path'};
}

1;
############################################################################EOF
