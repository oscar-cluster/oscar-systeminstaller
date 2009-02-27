package SystemInstaller::Tk::Image;

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

# $Id$
#
# Copyright (c) 2006      Erich Focht <efocht@hpce.nec.com>
# Copyright (c) 2007-2009 Geoffroy Vallee <valleegr@ornl.gov>
#                         Oak Ridge National Laboratory
#                         All rights reserved.

BEGIN {
    if (defined $ENV{OSCAR_HOME}) {
        unshift @INC, "$ENV{OSCAR_HOME}/lib";
    }
}

use base qw(Exporter);
use vars qw(@EXPORT);
use Data::Dumper;
use AppConfig;
use File::Copy;
use POSIX;
use Tk;
use Tk::ProgressBar;
use Tk::FileSelect;
use SystemInstaller::Log qw (verbose get_verbose);
use SystemInstaller::Tk::Common;
use SystemInstaller::Tk::Help;
use SystemInstaller::Passwd qw(update_user);
use SystemInstaller::Utils;
use Carp;
use SystemImager::Server;
use SystemImager::Common;
use SystemImager::Config;

# OSCAR specific stuff
use OSCAR::PackagePath;
use OSCAR::Database;

use strict;

@EXPORT = qw(
            createimage_basic_window
            createimage_window
            add2rsyncd
            delfromrsyncd
            );

# Global variable to store image parameters. This is needed to keep an hand on
# those parameters during the different phases of the GUI.
use vars qw ($image_params);

sub createimage_basic_window ($%) {
    my $config = SystemInstaller::Utils::init_si_config();

    my ($window, %vars) = @_;
    $vars{'title'} = "Create an SIS Image";
    $vars{'vdiskdev'} = "none";
    $vars{'pass1'} = "";
    $vars{'pass2'} = "";
    # This is the dummy post install.  Postinstalls MUST return true lest things go funky.
    $vars{'postinstall'} = sub {return 1};

    #
    # Validate image name.
    #
    my @images = &listimages;
    if( grep {$vars{imgname} eq $_} @images ) {
    my $last = 0;
    foreach (@images) {
        if( /^\Q$vars{imgname}\E(\d+)$/ ) {
        $last = $1 if $1 > $last;
        }
    }
    $vars{imgname} .= $last + 1;
    }

    my %defaults = %vars;
    my %noshow = %{$vars{noshow}};

    # locate all available distro pools
    my %distro_pools = &OSCAR::PackagePath::list_distro_pools();
    my @distros = sort(keys(%distro_pools));
    # We put the local distro first: this avoid the bug where the GUI has 
    # default values based on alphabetic sorting and others based on the local
    # distro, which makes the GUI kind of incoherent.
    #
    # Also note that this kind of functionality may be integrated into 
    # OS_Dectec. But since this is not currently the case (OS_Detect can detect
    # the distro of pools for Linux distributions, not OSCAR pools.
    my $os = OSCAR::OCA::OS_Detect::open("/");
    my $osid = $os->{distro}."-".$os->{distro_version}."-".$os->{arch};
    my $i = 0;
    while ($i < scalar(@distros)) {
        print "$i: $distros[$i]\n";
        if ($distros[$i] eq $osid) {
            my $d = $distros[$i];
            delete ($distros[$i]);
            unshift (@distros, $d);
        }
        $i++;
    }

    $noshow{vdiskdev}="yes" unless -d '/proc/iSeries';

    my $image_window = $window->Toplevel();
    $image_window->withdraw;
    $image_window->title($vars{title});
    my $message = $image_window->Message(-text => "Fill out the following fields to build a System Installation Suite image.  If you need help on any field, click the help button next to it",
                     -justify => "left",
                     -aspect => 800);
    $message->grid("-","-","-");

    #
    #  First line:  What is your image name?
    # 

    label_entry_line($image_window, "Image Name", \$vars{imgname},"","x",helpbutton($image_window, "Image Name"))
    unless $noshow{pkgpath};

    #
    #  Second line: Where is your package file
    #
    my $package_button = $image_window->Button(
                           -text=>"Choose a File...",
                           -command=> [\&selector2entry, 
                                       \$vars{pkgfile}, 
                                       "Select package list", 
                                       [["Package list", ".rpmlist"],
                                        ["All files", "*"]], 
                                       $image_window],
                           -pady => 4,
                           -padx => 4,
                           );
    label_entry_line($image_window,
             "Base Package File",
             \$vars{pkgfile},
             "", 
             $package_button,
             helpbutton($image_window, "Package File"))
    unless $noshow{pkgfile};

    # Few variables we use all the time.
    my ($labeltext, $entry, $label, @options);

    #
    # Select the target distribution
    #
    $labeltext = "Target Distribution";
    $vars{distro} = $distros[0];
    my $label2 = $image_window->Label(-text => "Target Distribution",
                      -anchor => "w");
    my $default = $vars{distro};

    my $distrooption = $image_window->Optionmenu(
        -options => \@distros,
        -command => sub {
            my $dist = shift;
            print "Selection: $dist\n";
            $vars{'distro'} = $dist;
        },
        -variable => \$vars{distro});
    $distrooption->setOption($default) if $default;

    my @morewidgets2 = helpbutton($image_window,
                      "Target Distribution");
    $label2->grid($distrooption, "x", @morewidgets2, -sticky => "nesw");

    #
    #  Fourth line:  disktable
    #
    my $disk_button = $image_window->Button(
                        -text=>"Choose a File...",
                        -command=> [\&selector2entry, 
                            \$vars{diskfile}, 
                            "Select disk configuration", 
                            [["Disk configuration", ".disk"],
                             ["All files", "*"]], 
                            $image_window],
                        -pady => 4,
                        -padx => 4,
                        );

    #
    # (only for iseries).  Virtual disk enable.
    # 

    label_entry_line($image_window, 
                     "Virtual Disk", 
                     \$vars{vdiskdev},
                     "","x",helpbutton($image_window, "Virtual Disk"))
    unless $noshow{vdiskdev};

    #
    # Disk partition file
    #

    label_entry_line($image_window,
                     "Disk Partition File",
                     \$vars{diskfile},
                     "",
                     $disk_button,
                     helpbutton($image_window, "Disk File"))
        unless $noshow{diskfile};

    # 
    # Set root password
    #

    my $passlabel=$image_window->Label(-text=>"Root password(confirm):", 
                                       -anchor=>"w");
    my $pass = $image_window->Entry(-textvariable=>\$vars{pass1}, -show=>"*");
    my $passconfirm = $image_window->Entry(-textvariable=>\$vars{pass2}, 
                                           -show=>"*", 
                                           -width=>14);
    $passlabel->grid($pass,$passconfirm,helpbutton($image_window, 
        "Root password"))
    unless $noshow{password};

    #
    #  What is the architecture?
    #

    my @archoptions = qw( i386 i486 i586 i686 ia64 ppc ppc64 x86_64 athlon amd64 );

    my $archoption = label_option_line($image_window, 
                                       "Target Architecture",
                                       \$vars{arch},\@archoptions, 
                                       "x",
                       helpbutton($image_window,
                                                  "Target Architecture"))
    unless $noshow{arch};

    #
    #  What is your ip assignment method?
    #

    my @ipoptions = qw( dhcp replicant static );

    my $ipoption = label_option_line($image_window, 
                                     "IP Assignment Method",
                                     \$vars{ipmeth},
                                     \@ipoptions, 
                                     "x",
                     helpbutton($image_window, "IP Method"))
    unless $noshow{ipmeth};

    #
    #  What is the post install action?
    #

    my @postinstall = qw(beep reboot shutdown kexec);

    my $postoption = label_option_line($image_window, "Post Install Action",
                       \$vars{piaction},\@postinstall, "x",
                       helpbutton($image_window, "Post Install Action"))
    unless $noshow{piaction};

    # Then a whole bunch of control buttons

    my $activate_button = $image_window->Button(
                        -text => "Build Image",
                        -command => [\&add_image, \%vars, $image_window],
                        -pady => 8,
                        -padx => 8,
                        );

    my $reset_button = $image_window->Button(
                         -text=>"Reset",
                         -command=> [
                             \&reset_window, $image_window, \%vars, \%defaults,
                             {
                                 piaction => $postoption,
                                 arch => $archoption,
                                 ipmeth => $ipoption,
                                 },
                             ],
                         -pady => 8,
                         -padx => 8,
                         );

    $reset_button->grid($activate_button,
                        quit_button($image_window),
                        "-" , 
                        -sticky => "nesw");

    # key bindings
    $image_window->bind("<Control-q>",sub {$image_window->destroy});
    $image_window->bind("<Control-r>",sub {$reset_button->invoke});

    center_window( $image_window );

    return (0);
}

# !!!! WARNING: This function is not anymore adapted to OSCAR, the OSCAR GUI
# should not use it anymore. Prefer createimage_basic_window instead. !!!!
sub createimage_window ($%) {
    my $config = SystemInstaller::Utils::init_si_config();

    my ($window, %vars) = @_;
    $vars{'title'} = "Create an SIS Image";
	$vars{'vdiskdev'} = "none";
	$vars{'pass1'} = "";
	$vars{'pass2'} = "";
	# This is the dummy post install.  Postinstalls MUST return true lest things go funky.
	$vars{'postinstall'} = sub {return 1};

    #
    # Validate image name.
    #
    my @images = &listimages;
    if( grep {$vars{imgname} eq $_} @images ) {
	my $last = 0;
	foreach (@images) {
	    if( /^\Q$vars{imgname}\E(\d+)$/ ) {
		$last = $1 if $1 > $last;
	    }
	}
	$vars{imgname} .= $last + 1;
    }

    my %defaults = %vars;
    my %noshow = %{$vars{noshow}};

    # locate all available distro pools
    my %distro_pools = &OSCAR::PackagePath::list_distro_pools();
    my @distros = sort(keys(%distro_pools));
    # We put the local distro first: this avoid the bug where the GUI has 
    # default values based on alphabetic sorting and others based on the local
    # distro, which makes the GUI kind of incoherent.
    #
    # Also note that this kind of functionality may be integrated into 
    # OS_Dectec. But since this is not currently the case (OS_Detect can detect
    # the distro of pools for Linux distributions, not OSCAR pools.
    my $os = OSCAR::OCA::OS_Detect::open("/");
    my $osid = $os->{distro}."-".$os->{distro_version}."-".$os->{arch};
    my $i = 0;
    while ($i < scalar(@distros)) {
        print "$i: $distros[$i]\n";
        if ($distros[$i] eq $osid) {
            my $d = $distros[$i];
            delete ($distros[$i]);
            unshift (@distros, $d);
        }
        $i++;
    }

    $noshow{vdiskdev}="yes" unless -d '/proc/iSeries';

    my $image_window = $window->Toplevel();
    $image_window->withdraw;
    $image_window->title($vars{title});
    my $message = $image_window->Message(-text => "Fill out the following fields to build a System Installation Suite image.  If you need help on any field, click the help button next to it",
					 -justify => "left",
					 -aspect => 800);
    $message->grid("-","-","-");

    #
    #  First line:  What is your image name?
    # 

    label_entry_line($image_window, "Image Name", \$vars{imgname},"","x",helpbutton($image_window, "Image Name"))
	unless $noshow{pkgpath};
	
    #
    #  Second line: Where is your package file
    #
    my $package_button = $image_window->Button(
					       -text=>"Choose a File...",
					       -command=> [\&selector2entry, 
                                       \$vars{pkgfile}, 
                                       "Select package list", 
                                       [["Package list", ".rpmlist"],
                                        ["All files", "*"]], 
                                       $image_window],
					       -pady => 4,
					       -padx => 4,
					       );
    label_entry_line($image_window,
		     "Base Package File",
		     \$vars{pkgfile},
		     "", 
		     $package_button,
		     helpbutton($image_window, "Package File"))
	unless $noshow{pkgfile};


    #
    #  Fourth Line:  where are your packages?
    #
    my @options;
    my $validate = "";
    my $labeltext = "Package Repositories";
    my $variable = $vars{pkgpath};
    my @morewidgets = helpbutton($image_window, "Package Repositories");
    if($validate) {
        @options = (
		    -validatecommand => $validate,
		    -validate => "focusout",
		    -width => 40,
        );
    }
    my $label = $image_window->Label(-text => "$labeltext: ", -anchor => "w");
    my $entry = $image_window->Entry(-textvariable => $variable, @options);
    $label->grid($entry, "x", @morewidgets, -sticky => "nw");


    #
    # Select an additional package group file, if passed.
    # $vars{package_group} must be a reference to an array of hash references.
    # Each hash reference must be of the form:
    #   { label => "group label" , path => path_to_group_file }
    #
    my ($selected_group, @group_labels);

    if ($vars{package_group} && ref($vars{package_group}) eq "ARRAY") {
	# Eliminate labels which point to non-existent files.
	for (@{$vars{package_group}}) {
	    if (-f $_->{path}) {
		push @group_labels, $_->{label};
	    }
	}
    }
    if (scalar(@group_labels)) {
	$vars{selected_group} = $group_labels[0];
	my $groupoption = label_option_line($image_window, 
					    "Additional Package Group",
					    \$vars{selected_group},
					    \@group_labels, 
					    "x",
					    helpbutton($image_window,
						       "Package Group"))
	    unless $noshow{package_group};
    }

    #
    # Select the target distribution
    #
    $labeltext = "Target Distribution";
    $vars{distro} = $distros[0];
    my $label2 = $image_window->Label(-text => "Target Distribution",
				      -anchor => "w");
    my $default = $vars{distro};

    my $distrooption = $image_window->Optionmenu(
        -options => \@distros,
        -command => sub {
            my $dist = shift;
            print "Selection: $dist\n";
            my %distro_pools = &OSCAR::PackagePath::list_distro_pools();
            foreach my $k (keys %distro_pools) {
                if ($k eq $dist) {
                    my $new_pools = "$distro_pools{$k}->{distro_repo},".
                                    "$distro_pools{$k}->{oscar_repo}";
                    print "the new package list is: $new_pools\n";
                    $vars{pkgpath} = $new_pools;
                    $entry->gridForget();                
                    $label = $image_window->Label(-text => "$labeltext: ",
						     -anchor => "w");
                    $entry = $image_window->Entry(-textvariable => $new_pools, @options);
                    $label->grid($entry, -row => 3, -column => 1, -sticky => "nw");
                }
            }
        },
        -variable => \$vars{distro});
    $distrooption->setOption($default) if $default;

    my @morewidgets2 = helpbutton($image_window,
                      "Target Distribution");
    $label2->grid($distrooption, "x", @morewidgets2, -sticky => "nesw");
	
    #
    #  Fourth line:  disktable
    #
    my $disk_button = $image_window->Button(
					    -text=>"Choose a File...",
					    -command=> [\&selector2entry, 
							\$vars{diskfile}, 
							"Select disk configuration", 
							[["Disk configuration", ".disk"],
							 ["All files", "*"]], 
							$image_window],
					    -pady => 4,
					    -padx => 4,
					    );

    #
    # (only for iseries).  Virtual disk enable.
    # 

    label_entry_line($image_window, 
                     "Virtual Disk", 
                     \$vars{vdiskdev},
                     "","x",helpbutton($image_window, "Virtual Disk"))
	unless $noshow{vdiskdev};

    #
    # Disk partition file
    #
	
    label_entry_line($image_window, "Disk Partition File", \$vars{diskfile}, "", 
		     $disk_button, helpbutton($image_window, "Disk File"))
	unless $noshow{diskfile};

    # 
    # Set root password
    #
	
    my $passlabel=$image_window->Label(-text=>"Root password(confirm):", 
                                       -anchor=>"w");
    my $pass = $image_window->Entry(-textvariable=>\$vars{pass1}, -show=>"*");
    my $passconfirm = $image_window->Entry(-textvariable=>\$vars{pass2}, 
                                           -show=>"*", 
                                           -width=>14);
    $passlabel->grid($pass,$passconfirm,helpbutton($image_window, "Root password"))
	unless $noshow{password};

    #
    #  What is the architecture?
    #
	
    my @archoptions = qw( i386 i486 i586 i686 ia64 ppc ppc64 x86_64 athlon amd64 );

    my $archoption = label_option_line($image_window, 
                                       "Target Architecture",
                                       \$vars{arch},\@archoptions, 
                                       "x",
				       helpbutton($image_window,
                                                  "Target Architecture"))
	unless $noshow{arch};

    #
    #  What is your ip assignment method?
    #

    my @ipoptions = qw( dhcp replicant static );

    my $ipoption = label_option_line($image_window, 
                                     "IP Assignment Method",
                                     \$vars{ipmeth},
                                     \@ipoptions, 
                                     "x",
				     helpbutton($image_window, "IP Method"))
	unless $noshow{ipmeth};

    #
    #  What is the post install action?
    #

    my @postinstall = qw(beep reboot shutdown kexec);

    my $postoption = label_option_line($image_window, "Post Install Action",
				       \$vars{piaction},\@postinstall, "x",
				       helpbutton($image_window, "Post Install Action"))
	unless $noshow{piaction};

    # Then a whole bunch of control buttons
	
    my $activate_button = $image_window->Button(
						-text => "Build Image",
						-command => [\&add_image, \%vars, $image_window],
						-pady => 8,
						-padx => 8,
						);
	
    my $reset_button = $image_window->Button(
					     -text=>"Reset",
					     -command=> [
							 \&reset_window, $image_window, \%vars, \%defaults,
							 {
							     piaction => $postoption,
							     arch => $archoption,
							     ipmeth => $ipoption,
							     },
							 ],
					     -pady => 8,
					     -padx => 8,
					     );

    $reset_button->grid($activate_button, 
                        quit_button($image_window),
                        "-" , 
                        -sticky => "nesw");
	
    # key bindings
    $image_window->bind("<Control-q>",sub {$image_window->destroy});
    $image_window->bind("<Control-r>",sub {$reset_button->invoke});

    center_window( $image_window );
}

our $progress_status;
our $progress_window;
our $progress_widget;
sub progress_bar {
    my ($window, $title) = @_;

    our $progress_window = $window->Toplevel();
    $progress_window->withdraw;
    $progress_window->title($title);

    $progress_window->Label(
			    -text => "Please be patient the image creation can take a while especially when using online repositories",
			    -anchor => "w",
			    )->pack(
				    -fill => 'x',
				    -padx => 4,
				    -pady => 4,
				    );

#    my $var;
#    our $progress_widget = $progress_window->ProgressBar(
#							 -variable => \$var,
#							 -takefocus => 0,
#							 -width => 20,
#							 -length => 400,
#							 -anchor => 'w',
#							 -from => 0,
#							 -to => 100,
#							 -blocks => 20,
#							 -colors => [0, 'green'], # [0, 'green', 50, 'yellow' , 80, 'red'],
#							 );
#    $progress_widget->pack(
#			   -fill => 'x',
#			   -padx => 4,
#			   );
#
#    $progress_window->Button(
#			     -text => "Cancel",
#			     -command => [ \&progress_cancel ],
#			     -padx => 8,
#			     -pady => 8,
#			     )->pack(
#				     -pady => 4,
#				     );
#    our $progress_status = 1;
    center_window( $progress_window );

}

sub progress_cancel {
    our $progress_status = 0;
}

sub progress_destroy {
    our $progress_window->destroy();
}

sub progress_update {
    my $value = shift;
    our $progress_widget->value( $value );
    $progress_widget->update();
}

sub progress_continue {
    our $progress_status;
    return $progress_status;
}

sub reset_window {
    my ($window, $curvars, $defvars, $optiondefaults) = @_;
    resethash($curvars, $defvars);
    foreach my $key (keys %$optiondefaults) {
	$$optiondefaults{$key}->setOption($$curvars{$key}) if($$optiondefaults{$key} && $$curvars{$key});
    }
}

sub listimages {
    my @list;
    if( open IN, "mksiimage --list |" ) {
	while (<IN>) {
	    next if $. <= 2;
	    chomp;
	    my @items = split;
	    push @list, $items[0] if $items[0];
	}
	close IN;
    }
    return @list;
}

# Wrapper around the add_image_build to deal with GUI specific stuff (display
# an error dialog if we cannot create the image and so on).
sub add_image ($$) {
    my ($vars, $window) = @_;

    print "[add_image] Starting... \n";
    my $config = SystemInstaller::Utils::init_si_config();
    my $rsyncd_conf = $config->rsyncd_conf();
    my $rsync_stub_dir = $config->rsync_stub_dir();
    my $verbose = &get_verbose();

    $window->Busy(-recurse => 1);

    my @imgs = &listimages;
    my $iexists = grep /^($$vars{imgname})$/, @imgs;
    print "Image $$vars{imgname} : ".($iexists?"found":"not found")."\n" 
        if $verbose;
    if( imageexists("/etc/systemimager/rsyncd.conf", $$vars{imgname}) 
        || $iexists ) {
        unless( yn_window( $window, "\"$$vars{imgname}\" exists.\n".
                                    "Do you want to replace it?" ) ) {
            $window->Unbusy();
            return undef;
        }

        # Manually delete the image directory such that SystemInstaller can
        # re-create it in the same path.
        # This way, the SystemImager rsync files etc. are intact
        system("rm -rf $$vars{imgpath}/$$vars{imgname}");
        $$vars{extraflags} .= " --force ";
        $window->update();
    }

    if ($$vars{pass1} ne $$vars{pass2}) {
        error_window($window, "The root passwords specified do not match");
        $window->Unbusy();
        return undef;
    }

#    progress_bar( $window, "Building Image..." );
    my $result = add_image_build( $vars, $window );
#    progress_destroy();
    if( $result ) {
        done_window($window, "Successfully created image \"$$vars{imgname}\"");
        if( $$vars{imgname} =~ /(.*?)(\d+)$/ ) {
            $$vars{imgname} = $1.($2 + 1);
        } else {
            $$vars{imgname} .= 1;
        }
    } else {
        if( progress_continue() ) {
            error_window($window, "Failed building image \"$$vars{imgname}\"");
        } else {
            error_window($window, "User cancelled building image \"$$vars{imgname}\"");
        }
        #
        # This should work, but it's not trustworthy.
        #
        system("mksiimage -D --name $$vars{imgname}");
        #
        # Belt and suspenders for above.
        #
        SystemImager::Server->remove_image_stub($rsync_stub_dir,
                                                $$vars{imgname});
        SystemImager::Server->gen_rsyncd_conf($rsync_stub_dir, $rsyncd_conf);
    }

    $window->Unbusy();

    return ($result);
}

# Actually create the image.
sub add_image_build ($$) {
    my $vars = shift;
    my $window = shift;
    my $verbose = &get_verbose();

    my $groupfile;
    if ($$vars{selected_group}) {
        my $path;
        for my $a (@{$$vars{package_group}}) {
            if ($a->{label} eq $$vars{selected_group}) {
                $path = $a->{path};
                last;
            }
        }
        $groupfile = "--filename $path";
    }

    # GV: i am sure we can find a better way to do that, we currently go back
    # and forth between OSCAR base Perl modules and SystemInstaller. We should
    # cleanup the image creation, the interaction with the GUI and the post
    # image creation scripts.
    if (OSCAR::ImageMgt::create_image ($$vars{imgname}, %$vars)) {
        carp "ERROR: Impossible to create the image";
        return 0;
    }

# TODO - GV: the progress bar is broken since we may use online repositories and
# automatically deal with dependencies. So we just deactive it.
#     my $value = 0;
#     $SIG{PIPE} = 'IGNORE';
#     my $pid = open( OUTPUT, "$cmd |" );
#     unless( $pid ) {
#         carp("Couldn't run command $cmd");
#         return 0;
#     }
#     &progress_update( $value );
#     while(my $line = <OUTPUT>) {
#         unless( &progress_continue() ) {
#         kill( "TERM", $pid );
#         last;
#     }
#     print "$line" if (exists $ENV{OSCAR_VERBOSE});
#     my $ovalue = $value;
#     if ($line =~ /\[progress: (\d+)\]/) {
#         # progress is scaled to 90%
#         $value = $1 * 0.9;
#     }
#     &progress_update($value);
#     }
#     close(OUTPUT);
#     return 0 unless progress_continue();
# 
#     progress_update(90);

    print "Image build finished.\n";

    # Now set the root password if given
#     return 0 unless progress_continue();
#     if ($$vars{pass1}) {
#         update_user(
#             imagepath => $$vars{imgpath}."/".$$vars{imgname},
#             user => 'root',
#             password => $$vars{pass1}
#             );
#     }
#     return 0 unless progress_continue();
#     progress_update(92);

    my $cmd = "mksidisk -A --name $$vars{imgname} --file $$vars{diskfile}";
    if( system($cmd) ) {
        carp("Couldn't run command $cmd");
        return 0;
    }
#     return 0 unless progress_continue();
#     progress_update(94);

    print "Added Disk Table for $$vars{imgname} based on $$vars{diskfile}\n";

    # Default command options
    $cmd = $main::config->mkaiscript . " -quiet --autodetect-disks -image $$vars{imgname} -force -ip-assignment $$vars{ipmeth} -post-install $$vars{piaction}";

    $cmd = $cmd . " -iseries-vdisk=$$vars{vdiskdev}" if ( $$vars{vdiskdev} =~ (/\/dev\/[a-zA-Z]*/) );

    print "Running: $cmd ... ";
    if( system($cmd) ) {
        carp("ERROR: Impossible to execute $cmd");
        return 0;
    }
#     return 0 unless progress_continue();
#     progress_update(96);

    print "done\n";

    # This allows for an arbitrary callback to be registered.
    # It will get a reference to all the variables that have been defined for
    # the image

    if(ref($$vars{postinstall}) eq "CODE") {
        unless( &{$$vars{postinstall}}($vars) ) {
            carp("Couldn't run postinstall"), 
            return 0;
        }
    }
    if(ref($$vars{postinstall}) eq "ARRAY") {
        my $sub = shift(@{$$vars{postinstall}});
        unless( &$sub($vars, @{$$vars{postinstall}}) ) {
            carp("Couldn't run postinstall");
            return 0;
        }
    }

    $image_params = $vars;
    return 1;
}

sub delfromrsyncd {
    my ($rsyncconf, $imagename) = @_;
	
    return 1 unless imageexists($rsyncconf, $imagename);

    open(IN,"<$rsyncconf") or return undef;
    my @lines = <IN>;
    close IN;

    return undef unless open(OUT,">$rsyncconf");
    my $state = 1;
    foreach (@lines) {
	if(/^\[$imagename\]/) {
	    $state = 0;
	} elsif (/^\[/) {
	    $state = 1;
	}
	print OUT $_ if $state;
    }
    close(OUT);
    return 1;
}

sub add2rsyncd {
    my ($rsyncconf, $imagename, $imagedir) = @_;
	
    unless(imageexists($rsyncconf, $imagename)) {
	open(OUT,">>$rsyncconf") or return undef;
	print OUT "[$imagename]\n\tpath=$imagedir/$imagename\n\n";
	close OUT;
    }
    return 1;
}

sub make_pkglist {
    my ($os) = @_;
    my @opkgs = list_selected_packages("all");
    my $outfile = "/tmp/oscar-install-rpmlist.$$";
    my @errors;
    local *OUTFILE;
    open(OUTFILE, ">$outfile") or croak("Could not open $outfile");
    foreach my $opkg_ref (@opkgs) {
	my $opkg = $$opkg_ref{package};
	my @pkgs = pkgs_of_opkg($opkg, undef, \@errors,
				group => "oscar_clients",
				os    => $os );
	foreach my $pkg (@pkgs) {
	    print OUTFILE "$pkg\n";
	}
    }
    close(OUTFILE);
}
1;
