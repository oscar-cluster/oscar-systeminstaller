#   $Id$

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

#   Copyright 2001 International Business Machines
#
#   Sean Dague <japh@us.ibm.com>

package SystemInstaller::Passwd;
use Carp;
use Data::Dumper;
use strict;
use base qw(Exporter);
use vars qw($VERSION @EXPORT @EXPORT_OK  %EXPORT_TAGS);

$VERSION = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);

@EXPORT_OK = qw(update_user);


%EXPORT_TAGS = (
                'all' => [@EXPORT_OK],
               );

sub update_user {
    my %vars = (
                imagepath => undef,
                user => undef,
                password => undef,
                @_,
               );

    foreach my $required (qw(imagepath user password)) {
        if (!$vars{$required}) {
            carp("Required variable $required not provided");
            return undef;
        }
    }

    my $cryptpw = _cryptpasswd($vars{password});

    if (system("chroot $vars{imagepath} usermod -p $cryptpw $vars{user}")) {
        carp("Failed to set password for user $vars{user}");
        return undef;
    }
    return  
}

sub _cryptpasswd {
    my $passwd = shift;
    my $salt = shift;

    # The next line is straight from pg 695 of Camel 3
    $salt ||= join '', ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64];

    crypt $passwd, $salt;
}

=head1 NAME

SystemInstaller::Passwd - a library to modify passwd files from Perl

=head1 SYNOPSIS

  use SystemInstaller::Passwd qw(update_user);
  update_user(
              imagepath => '/var/lib/systemimager/image/image1',
              user => 'root',
              password => 'yourmoma'
             );

=head1 DESCRIPTION

This library uses the usermod command to set the password for 
a user within an image. They password given is encrypted using 
crypt and then passed to usermod.

=head1 METHODS

=over 4

=item B<update_user(%variables)>

=back

=head1 AUTHORS

  Sean Dague <japh@us.ibm.com>, Michael Chase-Salerno <mchasal@users.sf.net>

=head1 SEE ALSO

crypt(3), usermod(8), perl(1)

=head1 COPYRIGHT

Copyright 2001 International Business Machines

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
 
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=head1 CHANGELOG

$Log: Passwd.pm,v $
Revision 1.8  2002/06/12 15:34:35  mchasal
Use usermod for password setting.

Revision 1.7  2001/10/09 15:36:57  sdague
added better error messages if password files can't be opened

Revision 1.6  2001/09/04 17:04:22  sdague
updated shadow passwd fields

Revision 1.5  2001/08/31 17:51:08  sdague
added some more stub documentation

Revision 1.4  2001/08/31 17:46:43  sdague
added version and changelog to SystemInstaller::Passwd


=cut

1;
