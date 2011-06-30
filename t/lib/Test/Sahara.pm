package Test::Sahara;

use strict;
use warnings;

use Cwd ();
use DBI ();
use File::Spec ();
use File::Temp ();
use HTTP::Request ();
use MIME::Base64 ();
use Plack::Test ();
use SaharaSync::Hostd ();
use Test::More ();

our $VERSION = '0.01';

sub test_host {
    my ( $cb ) = @_;

    my $dsn      = "dbi:SQLite:dbname=:memory:";
    my $dbh      = DBI->connect($dsn, '', '', {
        RaiseError                       => 1,
        PrintError                       => 0,
        sqlite_allow_multiple_statements => 1,
    });

    my $schema = Cwd::realpath(File::Spec->catfile($INC{'Test/Sahara.pm'},
        (File::Spec->updir) x 4, 'schema.sqlite'));

    my $fh;
    open $fh, '<', $schema or die $!;
    $schema = do {
        local $/;
        <$fh>;
    };
    close $fh;

    $dbh->do($schema);
    $dbh->do("INSERT INTO users (username, password) VALUES ('test', 'abc123')");

    my $tempdir = File::Temp->newdir;

    my $app = SaharaSync::Hostd->new(
        storage => {
            type            => 'DBIWithFS',
            dbh             => $dbh,
            fs_storage_path => $tempdir->dirname,
        },
        log     => [{
            type      => 'Null',
            min_level => 'debug',
        }],
    )->to_app;

    return Plack::Test::test_psgi $app, $cb;
}

sub REQUEST {
    my ( $method, $path, @headers ) = @_;

    my $content;
    for(my $i = 0; $i < @headers; $i += 2) {
        if($headers[$i] eq 'Content') {
            $content = $headers[$i + 1];
            splice @headers, $i, 2;
            last;
        }
    }

    my $req = HTTP::Request->new($method, $path);
    for(my $i = 0; $i < @headers; $i += 2) {
        $req->push_header(@headers[$i, $i + 1]);
    }

    if(defined $content) {
        $req->content($content);
    }

    return $req;
}

sub REQUEST_AUTHD {
    my ( $method, $path, @headers ) = @_;

    push @headers, 'Authorization' => 'Basic ' . MIME::Base64::encode_base64('test:abc123');

    return REQUEST($method, $path, @headers);
}

sub lazy_hash (&) {
    my ( $fn ) = @_;

    return sub {
        return {
            ($fn->()),
        }
    };
}

my @methods = qw(GET POST PUT DELETE HEAD OPTIONS);

foreach my $method (@methods) {
    no strict 'refs';

    *{$method} = sub {
        return REQUEST($method, @_);
    };

    *{$method . '_AUTHD'} = sub {
        return REQUEST_AUTHD($method, @_);
    };
}

my @export = (@methods, 'REQUEST', 'lazy_hash');

sub import {
    my ( $class, @args ) = @_;

    my %options = map { $_ => 1 } grep { /^:/ } @args;
    @args       = grep { ! /^:/ } @args;

    my $dest = caller;

    no strict 'refs';

    *{$dest . '::test_host'} = \&test_host;
    foreach my $sym (@Test::More::EXPORT) {
        *{$dest . '::' . $sym} = \&{'Test::More::' . $sym};
    }

    if($options{':methods'}) {
        foreach my $method (@export) {
            *{$dest . '::' . $method}            = \&{$method};
            *{$dest . '::' . $method . '_AUTHD'} = \&{$method . '_AUTHD'};
        }
    }

    Test::More::plan @args if @args;
}

1;

__END__

=head1 NAME

Test::Sahara

=head1 VERSION

0.01

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=head1 AUTHOR

Rob Hoelz, C<< rob at hoelz.ro >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-SaharaSync at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=SaharaSync>. I will
be notified, and then you'll automatically be notified of progress on your bug as I make changes.

=head1 COPYRIGHT & LICENSE

Copyright 2011 Rob Hoelz.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

=cut
