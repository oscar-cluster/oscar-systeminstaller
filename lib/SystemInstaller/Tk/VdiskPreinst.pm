package SystemInstaller::Tk::VdiskPreinst;

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
#
#  Igor Grobman <ilgrobma@us.ibm.com>
#
#
use base qw(Exporter);
use vars qw(@EXPORT %oldvars);
use Data::Dumper;
use AppConfig;
use POSIX;
use Carp;
use Tk;
use Tk::FileSelect;
use SystemInstaller::Tk::Common;
use SystemInstaller::Utils;
use SystemInstaller::Tk::Help;
use strict;

@EXPORT = qw(vdiskpreinst_window);


sub vdiskpreinst_window {
    my $config = SystemInstaller::Utils::init_si_config();

    my $window = shift;
    my %vars = (
                imgname => "",
                noshow => {},
                # This is the dummy postinstall.  Postinstalls MUST return true, lest the sky falls
                postinstall => sub {return 1},
                @_,
               );

    my %defaults = %vars;
    my %noshow = %{$vars{noshow}};

    my $vdiskpreinst_window = $window->Toplevel();
    $vdiskpreinst_window->title("Run Preinstall Script for Virtual Disks");

    #
    #  First line:  What is you image name?
    # 
#    my $imgoption = label_option_line($vdiskpreinst_window, "Image Name",
#                                      \$vars{imgname},["",listimages($config->rsyncd_conf)]) unless $noshow{imgname};
    label_entry_line($vdiskpreinst_window, "Image Name", \$vars{imgname},"",
                     helpbutton($vdiskpreinst_window, 'Image Name VdiskPreinst')) unless $noshow{imgname};
    
   # Then a whole bunch of control buttons

    my $reset_button = $vdiskpreinst_window->Button(
                                             -text=>"Reset",
                                             -command=> [\&reset_window, $vdiskpreinst_window, 
                                                         \%vars, \%defaults, {}], # imgname => $imgoption}],
                                             -pady => 8,
                                             -padx => 8,
                                            );

    my $activate_button = $vdiskpreinst_window->Button(
                                                -text => "Run Vdisk Preinstall",
                                                -command => [\&run_vdiskpreinst, $vdiskpreinst_window, \%vars],
                                                -pady => 8,
                                                -padx => 8,
                                               );

    $reset_button->grid($activate_button, quit_button($vdiskpreinst_window) , -sticky => "nesw");

}

sub what_changed {
    my $vars = shift;

    foreach my $key (qw(startinghostnum endinghostnum startip endip numhosts)) {
        if($oldvars{$key} ne $$vars{$key}) {
            %oldvars = %$vars;
            return $key;
        }
    }
    return undef;
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

sub run_vdiskpreinst {
    my ($window, $vars) = @_;
    $window->Busy(-recurse => 1);
    my %hashkeys = (
                    imgname => 'image',
                   );
   my $scriptdir="/var/lib/systemimager/scripts";

    my $cmd = "sh $scriptdir/main-install/$$vars{imgname}.master.preinst";

    open(OUTPUT, $cmd |") or (carp("Couldn't run virtual disk preinstall script: $!"),
                      error_window($window,"Couldn't run vdiskpreinstall: $!"),
                      $window->Unbusy(),
                      return undef);
    while(<OUTPUT>) {
        print $_;
        $window->update();
    }
   
   close(OUTPUT) or (carp("Couldn't run command $cmd"),
                      error_window($window,"Couldn't run command $cmd"),
                      $window->Unbusy(), return undef);

    if(ref($$vars{postinstall}) eq "CODE") {
        &{$$vars{postinstall}}($vars)  or (carp("Couldn't run postinstall"), 
                                          error_window($window,"There was an error running the post vdisk preinst script, please check your logs for more info"),
                                          $window->Unbusy(),
                                          return 0);
    }
    if(ref($$vars{postinstall}) eq "ARRAY") {
        my $sub = shift(@{$$vars{postinstall}});
        &$sub($vars, @{$$vars{postinstall}}) or (carp("Couldn't run postinstall"),
                                                 error_window($window,"There was an error running the post vdiskpreinst script, please check your logs for more info"),
                                                 $window->Unbusy(),
                                                 return 0);
    }

    done_window($window, "Successfully created virtual disk for image $$vars{imgname}");
    $window->Unbusy();
    return 1;
}

1;
