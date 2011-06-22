use strict;
use warnings;
use parent 'Test::Sahara::Storage';

use File::Temp;
use SaharaSync::Hostd::Plugin::Store::DBIWithFS;
use Test::More;

my $catalog  = $ENV{'TEST_MYDATABASE'};
my $username = $ENV{'TEST_MYUSER'} || '';
my $password = $ENV{'TEST_MYPASS'} || '';
my $dsn;
do {
    no warnings 'uninitialized';
    $dsn = "dbi:mysql:database=$catalog";
    if(my $host = $ENV{'TEST_MYHOST'}) {
        $dsn .= ":host=$host";
    }
    if(my $port = $ENV{'TEST_MYPORT'}) {
        $dsn .= ":port=$port";
    }
};

sub SKIP_CLASS {
    eval {
        require DBD::mysql;
    };
    if($@) {
        return 'You must install DBD::mysql to run this test';
    }
    unless(defined($ENV{'TEST_MYDATABASE'})) {
        return 'You must define TEST_MYDATABASE to run this test';
    }
    return;
}

sub reset_db {
    my ( $self ) = @_;

    my $dbh = DBI->connect($dsn, $username, $password, {
        RaiseError => 1,
        PrintError => 0,
    });
    my @tables = $dbh->tables(undef, $catalog, '%', 'TABLE'); 

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

if(my $reason = __PACKAGE__->SKIP_CLASS) {
    plan skip_all => $reason;
} else {
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
