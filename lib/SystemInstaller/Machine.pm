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

use strict;
use vars qw($VERSION @EXPORT);
use base qw(Exporter);
use SIS::Client;
use SIS::Adapter;
use SIS::Image;
use SIS::DB;
use SystemInstaller::Log qw (verbose);
use File::Copy;
use Data::Dumper;
use Carp;

@EXPORT = qw(get_machine_listing synchosts linkscript);

sub get_machine_listing {
    my $image = shift;

    my @machines;
    if ($image) {
        @machines = list_client(imagename=>$image);
    } else {
        @machines = list_client();
    }

    my %results = ();
    
    foreach my $machine (@machines) {
        my $adapter = list_adapter(client=>$machine->name, devname=>"eth0");
        $results{$machine->name} = {
                                      HOST => $machine->hostname,
                                      DOMAIN => $machine->domainname,
                                      NUM_PROCS => $machine->proccount,
                                      IPADDR => $adapter->ip
                                     };
    }
    return %results;
}

sub adapter_devs {
    my %dev;
    my @adapterlist = list_adapter();

    foreach my $adap (@adapterlist) {
	my $d = $adap->devname;
	$dev{$d} = 1;
    }
    return sort(keys(%dev));
}

# Use Schwartzian transform to sort clients by node names alphabetically and numerically.
# Names w/o numeric suffix precede those with numeric suffix.
sub sortclients(@) {
	return map { $_->[0] }
	       sort { $a->[1] cmp $b->[1] || ($a->[2]||-1) <=> ($b->[2]||-1) }
	       map { [$_, $_->name =~ /^([\D]+)([\d]*)$/] }
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

sub synchosts {
	my @delhosts=@_;
	my @machinelist = list_client();
	my @adapterlist = list_adapter();
	my @devlist = adapter_devs();
        my %ADAPTERS;
	my %APPLIANCES;
        &verbose("Parsing adapters");
        foreach my $adap (@adapterlist) {
	    my $name = $adap->client;
	    $ADAPTERS{$adap->devname}{$name} = $adap->ip;
	    if ($name =~ /^__(.*)__$/) {
		my $client = $1;
		$APPLIANCES{$client} = $adap->ip;
	    }
        }
	&verbose("Syncing /etc/hosts/ to database.");
	open (HOSTS,"/etc/hosts");
	open (TMP,">/tmp/hosts.$$");
	# First find all of the SIS entries and remove them.
	&verbose("Removing old SIS entries");
	my $below_line = 0;
	while (<HOSTS>) {
		my $found=0;
		my ($ip,$lhost,$shost)=split;
		if ($lhost && !$shost) {
		    $shost = $lhost;
		}
                if ($_ =~ /.*managed by SIS.*/) {
                        $found=1;
			$below_line = 1;
                }
		for my $d (@devlist) {
		    my $hname = hnamedev($d, $shost);
		    if ($ADAPTERS{$d}{$hname}) {
			$found=1;
		    }
		}
		if ($APPLIANCES{$shost}) {
		    $found=1;
		}
		foreach my $mach (@delhosts) {
			if ($shost eq $mach) {
				$found=1;
			}
		}
		unless ($found || $below_line) {
			unless ($_ =~ /^$/ || $_ =~ /^\#/) {
				print TMP $_;
			}
		}
	}
	close(HOSTS);

	# Now put the entries that are in the DB in the file.
	&verbose("Re-adding currently defined machines.");

	print TMP "\n# These entries are managed by SIS, please don't modify them.\n";
	foreach my $dev (@devlist) {
	    print TMP "\n# $dev addresses\n";
	    foreach my $mach (sortclients @machinelist) {
                my $name=$mach->name;
		if ($dev eq "eth0") {
		    if ($ADAPTERS{$dev}{$name}) {
	                printf TMP "%-20.20s %s\t%s\n",
			$ADAPTERS{$dev}{$name}, $mach->hostname, $name;
		    }
		} else {
		    my $dname = devhname($dev, $name);
		    if ($ADAPTERS{$dev}{$name}) {
	                printf TMP "%-20.20s %s\n",
			$ADAPTERS{$dev}{$name}, $dname;
		    }
		}
	    }
	}
	if (scalar(keys(%APPLIANCES))) {
	    print TMP "\n# Appliance IPs\n";
	    foreach my $appl (sort(keys(%APPLIANCES))) {
		printf TMP "%-20.20s %s\n", $APPLIANCES{$appl}, $appl;
	    }
	}
	close(TMP);
	&verbose("Moving temp file to actual location.");
	move("/tmp/hosts.$$","/etc/hosts");
	&verbose("Copying hosts file to scripts directory.");
        my $aidir=$main::config->autoinstall_script_dir;
        copy("/etc/hosts",$aidir);
	
} #synchosts

sub linkscript {
        my $client=shift;
        if (! symlink($client->imagename . ".master",$main::config->autoinstall_script_dir ."/". $client->name . ".sh")) {
                carp("Unable to create new script link for machine ".$client->name);
                return 0;
        }
        return 1;
}
1;
