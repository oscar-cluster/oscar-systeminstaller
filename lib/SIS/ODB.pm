package SIS::ODB;

#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
 
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
 
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

#   $Id$
#
#   Copyright (c) Erich Focht <efocht@hpce.nec.com>
#                 All rights reserved
#

=head1 NAME

SIS::ODB - SIS Interface for client, image, and adapter objects, adapted to ODA

=head1 SYNOPSIS

  use SIS::ODB;

  my @clients = list_client();
  my $name = $clients[0]->name();
  del_client($name);
  my $newname = "test";
  $clients[0]->name($newname) or croak("Can't set name on client");
  set_client($clients[0]);

=head1 DESCRIPTION

The SIS::ODB interface gives one access to the System Installation
Suite Database.  There exists 4 functions for every object type:
exists_X, list_X, set_X, del_X.  (These will be discussed in detail
later).

=head1 ENVIRONMENTAL VARIABLES

The behavior of this module may be changed by setting certain
environmental variables before calling use.

=head1 FUNCTIONS

=over 4

=head2 exists_X

exists_X($name) - does this object exist?

returns true if the object with that name exists, false otherwise.
This is used for quick lookups to see if something is defined.  (note:
exists_adapter is different, and needs ($devname, $client) passed to
it) 

=head2 list_X

list_X([n1 => v1, ...])  - return list of objects of type X that
satisfy criteria n1 => v1.

If called with no args, it returns the list of all the objects of type
X.  With args, it will return the list of objects that satisfy the
criteria listed (like 'imagename => myimage').

If called in scalar context, and if the criteria matches only one
object, it will return the single object instead of the list.  If
called in scalar context, if the criteria matches multiple objects,
the function will return 'undef'.

=head2 set_X

set_X($object1[, $object2...]) - store objects of type X.

=head2 del_X

del_X($primkey) - detele object of type X by key using $primkey as the
value.

=back

=head1 AUTHORS

  Copyright 2006 Erich Focht <efocht at hpce dot nec dot de>

=cut

use strict;
use Carp;
use Data::Dumper;
use lib "$ENV{OSCAR_HOME}/lib";
use OSCAR::Database;
use Fcntl;
use base qw(Exporter);
use vars qw($VERSION $DBMAP @EXPORT);

$VERSION = sprintf("%d", q$Revision: 4368 $ =~ /(\d+)/);

@EXPORT = qw(exists_image list_image set_image del_image
             exists_client list_client set_client del_client
             exists_adapter list_adapter set_adapter del_adapter
             exists_network list_network set_network del_network );

$DBMAP = {
          'SIS::Client' => {
	      table => 'Nodes',
	      key   => 'name',
	  },
          'SIS::Image' => {
	      table => 'Images',
	      key   => 'name',
	  },
          'SIS::Adapter' => {
	      table => 'Nics',
	      key   => 'ip',
	  },
          'SIS::Network' => {
	      table => 'Networks',
	      key   => 'n_id',
	  },
      };

# lisp has the tendency to us p as a typable replacement for ?

sub match_p {
    my ($obj, $criteria) = @_;
    foreach my $key (sort keys %$criteria) {
        unless($obj->get($key) eq $criteria->{$key}) {
            return undef;
        }
    }
    return 1;
}

sub exists_image {
    my ($name) = @_;
    my @images = list_image(name => $name);
    return scalar(@images);
}

sub list_image {return _list_obj('SIS::Image',@_)}
sub del_image {return sisdel('SIS::Image',@_)}
sub set_image {return sisset('SIS::Image',@_)}

sub exists_client {
    my ($name) = @_;
    my @images = list_client(name => $name);
    return scalar(@images);
}

sub list_client {return _list_obj('SIS::Client',@_)}
sub del_client {return sisdel('SIS::Client',@_)}
sub set_client {return sisset('SIS::Client',@_)}

sub exists_adapter {
    my ($name, $client) = @_;
    my @images = list_adapter(devname => $name, client => $client);
    return scalar(@images);
}
sub list_adapter {return _list_obj('SIS::Adapter',@_)}
sub del_adapter {return sisdel('SIS::Adapter',@_)}
sub set_adapter {return sisset('SIS::Adapter',@_)}

sub exists_network {
    my ($name) = @_;
    my @networks = list_network(name => $name);
    return scalar(@networks);
}
sub list_network {return _list_obj('SIS::Network',@_)}
sub del_network {return sisdel('SIS::Network',@_)}
sub set_network {return sisset('SIS::Network',@_)}

sub _list_obj {
    my $type = shift;
    my %criteria = @_;
    my @obj = sisget($type,%criteria);
    if(wantarray) {
        return @obj;
    } elsif(scalar(@obj) == 1) {
        return $obj[0];
    } else {
        return undef;
    }
}

sub sisget {
    my $type = shift;
    my (%args) = @_;

    my $table = $DBMAP->{$type}->{table};
    my $sql = "SELECT * FROM $table";
    my @where = map { "$_='".$args{$_}."'" } keys(%args);
    if (@where) {
	$sql .= " WHERE " . join(" AND ", @where);
    }

    my @result;
    my (%options,@errors);
    $options{debug}=1;
    print "SQL query: $sql\n" if $option{debug};
    die "$0:Failed to query values via << $sql >>"
        if (!do_select($sql,\@result, \%options, @errors));
    return @result;
}

sub sisset {
    my $type = shift;
    my @obj = @_;

    my @result;
    my (%options,@errors);
    $options{debug}=1;

    my $table = $DBMAP->{$type}->{table};
    my $key = $DBMAP->{$type}->{key};

    foreach my $o (@obj) {
	# does the record with $primkey exist? if yes, update it, otherwise
	# create it
        my $keyval = $o->{$key};
	my $sql = "SELECT $key FROM $table WHERE $key='".$keyval."'";

	print "SQL query: $sql\n" if $option{debug};
	die "$0:Failed to query values via << $sql >>"
	    if (!do_select($sql,\@result, \%options, \@errors));
	if (scalar(@result)) {
	    # update

	    $sql = "UPDATE $table SET ";
	    my @updates = map { "$_='" . $o->{$_} . "'" } (keys(%{$o}));
	    $sql .= join(", ",@updates);
            $sql .= " WHERE $key='$keyval' ";
	    croak("$0:Failed to update values via << $sql >>")
		if !do_update($sql, $table, \%options, \@errors);

	} else {
	    # insert

	    $sql = "INSERT INTO $table (" . join(", ",(keys(%{$o}))) . ") ";
	    $sql .= "VALUES ('" . join("', '",(values(%{$o}))) . "')";

	    croak("$0:Failed to insert values via << $sql >>")
		if !do_update($sql, $table, \%options, \@errors);
	}
    }
    return 1;
}

sub sisdel {
    my $type = shift;
    my @keys = @_;

    return if (!scalar(@keys));

    my @result;
    my (%options,@errors);
    $options{debug}=1;

    my $table = $DBMAP->{$type}->{table};
    my $key = $DBMAP->{$type}->{key};

    my @where = map { "$key='" . $_ . "'" } @keys;
    my $sql = "DELETE FROM $table WHERE " . join(" OR ", @where);
    croak("$0:Failed to delete values via << $sql >>")
	if !do_update($sql, $table, \%options, \@errors);
    return 1;
}

42;
