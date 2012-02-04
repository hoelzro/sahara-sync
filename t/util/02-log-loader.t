use strict;
use warnings;
use parent 'Test::Class';

use DateTime;
use SaharaSync::Util;
use Test::Exception;
use Test::More;

my $MESSAGE_RE = qr{
    \A
    \[
    (?<year>\d{4})
    -
    (?<month>\d{2})
    -
    (?<day>\d{2})
    [ ]
    (?<hour>\d{2})
    :
    (?<minute>\d{2})
    :
    (?<second>\d{2})
    \]
}x;

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

sub test_logger_timestamp : Test(1) {
    my @messages;

    my @loggers = ({
        type      => 'Array',
        min_level => 'debug',
        array     => \@messages,
    });

    my $logger = SaharaSync::Util->load_logger(\@loggers);
    $logger->info('test message');

    if($messages[0]{'message'} =~ /$MESSAGE_RE/) {
        my $now       = DateTime->now->set_time_zone('local');
        my $logged_ts = DateTime->new(
            year   => $+{'year'},
            month  => $+{'month'},
            day    => $+{'day'},
            hour   => $+{'hour'},
            minute => $+{'minute'},
            second => $+{'second'},
        )->set_time_zone('local');

        my $delta_ts = $now->epoch - $logged_ts->epoch;
        $delta_ts *= -1 if $delta_ts < 0;

        ok $delta_ts <= 1, 'logged timestamps should be in the current timezone';
    } else {
        fail 'failed to parse log message!';
        diag($messages[0]{'message'});
    }
}

__PACKAGE__->runtests;
