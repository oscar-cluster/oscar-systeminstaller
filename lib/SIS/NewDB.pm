package SIS::NewDB;

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


=head1 NAME

SIS::NewDB - ODA Interface for client, image, and adapter objects

=head1 SYNOPSIS

  use SIS::NewDB;

  my @clients = list_client();
  my $name = $clients[0]->name();
  del_client($name);
  my $newname = "test";
  $clients[0]->name($newname) or croak("Can't set name on client");
  set_client($clients[0]);

=head1 DESCRIPTION

The SIS::NewDB interface gives one access to the OSCAR mysql database.
There exists 4 functions for every object type: exists_X, list_X, set_X, del_X.  (These will be discussed in detail later).

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

  Copyright 2006 Erich Focht <efocht@hpce.nec.com>

=cut

use strict;
use Carp;
use GDBM_File;
use Data::Dumper;
use OSCAR::Database;
use base qw(Exporter);
use vars qw($VERSION $DBPATH $DBMAP @EXPORT);

$VERSION = sprintf("%d.%02d", q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/);

@EXPORT = qw(exists_image list_image set_image del_image
             exists_client list_client set_client del_client
             exists_adapter list_adapter set_adapter del_adapter);

$DBPATH = $ENV{SIS_DBPATH} || "/var/lib/sis";
if($ENV{SIS_DBTYPE} and ($ENV{SIS_DBTYPE} eq "Storable")) {
    $MLDBM::Serializer = "Storable";
}

$DBMAP = {
          'SIS::Client' => {
                            file => 'client',
                           },
          'SIS::Image' => {
                           file => 'image',
                          },
          'SIS::Adapter' => {
                             file => 'adapter',
                            },
          'SIS::Trigger' => {
                             file => 'trigger',
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

my $sis2oda = (
	       image => {
		   arch => "architecture",
		   name => "name",
		   location => "path",
	       },
	       adapter => {
		   client  => "Nodes.name:Nodes.id=Nics.node_id",
		   mac     => "mac",
		   ip      => "ip",
		   netmask => "Networks.netmask:Networks.n_id=Nics.network_id",
		   devname => "name" ,
	       },
	       client => {
		   route => "",
		   hostname => "hostname",
		   domainname => "fqdn",
		   arch => "",
		   imagename => "",
		   name => "name",
		   proccount => "cpu_num",
	       },
	       );



sub list_image {
    my %args = @_;
    my $sql = "SELECT * FROM Images ";

    &convert_sis2oda(\%args, "image");
    my @where = map { "$_='".$args->{$_}."'" } keys(%{$args});
    if (@where) {
	$sql .= " WHERE " . join(" AND ", @where);
    }

    my @images;
    die "$0:Failed to query values via << $sql >>"
        if (!do_select($sql,\@images, $options_ref, $error_strings_ref));

    print Dumper(@images);
    &convert_results_oda2sis(\@images, "image");
    return @images;
}



sub convert_sis2oda {
    my ($args, $table) = @_;
    my @where;
    for my $k (keys(%{$args})) {
	my $o = $sis2oda{$k};
	my $v = $args->{$k}
	delete $args->{$k};
	$args->{$o} = $v;
    }
}

sub convert_oda2sis {
    my ($ref, $table) = @_;
    my @where;

    my %oda2sis;
    my %tmp = %{$sis2oda{$table}};
    for my $k (keys(%tmp)) {
	my ($var,$condition) = split(":",$tmp{$k});
	$oda2sis{$var} = $k;
    }

    for my $o (keys(%{$ref})) {
	if (!exists($oda2sis{$o})) {
	    print "Could not find key $o in oda2sis table!\n";
	    print "Result hash:\n".Dumper($ref);
	    print "oda2sis hash:\n".Dumper($oda2sis);
	    exit;
	}
	my $k = $oda2sis{$o};
	my $v = $ref->{$o}
	delete $ref->{$o};
	$ref->{$k} = $v;
    }
}

sub convert_results_oda2sis {
    my ($arr, $table) = @_;

    for (my $i = 0; $i < scalar(@{$arr}); $i++) {
	&convert_oda2sis($$arr[$i], $table);
    }
}


# sub exists_image {
#     my ($name) = @_;
#     my @images = list_image(name => $name);
#     return scalar(@images);
# }
# 
# sub list_image {return _list_obj('SIS::Image',@_)}
# sub del_image {return sisdel('SIS::Image',@_)}
# sub set_image {return sisset('SIS::Image',@_)}
# 
# sub exists_client {
#     my ($name) = @_;
#     my @images = list_client(name => $name);
#     return scalar(@images);
# }
# 
# sub list_client {return _list_obj('SIS::Client',@_)}
# sub del_client {return sisdel('SIS::Client',@_)}
# sub set_client {return sisset('SIS::Client',@_)}
# 
# sub exists_adapter {
#     my ($name, $client) = @_;
#     my @images = list_adapter(devname => $name, client => $client);
#     return scalar(@images);
# }
# sub list_adapter {return _list_obj('SIS::Adapter',@_)}
# sub del_adapter {return sisdel('SIS::Adapter',@_)}
# sub set_adapter {return sisset('SIS::Adapter',@_)}
# 
# sub _list_obj {
#     my $type = shift;
#     my %criteria = @_;
#     my @obj = ();
#     my @temp = sisget($type);
#     foreach my $obj (@temp) {
#         if(match_p($obj, \%criteria)) {
#             push @obj, $obj->clone;
#         }
#     }
#     if(wantarray) {
#         return @obj;
#     } elsif(scalar(@obj) == 1) {
#         return $obj[0];
#     } else {
#         return undef;
#     }
# }
# 
# sub _dbfile {
#     my $type = shift;
#     my $file = $DBPATH . "/" . $DBMAP->{$type}->{file};
#     if(-e $file) {
#         return $file;
#     }
#     croak("Can't find db file $file!");
# }
# 
# sub sisget {
#     my $type = shift;
#     my %dbh = ();
#     my $file = _dbfile($type);
#     return () if -z $file;
#     my $rc = tie (%dbh, 'MLDBM', $file, GDBM_READER(), 0444) or croak("Couldn't open MLDBM $file: $!");
#     my @obj =  (sort {$a->primkey cmp $b->primkey} values %dbh);
#     # This must be done to get rid of the untie warning
#     undef $rc;
#     untie %dbh;
#     return @obj;
# }
# 
# sub sisset {
#     my $type = shift;
#     my @obj = @_;
#     my %dbh = ();
#     my $file = _dbfile($type);
#     my $rc = tie (%dbh, 'MLDBM', $file, GDBM_WRCREAT(), 0640) or croak("Couldn't open MLDBM $file: $!");
#     foreach my $o (@obj) {
#         $dbh{$o->primkey} = $o;
#     }
#     # This must be done to get rid of the untie warning
#     undef $rc;
#     untie %dbh;
#     return 1;
# }
# 
# sub sisdel {
#     my $type = shift;
#     my @keys = @_;
#     my %dbh = ();
#     my $file = _dbfile($type);
#     my $rc = tie (%dbh, 'MLDBM', $file, GDBM_WRCREAT(), 0640) or croak("Couldn't open MLDBM $file: $!");
#     foreach my $key (@keys) {
#         delete $dbh{$key};
#     }
#     # This must be done to get rid of the untie warning
#     undef $rc;
#     untie %dbh;
#     return 1;
# }

42;
