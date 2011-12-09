## no critic (RequireUseStrict)
package Plack::Middleware::Sahara::Auth;

## use critic (RequireUseStrict)
use strict;
use warnings;
use parent 'Plack::Middleware::Auth::Basic';

sub new {
    my $class = shift;

    my %options;

    if(@_ == 1) {
        %options = %{ $_[0] };
    } else {
        %options = @_;
    }

    my $store = delete $options{'store'};
    my $log   = delete $options{'log'};

    my %params = (
        realm           => 'Sahara',
        authenticator   => sub {
            my ( $username, $password, $env ) = @_;

            my $info = $store->load_user_info($username);
            return unless $info;
            if(my $address = $env->{'REMOTE_ADDR'}) {
                $log->info("Logging in as $username ($address)");
            } else {
                $log->info("Logging in as $username");
            }
            return $info->{'password'} eq $password;
        },
        %options,
    );

    return bless Plack::Middleware::Auth::Basic->new(%params), $class;
}

1;

__END__

# ABSTRACT: Simple middleware wrapping Auth::Basic

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
