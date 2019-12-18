package SystemInstaller::Package::Deb;

#   $Header: /cvsroot/systeminstaller/systeminstaller/lib/SystemInstaller/Package/Deb.pm,v 1.16 2002/08/31 16:19:06 mchasal Exp $

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
 
#   Vasilios Hoffman <greekboy@users.sourceforge.net>

# Debianized by Amit Pabalkar <amit.p@californiadigital.com>
use strict;

use File::Path;
use Data::Dumper;
use SystemInstaller::Log qw(:all);
my $DEBTARBALL;

##TODO
#
#  --> add tar to config file instead of dpkg
#  --> real dpkg -i support!! i.e. apt.
#  --> fix possible path issues inside of chroot
#  --> auto versioning for deb files (use latest)
#  --> interactive support

#
## API FUNCTIONS
#

sub files_find {
# Check that the files exist on the specified media.
# Set the PFILES list to the filenames found.
# Input:	%Pinfo structure
# Returns:	1 if failure, 0 if ok

	my $class=shift;
	my $debdir=shift;
	my $arch=shift;
	my @pkglist=@_;

	my $RC=0; #return code

	#variables used locally
	my ($pkg,$base_tarball);
	my @install_packages;
	my @missing_packages;
	#
	#Check and set the packages of our type in PFILES
	#

	# first, make sure we have a single .tgz file, which is our
	# base system
	$base_tarball = undef;
	foreach $pkg (@pkglist) {
	  if ( $pkg =~ /\.tgz$/ ) {
	    if (not defined $base_tarball) {
	      if ( -e "$debdir/$pkg") {
		$base_tarball = "$debdir/$pkg";
	      }
	    } else {
	      debug("extra base tarballs:  $pkg");
	      $RC = 1;
	    }
	  }
	}

	if (not defined $base_tarball) {
	  verbose("Missing a base tarball, aborting");
	  return 1;
	}
	
	#set base tarball
	$DEBTARBALL = $base_tarball;
	debug("Base tarball is $base_tarball");	
	
	#create the list of package files (PFILES)
	foreach $pkg (@pkglist) {
	  #find the "best" file... which means:
	  #  1)  if the file was a full filename, use it
	  #  2)  if it exists with a .deb extension, use that
	  #  3)  otherwise, pick the latest versioned .deb file <-- not implemented yet

	  #skip the base tarball
	
	  if ( "$debdir/$pkg" eq "$base_tarball" ) {
	    next;
	  }
	  if ( -e "$debdir/$pkg" ) {
	    push @install_packages,"$debdir/$pkg";
	  } elsif ( -e "$debdir/$pkg.deb" ) {
	    push @install_packages,"$debdir/$pkg.deb";
	  } else {
	    #for now, it is missing
	    push (@missing_packages,$pkg);
	    verbose("missing packages\n");
    	    $RC = 1;
	  }
	}

	#verbose(Dumper($Pinfo));

	return @install_packages;

} #files_find

sub files_pre_install {
        # Nothing needed for now
        return 0;
}

sub files_install {
# Install the packages.
# Input:	%Pinfo structure
# Returns:	1 if failure, 0 if ok

	my $class=shift;
	my $imgpath=shift;
	my $pkgpath=shift;
	my $errs=shift;
	my @packages=@_;

	my $RC=0;
	my $base_tarball = $DEBTARBALL;
	
	#now we change to that directory, to avoid a possible gnu-only
	#flag on tar
	chdir("$imgpath/");

	#untar base into here
	my $redir;
	if (get_debug) {
	  $redir = "";
	} else {
	  $redir = ">/dev/null";
	}
	if (system("tar zxvf $base_tarball $redir")) {
	  verbose("Failed to untar $base_tarball, aborting");
	  return $RC;
	}
	
	#copy our dpkg files into here
	my $file;
	foreach $file (@packages) {
	  if(system("cp $file $imgpath/tmp")) {
	    verbose("failed to copy $file to chroot image, aborting");
	    return 0;
	  }
	}

	#chroot into the image
	my $pid = fork;
	
	if ($pid == 0) {
	    chroot ($imgpath) or die "failed to chroot";

	    #prep image for the rest of the install
	    if ( configure_image() == 1 ) {
		verbose("failed to configure image\n");
		return 0;
	    }
	    #dpkg install the rest
	    if ( dpkg_inst() == 1 ) {
		verbose("Deb installation failed.\n");
		return 0;
	    }
	    exit;
	}
	wait; 	
	return 1;
	
    } #install

sub files_post_install {
        # Nothing needed for now
        return 0;
}

sub footprint {
# Look at a directory and determine if it looks like rpms.
# Input:        Directory name
# Returns:      Boolean of match
        my $class=shift;
        my $mode=shift;
        my $path=shift;
        if (glob "$path/*.deb") {
                return 1;
                
        }
        return 0;

} #footprint

#
## OTHER FUNCTIONS
#

sub configure_image {
# Configure the chrooted image before installing any packages
# Input:	%Pinfo structure
# Returns:	1 if failure, 0 if ok

#  my $Pinfo = shift;

  #first we run pwconv to create shadow password files
  if (system("/usr/sbin/pwconv")) {
    verbose("failed to run pwconv, aborting");
    return 1;
  }

  #now we remove unconfigured.sh
  if (system("rm -f /sbin/unconfigured.sh")) {
    verbose("failed to remove unconfigured.sh");
    return 1;
  }

  #rest of it to go here when I find it

} #configure_image

sub dpkg_inst {
# dpkg install the rest of the files
# Input:	%Pinfo structure
# Returns:	1 if failure, 0 if ok

#  my $Pinfo = shift;
  my $redir;

  if (get_debug) {
    $redir = "";
  } else {
    $redir = "> /dev/null";
  }

  if (system("DEBIAN_FRONTEND=noninteractive /usr/bin/dpkg -i /tmp/*.deb ")) {
        verbose("failed to run dpkg -i");
	return 1;
  }	
    
} #dpkg_inst

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
