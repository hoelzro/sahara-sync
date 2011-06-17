package SaharaSync::Stream::Reader::JSON;

use Moose;

with 'SaharaSync::Stream::Reader';

use JSON::Streaming::Reader;
use SaharaSync::X::BadStream;

use namespace::clean -except => 'meta';

has json_reader => (
    is       => 'ro',
    init_arg => undef,
    builder  => 'build_json_reader',
);

sub build_json_reader {
    my ( $self ) = @_;

    my @object_stack;
    my $last_property;

    my $end_object = sub {
        if(@object_stack == 2) {
            $self->on_read_object->($self, $object_stack[$#object_stack]);
        }
        if(@object_stack == 1) {
            $self->on_end->($self);
        }
        pop @object_stack;
    };

    my $add_value = sub {
        my ( $value ) = @_;

        if(@object_stack) {
            if(@object_stack > 1) {
                if(defined $last_property) {
                    $object_stack[$#object_stack]->{$last_property} = $value;
                } else {
                    push @{ $object_stack[$#object_stack] }, $value;
                }
            } else {
                $self->on_read_object->($self, $value);
            }
        } else {
            $self->on_parse_error->($self, "non-object at top level");
        }
    };

    return JSON::Streaming::Reader->event_based(
        error => sub {
            my ( $err ) = @_;

            $self->on_parse_error->($self,
                SaharaSync::X::BadStream->new(message =>$err));
        },
        eof => sub {
            $self->on_end->($self);
        },

        start_object => sub {
            push @object_stack, {};
        },
        end_object => $end_object,
        start_array => sub {
            push @object_stack, [];
        },
        end_array => $end_object,

        start_property => sub {
            my ( $key ) = @_;
            $last_property = $key;
        },
        end_property => sub {
            undef $last_property;
        },

        add_number  => $add_value,
        add_string  => $add_value,
        add_boolean => $add_value,
        add_null    => $add_value,
    );
}

sub feed {
    my ( $self, $buffer ) = @_;

    if(defined $buffer) {
        $self->json_reader->feed_buffer(\$buffer);
    } else {
        $self->json_reader->signal_eof;
    }
}

__PACKAGE__->meta->make_immutable;

1;
