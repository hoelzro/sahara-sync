use strict;
use warnings;
use parent 'SaharaSync::Config::Test';

use File::HomeDir;
use File::Glob qw(bsd_glob GLOB_TILDE GLOB_NOCHECK);
use File::Spec;

require JSON;
require YAML;

use Test::More;
use Test::Deep::NoTest qw(cmp_details deep_diag);

my $default_home_dir;

if(my $dir = $ENV{'XDG_CONFIG_HOME'}) {
    $default_home_dir = File::Spec->catdir($dir, 'sahara-sync');
} else {
    $default_home_dir = File::Spec->catdir(File::HomeDir->my_data, 'Sahara Sync');
}

my $user = getpwuid $<;

sub required_params {
    return {
        upstream => [
            'http://localhost:5982',
            'https://localhost:5982',
            {
                host   => 'localhost',
                scheme => 'http',
                port   => 5982,
            },
            {
                host   => 'localhost',
            },
            {
                host   => 'localhost',
                scheme => 'https',
            },
            {
                host   => 'localhost',
                port   => 5983,
            },
            {
                host   => 'localhost',
                port   => 0,
            },
            {
                host   => 'localhost',
                port   => 65535,
            },
        ],
        username => 'test',
        password => 'abc123',
    };
}

sub optional_params {
    return {
        sync_dir => {
            values  => [
                '/tmp/sahara-data',
                '~/sahara',
                "~$user/sahara",
            ],
            default => '~/Sandbox',
        },

        log => {
            values  => [
                { type => 'Null' },
                [{ type => 'Null' }],
            ],
            default => sub {
                my ( $self ) = @_;

                return [{
                    type        => 'File',
                    filename    => File::Spec->catfile($self->home_dir, 'sahara.log'),
                    mode        => 'append',
                    binmode     => ':encode(utf8)',
                    permissions => 0600,
                    newline     => 1,
                }];
            },
        },

        poll_interval => {
            values  => [
                1,
                10,
                6.5
            ],
            default => 15,
        },
    };
}

sub config_class {
    return 'SaharaSync::Clientd::Config';
}

sub file_formats {
    return {
        json => 'JSON::encode_json',
        yaml => 'YAML::Dump',
    };
}

sub bad_params {
    return [
        upstream      => 'hey!',
        upstream      => 1,
        upstream      => {},
        upstream      => { port => 5982, scheme => 'http' },
        upstream      => { host => 'localhost', scheme => 'xmpp' },
        upstream      => { host => 'localhost', port => -1 },
        upstream      => { host => 'localhost', port => 65536 },
        upstream      => { host => 'localhost', foo => 1 },
        log           => [{}],
        log           => {},
        poll_interval => 0,
        poll_interval => -1,
    ];
}

sub compare_upstream {
    my ( $self, undef, $got, $expected ) = @_;

    if(ref($expected) eq 'HASH') {
        $expected = { %$expected };
        $expected->{'scheme'} = 'http' unless exists $expected->{'scheme'};
        $expected->{'port'}   = 5982 unless exists $expected->{'port'};

        $expected = URI->new(sprintf('%s://%s:%d', @{$expected}{qw/scheme host port/}));
    } else {
        $expected = URI->new($expected);
    }

    if("$got" eq "$expected") {
        return 1;
    } else {
        return 0, "\n  got:      $got\n  expected: $expected";
    }
}

sub expand_and_compare {
    my ( $self, $config, $got, $expected ) = @_;

    if(ref($expected) eq 'CODE') {
        $expected = $config->$expected();
    }
    $expected = bsd_glob($expected, GLOB_TILDE | GLOB_NOCHECK);

    if($got eq $expected) {
        return 1;
    } else {
        return 0, "\n  got:     $got\n  expected: $expected";
    }
}

do {
    no warnings 'once';

    *compare_sync_dir    = \&expand_and_compare;
};

sub compare_log {
    my ( $self, $config, $got, $expected ) = @_;

    if(ref($expected) eq 'CODE') {
        $expected = $config->$expected();
    }

    unless(ref($expected) eq 'ARRAY') {
        $expected = [ $expected ];
    }

    my ( $ok, $stack ) = cmp_details($got, $expected);

    if($ok) {
        return 1;
    } else {
        return 0, deep_diag($stack);
    }
}

sub test_home_dir :Test {
    my ( $self ) = @_;

    my $params = $self->required_params;
    foreach my $value (values %$params) {
        if(ref($value) eq 'ARRAY') {
            $value = $value->[0];
        }
    }

    my $config = $self->config_class->new($params);

    is($config->home_dir, $default_home_dir);
}

__PACKAGE__->runtests;
