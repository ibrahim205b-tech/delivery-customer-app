#!/usr/bin/env bash
# يشغّل اختبارات قاعدة البيانات على PostgreSQL 16 محلي (بدون Supabase).
# الاستخدام: bash supabase/tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."
PG=${PG_BIN:-/usr/lib/postgresql/16/bin}
DIR=$(mktemp -d /var/tmp/wasel-pg-XXXX)
PORT=${PG_PORT:-54331}
chown postgres "$DIR" 2>/dev/null || true
run() { if [ "$(id -u)" = 0 ]; then su postgres -c "$*"; else bash -c "$*"; fi; }
run "$PG/initdb -D $DIR/data -A trust -U postgres >/dev/null"
run "$PG/pg_ctl -D $DIR/data -o '-p $PORT -k $DIR -c wal_level=logical' -l $DIR/log start >/dev/null"
trap 'run "$PG/pg_ctl -D $DIR/data stop -m fast >/dev/null"; rm -rf "$DIR"' EXIT
sleep 2
P="psql -h $DIR -p $PORT -U postgres -v ON_ERROR_STOP=1 -q"
$P -c "create database wasel_test"
for f in tests/supabase_stub.sql migrations/*.sql tests/e2e_flow.sql; do
  $P -d wasel_test -f "$f" 2>&1 | grep -E "PASS|FAIL|ERROR|PASSED" || true
done
