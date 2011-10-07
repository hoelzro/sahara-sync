package SaharaSync::Hostd::Launcher;

use strict;
use warnings;

use AnyEvent;
use SaharaSync::Hostd;
use SaharaSync::Hostd::Server;
use UNIVERSAL;

use namespace::clean -except => 'meta';

sub run {
    my ( undef, $config ) = @_;

    my $hostd;

    if(UNIVERSAL::isa($config, 'SaharaSync::Hostd')) {
        $hostd = $config;
    } else {
        $hostd = SaharaSync::Hostd->new($config);
    }

    my $server = SaharaSync::Hostd::Server->new(
        port => $hostd->port,
        host => $hostd->host,
    );
    $server->start($hostd->to_app);

    my $cond = AnyEvent->condvar;

    my $term = AnyEvent->signal(
        signal => 'TERM',
        cb     => sub {
            $cond->send;
        },
    );

    my $int = AnyEvent->signal(
        signal => 'INT',
        cb     => sub {
            $cond->send;
        },
    );

    my $pipe = AnyEvent->signal(
        signal => 'PIPE',
        cb     => sub {},
    );

    $hostd->log->info('Starting host daemon');
    $cond->recv;
    $server->stop;
}

1;

__END__

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
