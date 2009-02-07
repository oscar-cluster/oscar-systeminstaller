package SystemInstaller::Tk::Common;

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
use vars qw(@EXPORT %Labels);
use AppConfig;
use File::Basename;
use strict;

@EXPORT = qw(selector2entry
			 quit_button
			 label_entry_line 
			 label_option_line 
			 label_listbox_line 
			 resethash
			 imageexists
			 center_window
			 yn_window
			 done_window
			 error_window
			);

%Labels = ();

# Default font for Tk dialogs
my $FONT = "-*-helvetica-bold-r-normal-*-14-140-*-*-*-*-*-*";

#
#  selector2entry sets up the callback needed for a fileselector to be tied to 
#  an entry box
#  

sub selector2entry {
	my ($var, $title, $filter, $widget) = @_;

	# now we attempt to do some reasonable directory setting
	my $dir = $$var;
	$dir = dirname( $dir ) unless -d $dir;
	my $t = $widget->getOpenFile(
		-title => $title,
		-initialdir => $dir,
		-filetypes => $filter,
	);
	$$var = $t if $t && -e $t;
}

sub reset_window {
	my ($window, $curvars, $defvars, $optiondefaults) = @_;
	resethash($curvars, $defvars);
	foreach my $key (keys %$optiondefaults) {
		$$optiondefaults{$key}->setOption($$curvars{$key}) if($$optiondefaults{$key});
	}
}

sub close_after {
	my ($window, $onclose, @args) = @_;
	&$onclose(@args) if(ref($onclose) eq "CODE");
	$window->destroy;
}

# Just the standard Tk window centering code...
#
sub center_window {
	my $w = shift;
	my $p = $w->parent();

	$w->withdraw() if $w->viewable();

	$w->idletasks;
	my $x = int( ($w->screenwidth - $w->reqwidth)/2 );
	my $y = int( ($w->screenheight - $w->reqheight)/2 );
	if( $p ) {
		$x -= int( $p->vrootx/2 ) if $p->vrootx;
		$y -= int( $p->vrooty/2 ) if $p->vrooty;
	}
	$w->geometry( "+$x+$y" );

	$w->deiconify();

}

sub yn_window {
	my ($w, $message, $onclose, @args) = @_;

	my $dialog = $w->Dialog(
		-title => 'A Question',
		-bitmap => 'question',
		-font => $FONT,
		-text => $message,
		-default_button => 'No',
		-buttons => [ 'Yes', 'No' ],
	);
	my $ans = $dialog->Show();

	&$onclose( @args ) if ref( $onclose ) eq 'CODE';

	return $ans eq "Yes";
}

sub done_window {
	my ($w, $message, $onclose, @args) = @_;

	my $dialog = $w->Dialog(
		-title => 'Done!',
		-bitmap => 'info',
		-font => $FONT,
		-text => $message,
		-default_button => 'OK',
		-buttons => [ 'OK' ],
	);
	$dialog->Show();

	&$onclose( @args ) if ref( $onclose ) eq 'CODE';

	1;
}

sub error_window {
	my ($w, $message, $onclose, @args) = @_;

	my $dialog = $w->Dialog(
		-title => 'ERROR!',
		-bitmap => 'error',
		-font => $FONT,
		-text => $message,
		-default_button => 'OK',
		-buttons => [ 'OK' ],
		);
	$dialog->Subwidget( 'bitmap' )->configure( -foreground => 'red' );
	$dialog->Subwidget( 'message' )->configure( -foreground => 'red' );
	$dialog->Show();

	&$onclose( @args ) if ref( $onclose ) eq 'CODE';

	1;
}

#
#  resethash sets one hash to another hash.
#

sub resethash {
	my ($hash1, $hash2) = @_;
	foreach my $key (keys %$hash2) {
		$$hash1{$key} = $$hash2{$key};
	}
}

#
#  The following creates a set of widgets with do 'Label: [Entry]' 
#

sub label_entry_line {
	my ($window, $labeltext, $variable, $validate, @morewidgets) = @_;
	my @options;
	if($validate) {
		@options = (
			-validatecommand => $validate,
			-validate => "focusout",
		);
	}
	my $label = $window->Label(-text => "$labeltext: ", -anchor => "w");
	my $entry = $window->Entry(-textvariable => $variable, @options);
	$label->grid($entry,@morewidgets, -sticky => "nesw");
}

# This creates a small list box with 1 item ($selection) selected.
sub label_listbox_line {
	my ($window, $labeltext, $selection, $listitems , @morewidgets) = @_;
	my $label = $window->Label(-text => "$labeltext: ", -anchor => "w");
	my $listbox = $window->Scrolled("Listbox",-scrollbars => 'e', -height => 2, 
		-width => 17, -selectmode => "single", -exportselection=>0);
	$listbox->insert(0,$selection);
	$listbox->insert('end',@$listitems);
	$listbox->selectionSet(0);

	$label->grid($listbox,@morewidgets);
	return $listbox;
}

sub label_entry_file_line {
	
}

sub quit_button {
	my $window = shift;
	my $quit_button = $window->Button(
		-text=>"Close",
		-command=> [sub { shift->destroy }, $window],
		-pady => 8,
		-padx => 8,
	);
	return $quit_button;
}

sub label_option_line {
	my ($window, $labeltext, $variable, $options, @morewidgets) = @_;
	my $label = $window->Label(-text => "$labeltext: ", -anchor => "w");

	my $default = $$variable;
	my $optionmenu = $window->Optionmenu(-options => $options, -variable => $variable);
	$optionmenu->setOption($default) if $default;

	$label->grid($optionmenu, @morewidgets, -sticky => "nesw");
	return $optionmenu;
}

sub imageexists {
	my ($rsyncconf, $imagename) = @_;
	open(IN,"<$rsyncconf") or return undef;
	if(grep(/\[$imagename\]/, <IN>)) {
		close(IN);
		return 1;
	}
	close(IN);
	return undef;
}


1;
