use strict;
use warnings;

use JSON qw(decode_json);
use SaharaSync::Stream::Reader;

use Test::Deep;
use Test::Sahara ':methods', tests => 15;

$Plack::Test::Impl = 'AnyEvent';

my $put_revision;
my $delete_revision;
my $metadata_present;
my $reader;

my @objects = (
    sub {
        {
            name     => 'file.txt',
            revision => $put_revision,
        }
    },
    sub {
        {
            name       => 'file.txt',
            revision   => $delete_revision,
            is_deleted => 1,
        }
    },
    sub {
        {
            name     => 'file.txt',
            revision => $put_revision,
        }
    },
    sub {
        {
            name       => 'file.txt',
            revision   => $delete_revision,
            is_deleted => 1,
        }
    },
    sub {
        {
            name       => 'file.txt',
            revision   => $delete_revision,
            is_deleted => 1,
            foo        => 18,
        }
    },
    sub {
        {
            name     => 'file.txt', 
            revision => $put_revision,
            foo      => 18,
        }
    },
    sub {
        {
            name       => 'file.txt',
            revision   => $delete_revision,
            is_deleted => 1,
            foo        => 18,
        }
    },
    sub {
        {
            name     => 'file2.txt',
            revision => $put_revision,
            foo      => 19,
        }
    },
    sub {
        {
            name     => 'file3.txt',
            revision => $put_revision,
            foo      => 20,
        }
    },
);

my $i = 0;

sub create_reader {
    my $reader = SaharaSync::Stream::Reader->for_mimetype('application/json');

    $reader->on_read_object(sub {
        my ( undef, $object ) = @_;

        is_deeply $object, $objects[$i++]->();
    });

    return $reader;
}

sub put_blob {
    my ( $cb, $streaming_res ) = @_;

    my $res   = $cb->(PUT_AUTHD '/blobs/file.txt', Content => 'Hello, there!');
    $put_revision = $res->header('ETag');
}

sub delete_blob {
    my ( $cb, $streaming_res ) = @_;

    my $res = $cb->(DELETE_AUTHD '/blobs/file.txt', 'If-Match' => $put_revision);
    $delete_revision = $res->header('ETag');
}

sub put_metadata_blob {
    my ( $cb, $streaming_res ) = @_;

    my $res = $cb->(PUT_AUTHD '/blobs/file.txt', Content => 'Hi, there!',
        'X-Sahara-Foo' => 18);
    $put_revision = $res->header('ETag');
}

sub put_metadata_blob2 {
    my ( $cb, $streaming_res ) = @_;

    my $res = $cb->(PUT_AUTHD '/blobs/file2.txt', Content => 'Two',
        'X-Sahara-Foo' => 19);
    $put_revision = $res->header('ETag');
}

sub put_metadata_blob3 {
    my ( $cb, $streaming_res ) = @_;

    my $res = $cb->(PUT_AUTHD '/blobs/file3.txt', Content => 'Three',
        'X-Sahara-Bar' => 19, 'X-Sahara-Foo' => 20);
    $put_revision = $res->header('ETag');
}

test_host sub {
    my ( $cb ) = @_;

    my $streaming_res;

    $reader        = create_reader;
    $streaming_res = $cb->(GET_AUTHD '/changes.json');
    is $streaming_res->code, 200;
    ok !defined($streaming_res->header('Content-Length'));
    is $streaming_res->content_type, 'application/json';

    $streaming_res->on_content_received(sub {
        my ( $content ) = @_;

        $reader->feed($content);
    });

    my @callbacks = (
        \&put_blob,
        \&delete_blob,
        \&put_metadata_blob,
        \&delete_blob,
    );

    my $timer = AnyEvent->timer(
        interval => 0.5,
        cb       => sub {
            if(@callbacks) {
                my $callback = shift @callbacks;
                $callback->($cb, $streaming_res);
            } else {
                $streaming_res->send;
                $reader->feed(undef);
            }
        },
    );

    $streaming_res->recv;

    $metadata_present = 1;

    $reader        = create_reader;
    $streaming_res = $cb->(GET_AUTHD '/changes.json?metadata=foo');
    is $streaming_res->code, 200;
    ok !defined($streaming_res->header('Content-Length'));
    is $streaming_res->content_type, 'application/json';

    $streaming_res->on_content_received(sub {
        my ( $content ) = @_;

        $reader->feed($content);
    });

    @callbacks = (
        \&put_metadata_blob,
        \&delete_blob,
    );

    $timer = AnyEvent->timer(
        interval => 0.5,
        cb       => sub {
            if(@callbacks) {
                my $callback = shift @callbacks;
                $callback->($cb, $streaming_res);
            } else {
                $streaming_res->send;
                $reader->feed(undef);
            }
        },
    );

    $streaming_res->recv;

    @callbacks = (
        \&put_metadata_blob2,
        \&put_metadata_blob3,
    );

    my $res           = $cb->(PUT_AUTHD '/blobs/file1.txt', Content => 'One');
    my $last_revision = $put_revision = $res->header('ETag');

    $reader        = create_reader;
    $streaming_res = $cb->(GET_AUTHD '/changes.json?metadata=foo', 'X-Sahara-Last-Sync' => $last_revision);

    $streaming_res->on_content_received(sub {
        my ( $content ) = @_;

        $reader->feed($content);
    });

    $timer = AnyEvent->timer(
        interval => 0.5,
        cb       => sub {
            if(@callbacks) {
                my $callback = shift @callbacks;
                $callback->($cb, $streaming_res);
            } else {
                $streaming_res->send;
                $reader->feed(undef);
            }
        },
    );

    $streaming_res->recv;
};
