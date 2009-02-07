package SystemInstaller::Tk::AddClients;

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
use SystemInstaller::Utils;
use SIS::Image;
use SIS::DB;
use strict;

@EXPORT = qw(addclients_window);


sub addclients_window {
    my $config = SystemInstaller::Utils::init_si_config();

    my $window = shift;
    my %vars = (
                title => "Add Clients to an SIS Image",
                imgname => "",
                basename => "",
                domainname => "",
                startinghostnum => "",
                startip => "",
                netmask => "",
                gateway => "",
                padding => "0",
                numhosts => "",
                noshow => {},
                # This is the dummy postinstall.  Postinstalls MUST return true, lest the sky falls
                postinstall => sub {return 1},
                @_,
               );

    # Get the list of images and remove the default selection
    my @allimages= list_image();
    my @mostimages;
    my $defimage;
    foreach my $img (@allimages) {
            if ($img->name eq $vars{imgname}) {
                    $defimage=$vars{imgname};
            } else {
                push(@mostimages,$img->name);
            }
    }
    # If the default selection wasn't found, just use 
    # the first defined image.
    $defimage = shift(@mostimages) unless $defimage;

    unless( $defimage ) {
        error_window($window,"You must build at least one image!");
        $window->Unbusy();
        return;
	}


    my %defaults = %vars;
    my %noshow = %{$vars{noshow}};

    my $addclient_window = $window->Toplevel();
    $addclient_window->withdraw;
    $addclient_window->title($vars{title});

    #
    #  First line:  What is your image name?
    # 

    my $imagebox=label_listbox_line($addclient_window, "Image Name", $defimage, \@mostimages,
                     helpbutton($addclient_window, 'Image Name Addclients')) unless $noshow{imgname};
    #
    #  Second line: What is your domain name?
    #

    label_entry_line($addclient_window, "Domain Name", \$vars{domainname},"",
                     helpbutton($addclient_window, 'Domain Name')) unless $noshow{domainname};

    #
    #  Third line: What is the base name?
    #

    label_entry_line($addclient_window, "Base Name", \$vars{basename},"",
                     helpbutton($addclient_window, 'Base Name')) unless $noshow{basename};

    my $numentry=label_entry_line($addclient_window, "Number of Hosts", \$vars{numhosts},"",
                     helpbutton($addclient_window, 'Number of Hosts')) unless $noshow{numhosts};

    $vars{startinghostnum} = nexthostnum( $vars{basename} ) || $vars{startinghostnum};
    label_entry_line($addclient_window, "Starting Number", \$vars{startinghostnum},"",
                     helpbutton($addclient_window,'Starting Number')) unless $noshow{startinghostnum};
    # Number padding
    label_entry_line($addclient_window, "Padding", \$vars{padding},"",
                     helpbutton($addclient_window,'Padding')) unless $noshow{padding};


    #
    #  More lines: Starting IP Addr?
    #


    $vars{startip} = nextip() || $vars{startip};
    label_entry_line($addclient_window, "Starting IP", \$vars{startip},"",
                     helpbutton($addclient_window, 'Starting IP')) unless $noshow{startip};
    label_entry_line($addclient_window, "Subnet Mask", \$vars{netmask},"",
                     helpbutton($addclient_window, 'Subnet Mask')) unless $noshow{netmask};
    label_entry_line($addclient_window, "Default Gateway", \$vars{gateway},"",
                     helpbutton($addclient_window, 'Default Gateway')) unless $noshow{gateway};

#    label_entry_line($addclient_window, "Ending IP", \$vars{endip}, [\&compute_hosts, \%vars]) unless $noshow{endip};

    # Then a whole bunch of control buttons

    my $reset_button = $addclient_window->Button(
                                             -text=>"Reset",
                                             -command=> [\&reset_window, $addclient_window, 
                                                         \%vars, \%defaults, {}], # imgname => $imgoption}],
                                             -pady => 8,
                                             -padx => 8,
                                            );

    my $activate_button = $addclient_window->Button(
                                                -text => "Add Clients",
                                                -command => [\&run_addclients, $addclient_window, $imagebox, $numentry, \%vars],
                                                -pady => 8,
                                                -padx => 8,
                                               );

    $reset_button->grid($activate_button, quit_button($addclient_window) , -sticky => "nesw");
    center_window( $addclient_window );

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

sub run_addclients {
    my ($window, $imagebox, $numentry, $vars) = @_;
    $window->Busy(-recurse => 1);
    my %hashkeys = (
                    numhosts => 'count',
                    basename => 'basename',
                    startinghostnum => 'start',
                    startip => 'ipstart',
                    gateway => 'gateway',
                    netmask => 'netmask',
                    domainname => 'domain',
                    padding => 'pad',
                   );

    unless( $$vars{numhosts} > 0 ) {
        error_window($window,"You must add at least one host!");
        $window->Unbusy();
        $numentry->focus;
        # -BL- selectionRange is no longer supported in perl-Tk-804
        #$numentry->selectionRange( 0, "end" );
        return undef;
    }

    my @imagesel=$imagebox->curselection;
    my $imagename=$imagebox->get($imagesel[0]);

    my $cmd = "mksirange --image $imagename ";
    foreach my $key (keys %hashkeys) {
        if($$vars{$key}) {
            $cmd .= " --$hashkeys{$key}=$$vars{$key}";
        }
    }

    !system($cmd) or (carp("Couldn't run mksirange: ($cmd) $!"),
                      error_window($window,"Couldn't run mksirange: $!"),
                      $window->Unbusy(),
                      return undef);

    if(ref($$vars{postinstall}) eq "CODE") {
        &{$$vars{postinstall}}($vars)  or (carp("Couldn't run postinstall"), 
                                          error_window($window,"There was an error running the post addclients script, please check your logs for more info"),
                                          $window->Unbusy(),
                                          return 0);
    }
    if(ref($$vars{postinstall}) eq "ARRAY") {
        my $sub = shift(@{$$vars{postinstall}});
        &$sub($vars, @{$$vars{postinstall}}) or (carp("Couldn't run postinstall"),
                                                 error_window($window,"There was an error running the post addclients script, please check your logs for more info"),
                                                 $window->Unbusy(),
                                                 return 0);
    }

    done_window($window, "Successfully created clients for image \"$imagename\"");

    $$vars{startinghostnum} = nexthostnum( $$vars{basename} ) || $$vars{startinghostnum};
    $$vars{startip} = nextip() || $$vars{startip};
    $window->update();

    $window->Unbusy();
    return 1;
}

sub nexthostnum($)
{
    my $bn = quotemeta shift;

    my @hosts = grep { /^$bn\d/ } map { $_->name } list_client();
    return 1 + (sort { $a <=> $b } map { /(\d+)$/ } @hosts)[-1] if @hosts;
}

sub nextip()
{
    my @allip = map { $_->ip } list_adapter();
    if( @allip ) {
        my $lastip = hex( (sort map { sprintf "%.2x%.2x%.2x%.2x", split /\./, $_ } @allip)[-1] );
        my $x;
        do {
            $lastip++;
            $x = sprintf "%8.8x", $lastip;
        } while $x =~ /00$/ || $x =~ /ff$/;
        return join( ".", map { (sprintf "%d", hex $_) } ($x =~ /../g));
    }
}

1;
