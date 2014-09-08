package SystemInstaller::Package;

#   $Header: /cvsroot/systeminstaller/systeminstaller/lib/SystemInstaller/Package.pm,v 1.57 2003/04/11 21:09:03 mchasal Exp $

#   Copyright (c) 2001 International Business Machines
#   Copyright (c) 2008 Geoffroy Vallee <valleegr@ornl.gov>
#                      Oak Ridge National Laboratory
#                      All rights reserved.
 
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
#   Mostly rewrote by Geoffroy Vallee for systeminstaller-oscar
#       <valleegr@ornl.gov>

use base qw(Exporter);
use vars qw($VERSION @EXPORT @EXPORT_OK);
use SystemInstaller::Log qw (verbose);
use SystemInstaller::Package::PackManSmart;
use OSCAR::RepositoryManager;
use OSCAR::Opkg;
use OSCAR::Utils;
use OSCAR::PackManDefs;
use Carp;
use Cwd;

@EXPORT = qw(pkg_install);
@EXPORT_OK = qw(pkglist_read files_find files_install);

$VERSION = sprintf("%d", q$Revision$ =~ /(\d+)/);

################################################################################
# Basic function that creates the basic image, including OSCAR packages. This  #
# is actually only the SystemInstaller entry point to use ORM/PackMan 
#                                                                              #
# Input:        distro, the target distribution id (OS_Detect syntax).         #
#               pkg dir name,                                                  #
#               image dir name,                                                #
#               arch,                                                          #
#               list of pkg files                                              #
# Output:       0 if error, 1 else.                                            #
################################################################################
sub pkg_install ($$$$@) {
    my ($distro, $pkgpath, $imgpath, $arch, @pkglistfiles) =@_;
    my (@pkglist, @pkgfiles);
    my $outlines=13; # Extra lines of output for GUI count below.

    my $rm;
    if (defined $distro) {
        $rm = OSCAR::RepositoryManager->new (distro => $distro);
    } elsif (defined $pkgpath) {
        $rm = OSCAR::RepositoryManager->new (repo => $pkgpath);
    } else {
        carp "ERROR: no distro or repos defined";
        return 0;
    }

    if (!defined $rm) {
        carp "ERROR: Invalid RepositoryManager object";
        return 0;
    }

    # We set the chroot path so PackMan knows what to do (including the image
    # bootstrap.
    $rm->{pm}->{ChRoot} = $imgpath;

    verbose "---> Package files: " .join (" ", @pkglistfiles)."\n";

    # We create the list of pkg to install from the different files defining the
    # needed files.
    foreach my $pkgs_file (@pkglistfiles) {
        open (FILE, "$pkgs_file");
        while (my $line = <FILE>) {
            chomp ($line);
            # We ignore invalid package names.
            next if (OSCAR::Utils::trim($line) eq "");
            push (@pkglist, $line) if (OSCAR::Utils::is_a_comment ($line) == 0);
        }
        close (FILE);
    }

    # We add the list of core OPKGs, client side.
#    my @core_opkgs = OSCAR::Opkg::get_list_core_opkgs ();
#    verbose "---> Core OPKGs: ".join(" ", @core_opkgs)."\n";

#    push (@pkglist, map { "opkg-".$_."-client" } @core_opkgs);
    verbose "---> Package list: ".join(" ", @pkglist)."\n";

    use OSCAR::PackManDefs;
    my ($err, $output) = $rm->install_pkg ($imgpath, @pkglist);
    if ($err != OSCAR::PackManDefs::PM_SUCCESS()) {
        print STDERR "WARNING: Impossible to install ".join(', ',@pkglist)." ($err, $output)\n";
        # The error handling from ORM is not yet perfect, we display
        # messages if we think there is an error during package installation
        # but we do not stop.
        # return 0;
    }

    return 1;
} # pkg_install

# sub pkglist_read {
# # Read in the specified files
# # Input: 	list of pkg files.
# # Returns:	list of pkgs or null if failure
# 
#         my @filelist=@_;
#         my @pkglist;
# 	my $line; 
# 	local *PFILE;
#         foreach my $fn (@filelist) {
#         	&verbose("Opening package file $fn.");
#         	if (! open(PFILE,$fn)) {
#                         carp("Unable to open package file $fn");
#         		return;
#         	}
#         	&verbose("Parsing package file.");
#         	while ($line=<PFILE>) {
#         		chomp $line;
# 		        if (($line =~ /^\s*$/) || ($line =~ /^#/)) {
# 			        next;
#                         }
#                         $line=~s/\s//g;
#         		# Found a package name, save it
#         	        push (@pkglist,$line);
#         	}
#         	close(PFILE);
#         }
#         # get rid of dupes and return the list
#         &verbose("Deleting duplicate package entries.");
#         return &pkglist_uniq(@pkglist);
# } #pkglist_read
# 
# sub pkglist_uniq {
# # Gets rid of dupe package names while maintaining the order.
# # Input:        list of pkgs
# # Output:       list of unique pkgs 
# 
# 	my $ptype; my $pkg;
# 	my %found=();
# 	my @upkgs=();
# 
# 	foreach $pkg (@_) {
# 		if (! defined $found{$pkg} ) {
# 			$found{$pkg}++;
# 			push (@upkgs,$pkg);	
# 		}
# 	}
# 	return @upkgs;
# } #pkglist_uniq
# 
# # Ensure that required packages are in the list
# #
# # Input:        list of pkgs
# # Output:       list of missing pkgs or null if OK
# #
# # TODO: do we really need that since we deal automatically with dependencies
# # now and that we install automatically all core packages?
# # DEPRECATED???
# sub check_reqd_pkgs (@) {
#     my @pkglist=@_;
#     my @req_pkgs=qw(systemconfigurator|opkg-sis-client);
#     my @missing=();
#     foreach my $pkg (@req_pkgs){
#         unless (grep(/^($pkg).*/, @pkglist)) {
#             push(@missing, $pkg);
#         }
#     }
#     return @missing;
# } # check_reqd_pkgs
# 
# # Find the filenames corresponding to the package lists
# # Input: pkg dir, arch, pkg list
# # Output:  file list or null on failure.
# sub files_find {
#     my $path=shift;
#     my $arch=shift;
#     my @pkglist=@_;
# 
#     foreach my $mod (@PKGMODS){
#         my $class="SystemInstaller::Package::$mod";
#         if ($class->footprint("files",$path)) {
#             &verbose("Finding files with module $class");
#             return $class->files_find($path,$arch,@pkglist);
#         }
#     }
#     return undef;
# } # files_find
# 
# ################################################################################
# # Perform any pre install actions.                                             #
# #                                                                              #
# # Input:    pkg dir,                                                           #
# #           imagedir                                                           #
# # Output:   0 if error, 1 else.                                                #
# ################################################################################
# sub files_pre_install {
#     my $path=shift;
#     my $imgpath=shift;
#     my @file=@_;
# 
#     foreach my $mod (@PKGMODS){
#         my $class="SystemInstaller::Package::$mod";
#         if ($class->footprint("pre_install",$path)) {
#             &verbose("Performing pre-install with module $class");
#             return $class->files_pre_install($imgpath,$path);
#         }
#     }
#     return undef;
# } # files_pre_install
# 
# sub files_install {
# # Install the pkgs
# # Input: pkg dir, imagedir, file list
# # Output:  file list or null on failure.
#         my $path=shift;
#         my $imgpath=shift;
#         my @file=@_;
# 
# 	print "!!! Files for files_install = ".join(" ",@file)."\n";
#         foreach my $mod (@PKGMODS){
# 		my $class="SystemInstaller::Package::$mod";
#                 if ($class->footprint("install",$path)) {
#                         &verbose("Installing with module $class");
#                         return $class->files_install($imgpath,$path,@file);
#                 }
#         }
#         return;
# } #files_install
# 
# sub files_post_install {
# # Perform any post install actions
# # Input: pkg dir, imagedir
# # Output:  Boolean
#         my $path=shift;
#         my $imgpath=shift;
#         my @file=@_;
# 
#         foreach my $mod (@PKGMODS){
# 		my $class="SystemInstaller::Package::$mod";
#                 if ($class->footprint("post_install",$path,$imgpath)) {
#                         &verbose("Performing post-install with module $class");
#                         return $class->files_post_install($imgpath,$path);
#                 }
#         }
#         return;
# } #files_post_install


### POD from here down

1;

__END__

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
