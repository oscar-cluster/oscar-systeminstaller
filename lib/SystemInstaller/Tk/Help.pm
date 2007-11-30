package SystemInstaller::Tk::Help;

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

use base qw(Exporter);
use SystemInstaller::Tk::Common;
use Tk::ROText;
use vars qw(@EXPORT %Help);
use strict;

@EXPORT = qw(%Help helpwindow helpbutton);

%Help = (
	 #### Build Image Help
         "Image Name" => "Image Name:\n\nThe name you wish to call the image.",
	 "Target Distribution" => "Target Distribution:\n\nThis menu allows the selection of the distribution/architecture on which the image will be based. The choices are from the distribution repositories located in /tftpboot/distro.\n\n The selection of one menu item leads to an automatic change of the Package Repositories entries as well as the regeneration of the package list file located in /tmp/rpmlist_*\n",
         "Package Repositories" => "Package Repositories:\n\nThis option specifies the locations which contain the packages (RPM, Deb, or other) which will be used to build the image.\n\nThree repositories are necessary: repository for common packages for OSCAR, repository for Linux distribution specific packages for OSCAR and repository for Linux distribution packages.",
         "Package File" => "Package File:\n\nThis option specifies a text file which contains a list of all the packages that should be installed.\nThere are various samples for several distributions under \$OSCAR_HOME/oscarsamples",
         "Package Group" => "Additional Package Group:\n\nThis option specifies a text file which contains a list of packages that should be installed in addition to the distribution's base packages.\nThis allows to build images with same base distro packages but different add-on packages.",
         "Disk File" => "Disk File:\n\nThis option specifies a text file which contains the disk partition table for the image.\n\nFor more information on the format please see the mksidisk man page. There is a sample disktable in /usr/share/doc/systeminstaller-<version>/disktable.",
         "Target Architecture" => "Target Architecture:\n\nThis option specifies what architecture the images should be built for.  The value will default to the current architecture.\n\nThere is some support for cross architecture image building, though it is mostly untested.",
         "Post Install Action" => "Post Install Action:\n\nThis option specifies what the client should do after installation has completed.  The options are:\n\nbeep - Clients will beep incessantly after succussful completion of an autoinstall.\n\nreboot - Clients will reboot themselves after successful completion of an autoinstall.\n\nshutdown -- Clients will halt themselves after successful completion of an autoinstall.\n\nkexec -- Clients will boot the kernels via kexec that were just installed after successful completion of an autoinstall.",
         "Virtual Disk" => "Virtual Disk:\n\nSpecify a virtual disk device for the Iseries machine.  The specified device will have the image copied to it, and can serve as a master virtual disk, that can be replicated using CPYNWSSTG commands.  WARNING:The contents of the  device  specified here will be completely destroyed.",
         "IP Method" => "IP Assignment Method:\n\nThis option specifies how ip addresses will be assigned to clients. The options are:\n\ndhcp -- A DHCP server will assign IP addresses dynamically to clients installed. They may be assigned a different address each time.\n\nstatic -- The IP address the client uses during autoinstall will be permanently assigned to that client.\n\nreplicant -- Don't mess with the network settings in this image.  I'm using it as a backup and quick restore mechanism for a single machine.",
         #### Now we get the Addclients Help
         "Image Name Addclients" => "Image Name:\n\nThe name of the image that this client will be attached to.  This image must already exist on your image server.",
         "Domain Name" => "Domain Name:\n\nThe network domain name you wish to be assigned to the client.",
         "Base Name" => "Base Name:\n\nThe hostname stub you wish to use for the client.  This value will be prepended to the number of the client to determine the client's hostname.",
         "Number of Hosts" => "Number of Hosts:\n\nThe number of clients you wish to be defined with this definition.",
         "Starting Number" => "Starting Number:\n\nThe first number in the range of clients you wish to allocate.\n\nFor instance, if you created a definition with 'Base Name' = 'www', 'Number of Hosts' = '5', and 'Starting Number' = '5', you would get hosts www5, www6, www7, www8, and www9.",
         "Padding" => "The number of digits to pad the node names with.\n\nFor example a value of 3 would create nodes with names like www001, www002, where a value of 0 would create nodes like www1, www2.",
         "Starting IP" => "Starting IP:\n\nThe IP address in the range of IPs to allocate.\n\nAllocating a range of ips accross a subnet boundry is not currently supported.",
         "Subnet Mask" => "Subnet Mask:\n\nThe Network Subnet Mask.",
         "Default Gateway" => "Default Gateway:\n\nThe default route to send all packets.",
         #### Update Client helps
         "Client Names" => "Client Names:\n\nA comma delimited list of client names that you wish to update.",
         "Image Name Updateclients" => "Image Name:\n\nThe image you wish the clients to use.",
         "MAC Address" => "MAC Address:\n\nThe MAC address of the install adapter of the client.",
         "IP Address" => "IP Address:\n\nThe IP address of the install adapter of the client.",
         "Root password" => "Root password:\n\nThe root password to be set in the image. It must be specified twice to ensure that it is correct.",
         
        );

# 
#  open_help_window
#

sub helpbutton {
    my ($window, $tag) = @_;
    $window->Button(
                    -text=>"Help",
                    -takefocus => 0,
                    -command=> [\&helpwindow, $window, $tag],
                    -pady => 4,
                    -padx => 8,
                   );
}

sub helpwindow {
    my $window = shift;
    my $tag = shift;
    my $helpwindow = $window->Toplevel();
    $helpwindow->withdraw;
    $helpwindow->title("Help About: $tag");
    my $ro = $helpwindow->Message(-text => $Help{$tag});
    $ro->pack(-fill => "both", -expand => 1);
    quit_button($helpwindow)->pack(-fill => "x");
    center_window( $helpwindow );
}

1;
