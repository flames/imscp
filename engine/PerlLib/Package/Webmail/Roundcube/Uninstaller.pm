=head1 NAME

Package::Webmail::Roundcube::Uninstaller - i-MSCP Roundcube package uninstaller

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

package Package::Webmail::Roundcube::Uninstaller;

use strict;
use warnings;
use iMSCP::Debug;
use iMSCP::Dir;
use iMSCP::File;
use iMSCP::Database;
use Package::FrontEnd;
use Package::Webmail::Roundcube::Roundcube;
use parent 'Common::SingletonClass';

=head1 DESCRIPTION

 i-MSCP Roundcube package uninstaller.

=head1 PUBLIC METHODS

=over 4

=item uninstall()

 Process uninstall tasks

 Return int 0 on success, other on failure

=cut

sub uninstall
{
	my $self = shift;

	my $rs = $self->_removeSqlUser();
	return $rs if $rs;

	$rs = $self->_removeSqlDatabase();
	return $rs if $rs;

	$rs = $self->_unregisterConfig();
	return $rs if $rs;

	$self->_removeFiles();
}

=back

=head1 PRIVATE METHODS

=over 4

=item _init()

 Initialize instance

 Return Package::Webmail::Roundcube::Uninstaller

=cut

sub _init
{
	my $self = shift;

	$self->{'frontend'} = Package::FrontEnd->getInstance();
	$self->{'roundcube'} = Package::Webmail::Roundcube::Roundcube->getInstance();
	$self->{'db'} = iMSCP::Database->factory();
	$self->{'cfgDir'} = "$main::imscpConfig{'CONF_DIR'}/roundcube";
	$self->{'bkpDir'} = "$self->{'cfgDir'}/backup";
	$self->{'wrkDir'} = "$self->{'cfgDir'}/working";
	$self->{'config'} = $self->{'roundcube'}->{'config'};
	$self;
}

=item _removeSqlUser()

 Remove SQL user

 Return int 0 on success, other on failure

=cut

sub _removeSqlUser
{
	my $self = shift;

	for($main::imscpConfig{'DATABASE_USER_HOST'}, $main::imscpConfig{'BASE_SERVER_IP'}, 'localhost', '127.0.0.1', '%') {
		next unless $_;
		$self->{'db'}->doQuery('dummy', "DROP USER ?@?", $self->{'config'}->{'DATABASE_USER'}, $_);
	}

	$self->{'db'}->doQuery('dummy', 'FLUSH PRIVILEGES');
	0;
}

=item _removeSqlDatabase()

 Remove database

 Return int 0

=cut

sub _removeSqlDatabase
{
	my $self = shift;

	my $dbName = $self->{'db'}->quoteIdentifier($main::imscpConfig{'DATABASE_NAME'} . '_roundcube');
	$self->{'db'}->doQuery('dummy', "DROP DATABASE IF EXISTS $dbName");
	0;
}

=item _unregisterConfig

 Remove include directive from frontEnd vhost files

 Return int 0 on success, other on failure

=cut

sub _unregisterConfig
{
	my $self = shift;

	for my $vhostFile('00_master.conf', '00_master_ssl.conf') {
		if(-f "$self->{'frontend'}->{'config'}->{'HTTPD_SITES_AVAILABLE_DIR'}/$vhostFile") {
			my $file = iMSCP::File->new(
				filename => "$self->{'frontend'}->{'config'}->{'HTTPD_SITES_AVAILABLE_DIR'}/$vhostFile"
			);

			my $fileContent = $file->get();
			$fileContent =~ s/[\t ]*include imscp_roundcube.conf;\n//;
			$file->set($fileContent);
			$file->save();
		}
	}

	$self->{'frontend'}->{'reload'} = 1;
	0;
}

=item _removeFiles()

 Remove files

 Return int 0

=cut

sub _removeFiles
{
	my $self = shift;

	iMSCP::Dir->new( dirname => "$main::imscpConfig{'GUI_PUBLIC_DIR'}/tools/webmail" )->remove();
	iMSCP::Dir->new( dirname => $self->{'cfgDir'} )->remove();

	if(-f "$self->{'frontend'}->{'config'}->{'HTTPD_CONF_DIR'}/imscp_roundcube.conf") {
		iMSCP::File->new(filename => "$self->{'frontend'}->{'config'}->{'HTTPD_CONF_DIR'}/imscp_roundcube.conf")->delFile();
	}

	0;
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
