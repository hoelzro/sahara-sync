#!/bin/bash

# This script assumes you have a MySQL instance and PostgreSQL instance
# running on the default ports and sockets on localhost.  It also assumes
# your MySQL instance has a root user with no password, and your default
# PostgreSQL user has no password as well.

if [[ "$0" == 'bash' ]]; then
    echo "Usage: . $0"
fi

export TEST_PGDATABASE=sahara-test
export TEST_MYHOST=127.0.0.1
export TEST_MYUSER=root
export TEST_MYDATABASE=sahara

dropdb $TEST_PGDATABASE
createdb $TEST_PGDATABASE
dropdb sahara
createdb sahara

psql -f schema.psql sahara
psql -f schema.psql $TEST_PGDATABASE

mysql -h $TEST_MYHOST -u $TEST_MYUSER <<SQL
drop database if exists $TEST_MYDATABASE;
create database $TEST_MYDATABASE;
SQL
mysql -h $TEST_MYHOST -u $TEST_MYUSER $TEST_MYDATABASE < schema.mysql
