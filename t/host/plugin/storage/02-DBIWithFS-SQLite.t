use strict;
use warnings;
use autodie qw(open);
use parent 'Test::Sahara::Storage';

use Cwd qw(realpath);
use FindBin;
use File::Spec;
use File::Temp;
use SaharaSync::Hostd::Plugin::Store::DBIWithFS;
use Test::More;

my $tempfile = File::Temp->new;
unlink $tempfile->filename;
my $schema   = realpath(File::Spec->catfile($FindBin::Bin,
    (File::Spec->updir) x 4, 'schema.sqlite'));

my $fh;
open $fh, '<', $schema;
$schema = do {
    local $/;
    <$fh>;
};
close $fh;

my $dsn = "dbi:SQLite:dbname=" . $tempfile->filename;

sub SKIP_CLASS {
    eval {
        require DBD::SQLite;
    };
    if($@) {
        return 'You must install DBD::SQLite to run this test';
    }
}

sub reset_db {
    my ( $self ) = @_;

    my $first_run = !(-e $tempfile->filename);

    my $dbh = DBI->connect($dsn, '', '', {
        RaiseError                       => 1,
        PrintError                       => 0,
        ($first_run ? (sqlite_allow_multiple_statements => 1) : ()),
    });
    $dbh->begin_work;
    if($first_run) {
        $dbh->do($schema);
    } else {
        my @tables = $dbh->tables(undef, undef, '%', 'TABLE'); 

        $dbh->do("DELETE FROM $_") foreach @tables;
    }

    $dbh->do(<<SQL);
INSERT INTO users (username, password) VALUES ('test', 'abc123')
SQL

    $dbh->do(<<SQL);
INSERT INTO users (username, password) VALUES ('test2', 'abc123')
SQL
    $dbh->commit;

    $dbh->disconnect;
}

sub create_impl : Test(setup) {
    my ( $self ) = @_;

    my %args = $self->arguments;

    $self->{'tempdir'} = File::Temp->newdir;
    $self->reset_db;
    $self->store(SaharaSync::Hostd::Plugin::Store::DBIWithFS->new(
        %args,
        storage_path => $self->{'tempdir'}->dirname,
    ));
}

sub cleanup_impl : Test(teardown) {
    my ( $self ) = @_;
    
    undef $self->{'tempdir'};
}

if(my $reason = __PACKAGE__->SKIP_CLASS) {
    plan skip_all => $reason;
} else {
    plan tests => __PACKAGE__->expected_tests * 2;

    __PACKAGE__->new(
        dsn      => $dsn,
        username => '',
        password => '',
    )->runtests;

    __PACKAGE__->new(
        dbh => DBI->connect($dsn, '', ''),
    )->runtests;
}
