use strict;
use warnings;
use parent 'SaharaSync::Config::Test';

use Test::Exception;
use Test::More;

require JSON;
require YAML;

sub required_params {
    return {
        log     => [
            [{ type => 'Null' }],
            { type => 'Null' },
        ],
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
            values  => [
                {},
                { port => 5983 },
                { disable_streaming => 1 },
                { port => 5983, disable_streaming => 1 },
            ],
            default => {},
        },
    };
}

sub config_class {
    return 'SaharaSync::Hostd::Config';
}

sub file_formats {
    return {
        json => 'JSON::encode_json',
        yaml => 'YAML::Dump',
    }
}

__PACKAGE__->runtests;
