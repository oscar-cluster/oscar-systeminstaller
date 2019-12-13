package SystemInstaller::PackageBest;

#   $Header: /cvsroot/systeminstaller/systeminstaller/lib/SystemInstaller/PackageBest.pm,v 1.4 2002/11/07 20:54:38 mchasal Exp $

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
 
#   Michael Chase-Salerno <mchasal@users.sf.net>
#   Sean Dague <sdague@users.sf.net>

use strict;

use Carp;

use vars qw(@ISA @EXPORT);
use POSIX;

my @PBMODS=qw(Rpm);

use base qw(Exporter);
@EXPORT = qw(find_files cache_gen);

use SystemInstaller::PackageBest::Rpm;

sub cache_gen {
# Generate/update the cache lists
# Input: dir name, force flag
# Output: boolean success/failure

        my %args = (
                FORCE           => "0",
                CACHEFILE       => ".pkgcache",
                PKGDIR          => "",
                @_,
        );

        foreach my $mod (@PBMODS){
                my $class="SystemInstaller::PackageBest::$mod";
                if ($class->footprint(%args->{PKGDIR})) {
                        return $class->cache_gen(%args->{PKGDIR},%args->{FORCE});
                }
        }
        return 1;

} #cache_gen


sub find_files {
        # Finds the best version of files to use based on an rpm list
        # Input:  a parameter list containing the following:
        #       PKGDIR  The location of the packages
        #       PKGLIST A reference to a list of desired packages
        #   and optionally:
        #       ARCH    The target archtecture, default: current arch
        #       RPMRC   The rpmrc filename, default: /usr/lib/rpm/rpmrc
        #       CACHEFILE The name for the cachefile, default: .pkgcache
        # 
        # Output: A hash whose keys are the package name and whose
        #         values are the filenames.

        my %args = (
                ARCH            => (uname)[4],
                RPMRC           => "/usr/lib/rpm/rpmrc",
                RPMCMD          => "/bin/rpm",
                CACHEFILE       => ".pkgcache",
                FORCE           => 0,
                CACHEONLY       => 0,
                PKGDIR          => "",
                PKGLIST         => [],
                @_,
        );
        # Find a class that footprints
        my $class;
        foreach my $mod (@PBMODS){
                my $tclass="SystemInstaller::PackageBest::$mod";
                if ($tclass->footprint(%args->{PKGDIR})) {
                        $class=$tclass;
                        last;
                }
        }
        unless ($class) { 
                carp("Couldn't find a matching footprint in ". %args->{PKGDIR} . "!");
                return;
        }
        
        # Now do the work

        my $rc=$class->cache_gen(%args);
        unless ($rc) {
                return;
        }
        if (%args->{CACHEONLY}) {
                return $rc;
        }
        return $class->find_files(%args);
}

1;
