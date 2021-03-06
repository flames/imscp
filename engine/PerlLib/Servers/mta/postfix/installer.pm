=head1 NAME

 Servers::mta::postfix::installer - i-MSCP Postfix MTA server installer implementation

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2015 by internet Multi Server Control Panel
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

package Servers::mta::postfix::installer;

use strict;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use iMSCP::Crypt 'randomStr';
use iMSCP::Debug;
use iMSCP::Config;
use iMSCP::Execute;
use iMSCP::Dir;
use iMSCP::File;
use iMSCP::TemplateParser;
use iMSCP::Rights;
use iMSCP::SystemUser;
use iMSCP::SystemGroup;
use File::Basename;
use Servers::mta::postfix;
use version;
use parent 'Common::SingletonClass';

%main::sqlUsers = () unless %main::sqlUsers;
@main::createdSqlUsers = () unless @main::createdSqlUsers;

=head1 DESCRIPTION

 i-MSCP Postfix MTA server installer implementation.

=head1 PUBLIC METHODS

=over 4

=item registerSetupListeners(\%eventManager)

 Register setup event listeners

 Param iMSCP::EventManager \%eventManager
 Return int 0 on success, other on failure

=cut

sub registerSetupListeners
{
	my ($self, $eventManager) = @_;

	$eventManager->register('beforeSetupDialog', sub { push @{$_[0]}, sub { $self->showDialog(@_) }; 0; });
}

=item showDialog(\%dialog)

 Show dialog

 Param iMSCP::Dialog \%dialog
 Return int 0 on success, other on failure

=cut

sub showDialog
{
	my ($self, $dialog) = @_;

	my $dbUser = main::setupGetQuestion('SASL_SQL_USER') || $self->{'config'}->{'DATABASE_USER'} || 'sasl_user';
	my $dbPass = main::setupGetQuestion('SASL_SQL_PASSWORD') || $self->{'config'}->{'DATABASE_PASSWORD'} || '';

	my ($rs, $msg) = (0, '');

	if(
		$main::reconfigure ~~ [ 'mta', 'servers', 'all', 'forced' ] ||
		(length $dbUser < 6 || length $dbUser > 16 || $dbUser !~ /^[\x21-\x22\x24-\x5b\x5d-\x7e]+$/) ||
		(length $dbPass < 6 || $dbPass !~ /^[\x21-\x22\x24-\x5b\x5d-\x7e]+$/)
	) {
		# Ask for the SASL restricted SQL username
		do{
			($rs, $dbUser) = $dialog->inputbox(
				"\nPlease enter an username for the SASL SQL user:$msg", $dbUser
			);

			if($dbUser eq $main::imscpConfig{'DATABASE_USER'}) {
				$msg = "\n\n\\Z1You cannot reuse the i-MSCP SQL user '$dbUser'.\\Zn\n\nPlease try again:";
				$dbUser = '';
			} elsif(length $dbUser > 16) {
				$msg = "\n\n\\Username can be up to 16 characters long.\\Zn\n\nPlease try again:";
				$dbUser = '';
			} elsif(length $dbUser < 6) {
				$msg = "\n\n\\Z1Username must be at least 6 characters long.\\Zn\n\nPlease try again:";
				$dbUser = '';
			} elsif($dbUser !~ /^[\x21-\x22\x24-\x5b\x5d-\x7e]+$/) {
				$msg = "\n\n\\Z1Only printable ASCII characters (excepted space and number sign and backslash) are allowed.\\Zn\n\nPlease try again:";
				$dbUser = '';
			}
		} while ($rs != 30 && ! $dbUser);

		if($rs != 30) {
			$msg = '';

			# Ask for the SASL SQL user password unless we reuses existent SQL user
			unless($dbUser ~~ [ keys %main::sqlUsers ]) {
				do {
					# Ask for the SASL restricted SQL user password
					($rs, $dbPass) = $dialog->passwordbox(
						"\nPlease, enter a password for the SASL SQL user (blank for autogenerate):$msg", $dbPass
					);

					if($dbPass ne '') {
						if(length $dbPass < 6) {
							$msg = "\n\n\\Z1Password must be at least 6 characters long.\\Zn\n\nPlease try again:";
							$dbPass = '';
						} elsif($dbPass !~ /^[\x21-\x22\x24-\x5b\x5d-\x7e]+$/) {
							$msg = "\n\n\\Z1Only printable ASCII characters (excepted space and number sign and backslash) are allowed.\\Zn\n\nPlease try again:";
							$dbPass = '';
						} else {
							$msg = '';
						}
					} else {
						$msg = '';
					}
				} while($rs != 30 && $msg);
			} else {
				$dbPass = $main::sqlUsers{$dbUser};
			}

			if($rs != 30) {
				$dbPass = randomStr(16) unless $dbPass;
				$dialog->msgbox("\nPassword for the SASL SQL user set to: $dbPass");
			}
		}
	}

	if($rs != 30) {
		main::setupSetQuestion('SASL_SQL_USER', $dbUser);
		main::setupSetQuestion('SASL_SQL_PASSWORD', $dbPass);
		$main::sqlUsers{$dbUser} = $dbPass;
	}

	$rs;
}

=item preinstall()

 Process preinstall tasks

 Return int 0 on success, other on failure

=cut

sub preinstall
{
	my $self = shift;

	my $rs = $self->_addUsersAndGroups();
	return $rs if $rs;

	$rs = $self->_makeDirs();
	return $rs if $rs;

	$self->_createLookupTables();
}

=item install()

 Process install tasks

 Return int 0 on success, other on failure

=cut

sub install
{
	my $self = shift;

	my $rs = $self->_setupSqlUser();
	return $rs if $rs;

	$rs = $self->_buildConf();
	return $rs if $rs;

	$rs = $self->_buildAliasesDb();
	return $rs if $rs;

	$rs = $self->_oldEngineCompatibility();
	return $rs if $rs;

	$self->_saveConf();
}

=item setEnginePermissions()

 Set engine permissions

 Return int 0 on success, other on failure

=cut

sub setEnginePermissions
{
	my $self = shift;

	my $rootUName = $main::imscpConfig{'ROOT_USER'};
	my $rootGName = $main::imscpConfig{'ROOT_GROUP'};
	my $imscpGName = $main::imscpConfig{'IMSCP_GROUP'};
	my $mtaUName = $self->{'config'}->{'MTA_MAILBOX_UID_NAME'};
	my $mtaGName = $self->{'config'}->{'MTA_MAILBOX_GID_NAME'};
	my $postfixGrp = $self->{'config'}->{'POSTFIX_GROUP'};

	# Postfix main.cf configuration file
	setRights($self->{'config'}->{'POSTFIX_CONF_FILE'}, { user => $rootUName, group => $rootGName, mode => '0644' });

	# Postfix master.cf configuration file
	setRights($self->{'config'}->{'POSTFIX_MASTER_CONF_FILE'}, {
		user => $rootUName, group => $rootGName, mode => '0644'
	});

	# Postfix map configuration directory
	setRights($self->{'config'}->{'MTA_VIRTUAL_CONF_DIR'}, {
		user => $rootUName, group => $postfixGrp, dirmode => '0750', filemode => '0640', recursive => 1
	});

	# Postfix SASL configuration directory
	setRights($self->{'config'}->{'SASL_CONF_DIR'}, {
		user => $rootUName, group => $postfixGrp, dirmode => '0750', filemode => '0640', recursive => 1
	});

	# saslauthd configuration file
	setRights($self->{'config'}->{'SASLAUTHD_CONF_FILE'}, { user => $rootUName, group => $rootGName, mode => '0644' });

	# PAM smtp configuration file
	setRights($self->{'config'}->{'PAM_SMTP_CONF_FILE'}, { user => $rootUName, group => $rootGName, mode => '0640' });

	# i-MSCP messenger
	setRights("$main::imscpConfig{'ENGINE_ROOT_DIR'}/messenger", {
		user => $rootUName, group => $imscpGName, dirmode => '0750', filemode => '0750', recursive => 1
	});

	# i-MSCP responder
	setRights("$main::imscpConfig{'LOG_DIR'}/imscp-arpl-msgr", {
		user => $mtaUName, group => $imscpGName, dirmode => '0750', filemode => '0600', recursive => 1
	});

	# i-MSCP virtual mail directory
	setRights($self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'}, {
		user => $mtaUName, group => $mtaGName, dirmode => '0750', filemode => '0640', recursive => 1
	});

	# /usr/sbin/maillogconvert.pl
	setRights('/usr/sbin/maillogconvert.pl', { user => $rootUName, group => $rootGName, mode => '0750' });
}

=back

=head1 PRIVATE METHODS

=over 4

=item _init()

 Initialize instance

 Return Servers::mta::postfix::installer

=cut

sub _init
{
	my $self = shift;

	$self->{'mta'} = Servers::mta::postfix->getInstance();
	$self->{'eventManager'} = $self->{'mta'}->{'eventManager'};
	$self->{'cfgDir'} = $self->{'mta'}->{'cfgDir'};
	$self->{'bkpDir'} = $self->{'mta'}->{'bkpDir'};
	$self->{'config'} = $self->{'mta'}->{'config'};

	# Merge old config file with new config file
	my $oldConf = "$self->{'cfgDir'}/postfix.old.data";
	if(-f $oldConf) {
		tie my %oldConfig, 'iMSCP::Config', fileName => $oldConf;
		for my $param(keys %oldConfig) {
			if(exists $self->{'config'}->{$param}) {
				$self->{'config'}->{$param} = $oldConfig{$param};
			}
		}
	}

	$self;
}

=item _addUsersAndGroups()

 Add users and groups

 Return int 0 on success, other on failure

=cut

sub _addUsersAndGroups
{
	my $self = shift;

	my @groups = (
		[
			$self->{'config'}->{'MTA_MAILBOX_GID_NAME'}, # Group name
			'yes' # Whether it's a system group
		],
		[
			$self->{'config'}->{'SASL_GROUP'}, # Group name
			'yes' # Whether it's a system group
		]
	);

	my @users = (
		[
			$self->{'config'}->{'MTA_MAILBOX_UID_NAME'}, # User name
			$self->{'config'}->{'MTA_MAILBOX_GID_NAME'}, # User primary group name
			'vmail_user', # Comment
			$self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'}, # User homedir
			'yes', # Whether it's a system user
			[ $main::imscpConfig{'IMSCP_GROUP'} ] # Additional user group(s)
		]
	);

	my %userToGroups = (
		$self->{'config'}->{'POSTFIX_USER'} => [ $self->{'config'}->{'SASL_GROUP'} ]
	);

	$self->{'eventManager'}->trigger('beforeMtaAddUsersAndGroups', \@groups, \@users, \%userToGroups);

	# Create groups
	my $systemGroup = iMSCP::SystemGroup->getInstance();

	for my $group(@groups) {
		my $rs = $systemGroup->addSystemGroup($group->[0], ($group->[1] eq 'yes') ? 1 : 0);
		return $rs if $rs;
	}

	# Create users
	for my $user(@users) {
		my $systemUser = iMSCP::SystemUser->new();
		$systemUser->{'group'} = $user->[1];
		$systemUser->{'comment'} = $user->[2];
		$systemUser->{'home'} = $user->[3];
		$systemUser->{'system'} = 'yes' if $user->[4] eq 'yes';

		my $rs = $systemUser->addSystemUser($user->[0]);
		return $rs if $rs;

		if(defined $user->[5]) {
			for my $group(@{$user->[5]}) {
				$rs = $systemUser->addToGroup($group) ;
				return $rs if $rs;
			}
		}
	}

	# User to groups
	while(my ($user, $groups) = each(%userToGroups)) {
		my $systemUser = iMSCP::SystemUser->new( username => $user );

		for my $group(@{$groups}) {
			my $rs = $systemUser->addToGroup($group);
			return $rs if $rs;
		}
	}

	$self->{'eventManager'}->trigger('afterMtaAddUsersAndGroups');
}

=item _makeDirs()

 Create directories

 Return int 0 on success, other on failure

=cut

sub _makeDirs
{
	my $self = shift;

	my @directories = (
		[
			$self->{'config'}->{'MTA_VIRTUAL_CONF_DIR'}, # Postfix map configuration directory
			$main::imscpConfig{'ROOT_USER'},
			$self->{'CONFIG'}->{'POSTFIX_GROUP'},
			0750
		],
		[
			$self->{'config'}->{'SASL_CONF_DIR'}, # Postfix SASL configuration directory
			$main::imscpConfig{'ROOT_USER'},
			$self->{'CONFIG'}->{'POSTFIX_GROUP'},
			0750
		],
		[
			$self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'}, # Virtual mail user directory
			$self->{'config'}->{'MTA_MAILBOX_UID_NAME'},
			$self->{'config'}->{'MTA_MAILBOX_GID_NAME'},
			0750
		],
		[
			$main::imscpConfig{'LOG_DIR'} . '/imscp-arpl-msgr', # i-MSCP messenger log directory
			$self->{'config'}->{'MTA_MAILBOX_UID_NAME'},
			$main::imscpConfig{'IMSCP_GROUP'},
			0750
		]
	);

	$self->{'eventManager'}->trigger('beforeMtaMakeDirs', \@directories);

	for my $dir(@directories) {
		iMSCP::Dir->new( dirname => $dir->[0] )->make({ user => $dir->[1], group => $dir->[2], mode => $dir->[3] });
	}

	$self->{'eventManager'}->trigger('afterMtaMakeDirs');
}

=item _createLookupTables()

 Create lookupTables

 Return int 0 on success, die on failure

=cut

sub _createLookupTables
{
	my $self = shift;

	my @lookupTables = ('aliases', 'domains', 'mailboxes', 'relay_domains', 'transport');

	$self->{'eventManager'}->trigger('beforeMtaCreatedLookupTables', \@lookupTables);

	for my $table(@lookupTables) {
		my $file = iMSCP::File->new( filename => "$self->{'config'}->{'MTA_VIRTUAL_CONF_DIR'}/$table" );
		$file->set(<<TPL);
# Postfix configuration file - auto-generated by i-MSCP
#     DO NOT EDIT THIS FILE BY HAND -- YOUR CHANGES WILL BE OVERWRITTEN
TPL
		$file->save();
		$self->{'mta'}->{'postmap'}->{"$self->{'config'}->{'MTA_VIRTUAL_CONF_DIR'}/$table"} = 'cdb';
	}

	$self->{'eventManager'}->trigger('afterMtaCreatedLookupTables', \@lookupTables);
}

=item _setupSqlUser()

 Setup SASL SQL user

 Return int 0 on success, other on failure

=cut

sub _setupSqlUser
{
	my $self = shift;

	my $dbName = main::setupGetQuestion('DATABASE_NAME');
	my $dbUser = main::setupGetQuestion('SASL_SQL_USER');
	my $dbUserHost = main::setupGetQuestion('DATABASE_USER_HOST');
	my $dbPass = main::setupGetQuestion('SASL_SQL_PASSWORD');
	my $dbOldUser = $self->{'config'}->{'DATABASE_USER'};

	$self->{'eventManager'}->trigger('beforeMtaSetupDb', $dbUser, $dbOldUser, $dbPass, $dbUserHost);

	for my $sqlUser ($dbOldUser, $dbUser) {
		next if ! $sqlUser || "$sqlUser\@$dbUserHost" ~~ @main::createdSqlUsers;

		for my $host(
			$dbUserHost, $main::imscpOldConfig{'DATABASE_USER_HOST'}, $main::imscpOldConfig{'DATABASE_HOST'},
			$main::imscpOldConfig{'BASE_SERVER_IP'}
		) {
			next unless $host;

			if(main::setupDeleteSqlUser($sqlUser, $host)) {
				error(sprintf('Could not remove %s@%s SQL user or one of its privileges', $sqlUser, $host));
				return 1;
			}
		}
	}

	my ($db, $errStr) = main::setupGetSqlConnect();
	fatal(sprintf('Could not connect to SQL server: %s', $errStr)) unless $db;

	# Create SQL user if not already created by another server/package installer
	unless("$dbUser\@$dbUserHost" ~~ @main::createdSqlUsers) {
		debug(sprintf('Creating %s@%s SQL user with password: %s', $dbUser, $dbUserHost, $dbPass));

		my $rs = $db->doQuery('c', 'CREATE USER ?@? IDENTIFIED BY ?', $dbUser, $dbUserHost, $dbPass);
		unless(ref $rs eq 'HASH') {
			error(sprintf('Could not create %s@%s SQL user: %s', $dbUser, $dbUserHost, $rs));
			return 1;
		}

		push @main::createdSqlUsers, "$dbUser\@$dbUserHost";
	}

	my $quotedDbName = $db->quoteIdentifier($dbName);

	my $rs = $db->doQuery('g', "GRANT SELECT ON $quotedDbName.mail_users TO ?@?", $dbUser, $dbUserHost);
	unless(ref $rs eq 'HASH') {
		error(sprintf('Could not add SQL privileges: %s', $rs));
		return 1;
	}

	$self->{'config'}->{'DATABASE_USER'} = $dbUser;
	$self->{'config'}->{'DATABASE_PASSWORD'} = $dbPass;
	$self->{'eventManager'}->trigger('afterMtaSetupDb');
}

=item _buildConf()

 Build configuration file

 Return int 0 on success, other on failure

=cut

sub _buildConf
{
	my $self = shift;

	$self->{'eventManager'}->trigger('beforeMtaBuildConf');

	my $rs = $self->_buildMainCfFile();
	return $rs if $rs;

	$rs = $self->_buildMasterCfFile();
	return $rs if $rs;

	$rs = $self->_buildSaslConfFiles();
	return $rs if $rs;

	$self->{'eventManager'}->trigger('afterMtaBuildConf');
}

=item _buildAliasesDb()

 Build aliases database

 Return int 0 on success, other on failure

=cut

sub _buildAliasesDb
{
	my $self = shift;

	$self->{'eventManager'}->trigger('beforeMtaBuildAliases');
	my $rs = execute("newaliases -oAcdb:$self->{'config'}->{'MTA_LOCAL_ALIAS_MAP'}", \my $stdout, \my $stderr);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;
	error("Error while executing newaliases command") if $rs && !$stderr;
	return $rs if $rs;
	$self->{'eventManager'}->trigger('afterMtaBuildAliases');
}

=item _saveConf()

 Save configuration file

 Return int 0 on success, other on failure

=cut

sub _saveConf
{
	my $self = shift;

	iMSCP::File->new( filename => "$self->{'cfgDir'}/postfix.data" )->copyFile("$self->{'cfgDir'}/postfix.old.data");
}

=item _bkpConfFile($cfgFile)

 Backup the given configuration file

 Param string $cfgFile Configuration file path
 Return int 0 on success, die on failure

=cut

sub _bkpConfFile
{
	my ($self, $cfgFile) = @_;

	$self->{'eventManager'}->trigger('beforeMtaBkpConfFile', $cfgFile);

	if(-f $cfgFile) {
		my $basename = basename($cfgFile);

		iMSCP::File->new( filename => $cfgFile )->copyFile(
			! -f "$self->{'bkpDir'}/$basename.system"
				? "$self->{'bkpDir'}/$basename.system" : "$self->{'bkpDir'}/$basename." . time()
		);
	}

	$self->{'eventManager'}->trigger('afterMtaBkpConfFile', $cfgFile);
}

=item _buildMainCfFile()

 Build main.cf file

 Return int 0 on success, other or die on failure

=cut

sub _buildMainCfFile
{
	my $self = shift;

	$self->_bkpConfFile($self->{'config'}->{'POSTFIX_CONF_FILE'});

	my $baseServerIpType = iMSCP::Net->getInstance->getAddrVersion($main::imscpConfig{'BASE_SERVER_IP'});
	my $gid = getgrnam($self->{'config'}->{'MTA_MAILBOX_GID_NAME'});
	my $uid = getpwnam($self->{'config'}->{'MTA_MAILBOX_UID_NAME'});
	my $hostname = $main::imscpConfig{'SERVER_HOSTNAME'};

	my $data = {
		MTA_INET_PROTOCOLS => $baseServerIpType,
		MTA_SMTP_BIND_ADDRESS => ($baseServerIpType eq 'ipv4') ? $main::imscpConfig{'BASE_SERVER_IP'} : '',
		MTA_SMTP_BIND_ADDRESS6 => ($baseServerIpType eq 'ipv6') ? $main::imscpConfig{'BASE_SERVER_IP'} : '',
		MTA_HOSTNAME => $hostname,
		MTA_LOCAL_DOMAIN => "$hostname.local",
		MTA_VERSION => $main::imscpConfig{'Version'},
		MTA_TRANSPORT_MAP => $self->{'config'}->{'MTA_TRANSPORT_MAP'},
		MTA_LOCAL_MAIL_DIR => $self->{'config'}->{'MTA_LOCAL_MAIL_DIR'},
		MTA_LOCAL_ALIAS_MAP => $self->{'config'}->{'MTA_LOCAL_ALIAS_MAP'},
		MTA_VIRTUAL_MAIL_DIR => $self->{'config'}->{'MTA_VIRTUAL_MAIL_DIR'},
		MTA_VIRTUAL_DMN_MAP => $self->{'config'}->{'MTA_VIRTUAL_DMN_MAP'},
		MTA_VIRTUAL_MAILBOX_MAP => $self->{'config'}->{'MTA_VIRTUAL_MAILBOX_MAP'},
		MTA_VIRTUAL_ALIAS_MAP => $self->{'config'}->{'MTA_VIRTUAL_ALIAS_MAP'},
		MTA_RELAY_MAP => $self->{'config'}->{'MTA_RELAY_MAP'},
		MTA_MAILBOX_MIN_UID => $uid,
		MTA_MAILBOX_UID => $uid,
		MTA_MAILBOX_GID => $gid,
		CONF_DIR => $main::imscpConfig{'CONF_DIR'},
		SSL => ($main::imscpConfig{'SERVICES_SSL_ENABLED'} eq 'yes') ? '' : '#',
		CERTIFICATE => 'imscp_services'
	};

	$self->{'eventManager'}->trigger('onLoadTemplate', 'postfix', 'main.cf', \my $cfgTpl, $data);
	$cfgTpl = iMSCP::File->new( filename => "$self->{'cfgDir'}/main.cf" )->get() unless defined $cfgTpl;

	$self->{'eventManager'}->trigger('beforeMtaBuildMainCfFile', \$cfgTpl, 'main.cf');
	$cfgTpl = process($data, $cfgTpl);

	# Fix for #790
	my $rs = execute("postconf -h mail_version", \my $stdout, \my $stderr);
	debug($stdout) if $stdout;
	warning($stderr) if $stderr && !$rs;
	error($stderr) if $stderr && $rs;
	return 1 if $rs;

	unless(defined $stdout) {
		error('Unable to find Postfix version');
		return 1;
	}

	chomp($stdout);
	if(version->parse($stdout) >= version->parse('2.10.0')) {
		$cfgTpl =~ s/smtpd_recipient_restrictions/smtpd_relay_restrictions =\n\nsmtpd_recipient_restrictions/;
	}

	$self->{'eventManager'}->trigger('afterMtaBuildMainCfFile', \$cfgTpl, 'main.cf');

	my $file = iMSCP::File->new( filename => $self->{'config'}->{'POSTFIX_CONF_FILE'} );
	$file->set($cfgTpl);
	$file->save();
}

=item _buildMasterCfFile()

 Build master.cf file

 Return int 0 on success, die on failure

=cut

sub _buildMasterCfFile
{
	my $self = shift;

	$self->_bkpConfFile($self->{'config'}->{'POSTFIX_MASTER_CONF_FILE'});

	my $data = {
		MTA_MAILBOX_UID_NAME => $self->{'config'}->{'MTA_MAILBOX_UID_NAME'},
		IMSCP_GROUP => $main::imscpConfig{'IMSCP_GROUP'},
		ARPL_PATH => $main::imscpConfig{'ROOT_DIR'}."/engine/messenger/imscp-arpl-msgr"
	};

	$self->{'eventManager'}->trigger('onLoadTemplate', 'postfix', 'master.cf', \my $cfgTpl, $data);
	$cfgTpl = iMSCP::File->new( filename => "$self->{'cfgDir'}/master.cf" )->get() unless defined $cfgTpl;

	$self->{'eventManager'}->trigger('beforeMtaBuildMasterCfFile', \$cfgTpl, 'master.cf');
	$cfgTpl = process($data, $cfgTpl);
	$self->{'eventManager'}->trigger('afterMtaBuildMasterCfFile', \$cfgTpl, 'master.cf');

	my $file = iMSCP::File->new( filename => $self->{'config'}->{'POSTFIX_MASTER_CONF_FILE'} );
	$file->set($cfgTpl);
	$file->save();
}

=item _buildSaslConfFiles()

 Build SASL configuration files

 Return int 0 on success, die on failure

=cut

sub _buildSaslConfFiles
{
	my $self = shift;

	# saslauthd configuration file

	$self->_bkpConfFile($self->{'config'}->{'SASLAUTHD_CONF_FILE'});

	my $data = {
		SASLAUTHD_THREADS => $self->{'config'}->{'SASLAUTHD_THREADS'}
	};

	$self->{'eventManager'}->trigger('onLoadTemplate', 'sasl', 'saslauthd', \my $cfgTpl, $data);
	$cfgTpl = iMSCP::File->new( filename => "$self->{'cfgDir'}/sasl/saslauthd")->get() unless defined $cfgTpl;

	$self->{'eventManager'}->trigger('beforeMtaBuildSaslConffile', \$cfgTpl, 'saslauthd');
	$cfgTpl = process($data, $cfgTpl);
	$self->{'eventManager'}->trigger('afterMtaBuildSaslConffile', \$cfgTpl, 'saslauthd');

	my $file = iMSCP::File->new( filename => $self->{'config'}->{'SASLAUTHD_CONF_FILE'} );
	$file->set($cfgTpl);
	$file->save();
	undef $cfgTpl;

	# Postfix Cyrus SASL configuration file

	$self->_bkpConfFile($self->{'config'}->{'SASL_SMTPD_CONF_FILE'});

	$data = {
		SASL_SMTPD_LOG_LEVEL => $self->{'config'}->{'SASL_SMTPD_LOG_LEVEL'}
	};

	$self->{'eventManager'}->trigger('onLoadTemplate', 'sasl', 'smtpd.conf', \$cfgTpl, $data);
	$cfgTpl = iMSCP::File->new( filename => "$self->{'cfgDir'}/sasl/smtpd.conf" )->get() unless defined $cfgTpl;

	$self->{'eventManager'}->trigger('beforeMtaBuildSaslConffile', \$cfgTpl, 'smtpd.conf');
	$cfgTpl = process($data, $cfgTpl);
	$self->{'eventManager'}->trigger('afterMtaBuildSaslConffile', \$cfgTpl, 'smtpd.conf');

	$file = iMSCP::File->new( filename => $self->{'config'}->{'SASL_SMTPD_CONF_FILE'} );
	$file->set($cfgTpl);
	$file->save();
	$file->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	$file->mode(0640);
	undef $cfgTpl;

	# PAM smtp configuration file

	$self->_bkpConfFile($self->{'config'}->{'PAM_SMTP_CONF_FILE'});

	$data = {
		DATABASE_HOST =>  $main::imscpConfig{'DATABASE_HOST'},
		DATABASE_PORT => $main::imscpConfig{'DATABASE_PORT'},
		DATABASE_NAME => $main::imscpConfig{'DATABASE_NAME'},
		DATABASE_USER => $self->{'config'}->{'DATABASE_USER'},
		DATABASE_PASS => $self->{'config'}->{'DATABASE_PASSWORD'}
	};

	$self->{'eventManager'}->trigger('onLoadTemplate', 'pam', 'smtp', \$cfgTpl, $data);
	$cfgTpl = iMSCP::File->new( filename => "$self->{'cfgDir'}/sasl/pam/smtp" )->get() unless defined $cfgTpl;

	$self->{'eventManager'}->trigger('beforeMtaBuildPamConffile', \$cfgTpl, 'smtp');
	$cfgTpl = process($data, $cfgTpl);
	$self->{'eventManager'}->trigger('afterMtaBuildPamConffile', \$cfgTpl, 'smtp');

	$file = iMSCP::File->new( filename => $self->{'config'}->{'PAM_SMTP_CONF_FILE'} );
	$file->set($cfgTpl);
	$file->save();
	$file->owner($main::imscpConfig{'ROOT_USER'}, $main::imscpConfig{'ROOT_GROUP'});
	$file->mode(0640);
}

=item _oldEngineCompatibility()

 Remove old files

 Return int 0 on success, other on failure

=cut

sub _oldEngineCompatibility
{
	my $self = shift;

	$self->{'eventManager'}->trigger('beforeMtaOldEngineCompatibility');

	for my $file(
		'/etc/sasldb2', '/var/spool/postfix/etc/sasldb2', "$self->{'config'}->{'MTA_VIRTUAL_CONF_DIR'}/sender-access",
		"$self->{'config'}->{'MTA_LOCAL_ALIAS_MAP'}.db", "$main::imscpConfig{'CONF_DIR'}/postfix/smtpd.conf"
	) {
		iMSCP::File->new( filename => $file )->delFile() if -f $file;
	}

	for my $file(
		iMSCP::Dir->new( dirname => $self->{'config'}->{'MTA_VIRTUAL_CONF_DIR'}, fileType => '\\.db' )->getFiles()
	) {
		if($file =~ /^(?:aliases|domains|mailboxes|relay_domains|sender-access|transport)\.db$/) {
			iMSCP::File->new( filename => "$self->{'config'}->{'MTA_VIRTUAL_CONF_DIR'}/$file" )->delFile();
		}
	}

	for my $dir('working', 'imscp', 'parts') {
		iMSCP::Dir->new( dirname => "$self->{'cfgDir'}/$dir" )->remove();
	}

	$self->{'eventManager'}->trigger('afterMtadOldEngineCompatibility');
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
