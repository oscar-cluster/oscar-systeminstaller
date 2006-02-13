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

# Use Schwartzian transform to sort clients by node names alphabetically and numerically.
# Names w/o numeric suffix precede those with numeric suffix.
sub sortclients(@) {
	return map { $_->[0] }
	       sort { $a->[1] cmp $b->[1] || ($a->[2]||-1) <=> ($b->[2]||-1) }
	       map { [$_, $_->name =~ /^([\D]+)([\d]*)$/] }
	       @_;
}

sub synchosts {
	my @delhosts=@_;
	my @machinelist = list_client();
	my @adapterlist = list_adapter(devname=>"eth0");
        my %ADAPTERS;
        &verbose("Parsing adapters");
        foreach my $adap (@adapterlist) {
                # will need to check if this is the install
                # adapter in the future.
                $ADAPTERS{$adap->client}=$adap->ip;
        }
	&verbose("Syncing /etc/hosts/ to database.");
	open (HOSTS,"/etc/hosts");
	open (TMP,">/tmp/hosts.$$");
	# First find all of the SIS entries and remove them.
	&verbose("Removing old SIS entries");
	while (<HOSTS>) {
		my $found=0;
		my ($ip,$lhost,$shost)=split;
                if ($_ =~ /.*managed by SIS.*/) {
                        $found=1;
                }
                if ($ADAPTERS{$shost}) {
			$found=1;
		}
		foreach my $mach (@delhosts) {
			if ($shost eq $mach) {
				$found=1;
			}
		}
		unless ($found) {
			unless ($_ =~ /^$/ ) {
				print TMP $_;
			}
		}
	}
	close(HOSTS);

	# Now put the entries that are in the DB in the file.
	&verbose("Re-adding currently defined machines.");

	print TMP "\n# These entries are managed by SIS, please don't modify them.\n";
	foreach my $mach (sortclients @machinelist) {
                my $name=$mach->name;
                if ($ADAPTERS{$name}) {
	                printf TMP "%-20.20s %s\t%s\n", $ADAPTERS{$name},$mach->hostname,$name;
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
