use strict;
use warnings;
use parent 'Test::Class';

use SaharaSync::Util;
use Test::Exception;
use Test::More;

sub test_one_bad_logger : Test(4) {
    my @messages;

    my @logs = ({
        type      => 'IHadBetterNotExist',
        min_level => 'debug',
    }, {
        type      => 'Array',
        min_level => 'debug',
        array     => \@messages,
    });

    my $logger;
    lives_ok {
        $logger = SaharaSync::Util->load_logger(\@logs);
    };
    ok $logger;
    is scalar(@messages), 1;
    like $messages[0]{'message'}, qr/Unable to load logger 'IHadBetterNotExist'/;
}

sub test_one_bad_mandatory_logger : Test {
    my @logs = ({
        type      => 'IHadBetterNotExist',
        min_level => 'debug',
        mandatory => 1,
    }, {
        type      => 'Null',
        min_level => 'debug',
    });

    throws_ok {
        SaharaSync::Util->load_logger(\@logs);
    } qr/Unable to load mandatory logger 'IHadBetterNotExist'/;
}

sub test_all_bad_loggers : Test {
    my @logs = ({
        type      => 'IHadBetterNotExist',
        min_level => 'debug',
    }, {
        type      => 'IHadBetterNotExistEither',
        min_level => 'debug',
    });

    throws_ok {
        SaharaSync::Util->load_logger(\@logs);
    } qr/Unable to load any loggers/;
}

__PACKAGE__->runtests;
