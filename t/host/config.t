use strict;
use warnings;
use parent 'SaharaSync::Config::Test';

use Test::Deep::NoTest qw(cmp_details deep_diag);
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
                { port => 0 },
                { port => 65535 },
                { disable_streaming => 1 },
                { disable_streaming => 0 },
                { disable_streaming => undef },
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

sub bad_params {
    return [
        server  => { foo => 1 },
        server  => { port => -1 },
        server  => { port => 65536 },
        server  => { disable_streaming => 2 },
        server  => { disable_streaming => -1 },
        server  => { disable_streaming => 'foo' },
        log     => {},
        log     => [{}],
        log     => 1,
        storage => {},
        storage => 1,
    ];
}

sub compare_log {
    my ( $self, undef, $got, $expected ) = @_;

    unless(ref($expected) eq 'ARRAY') {
        $expected = [ $expected ];
    }

    my ( $ok, $stack ) = cmp_details($got, $expected);
    unless($ok) {
        $stack = deep_diag($stack);
    }
    return ( $ok, $stack );
}

sub test_yaml_bools :Test(2) :File {
    my ( $self ) = @_;

    my $class = $self->config_class;
    my $temp  = File::Temp->new(SUFFIX => '.yaml');
    print $temp <<YAML;
---

log:
 -
   type: Null
storage:
  type: DBIWithFS
  root: /tmp/sahara
  dsn: 'dbi:SQLite:dbname=:memory:'
server:
  disable_streaming: true
YAML
    close $temp;

    lives_ok {
        $class->new_from_file($temp->filename);
    } "The YAML value 'true' should work fine";

    $temp  = File::Temp->new(SUFFIX => '.yaml');
    print $temp <<YAML;
---

log:
 -
   type: Null
storage:
  type: DBIWithFS
  root: /tmp/sahara
  dsn: 'dbi:SQLite:dbname=:memory:'
server:
  disable_streaming: false
YAML
    close $temp;

    lives_ok {
        $class->new_from_file($temp->filename);
    } "The YAML value 'false' should work fine";
}

__PACKAGE__->runtests;
