package SystemInstaller::PackageBest::Rpm;

#   $Header: /cvsroot/systeminstaller/systeminstaller/lib/SystemInstaller/PackageBest/Rpm.pm,v 1.6 2002/11/07 20:54:38 mchasal Exp $

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
use strict;
use Carp;
use POSIX;

use vars qw($VERSION);

$VERSION = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);

#
## API FUNCTIONS
#

sub footprint {
# Look at a directory and determine if it looks like rpms.
# Input:        Directory name
# Returns:      Boolean of match
	my $class=shift;
        my $path=shift;
        if (glob "$path/*.rpm") {
                return 1;
        }
        return 0;

} #footprint


sub find_files {
        # Finds the best version of files to use based on an rpm list
        # Input:  a parameter list containing the following:
        #       PKGDIR  The location of the packages
        #       PKGLIST A reference to a list of desired packages
        #       ARCH    The target archtecture, default: current arch
        #       RPMRC   The rpmrc filename, default: /usr/lib/rpm/rpmrc
        #       CACHEFILE The name for the cachefile, default: .pkgcache
        # 
        # Output: A hash whose keys are the package name and whose
        #         values are the filenames.

        my $class=shift;
        my %args = (
                ARCH            => "",
                RPMRC           => "",
                RPMCMD          => "",
                CACHEFILE       => "",
                PKGDIR          => "",
                PKGLIST         => [],
                @_,
        );

        my @compatlist; my $RPM_TABLE; 

        unless (@compatlist=gen_compat_list(%args->{ARCH},%args->{RPMRC})) {
                return;
        }
        unless ($RPM_TABLE=populate_rpm_table(%args->{PKGDIR},%args->{CACHEFILE})) {
                return;
        }

        return find_best_files($RPM_TABLE,\@compatlist,@{%args->{PKGLIST}});
} #find_files


sub cache_gen {
# Generate/update the cache lists
# Input: dir name, force flag
# Output: boolean success/failure

        my $class=shift;
        my %args = (
                ARCH            => "",
                RPMRC           => "",
                CACHEFILE       => "",
                PKGDIR          => "",
                FORCE           => "",
                PKGLIST         => [],
                @_,
        );
        my %CSIZES;
        my %CLINES;
        my %FSIZES;
        local *PKGDIR;
	my $rpmcmd="/bin/rpm";
        my $cachefile=%args->{CACHEFILE};
        my $path=%args->{PKGDIR};
        my $force=%args->{FORCE};

        unless ($cachefile =~ /^\//) {
                $cachefile=$path."/".$cachefile;
        }

        unless (opendir(PKGDIR,$path)) {
                carp("Can't open package directory $path");
                return 0;
        }
        while($_ = readdir(PKGDIR)) {
                my $file = "$path/$_";
                if($file !~ /\.rpm$/) {next;}
                my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($file);
                $FSIZES{$_}=$size;
        }
        if ((!$force) && (-e "$cachefile")) {
                unless (open(CACHE,"<$cachefile")) {
                        carp("Can't open cachefile $cachefile");
                        return 0;
                }
                while (<CACHE>){
                        chomp;
                        my ($name, $version, $release, $arch, $file, $size, $srpm) = split;
                        $CSIZES{$file}=$size;
                        $CLINES{$file}=$_;
                }
                close(CACHE);
        }
        # Check that all files in the dir first.
        foreach (keys(%FSIZES)) {
                # Check if the file is in the cache at all
                if (! defined $CSIZES{$_}) {
                        # If not, add a blank entry
                        $CLINES{$_}="";
                }
                # Now see if the size is the same
                if ($FSIZES{$_} != $CSIZES{$_}){
                        # If not, blank the entry.
                        $CLINES{$_}="";
                }
        }
        foreach (keys(%CSIZES)) {
                if (! defined $FSIZES{$_}) {
                        # If the file isn't around, undef it in
                        # the hash
                        undef ($CLINES{$_});
                }
                if ($FSIZES{$_} != $CSIZES{$_}){
                        # If the sizes don't match, blank it
                        $CLINES{$_}="";
                }
        }
        unless (open(CACHE,">$cachefile")) {
                carp("ERROR: Couldn't open cachefile $cachefile");
                return 0;
        }
        foreach (keys %CLINES) {
                my $file = "$path/$_";
                if(!-f $file) {next;}
                if ($CLINES{$_} eq "") {
                        my $CMD = "$rpmcmd -qp --qf '\%{NAME} \%{VERSION} \%{RELEASE} \%{ARCH} \%{SOURCERPM}' $file 2> /dev/null";
                        my $output = `$CMD`;
                        my ($name, $version, $release, $arch, $srpm) = split (/\s+/, $output);
                        # Do some sanity checking to see that name is actually there
                        if($name) {
                                my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($file);
                                print CACHE "$name $version $release $arch $_ $size $srpm\n";
                        } else {
                                carp("Unable to query rpm file, $file with command $CMD.");
                        }
                } else {
                        print CACHE "$CLINES{$_}\n";
                }
        }
        close(CACHE);
        return 1;

} #cache_gen
#
### SECONDARY FUNCTIONS ###
#

sub find_best_files {
    # Finds the highest versions and best architectures for rpms
    # Input: Ref to the rpm table info
    #        Ref to the ordered list of compatable rpms
    #        List of rpms desired
    # Output: filelist or null.
    my $RPM_TABLE=shift;
    my $compatlist=shift;
    my @rpms = @_;
    my %files;
    my $missing;
    my $file;
    my $pkg;
    my $version; my $release; my $arch;

    foreach my $rpm (@rpms) {
        my $arch = find_best_arch($RPM_TABLE,$compatlist,$rpm);
        if(!$arch) {
                carp("Couldn't find file for $rpm.");
                $missing++;
                next;
        }

        if (defined $RPM_TABLE->{$arch}->{$rpm}->{FILENAME}) {
                $file=$RPM_TABLE->{$arch}->{$rpm}->{FILENAME};
                $pkg=$RPM_TABLE->{$arch}->{$rpm}->{PKGNAME};
        } else {
                my $version = find_best(keys %{$RPM_TABLE->{$arch}->{$rpm}});
                if(!defined($version)) {
                        carp("Couldn't find file for $rpm.");
                        $missing++;
                        next;
                }
                my $release = find_best(keys %{$RPM_TABLE->{$arch}->{$rpm}->{$version}});
                if(!defined($release)) {
                        carp("Couldn't find file for $rpm.");
                        $missing++;
                        next;
                }
                $file = $RPM_TABLE->{$arch}->{$rpm}->{$version}->{$release}->{FILENAME};
                $pkg = $RPM_TABLE->{$arch}->{$rpm}->{$version}->{$release}->{PKGNAME};
        }
        $files{$pkg}=$file;
    }
    if ($missing) {
        return;
    }
    return %files;
}

sub gen_compat_list {
        # Generates the compatability list from the rpmrc file.
        # Input: the desired architecture.
        # Output: return code and a list of data:
        #         Return code           Data contents
        #         0(ok)                 Ordered list of compat archs
        #         1                     misc error messages
        my $arch=shift;
        my $rpmrcfile=shift;
        my %RPM_COMPAT;
        my @list=@_;
        my $line;
        local *COMPF;
        
        # Read in the compat matrix from the rpmrc file
        if (! %RPM_COMPAT){
                if (! open(COMPF,"$rpmrcfile")) {
                        carp("Couldn't read rpmrc file $rpmrcfile");
                        return;
                }
                while ($line=<COMPF>) {
                        chomp $line;
                        my ($tag,$arch,$carchs)=split(/:/,$line);
                        next unless(defined $tag);
                        if ($tag eq "arch_compat") {
                                $carchs=~s/^ //;
                                $arch=~s/^ //;
                                my ($carch,$junk)=split(/ /,$carchs);      # chuck multiples for now
                                $RPM_COMPAT{$arch}=$carch; 
                        }
                }
                close(COMPF);
                $list[0]=$arch; # Prime the list with the requested arch.
        }
        return resolve_compat_chain(\%RPM_COMPAT,@list);
}

sub resolve_compat_chain {
        # Recursively generate a list based on the rpm compat data
        # Input: a ref to the rpm compat data
        #        the compatability list so-far
        # Output: the complete compat list.
        my $RPM_COMPAT=shift;
        my @list=@_;
        # Now do the recursive stuff to build a compat chain.
        my $last=scalar(@list)-1;
        if (defined $$RPM_COMPAT{$list[$last]}){
                push @list,$$RPM_COMPAT{$list[$last]};
                return resolve_compat_chain($RPM_COMPAT,@list);
        } else {
                return @list;
        }

}

sub populate_rpm_table {
    # Gathers the data from the rpm files
    # Input: directory with rpms
    # Output: return code and a scalar data item:
    #         Return code           Data contents
    #         0(ok)                 Reference to rpm table
    #         1                     Error message
    my $dir = shift;
    my $cachefile=shift;
    my $RPM_TABLE;
    local *CACHE;
    unless ($cachefile =~ /^\//) {
            $cachefile=$dir."/".$cachefile;
    }

    unless (open(CACHE,"<$cachefile")) {
            carp("Can't open cache file $cachefile.");
            return;
    }
    while(<CACHE>) {
        my ($name, $version, $release, $arch, $file, $size, $srpm) = split;
        # Do some sanity checking to see that name is actually there
        if( ($name) && ($srpm ne "(none)") ) {
            $RPM_TABLE->{$arch}->{$name}->{$version}->{$release}->{FILENAME} = $file;
            $RPM_TABLE->{$arch}->{$name}->{$version}->{$release}->{PKGNAME} = $name;
            my $rpmname="$name-$version-$release";
            $RPM_TABLE->{$arch}->{$name}->{$version}->{$release}->{RPMNAME} = $rpmname;
            # A shortcut for finding based on full name.
            $RPM_TABLE->{$arch}->{$rpmname} = $RPM_TABLE->{$arch}->{$name}->{$version}->{$release};
        }
    }
    close(CACHE);
    return $RPM_TABLE;
}

sub find_best {
        # Sort an array and return the top of the sort
        # Input: array to be sorted
        # Output: the "highest" element.
        my @versions = @_;

        my $nonnumeric = 0;
        foreach my $entry (@versions) {
                if($entry !~ /^\d+\.*\d*$/) {
                        $nonnumeric++;
                }
        }
        my @best = ();
        if($nonnumeric) {
                @best = sort {$b cmp $a} @versions;
        } else {
                @best = sort {$b <=> $a} @versions;
        }

        return shift @best;
}

sub find_best_arch {
        # Finds the first architecture that we have an rpm for
        # based on the rpm compatability info.
        # Input: Ref to the rpm table info
        #        Ref to the ordered list of compatable rpms
        #        The package name we're looking for
        # Output: The best arch to use.
        my $RPM_TABLE=shift;
        my $compatlist=shift;
        my $pkg=shift;
        foreach my $arch (@$compatlist){
                if (defined $RPM_TABLE->{$arch}->{$pkg}) {
                        return $arch;
                }
        }
}


### POD from here down
1;
