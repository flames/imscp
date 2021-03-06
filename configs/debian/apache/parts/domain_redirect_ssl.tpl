# Apache2 configuration file - auto-generated by i-MSCP
#     DO NOT EDIT THIS FILE BY HAND -- YOUR CHANGES WILL BE OVERWRITTEN
<VirtualHost {DOMAIN_IP}:443>
    ServerAdmin webmaster@{DOMAIN_NAME}
    ServerName {DOMAIN_NAME}
    ServerAlias www.{DOMAIN_NAME} {ALIAS}.{BASE_SERVER_VHOST}

    LogLevel error
    ErrorLog {HTTPD_LOG_DIR}/{DOMAIN_NAME}/error.log

    Redirect {FORWARD_TYPE} / {FORWARD}

    SSLEngine On
    SSLCertificateFile {CERTIFICATE}
    SSLCertificateChainFile {CERTIFICATE}

    # SECTION hsts_enabled BEGIN.
    Header always set Strict-Transport-Security "max-age={HSTS_MAX_AGE}{HSTS_INCLUDE_SUBDOMAINS}"
    # SECTION hsts_enabled END.
</VirtualHost>
