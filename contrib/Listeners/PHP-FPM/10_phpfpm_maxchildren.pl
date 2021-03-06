# i-MSCP Listener::phpFPM::MaxChildren listener file
# Copyright (C) 2015 Ninos Ego <me@ninosego.de>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

#
## Listener file which changes the max-children value
#

package Listener::phpFPM::MaxChildren;

use strict;
use warnings;
use iMSCP::EventManager;

iMSCP::EventManager->getInstance()->register('beforeHttpdBuildConf', sub {
	my ($cfgTpl, $tplName, $data) = @_;

	if($tplName eq 'pool.conf') {
		my $search = "pm.max_children = 6\n";
		my $replace = "pm.max_children = 100\n";

		$$cfgTpl =~ s/$search/$replace/;
	}

	0;
});

1;
__END__
