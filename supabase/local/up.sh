#!/usr/bin/env bash
# يشغّل Supabase محلياً (Auth + REST + Realtime + Storage) على PostgreSQL محلي، للاختبار فقط.
# المتطلبات: PostgreSQL 16 + الإضافة wal2json (لـ Realtime) + Docker. الاستخدام: bash supabase/local/up.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PG=${PG_BIN:-/usr/lib/postgresql/16/bin}
DATA=${SB_DATA:-/var/tmp/wasel-supabase}
PORT=54322
JWT_SECRET=local-dev-jwt-secret-at-least-32-characters-long
eval "$(python3 "$HERE/keys.py" "$JWT_SECRET")"
run() { if [ "$(id -u)" = 0 ]; then su postgres -c "$*"; else bash -c "$*"; fi; }

if [ ! -d "$DATA/data" ]; then
  mkdir -p "$DATA" && chown postgres "$DATA" 2>/dev/null || true
  run "$PG/initdb -D $DATA/data -A trust -U postgres >/dev/null"
  run "$PG/pg_ctl -D $DATA/data -o '-p $PORT -k $DATA -c listen_addresses=127.0.0.1 -c wal_level=logical -c max_replication_slots=10 -c max_wal_senders=10 -c output_plugin_libraries=wal2json,pgoutput' -l $DATA/log start >/dev/null"
  sleep 2
  psql -h 127.0.0.1 -p $PORT -U postgres -q -v ON_ERROR_STOP=1 -f "$HERE/roles.sql"
else
  run "$PG/pg_ctl -D $DATA/data -o '-p $PORT -k $DATA -c listen_addresses=127.0.0.1 -c wal_level=logical -c max_replication_slots=10 -c max_wal_senders=10 -c output_plugin_libraries=wal2json,pgoutput' -l $DATA/log start >/dev/null" || true
  sleep 2
fi
DB=postgres://supabase_admin:localpw@127.0.0.1:$PORT/postgres

docker rm -f wasel-auth wasel-rest wasel-realtime wasel-storage wasel-gw >/dev/null 2>&1 || true

docker run -d --name wasel-auth --network host \
  -e GOTRUE_API_HOST=127.0.0.1 -e GOTRUE_API_PORT=9999 -e API_EXTERNAL_URL=http://localhost:54321/auth/v1 \
  -e GOTRUE_DB_DRIVER=postgres -e GOTRUE_DB_DATABASE_URL="postgres://supabase_auth_admin:localpw@127.0.0.1:$PORT/postgres" \
  -e GOTRUE_SITE_URL=http://localhost:8080 -e GOTRUE_URI_ALLOW_LIST='*' -e GOTRUE_DISABLE_SIGNUP=false \
  -e GOTRUE_JWT_SECRET=$JWT_SECRET -e GOTRUE_JWT_EXP=3600 -e GOTRUE_JWT_AUD=authenticated \
  -e GOTRUE_JWT_DEFAULT_GROUP_NAME=authenticated -e GOTRUE_JWT_ADMIN_ROLES=service_role \
  -e GOTRUE_EXTERNAL_EMAIL_ENABLED=true -e GOTRUE_MAILER_AUTOCONFIRM=true -e GOTRUE_EXTERNAL_PHONE_ENABLED=false \
  supabase/gotrue:v2.170.0 >/dev/null

for i in $(seq 1 30); do curl -sf http://127.0.0.1:9999/health >/dev/null && break; sleep 1; done

docker run -d --name wasel-storage --network host \
  -e ANON_KEY=$ANON_KEY -e SERVICE_KEY=$SERVICE_KEY -e AUTH_JWT_SECRET=$JWT_SECRET -e PGRST_JWT_SECRET=$JWT_SECRET \
  -e POSTGREST_URL=http://127.0.0.1:3000 -e DATABASE_URL="postgres://supabase_storage_admin:localpw@127.0.0.1:$PORT/postgres" \
  -e FILE_SIZE_LIMIT=10485760 -e STORAGE_BACKEND=file -e FILE_STORAGE_BACKEND_PATH=/tmp/storage \
  -e TENANT_ID=stub -e REGION=local -e GLOBAL_S3_BUCKET=stub -e SERVER_PORT=5000 -e SERVER_HOST=127.0.0.1 \
  -e ENABLE_IMAGE_TRANSFORMATION=false \
  supabase/storage-api:v1.19.3 >/dev/null

for i in $(seq 1 90); do curl -sf http://127.0.0.1:5000/status >/dev/null && break; sleep 1; done
curl -sf http://127.0.0.1:5000/status >/dev/null || { echo "storage failed"; docker logs wasel-storage | tail -5; exit 1; }

# صلاحيات جداول Storage (موجودة افتراضياً بصورة supabase/postgres)
psql "$DB" -q -c "grant all on all tables in schema storage to anon, authenticated, service_role; grant usage on all sequences in schema storage to anon, authenticated, service_role;"

# مخطط واصل
if ! psql "$DB" -tAc "select 1 from pg_tables where tablename='merchants'" | grep -q 1; then
  for f in "$HERE"/../migrations/*.sql; do
    psql "$DB" -q -v ON_ERROR_STOP=1 -f "$f" 2>&1 | grep -vE "^$|NOTICE" || true
  done
fi
psql "$DB" -q -c "notify pgrst, 'reload schema'" >/dev/null

docker run -d --name wasel-rest --network host \
  -e PGRST_DB_URI="postgres://authenticator:localpw@127.0.0.1:$PORT/postgres" -e PGRST_DB_SCHEMAS=public,storage \
  -e PGRST_DB_ANON_ROLE=anon -e PGRST_JWT_SECRET=$JWT_SECRET -e PGRST_DB_USE_LEGACY_GUCS=false \
  -e PGRST_SERVER_PORT=3000 -e PGRST_SERVER_HOST=127.0.0.1 \
  postgrest/postgrest:v12.2.3 >/dev/null

docker run -d --name wasel-realtime --network host \
  -v "$HERE/realtime-runtime.exs:/app/releases/2.34.47/runtime.exs:ro" -e DB_IP_VERSION=ipv4 \
  -e PORT=4000 -e DB_HOST=127.0.0.1 -e DB_PORT=$PORT -e DB_USER=supabase_admin -e DB_PASSWORD=localpw -e DB_NAME=postgres \
  -e DB_AFTER_CONNECT_QUERY='SET search_path TO _realtime' -e DB_ENC_KEY=supabaserealtime \
  -e API_JWT_SECRET=$JWT_SECRET -e SECRET_KEY_BASE=UpNVntn3cDxHJpq99YMc1T1AQgQpc8kfYTuRgBiYa15BLrx8etQoXz3gZv1/u2oq \
  -e ERL_AFLAGS="-proto_dist inet_tcp" -e DNS_NODES="''" -e RLIMIT_NOFILE=10000 -e APP_NAME=realtime \
  -e SEED_SELF_HOST=true -e RUN_JANITOR=true \
  supabase/realtime:v2.34.47 >/dev/null

docker run -d --name wasel-gw --network host -v "$HERE/nginx.conf:/etc/nginx/nginx.conf:ro" nginx:1.27-alpine >/dev/null

sleep 6
echo "SUPABASE_URL=http://localhost:54321"
echo "SUPABASE_ANON_KEY=$ANON_KEY"
echo "SUPABASE_SERVICE_KEY=$SERVICE_KEY"
echo "DB_URL=$DB"
