use strict;
use warnings;

use Test::Exception;
use Test::More;

use File::Temp;
use JSON qw(encode_json);
use SaharaSync::Hostd::Config;

my @params = (
    {
        throws => qr/Attribute.*(log|storage).*is\s+required/,
        name   => 'Cannot build a config object with no parameters',
        params => {},
    },
    {
        name   => 'Building a config object with a storage parameter should succeed',
        params => {
            storage => {
                type => 'DBIWithFS',
                root => '/tmp/sahara',
                dsn  => 'dbi:SQLite:dbname=:memory:',
            },
            log     => [{
                type => 'Null',
            }],
        },
    },
    {
        throws => qr/Found unknown attribute/,
        name   => 'Cannot build a config object with an invalid parameter',
        params => {
            storage => {
                type => 'DBIWithFS',
                root => '/tmp/sahara',
                dsn  => 'dbi:SQLite:dbname=:memory:',
            },
            log     => [{
                type => 'Null',
            }],
            foo => {},
        },
    },
);

plan tests => @params * 2 + 2;

foreach my $param (@params) {
    my ( $throws, $name, $params ) = @{$param}{qw/throws name params/};

    if(defined $throws) {
        throws_ok {
            SaharaSync::Hostd::Config->new(%$params);
        } $throws, $name;
    } else {
        lives_ok {
            SaharaSync::Hostd::Config->new(%$params);
        } $name;
    }

    my $temp = File::Temp->new(SUFFIX => '.json');
    print $temp encode_json($params);
    close $temp;

    if(defined $throws) {
        throws_ok {
            SaharaSync::Hostd::Config->load_from_file($temp->filename);
        } $throws, $name;
    } else {
        lives_ok {
            SaharaSync::Hostd::Config->load_from_file($temp->filename);
        } $name;
    }
}

my $temp = File::Temp->new(SUFFIX => '.json');
print $temp encode_json {
    storage => {
        type => 'DBIWithFS',
        root => '/tmp/sahara',
        dsn  => 'dbi:SQLite:dbname=:memory:',
    },
    log     => [{
        type => 'Null',
    }],
};
close $temp;
unlink $temp->filename;
throws_ok {
    SaharaSync::Hostd::Config->load_from_file($temp->filename);
} qr/Unable to read/, "Loading a non-existent file should fail";

$temp = File::Temp->new(SUFFIX => '.json');
print $temp "random text!!!\n";
close $temp;
throws_ok {
    SaharaSync::Hostd::Config->load_from_file($temp->filename);
} qr/Error parsing/, "Loading a non-existent file should fail";
