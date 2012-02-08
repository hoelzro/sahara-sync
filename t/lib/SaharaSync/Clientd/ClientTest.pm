package SaharaSync::Clientd::ClientTest;

use strict;
use warnings;
use parent 'Test::Class::AnyEvent';

use Carp qw(confess croak);
use File::Slurp qw(read_dir read_file);
use Test::More;
use Test::Sahara::Client;
use Test::Sahara::Host;

sub catchup {
    my ( $self, $extra ) = @_;

    $extra = 1 unless defined $extra;

    for(my $i = 0; $i < $self->client_poll_interval + $extra; $i++) {
        sleep 1;
    }
}

sub client_poll_interval {
    return 1;
}

sub port {
    my $self = shift;

    if(@_) {
        $self->{'port'} = shift;
    }

    return $self->{'port'};
}

sub create_fresh_client {
    my ( $self, $client_num, %opts ) = @_;

    if($self->{"client$client_num"}) {
        confess "create_fresh_client called with existing client ($client_num)";
    }

    if(my $proxy = $opts{'proxy'}) {
        $opts{'port'} = $proxy->port;
    } else {
        $opts{'port'} = $self->port;
    }

    unless($opts{'poll_interval'}) {
        $opts{'poll_interval'} = $self->client_poll_interval;
    }

    return Test::Sahara::Client->new(
        num => $client_num,
        %opts,
    );
}

sub create_fresh_host {
    my ( $self ) = @_;

    if($self->{'hostd'}) {
        confess "create_fresh_host called without checking the host first";
    }

    return Test::Sahara::Host->new;
}

# This is two tests in one method
# It also cleans up the client pipe and object
sub check_client {
    my ( $self, $client_num ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    
    my $client = delete $self->{'client' . $client_num};

    return $client->check;
}

# four tests in one
# XXX consider rename
sub check_clients {
    my ( $self ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $ok = $self->check_client(1);
       $ok = $self->check_client(2) && $ok;

    unless($ok) {
        diag("Client check in method " . $self->current_method . " failed");
    }
}

# This method runs two tests, and cleans up the host object/pipe
sub check_host {
    my ( $self ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $host = delete $self->{'hostd'};

    unless($host->check) {
        diag("Host check in method " . $self->current_method . " failed");
    }
}

sub check_files {
    my ( $self, %opts ) = @_;

    # $opts{'force_wait'}

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $client_no  = $opts{'client'};
    my $dir        = $opts{'dir'};
    my $files      = $opts{'files'};
    my $name       = $opts{'name'};
    my $wait_time  = $opts{'wait_time'};
    my $is_waiting = exists($opts{'wait'}) ? $opts{'wait'} : 1;

    # XXX check %opts

    if($is_waiting) {
        $self->catchup($wait_time); # wait for a sync period
    }

    unless($client_no || $dir) {
        croak 'You must provide either client or dir to check_files';
    }
    if($client_no && $dir) {
        croak 'client and dir are mutually exclusive';
    }
    if($client_no && !exists $self->{'client' . $client_no}) {
        croak "client $client_no doesn't exist";
    }

    my $temp_dir = $client_no ? $self->{'client' . $client_no}->sync_dir : $dir;

    # this bit might be a little too specific to the inotify implementation...
    my @files         = grep { $_ ne '.saharasync' } read_dir($temp_dir);
    my %file_contents = (
        map {
            $_ => read_file(File::Spec->catfile($temp_dir, $_))
        } @files
    );

    is_deeply \%file_contents, $files, $name;
}


sub setup : Test(setup) {
    my ( $self ) = @_;

    $self->port(undef);

    $self->{'hostd'} = $self->create_fresh_host;

    $self->port($self->{'hostd'}->port);

    $self->{'client1'} = $self->create_fresh_client(1);
    $self->{'client2'} = $self->create_fresh_client(2);
}

sub teardown : Test(teardown => 6) {
    my ( $self ) = @_;

    $self->check_clients; # stop client daemons first (4 tests)
    $self->check_host;    # stop host daemon (1 test)

    if($ENV{'TEST_BAIL_EARLY'} && !$self->builder->is_passing) {
        $self->BAILOUT('Bailing out early');
    }
}

__PACKAGE__->SKIP_CLASS(1);

1;
