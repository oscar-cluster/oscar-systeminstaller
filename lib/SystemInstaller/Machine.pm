package SystemInstaller::Machine;

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

#   Sean Dague <japh@us.ibm.com>
#   Copyright (c) 2009 Oak Ridge National Laboratory.
#                      Geoffroy R. Vallee <valleegr@ornl.gov>
#                      All rights reserved.


use strict;
use vars qw(@EXPORT);
use base qw(Exporter);
use SIS::Client;
use SIS::Adapter;
use SIS::Image;
use SIS::NewDB;
use SystemInstaller::Env qw ($config);
use SystemInstaller::Log qw (verbose);
#use SystemInstaller::Utils;
#use SystemImager::JConfig qw($jconfig);
use File::Copy;
use Carp;

@EXPORT = qw(get_machine_listing synchosts linkscript);

sub get_machine_listing {
    my $image = shift;

    my @machines;
    if ($image) {
        @machines = SIS::NewDB::list_client(imagename=>$image);
    } else {
        @machines = SIS::NewDB::list_client();
    }

    my %results = ();
    
    foreach my $machine (@machines) {
        my %h = (client=>$machine->{name}, devname=>"eth0"); # FIXME: eth0 should not be hardcodded.
        my $adapter = SIS::NewDB::list_adapter(\%h);
        if (!defined $adapter) {
            carp "ERROR: Impossible to get adapter data (".
                $machine->{name}.")";
            return undef;
        }
        $results{$machine->{name}} = {
                                      HOST => $machine->{hostname},
                                      DOMAIN => $machine->{domainname},
                                      NUM_PROCS => $machine->{proccount},
                                      NUM_GPUS => $machine->{gpucount},
                                      IPADDR => @$adapter[0]->{ip}
                                     };
    }

    return %results;
}

sub adapter_devs {
    my %dev;
    my $adapterlist = SIS::NewDB::list_adapter(undef);

    foreach my $adap (@$adapterlist) {
        my $d = $adap->{devname};
        $dev{$d} = 1;
    }
    return sort(keys(%dev));
}

# Use Schwartzian transform to sort clients by node names alphabetically and numerically.
# Names w/o numeric suffix precede those with numeric suffix.
sub sortclients(@) {
	return map { $_->[0] }
	       sort { $a->[1] cmp $b->[1] || ($a->[2]||-1) <=> ($b->[2]||-1) }
	       map { [$_, $_->{name} =~ /^([\D]+)([\d]*)$/] }
	       @_;
}

# convert hostname to adapter-device specific name
sub devhname {
    my ($dev, $dname) = @_;

    if ($dev ne "eth0") {
	$dname =~ s/(\d+)$//;
	return $dname . $dev . $1;
    } else {
	return $dname;
    }
}

# convert adapter-specific name back to real hostname
sub hnamedev {
    my ($dev, $dname) = @_;

    if ($dev ne "eth0") {
	$dname =~ m/^(.*)$dev(\d+)$/;
	return $1 . $2;
    } else {
	return $dname;
    }
}

# Return: 0 if success, -1 else.
sub synchosts {
    my @delhosts=@_;
    my @machinelist = list_client();
    my $adapterlist = list_adapter(undef);
    my @devlist = adapter_devs();
    my %ADAPTERS;
    my %APPLIANCES;

    &verbose("Parsing adapters");
    foreach my $adap (@$adapterlist) {
        my $name = $adap->{client};
        $ADAPTERS{$adap->{devname}}{$name} = $adap->{ip};
        if ($name =~ /^__(.*)__$/) {
            my $client = $1;
            $APPLIANCES{$client} = $adap->ip;
        }
    }
	&verbose("Syncing /etc/hosts/ to database.");
#	open (HOSTS,"/etc/hosts");
#	open (TMP,">/tmp/hosts.$$");
	# First find all of the SIS entries and remove them.
#	&verbose("Removing old SIS entries");
#	my $below_line = 0;
#	while (<HOSTS>) {
#		my $found=0;
#		my ($ip,$lhost,$shost)=split;
#		if ($lhost && !$shost) {
#		    $shost = $lhost;
#		}
#                if ($_ =~ /.*managed by SIS.*/) {
#                        $found=1;
#			$below_line = 1;
#                }
#		for my $d (@devlist) {
#		    my $hname = hnamedev($d, $shost);
#		    if ($ADAPTERS{$d}{$hname}) {
#			$found=1;
#		    }
#		}
#		if ($APPLIANCES{$shost}) {
#		    $found=1;
#		}
#		foreach my $mach (@delhosts) {
#			if ($shost eq $mach) {
#				$found=1;
#			}
#		}
#		unless ($found || $below_line) {
#			unless ($_ =~ /^$/ || $_ =~ /^\#/) {
#				print TMP $_;
#			}
#		}
#	}
#	close(HOSTS);

	# Now put the entries that are in the DB in the file.
	&verbose("Re-adding currently defined machines.");
    my @data = ();
    my $s;
    require OSCAR::FileUtils;
	foreach my $dev (@devlist) {
	    foreach my $mach (sortclients @machinelist) {
        my $name=$mach->{name};
		if ($dev eq "eth0") {
		    if ($ADAPTERS{$dev}{$name}) {
                 $s = sprintf ("%-20.20s %s\t%s",
                              $ADAPTERS{$dev}{$name},
                              $mach->hostname,
                              $name);
                 push (@data, $s);
		    }
		} else {
		    my $dname = devhname($dev, $name);
		    if ($ADAPTERS{$dev}{$name}) {
	            $s = sprintf ("%-20.20s %s",
			                  $ADAPTERS{$dev}{$name},
                              $dname);
                push (@data, $s);
		    }
		}
	    }
	}
	if (scalar(keys(%APPLIANCES))) {
#	    print TMP "\n# Appliance IPs\n";
	    foreach my $appl (sort(keys(%APPLIANCES))) {
		    $s = fprintf ("%-20.20s %s", $APPLIANCES{$appl}, $appl);
            push (@data, $s);
	    }
	}
    if (OSCAR::FileUtils::replace_block_in_file ("/etc/hosts",
                                                 "OSCAR hosts",
                                                 \@data)) {
        carp "ERROR: Impossible to update the hosts in /etc/hosts";
        return -1;
    }
#	close(TMP);
#	&verbose("Moving temp file to actual location.");
#	move("/tmp/hosts.$$","/etc/hosts");
	&verbose("Copying hosts file to scripts directory.");
        my $aidir=$main::config->autoinstall_script_dir;
        copy("/etc/hosts",$aidir);
	
    return 0;
} #synchosts


# Return: 1 if success, 0 else.
sub linkscript ($) {
    my $client = shift;
    #    my %si_config = SystemInstaller::Utils::get_si_config ();
    my $script_dir = $config->autoinstall_script_dir;
    my $orig_file = $client->{imagename} . ".master";
    my $dest_file = "$script_dir/main-install/" . $client->{name} . ".sh";

    if (! -f "$script_dir/main-install/$orig_file") {
        carp "ERROR: Impossible to create the symlink, $orig_file does not exist";
        return 0;
    }

    if (! -d "$script_dir/main-install/") {
        carp "ERROR: Destination directory does not exist";
        return 0;
    }

    if (-f $dest_file) {
        print "[INFO] Deleting $dest_file\n";
        unlink ($dest_file);
        # We double check everything is fine
        if (-f $dest_file) {
            carp "ERROR: Impossible to create the symlink the destination ".
                 "file ($dest_file) already exists";
            return 0;
        }
    }

#        chdir($script_dir/main-install/);
    if (! symlink($orig_file, $dest_file)) {
         carp("Unable to create new script link for machine ".
              $client->{name} . "(orig: $orig_file, dest: $dest_file)");
         return 0;
    }

    return 1;
}
1;
