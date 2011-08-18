package SaharaSync::Util;

use strict;
use warnings;

use Carp qw(croak);
use Log::Dispatch;
use namespace::clean;

$Carp::CarpInternal{ (__PACKAGE__) } = 1;

sub install_exception_handler {
    my ( $class, $handler ) = @_;

    $SIG{__DIE__} = sub {
        my ( $message ) = @_;

        my $i = 0;

        my @last_eval_frame;

        while(my @info = caller($i)) {
            my ( $subroutine, $evaltext ) = @info[3, 6];

            if($subroutine eq '(eval)' && !defined($evaltext)) {
                @last_eval_frame = caller($i + 1);
                last;
            }
        } continue {
            $i++;
        }

        if(@last_eval_frame) {
            my $subroutine = $last_eval_frame[3];

            if($subroutine =~ /^(?:AnyEvent::Impl|Plack::Util::run_app)/) {
                local $Carp::CarpLevel = 1; # skip $handler in any backtrace
                                            # that it may request
                $handler->($message);
            }
        }
    };
}

sub load_logger {
    my ( $class, $configs ) = @_;

    my @messages;
    my @loggers;

    foreach my $config (@$configs) {
        my ( $type, $mandatory ) = delete @{$config}{qw/type mandatory/};

        my $pristine_type = $type;
        $type             = 'Log::Dispatch::' . $type unless $type =~ s/^\+//;
        my $path          = $type;
        $path             =~ s!::!/!g;
        $path            .= '.pm';

        eval {
            require $path;
            push @loggers, $type->new(%$config);
        };
        if($@) {
            if($mandatory) {
                croak "Unable to load mandatory logger '$pristine_type': $@";
            } else {
                push @messages, "Unable to load logger '$pristine_type': $@";
            }
        }
    }

    croak "Unable to load any loggers" unless @loggers;

    my $logger = Log::Dispatch->new;
    $logger->add($_)  foreach @loggers;
    $logger->warn($_) foreach @messages;

    return $logger;
}

1;

__END__

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
