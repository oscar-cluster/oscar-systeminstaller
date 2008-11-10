package SystemInstaller::Package::PackManSmart;

#   Copyright (c) 2005 Erich Focht <efocht@hpce.nec.com>
#                      All rights reserved.
# 
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

use strict;

use File::Path;
use File::Basename;
use SystemInstaller::Log qw(verbose get_verbose);
use OSCAR::PackMan;
use Carp;

use vars qw($VERSION $config);

# The following two env var is needed by mandrake. It should not affect
# anyone else in a negative way

$ENV{SECURE_LEVEL} = 1;
 
$VERSION = sprintf("r%d", q$Revision: 1111$ =~ /(\d+)/);

#
## API FUNCTIONS
#

sub footprint {
# Look at a directory and determine if it looks like rpms.
# Input:        Directory name
# Returns:      Boolean of match
        my $class=shift;
        my $mode=shift;
        my $path=shift;
        if (($mode eq "files")
                || ($mode eq "install")
                || ($mode eq "post_install")
                || ($mode eq "pre_install")) {

	    # is PackMan available and is it "smart"
	    my $pm = PackMan->new();
	    if ($pm && $pm->is_smart()) {
		return 1;
	    }
        }
        return 0;
} #footprint

sub files_find {
#
# Check that the files exist on the specified media.
# Set the PFILES list to the filenames found.
# With a smart package manager we don't care whether all dependencies
# are resolved. The package manager will fail later when it cannot
# resolve dependencies.
#
# Input:	rpm paths, architecture, pkg list
# Returns:	file list or null if failure.

        my $class  = shift;
        my $rpmdir = shift;
        my $arch   = shift;
        my (@pkglist) = @_;

        return @pkglist;

} #files_find


sub files_pre_install {
# Rpm pre install routine
# Make sure rpm database dir exists.
# Input: imagedir, pkgdir
# Output: boolean
    my $class=shift;
    my $imagedir = shift;
    my $pkgdir = shift;

    &verbose("Priming Rpm database: $imagedir/var/lib/rpm/");
    unless (mkpath("$imagedir/var/lib/rpm/")) {
            carp("Unable to create rpm database directory.");
            return 0;
    }
    unless (mkpath("$imagedir/dev/")) {
            carp("Unable to create dev directory.");
            return 0;
    }

    &verbose("Creating /dev/null");
    if (system("/bin/mknod $imagedir/dev/null c 1 3")) {
            carp("Unable to create /dev/null device, continuing.");
    }

    &verbose("Creating /dev/console");
    if (system("/bin/mknod $imagedir/dev/console c 5 1")) {
            carp("Unable to create /dev/console device, continuing.");
    }


    return 1;
} # files_pre_install

sub files_install {
# Install the packages.
# Input:        image dir, filelist	
# Returns:	Boolean

    my $class    = shift;
    my $imgpath  = shift;
    my $pkgpath  = shift;
    my $errs     = shift;
    my (@stages) = @_;


    use lib "$ENV{OSCAR_HOME}/lib";
    require OSCAR::PackageSmart;

    my $verbose=1;
    if (get_verbose) {
        $verbose = 1;
    }

    my @pools = split(",",$pkgpath);

    my $pm = OSCAR::PackageSmart::prepare_pools($verbose,@pools);
    if (!$pm) {
    	croak "\nERROR: Could not create PackMan instance!\n";
    }

    $pm->chroot($imgpath);
    $pm->progress(1);

    # for smart installs the stages is simply the package list
    my @pkglist = @stages;

    &verbose("Performing PackMan smart_install:");
    print "---> " . $pm->status() . "\n";
    my ($res,@out) = $pm->smart_install(@pkglist);
    my @failed = $pm->check_installed(@pkglist);
    if (@failed) {
	    push @{$errs}, "\n~~~~\nERROR: Failed to install packages: ".
		    join(", ",@failed)."\n~~~~\n";
	    carp("PackMan smart_install failed.");
	    return 0;
    }
    if (!$res) {
    	push @{$errs}, "Error occured during installation with Yume:\n";
	    push @{$errs}, "pkglist was: ". join(",",@pkglist)."\n";
	    push @{$errs}, join("\n",@out)."\n\n";
    }
    return 1;
} #files_install

sub files_post_install {
# Rpm post install routine
# Input: imagedir, pkgdir
# Output: boolean
    my $class=shift;
    my $imagedir = shift;
    my $pkgdir = shift;
    my @file;
    # Here are some things that I know we need to do...

    # The following is a Mandrakeism.
    if(-x "$imagedir/usr/sbin/msec") {
        system("chroot $imagedir /usr/sbin/msec 3");
    }
    if ((! -e "$imagedir/boot/lilo") && (-e "$imagedir/boot/lilo-text")) {
            symlink("lilo-text","$imagedir/boot/lilo");
    }

    # Generate shadow files
    if(-x "$imagedir/usr/sbin/pwconv") {
        system("chroot $imagedir /usr/sbin/pwconv");
    }
    if(-x "$imagedir/usr/sbin/grpconv") {
        system("chroot $imagedir /usr/sbin/grpconv");
    }

    
    # run ldconfig to ensure libraries are accounted for
    system("chroot $imagedir /sbin/ldconfig");

    return 1;
} # files_post_install

#
## ADDITIONAL FUNCTIONS
#

sub find_imgroot{
# Find a valid imgroot tree
# Input: distro, version
# Output: Path to the tree or 0 if not found.

        my $distro=shift;
        my $version=shift;
        # Split the version to major and minor parts
        my ($maj,$min)=split_version($version);
        # Now loop through the parent directories until an imgroot is found
        # or we hit the top of distinfo.
        my $imgroot=$main::config->distinfo ."/".$distro."/".$maj."/".$min."/imgroot";
        until ((-d $imgroot) || ($imgroot eq $main::config->distinfo."/imgroot")) {
                $imgroot=~s/\/+/\//g; # get rid of any double /
                $imgroot=~s/\/[^\/]+\/imgroot$/\/imgroot/;
        }
        # If we didn't hit the top, return the directory.
        unless (-d $imgroot) {
                return 0;
        } else {
                return $imgroot;
        }

} #find_imgroot

### POD from here down

=head1 NAME
 
SystemInstaller::Package::Rpm - Rpm package installation functions.
 
=head1 DESCRIPTION

This module provides the SystemInstall package API functions for Rpm based
installation. This is the default type of installation when no other modules
have provided a suitable match. This module provides the following API subroutines:
files_find, files_pre_install, files_install, files_post_install.

See the SystemInstaller::Package manpage for details
on the API specification.

=head1 AUTHOR
 
Michael Chase-Salerno <mchasal@users.sf.net>
 
=head1 SEE ALSO

L<SystemInstaller::Package>
 
=cut

1;
