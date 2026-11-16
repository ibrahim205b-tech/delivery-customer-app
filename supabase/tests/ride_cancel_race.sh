#!/usr/bin/env bash
# اختبار التزامن الحقيقي لإلغاء الرحلات: جلسات متوازية تتنافس على نفس الرحلة وعلى عدّاد الزبون.
# البيانات هنا "committed" (ليست داخل transaction) لأن التنافس يحتاج جلسات حقيقية.
# الاستخدام: bash supabase/tests/ride_cancel_race.sh
set -uo pipefail
cd "$(dirname "$0")/.."
PG=${PG_BIN:-/usr/lib/postgresql/16/bin}
DIR=$(mktemp -d /var/tmp/wasel-race-XXXX)
PORT=${PG_PORT:-54351}
chown postgres "$DIR" 2>/dev/null || true
run() { if [ "$(id -u)" = 0 ]; then su postgres -c "$*"; else bash -c "$*"; fi; }
run "$PG/initdb -D $DIR/data -A trust -U postgres >/dev/null"
run "$PG/pg_ctl -D $DIR/data -o '-p $PORT -k $DIR -c wal_level=logical' -l $DIR/log start >/dev/null"
trap 'run "$PG/pg_ctl -D $DIR/data stop -m fast >/dev/null"; rm -rf "$DIR"' EXIT
sleep 2
ADM="psql -h $DIR -p $PORT -U postgres -v ON_ERROR_STOP=1 -q"
$ADM -c "create database race" >/dev/null
for f in tests/supabase_stub.sql migrations/*.sql; do $ADM -d race -f "$f" >"$DIR/mig.log" 2>&1 || { echo "FAIL: migration $f"; tail -3 "$DIR/mig.log"; exit 1; }; done

CUST=f1000001-0000-4000-8000-000000000001
DRV=f1000002-0000-4000-8000-000000000002
AREA=f1000003-0000-4000-8000-000000000003
$ADM -d race -c "
insert into auth.users (id, email, raw_user_meta_data) values
  ('$CUST','cust@race.test','{\"full_name\":\"زبون التزامن\",\"phone\":\"07760000001\"}'),
  ('$DRV','drv@race.test','{\"full_name\":\"سائق التزامن\",\"phone\":\"07760000002\"}');
insert into user_roles (user_id, role) values ('$DRV','driver');
insert into service_areas (id, name, city, center_lat, center_lng, radius_km, is_active)
  values ('$AREA','منطقة التزامن','بغداد',33.3030,44.4350,3,true);
insert into drivers (id, vehicle_type, area_id, is_active, is_available) values ('$DRV','taxi','$AREA',true,true);
insert into rides (customer_id, vehicle, area_id, status, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng, distance_km, fare, customer_name, customer_phone)
select '$CUST', 'taxi', '$AREA', 'requested', 'a', 33.3045, 44.4365, 'b', 33.315, 44.41, 3, 5000, 'زبون', '07760000001'
  from generate_series(1, 12);" >/dev/null || { echo "FAIL: seed"; exit 1; }

# نفس الرحلة من 8 جلسات متوازية: إلغاء واحد فقط ينجح، والباقي يُرفض
SAME=$($ADM -d race -tAc "select id from rides where customer_id = '$CUST' order by created_at limit 1")
pids=()
for i in $(seq 1 8); do
  ( psql -h $DIR -p $PORT -U postgres -qAt -d race -c "select set_config('request.jwt.claim.sub','$CUST',false); set role authenticated; select cancel_ride('$SAME','changed_mind','');" >/dev/null 2>"$DIR/same_$i.err" ) &
  pids+=($!)
done
for p in "${pids[@]}"; do wait $p; done
OK=$(grep -L "ERROR" "$DIR"/same_*.err | wc -l)
DUP=$(grep -l "ride_already_cancelled" "$DIR"/same_*.err | wc -l)
ROWS=$($ADM -d race -tAc "select count(*) from ride_cancellations where ride_id = '$SAME'")
if [ "$OK" = 1 ] && [ "$DUP" = 7 ] && [ "$ROWS" = 1 ]; then
  echo "PASS: 8 إلغاءات متوازية لنفس الرحلة: نجح واحد، و7 رُفضت (ride_already_cancelled)، وسجل واحد فقط"
else
  echo "FAIL: نفس الرحلة: نجح=$OK رُفض_مكرر=$DUP سجلات=$ROWS"; cat "$DIR"/same_*.err 2>/dev/null | head; exit 1
fi

# 10 رحلات مختلفة لنفس الزبون متوازياً. الإلغاء الأول من الاختبار السابق مضاف للعدّ،
# فالإجمالي 11 إلغاءً، وإيقاف واحد فقط (عند العتبة 10 تحديداً).
mapfile -t OTHER < <($ADM -d race -tAc "select id from rides where customer_id = '$CUST' and status = 'requested' order by created_at")
pids=()
for i in $(seq 0 9); do
  ( psql -h $DIR -p $PORT -U postgres -qAt -d race -c "select set_config('request.jwt.claim.sub','$CUST',false); set role authenticated; select cancel_ride('${OTHER[$i]}','changed_mind','');" >/dev/null 2>"$DIR/many_$i.err" ) &
  pids+=($!)
done
for p in "${pids[@]}"; do wait $p; done
MANY_OK=$(grep -L "ERROR" "$DIR"/many_*.err | wc -l)
CNT=$($ADM -d race -tAc "select cancellations_today('$CUST','customer')")
RST=$($ADM -d race -tAc "select count(*) from user_restrictions where user_id = '$CUST' and kind = 'customer_rides'")
if [ "$MANY_OK" = 10 ] && [ "$CNT" = 11 ] && [ "$RST" = 1 ]; then
  echo "PASS: 10 إلغاءات متوازية (+1 سابق = 11): العدّ دقيق، وإيقاف واحد فقط عند العتبة 10"
else
  echo "FAIL: 10 متوازية: نجح=$MANY_OK العدّ=$CNT (متوقع 11) الإيقافات=$RST"; cat "$DIR"/many_*.err 2>/dev/null | head; exit 1
fi
echo "ALL RACE TESTS PASSED"
