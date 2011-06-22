use strict;
use warnings;
use parent 'Test::Sahara::Storage';

use File::Temp;
use SaharaSync::Hostd::Plugin::Store::DBIWithFS;
use Test::More;

my $catalog  = $ENV{'TEST_PGDATABASE'};
my $schema   = 'public';
my $username = $ENV{'TEST_PGUSER'} || '';
my $password = $ENV{'TEST_PGPASS'} || '';
my $host     = $ENV{'TEST_PGHOST'};
my $port     = $ENV{'TEST_PGPORT'};
my $dsn;
do {
    no warnings 'uninitialized';
    $dsn  = "dbi:Pg:dbname=$catalog";
    $dsn .= ":host=$host" if $host;
    $dsn .= ":port=$port" if $port;
};

sub reset_db {
    my ( $self ) = @_;

    my $dbh = DBI->connect($dsn, $username, $password, {
        RaiseError => 1,
        PrintError => 0,
    });
    my @tables = $dbh->tables($catalog, $schema, '%', 'TABLE'); 

    foreach my $table (@tables) {
        $dbh->do("DELETE FROM $table");
    }

    $dbh->do(<<SQL);
INSERT INTO users (username, password)
VALUES
    ('test', 'abc123'),
    ('test2', 'abc123')
SQL

    $dbh->disconnect;
}

sub SKIP_CLASS {
    eval {
        require DBD::Pg;
    };
    if($@) {
        return 'You must install DBD::Pg to run this test';
    }
    unless(defined($ENV{'TEST_PGDATABASE'})) {
        return 'You must define TEST_PGDATABASE to run this test';
    }
    return;
}

sub create_impl : Test(setup) {
    my ( $self ) = @_;

    my %args = $self->arguments;

    $self->{'tempdir'} = File::Temp->newdir;
    $self->reset_db;
    $self->store(SaharaSync::Hostd::Plugin::Store::DBIWithFS->new(
        %args,
        fs_storage_path => $self->{'tempdir'}->dirname,
    ));
}

sub cleanup_impl : Test(teardown) {
    my ( $self ) = @_;
    
    undef $self->{'tempdir'};
}

unless(__PACKAGE__->SKIP_CLASS) {
    plan tests => __PACKAGE__->expected_tests * 2;

    __PACKAGE__->new(
        dsn      => $dsn,
        username => $username,
        password => $password,
    )->runtests;

    __PACKAGE__->new(
        dbh => DBI->connect($dsn, $username, $password),
    )->runtests;
}
