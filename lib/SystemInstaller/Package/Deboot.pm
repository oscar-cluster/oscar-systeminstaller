package SystemInstaller::Package::Deboot;

#   $Header: /cvsroot/systeminstaller/systeminstaller/lib/SystemInstaller/Package/Deboot.pm,v 1.1 2003/04/11 21:09:04 mchasal Exp $

#   Copyright (c) 2001 International Business Machines
#   Copyright (c) 2003 Hewlett-Packard Development Company
 
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
 
#   Debootstrapitized by dann frazier <dannf@hp.com>
#
use strict;

use File::Path;
use Data::Dumper;
use SystemInstaller::Log qw(:all);

#
## API FUNCTIONS
#

sub files_find {
# Check that the files exist on the specified media.
# Input:	class, path, arch, pkglist
# Returns:	1 if failure, 0 if ok

# There's really nothing we can check for here without being further
# along in the process.  Just return.
	my $class = shift;
	my $path = shift;
	my $arch = shift;
	my @pkglist = @_;

	return @pkglist;
	
} #files_find

sub files_pre_install {
# Perform any pre-installation steps
# Input:	class, image path, package source
# Returns:	1 on success, 0 on failure

	my $class=shift;
	my $imgpath=shift;
	my $pkgpath=shift;

	(my $mirror, my $suite) = get_debootstrap_opts($pkgpath);
	if ($mirror eq undef or $suite eq undef) { 
	    verbose("Failed to retreive debboot info from $pkgpath.");
	    return 0; 
	}

	my $RC = debootstrap($imgpath, $suite, $mirror);
	
	return $RC;
} #files_pre_install

sub files_install {
# Install the packages.
# Input:	image dir, package source
# Returns:	1 if failure, 0 if ok

	my $class=shift;
	my $imgpath=shift;
	my $pkgpath=shift;
	my $errs=shift;
	my @packages=@_;

	$pkgpath = "/tmp/sources.list";
	write_sources_list($pkgpath, 
			   "$imgpath/etc/apt/sources.list") or return 1;
	!system("chroot $imgpath apt-get update") or return 1;
	install_fake_start_stop_daemon($imgpath) or return 1;
	shutup_debconf($imgpath);
	my $cmd = "chroot $imgpath apt-get -y install";
	foreach my $pkg (@packages) {
	    $cmd .= " $pkg";
	}
	!system($cmd) or return 1;
	uninstall_fake_start_stop_daemon($imgpath) or return 1;
	openup_debconf($imgpath);
}

sub files_post_install {
        # Nothing needed for now
        return 1;
}

sub footprint {
# Look at a directory and determine if it looks like rpms.
# Input:        Directory name
# Returns:      Boolean of match
        my $class=shift;
        my $mode=shift;
        my $path=shift;
	my $imgpath = shift;
	
        if (-f $path) {
	    open FILE, "<$path" or return 0;
	    while (<FILE>) {
		if (/\s*deboot\s.*$/) {
		    return 1;
		}
	    }
        }
        return 0;
} #footprintd

#
## OTHER FUNCTIONS
#

sub get_debootstrap_opts {
# Extracts the debootstrap info from a SIS style sources.list file.
# Input:	sources.list path
# Returns:	mirror, suite on success, undef on failure
	my $sources=shift;
	
	open(SOURCES, "<$sources") or return undef;
	while (<SOURCES>) {
	    if (/^\s*deboot\s*(\S*)\s*(\S*)\s*$/) {
		close(SOURCES);
		return $1, $2;
	    }
	}
	verbose("debboot entry not found in sources.list");
	return undef;
}

sub shutup_debconf {
# Preconfigure the debconf database for maximum non-interactivity
# Input:	image path
# Returns:	1 on success, 0 on failure.
	my $imgpath = shift;
#	my $active = 0;

	my $config = "$imgpath/var/cache/debconf/config.dat";

	verbose("Configuring debconf to use the Noninteractive interface.");
#	rename $config, "${config}.SIS.tmp" or return 1;
	    
#	open(OLD_CONFIG, "<${config}.SIS.tmp") or return 1;
#	open(NEW_CONFIG, ">$config") or close OLD_CONFIG and return 1;
#	while (<CONFIG>) {
#	    verbose("Read $_");
#	    if (/^Name: debconf\/frontend$/) {
#		$active = 1;
#	    }
#	    if ($active == 1 and /^\s*$/) {
#		$active = 0;
#	    }
#	    if ($active == 1 and /^Value: Dialog$/) {
#		print NEW_CONFIG "Value: Noninteractive\n";
#		verbose("Debconf configured ok.");
#		$active = 0;
#		next;
#	    }
#	    print NEW_CONFIG;
#	}
#	close OLD_CONFIG;
	open(NEW_CONFIG, ">>$config") or close OLD_CONFIG and return 1;
	print NEW_CONFIG << 'EOF';
Name: debconf/frontend
Template: debconf/frontend
Value: Noninteractive
Owners: debconf
Flags: seen
EOF
	close NEW_CONFIG;
	return 0;
}

sub openup_debconf {
# Undo what shutup_debconf did, removing the Noninteractive setting.
# Input:	image path
# Returns:	1 on success, 0 on failure.
	my $imgpath = shift;
	my $active = 0;

	my $config = "$imgpath/var/cache/debconf/config.dat";
	my $tmp = "$imgpath/var/cache/debconf/config.dat.SIS.tmp";

	verbose("Configuring debconf to use the Dialog interface.");
	rename $config, $tmp or return 1;
	    
	open(OLD_CONFIG, "<$tmp") or return 1;
	open(NEW_CONFIG, ">$config") or close OLD_CONFIG and return 1;
	while (<CONFIG>) {
	    if (/^Name: debconf\/frontend$/) {
		$active = 1;
	    }
	    if ($active == 1 and /^\s*$/) {
		$active = 0;
	    }
	    if ($active == 1 and /^Value: Noninteractive$/) {
		print NEW_CONFIG "Value: Dialog\n";
		$active = 0;
		next;
	    }
	    print NEW_CONFIG;
	}
	close OLD_CONFIG;
	close NEW_CONFIG;
	return 0;
}

sub write_sources_list {
# Strip the input sources.list of all deboot options, and write it out.
# Input:	sources.list src, sources.list dest
# Returns:	1 on success, 0 on failure.
	my $src=shift;
	my $dest=shift;
	
	open(SRC, "<$src") or return 0;
	open(DEST, ">$dest") or close(SRC) and return 0;
	while (<SRC>) {
	    unless (/^\s*deboot\s*(\S*)\s*(\S*)\s*$/) {
		print DEST;
	    }
	}
	close(SRC);
	close(DEST);
	return 1;
}

sub install_fake_start_stop_daemon {
# puts a fake start-stop-daemon in place, to prevent daemons from
# starting on the build system.
# Input: image path
# Output: 0 on success, non-zero on failure.

	my $imgpath=shift;

	verbose("Installing fake start-stop-daemon.");
	rename "$imgpath/sbin/start-stop-daemon", 
	    "$imgpath/sbin/start-stop-daemon.SIS.tmp" or return 1;
	open(SSD, ">$imgpath/sbin/start-stop-daemon") or return 1;
	print SSD "#!/bin/sh\n";
	print SSD "echo\n";
	print SSD "echo Warning: Fake start-stop-daemon called, doing nothing\n";
	close SSD;
	chmod 0755, "$imgpath/sbin/start-stop-daemon" or return 1;
}
	    

sub uninstall_fake_start_stop_daemon {
# puts a fake start-stop-daemon in place, to prevent daemons from
# starting on the build system.
# Input: image path
# Output: 0 on success, non-zero on failure.

	my $imgpath=shift;
	
	verbose("Uninstalling fake start-stop-daemon.");
	unlink "$imgpath/sbin/start-stop-daemon" or return 1;
	rename "$imgpath/sbin/start-stop-daemon.SIS.tmp", 
	"$imgpath/sbin/start-stop-daemon" or return 1;
}	    

sub debootstrap ($$$) {
# debootstrap is used to install the base system into a chroot
# Input:      target, suite, mirror
# Returns:    0 if failure, 1 if ok
    my $target = shift;
    my $suite = shift;
    my $mirror = shift;

    my $cmd = "debootstrap $suite $target $mirror";
    verbose("Executing $cmd");
    if (system($cmd)) {
	    verbose("Failed to debootstrap, aborting.");
	    return 0;
    }
    ## debootstrap umounts proc within the image.  remount it here.
    ## if it fails, assume its a version of debootstrap that doesn't umount
    ## for us, and don't return an error.
    system("mount proc $target/proc -t proc");

    return 1;
}

### POD from here down

=head1 NAME
 
SystemInstaller::Package::Deb - Debian packaging for SystemInstaller
 
=head1 SYNOPSIS

 use SystemInstaller::Package::Deb;

 $Pinfo{PTYPES}{Deb}=	"<list of Debian packages>";
 $Pinfo{root}=		"<image root location>";
 $Pinfo{arch}=		"<image architecture>";

 if ( SystemInstaller::Package::Deb->check_files(\%Pinfo) ) {
	print "files missing\n";
 }
 if ( SystemInstaller::Package::Deb->install(\%Pinfo) ) {
	print "install failed\n";
 }

=head1 DESCRIPTION

SystemInstaller::Package::Deb provides the specific functions for
SystemInstaller to install debian packages.

It reads the package list from $Pinfo{PTYPES}{Deb} and based on the
information there, checks and installs the packages.

=head1 FUNCTIONS

check_files(\%Pinfo)

       Checks that the .deb files exist, and attempts to clear up any
       ambiguity over the actual full filename.  It references the
       following elements from the %Pinfo structure:

              $Pinfo{arch}		architecture
              $Pinfo{location}	package file location
       	$Pinfo{PTYPES}{Deb}	list of .deb packages to check

       It creates the following lists:
              $Pinfo{PFILES}{Deb} 	list of full filenames.
              $Pinfo{MISSING} 	list of missing .deb packages.

install(\%Pinfo)

     Installs the packages. It references the following elements of
     the %Pinfo structure.

       	$Pinfo{location}	package file location
       	$Pinfo{root}	The image root to install to
       	$Pinfo{PFILES}{Deb}  list of .deb filenames to install

     The install function must be run with the full powers of root,
     since installed files must be given the proper ownerships and
     permissions.  Also, for debian packaging a successful chroot()
     system call must be made in order to properly install packages.

=head1 AUTHOR

Vasilios Hoffman <greekboy@users.sourceforge.net>

=head1 SEE ALSO

L<SystemInstaller::Package>

=cut

1;
