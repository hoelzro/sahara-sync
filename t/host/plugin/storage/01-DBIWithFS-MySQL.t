use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../../lib";

use File::Temp;
use Test::Sahara::Storage;
use SaharaSync::Hostd::Plugin::Store::DBIWithFS;

eval {
    require DBD::mysql;
};
if($@) {
    diag($@);
    plan skip_all => 'You must install DBD::mysql to run this test';
    exit;
}

my $catalog  = $ENV{'TEST_MYDATABASE'};
my $username = $ENV{'TEST_MYUSER'} || '';
my $password = $ENV{'TEST_MYPASS'} || '';

unless(defined $catalog) {
    plan skip_all => 'You must define TEST_MYDATABASE to run this test';
    exit;
}

my $dsn = "dbi:mysql:database=$catalog";
if(my $host = $ENV{'TEST_MYHOST'}) {
    $dsn .= ":host=$host";
}
if(my $port = $ENV{'TEST_MYPORT'}) {
    $dsn .= ":port=$port";
}

sub reset_db {
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

plan tests => 2;
my $tempdir = File::Temp->newdir;
reset_db;

my $store = SaharaSync::Hostd::Plugin::Store::DBIWithFS->new(
    dsn             => $dsn,
    username        => $username,
    password        => $password,
    fs_storage_path => $tempdir->dirname,
);

run_store_tests $store;

reset_db;
$tempdir = File::Temp->newdir;

$store = SaharaSync::Hostd::Plugin::Store::DBIWithFS->new(
    dbh             => DBI->connect($dsn, $username, $password),
    fs_storage_path => $tempdir->dirname,
);

run_store_tests $store;
