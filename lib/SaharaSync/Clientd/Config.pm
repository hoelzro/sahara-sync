package SaharaSync::Clientd::Config;

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Types -declare => [qw/ContainsType ExpandDir ExpandFile LogConfigs SaharaUri PollInterval/];
use MooseX::Types::Moose qw(ArrayRef HashRef Num Str);
use MooseX::Types::Path::Class qw(Dir File);
use MooseX::Types::Structured;
use MooseX::Types::URI qw(Uri);
use MooseX::StrictConstructor;

use Carp qw(croak);
use File::HomeDir;
use File::Glob qw(bsd_glob GLOB_TILDE GLOB_NOCHECK GLOB_NOSORT);
use URI;

use namespace::clean -except => 'meta';

with 'MooseX::Getopt', 'MooseX::SimpleConfig';

subtype ExpandDir,
    as  Dir;

subtype ExpandFile,
    as  File;

coerce ExpandDir,
    from Str,
    via { Path::Class::Dir->new(bsd_glob($_, GLOB_TILDE | GLOB_NOCHECK | GLOB_NOSORT)) };

coerce ExpandFile,
    from Str,
    via { Path::Class::File->new(bsd_glob($_, GLOB_TILDE | GLOB_NOCHECK | GLOB_NOSORT)) };

subtype ContainsType,
    as HashRef,
    where { exists $_->{'type'} },
    message { "Must contain 'type' key" };

subtype LogConfigs,
    as ArrayRef[ContainsType];

coerce LogConfigs,
    from ContainsType,
    via { [ $_ ] };

subtype SaharaUri,
    as Uri;

coerce SaharaUri,
    from Str,
    via {
        return unless m!^https?://!;
        return URI->new($_);
    };

coerce SaharaUri,
    from HashRef,
    via {
        return unless $_->{'host'};
        $_->{'scheme'} = 'http' unless exists $_->{'scheme'};
        $_->{'port'}   = 5982   unless exists $_->{'port'};

        return unless $_->{'scheme'} =~ m!^https?!;
        return unless $_->{'port'} >= 0;
        return unless $_->{'port'} < 2 ** 16;

        my @keys = grep { $_ ne 'scheme' && $_ ne 'port' && $_ ne 'host' } keys(%$_);
        return if @keys;

        return URI->new(sprintf("%s://%s:%d", @{$_}{qw/scheme host port/}));
    };

subtype PollInterval,
    as Num,
    where { $_ > 0 },
    message { "Poll interval must be greater than zero" };

has home_dir => (
    is      => 'ro',
    isa     => ExpandDir,
    default => sub {
        if(my $dir = $ENV{'XDG_CONFIG_HOME'}) {
            return Path::Class::Dir->new($dir, 'sahara-sync');
        } else {
            return Path::Class::Dir->new(File::HomeDir->my_data, 'Sahara Sync');
        }
    },
    coerce        => 1,
    metaclass     => 'Getopt',
    cmd_flag      => 'homedir',
    documentation => 'The base directory for Sahara Sync client resources',
);

## why do I have a handle to this?
## it's either ->new or ->new_from_file...
has config_file => (
    is      => 'ro',
    isa     => ExpandFile,
    lazy    => 1,
    default => sub {
        my ( $self ) = @_;

        return $self->home_dir->file('config.json');
    },
    coerce      => 1,
    metaclass   => 'Getopt',
    cmd_flag    => 'configfile',
    cmd_aliases => 'c',
);

has upstream => (
    is        => 'ro',
    isa       => SaharaUri,
    required  => 1,
    coerce    => 1,
    metaclass => 'NoGetopt',
);

has sync_dir => (
    is        => 'ro',
    isa       => ExpandDir,
    default   => '~/Sandbox',
    coerce    => 1,
    metaclass => 'NoGetopt',
);

has username => (
    is        => 'ro',
    isa       => 'Str',
    required  => 1,
    metaclass => 'NoGetopt',
);

has password => (
    is        => 'ro',
    isa       => 'Str',
    required  => 1,
    metaclass => 'NoGetopt',
);

has log => (
    is        => 'ro',
    isa       => LogConfigs,
    default   => sub {
        my ( $self ) = @_;

        return [{
            type        => 'File',
            filename    => $self->home_dir->file('sahara.log') . '',
            mode        => 'append',
            binmode     => ':encode(utf8)',
            permissions => 0600,
            newline     => 1,
        }]
    },
    coerce    => 1,
    metaclass => 'NoGetopt',
);

has poll_interval => (
    is        => 'ro',
    isa       => PollInterval,
    default   => 15,
    metaclass => 'NoGetopt',
);

sub new_from_file {
    my ( $class, $filename ) = @_;

    unless(-r $filename) {
        croak "Unable to read '$filename'";
    }

    return $class->new_with_config(configfile => $filename);
}

__PACKAGE__->meta->make_immutable;

1;
