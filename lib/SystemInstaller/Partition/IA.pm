package SystemInstaller::Partition::IA;
	
#   $Id$
#
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
#   Sean Dague <sean@dague.net>
#
#   Copyright (c) 2005, 2006 Erich Focht <efocht@hpce.nec.com>
#                 Added RAID1 support. (c) 2005 NEC HPCE
#                 Generalized to RAID0,1,5,6.

# Copyright (c) 2009 CEA (Commissariat à l'Énergie Atomique)
#                    Olivier Lahaye <olivier.lahaye@cea.fr>
#                    All rights reserved

# Copyright (c) 2009    Oak Ridge National Laboratory
#                       Geoffroy Vallee <valleegr@ornl.gov>
#                       All rights reserved.

use vars qw($VERSION);
$VERSION = sprintf("%d", q$Revision$ =~ /(\d+)/);

use strict;
use vars qw(@EXPORT @ISA $drive_prefix $systemimager_path $udev_dir);
use Exporter;
use lib "/usr/lib/systemconfig";
use lib "/usr/lib/systeminstaller";
use SystemInstaller::Log qw(verbose); 
use SystemInstaller::Image;
use SIS::NewDB;
use Initrd::Generic;
use Data::Dumper;
use Carp;
 
$systemimager_path = "/etc/systemimager";

sub create_partition_file {
# Reads the partition_file and creates the necessary files needed for 
# partitioning and filesystem initialization.
# Input:        image path
# Returns:      1 if failure, 0 if ok
#
	my $ipath = shift;
    my %DISKS = @_;
	my @found_devices;
	my %disk_devices;
	my $device;
	my $device_on_list;
	&verbose("Creating partition files for intel architecture.");

        if ($main::config->diskversion eq "2") {
	        &create_fstab_file($ipath,%DISKS);
                &build_sfdisk_file($ipath,%DISKS);
        } elsif ($main::config->diskversion eq "3") {
                &build_aiconf_file($ipath,%DISKS);
                &build_mdadmconf_file($ipath,%DISKS);
        } else {
                carp("Disk table version is invalid in systeminstaller.conf file.");
                return 1;
        }
	&create_systemconfig_conf($ipath,%DISKS);

    my $systemconfig_file = "$ipath/etc/systemconfig/systemconfig.conf";
    require OSCAR::ImageMgt;
    OSCAR::ImageMgt::update_systemconfigurator_configfile ($systemconfig_file);

    return 0;
} #read_partition_file

sub get_partition_flags ($%) {
    my ($parname, %DISKS) = @_;
    my $flags;

    if ($DISKS{PARTITIONS}{$parname}{BOOTABLE} ) {
        $flags="boot";
    }
    if ($DISKS{PARTITIONS}{$parname}{RAID} ) {
        if ($flags) {
            $flags .= ",raid";
        } else {
            $flags="raid";
        }
    }
    if ($DISKS{PARTITIONS}{$parname}{TYPE} == "82") {
        if ($flags) {
            $flags .= ",swap";
        } else {
            $flags="swap";
        }
    }

    return $flags;
}

sub get_partition_device ($$) {
    my ($disk, $partnum) = @_;

    if ($disk =~ /\/dev\/cciss\/c[0-9]+d[0-9][0-9]*$/) {
        return $disk."p".$partnum;
    } else {
        return $disk.$partnum;
    }
}

# Create <part= tag.
#
# Input: pnum, partition numer
#        psize, partition size (string) or "\*"
#        ptype, eiter "primary", "logical" "extended" or "41"
#        pflag, flags (can be undef, optional).
# Return: 0 if success, -1 else.
sub do_partition ($$$$) {
    my ($pnum, $psize, $ptype, $pflags) = @_ ;

    if (!defined $pnum) {
        carp "ERROR: Invalid partition number";
        return -1;
    }

    if (!defined $psize) {
        carp "ERROR: Invalid partition size";
        return -1;
    }

    if (!defined $ptype) {
        carp "ERROR: Invalid partition type";
        return -1;
    }

    my $pid;
    if ($ptype eq "41") {
        $pid = 41;
        $ptype = "primary";
    }
    print AICONF "\t\t<part num=\"$pnum\" ";
    print AICONF "size=\"$psize\" ";
    print AICONF "p_type=\"$ptype\" ";
    if($pid == 41) {
        print AICONF "id=\"41\"";
    }
    if(defined($pflags) && !($pflags eq "")) {
        print AICONF "flags=\"$pflags\" ";
    }
    print AICONF "/>\n";

    return 0;
}

# Return: value > 0 if success (highest logical partition id), -1 if errors.
sub check_partitioning ($%) {
    my ($disk, %DISKS) = @_;
    my $has_logicals = 0;
    my $highest_logical = 0;
    my $extended_part_num;

    if ($DISKS{LABEL_TYPE} eq "msdos") {
        my $primary_count = 0;
        # Cycle thru partitions,; count primaries and see if we have 
        # logicals
        foreach my $partname ( @{$DISKS{DRIVES}{$disk}} ) {
            if ($DISKS{PARTITIONS}{$partname}{PNUM} > 4) {
                $has_logicals++;
                if ($DISKS{PARTITIONS}{$partname}{PNUM} > $highest_logical) {
                    $highest_logical = $DISKS{PARTITIONS}{$partname}{PNUM};
                }
            } else {
                $primary_count++;
            }
        }

        # Check if we have room for extended partition (if required)
        if ($has_logicals > 0) {
            # check 4 primary + extended impossible layout.
            if ($primary_count == 4) {
                carp "ERROR: $DISKS{FILENAME} layout incompatible with ".
                "label_type=msdos. Use gpt or use less primary ".
                "partitions";
                return (-1, undef);
            }
            # Check that all logical partitions are contiguous or die.
            if ($highest_logical != ($has_logicals + 4)) {
                carp "ERROR: $DISKS{FILENAME} layout incompatible with ".
                     "label_type=msdos. Logical partitions (Part id > 4) ".
                     "must be contiguous";
                return (-1, undef);
            }
            # Determine which partition device name is available for
            # extended partition (if required) cycle thru ids 1 to 4 and see
            # if a slot is available.
            foreach my $parnum (1..4) {
                my $partname = get_partition_device ($disk, $parnum);
                # If we find a slot
                if (! defined ($DISKS{PARTITIONS}{$partname})) {
                    $extended_part_num = $parnum ;
                    last ;
                }
            }
        }
    } elsif (scalar @{$DISKS{DRIVES}{$disk}} > 128) {
        # TODO: Handle less probable cases
        carp "ERROR: $DISKS{FILENAME} layout incompatible with ".
             "label_type=$DISKS{LABEL_TYPE}: partition count exceeded: ".
             "max=128 (gpt)";
        return (-1, undef);
    }

    return (0, $extended_part_num);
}

# Create an autoinstallscript.conf file to be used
# be used by SystemImager's mkautoinstallscript.
# Input:  partition table created from input partition_file
# Returns: 0 if success, 1 else.
sub build_aiconf_file {
    my ($image_dir,%DISKS) = @_;
    local *AICONF;

    # Can we get the filename from the systemimager.conf file?
    my $file = "$image_dir/etc/systemimager/autoinstallscript.conf";
    unless (open (AICONF,">$file")) { 
        carp("ERROR: Can't open autoinstallscript.conf in image ($file).");
        return 1;
    }

    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) 
        = localtime(time);
    $year=$year+1900;
    $mon++;
    my $timestamp="$year-$mon-$mday $hour:$min:$sec";
    print AICONF "<!--\n";
    print AICONF "\tThis autoinstallscript.conf file was generated by ".
                 "SystemInstaller\n";
    print AICONF "\tfor use by SystemImager when creating the autoinstall ".
                 "script.\n";
    print AICONF "\tThis file generated at: $timestamp\n"; 
    print AICONF "\tfrom: $DISKS{FILENAME}\n";
    print AICONF "\tImage directory: $image_dir\n";
    print AICONF "-->\n";
    print AICONF "<config>\n";

    # Set the defaults for globals if not given.
    unless ($DISKS{LABEL_TYPE}) {
        $DISKS{LABEL_TYPE}="msdos";
    }
    unless ($DISKS{UNITS}) {
        $DISKS{UNITS}="MB";
    }
    # First do the disk partitions
    my $flags;
    my $extended_part_num;
    my $highest_logical;
    foreach my $disk (keys(%{$DISKS{DRIVES}})) {
        print AICONF "\t<disk dev=\"$disk\" ";
        print AICONF "label_type=\"$DISKS{LABEL_TYPE}\" ";
        print AICONF "unit_of_measurement=\"$DISKS{UNITS}\">\n";

        my $has_logicals = 0;
        # 1st, check for incompatible layouts if we use msdos partition table.
        ($highest_logical, $extended_part_num) = check_partitioning ($disk, %DISKS);
        if ($highest_logical == -1) {
            carp "ERROR: Invalid partition layout";
            return 0;
        }

        # Do all partitions at once. Be carefull when PNUM becomes > 4
        my $partition_type;
        my $size_star = 0;
        foreach my $parname ( sort @{$DISKS{DRIVES}{$disk}} ) {
            if (($DISKS{LABEL_TYPE} eq "msdos") 
                && $DISKS{PARTITIONS}{$parname}{PNUM} > 4) {
                # on msdos partition table, if pnum >4 we need to be carefull
                if (defined($extended_part_num)) {
                    # We need to create $extended_part_num (not yet created)
                    if (do_partition ($extended_part_num,
                                    "\*",
                                    "extended",
                                    undef)) {
                        carp "ERROR: Impossible to prepare a partition";
                        return 1;
                    }
                    undef $extended_part_num; # Done, we won't go here again.
                }
                $partition_type = "logical" ; # msdos & PNUM > 4
            } else {
                $partition_type = "primary" ; # PNUM <= 4 or not msdos
            }
            if ("$DISKS{PARTITIONS}{$parname}{SIZE}" eq "\*") {
                $size_star++;
            }
            if ($size_star > 1) {
                carp "ERROR: $DISKS{FILENAME} layout problem: You cannot have ".
                    "more than one partition size set to \"\*\"";
                return 1;
            }
            $flags = get_partition_flags ($parname, %DISKS);
            if (!defined ($DISKS{PARTITIONS}{$parname}{PNUM})) {
                my $data = Dumper $DISKS{PARTITIONS}{$parname};
                carp "ERROR: partition number is not defined for: $data";
                return 1;
            }
            if (do_partition ($DISKS{PARTITIONS}{$parname}{PNUM},
                    $DISKS{PARTITIONS}{$parname}{SIZE},
                    $partition_type,
                    $flags )) {
                carp "ERROR: Impossible to create a partition";
                return 1;
            }
        } 
        print AICONF "\t</disk>\n";
    }

    # Write RAID structures - EF -
    for my $rlevel ("0", "1", "5", "6") {
        my $rraid = "RAID$rlevel";
        foreach my $rdev (sort(keys %{$DISKS{$rraid}})) {
            my @active = @{$DISKS{$rraid}{$rdev}{active}};
            my @spares = @{$DISKS{$rraid}{$rdev}{spares}};
            my @parts = (@active, @spares);
            my $nactive = scalar(@active);
            my $nspares = scalar(@spares);
            print AICONF "\t<raid name=\"$rdev\"\n";
            print AICONF "\t    raid_level=\"raid$rlevel\"\n";
            print AICONF "\t    raid_devices=\"$nactive\"\n";
            print AICONF "\t    spare_devices=\"$nspares\"\n";
            print AICONF "\t    persistence=\"yes\"\n";
            if ($rlevel eq "5" || $rlevel eq "6") {
                print AICONF "\t    layout=\"left-asymmetric\"\n";
            }
            print AICONF "\t    devices=\"".join(" ",@parts)."\"\n";
            print AICONF "\t/>\n";
        }
    }

    # Now do the filesystems
    my $lcount=100;
    foreach my $dev (@{$DISKS{MOUNTORDER}}) {
        if ( ($DISKS{FILESYSTEMS}{$dev}{TYPE} ne "nfs") &&             ($DISKS{FILESYSTEMS}{$dev}{TYPE} ne "extended") &&
             ($DISKS{FILESYSTEMS}{$dev}{TYPE} ne "PReP" )) {
            print AICONF "\t<fsinfo line=\"$lcount\" ";
            if ($DISKS{FILESYSTEMS}{$dev}{TYPE} eq "swap") {
                print AICONF "real_dev=\"$DISKS{FILESYSTEMS}{$dev}{DEVICE}\" ";
                print AICONF "mp=\"swap\" fs=\"swap\" options=\"defaults\" dump=\"0\" pass=\"0\" ";
            } elsif ($DISKS{FILESYSTEMS}{$dev}{TYPE} eq "proc") {
                print AICONF "real_dev=\"none\" ";
                print AICONF "mp=\"/proc\" ".
                             "fs=\"$DISKS{FILESYSTEMS}{$dev}{TYPE}\" ";
                print AICONF "options=\"defaults\" dump=\"0\" pass=\"0\" ";
            } elsif ($DISKS{FILESYSTEMS}{$dev}{TYPE} eq "devpts") {
                print AICONF "real_dev=\"none\" ";
                print AICONF "mp=\"/dev/pts\" fs=\"$DISKS{FILESYSTEMS}{$dev}{TYPE}\" ";
                print AICONF "options=\"defaults\" dump=\"0\" pass=\"0\" ";
            } elsif ($DISKS{FILESYSTEMS}{$dev}{DEVICE} =~ /^\/dev\/fd[0-9]*$/) {
                print AICONF "real_dev=\"$DISKS{FILESYSTEMS}{$dev}{DEVICE}\" ";
                print AICONF "mp=\"$DISKS{FILESYSTEMS}{$dev}{MOUNT}\" ";
                print AICONF "fs=\"$DISKS{FILESYSTEMS}{$dev}{TYPE}\" ";
                print AICONF "options=\"$DISKS{FILESYSTEMS}{$dev}{OPTIONS}\" ";
                print AICONF "dump=\"0\" pass=\"0\" ";
            } else {
                print AICONF "real_dev=\"$DISKS{FILESYSTEMS}{$dev}{DEVICE}\" ";
                print AICONF "mp=\"$DISKS{FILESYSTEMS}{$dev}{MOUNT}\" ";
                print AICONF "fs=\"$DISKS{FILESYSTEMS}{$dev}{TYPE}\" ";
                print AICONF "options=\"$DISKS{FILESYSTEMS}{$dev}{OPTIONS}\" ";
                print AICONF "dump=\"1\" pass=\"2\" ";
            }
            print AICONF "/>\n";
            $lcount++;
        }
    }
    #
    # Now do the nfs filesystems
    &verbose("Finding nfs filesystems");
    foreach my $dev (@{$DISKS{MOUNTORDER}}) {
        if ($DISKS{FILESYSTEMS}{$dev}{TYPE} eq "nfs") {
            print AICONF "\t<fsinfo line=\"$lcount\" ";
            print AICONF "real_dev=\"$DISKS{FILESYSTEMS}{$dev}{DEVICE}\" ";
            print AICONF "mp=\"$DISKS{FILESYSTEMS}{$dev}{MOUNT}\" ";
            print AICONF "fs=\"$DISKS{FILESYSTEMS}{$dev}{TYPE}\" ";
            print AICONF "options=\"$DISKS{FILESYSTEMS}{$dev}{OPTIONS}\" ";
            print AICONF "dump=\"0\" pass=\"0\" ";
            print AICONF "/>\n";
            $lcount++;
        }
    }

    # Is the install kernel 2.6.X? Then it probably uses udev,
    # so let's use devfs install style.
    # (triggers /dev to be mounted during node installation)
    # - detect architecture of install image
    my @images = list_image(location => $image_dir);
    if (scalar (@images) != 1) {
        carp "ERROR: We did not get exactly one image for $image_dir, this ".
             "is not normal";
        return 1;
    }
    my $instarch = $images[0]->{arch};
    if (!OSCAR::Utils::is_a_valid_string ($instarch)) {
        carp "ERROR: Impossible to detect the arch of the $images[0] image";
        return 1;
    }
    $instarch =~ s/i.86/i386/;
    # added to support ppc64-ps3
    $instarch = "ppc64-ps3" if (-d "/usr/share/systemimager/boot/ppc64-ps3");
    # detect version of install kernel
    my $instkdir = "/usr/share/systemimager/boot/$instarch/standard";
    if (! -d $instkdir) {
        carp "ERROR: Kernels are not installed ($instkdir)";
        return 1;
    }

    my $kvers = kernel_version($instkdir . "/kernel");
    if ($kvers =~ /^2\.6\./) {
        print AICONF "\t<boel devstyle=\"udev\" />\n";
    }

    print AICONF "</config>\n";
    close AICONF;
    return 0;
} # build_aiconf_file

sub build_mdadmconf_file {
# Create a mdadm.conf file in the image
# Input:  partition table created from input partition_file
# Returns:

    my ($image_dir,%DISKS) = @_;
    # only RAID1 is actually supported currently (EF: Nov 30, 2005)
    return if (!(%{$DISKS{RAID0}}) && !(%{$DISKS{RAID1}}) &&
	       !(%{$DISKS{RAID5}}) && !(%{$DISKS{RAID6}}));
    local *RT;
    if (-f "$image_dir/etc/mdadm.conf") {
	&verbose("Overwriting old mdadm.conf file from image $image_dir...\n");
    }
    unless (open (RT,"> $image_dir/etc/mdadm.conf")) { 
	carp("Can't open /etc/mdadm.conf in image $image_dir.");
	return 1;
    }

    my ($sec, $min, $hour, $mday,$mon, $year, $wday, $yday, $isdst) = localtime(time);
    $year=$year+1900;
    $mon++;
    my $timestamp="$year-$mon-$mday $hour:$min:$sec";
    print RT "# This mdadm.conf file was generated by SystemInstaller.\n";
    print RT "# This file generated at: $timestamp\n"; 
    print RT "# from: $DISKS{FILENAME}\n";
    print RT "# Image directory: $image_dir\n";

    print RT "DEVICE partitions\n";
    for my $rlevel ("0", "1", "5", "6") {
	my $rraid = "RAID$rlevel";


	foreach my $rdev (keys %{$DISKS{$rraid}}) {
	    my @active = @{$DISKS{$rraid}{$rdev}{active}};
	    my @spares = @{$DISKS{$rraid}{$rdev}{spares}};
	    my $parts = join(",",(@active, @spares));
	    print RT "ARRAY $rdev level=raid$rlevel devices=$parts\n";
	}
    }
    close RT;
}

sub build_sfdisk_file {
# Create a file that resembles the output of "sfdisk -l -uM <dev>" which will 
# be used by SystemImager getimage to build a sfdisk command.  
# Input:  partition table created from input partition_file
# Returns:
	my ($image_dir,%DISKS) = @_;
        my @opendevs;
        my %DISKPARS=();

	# remove existing device files
	system("/bin/rm -f $image_dir/$systemimager_path/partitionschemes/*");

	&verbose("Mapping partitions to disks.");
        foreach my $dev (keys(%{$DISKS{PARTITIONS}})) {
                # Figure out the diskname
                my $diskname=$dev;
                if ($dev=~/c[0-9]+d[0-9]+p[0-9]*$/) {
                    $diskname=~s/p[0-9]*$//;
                } else {
                    $diskname=~s/[0-9]*$//;
                }
                $diskname=~s/^\/dev\///;
                my $parnum=$dev;
                $parnum=~s/\/dev\/$diskname//;
                $DISKPARS{$diskname}[$parnum]=$dev;
        }
        foreach my $disk (keys(%DISKPARS)) {
                my $extended_par_created = 1;
                # Start the file for this disk
                &verbose("Initializing file for $disk");
                unless (open(SFDISK_FILE,">$image_dir/$systemimager_path/partitionschemes/$disk")) {
                        carp("Unable to create disk partition file $image_dir/$systemimager_path/partitionschemes/$disk");
                        return 1;
                }
                print SFDISK_FILE "\n##File created by SystemInstaller for input to SystemImager##\n";
                print SFDISK_FILE "Units = megabytes\n\n";
                print SFDISK_FILE "Device\tBoot\tStart\tEnd\tMB\t#blocks\tId\n";

                # Now put the partitions in there.
                foreach my $parnum (1..4) {
                        my $dev=$DISKPARS{$disk}[$parnum];
                        if ($dev=~/.*dev*/ ) {
                                print SFDISK_FILE "$dev  $DISKS{PARTITIONS}{$dev}{BOOTABLE} \t0 \txx \t$DISKS{PARTITIONS}{$dev}{SIZE} \txx \t$DISKS{PARTITIONS}{$dev}{TYPE}\n";
                        } elsif ($extended_par_created && (scalar(@{$DISKPARS{$disk}})-1) > 4 ) {
                                print SFDISK_FILE "/dev/$disk$parnum \t0 \txx \t99 \txx \t5\n";
                                $extended_par_created = 0;
                        } else {
                                print SFDISK_FILE "/dev/$disk$parnum \t0 \txx \t0 \txx \t0\n";
                        }

                }
                foreach my $parnum (5..(scalar(@{$DISKPARS{$disk}})-1)) {
                        my $dev=$DISKPARS{$disk}[$parnum];
                        print SFDISK_FILE "$dev  $DISKS{PARTITIONS}{$dev}{BOOTABLE} \t0 \txx \t$DISKS{PARTITIONS}{$dev}{SIZE} \txx \t$DISKS{PARTITIONS}{$dev}{TYPE}\n";
                }
        }

        return 0;

} # build_sfdisk_file

sub create_fstab_file {
# Create the /etc/fstab file for the image
# Input:        image path, hash array from partition_file input
# Returns:      1 if failure, 0 if ok
	my ($ipath,%DISKS) = @_;
        my $rootfound=0;

	&verbose("Creating /etc/fstab file for image.");
	unless (open(FSTAB,">$ipath/etc/fstab")) { 
		carp("Could not open the file $ipath/etc/fstab\n");
		return 1;
        }       
        &verbose("Finding local filesystems");
        foreach my $dev (@{$DISKS{MOUNTORDER}}) {
                if ( ($DISKS{FILESYSTEMS}{$dev}{TYPE} ne "nfs") &&
                        ($DISKS{FILESYSTEMS}{$dev}{TYPE} ne "PReP" )) {
                        if ($DISKS{FILESYSTEMS}{$dev}{TYPE} eq "swap") {
                                print FSTAB "$DISKS{FILESYSTEMS}{$dev}{DEVICE} \tswap \t\tswap \tdefaults \t0 0\n";
                        } elsif ($DISKS{FILESYSTEMS}{$dev}{TYPE} =~ /^proc|devpts$/) {
                                print FSTAB "none \t\t$DISKS{FILESYSTEMS}{$dev}{MOUNT} \t\t$DISKS{FILESYSTEMS}{$dev}{TYPE} \t$DISKS{FILESYSTEMS}{$dev}{OPTIONS} \t0 0\n";
                        } elsif ($DISKS{FILESYSTEMS}{$dev}{DEVICE} =~ /^\/dev\/fd[0-9]*$/) {
                                print FSTAB "$DISKS{FILESYSTEMS}{$dev}{DEVICE} \t$DISKS{FILESYSTEMS}{$dev}{MOUNT} \t$DISKS{FILESYSTEMS}{$dev}{TYPE} \t$DISKS{FILESYSTEMS}{$dev}{OPTIONS} \t0 0\n";
                        } else {
                                print FSTAB "$DISKS{FILESYSTEMS}{$dev}{DEVICE} \t$DISKS{FILESYSTEMS}{$dev}{MOUNT} \t\t$DISKS{FILESYSTEMS}{$dev}{TYPE} \t$DISKS{FILESYSTEMS}{$dev}{OPTIONS} \t1 2\n";
                        }
                }
        }        

        # Now do the nfs filesystems
        &verbose("Finding nfs filesystems");
        foreach my $dev (@{$DISKS{MOUNTORDER}}) {
                if ($DISKS{FILESYSTEMS}{$dev}{TYPE} eq "nfs") {
                        print FSTAB "$DISKS{FILESYSTEMS}{$dev}{DEVICE} \t$DISKS{FILESYSTEMS}{$dev}{MOUNT} \t\t$DISKS{FILESYSTEMS}{$dev}{TYPE} \t$DISKS{FILESYSTEMS}{$dev}{OPTIONS} \t0 0\n";
                }        
        }        

        close(FSTAB);

	return 0;

} # create_fstab_file


sub create_systemconfig_conf {
# Create the /etc/systemconfig/systemconfig.conf file for the image
# Input:        image path, %DISKS structure
# Returns:      1 if failure, 0 if ok
	my ($ipath,%DISKS) = @_;

	&verbose("Modifying systemconfig.conf file for image."); 
	my ($rootdev, $bootdev);
        foreach my $dev (keys %{$DISKS{FILESYSTEMS}}) {
                if ($DISKS{FILESYSTEMS}{$dev}{MOUNT} eq "/") {
                        $rootdev=$dev;
                }
		if ($DISKS{FILESYSTEMS}{$dev}{MOUNT} =~ m/\/boot/) {
			$bootdev=$dev;
		}
	}
	if (!$rootdev) {
		return 1;
	}
	if (!$bootdev) {
		$bootdev=$rootdev;
	}
	if (!($bootdev =~ m:/dev/md:)) {
        if ($bootdev =~ /c[0-9]+d[0-9]+p[0-9]*$/) {
            $bootdev =~ s/p[0-9]*$//;
        } else {
    		$bootdev =~ s/[0-9]*$//;
        }
	}
	return SystemInstaller::Image::write_scconf($ipath, $rootdev, $bootdev);
} # create_systemconfig_conf

=head1 NAME

SystemInstaller::Partition::IA - Creates the partitioning and filesystem files required for machines with ia64 or x86 architecture.

=head1 SYNOPSIS

use SystemInstaller::Partition::IA;

if (&SystemInstaller::Partition::IA::create_partition_file($image_path,%DISKS){
        printf "Partition files not created\n";
 }

=head1 DESCRIPTION

The routines for partitioning and filesystem initialization for the ia64 and x86 machines.

=head1 FUNCTIONS

=over 4

=item create_partition_file($path,%DISKS)

Applies the partition and filesystem information in the %DISKS hash to 
the image stored at $path.

=head1 AUTHOR

Michael Chase-Salerno, mchasal@users.sf.net,
Stacy Woods, spwoods@us.ibm.com

=head1 SEE ALSO

L<SystemInstaller::Partition>, mksidisk(1)

=cut

1;
