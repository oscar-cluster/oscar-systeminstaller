package SystemInstaller::Tk::Main;

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

use strict;
use vars qw($VERSION @EXPORT);
use Tk;
use Carp;
#use SystemInstaller::Utils;
use SystemInstaller::Tk::Image qw(createimage_window add2rsyncd delfromrsyncd);
use SystemInstaller::Tk::GetImage qw(creategetimage_window);
use SystemInstaller::Tk::AddClients qw(addclients_window);
use SystemInstaller::Tk::UpdateClient qw(updateclient_window);
use SystemInstaller::Tk::SISTree; # My fun SIS Tree Widget
use SystemInstaller::Env qw(get_version $config);
use SIS::Image;
use SIS::Client;
use SIS::Adapter;
use SIS::NewDB;
use Data::Dumper;
use base qw(Exporter);
use POSIX;

@EXPORT = qw(img_window);

sub img_window {
    my $imgdir = shift;
    my $vars = shift;
#    my $config = SystemInstaller::Utils::init_si_config();
    my $tree;
    
    my $window = new MainWindow();
    $window->geometry("650x400");
    
    my ($imagepic, $clientpic);
    eval {$imagepic = $window->Pixmap('imageicon', file => "$imgdir/image.xpm");};
    eval {$clientpic = $window->Pixmap('clienticon', file => "$imgdir/monitor.xpm");};

    # Here comes the menu stuff.  I really do need to factor this into a sub

    $tree = $window->ScrlSISTree(
                                 -indent => 30,
                                 -background => "white",
                                 -itemtype   => 'imagetext',
                                 -separator  => '|',
                                 -selectmode => 'extended',
                                 -imageicon => $imagepic,
                                 -clienticon => $clientpic,
                                 -lsimagecmd => [\&list_image],
                                 -lsadapcmd => [\&adapters_for_client],
                                 -lsclientcmd => [\&clients_for_image]);

    my $menubar = generate_menubar($window,$tree);
    $window->Menu(-type => "menubar");
    $window->configure(-menu => $menubar);
    
    $tree->pack(-expand => "yes", -fill => "both");
    
    my $newbutton = $window->Button(-text => "New Image",
                                    -command => [\&createimage_window, $window, 
                                                 postinstall => sub {$tree->render},
                                                ],
                                   );
    my $getbutton = $window->Button(-text => "Fetch Image",
                                    -command => [\&creategetimage_window, $window, 
                                                 postinstall => sub {$tree->render},
                                                ],
                                   );
    my $addclientbutton = $window->Button(
                                          -text => "Add Clients",
                                          -command => [\&addclients2image, $window, $tree],
                                         );
    my $updateclientbutton = $window->Button(
                                          -text => "Update Clients",
                                          -command => [\&updateclient, $window, $tree],
                                         );
    my $windowbutton = $window->Button(
                                       -text => "Open Terminal",
                                       -command => [\&openxterm, $window, $tree, $config],
                                      );
    my $deletebutton = $window->Button(
                                       -text => "Delete",
                                       -command => [\&delete_items, $tree],
                                      );
    my $exitbutton = $window->Button(
                                     -text => "Quit",
                                     -command => sub {$window->destroy},
                                    );
    $tree->configure(-browsecmd  => [\&configure_buttons, 
                                     $tree, 
                                     [$newbutton,$exitbutton,$getbutton],
                                     [$addclientbutton, $windowbutton, $deletebutton],
                                     [$updateclientbutton, $deletebutton]
                                    ],
                    );

    # And now all the fun bindings

    $window->bind("<Control-n>", sub {$newbutton->invoke;});
    $window->bind("<Control-a>", sub {$addclientbutton->invoke;});
    $window->bind("<Control-u>", sub {$addclientbutton->invoke;});
    $window->bind("<Control-d>", sub {$deletebutton->invoke;});
    $window->bind("<Control-q>", sub {$exitbutton->invoke;});
    $window->bind("<Control-o>", sub {$windowbutton->invoke;});
    
    #  This next could be used for a right click popup menu.  Not sure if I want it yet
    #  or not
    #    $tree->bind("<ButtonPress-3>",sub {print $tree->nearest($tree->pointery - $tree->rooty),"\n"});
    
    $newbutton->pack($getbutton,$addclientbutton,$updateclientbutton, $windowbutton, $deletebutton, $exitbutton,-side=>"left");

    $tree->render();
    $tree->images_and_clients();
}


sub generate_menubar {
    my ($window, $tree) = @_;
    my $menubar = $window->Menu();
    my $image = $menubar->cascade(-label => 'Image', -tearoff => 0);
    $image->command(-label => 'Collapse to Images', -command => sub {$tree->render;});
    $image->command(-label => 'Collapse to Images and Clients', -command => sub {$tree->render;$tree->images_and_clients});
    $image->command(-label => 'Expand All', -command => sub {$tree->render;$tree->expand;});

    $image->separator();

    $image->command(-label => 'Quit', -command => sub {$window->destroy});
    
    my $help = $menubar->cascade(-label => 'Help', -tearoff => 0);
    $help->command(-label => 'About TkSIS...',  -command => [\&about_window, $window]);
    return $menubar;
}

#  Holy crap is this ugly.  What I really need here is some sort of
#  matrix of states, but I can't quite figure out how to do that in
#  a way that is any less ugly than this at the moment.  And this
#  works.

sub configure_buttons {
    my $tree = shift;
    my $basebuttons = shift;
    my $imagebuttons = shift;
    my $clientbuttons = shift;

    # Set to starting state
    map {$_->configure(-state => "normal")} @$basebuttons;
    map {$_->configure(-state => "disable")} @$imagebuttons;
    map {$_->configure(-state => "disable")} @$clientbuttons;


    my @types = $tree->list_selected_types();
    if (@types == 1) {
            if ($types[0] eq "IMG") {
                map {$_->configure(-state => "normal")} @$imagebuttons;
            }
            if ($types[0] eq "CLI") {
                map {$_->configure(-state => "normal")} @$clientbuttons;
            }
    }
     
    
}

# this is a really stupid existance function.  Clearly have lisp flashbacks.

sub in_arrayp {
    my ($i, @array) = @_;
    foreach my $j (@array) {
        return 1 if $i eq $j;
    }
    return undef;
}

sub openxterm {
    my ($window, $tree, $config) = @_;
    my @selected = $tree->infoSelection;
    if(scalar(@selected) >= 1) {
        my $image = $selected[0];
        my $imgname = $tree->entrycget($image,"-text");
        my $cmd = $config->xterm_cmd . " -T 'Chroot Window: $imgname' -e chroot " . 
          $config->default_image_dir . "/$imgname";
        !system("$cmd &") or carp "Couldn't run '$cmd'";
    }
}

sub addclients2image {
    my ($window, $tree) = @_;
    my @selected = $tree->infoSelection;
    if(scalar(@selected) >= 1) {
        my $image = $selected[0];
        my $imgname = $tree->entrycget($image,"-text");
        my $HOST = (uname)[1];
        my ($junk,$DOM)  = split(/\./,$HOST,2);
        my $vars = {
                    postinstall => sub {
                        $tree->render;
                    },
                    imgname => $imgname,
                    domainname => $DOM,
                   };
        addclients_window($window, %$vars);
    }
}

sub updateclient {
    my ($window, $tree) = @_;
    my @selected = $tree->infoSelection;
    my @clients;
    foreach my $client (@selected) {
            my $clientname = $tree->entrycget($client,"-text");
            push @clients,$clientname;
    }
    my $vars = {
            clients => \@clients,
            postinstall => sub {
                $tree->render;
                },
    };
    updateclient_window($window, %$vars);

}

sub clients_for_image {
    my ($image, $config) = @_;
    my @clients = list_client(imagename => $image);
    return @clients;
}

sub adapters_for_client {
    my ($client, $config) = @_;
    my @adapters = list_adapter(client => $client);
    return @adapters;
}

sub delete_items {
    my $tree = shift;
    $tree->toplevel->Busy();
    my @selections = $tree->infoSelection;
    foreach my $selection (@selections) {
        if($tree->entrycget($selection, "-data") eq "IMG") {
            my $imgname = $tree->entrycget($selection, "-text");
            delete_image($imgname) or ($tree->render, 
                                       carp("Couldn't delete image $imgname"),
                                       $tree->toplevel->Unbusy(),
                                       return undef);
            $tree->render;
        } elsif ($tree->entrycget($selection, "-data") eq "CLI") {
            my $machname = $tree->entrycget($selection, "-text");
            delete_machine($machname) or ($tree->render, 
                                          carp("Couldn't delete client $machname"),
                                          $tree->toplevel->Unbusy(),
                                          return undef);
            $tree->render;
        }
    }
    $tree->toplevel->Unbusy();
}

sub delete_machine {
    my $name = shift;
    !system("mksimachine -D --name $name") or (carp("Couldn't run mksimachine -D --name $name") and return undef);
    return 1;
}

sub delete_image {
    my $imagename = shift;
    !system("mksiimage -D --name $imagename") or (carp("Couldn't run mksiimage -D --name $imagename") and return undef);
    delfromrsyncd('/etc/systemimager/rsyncd.conf', $imagename) or (carp("Couldn't delfromrsyncd $imagename") and return undef);
    return 1;
}

sub about_window {
    my $w = shift;
    my $w2 = $w->Toplevel();
    my $version=get_version;
    my $message = $w2->Message(-text => "TKSIS v$version\n\nWriten by Sean Dague <japh\@us.ibm.com> & Michael Chase-Salerno(mchasal\@users.sf.net)\n\nThis application is part of the System Installer package, and is designed to aid in the creation and manipulation of System Installation Suite images.\n\nFor more information see the System Installation Suite website at http://sisuite.org\n");
    $message->pack();
    my $butt = $w2->Button(-text => "Close", -command => sub {$w2->destroy});
    $butt->pack();
}

1;
