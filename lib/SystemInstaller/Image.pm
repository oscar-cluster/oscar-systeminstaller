package SystemInstaller::Image;

#   $Id$

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
 
#   Copyright (c) 2001 International Business Machines
#                      Michael Chase-Salerno <salernom@us.ibm.com>             
#   Copyright (c) 2004, Revolution Linux Inc, Benoit des Ligneris
#   Copyright (c) 2003-2006 Erich Focht <efocht@hpce.nec.com>
#                           All rights reserved

use strict;

use base qw(Exporter);
use vars qw($VERSION @EXPORT @EXPORT_OK);
use File::Path;
use SystemInstaller::Log qw (verbose);
use Carp;
 
@EXPORT = qw(init_image del_image write_scconf cp_image split_version
	     umount_recursive); 
@EXPORT_OK = qw(init_image del_image write_scconf cp_image split_version
	     umount_recursive); 
 
$VERSION = sprintf("%d", q$Revision$ =~ /(\d+)/);

my @MODS=qw(Kernel_ia64 Kernel_iseries Kernel_x86);
use SystemInstaller::Image::Kernel_x86;
use SystemInstaller::Image::Kernel_ia64;
use SystemInstaller::Image::Kernel_iseries;

use SystemInstaller::Log qw(verbose get_verbose);

sub init_image {
# Creates the image directories 
#
# Input: 	Image root directory
# Returns:	1 if failure, 0 if ok

	my $root = shift;
# 	mkpath(["$root/usr/lib","$root/var","$root/home","$root/tmp","$root/boot","$root/proc","$root/root"]);
	mkpath(["$root/etc/systemimager/partitionschemes"]);
	mkpath(["$root/etc/systemconfig"]);
	# Check that something worked.
	unless (-d "$root/usr/lib" ){
		return 1;
	}
	return 0;
} #init_image

sub del_image {
# Removes an image
#
# Input: 	Image root directory
# Returns:	1 if failure, 0 if ok

	my $image = shift;
	my $CMD=$main::config->delimage ." ". $image;
	&verbose("$CMD");
	if (system($CMD)){
		return 1;
	}
	return 0;
} #del_image

sub cp_image {
# Makes a copy of an image.
#
        my %vars = (
                source => undef,
                destination => undef,
                @_,
        );
        &verbose("Checking cp_image input.");
        foreach my $required (qw(source destination)) {
                if (!$vars{$required}) {
                        carp("Required variable $required not provided");
                        return undef;
                }
        }
	my $cmd=$main::config->cpimage;
        if (&get_verbose) {
                $cmd.=" -verbose";
        }
        $cmd.=" $vars{source} $vars{destination}";
        &verbose($cmd);
	if (system($cmd)){
		return 1;
	}
	return 0;



} # cp_image

sub write_scconf {
        # Write the boot and kernel info to the systemconfig.conf file.
        #
        # Input: imagedir, root device, boot device
        # Returns: Boolean
        my $imagedir=shift;
        my $root=shift;
        my $boot=shift;
        my $scfile="$imagedir/etc/systemconfig/systemconfig.conf";

        # Make sure we have all input
        unless ($imagedir && $root && $boot) {
                carp("Missing required input!");
                return 0;
        }
        unless (open(SCFILE,">$scfile")) {
                carp("Cannot open System Configurator conf file $scfile!");
                return 0;
        }
        # Print the first part of the file, the static data and the boot 
        # devices.
        print SCFILE "# systemconfig.conf written by systeminstaller.\n";
        print SCFILE "CONFIGBOOT = YES\nCONFIGRD = YES\n\n[BOOT]\n";
        print SCFILE "\tROOTDEV = $root\n\tBOOTDEV = $boot\n";

        # Now find the kernels.
        my @kernels=find_kernels($imagedir);
        my $i=0;
        my $default=0;

        foreach (@kernels){
                my ($path,$label)=split;
                # Make sure its not longer than 15 characters
		# (why actually? grub doesn't have this limitation)
		#$label=substr($label,0,15);
		unless ($default){
			print SCFILE "\tDEFAULTBOOT = $label\n\n";
			$default++;
		}
		print SCFILE "[KERNEL$i]\n";
		print SCFILE "\tPATH = $path\n";
		print SCFILE "\tLABEL = $label\n\n";
		$i++;
	}        
	close SCFILE;
	return 1;
} #write_scconf

sub find_kernels {
# Builds the systemconfig.conf
# Input: pkg path, imagedir, force flag
# Output: boolean success/failure

        my $imgpath=shift;
        my @kernels;

        foreach (@MODS){
		my $class="SystemInstaller::Image::$_";
                if ($class->footprint($imgpath)) {
                        return $class->find_kernels($imgpath);
                }
        }
        return 1;

} #find_kernels

#
# Unmount /proc from an image. This needs to be recursive.
#
sub umount_recursive {
    my ($path) = @_;

    for (`grep "$path/" /proc/mounts`) {
	chomp;
	if (m, ($path\S+) ,) {
	    my $d = $1;
	    print "dir: $d\n";
	    next if ($d =~ /^\s*$/);
	    next if (!scalar(`grep " $d " /proc/mounts`));
	    &umount_recursive($d);
	}
    }
    print "      : unmounting $path\n";
    !system("umount $path")
	or croak("Couldn't umount $path!: $!");
}


### POD from here down

=head1 NAME
 
SystemInstaller::Image - Interface to Images for SystemInstaller
 
=head1 SYNOPSIS   

 use SystemInstaller::Image;

 if (&SystemInstaller::Image::init_image("/var/images/image1") {
	printf "Image initialization failed\n";
 }

=head1 DESCRIPTION

SystemInstaller::Image provides an interface to creating images
for SystemInstaller.

=head1 AUTHOR
 
Michael Chase-Salerno <mchasal@users.sourceforge.net>
 
=head1 SEE ALSO

 
=cut

1;
