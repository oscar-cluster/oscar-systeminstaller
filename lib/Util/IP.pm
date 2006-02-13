package Util::IP;

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

#   Sean Dague <japh@us.ibm.com>

#   The following is a set of libraries for building Command Line Interfaces

use strict;
use base qw(Exporter);
use vars qw(@EXPORT @EXPORT_OK @ISA);
use Carp;
use Data::Dumper;

push @ISA, qw(Exporter);
@EXPORT = qw(next_ip ip_list);
@EXPORT_OK = qw(next_ip ip_list);

sub next_ip {
	my $ip=shift;
        my @oct=split(/\./,$ip);
	$oct[3]++;
	if ($oct[3] == 255) {
		$oct[3]=1;
		$oct[2]++;
		if ($oct[2] == 255) {
			$oct[2]=1;
			$oct[1]++;
		}
	}
	return join(".",@oct);
}
sub ip_list {
        my ($ip,$count)=@_;
	my $i=1;
	my @iplist;
	push (@iplist,$ip);
        while ($i < $count) {
		$ip=&next_ip($ip);
                push(@iplist,$ip);
		$i++
        }
        return @iplist;
}

1;
