package SystemInstaller::Tk::UpdateClient;

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
use vars qw(@EXPORT %oldvars);
use Data::Dumper;
use AppConfig;
use POSIX;
use Carp;
use Tk;
use Tk::FileSelect;
use SystemInstaller::Tk::Common;
use SystemInstaller::Tk::Help;
use strict;

@EXPORT = qw(updateclient_window);


sub updateclient_window {
    my $config = init_si_config();

    my $window = shift;
    my %vars = (
                clients => "",
                domainname => "",
                startip => "",
                netmask => "",
                gateway => "",
                noshow => {},
                # This is the dummy postinstall.  Postinstalls MUST return true, lest the sky falls
                postinstall => sub {return 1},
                @_,
               );

    my %defaults = %vars;
    my %noshow = %{$vars{noshow}};
    $vars{clientlist}=join(',',@{$vars{clients}});

    my $updateclient_window = $window->Toplevel();
    $updateclient_window->title("Update Client Definitions");

    #
    # Client names
    label_entry_line($updateclient_window, "Client Names", \$vars{clientlist},"",
                     helpbutton($updateclient_window, 'Client Names')) unless $noshow{clients};

    #
    #  First line:  What is you image name?
    # 
    label_entry_line($updateclient_window, "Image Name", \$vars{imgname},"",
                     helpbutton($updateclient_window, 'Image Name Updateclients')) unless $noshow{imgname};

    #
    #  Second line: What is your domain name?
    #

    label_entry_line($updateclient_window, "Domain Name", \$vars{domainname},"",
                     helpbutton($updateclient_window, 'Domain Name')) unless $noshow{domainname};

    #
    # IP info
    #
    label_entry_line($updateclient_window, "MACAddress", \$vars{startip},"",
                     helpbutton($updateclient_window, 'MAC Address')) unless $noshow{MAC};
    label_entry_line($updateclient_window, "IP Address", \$vars{startip},"",
                     helpbutton($updateclient_window, 'IP Address')) unless $noshow{ipaddr};
    label_entry_line($updateclient_window, "Subnet Mask", \$vars{netmask},"",
                     helpbutton($updateclient_window, 'Subnet Mask')) unless $noshow{netmask};
    label_entry_line($updateclient_window, "Default Gateway", \$vars{gateway},"",
                     helpbutton($updateclient_window, 'Default Gateway')) unless $noshow{gateway};


    # Then a whole bunch of control buttons

    my $reset_button = $updateclient_window->Button(
                                             -text=>"Reset",
                                             -command=> [\&reset_window, $updateclient_window, 
                                                         \%vars, \%defaults, {}],
                                             -pady => 8,
                                             -padx => 8,
                                            );

    my $activate_button = $updateclient_window->Button(
                                                -text => "Update Clients",
                                                -command => [\&run_updateclient, $updateclient_window, \%vars],
                                                -pady => 8,
                                                -padx => 8,
                                               );

    $reset_button->grid($activate_button, quit_button($updateclient_window) , -sticky => "nesw");

}

sub reset_window {
    my ($window, $curvars, $defvars, $optiondefaults) = @_;
    resethash($curvars, $defvars);
    foreach my $key (keys %$optiondefaults) {
        if($$optiondefaults{$key} and $$curvars{$key}) {
            $$optiondefaults{$key}->setOption($$curvars{$key});
        }
    }
    return 1;
}

sub run_updateclient {
    my ($window, $vars) = @_;
    $window->Busy(-recurse => 1);
    my %hashkeys = (
                    imgname => 'image',
                    startip => 'ipaddress',
                    gateway => 'gateway',
                    netmask => 'netmask',
                    domainname => 'domain',
                    MAC    =>  'MACaddress',
                    clientlist => 'name',
                   );

    my $cmd = "mksimachine --Update";
    foreach my $key (keys %hashkeys) {
        if($$vars{$key}) {
            $cmd .= " --$hashkeys{$key}=$$vars{$key}";
        }
    }

    !system($cmd) or (carp("Couldn't run mksimachine: $!"),
                      error_window($window,"Couldn't run mksimachine: $!"),
                      $window->Unbusy(),
                      return undef);

    if(ref($$vars{postinstall}) eq "CODE") {
        &{$$vars{postinstall}}($vars)  or (carp("Couldn't run postinstall"), 
                                          error_window($window,"There was an error running the post client update script, please check your logs for more info"),
                                          $window->Unbusy(),
                                          return 0);
    }
    if(ref($$vars{postinstall}) eq "ARRAY") {
        my $sub = shift(@{$$vars{postinstall}});
        &$sub($vars, @{$$vars{postinstall}}) or (carp("Couldn't run postinstall"),
                                                 error_window($window,"There was an error running the post client update script, please check your logs for more info"),
                                                 $window->Unbusy(),
                                                 return 0);
    }

    done_window($window, "Successfully updated clients");
    $window->Unbusy();
    return 1;
}

1;
