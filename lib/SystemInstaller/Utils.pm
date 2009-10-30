package SystemInstaller::Utils;

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

# Copyright (c) 2009 Geoffroy Vallee <valleegr at ornl dot gov>
#                    Oak Ridge National Laboratory
#                    All rights reserved.

use strict;
use AppConfig;
use vars qw($VERSION @EXPORT);
use base qw(Exporter);
use Carp;

@EXPORT = qw(init_si_config get_si_config);

sub init_si_config {
    my $config = new AppConfig(
        DEFAULT_IMAGE_DIR => { ARGCOUNT => 1},
        DEFAULT_OVERRIDE_DIR => { ARGCOUNT => 1},
        AUTOINSTALL_SCRIPT_DIR => { ARGCOUNT => 1},
        AUTOINSTALL_BOOT_DIR => { ARGCOUNT => 1},
        RSYNCD_CONF => { ARGCOUNT => 1},
        RSYNC_STUB_DIR => { ARGCOUNT => 1},
        CONFIG_DIR => { ARGCOUNT => 1},
        TFTP_DIR => { ARGCOUNT => 1},
        NET_BOOT_DEFAULT => { ARGCOUNT => 1},
        AUTOINSTALL_TARBALL_DIR => { ARGCOUNT => 1},
        AUTOINSTALL_TORRENT_DIR => { ARGCOUNT => 1},
        # now for tksis configuration parameters
        ICON_DIR => { ARGCOUNT => 1, DEFAULT => "/usr/share/systeminstaller/images"},
        XTERM_CMD => { ARGCOUNT => 1,
            DEFAULT => "xterm -bg black -fg magenta",
        },
    );
    $config->file("/etc/systemimager/systemimager.conf", 
                  "/etc/systeminstaller/tksis.conf");
    return $config;
}

sub get_si_config () {
    require OSCAR::ConfigFile;

    my $si_conffile = "/etc/systemimager/systemimager.conf";
    my %config = OSCAR::ConfigFile::get_all_values ($si_conffile, undef);

    return (%config);
}

1;


