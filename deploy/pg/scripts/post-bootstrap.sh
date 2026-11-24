#!/bin/sh
# Patroni post_bootstrap: runs once, on the first primary after initdb. $1 is a superuser connection URL.
# Patroni itself creates the superuser, replicator and rewind roles. This creates the others.
# Passwords are read inside psql with \getenv, so they never appear on a command line or in output,
# and failed statements are kept out of the server log.
set -eu
psql "$1" -X -q -v ON_ERROR_STOP=1 <<'SQL'
\set VERBOSITY terse
SET log_min_error_statement = panic;
SET log_statement = none;
\getenv monitor_pw PG_MONITOR_PASSWORD
\getenv backup_pw PG_BACKUP_PASSWORD
\getenv app_pw PG_APP_PASSWORD
\getenv app_ro_pw PG_APP_RO_PASSWORD
CREATE ROLE monitor LOGIN PASSWORD :'monitor_pw' IN ROLE pg_monitor;
-- pgBackRest privileges are finalised in L3.
CREATE ROLE backup LOGIN PASSWORD :'backup_pw' IN ROLE pg_read_all_settings, pg_checkpoint;
CREATE ROLE app LOGIN PASSWORD :'app_pw';
CREATE ROLE app_ro LOGIN PASSWORD :'app_ro_pw' IN ROLE pg_read_all_data;
CREATE DATABASE app OWNER app;
SQL
echo "post-bootstrap: roles monitor, backup, app, app_ro and database app created"
