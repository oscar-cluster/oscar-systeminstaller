package SystemInstaller::Env;

#   $Id$

#   Copyright (c) 2001 International Business Machines
 
#   Copyright (c) 2007 Erich Focht <efocht@hpce.nec.com>
#                      All rights reserved.
 
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
 
#   Michael Chase-Salerno <salernom@us.ibm.com>
use strict;
use base qw(Exporter);
use vars qw($VERSION @EXPORT $config);

@EXPORT = qw(print_version get_version);

use AppConfig;

$VERSION = sprintf("%d", q$Revision$ =~ /(\d+)/);

# Globally needed variables
$config = AppConfig->new(
        cfgfile =>      { ARGCOUNT => 1, 
                DEFAULT => '/etc/systeminstaller/systeminstaller.conf'},
        binpath =>      { ARGCOUNT => 1, 
                DEFAULT => '/usr/local/sbin:/usr/bin:/usr/sbin'},
        pkgcachefile => { ARGCOUNT => 1, DEFAULT => '.pkgcache'},
        simachine =>    { ARGCOUNT => 1, DEFAULT => 'mksimachine'},
        sirange =>      { ARGCOUNT => 1, DEFAULT => 'mksirange'},
        siimage =>      { ARGCOUNT => 1, DEFAULT => 'mksiimage'},
        sidisk =>       { ARGCOUNT => 1, DEFAULT => 'mksidisk'},
        mkaiscript =>   { ARGCOUNT => 1, DEFAULT => 'si_mkautoinstallscript'},
        addclients =>   { ARGCOUNT => 1, DEFAULT => 'si_addclients'},
        delimage =>     { ARGCOUNT => 1, DEFAULT => 'si_rmimage'},
        cpimage =>      { ARGCOUNT => 1, DEFAULT => 'si_cpimage'},
        distinfo =>     { ARGCOUNT => 1, 
                DEFAULT => '/usr/share/systeminstaller/distinfo'},
        pkgpath =>      { ARGCOUNT => 1, DEFAULT => '/tftpboot/rpms'},
        ipmeth =>       { ARGCOUNT => 1, DEFAULT => 'dynamic_dhcp'},
        piaction =>     { ARGCOUNT => 1, DEFAULT => 'beep'},
        disktype =>     { ARGCOUNT => 1, DEFAULT => 'scsi'},
        rpmrc =>        { ARGCOUNT => 1, DEFAULT => '/usr/lib/rpm/rpmrc'},
        rpm =>          { ARGCOUNT => 1, DEFAULT => 'rpm'},
        rpmargs =>      { ARGCOUNT => 1, DEFAULT => "-vh"},
        dpkg =>         { ARGCOUNT => 1, DEFAULT => 'dpkg'},
        verbose =>      { ARGCOUNT => 0, ALIAS => "v"},
        pkginstfail =>  { ARGCOUNT => 0},
        postinstfail => { ARGCOUNT => 0},
        diskversion =>  {ARGCOUNT => 1, DEFAULT => "2"},
        # The next are variables that we expect from the SystemImager
        # systemimager.conf file.
        'default_image_dir'         => { ARGCOUNT => 1 },
        'default_override_dir'      => { ARGCOUNT => 1 },
        'autoinstall_script_dir'    => { ARGCOUNT => 1 },
        'autoinstall_boot_dir'      => { ARGCOUNT => 1 },
        'autoinstall_tarball_dir'   => { ARGCOUNT => 1 },
        'autoinstall_torrent_dir'   => { ARGCOUNT => 1 },
        'rsyncd_conf'               => { ARGCOUNT => 1 },
        'rsync_stub_dir'            => { ARGCOUNT => 1 },
        'tftp_dir'                  => { ARGCOUNT => 1 },
        'net_boot_default'          => { ARGCOUNT => 1 },

);
if (-e $config->cfgfile ) {
        $config->file($config->cfgfile);
}
if (-e '/etc/systemimager/systemimager.conf') {
    $config->file('/etc/systemimager/systemimager.conf');
}

# Push it up to main
$::main::config = $config;

sub print_version {
        my $CMD=shift;
        $CMD =~ s/^.*\///;
        my $CMDVERSION=shift;
        my $PKGVERSION=&get_version;
        print <<EOL;
$CMD version $CMDVERSION
Part of SystemInstaller version $PKGVERSION

Copyright (C) 2001 Internation Business Machines
Copyright (C) 2007 Erich Focht @ NEC HPC Europe
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

EOL
            return 1;
}

sub get_version {
        # This just returns the version number, looks silly,
        # but the string below is replaced during the build
        # process with the proper version.
        my $SIVERSION="2.4.2svn20090612";
        return $SIVERSION;
}


### POD from here down

=head1 NAME
 
SystemInstaller::Env - Environment info
 
=head1 SYNOPSIS   

 use SystemInstaller::Env;

 print_version("mksidisk","1.2.2");

=head1 DESCRIPTION

SystemInstaller::Env defines on object containing environment info for SystemInstaller.

It exports an Appconfig structure, $config into the "main" name space.

Also provided is the print_version subroutine that will print the version blurb for
the current version of SystemInstaller. It takes the command name and its file version
as input and always returns 1.

=head1 AUTHOR
 
Michael Chase-Salerno <mchasal@users.sourceforge.net>

=head1 SEE ALSO

L<AppConfig>, L<perl>, L<systeminstaller.conf>

 
=cut

1;
