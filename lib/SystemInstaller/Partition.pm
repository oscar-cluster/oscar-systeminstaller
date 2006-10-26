package SystemInstaller::Partition;
	
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
 
#   Stacy Woods <spwoods@us.ibm.com>             
#
#   Copyright (c) 2005, 2006 Erich Focht <efocht@hpce.nec.com>
#                 Added RAID1 support.
#                 Generalized to new systemimager RAID XML format.
#                 Added RAID0,1,5,6 support.
#

use strict;
use vars qw($VERSION @EXPORT @EXPORT_OK);
$VERSION = sprintf("%d", q$Revision$ =~ /(\d+)/);

use base qw(Exporter);
@EXPORT=qw(read_partition_info partition_setup change_disk_type);

use FindBin qw($Bin);
use lib "$Bin/../lib";
use SIS::Image;
use SIS::DB;
use SystemInstaller::Log qw(verbose);
use SystemInstaller::Partition::IA;
use Data::Dumper;
use Carp;


sub read_partition_info {
# Reads in the partition info from the user and converts it
# to the %DISKS structure.
# Input:        filehandle to the partition info (may be STDIN)
# Output:       filled %DISKS structure.
        my ($fh)=shift;
        my $fn=shift;
        my %DISKS=();

        $DISKS{FILENAME}=$fn;
                
        while (<$fh>){
                chomp;
                if ((/^\s*#/) || (/^\s*$/)) {
                        next;
                }
                # Not sure if this is the best way to handle this.
                if (/^\s*[^(=|\s)]+\s*=\s*[^(=|\s)]+\s*$/) {
                        my($tag,$val)=split(/=/,$_);
                        $tag=uc($tag);
                        $DISKS{$tag}=$val;
                        next;
                }

		# RAID* software raid definitions
		if (/^\s*raid([0156])\s+/) {
		    my $level = $1;
		    my $rlevel = "RAID$level";
		    my @parts = split /\s+/, $_;
		    shift @parts;
		    my $rdev = shift @parts;    # raid* device name
		    my @spares = grep /^\[\S+\]$/, @parts;
		    @spares = map { m/^\[(\S+)\]$/; $1; } @spares;
		    my @active = grep !/^\[\S+\]$/, @parts;
		    @{$DISKS{$rlevel}{$rdev}{active}} = @active;
		    @{$DISKS{$rlevel}{$rdev}{spares}} = @spares;
		    next;
		}

                my ($pdev,$size,$type,$mnt,$opt,$boot) = split /\s+/,$_,6;
                my $fstype=get_id($type);
                if ($boot) {
                        $boot="*";
                }
                unless ($fstype == 0) {

		    my @partitions = ();
		    my $raid = "";
		    # is it a software raid partition?
		    for my $level (0, 1, 5, 6) {
			my $rlev = "RAID$level";
			if (defined($DISKS{$rlev}{$pdev})) {
			    push @partitions, @{$DISKS{$rlev}{$pdev}{active}};
			    push @partitions, @{$DISKS{$rlev}{$pdev}{spares}};
			    $raid = "*";
			}
		    }
		    if (!$raid) {
			push @partitions, $pdev;
		    }
		    foreach my $part (@partitions) {
                        my %DEV=parse_dev($part);
                        my $drive="/dev/".$DEV{DRIVE};
                        push(@{$DISKS{DRIVES}{$drive}},$part);
                        %{$DISKS{PARTITIONS}{$part}} = (
                                TYPE            =>$fstype,
                                SIZE            =>$size,
                                BOOTABLE        =>$boot,
                                RAID            =>$raid,
                                DEVICE          =>$part,
                                DRIVE           =>$drive,
                                PNUM            =>$DEV{PARTNUM},
                        );
		    }
                }
                %{$DISKS{FILESYSTEMS}{$pdev}} = (
                        TYPE            =>$type,
                        MOUNT           =>$mnt,
                        DEVICE          =>$pdev,
                        OPTIONS         =>$opt,
                );

        }        
        %DISKS=&add_defaults(%DISKS);
        @{$DISKS{MOUNTORDER}}=&mount_order(%DISKS);

        return %DISKS;


} # read_partition_info

sub mount_order {
# Return a list of device ordered by their mount point depth
# Input:        %DISKS structure
# Output:       List of devices
        my %DISKS=@_;
        my @FS;
        my @FSNONE;
        my @FSAUTO;
        # First split it up according to depth
        foreach my $dev (keys %{$DISKS{FILESYSTEMS}}) {
                # Put '/' first
                if ($DISKS{FILESYSTEMS}{$dev}{MOUNT} eq "/") {
                        push @{$FS[0]},$dev;
                } elsif ($DISKS{FILESYSTEMS}{$dev}{TYPE} =~ /^(none)$/) {
                        push @FSAUTO,$dev;
                } elsif ($DISKS{FILESYSTEMS}{$dev}{TYPE} =~ /^(proc|devpts)$/) {
                        push @FSNONE,$dev;
                } else {
                        # Count the number of '/' in the mount point
                        my $count=0;
                        while ($DISKS{FILESYSTEMS}{$dev}{MOUNT} =~/\//g) {
                                $count++;
                        }
                        push @{$FS[$count]},$dev;
                }
        }
        # Now smush them all into 1 list
        foreach (1..(scalar(@FS)-1)) {
    	   if ( defined (@{$FS[$_]} ) ) {
		push @{$FS[0]},@{$FS[$_]};
           }
        }
        push @{$FS[0]},@FSAUTO;
        push @{$FS[0]},@FSNONE;
        return @{$FS[0]};
        
} # mount_order




sub add_defaults {
# Add some default filesystems if not defined.
# Input:        %DISKS structure
# Output:       %DISKS structure
        my %DISKS=@_;

        unless (defined $DISKS{FILESYSTEMS}{"/dev/fd0"}) {
                %{$DISKS{FILESYSTEMS}{"/dev/fd0"}} = (
                        TYPE    => "auto",
                        MOUNT   => "/mnt/floppy",
                        DEVICE  => "/dev/fd0",
                        OPTIONS => "noauto,owner",
                );
        }        
        unless (defined $DISKS{FILESYSTEMS}{"/proc"}) {
                %{$DISKS{FILESYSTEMS}{"/proc"}} = (
                        TYPE    => "proc",
                        MOUNT   => "/proc",
                        DEVICE  => "/proc",
                        OPTIONS => "defaults",
                );
        }        
        unless (defined $DISKS{FILESYSTEMS}{"/dev/pts"}) {
                %{$DISKS{FILESYSTEMS}{"/dev/pts"}} = (
                        TYPE    => "devpts",
                        MOUNT   => "/dev/pts",
                        DEVICE  => "/dev/pts",
                        OPTIONS => "mode=0622",
                );
        }        
        return %DISKS;


} # add_defaults
        

sub change_disk_type {
# Changes the disk type for all drives to the type given
# Input:        disk type, %DISKS structure
# Returns:      new %DISKS structure 
#
        my ($type,%DISKS) = @_;
        my %NEWDISKS;
        my $newpre;
        # fs types we shouldn't touch.
        my @ignores = qw(proc auto devpts nfs);
                
        if ($type eq "ide") {
                $newpre="/dev/hd";
        } elsif ($type eq "scsi") {
                $newpre="/dev/sd";
        } else {
                carp("Unrecognized device type $type");
                return 0;
        }
        foreach my $cat (qw(FILESYSTEMS PARTITIONS)) {

                foreach my $dev (sort keys %{$DISKS{$cat}}) {
                        # Skip non device filesystems (nfs)
                        if ( grep(/$DISKS{$cat}{$dev}{TYPE}/,@ignores) ) {
                                %{$NEWDISKS{$cat}{$dev}}=%{$DISKS{$cat}{$dev}};
                                next;
                        }
                        my %DEV=parse_dev($dev);
                        my $newdev=$newpre.$DEV{DLETTER}.$DEV{PARTNUM};
                        my $newdrive=$newpre.$DEV{DLETTER};

                        %{$NEWDISKS{$cat}{$newdev}}=%{$DISKS{$cat}{$dev}};
                        $NEWDISKS{$cat}{$newdev}{DEVICE}=$newdev;
                        if ($cat eq "PARTITIONS") {
                                $NEWDISKS{$cat}{$newdev}{DRIVE}=$newdrive;
                                push @{$NEWDISKS{DRIVES}{$newdrive}},$newdev;
                        }


                }
        }
        # Transfer values and regen defaults and order
        $NEWDISKS{FILENAME}=$DISKS{FILENAME};
        %NEWDISKS=&add_defaults(%NEWDISKS);
        @{$NEWDISKS{MOUNTORDER}}=&mount_order(%NEWDISKS);
        return %NEWDISKS;


} #change_disk_type

sub parse_dev {
# Breaks a device into its components
# Input:        Device name (eg /dev/hda1)
# Output:       A hash with the following
#               %DEV = (
#                   DEVICE      #Same as the input
#                   DRIVE       #drive name (hda)
#                   TYPE        #Drive type (hd)
#                   DLETTER     #Drive letter (a)
#                   PARTNUM     #Part number (1)
#               )
        my %DEV=();
        $DEV{DEVICE}=shift;

        # Get the drive,(eg hda)
        $DEV{DRIVE}=$DEV{DEVICE};
        $DEV{DRIVE}=~s/\/dev\///;
        $DEV{DRIVE}=~s/[0-9]*$//;
        # Get the drive type, (hd)
        $DEV{TYPE}=$DEV{DRIVE};
        $DEV{TYPE}=~s/[a-z]$//;
        # Get the drive letter, (a)
        $DEV{DLETTER}=$DEV{DRIVE};
        $DEV{DLETTER}=~s/$DEV{TYPE}//;
        # Get the partition number
        $DEV{PARTNUM}=$DEV{DEVICE};
        $DEV{PARTNUM}=~s/\/dev\/$DEV{DRIVE}//;

        return %DEV;
} #parse_dev

sub partition_setup {
# Create partition_file that includes the drive type, architecture, and
#  partition information.  Then call architecture specific routines to create
#  partition input file.
#
# Input:        image name, %DISKS structure
# Returns:      1 if failure, 0 if ok
#

        my ($name,%DISKS) = @_;
        my $image=list_image(name=>$name);
        unless ($image) {
              carp("Image $name does not exist\n");
              return 1;
        }

	&verbose("Determining which routine to call based on architecture.");
	if ($image->arch =~ /^(i.86|ia64|x86_64)$/) {
        	if (&SystemInstaller::Partition::IA::create_partition_file($image->location,%DISKS)) {
			return 1;
		}
	} elsif ( ($image->arch =~ /^(ppc.*)$/) && ( -d '/proc/iSeries' ))  {
		if (&SystemInstaller::Partition::IA::create_partition_file($image->location,%DISKS)) {
			return 1;
		}
	} else {
		print STDERR "$image->arch is not a recognized architecture\n";
		return 1;
	}
        &verbose("Writing updateclient exclude file");
        unless (&write_exclude_file($image->location,%DISKS)) {
		carp("Failed to write exclude file to image");
		return 1;
        }
        return 0;

} #partition_setup

sub write_exclude_file {
# Writes the remote (nfs) filesystems to the update client exclude file
# Input:        Image path, %DISKS structure
# Output:       Boolean
        my ($ipath, %DISKS)=@_;
        my @excludes;
        my @lines;
        my $filename="$ipath/etc/systemimager/updateclient.local.exclude";
        # First read the old file into memory minus the SystemInstaller bits
        if (-e $filename) {
                unless (open(EXCLUDE,"<$filename")) {
                        carp("Unable to open exclude file: $filename");
                        return 0;
                }
                my $tossing=0;
                while (<EXCLUDE>){
                        if ($tossing) {
                                if (/End SystemInstaller excludes/) {
                                        $tossing=0;
                                }
                        } else {
                                if (/Start SystemInstaller excludes/) {
                                        $tossing=1;
                                } else {
                                        push @lines,$_;
                                }
                        }
                }
                close(EXCLUDE);
        }
       
        # Now get a list of nfs filesystems
        foreach my $dev (keys %{$DISKS{FILESYSTEMS}}) {
                if ($DISKS{FILESYSTEMS}{$dev}{TYPE} eq "nfs"){
                        push @excludes,$DISKS{FILESYSTEMS}{$dev}{MOUNT};
                }        
        }

        # Write out the new file.
        unless (open(EXCLUDE,">$filename")) {
                carp("Unable to open exclude file: $filename");
                return 0;
        }
        if (@lines) {
                foreach (@lines) {
                        print EXCLUDE "$_";
                }
        }
        if (@excludes) {
                print EXCLUDE "# Start SystemInstaller excludes\n";
                print EXCLUDE "# These lines may be reconfigured by SystemInstaller\n";
                print EXCLUDE "# So, don't put anything between this and the end comment\n";
                print EXCLUDE "# that you want to keep!\n";
                foreach (@excludes) {
                        print EXCLUDE "$_/*\n";
                }
                print EXCLUDE "# End SystemInstaller excludes\n";
        }
        close(EXCLUDE);
        return 1;
} # write_exclude_file

sub get_id {
# Determine the filesystem id from the filesystem type.
# Input:        filesystem type 
# Returns:      return filesystem id
    my $fstype = shift;
    $fstype =~ tr/A-Z/a-z/;
    my @nodev = qw(sysfs rootfs bdev proc sockfs debugfs securityfs
		   pipefs futexfs tmpfs inotifyfs eventpollfs devpts
		   ramfs hugetlbfs nfs nfs4 mqueue rpc_pipefs subdomainfs
		   usbfs auto);
    my $nodevmatch = join("|",@nodev);
    if ($fstype =~ /^(ext2|ext3|xfs|jfs|reiserfs)$/) {
        return 83;
    } elsif ($fstype =~ /^(swap)$/) {
        return 82;
    } elsif ($fstype =~ /^(extended)$/) {
        return 5;
    } elsif ($fstype =~ /^(fat16|vfat|msdos)$/) {
        return 6;
    } elsif ($fstype =~ /^(efi)$/) {
        return "ef";
    } elsif ($fstype =~ /^(prep)$/ ) {
	return 41;
    } elsif ($fstype =~ /^[0-9a-f][0-9a-f]*$/) {
        # when the id given as input just return the same value.
        return $fstype;
    } elsif ($fstype =~ /^($nodevmatch)$/) {
            # remote and special fs's don't get a fs type
        return 0;
    } else {
        # else just give linux standard fs type
        return 83;
    }

} # get_id

=head1 NAME

SystemInstaller::Partition - Interface for creating partition information files

=head1 SYNOPSIS

 use SystemInstaller::Partition

 open(FH,"</tmp/disktable");
 %DISKS=&read_partition_info(*FH);
 if (&partition_setup($imagename,%DISKS)) {
         print "Partition setup failed!\n";
 }


=head1 DESCRIPTION

SystemInstaller::Partition provides an interface for creating partitioning files.

It parses the partition file and creates the necessary files in the image to
initiate disk partitioning and filesystem creation when the image is installed.

The following routines are exported:

=over 4

=item %DISKS = read_partition_info(<FILEHANDLE>)

Read the partition info from the filehandle that is passed in. The file handle
may be STDIN. For details on the file format, see the I<mksidisk> man page. A
hash is returned that contains the information from the file to pass to the
other routines.

=item %DISKS = change_disk_type(<type>,%DISKS)

Given the desired disk type (eg ide) and a %DISKS hash, return a new %DISKS
hash in which B<ALL> drives have been changed to the desired type.

=item partition_setup(<imagename>,%DISKS)

Apply the partition and filesystem information in the %DISKS hash to the image
referenced by <imagename>

=back

=head1 DATA

The %DISKS hash stores all information from the partition file, as well as some
items that are added as execution progresses. The data has the following format:

        $DISKS{FILESYSTEMS}{$devicename} = (
                TYPE    => $fstype,
                MOUNT   => $mountpoint,
                DEVICE  => $devicename,
                OPTIONS => $mountoptions,
        );
        $DISKS{PARTITIONS}{$devicename} = (
                TYPE     => $partition_type,
                SIZE     => $size,
                BOOTABLE => $boot,
                DEVICE   => $devicename,
        );

        
=head1 AUTHOR

Michael Chase-Salerno <mchasal@users.sf.net>,
Stacy Woods <spwoods@us.ibm.com>

=head1 SEE ALSO

L<SystemInstaller::Partition::IA>,
mksidisk(1)

=cut

1;


