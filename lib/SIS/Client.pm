package SIS::Client;

#   $Header: /cvsroot/systeminstaller/systeminstaller/lib/SIS/Client.pm,v 1.4 2002/12/17 17:25:48 mchasal Exp $

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

@ATTR = qw(route hostname domainname arch imagename name proccount);

sub new {
    my $class = shift;
    my $name = shift;
    my @init = map {"_" . $_ => undef} @ATTR;
    my %this = (
                _vars => {
                          @init,
                          _name => $name,
                         },
               );
    bless \%this, $class;
}

sub primkey {
    my $this = shift;
    return $this->name();
}

sub valid {
    my ($this, $name, $value) = @_;
    if($name eq "imagename") {
        return exists_image($value);
    }
    return 1;
}

1;

__END__;
