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

# Copyright (c) Erich Focht <efocht@hpce.nec.com> , 2006
# Copyright (c) 2009        Geoffroy Vallee <valleegr@ornl.gov>
#                           Oak Ridge National Laboratory
#                           All rights reserved.

#
# $Id$


BEGIN {
    if (defined $ENV{OSCAR_HOME}) {
        unshift @INC, "$ENV{OSCAR_HOME}/lib";
    }
}

use strict;
use Carp;
use OSCAR::Database;
use OSCAR::Database_generic;
use OSCAR::NodeMgt;
use OSCAR::Network;
use OSCAR::Utils;
use GDBM_File;
use Data::Dumper;
use MLDBM qw(GDBM_File);
use Fcntl;
use base qw(Exporter);
use vars qw($VERSION $DBPATH $DBMAP @EXPORT);

my $debug = 1;


# $VERSION = sprintf("%d.%02d", q$Revision$ =~ /(\d+)/);

@EXPORT = qw(
            exists_image
            list_image
            set_image del_image
            exists_client
            list_client
            set_client
            del_client
            exists_adapter
            list_adapter
            set_adapter
            del_adapter
            );

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
# 
# # lisp has the tendency to us p as a typable replacement for ?
# 
# sub match_p {
#     my ($obj, $criteria) = @_;
#     foreach my $key (sort keys %$criteria) {
#         unless($obj->get($key) eq $criteria->{$key}) {
#             return undef;
#         }
#     }
#     return 1;
# }

my %sis2oda = (
                image => {
                    arch => "Images.architecture",
                    name => "Images.name",
                    location => "Images.path",
                },
                adapter => {
                    client  => "Nodes.name:Nodes.id=Nics.node_id",
                    mac     => "Nics.mac",
                    ip      => "Nics.ip",
                    netmask => "Networks.netmask:Networks.n_id=Nics.network_id",
                    devname => "Nics.name" ,
                },
                client => {
                    #EF: route is probably the Networks.gateway entry.
                    name => "Nodes.name",
#                     route => "Networks.gateway:Nics.node_id=Nodes.id AND Networks.n_id=Nics.network_id",
                    hostname => "Nodes.hostname",
                    # domainname required by SystemInstaller::Image::get_machine_listing()
                    domainname => "Nodes.dns_domain",
#                     arch => "Images.architecture:Nodes.image_id=Images.id",
                    imagename => "Images.name:Images.id=Nodes.image_id",
#                     name => "Nodes.name",
                    # proccount required by SystemInstaller::Image::get_machine_listing() and torque api-post-deploy
                    proccount => "Nodes.cpu_num",
                    gpucount => "Nodes.gpu_num",
                },
           );


# 
my %main_table = (
		  image => "Images",
		  client => "Nodes",
		  adapter => "Nics",
		  );
#
# Key fields in the corresponding ODA table.
# I didn't use the "id" fields because I'd like to remove them from the table.
# Also: I want to use a field that's returned by the list_* command.
my %key_fields = (
		  image => { name => "name" },  # SIS(Image).name  -> Images.name
		  client => { name => "name" }, # SIS(Client).name -> Nodes.name
		  adapter => { ip => "ip" },    # SIS(Adapter).ip  -> Nics.ip
		  );


sub list_image { return list_common("image",@_)}

sub list_adapter ($) {
    my $optref = shift;

    my $res = OSCAR::Network::get_network_adapter ($optref);
    if (!defined ($res)) {
        print "[INFO] Impossible to get the adapters\n";
        return undef;
    }

    return $res;
}

# Return: an array of hash, each element of the array being details about a 
#         given client. Undef if error.
sub list_client { return list_common("client",@_)}

sub exists_image {
    my ($name) = @_;
    my @images = list_image(name => $name);
    return scalar(@images);
}
sub exists_client {
    my ($name) = @_;
    my @images = list_client(name => $name);
    return scalar(@images);
}
sub exists_adapter {
    my ($name, $client) = @_;
    my %h = (devname => $name, client => $client);
    my @images = list_adapter(\%h);
    return scalar(@images);
}
# 
sub del_image   { return del_common("image", @_)   }
sub del_client  { return del_common("client", @_)  }
sub del_adapter { return del_common("adapter", @_) }


sub set_image {return sisset('SIS::Image',@_)}
# sub set_client {return sisset('SIS::Client',@_)}

# This function accepts arguments created by the  SIS::Client class.
# for instance:
# my $client_template = new SIS::Client($config->basename.$cnum);
sub set_client ($) {
    my $ref = shift;

    if (!defined $ref) {
        carp "ERROR: No clients to add";
        return -1;
    }

    if (OSCAR::NodeMgt::add_clients ($ref)) {
        carp "ERROR: Impossible to add clients";
        return -1;
    }
    return 0;
}

sub set_adapter (@) {
    my @alist = @_;

    print "Data to store:\n";
    print Dumper @alist;
    if (OSCAR::Network::set_network_adapter (\@alist)) {
        carp "ERROR: Impossible to set the adapters";
        return -1;
    }

    return 0;
}

##########################################################################

sub list_common {
    my ($table, %args) = @_;

    my (%tables, @fields, %fields_as, @conditions);
    for my $sisk (keys(%{$sis2oda{$table}})) {
        my ($field, $condition) = split(":",$sis2oda{$table}->{$sisk});
#         print "Field: $field\n";
        my ($tab, $f) = split(/\./,$field);
        if ($f) {
            my $as = lc($tab."__".$f);
            $fields_as{$as} = $field;
            push @fields, "$field AS $as";
        } else {
            push @fields, $field;
        }
        $tables{$tab} = 1;
        # check tables in conditions fields
        if (defined ($condition)) {
            my @conds = split(" AND ", $condition);
            for my $c (@conds) {
                my ($f1,$f2) = split(/=/, $c);
                my ($tab1,$n1) = split(/\./, $f1);
                $tables{$tab1} = 1;
                my ($tab2,$n2) = split(/\./, $f2);
                $tables{$tab2} = 1;
                push (@conditions, $c);
            }
        }
    }

    if (scalar (@fields) == 0) {
        carp "ERROR: No fields found (table: $table)";
        return undef;
    }
    my $sql = "SELECT ".join(", ",@fields)." FROM ".join(", ",keys(%tables));

    &convert_sis2oda(\%args, $table);
    my @where = map { "$_='".$args{$_}."'" } keys(%args);
    if (@where || @conditions) {
        $sql .= " WHERE " . join(" AND ", @where, @conditions);
    }

    my @result;
    my (%options,@errors);
    $options{debug} = 0;
#     print "SQL query: $sql\n" if $debug;
    die "$0:Failed to query values via << $sql >>"
        if (!do_select($sql,\@result, \%options, @errors));

    &convert_results_oda2sis(\@result, \%fields_as, $table);
    return @result;
}

# Return: 1 if success, 0 else.
sub del_common {
    my ($table, %args) = @_;
    my $maintable = $main_table{$table};
    my $siskey = (keys(%{$key_fields{$table}}))[0];
    my $odakey = $maintable . "." . $key_fields{$table}->{$siskey};

    if (!OSCAR::Utils::is_a_valid_string ($maintable)) {
        carp "ERROR: Impossible to get the maintable";
        return 0;
    }

    if (!scalar(keys(%args))) {
        carp "ERROR: No records selected. Refusing to delete all records in".
             " table  $maintable";
        return 0;
    }

    # - get the selection output by list_*
    # - collect key fields from output
    # - delete records with key fields from the main table
    my @selection;
    eval "\@selection = list_$table(%args)";
    if (!scalar(@selection)) {
        carp "ERROR: Selection had no result. Returning";
        return 0;
    }

    my @keys = map { $_->{$siskey} } @selection;

    my $sql = "DELETE FROM $maintable";

    my @where = map { "$odakey='".$_."'" } @keys;
    if (@where) {
        $sql .= " WHERE " . join(" OR ", @where);
    }

    my @result;
    my (%options,@errors);
    $options{debug} = 1;
    if (!do_update($sql, $maintable, \%options, @errors)) {
        carp "ERROR: Impossible to do the update ($sql)";
        return 0;
    }

    return 1;
}

#sub set_common {
#    my ($table,%args) = @_;
#    my $maintable = $main_table{$table};
#    my $siskey = (keys(%{$key_fields{$table}}))[0];
#    my $odakey = $maintable . "." . $key_fields{$table}->{$siskey};
#
#    if (!scalar(keys(%args))) {
#	print "No records selected. Refusing to delete all records in".
#	    " table  $maintable\n";
#	return 0;
#    }
#
#    # - get the selection output by list_*
#    # - collect key fields from output
#    # - delete records with key fields from the main table
#    my @selection;
#    eval "\@selection = list_$table(%args)";
#    if (!scalar(@selection)) {
#	print "Selection had no result. Returning.\n" if ($debug);
#	return 0;
#    }
#
#    my @keys = map { $_->{$siskey} } @selection;
#
#
#    my $sql = "DELETE FROM $maintable";
#
#
#    my @where = map { "$odakey='".$_."'" } @keys;
#    if (@where) {
#	$sql .= " WHERE " . join(" OR ", @where);
#    }
#
#    my @result;
#    my (%options,@errors);
#    $options{debug}=1;
#    print "SQL query: $sql\n" if $debug;
#    #die "$0:Failed to query values via << $sql >>"
#    #    if (!do_select($sql,\@result, \%options, @errors));
#    return @result;
#
#
#}

sub convert_fields_as {
    my ($ref, $as) = @_;

    for my $k (keys(%{$ref})) {
	if (exists($as->{$k})) {
	    my $o = $as->{$k};
	    my $v = $ref->{$k};
	    delete $ref->{$k};
	    $ref->{$o} = $v;
	}
    }
}


sub convert_sis2oda {
    my ($args, $table) = @_;
    my $maintable = $main_table{$table};
    my $dummy;
    for my $k (keys(%{$args})) {
	my $v = $args->{$k};
	if (exists($sis2oda{$table}->{$k})) {
	    #
	    # convert SIS selector to ODA selector argument
	    #
	    my $o = $sis2oda{$table}->{$k};
	    if ($o =~ /:/) {
		($o,$dummy) = split (/:/,$o);
	    }
	    delete $args->{$k};
	    $args->{$o} = $v;
	} else {
	    #
	    # is native ODA selector, prepend maintable to it if needed
	    #
	    if ($k !~ /\./) {
		delete $args->{$k};
		$args->{"$maintable.$k"} = $v;
	    }
	}
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
	    print "WARNING: Could not find key $o in oda2sis table!\n" if $debug;
	    next;
	}
	my $k = $oda2sis{$o};
	my $v = $ref->{$o};
	delete $ref->{$o};
	$ref->{$k} = $v;
    }
}

sub convert_results_oda2sis {
    my ($arr, $as, $table) = @_;

    for (my $i = 0; $i < scalar(@{$arr}); $i++) {
	&convert_fields_as($$arr[$i], $as);
	&convert_oda2sis($$arr[$i], $table);
    }
}




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
sub _dbfile {
    my $type = shift;
    my $file = $DBPATH . "/" . $DBMAP->{$type}->{file};
    if(-e $file) {
        return $file;
    }
    croak("Can't find db file $file!");
}
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
sub sisset {
    my $type = shift;
    my @obj = @_;
    my %dbh = ();
    my $file = _dbfile($type);
    my $rc = tie (%dbh, 'MLDBM', $file, GDBM_WRCREAT(), 0640) or croak("Couldn't open MLDBM $file: $!");
    foreach my $o (@obj) {
        $dbh{$o->{primkey}} = $o;
    }
    # This must be done to get rid of the untie warning
    undef $rc;
    untie %dbh;
    return 1;
}
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

1;

__END__

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
  Copyright 2009 Geoffroy Vallee <valleegr@ornl.gov>

=cut
