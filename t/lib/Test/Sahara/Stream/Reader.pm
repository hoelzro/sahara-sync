package Test::Sahara::Stream::Reader;

use strict;
use warnings;
use parent 'Test::Class';
use autodie qw(pipe);

use Test::Exception;
use Test::More;

use AnyEvent;
use AnyEvent::Handle;
use IO::Handle;
use IO::String;
use SaharaSync::Stream::Reader;

sub reader {
    my $self = shift;

    if(@_) {
        $self->{'reader'} = shift;
    }
    return $self->{'reader'};
}

sub setup : Test(setup => 1) {
    my ( $self ) = @_;

    $self->reader(SaharaSync::Stream::Reader->for_mimetype($self->mime_type));
    ok $self->reader->does('SaharaSync::Stream::Reader'),
        "for_mimetype should return a SaharaSync::Stream::Reader";
}

sub teardown : Test(teardown) {
    my ( $self ) = @_;

    $self->reader(undef);
}

my @values = (
    undef,
    428,
    'foobar',
    [],
    [1],
    [1, 19],
    {},
    { foo => 5297 },
    { foo => 5297, bar => 33 },
);

sub test_no_callbacks : Test(2) {
    my ( $self ) = @_;

    my $reader = $self->reader;
    my $stream = IO::String->new;
    $self->begin_stream($stream);
    $self->serialize($stream, $_) foreach @values;
    $self->end_stream($stream);

    lives_ok {
        $reader->feed(${ $stream->string_ref });
    } "Feeding a reader that uses no callbacks should succeed";

    lives_ok {
        $reader->feed(undef);
    } "Feeding undef to a reader that uses no callbacks should succeed";
}

sub test_basic : Test(10) {
    my ( $self ) = @_;

    my $reader = $self->reader;
    my $stream = IO::String->new;
    $self->begin_stream($stream);
    $self->serialize($stream, $_) foreach @values;
    $self->end_stream($stream);

    my $i        = 0;
    my $seen_eof = 0;
    $reader->on_read_object(sub {
        my ( undef, $object ) = @_;

        is_deeply($object, $values[$i++], "Received objects should match");
    });
    $reader->on_end(sub {
        $seen_eof = 1;
    });

    $reader->feed(${ $stream->string_ref });
    $reader->feed(undef);
    ok $seen_eof, "We see end of stream when undef is seen";
}

sub test_basic_chunked : Test(9) {
    my ( $self ) = @_;

    my $reader = $self->reader;
    my $stream = IO::String->new;

    my $i        = 0;
    my $seen_eof = 0;
    $reader->on_read_object(sub {
        my ( undef, $object ) = @_;

        is_deeply($object, $values[$i++], "Received objects should match");
    });
    $reader->on_end(sub {
       $seen_eof = 1;
    });

    my $string = $stream->string_ref;

    $self->begin_stream($stream);
    $reader->feed($$string);
    foreach my $value (@values) {
        $stream->truncate(0);
        $self->serialize($stream, $value);
        $reader->feed($$string);
    }
    $stream->truncate(0);
    $self->end_stream($stream);
    $reader->feed($$string);
    $reader->feed(undef);
}

sub test_bad_stream_exception : Test {
    my ( $self ) = @_;

    my $reader = $self->reader;
    my $stream = IO::String->new;
    $self->begin_stream($stream);
    $self->serialize($stream, $_) foreach @values;

    throws_ok {
        $reader->feed(${ $stream->string_ref });
        $reader->feed('i should think this is invalid input!');
        $reader->feed(undef);
    } 'SaharaSync::X::BadStream',
        "A bad stream with no callbacks should throw a SaharaSync::X::BadStream exception";
}

sub test_bad_stream_callback : Test(2) {
    my ( $self ) = @_;

    my $reader = $self->reader;
    my $stream = IO::String->new;
    $self->begin_stream($stream);
    $self->serialize($stream, $_) foreach @values;

    $reader->on_parse_error(sub {
        my ( undef, $ex ) = @_;

        isa_ok($ex, 'SaharaSync::X::BadStream');
    });

    lives_ok {
        $reader->feed(${ $stream->string_ref });
        $reader->feed('i should think this is invalid input!');
        $reader->feed(undef);
    } "A bad stream with a callback should succeed";
}

sub test_bad_callbacks : Test {
    my ( $self ) = @_;

    my $reader = $self->reader;
    my $stream = IO::String->new;
    $self->begin_stream($stream);
    $self->serialize($stream, $_) foreach @values;
    $self->end_stream($stream);
    $reader->on_read_object(sub {
        die "Hey!";
    });

    throws_ok {
        $reader->feed(${ $stream->string_ref });
    } qr/Hey/, "Callback exceptions should propagate";
}

sub test_streaming_basic : Test(9) {
    my ( $self ) = @_;

    my $reader = $self->reader;

    my $cond = AnyEvent->condvar;
    my $i    = 0;
    $reader->on_read_object(sub {
        my ( undef, $object ) = @_;
        is_deeply($object, $values[$i++], "Received objects should match");
    });
    $reader->on_end(sub {
        $cond->send;
    });

    my ( $read, $write );

    pipe $read, $write;

    my $read_handle = AnyEvent::Handle->new(
        fh      => $read,
        on_read => sub {
            my ( $h ) = @_;

            my $buf  = $h->rbuf;
            $h->rbuf = '';
            $reader->feed($buf);
        },
        on_eof => sub {
            $reader->feed(undef);
        },
    );

    $write = IO::Handle->new_from_fd($write, 'w');
    $write->autoflush(1);
    $self->begin_stream($write);

    my $j = 0;
    my $timer;
    $timer = AnyEvent->timer(
        interval => 0.25,
        cb       => sub {
            if($j >= @values) {
                $self->end_stream($write);
                undef $timer;
            } else {
                use Data::Dumper::Concise;
                $self->serialize($write, $values[$j++]); 
            }
        },
    );

    $cond->recv;
}

sub test_early_eos : Test {
    my ( $self ) = @_;

    my $reader = $self->reader;
    my $saw_error;

    my $cond = AnyEvent->condvar;
    $reader->on_parse_error(sub {
        $saw_error = 1;
    });
    $reader->on_end(sub {
        $cond->send;
    });

    my ( $read, $write );

    pipe $read, $write;

    my $read_handle = AnyEvent::Handle->new(
        fh      => $read,
        on_read => sub {
            my ( $h ) = @_;

            my $buf  = $h->rbuf;
            $h->rbuf = '';
            $reader->feed($buf);
        },
        on_eof => sub {
            $reader->feed(undef);
        },
    );

    $write = IO::Handle->new_from_fd($write, 'w');
    $write->autoflush(1);
    $self->begin_stream($write);

    my $i = 0;
    my $timer;
    $timer = AnyEvent->timer(
        interval => 0.25,
        cb       => sub {
            if($i >= @values) {
                $write->close;
                undef $timer;
            } else {
                $self->serialize($write, $values[$i++]);
            }
        },
    );

    $cond->recv;

    ok !$saw_error, "No errors should occur on an early end-of-stream";
}

1;
