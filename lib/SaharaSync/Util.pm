package SaharaSync::Util;

use strict;
use warnings;

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
                $handler->($message);
            }
        }
    };
}

1;

__END__

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
