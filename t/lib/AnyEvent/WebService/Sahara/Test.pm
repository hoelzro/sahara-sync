package AnyEvent::WebService::Sahara::Test;

use strict;
use warnings;
use parent 'Test::Class::AnyEvent';
use utf8;

use Test::More;
use Test::Sahara ':methods';
use Test::Sahara::Proxy;
use Test::TCP qw(empty_port);

use AnyEvent::WebService::Sahara;
use IO::String;
use LWP::UserAgent;
use Plack::Builder;
use Plack::Loader;

my $BAD_REVISION = '0' x 40;

sub client {
    my $self = shift;

    if(@_) {
        $self->{'client'} = shift;
    }
    return $self->{'client'};
}

sub server {
    my $self = shift;

    if(@_) {
        $self->{'server'} = shift;
    }

    return $self->{'server'};
}

sub create_client {
    my ( $self, $port ) = @_;

    $port ||= $self->port;

    return AnyEvent::WebService::Sahara->new(
        url           => 'http://localhost:' . $port,
        user          => 'test',
        password      => 'abc123',
        poll_interval => $self->client_poll_time,
    );
}

sub create_fresh_app {
    return Test::Sahara->create_fresh_app;
}

sub port {
    my ( $self ) = @_;

    return $self->server->port;
}

sub expected_capabilities {
    return ['streaming'];
}

sub client_poll_time {
    return 1;
}

sub setup : Test(setup) {
    my ( $self ) = @_;

    my $app = $self->create_fresh_app;
    $self->server(Test::TCP->new(
        code => sub {
            my ( $port ) = @_;

            my $server = Plack::Loader->auto(
                port => $port,
                host => '127.0.0.1',
            );
            $server->run($app);
        },
    ));

    $self->client($self->create_client);
}

sub cleanup : Test(teardown) {
    my ( $self ) = @_;

    $self->client(undef);
    $self->server(undef);
}

sub test_bad_connection : Test(10) {
    my $cond;
    my $bad_port = empty_port;
    my $client = AnyEvent::WebService::Sahara->new(
        url      => "http://localhost:$bad_port",
        user     => 'test',
        password => 'abc123',
    );

    $cond = AnyEvent->condvar;

    $client->capabilities(sub {
        my ( $c, $capabilities, $error ) = @_;

        is $capabilities, undef, "first callback argument should be undef on error";
        like $error, qr/Connection refused/i, "second callback argument should be error string on error";
        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->get_blob('file.txt', sub {
        my ( $c, $h, $metadata ) = @_;

        is $h, undef, "first callback argument should be undef on error";
        like $metadata, qr/Connection refused/i, "second callback argument should be error string on error";
        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->put_blob('file.txt', IO::String->new('something'), {}, sub {
        my ( $c, $revision, $error ) = @_;

        is $revision, undef, "first callback argument should be undef on error";
        like $error, qr/Connection refused/i, "second callback argument should be error string on error";
        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->delete_blob('file.txt', $BAD_REVISION, sub {
        my ( $c, $revision, $error ) = @_;

        is $revision, undef, "first callback argument should be undef on error";
        like $error, qr/Connection refused/i, "second callback argument should be error string on error";
        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->changes(undef, [], sub {
        my ( $c, $change, $error ) = @_;

        is $change, undef, "first callback argument should be undef on error";
        like $error, qr/Connection refused/i, "second callback argument should be error string on error";
        $cond->send;
    });

    $cond->recv;
}

sub test_bad_credentials : Test(18) {
    my ( $self ) = @_;

    my $cond;
    my $client1 = AnyEvent::WebService::Sahara->new(
        url      => "http://localhost:" . $self->port,
        user     => 'test',
        password => 'shit',
    );

    my $client2 = AnyEvent::WebService::Sahara->new(
        url      => "http://localhost:" . $self->port,
        user     => 'test2',
        password => 'abc123',
    );

    foreach my $client ($client1, $client2) {
        $cond = AnyEvent->condvar;

        $client->capabilities(sub {
            my ( $c, $capabilities ) = @_;
            is_deeply($capabilities, $self->expected_capabilities, "Capabilities should be fetchable with bad auth");
            $cond->send;
        });

        $cond->recv;

        $cond = AnyEvent->condvar;

        $client->get_blob('file.txt', sub {
            my ( $c, $h, $metadata ) = @_;
            is $h, undef, "First callback argument should be undef on auth error";
            like $metadata, qr/Unauthorized/, "Second callback argument should be error message on auth error";
            $cond->send;
        });

        $cond->recv;

        $cond = AnyEvent->condvar;

        $client->put_blob('file.txt', IO::String->new('Test content'), {}, sub {
            my ( $c, $revision, $error ) = @_;
            is $revision, undef, "First callback argument should be undef on auth error";
            like $error, qr/Unauthorized/, "Second callback argument should be error message on auth error";
            $cond->send;
        });

        $cond->recv;

        $cond = AnyEvent->condvar;

        $client->delete_blob('file.txt', $BAD_REVISION, sub {
            my ( $c, $revision, $error ) = @_;
            is $revision, undef, "First callback argument should be undef on auth error";
            like $error, qr/Unauthorized/, "Second callback argument should be error message on auth error";
            $cond->send;
        });

        $cond->recv;

        $cond = AnyEvent->condvar;

        $client->changes(undef, [], sub {
            my ( $c, $change, $error ) = @_;
            is $change, undef, "First callback argument should be undef on auth error";
            like $error, qr/Unauthorized/, "Second callback argument should be error message on auth error";
            $cond->send;
        });

        $cond->recv;
    }
}

sub test_capabilities : Test {
    my ( $self ) = @_;

    my $client = $self->client;

    my $cond = AnyEvent->condvar;

    $client->capabilities(sub {
        my ( $c, $capabilities ) = @_;
        is_deeply($capabilities, $self->expected_capabilities, "Streaming capabilities should be present");
        $cond->send;
    });

    $cond->recv;
}

sub test_get_blob : Test(10) {
    my ( $self ) = @_;

    my $client = $self->client;

    my $last_revision;
    my $cond = AnyEvent->condvar;

    $client->get_blob('file.txt', sub {
        my ( $c, $h, $metadata ) = @_;

        ok !defined($h), "Handle should be undefined for non-existent blob";
        like $metadata, qr/Not found/i, "Error message should be passed as second callback argument";
        $cond->send;
    });

    $cond->recv;

    $cond = AnyEvent->condvar;

    $client->put_blob('file.txt', IO::String->new('Test content'), {}, sub {
        my ( $c, $revision ) = @_;

        ok $revision, "put_blob should succeed";
        $last_revision = $revision;
        $cond->send;
    });

    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->get_blob('file.txt', sub {
        my ( $c, $h, $metadata ) = @_;

        is_deeply $metadata, { revision => $last_revision }, "putting empty metadata should yield metadata with only the revision";
        isa_ok $h, 'AnyEvent::Handle', "content handle should be an AnyEvent::Handle";

        my $content = '';

        $h->on_read(sub {
            $content .= $h->rbuf;
            $h->rbuf = '';
        });

        $h->on_eof(sub {
            $cond->send($content);
        });
    });

    is $cond->recv, 'Test content', "blob contents should match put_blob contents";

    my %meta = (
        foo => 'some value',
    );

    $cond = AnyEvent->condvar;
    $client->put_blob('file2.txt', IO::String->new('Test content 2: The sequel'), \%meta, sub {
        my ( $c, $revision ) = @_;

        ok $revision, "put_blob with metadata should suceed";
        $last_revision = $revision;
        $cond->send;
    });

    $cond->recv;

    $cond    = AnyEvent->condvar;
    $client->get_blob('file2.txt', sub {
        my ( $c, $h, $metadata ) = @_;

        is_deeply $metadata, { foo => 'some value', revision => $last_revision }, "metadata should match";
        isa_ok $h, 'AnyEvent::Handle', "content handle should ben an AnyEvent::Handle";

        my $content = '';

        $h->on_read(sub {
            $content .= $h->rbuf;
            $h->rbuf = '';
        });
        $h->on_eof(sub {
            $cond->send($content);
        });
    });

    is $cond->recv, 'Test content 2: The sequel', "blob contents should match put_blob contents" ;
}

sub test_put_blob : Test(8) {
    my ( $self ) = @_;

    my $cond;
    my $last_revision;
    my $client = $self->client;

    $cond = AnyEvent->condvar;
    $client->put_blob('file.txt', IO::String->new('Test content'), { revision => $BAD_REVISION }, sub {
        my ( $c, $revision, $error ) = @_;

        is $revision, undef, "specifying revision on create should conflict";
        like $error, qr/conflict/i;

        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->put_blob('file.txt', IO::String->new('Test content'), {}, sub {
        my ( $c, $revision ) = @_;

        $last_revision = $revision;

        ok $revision, "revision should be passed to callback on put_blob";
        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->put_blob('file.txt', IO::String->new('Test content 2'), {}, sub {
        my ( $c, $revision, $error ) = @_;

        is $revision, undef, "not specifying a revision on update should conflict";
        like $error, qr/conflict/i;
        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->put_blob('file.txt', IO::String->new('Test content 2'), { revision => $BAD_REVISION }, sub {
        my ( $c, $revision, $error ) = @_;

        is $revision, undef, "specifying a bad revision on update should error out";
        like $error, qr/conflict/i;
        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->put_blob('file.txt', IO::String->new('Test content 2'), { revision => $last_revision }, sub {
        my ( $c, $revision ) = @_;

        ok $revision, "specifying the correct revision on update should succeed";
        $cond->send;
    });
    $cond->recv;
}

sub test_metadata : Test(6) {
    my ( $self ) = @_;

    my $last_revision;
    my $cond   = AnyEvent->condvar;
    my $client = $self->client;

    $client->put_blob('file.txt', IO::String->new('Test content'), { foo => 17 }, sub {
        my ( $c, $revision ) = @_;

        ok $revision, "creating a blob with metadata should succeed";
        $last_revision = $revision;
        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->get_blob('file.txt', sub {
        my ( $c, undef, $metadata ) = @_;

        is_deeply $metadata, { foo => 17, revision => $last_revision }, "metadata should match";
        $cond->send;
    });
    $cond->recv;
    
    $cond = AnyEvent->condvar;
    $client->put_blob('file.txt', IO::String->new('Test content 2'), { foo => 18, bar => 21, revision => $last_revision }, sub {
        my ( $c, $revision ) = @_;
        ok $revision, "updating a blob with metadata shold succeed" or diag($_[1]);
        $last_revision = $revision;
        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->get_blob('file.txt', sub {
        my ( $c, undef, $metadata ) = @_;

        is_deeply $metadata, {
            foo      => 18,
            bar      => 21,
            revision => $last_revision,
        }, "metadata should match";

        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->put_blob('file.txt', IO::String->new('Test content 3'), { foo => 19, revision => $last_revision }, sub {
        my ( $c, $revision ) = @_;
        ok $revision, "updating a blob with metadata shold succeed";
        $last_revision = $revision;
        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->get_blob('file.txt', sub {
        my ( $c, undef, $metadata ) = @_;

        is_deeply $metadata, {
            foo      => 19,
            bar      => 21,
            revision => $last_revision,
        }, "metadata should match";

        $cond->send;
    });
    $cond->recv;
}

sub test_unicode_metadata : Test(4) {
    my ( $self ) = @_;

    my $cond;
    my $last_revision;
    my $client = $self->client;

    $cond = AnyEvent->condvar;
    $client->put_blob('file.txt', IO::String->new('Test content'), { word => 'über'}, sub {
        my ( $c, $revision ) = @_;

        ok $revision, "creating a blob with Unicode metadata should succeed";
        $last_revision = $revision;
        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->get_blob('file.txt', sub {
        my ( $c, undef, $metadata ) = @_;

        is_deeply $metadata, { word => 'über', revision => $last_revision },
            "Unicode metadata should match";
        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->put_blob('file.txt', IO::String->new('Test content 2'), { word => 'schön', revision => $last_revision }, sub {
        my ( $c, $revision ) = @_;

        ok $revision, "updating a blob with Unicode metadata should succeed";
        $last_revision = $revision;
        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->get_blob('file.txt', sub {
        my ( $c, undef, $metadata ) = @_;

        is_deeply $metadata, { word => 'schön', revision => $last_revision },
            "Unicode metadata should match";
        $cond->send;
    });
    $cond->recv;
}

sub test_delete_blob : Test(8) {
    my ( $self ) = @_;

    my $cond;
    my $last_revision;
    my $client = $self->client;

    $cond = AnyEvent->condvar;
    $client->delete_blob('file.txt', undef, sub {
        my ( $c, $revision, $error ) = @_;

        is $revision, undef, "Deleting a non-existent blob should fail";
        like $error, qr/revision required/i;
        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->delete_blob('file.txt', $BAD_REVISION, sub {
        my ( $c, $revision, $error ) = @_;

        is $revision, undef, "Deleting a non-existent blob should fail";
        like $error, qr/Not found/i;
        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->put_blob('file.txt', IO::String->new('Test content'), {}, sub {
        my ( $c, $revision ) = @_;

        ok $revision;
        $last_revision = $revision;
        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->delete_blob('file.txt', $BAD_REVISION, sub {
        my ( $c, $revision, $error ) = @_;

        is $revision, undef, "Deleting a blob with a bad revision should fail";
        like $error, qr/conflict/i;
        $cond->send;
    });
    $cond->recv;

    $cond = AnyEvent->condvar;
    $client->delete_blob('file.txt', $last_revision, sub {
        my ( $c, $revision ) = @_;

        ok $revision, "deleting a revision with a good revision should succeed";
        $cond->send;
    });
    $cond->recv;
}

sub test_streaming_changes : Test(4) {
    my ( $self ) = @_;

    my $expected_change;
    my $first_revision;
    my $revision;
    my $cond;
    my $res;
    my $client = $self->client;
    my $ua     = LWP::UserAgent->new;

    $client->changes(undef, [], sub {
        my ( $c, $change ) = @_;

        is_deeply($change, $expected_change, "changes should match");
        $cond->send;
    });

    # we need to use synchronous REST calls here, to guarantee ordering so that
    # the revision is correctly set

    my $port = $self->port;
    $cond = AnyEvent->condvar;
    $res  = $ua->request(PUT_AUTHD "http://localhost:$port/blobs/file.txt", Content => 'Test Content');
    $first_revision = $revision = $res->header('ETag');
    $expected_change = {
        name     => 'file.txt',
        revision => $revision,
    };
    $cond->recv;

    $cond = AnyEvent->condvar;
    $res  = $ua->request(PUT_AUTHD "http://localhost:$port/blobs/file.txt", Content => 'Test Content 2', 'If-Match' => $revision);
    $revision = $res->header('ETag');
    $expected_change = {
        name     => 'file.txt',
        revision => $revision,
    };
    $cond->recv;

    $cond = AnyEvent->condvar;
    $res  = $ua->request(PUT_AUTHD "http://localhost:$port/blobs/file.txt", Content => 'Test Content 3', 'If-Match' => $first_revision);
    $expected_change = {};
    my $timer_fired;
    my $timer = AnyEvent->timer(
        after => 1,
        cb    => sub {
            $timer_fired = 1;
            $cond->send;
        },
    );
    $cond->recv;
    ok $timer_fired, "no changes for failed requests";

    $cond = AnyEvent->condvar;
    $res  = $ua->request(DELETE_AUTHD "http://localhost:$port/blobs/file.txt", 'If-Match' => $revision);
    $revision = $res->header('ETag');
    $expected_change = {
        name       => 'file.txt',
        revision   => $revision,
        is_deleted => 1,
    };
    $cond->recv;
}

sub test_streaming_changes_since : Test(5) {
    my ( $self ) = @_;

    my $cond;
    my $res;
    my $revision;
    my $revision2;
    my $expected_change;
    my $seen_change;
    my $first_round = 1;
    my $client  = $self->client;
    my $ua      = LWP::UserAgent->new;

    my $port = $self->port;
    $cond = AnyEvent->condvar;
    $res  = $ua->request(PUT_AUTHD "http://localhost:$port/blobs/file.txt", Content => 'Test Content');
    $revision = $res->header('ETag');
    $expected_change = {
        name     => 'file.txt',
        revision => $revision,
    };

    my $guard = $client->changes(undef, [], sub {
        my ( $c, $change ) = @_;

        is_deeply($change, $expected_change);

        $cond->send;
    });

    my $guard2 = $client->changes($revision, [], sub {
        my ( $c, $change ) = @_;

        if($first_round) {
            $seen_change = 1;
        } else {
            is_deeply($change, $expected_change);
        }
    });
    $cond->recv;
    ok !$seen_change;
    $first_round = 0;

    $cond = AnyEvent->condvar;
    $res  = $ua->request(PUT_AUTHD "http://localhost:$port/blobs/file.txt", Content => 'Test Content', 'If-Match' => $revision);
    $revision = $res->header('ETag');
    $expected_change = {
        name     => 'file.txt',
        revision => $revision,
    };

    $cond->recv;

    undef $guard;
    undef $guard2;

    $cond = AnyEvent->condvar;
    $res  = $ua->request(DELETE_AUTHD "http://localhost:$port/blobs/file.txt", 'If-Match' => $revision);
    $revision = $res->header('ETag');

    $res = $ua->request(PUT_AUTHD "http://localhost:$port/blobs/file.txt",
        Content => 'Back for round 2');
    $revision2 = $res->header('ETag');

    $client->changes($revision, [], sub {
        my ( $c, $change ) = @_;

        is_deeply($change, {
            name     => 'file.txt',
            revision => $revision2,
        }, "Streaming changes since deleted revision should succeed");

        $cond->send;
    });

    $cond->recv;
}

sub test_changes_metadata : Test(45) {
    my ( $self ) = @_;

    my $port = $self->port;
    my $client = $self->client;
    my $expected_change;
    my $change_count;
    my $cond;
    my $ua = LWP::UserAgent->new;
    my $revision;
    my %url_revisions;

    my @operations = (
        [PUT => 'file.txt', Content => 1],
        [PUT => 'file1.txt', Content => 1, 'X-Sahara-Foo' => 12],
        [PUT => 'file.txt', Content => 2],
        [DELETE => 'file.txt'],
        [PUT => 'file2.txt', Content => 4, 'X-Sahara-Bar' => 13],
        [PUT => 'file3.txt', Content => 5, 'X-Sahara-Foo' => 1073, 'X-Sahara-Bar' => 'nineteen'],
        [PUT => 'file4.txt', Content => 25, 'X-Sahara-Foo' => 1, 'X-Sahara-Baz' => 2],
        [DELETE => 'file2.txt'],
        [DELETE => 'file3.txt'],
        [DELETE => 'file4.txt'],
    );

    my @expectations = (
        lazy_hash { name => 'file.txt', revision => $revision },
        lazy_hash { name => 'file1.txt', revision => $revision, foo => 12 },
        lazy_hash { name => 'file.txt', revision => $revision },
        lazy_hash { name => 'file.txt', revision  => $revision, is_deleted => 1 },
        lazy_hash { name => 'file2.txt', revision => $revision, bar => 13 },
        lazy_hash { name => 'file3.txt', revision => $revision, foo => 1073, bar => 'nineteen' },
        lazy_hash { name => 'file4.txt', revision => $revision, foo => 1 },
        lazy_hash { name => 'file2.txt', revision => $revision, bar => 13, is_deleted => 1 },
        lazy_hash { name => 'file3.txt', revision => $revision, foo => 1073, bar => 'nineteen', is_deleted => 1 },
        lazy_hash { name => 'file4.txt', revision => $revision, foo => 1, is_deleted => 1 },
    );
    my %seen_changes;

    my $run_operations = sub {
        my $i = 0;
        foreach my $op (@operations) {
            my $expected = $expectations[$i++];
            my ( $method, $url, @headers ) = @$op;
            $url = "http://localhost:$port/blobs/" . $url;
            if(my $current_revision = $url_revisions{$url}) {
                push @headers, 'If-Match' => $current_revision;
            }
            my $res = $ua->request(REQUEST_AUTHD $method, $url, @headers);
            fail "FUCK" unless $res->code =~ /^2/;
            $revision = $res->header('ETag');
            if($method eq 'DELETE') {
                delete $url_revisions{$url};
            } else {
                $url_revisions{$url} = $revision;
            }
            $change_count = 2;
            $expected_change = $expected->();
            $seen_changes{$expected_change->{'name'}} = $expected_change;

            $cond = AnyEvent->condvar;
            $cond->recv;
        }
    };

    my $changes1 = $client->changes(undef, ['foo'], sub {
        my ( $c, $change ) = @_;

        my $copy = { %$expected_change };
        delete $copy->{'bar'};

        is_deeply($change, $copy, "metadata changes should match");
        $cond->send unless --$change_count;
    });

    my $changes2 = $client->changes(undef, ['foo', 'bar'], sub {
        my ( $c, $change ) = @_;

        is_deeply($change, $expected_change, "metadata changes should match");
        $cond->send unless --$change_count;
    });

    $run_operations->();

    my $standalone = 1;
    $changes1 = $client->changes(undef, ['foo', 'bar'], sub {
        my ( $c, $change ) = @_;

        my $seen_change = delete $seen_changes{$change->{'name'}};
        is_deeply($change, $seen_change, "metadata changes should match");
        if($standalone) {
            $cond->send unless %seen_changes;
        } else {
            $cond->send unless --$change_count;
        }
    });

    undef $changes2;

    $cond = AnyEvent->condvar;
    $cond->recv;

    $standalone = 0;
    $changes2 = $client->changes($revision, ['foo', 'bar'], sub {
        my ( $c, $change ) = @_;

        is_deeply($change, $expected_change, "metadata changes should match");
        $cond->send unless --$change_count;
    });

    $run_operations->();
}

sub test_cancel_changes : Test(10) {
    my ( $self ) = @_;

    my $port          = $self->port;
    my $seen_change1  = 0;
    my $seen_change2  = 0;
    my $seen_change3  = 0;
    my $total_changes = 3;
    my $client = $self->client;
    my $ua     = LWP::UserAgent->new;
    my $cond;
    my $res;
    my $revision;

    $client->changes(undef, [], sub {
        $seen_change1++;
        $cond->send unless --$total_changes;
    });

    my $guard = $client->changes(undef, [], sub {
        $seen_change2++;
        $cond->send unless --$total_changes;
    });

    my $guard2 = $client->changes(undef, [], sub {
        $seen_change3++;
        $cond->send unless --$total_changes;
    });

    $res = $ua->request(PUT_AUTHD "http://localhost:$port/blobs/file.txt",
        Content => 'Test Content');
    $revision = $res->header('ETag');

    $cond = AnyEvent->condvar;
    $cond->recv;

    is $seen_change1, 1;
    is $seen_change2, 1;
    is $seen_change3, 1;

    undef $guard;

    $seen_change1  = $seen_change2 = $seen_change3 = 0;
    $total_changes = 2;

    $res = $ua->request(PUT_AUTHD "http://localhost:$port/blobs/file.txt",
        Content => 'Test Content 2', 'If-Match' => $revision);
    $revision = $res->header('ETag');

    $cond = AnyEvent->condvar;
    $cond->recv;

    is $seen_change1, 1;
    is $seen_change2, 0;
    is $seen_change3, 1;

    $self->client(undef);
    undef $client;

    $seen_change1  = $seen_change2 = $seen_change3 = 0;
    $total_changes = 0;

    $res = $ua->request(PUT_AUTHD "http://localhost:$port/blobs/file.txt",
        Content => 'Test Content 3', 'If-Match' => $revision);
    is $res->code, 200;
    $revision = $res->header('ETag');

    my $timer = AnyEvent->timer(
        after => $self->client_poll_time + 5,
        cb    => sub {
            $cond->send;
        },
    );

    $cond = AnyEvent->condvar;
    $cond->recv;

    is $seen_change1, 0;
    is $seen_change2, 0;
    is $seen_change3, 0;
}

sub test_own_changes_invisible : Test(8) {
    my ( $self ) = @_;

    my $cond;
    my $timer;
    my @client1_changes;
    my @client2_changes;
    my $client1 = $self->create_client;
    my $client2 = $self->create_client;
    my $revision1;
    my $revision2;

    $client1->changes(undef, [], sub {
        my ( $c, $change ) = @_;

        push @client1_changes, $change;
    });

    $client2->changes(undef, [], sub {
        my ( $c, $change ) = @_;

        push @client2_changes, $change;
    });

    $cond  = AnyEvent->condvar;
    $timer = AnyEvent->timer(
        after    => $self->client_poll_time + 5,
        interval => $self->client_poll_time + 5,
        cb    => sub {
            $cond->send;
        },
    );

    $client1->put_blob('file.txt', IO::String->new('Test content'), {}, sub {
        ( undef, $revision1 ) = @_;
    });

    $cond->recv;

    is_deeply(\@client1_changes, []);
    is_deeply(\@client2_changes, [{
        name     => 'file.txt',
        revision => $revision1,
    }]);

    @client1_changes = @client2_changes = ();
    $cond = AnyEvent->condvar;

    $client2->put_blob('file2.txt', IO::String->new('Test content 2'), {}, sub {
        ( undef, $revision2 ) = @_;
    });

    $cond->recv;

    is_deeply(\@client1_changes, [{
        name     => 'file2.txt',
        revision => $revision2,
    }]);
    is_deeply(\@client2_changes, []);

    @client1_changes = @client2_changes = ();
    $cond = AnyEvent->condvar;

    $client1->delete_blob('file2.txt', $revision2, sub {
        ( undef, $revision2 ) = @_;
    });

    $cond->recv;

    is_deeply(\@client1_changes, []);
    is_deeply(\@client2_changes, [{
        name       => 'file2.txt',
        revision   => $revision2,
        is_deleted => 1,
    }]);

    @client1_changes = @client2_changes = ();
    $cond = AnyEvent->condvar;

    $client2->delete_blob('file.txt', $revision1, sub {
        ( undef, $revision1 ) = @_;
    });

    $cond->recv;

    is_deeply(\@client1_changes, [{
        name       => 'file.txt',
        revision   => $revision1,
        is_deleted => 1,
    }]);
    is_deeply(\@client2_changes, []);
}

sub test_conflicting_change_in_flight : Test(4) {
    my ( $self ) = @_;

    my $cond;
    my $timer;
    my @client1_changes;
    my @client2_changes;
    my $revision1;
    my $revision2;
    my $client1 = $self->create_client;
    my $client2 = $self->create_client;

    $client1->changes(undef, [], sub {
        my ( undef, $change ) = @_;

        push @client1_changes, $change;
    });

    $client2->changes(undef, [], sub {
        my ( undef, $change ) = @_;

        push @client2_changes, $change;
    });

    $cond  = AnyEvent->condvar;
    $timer = AnyEvent->timer(
        after    => $self->client_poll_time + 5,
        interval => $self->client_poll_time + 5,
        cb    => sub {
            $cond->send;
        },
    );

    $client1->put_blob('file.txt', IO::String->new('Content 1'), {}, sub {
        ( undef, $revision1 ) = @_;
    });

    $client2->put_blob('file.txt', IO::String->new('Content 2'), {}, sub {
        ( undef, $revision2 ) = @_;
    });

    $cond->recv;

    ok($revision1 xor $revision2);

    my $revision = $revision1 || $revision2;
    my @expected_changes = ({
        name     => 'file.txt',
        revision => $revision,
    });

    if($revision1) {
        is_deeply \@client2_changes, \@expected_changes;
    } else {
        is_deeply \@client1_changes, \@expected_changes;
    }

    $cond = AnyEvent->condvar;

    $client1->delete_blob('file.txt', $revision, sub {
        ( undef, $revision1 ) = @_;
    });

    $client2->delete_blob('file.txt', $revision, sub {
        ( undef, $revision2 ) = @_;
    });

    @client1_changes = @client2_changes = ();
    $cond->recv;

    ok($revision1 xor $revision2);

    $revision = $revision1 || $revision2;
    @expected_changes = ({
        name       => 'file.txt',
        revision   => $revision,
        is_deleted => 1,
    });

    if($revision1) {
        is_deeply \@client2_changes, \@expected_changes;
    } else {
        is_deeply \@client1_changes, \@expected_changes;
    }
}

sub test_guard_request_in_flight : Test(2) {
    my ( $self ) = @_;

    my $app     = $self->create_fresh_app;
    my $delayed = builder {
        enable_if { $_[0]->{'REQUEST_METHOD'} eq 'GET' } 'Delay', delay => $self->client_poll_time + 5;
        $app;
    };

    my $port = $self->port;

    $self->server(Test::TCP->new(
        port => $port,
        code => sub {
            my ( $port ) = @_;

            my $server = Plack::Loader->auto(
                port => $port,
                host => '127.0.0.1',
            );
            $server->run($delayed);
        },
    ));

    my $ua  = LWP::UserAgent->new;
    my $res;
    do {
        sleep 1;
        $res = $ua->request(HEAD "http://localhost:$port/");
    } until $res->is_success;

    $res = $ua->request(PUT_AUTHD "http://localhost:$port/blobs/file.txt",
        Content => 'Test Content');

    is $res->code, 201 or diag($res->content);

    my $change_seen;
    my $guard = $self->client->changes(undef, [], sub {
        $change_seen = 1;
    });

    my $expire_timer;
    my $stop_timer;
    my $cond = AnyEvent->condvar;

    $expire_timer = AnyEvent->timer(
        after => $self->client_poll_time + 1,
        cb    => sub {
            undef $guard;
        },
    );

    $stop_timer = AnyEvent->timer(
        after => $self->client_poll_time + 10,
        cb    => sub {
            $cond->send;
        },
    );

    $cond->recv;
    ok !$change_seen;
}

sub test_unavailable_hostd : Test(1) {
    my ( $self ) = @_;

    my $proxy   = Test::Sahara::Proxy->new(remote => $self->port);
    my $client1 = $self->create_client;
    my $client2 = $self->create_client($proxy->port);
    my @client2_changes;
    my $revision;
    my $timer;

    my $cond = AnyEvent->condvar;

    $client2->changes(undef, [], sub {
        my ( undef, $change ) = @_;

        # XXX test for when an error occurs
        if(defined $change) {
            push @client2_changes, $change;
            $cond->send;
        }
    });

    # give the client time to actually establish a stream
    # if need be
    $timer = AnyEvent->timer(
        after => 1,
        cb    => sub {
            $cond->send;
        },
    );

    $cond->recv;
    $cond = AnyEvent->condvar;

    $proxy->kill_connections;

    $client1->put_blob('file.txt', IO::String->new('Content'), {}, sub {
        ( undef, $revision ) = @_;

        $timer = AnyEvent->timer(
            after => $self->client_poll_time + 5,
            cb    => sub {
                $cond->send;
            },
        );
    });

    $cond->recv;
    $cond = AnyEvent->condvar;

    $proxy->resume_connections;

    $timer = AnyEvent->timer(
        after => $self->client_poll_time + 5,
        cb    => sub {
            $cond->send;
        },
    );

    $cond->recv;

    is_deeply \@client2_changes, [{
        name     => 'file.txt',
        revision => $revision,
    }], 'change should show up on client2 even after connection loss';
}

## check non-change callbacks being called after destruction?

__PACKAGE__->SKIP_CLASS(1);
