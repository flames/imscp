# Dovecot configuration file - auto-generated by i-MSCP
#     DO NOT EDIT THIS FILE BY HAND -- YOUR CHANGES WILL BE OVERWRITTEN
mail_location = maildir:~/

namespace private {
	separator = .
	prefix = INBOX.
	inbox = yes
}

plugin {
	quota = maildir:User quota
	quota_rule = *:storage=1GB
	quota_warning2 = storage=95%% {ENGINE_ROOT_DIR}/quota/imscp-dovecot-quota.sh 95
	quota_warning = storage=80%% {ENGINE_ROOT_DIR}/quota/imscp-dovecot-quota.sh 80
}

disable_plaintext_auth = no

auth default {
	mechanisms = plain login

	passdb sql {
		args = {DOVECOT_CONF_DIR}/dovecot-sql.conf
	}

	userdb prefetch {
	}

	userdb sql {
		args = {DOVECOT_CONF_DIR}/dovecot-sql.conf
	}

	socket listen {
		# Master authentication socket for LDA
		master {
			path = {DOVECOT_AUTH_SOCKET_PATH}
			mode = 0600
			user = {MTA_MAILBOX_UID_NAME}
		}
	}
}

protocols = imap imaps pop3 pop3s

protocol imap {
	mail_plugins = quota imap_quota
}

protocol pop3 {
	mail_plugins = quota
	pop3_uidl_format = %u-%v
}

protocol lda {
	auth_socket_path = {DOVECOT_AUTH_SOCKET_PATH}
	mail_plugins = quota
	postmaster_address = postmaster@{HOSTNAME}
}

ssl = {DOVECOT_SSL}
{COMMENT_SSL}ssl_cert_file = {CONF_DIR}/{CERTIFICATE}.pem
{COMMENT_SSL}ssl_key_file = {CONF_DIR}/{CERTIFICATE}.pem
