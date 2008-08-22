package SystemInstaller::Package;

#   $Header: /cvsroot/systeminstaller/systeminstaller/lib/SystemInstaller/Package.pm,v 1.57 2003/04/11 21:09:03 mchasal Exp $

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
 
#   Michael Chase-Salerno <salernom@us.ibm.com>             
#   Modified by Amit Pabalkar <amit.p@californiadigital.com>
use strict;

use base qw(Exporter);
use vars qw($VERSION @EXPORT @EXPORT_OK);
use SystemInstaller::Log qw (verbose);
use Carp;
use Cwd;

@EXPORT = qw(pkg_install);
@EXPORT_OK = qw(pkglist_read files_find files_install);
 
$VERSION = sprintf("%d", q$Revision$ =~ /(\d+)/);

use SystemInstaller::Package::PackManSmart;
use SystemInstaller::Package::Deb;
use SystemInstaller::Package::Deboot;

my @PKGMODS=qw(PackManSmart Deboot Deb Suse RpmNoScripts UpdateRpms Rpm);

sub pkg_install ($$$@) {
# Head sub to do all the steps, use this or the individual subs below.
# Input:         pkg dir name, image dir name, arch, list of pkg files
# Output:        boolean
        my $pkgpath=shift;
        my $imgpath=shift;
        my $arch=shift;
        my @pkglistfiles=@_;
        my @pkglist; my @pkgfiles;
        my $outlines=13; #Extra lines of output for GUI count below.

	#
	# skipping check for package path because of yume pools,
	# they can be URLs and concatenated by ","
	#
        #&verbose("Checking package path.");
        #unless (-e $pkgpath) {
        #        carp("Package location $pkgpath not found!");
        #        return 0;
        #}
        &verbose("Reading package list files.");
        unless (@pkglist=&pkglist_read(@pkglistfiles)) {
                carp("Failed to read package files.");
                return 0;
        }

        &verbose("Checking for required packages");
        my @missing;
        if (@missing=&check_reqd_pkgs(@pkglist)){
                my $pkgstring=join("\n\t",@missing);
                carp("WARNING: Missing required packages, continuing:\n\t$pkgstring\n");
        }

        
        # Display the line count for GUI status bars.
        my $linecount = ((scalar(@pkglist) * 2) + $outlines);
        &verbose("Expected lines of output: $linecount");

        &verbose("Finding package install files.");
        unless (@pkgfiles=&files_find($pkgpath, $arch, @pkglist)) {
                carp("Failed to find files for all packages.");
                return 0;
        }

        &verbose("Performing pre-install.");
        unless (&files_pre_install($pkgpath, $imgpath)) {
                carp("Pre-install failed.");
                return 0;
        }
        &verbose("Installing package install files.");
	my @errs;
        unless (&files_install($pkgpath, $imgpath, \@errs, @pkgfiles)) {
		local *A;
		open A, "> $ENV{OSCAR_HOME}/tmp/sin-install.error";
		print A @errs."\n";
		close A;
                carp("Failed to install files.\n".join("\n",@errs));
                if ($main::config->pkginstfail) { return 0;};
        }
        &verbose("Performing post-install.");
        unless (&files_post_install($pkgpath, $imgpath)) {
                carp("Post-install failed, your image may not be quite right.");
                if ($main::config->postinstfail) { return 0;};
        }
        return 1;

} #pkg_install

sub pkglist_read {
# Read in the specified files
# Input: 	list of pkg files.
# Returns:	list of pkgs or null if failure

        my @filelist=@_;
        my @pkglist;
	my $line; 
	local *PFILE;
        foreach my $fn (@filelist) {
        	&verbose("Opening package file $fn.");
        	if (! open(PFILE,$fn)) {
                        carp("Unable to open package file $fn");
        		return;
        	}
        	&verbose("Parsing package file.");
        	while ($line=<PFILE>) {
        		chomp $line;
		        if (($line =~ /^\s*$/) || ($line =~ /^#/)) {
			        next;
                        }
                        $line=~s/\s//g;
        		# Found a package name, save it
        	        push (@pkglist,$line);
        	}
        	close(PFILE);
        }
        # get rid of dupes and return the list
        &verbose("Deleting duplicate package entries.");
        return &pkglist_uniq(@pkglist);
} #pkglist_read

sub pkglist_uniq {
# Gets rid of dupe package names while maintaining the order.
# Input:        list of pkgs
# Output:       list of unique pkgs 

	my $ptype; my $pkg;
	my %found=();
	my @upkgs=();

	foreach $pkg (@_) {
		if (! defined $found{$pkg} ) {
			$found{$pkg}++;
			push (@upkgs,$pkg);	
		}
	}
	return @upkgs;
} #pkglist_uniq

sub check_reqd_pkgs (@) {
        # Ensure that required packages are in the list
        # Input:        list of pkgs
        # Output:       list of missing pkgs or null if OK
        my @pkglist=@_;
        my @req_pkgs=qw(systemconfigurator|opkg-sis-client);
        my @missing=();
        foreach my $pkg (@req_pkgs){
                unless (grep(/^($pkg).*/,@pkglist)) {
                        push(@missing, $pkg);
                }
         }
         return @missing;
}# check_reqd_pkgs

sub files_find {
# Find the filenames corresponding to the package lists
# Input: pkg dir, arch, pkg list
# Output:  file list or null on failure.
        my $path=shift;
        my $arch=shift;
        my @pkglist=@_;

        foreach my $mod (@PKGMODS){
		my $class="SystemInstaller::Package::$mod";
                if ($class->footprint("files",$path)) {
                        &verbose("Finding files with module $class");
                        return $class->files_find($path,$arch,@pkglist);
                }
        }
        return;
} #files_find

sub files_pre_install {
# Perform any pre install actions
# Input: pkg dir, imagedir
# Output:  Boolean
        my $path=shift;
        my $imgpath=shift;
        my @file=@_;

        foreach my $mod (@PKGMODS){
		my $class="SystemInstaller::Package::$mod";
                if ($class->footprint("pre_install",$path)) {
                        &verbose("Performing pre-install with module $class");
                        return $class->files_pre_install($imgpath,$path);
                }
        }
        return;
} #files_pre_install

sub files_install {
# Install the pkgs
# Input: pkg dir, imagedir, file list
# Output:  file list or null on failure.
        my $path=shift;
        my $imgpath=shift;
        my @file=@_;

	print "!!! Files for files_install = ".join(" ",@file)."\n";
        foreach my $mod (@PKGMODS){
		my $class="SystemInstaller::Package::$mod";
                if ($class->footprint("install",$path)) {
                        &verbose("Installing with module $class");
                        return $class->files_install($imgpath,$path,@file);
                }
        }
        return;
} #files_install

sub files_post_install {
# Perform any post install actions
# Input: pkg dir, imagedir
# Output:  Boolean
        my $path=shift;
        my $imgpath=shift;
        my @file=@_;

        foreach my $mod (@PKGMODS){
		my $class="SystemInstaller::Package::$mod";
                if ($class->footprint("post_install",$path,$imgpath)) {
                        &verbose("Performing post-install with module $class");
                        return $class->files_post_install($imgpath,$path);
                }
        }
        return;
} #files_post_install


### POD from here down

=head1 NAME
 
SystemInstaller::Package - Interface to packaging for SystemInstaller
 
=head1 SYNOPSIS   

 use SystemInstaller::Package;

 $location=	"<package file location>";
 $root=		"<image root location>";
 $arch=		"<image architecture>";            
 @filename=	"<package list filenames>";

 unless (&pkg_install($location,$root,$arch,@filename) {
	printf "install failed\n";
 }

=head1 DESCRIPTION

SystemInstaller::Package provides an interface to package installation
for SystemInstaller.

=head1 ARGUMENTS

=over 4

=item $location

The location (directory) that contains the package install files.

=item $root

The directory that will contain the image.

=item $arch

The target architecture for the image.

=item @filename

A list of package list files.

=back

=head1 Module API specification

SystemInstaller::Package uses Perl modules to provide the actual functions
for specific package types. In order to add support for a new package 
type the following must be provided in a perl module file named 
<pkgtype>.pm in the Package subdirectory of the SystemInstaller library.
Additionally, the module name must be added to the @PKGMODS array in 
the Package.pm module. The order of the modules in the array
determines the heirarchy. The Rpm module should remain last as the default.
Finally, a use statement must be added for the new module in the Package.pm
library.

THIS API IS NOT YET FINAL!!! It may (and probably will) change somewhat
in the near future.

=over 4

=item sub files_find($class,$path,$arch,@pkglist)

Find the best files for the given packages. $path contains the location
of the package files, $arch is the desired image architecture, @pkglist
contains the names of the desired packages. Returns: list of filenames 
(without leading directories) or 0 on failure.

=item sub files_pre_install($class,$imgpath,$path)

Perform any required pre-installation action in the image. 
$imgpath contains the root directory for the image, $path contains the 
location of package files.
Returns: 1 on success, 0 on failure.

=item sub files_install($class,$imgpath,$path,@filelist)

Install the package files into the image. $imgpath contains the root
directory for the image, $path contains the location of package files,
@filelist contains the list of filenames as returned from &files_find.
Returns: 1 on success, 0 on failure.

=item sub files_post_install($class,$imgpath,$path)

Perform any required post-installation action in the image. 
$imgpath contains the root directory for the image, $path contains the 
location of package files.
Returns: 1 on success, 0 on failure.

=item sub footprint($class,$mode,$path,$imgpath);

Determine if this modules subroutine for the specific mode should be used.
$path contains the location of the package files. $imgpath is the location
of the image and is only available for B<post_install> and B<kernel> modes.
Returns: 1 if this module's subroutine is to be used, 0 if not.

Valid modes are: 

=over 4

=item files

Finding the best files to use, the &files_find subroutine.

=item pre_install

Before the packages are installed, the &files_pre_install subroutine.

=item install

Installing the packages, the &files_install subroutine.

=item post_install

After the packages are installed, the &files_post_install subroutine.

=back

=back

=head1 AUTHOR
 
Michael Chase-Salerno <mchasal@users.sourceforge.net>
 
=head1 SEE ALSO

L<SystemInstaller::Package::Rpm>
L<SystemInstaller::Package::Deb>
L<SystemInstaller::Package::Suse>
L<SystemInstaller::Package::Turbo>
L<mksiimage>
 
=cut

1;
