package SystemInstaller::Tk::SISTree;

use Tk ();
use Tk::Derived;
use Tk::Tree;
use Data::Dumper;
use base  qw(Tk::Derived Tk::Tree);
use strict;
use warnings;

Construct Tk::Widget 'SISTree';

sub Tk::Widget::ScrlSISTree { shift->Scrolled('SISTree' => @_) }

sub Populate {
    my( $w, $args ) = @_;
    
    $w->SUPER::Populate( $args );
    
    $w->ConfigSpecs(
                    -imageicon => ['PASSIVE', 'imageicon', 'Imageicon', ''],
                    -clienticon => ['PASSIVE', 'clienticon', 'Clienticon', ''],
                    -lsimagecmd => ['CALLBACK', 'lsimageCmd','LsimageCmd','dummy'],
                    -lsclientcmd => ['CALLBACK', 'lsclientCmd','LsclientCmd','dummy'],
                    -lsadapcmd => ['CALLBACK', 'lsadapCmd','LsadapCmd','dummy'],
                    -stupid    => ['PASSIVE', 'stupid', 'Stupid', 2],
                   );
}

sub LsimageCmd {
    my $w = shift;
    $w->Callback(-lsimagecmd => @_);
}

sub LsclientCmd {
    my $w = shift;
    $w->Callback(-lsclientcmd => @_);
}

sub LsadapCmd {
    my $w = shift;
    $w->Callback(-lsadapcmd => @_);
}

sub dummy {
    return ();
}

sub images_and_clients {
    my $self = shift;
    my @images = $self->info("children","|");
    foreach my $image (@images) {
                $self->setmode($image,"open");
                $self->open($image);
    }
}    

sub expand {
    my $self = shift;
    my $depth= shift;
    $depth="|" unless $depth;
    my @kids = $self->info("children",$depth);
    foreach my $kid (@kids) {
        if(my @grandkids = $self->info("children",$kid)) {
                $self->setmode($kid,"open");
                $self->open($kid);
                $self->expand($kid);
        }
    }
}    

sub togglemode {
    my $tree = shift;
    print "I have entered togglemode\n";
    foreach my $entry ($tree->infoSelection) {
        print $tree->getmode($entry),"\n";
        if($tree->getmode($entry) eq "close") {
            $tree->Activate($entry,"open");
         } elsif($tree->getmode($entry) eq "open") {
            $tree->Activate($entry,"close");
        }
    }
}

sub render {
    my $self = shift;
    $self->delete("all");
    
    $self->add("|",-text => "All Images on Server",-itemtype => "text", -data => 'ROOT');
    $self->setmode("|","close");
    foreach my $image ($self->LsimageCmd()) {
        my $imgstring = $image->{name};
        $self->add_sistree_entry("", '-imageicon', $imgstring, 'IMG');
        # Deal with Images nicely
        $self->add_sistree_entry("|$imgstring",'','Properties','PROPTOP');
        foreach my $key (keys %$image) {
            if ( $$image{$key} ) {
                $self->add_sistree_entry("|$imgstring|Properties",'',"$key = $$image{$key}",'PROP');
            } else {
                $self->add_sistree_entry("|$imgstring|Properties",'',"$key = ",'PROP');
            }
        }
        $self->setmode("|$imgstring|Properties","close");
        $self->close("|$imgstring|Properties");
        foreach my $client ($self->LsclientCmd($imgstring)) {
            my $clientstring = $client->{name};
            $self->add_sistree_entry("|$imgstring", '-clienticon', $clientstring, 'CLI');
                $self->add_sistree_entry("|$imgstring|$clientstring",'','Properties','PROPTOP');
                foreach my $key (keys %$client) {
                        if ($$client{$key}) {
                                $self->add_sistree_entry("|$imgstring|$clientstring|Properties",'',"$key = $$client{$key}",'PROP');
                        } else {
                                $self->add_sistree_entry("|$imgstring|$clientstring|Properties",'',"$key = ",'PROP');
                        }
                }
                $self->setmode("|$imgstring|$clientstring|Properties","close");
                $self->close("|$imgstring|$clientstring|Properties");
                $self->add_sistree_entry("|$imgstring|$clientstring",'','Adapters','ADAPTOP');
                foreach my $adapter ($self->LsadapCmd($clientstring)) {
                    my $adapterstring = $adapter->{name};
                    $self->add_sistree_entry("|$imgstring|$clientstring|Adapters",'',$adapterstring,'ADAP');
                    foreach my $key (keys %$adapter) {
                        if ($$adapter{$key}) {
                            $self->add_sistree_entry("|$imgstring|$clientstring|Adapters|$adapterstring",'',"$key = $$adapter{$key}",'ADAPPROP');
                        } else {    
                            $self->add_sistree_entry("|$imgstring|$clientstring|Adapters|$adapterstring",'',"$key =",'ADAPPROP');
                        }
                    }
                    $self->setmode("|$imgstring|$clientstring|Adapters|$adapterstring","close");
                    $self->close("|$imgstring|$clientstring|Adapters|$adapterstring");
                }
                $self->setmode("|$imgstring|$clientstring|Adapters","close");
                $self->close("|$imgstring|$clientstring|Adapters");
            $self->setmode("|$imgstring|$clientstring","close");
            $self->close("|$imgstring|$clientstring");

        }
        $self->setmode("|$imgstring","close");
        $self->close("|$imgstring");
    }
    $self->Callback("-browsecmd");
    $self->update;
    return 1;
}

sub list_selected_types {
    my ($self) = @_;
    my @selects = $self->infoSelection;
    my @types = ();
    my %keys = ();
    foreach my $item (@selects) {
        my $type = $self->entrycget($item,"-data");
        if(!$keys{$type}) {
            $keys{$type}++;
            push @types, $type;
        }
    }
    return @types;
}

sub add_sistree_entry {
    my ($self, $parent, $icon, $name, $data) = @_;
    my $image=();
    if ($icon) {
        $image = $self->cget($icon);
    }
    if($image) {
        $self->add("$parent|$name", -image => $image, 
                   -text => $name, -itemtype => "imagetext", -data => $data);
    } else {
        $self->add("$parent|$name", -text => $name, 
                   -itemtype => "text", -data => $data);
    }
}

1;
