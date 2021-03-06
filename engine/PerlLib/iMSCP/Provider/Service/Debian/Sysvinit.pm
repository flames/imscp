=head1 NAME

 iMSCP::Provider::Service::Sysvinit - Service provider for Debian `sysvinit` scripts

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2015 by Laurent Declercq <l.declercq@nuxwin.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

package iMSCP::Provider::Service::Debian::Sysvinit;

use strict;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use iMSCP::Execute;
use iMSCP::File;
use Scalar::Defer;
use parent 'iMSCP::Provider::Service::Sysvinit';

# Commands used in that package
my %commands = (
	dpkg => '/usr/bin/dpkg',
	'invoke-rc.d' => '/usr/sbin/invoke-rc.d',
	'update-rc.d' => '/usr/sbin/update-rc.d'
);

# Compatibility mode for sysv-rc
my $SYSVRC_COMPAT_MODE;

=head1 DESCRIPTION

 Service provider for Debian `sysvinit` scripts.

 The only differences with the base sysvinit provider are support for enabling, disabling and removing services
 via `update-rc.d` and the ability to determine enabled status via `invoke-rc.d`.

=head1 PUBLIC METHODS

=over 4

=item isEnabled($service)

 Does the given service is enabled?

 Param string $service Service name
 Return bool TRUE if the given service is enabled, FALSE otherwise

=cut

sub isEnabled
{
	my ($self, $service) = @_;

	my $ret = $self->_exec($commands{'invoke-rc.d'}, '--quiet', '--query', $service, 'start');

	# 104 is the exit status when you query start an enabled service.
	# 106 is the exit status when the policy layer supplies a fallback action
	if($ret ~~ [ 104, 106 ]) {
		1;
	} elsif($ret ~~ [ 101, 105 ]) {
		# 101 is action not allowed, which means we have to do the check manually.
		# 105 is unknown, which generally means the iniscript does not support query
		# The debian policy states that the initscript should support methods of query
		# For those that do not, peform the checks manually
		# http://www.debian.org/doc/debian-policy/ch-opersys.html
		(my @count = glob("/etc/rc*.d/S??$service")) >= 4;
	} else {
		0;
	}
}

=item enable($service)

 Enable the given service

 Param string $service Service name
 Return bool TRUE on success, FALSE on failure

=cut

sub enable
{
	my ($self, $service) = @_;

	if($SYSVRC_COMPAT_MODE) {
		! $self->_exec($commands{'update-rc.d'}, '-f', $service, 'remove') &&
		! $self->_exec($commands{'update-rc.d'}, $service, 'defaults');
	} else {
		! $self->_exec($commands{'update-rc.d'}, $service, 'defaults') &&
		! $self->_exec($commands{'update-rc.d'}, $service, 'enable');
	}
}

=item disable($service)

 Disable the given service

 Param string $service Service name
 Return bool TRUE on success, FALSE on failure

=cut

sub disable
{
	my ($self, $service) = @_;

	if($SYSVRC_COMPAT_MODE) {
		! $self->_exec($commands{'update-rc.d'}, '-f', $service, 'remove') &&
		! $self->_exec($commands{'update-rc.d'}, $service, 'stop', '00', '1', '2', '3', '4', '5', '6', '.');
	} else {
		! $self->_exec($commands{'update-rc.d'}, $service, 'defaults') &&
		! $self->_exec($commands{'update-rc.d'}, $service, 'disable');
	}
}

=item remove($service)

 Remove the given service

 Param string $service Service name
 Return bool TRUE on success, FALSE on failure

=cut

sub remove
{
	my ($self, $service) = @_;

	if($self->_isSysvinit($service)) {
		! $self->_exec($commands{'update-rc.d'}, '-f', $service, 'remove') &&
		! iMSCP::File->new( filename => $self->getInitscriptPath($service) )->delFile();
	} else {
		1;
	}
}

=item hasService($service)

 Does the given service exists?

 Return bool TRUE if the given service exits, FALSE otherwise

=cut

sub hasService
{
	my ($self, $service) = @_;

	$self->_isSysvinit($service);
}

=back

=head1 PRIVATE METHODS

=over 4

=item _init()

 Initialize instance

 Return iMSCP::Provider::Service::Debian::Sysvinit

=cut

sub _init
{
	my $self = shift;

	# Sets compatibility mode according systemd version in use
	unless(defined $SYSVRC_COMPAT_MODE) {
		$SYSVRC_COMPAT_MODE = lazy {
			$self->_exec(
				$commands{'dpkg'}, '--compare-versions', '$(dpkg-query -W --showformat \'${Version}\' sysv-rc)',
				'ge',
				'2.88'
			);
		};
	}

	$self->SUPER::_init();
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
