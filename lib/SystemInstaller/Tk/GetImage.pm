package SystemInstaller::Tk::GetImage;

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
use vars qw(@EXPORT);
use Data::Dumper;
use AppConfig;
use File::Copy;
use POSIX;
use Tk;
use SystemInstaller::Tk::Common;
use SystemInstaller::Tk::Help;
use SystemInstaller::Tk::Image;
use Carp;
use strict;

@EXPORT = qw(creategetimage_window);

sub creategetimage_window {
    my $config = init_si_config();

    my $window = shift;
    my %vars = (
                imgpath => $config->default_image_dir,
                imgname => "",
                ipmeth => "",
                client => "",
                user   => "",
                piaction => "",
                extraflags => "",
                # This is the dummy post install.  Postinstalls MUST return true lest things go funky.
                postinstall => sub {return 1},
                noshow => {},
                @_,
               );

    my %defaults = %vars;
    my %noshow = %{$vars{noshow}};

    my $image_window = $window->Toplevel();
    $image_window->title("Fetch a System Installation Suite Image");
    my $message = $image_window->Message(-text => "Fill out the following fields to fetch a System Installation Suite image.  If you need help on any field, click the help button next to it", -justify => "left", -aspect => 700);
    $message->grid("-","-","-");

    #
    #  What is your image name?
    # 

    label_entry_line($image_window, "Image Name", \$vars{imgname},"","x",helpbutton($image_window, "Image Name")) unless $noshow{pkgpath};

    label_entry_line($image_window, "Client Name", \$vars{client},"","x",helpbutton($image_window, "Fetch Client")) unless $noshow{client};

    label_entry_line($image_window, "SSH User Name", \$vars{user},"","x",helpbutton($image_window, "SSH User")) unless $noshow{user};
    
    #
    #  What is your ip assignment method?
    #

    my @ipoptions = qw( dynamic_dhcp replicant static static_dhcp );

    my $ipoption = label_option_line($image_window, "IP Assignment Method",
                                     \$vars{ipmeth},\@ipoptions, "x",
                                     helpbutton($image_window, "IP Method")) unless $noshow{ipmeth};

    #
    #  What is the post install action?
    #

    my @postinstall = qw(beep reboot shutdown);

    my $postoption = label_option_line($image_window, "Post Install Action",
                                       \$vars{piaction},\@postinstall, "x",
                                      helpbutton($image_window, "Post Install Action")) unless $noshow{piaction};

    # Then a whole bunch of control buttons
    
    my $reset_button = $image_window->Button(
                                             -text=>"Reset",
                                             -command=> [\&reset_window, $image_window, 
                                                         \%vars, \%defaults, {piaction => $postoption,
                                                                              ipmeth => $ipoption,
                                                                             },
                                                        ],
                                            -pady => 8,
                                            -padx => 8,
                                           );

    

    my $activate_button = $image_window->Button(
                                                -text => "Fetch Image",
                                                -command => [\&get_image, \%vars, $image_window],
                                                -pady => 8,
                                                -padx => 8,
                                               );
    
    $reset_button->grid($activate_button, quit_button($image_window),"-" , -sticky => "nesw");
    

    # key bindings
    $image_window->bind("<Control-q>",sub {$image_window->destroy});
    $image_window->bind("<Control-r>",sub {$reset_button->invoke});
    
}

sub reset_window {
    my ($window, $curvars, $defvars, $optiondefaults) = @_;
    resethash($curvars, $defvars);
    foreach my $key (keys %$optiondefaults) {
        if($$optiondefaults{$key} and $$curvars{$key}) {
            $$optiondefaults{$key}->setOption($$curvars{$key});
        }
    }
}

sub get_image {
    my $vars = shift;
    my $window = shift;
    $window->Busy(-recurse => 1);
    my $user="";
    unless ($$vars{user} eq "") {
            $user="--user $$vars{user}";
    }
    my $cmd = "mksiimage --Get --name $$vars{imgname} --path $$vars{imgpath}/$$vars{imgname} --client $$vars{client} $user --verbose $$vars{extraflags}";
    
    open(OUTPUT,"$cmd |") or (carp("Couldn't run command $cmd"), 
                              $window->Unbusy(), return undef);
    while(<OUTPUT>) {
            print "$_";
    }

    close(OUTPUT) or (carp("Command $cmd fail to run properly"), 
                      done_window($window, "Failed to create Image!"),
                      $window->Unbusy(),
                      return undef);

    my $mkaiscmd = $main::config->mkaiscript . " -quiet -image $$vars{imgname} -force -ip-assignment $$vars{ipmeth} -post-install $$vars{piaction}";
    !system($mkaiscmd) or (carp("Couldn't run $mkaiscmd"), $window->Unbusy(), return undef);

    print "Ran si_mkautoinstallscript\n";

    # This allows for an arbitrary callback to be registered.
    # It will get a reference to all the variables that have been defined for the image

    if(ref($$vars{postinstall}) eq "CODE") {
        &{$$vars{postinstall}}($vars) or (carp("Couldn't run postinstall"), 
                                          error_window($window,"There was an error running the post image building script, please check your logs for more info"), 
                                          $window->Unbusy(),
                                          return 0);
    }
    if(ref($$vars{postinstall}) eq "ARRAY") {
        my $sub = shift(@{$$vars{postinstall}});
        &$sub($vars, @{$$vars{postinstall}}) or (carp("Couldn't run postinstall"), 
                                                 error_window($window,"There was an error running the post image building script, please check your logs for more info"), 
                                                 $window->Unbusy(), 
                                                 return 0);
    }

    done_window($window, "Successfully fetched image $$vars{imgname}", sub {$a = shift; $a->value(0); $a->update();});
    $window->Unbusy();
    return 1;
}


1;
