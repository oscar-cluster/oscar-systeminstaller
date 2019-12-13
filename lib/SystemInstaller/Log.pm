package SystemInstaller::Log;

#   $Id $

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

#   Sean Dague <japh@us.ibm.com>

use strict;
use OSCAR::Env;

require Exporter;
use vars qw(@ISA @EXPORT_OK @EXPORT %EXPORT_TAGS $DEBUG $VERBOSE $FH);

push @ISA, qw(Exporter);

%EXPORT_TAGS = ( 
                'all' => [
                          qw(debug verbose start_debug start_verbose stop_debug stop_verbose logger_file get_debug get_verbose)
                         ],
                'print' => [ 
                            qw(debug verbose) 
                           ],
                'control' => [
                              qw(start_debug start_verbose stop_debug stop_verbose logger_file get_debug get_verbose)
                             ],
               );

@EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

# The following are encapsulated so that we can change the internals without having to change
# code that uses it

{
    $DEBUG = 0;
    $VERBOSE = 0;
    $FH = \*STDERR;
    
    sub start_debug {
        $DEBUG = 1;
    }
    
    sub stop_debug {
        $DEBUG = 0;
    }

    sub get_debug {
        return $DEBUG;
    }
    
    sub start_verbose {
        $VERBOSE = 1;
        $ENV{OSCAR_VERBOSE} = 5;
        $OSCAR::Env::oscar_verbose = 5;
    }
    
    sub stop_verbose {
        $VERBOSE = 0;
    }
    
    sub get_verbose {
        return $VERBOSE;
    }
    
    sub logger_file {
        my $fh = shift;
        $FH = $fh;
    }
    
    sub debug {
        if($DEBUG) {
            my ($package, $filename, $line) = caller;
            print $FH "[$package :: Line $line] " . join(', ', @_) . "\n";
        }
    }
    
    sub verbose {
        if($VERBOSE) {
            my ($package, $filename, $line) = caller;
            print $FH &timestamp . " [$package :: Line $line] " . join(', ', @_) . "\n";
        }
    }
    
    sub timestamp {
        my ($sec, $min, $hour, $mday,$mon, $year, $wday, $yday, $isdst) = localtime(time);
        $mon++;
        $year=$year+1900;
        return "$year-$mon-$mday $hour:$min:$sec";
    }
}

1;
__END__

=head1 NAME

SystemInstaller::Log - Logging and verbose mechanism for SystemInstaller

=head1 SYNOPSIS

  use SystemInstaller::Log qw(:print);

=head1 DESCRIPTION

Contains functions for logging & verbose output. The functions are:

=over 4

=item I<start_verbose>

Turns verbose flag on

=item I<stop_verbose>

Turns verbose flag off

=item I<get_verbose>

Gets verbose value

=item I<start_debug>

Turns debug flag on

=item I<stop_debug>

Turns debug flag off

=item I<get_debug>

Gets debug value

=item I<logger_file>

Sets output file handle

=item I<verbose(<STRING>)>

Outputs <STRING> if verbose is set

=item I<debug(<STRING>)>

Outputs <STRING> if debug is set

=back

=head1 EXPORTS

None by default.  The following export tags are provided:

=over 4

=item I<:all>

all specifications 

=item I<:print>

verbose & debug 

=item I<:control>

start_debug start_verbose stop_debug stop_verbose logger_file get_debug get_verbose

=back

=head1 AUTHOR

  Sean Dague <japh@us.ibm.com>

=head1 SEE ALSO

L<perl>.

=cut
