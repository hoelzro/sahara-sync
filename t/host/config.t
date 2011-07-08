use strict;
use warnings;
use parent 'SaharaSync::Config::Test';

use Test::Exception;
use Test::More;

sub required_params {
    return {
        log     => [{ type => 'Null' }],
        storage => {
            type => 'DBIWithFS',
            root => '/tmp/sahara',
            dsn  => 'dbi:SQLite:dbname=:memory:',
        },
    };
}

sub optional_params {
    return {
        server => {
            value   => {},
            default => {},
        },
    };
}

sub config_class {
    return 'SaharaSync::Hostd::Config';
}

__PACKAGE__->runtests;
