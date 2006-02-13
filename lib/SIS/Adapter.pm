package SIS::Adapter;

#   $Header: /cvsroot/systeminstaller/systeminstaller/lib/SIS/Adapter.pm,v 1.5 2003/01/21 22:18:47 mchasal Exp $

#   Copyright (c) 2001 International Business Machines

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

#   Sean Dague <sean@dague.net>

use strict;
use vars qw($VERSION @ATTR); 
use base qw(SIS::Component);
use SIS::DB;

$VERSION = sprintf("%d", q$Revision$ =~ /(\d+)/);

@ATTR = qw(client mac ip netmask devname);

sub new {
    my $class = shift;
    my $name = shift;
    my @init = map {"_" . $_ => undef} @ATTR;
    my %this = (
                _vars => {
                          @init,
                          _devname => $name,
                         },
                _cache => {
                           _primkey => '',
                          }
               );
    bless \%this, $class;
}

sub primkey {
    my $this = shift;
    return $this->{_cache}->{_primkey}; #client} . ":" . $this->{_devname};
}

sub valid {
    my ($this, $name, $value) = @_;
    if($name eq "client") {
        return exists_client($value);
    }
    return 1;
}

sub devname {
    my ($this, $value) = @_;
    if(defined($value)) {
        $this->{_vars}->{_devname} = $value;
        my $client = $this->{_vars}->{_client} || "";
        $this->{_cache}->{_primkey} = $this->{_vars}->{_devname} . ":" . $client;
    }
    return $this->{_vars}->{_devname}
}

sub client {
    my ($this, $value) = @_;
    if(defined($value)) {
        $this->{_vars}->{_client} = $value;
        my $dev = $this->{_vars}->{_devname} || "";
        $this->{_cache}->{_primkey} = $dev . ":" . $this->{_vars}->{_client};
    }
    return $this->{_vars}->{_client}
}

1;

__END__;
