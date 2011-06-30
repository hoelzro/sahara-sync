package SaharaSync::Hostd::Config;

use Moose;
use MooseX::StrictConstructor;

use Carp qw(croak);
use Config::Any;

use namespace::clean -except => 'meta';

has server => (
    is  => 'ro',
    isa => 'HashRef',
);

has storage => (
    is       => 'ro',
    isa      => 'HashRef',
    required => 1,
);

has log => (
    is       => 'ro',
    isa      => 'ArrayRef',
    required => 1,
);

sub load_from_file {
    my ( $class, $filename ) = @_;

    unless(-r $filename) {
        croak "Unable to read '$filename'";
    }

    my $configs = Config::Any->load_files({
        files   => [ $filename ],
        use_ext => 1,
    });

    if(@$configs) {
        return $class->new((values %{ $configs->[0] })[0]);
    } else {

    }
}

__PACKAGE__->meta->make_immutable;

1;

__END__

# ABSTRACT: Configuration object for the Sahara Sync host daemon.

=head1 SYNOPSIS

  use SaharaSync::Hostd::Config;

  my $config = SaharaSync::Hostd::Config->new(
    storage => {
      type => 'DBIWithFS',
      dsn  => 'dbi:Pg:dbname=sahara',
      root => '/tmp/sahara',
    },
  );

  # or

  my $config = SaharaSync::Hostd::Config->load_from_file($filename)

=head1 DESCRIPTION

SaharaSync::Hostd::Config objects tell a Sahara Sync host daemon instance
how to configure itself and its internal components.

=head1 ATTRIBUTES

=head2 storage

Configuration for the storage plugin; must be a hash reference.  The key
C<type> must be provided; it tells the host daemon which storage plugin to
load.  Every other key-value pair is provided to the storage plugin's
constructor.

=head1 METHODS

=head2 SaharaSync::Hostd::Config->new(%attributes)

Creates a config object.

=head2 SaharaSync::Hostd::Config->load_from_file($filename)

Loads the configuration from a file uses L<Config::Any>.

=cut
