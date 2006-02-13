package SIS::Component;

#   $Id$

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

=head1 NAME

SIS::Component;

=cut

use strict;
use Carp;
use Data::Dumper;
use vars qw($VERSION $AUTOLOAD @ATTR);

# If this ever shows up, something is wrong.
@ATTR = qw(I hate you kenny);

sub new {
    my $class = shift;
    my $name = shift;
    my %this = (
                _vars => {
                          @_,
                          _name => $name,
                         },
               );
    bless \%this, $class;
}

sub primkey {
    croak("You need to define a primary key for this data type");
}

sub equals {
    my ($this, $name, $value) = @_;
    if(($this->get($name) cmp $value) == 0) {
        return 1;
    }
    return 0;
}

sub valid {
    return 1;
}

sub get {
    my ($this, $name) = @_;
    return $this->$name;
}

sub set {
    my ($this, $name, $value) = @_;
    return $this->$name($value);
}

sub clone {
    my $this = shift;
    my $class = ref($this);
    my $new = $class->new;
    my @attr = $this->attrs();
    foreach my $attr (@attr) {
        $new->$attr($this->$attr);
    }
    return $new;
}

sub attrs {
    my $this = shift;
    return map {s/^_//; $_} (sort keys %{$this->{_vars}});
}

sub clear {
    my ($this, $name) = @_;
    if($this->valid($name,undef)) {
        $this->{_vars}->{"_$name"} = undef;
        return 1;
    }
    carp("Can't clear $name, would create invalid data");
    return undef;
}

sub DESTROY {
    # This makes sure that AUTOLOAD doesn't bitch on trying to call DESTROY
    return 1;
}

# Default Autoloader.  Means we don't have to define accessors for private data.
# This can probably be made more efficient through method caching, but
# I haven't gotten arround to it yet.

sub AUTOLOAD {
    my ($this, $value) = @_;
    $AUTOLOAD =~ /.*::(\w+)/ or croak("No AUTOLOAD present");
    my $var = $1;

    exists $this->{_vars}->{"_$var"}
      or (carp("No such method: $AUTOLOAD"), return undef);
    
    no strict 'refs';


    # The joyous voodoo of caching sub routines.  If you want
    # an explanation, search on google for AUTOLOAD cache
    
    *{$var} = sub {
        my $this = shift;
        my $value = shift;
        if(defined($value)) {
            if($this->valid($var,$value)) {
                $this->{_vars}->{"_$var"} = $value;
            } else {
                carp("Invalid assignment of $var = $value");
                return undef;
            }
        }
        return $this->{_vars}->{"_$var"};
    };
    goto &$var;
}
      
42;
