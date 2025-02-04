# class: letsencrypt
class letsencrypt {
    include ::apt

    apt::pin { 'certbot_backports':
        priority   => 740,
        originator => 'Debian',
        release    => 'stretch-backports',
        packages   => 'certbot',
    }

    package { 'certbot':
        ensure  => installed,
        require => Apt::Pin['certbot_backports'],
    }

    file { '/etc/letsencrypt/cli.ini':
        ensure => present,
        owner  => 'root',
        group  => 'root',
        source => 'puppet:///modules/letsencrypt/cli.ini',
        mode   => '0644',
    }

    ['/var/www/.well-known', '/var/www/.well-known/acme-challenge'].each |$folder| {
        file { "${folder}":
            ensure => directory,
            owner  => 'root',
            group  => 'root',
            mode   => '0755',
        }
    }

    file { '/root/ssl':
        ensure => directory,
        owner  => 'root',
        group  => 'root',
        mode   => '0770',
    }

    file { '/root/ssl-certificate':
        ensure => present,
        owner  => 'root',
        group  => 'root',
        source => 'puppet:///modules/letsencrypt/ssl-certificate.py',
        mode   => '0775',
    }

    file { '/srv/ssl':
        ensure => directory,
        owner  => 'nagiosre',
        group  => 'nagiosre',
        mode   => '0770',
    }

    file { '/var/lib/nagios/ssl-acme':
        ensure => present,
        source => 'puppet:///modules/letsencrypt/ssl-acme',
        owner  => 'nagiosre',
        group  => 'nagiosre',
        mode   => '0775',
    }

    file { '/var/lib/nagios/id_rsa':
        ensure => present,
        source => 'puppet:///private/acme/id_rsa',
        owner  => 'nagiosre',
        group  => 'nagiosre',
        mode   => '0400',
    }

    sudo::user { 'nrpe_ssl-certificate':
        user       => 'nagiosre',
        privileges => [
            'ALL = NOPASSWD: /root/ssl-certificate',
        ],
    }

    include letsencrypt::web
}
