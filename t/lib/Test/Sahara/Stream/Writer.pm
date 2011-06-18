package Test::Sahara::Stream::Writer;

use strict;
use warnings;
use parent 'Test::Class';
use autodie qw(pipe);

use Test::Exception;
use Test::More;

use AnyEvent::Handle;
use IO::Handle;
use IO::String;
use SaharaSync::Stream::Reader;
use SaharaSync::Stream::Writer;

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

sub test_basic : Test(2) {
    my ( $self ) = @_;

    my $stream = IO::String->new;
    my $string = $stream->string_ref;
    my $writer = SaharaSync::Stream::Writer->for_mimetype($self->mime_type,
        writer => $stream,
    );

    $writer->write_objects(@values);
    dies_ok {
        $self->deserialize($$string);
    } "The stream is incomplete before close is called";
    $writer->close;

    my $written = $self->deserialize($$string);

    is_deeply($written, \@values, "Deserialized values should match serialized ones");
}

sub test_destructor : Test(2) {
    my ( $self ) = @_;

    my $stream = IO::String->new;
    my $string = $stream->string_ref;
    my $writer = SaharaSync::Stream::Writer->for_mimetype($self->mime_type,
        writer => $stream,
    );

    $writer->write_objects(@values);
    dies_ok {
        $self->deserialize($$string);
    } "The stream is incomplete before close is called";
    undef $writer;

    my $written = $self->deserialize($$string);

    is_deeply($written, \@values, "Deserialized values should match serialized ones");
}

sub test_closed : Test(4) {
    my ( $self ) = @_;

    my $stream = IO::String->new;
    my $writer = SaharaSync::Stream::Writer->for_mimetype($self->mime_type,
        writer => $stream,
    );

    $writer->close;

    dies_ok {
        $writer->close;
    } "Closing an already-closed writer should fail";

    dies_ok {
        $writer->write_object({});
    } "Writing to a closed stream should fail";

    dies_ok {
        $writer->write_objects({});
    } "Writing to a closed stream should fail";

    lives_ok {
        undef $writer;
    } "Destructing a closed writer should succeed";
}

sub test_streaming : Test(9) {
    my ( $self ) = @_;

    my ( $read, $write );

    pipe $read, $write;

    my $writer = IO::Handle->new_from_fd($write, 'w');
    $writer->autoflush(1);
    $writer    = SaharaSync::Stream::Writer->for_mimetype($self->mime_type,
        writer => $writer,
    );

    my $cond   = AnyEvent->condvar;
    my $reader = SaharaSync::Stream::Reader->for_mimetype($self->mime_type);
    my $i      = 0;
    my $j      = 0;


    $reader->on_read_object(sub {
        my ( undef, $object ) = @_;

        is_deeply $object, $values[$i++];
    });

    $reader->on_end(sub {
        $cond->send;
    });

    my $timer;
    $timer = AnyEvent->timer(
        interval => 0.25,
        cb       => sub {
            $writer->write_object($values[$j++]);
            if($j >= @values) {
                $writer->close;
                undef $timer;
            }
        },
    );

    my $h = AnyEvent::Handle->new(
        fh      => $read,
        on_read => sub {
            my ( $h ) = @_;
            my $buf = $h->rbuf;
            $h->rbuf = '';
            $reader->feed($buf);
        },
        on_eof  => sub {
            $reader->feed(undef);
        },
    );
    $cond->recv;
}

1;
