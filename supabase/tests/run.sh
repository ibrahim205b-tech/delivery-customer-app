#!/usr/bin/env bash
# يشغّل كل اختبارات قاعدة البيانات على PostgreSQL 16 محلي (بدون Supabase).
# كل ملف اختبار يعمل على قاعدة جديدة مرحّلة من الصفر، حتى لا تتداخل البيانات بين الملفات.
# الاستخدام: bash supabase/tests/run.sh
set -uo pipefail
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
FAILED=0
TESTS="business_activities super_app_foundation activity_requests service_engine_pitch service_area_dispatch map_places captain_ledger driver_realtime ride_cancellation e2e_flow"
for t in $TESTS; do
  db="t_$t"
  $P -c "create database $db" >/dev/null || { echo "FAIL: create db $db"; FAILED=1; continue; }
  ok=1
  for f in tests/supabase_stub.sql migrations/*.sql; do
    $P -d "$db" -f "$f" >"$DIR/mig.log" 2>&1 || { echo "FAIL: migration $f ($t)"; tail -3 "$DIR/mig.log"; ok=0; break; }
  done
  if [ $ok = 1 ]; then
    out=$($P -d "$db" -f "tests/$t.sql" 2>&1); code=$?
    echo "$out" | grep -E "PASS|FAIL|ERROR" | sed 's/^psql:[^ ]* NOTICE:  //' 
    if [ $code -ne 0 ] || echo "$out" | grep -q "ERROR:"; then ok=0; fi
  fi
  if [ $ok = 1 ]; then echo "== $t: OK"; else echo "== $t: FAILED"; FAILED=1; fi
done
# اختبار التزامن (جلسات متوازية حقيقية)
if bash tests/ride_cancel_race.sh; then echo "race: OK"; else echo "race: FAILED"; FAILED=1; fi
if [ $FAILED = 0 ]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; exit 1; fi
