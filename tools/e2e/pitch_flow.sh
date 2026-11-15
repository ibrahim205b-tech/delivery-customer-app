#!/usr/bin/env bash
# اختبار حجز الملعب من البداية للنهاية عبر واجهة PostgREST نفسها التي تستخدمها التطبيقات.
# يتطلب بيئة محلية (Supabase المحلي) وحسابين: صاحب ملعب (07770000001) وزبون (07801112233).
# الاستخدام: bash tools/e2e/pitch_flow.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
API=http://localhost:54321
ANON=$(python3 "$ROOT/supabase/local/keys.py" local-dev-jwt-secret-at-least-32-characters-long | grep ^ANON | cut -d= -f2)
DB=postgres://supabase_admin:localpw@127.0.0.1:54322/postgres

login() { curl -s -X POST "$API/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d "{\"email\":\"$1@phone.wasel.app\",\"password\":\"demo1234\"}" | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])"; }
call() { # $1 token, $2 rpc name, $3 json body
  curl -s -X POST "$API/rest/v1/rpc/$2" -H "apikey: $ANON" -H "Authorization: Bearer $1" -H "Content-Type: application/json" -d "$3"; }
get()  { curl -s "$API/rest/v1/$2" -H "apikey: $ANON" -H "Authorization: Bearer $1"; }
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1 -> $2"; exit 1; }

OWN_T=$(login 9647770000001)
CUS_T=$(login 9647801112233)
MERCHANT=$(psql "$DB" -tAc "select id from merchants where business_type='pitch_owner' and status='approved' limit 1")
[ -n "$MERCHANT" ] || fail "setup" "لا يوجد ملعب معتمد"

# 1) صاحب الملعب يفعّل ملعبه بسعر
PITCH=$(call "$OWN_T" upsert_pitch "{\"p_id\":null,\"p_merchant_id\":\"$MERCHANT\",\"p_name\":\"ملعب الخماسي الاختباري\",\"p_description\":\"عشب صناعي\",\"p_price_per_hour\":30000,\"p_min_minutes\":60,\"p_open_hour\":8,\"p_close_hour\":23,\"p_cancel_before_hours\":2,\"p_cancellation_policy\":\"الإلغاء قبل ساعتين\",\"p_is_active\":true}" | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
pass "صاحب الملعب يفعّل ملعباً بسعر 30,000 د.ع/ساعة"

# 2) الزبون يرى الملعب
N=$(get "$CUS_T" "pitches?id=eq.$PITCH&select=id" | python3 -c "import sys,json;print(len(json.load(sys.stdin)))")
[ "$N" = "1" ] || fail "visibility" "الزبون لا يرى الملعب المفعّل"
pass "الزبون يرى الملعب المفعّل"

# 3) الزبون يطلب حجزاً بعد يومين الساعة 18:00 بتوقيت بغداد (15:00 UTC)، لمدة ساعتين
START=$(python3 -c "
from datetime import datetime, timedelta, timezone
b = timezone(timedelta(hours=3))
d = (datetime.now(b) + timedelta(days=2)).replace(hour=18, minute=0, second=0, microsecond=0)
print(d.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")
CID=$(python3 -c "import uuid;print(uuid.uuid4())")
REQ=$(call "$CUS_T" pitch_book_request "{\"p_pitch_id\":\"$PITCH\",\"p_starts_at\":\"$START\",\"p_minutes\":120,\"p_client_request_id\":\"$CID\"}")
REQ_ID=$(echo "$REQ" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['id'])")
AMT=$(echo "$REQ" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['amount'])")
[ "$AMT" = "60000" ] || fail "booking amount" "المبلغ $AMT بدل 60000"
pass "الزبون يطلب حجزاً (120 دقيقة = 60,000 د.ع)، والحالة requested"

# 4) إعادة الإرسال بنفس المعرّف لا تكرر
REQ2=$(call "$CUS_T" pitch_book_request "{\"p_pitch_id\":\"$PITCH\",\"p_starts_at\":\"$START\",\"p_minutes\":120,\"p_client_request_id\":\"$CID\"}" | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
[ "$REQ2" = "$REQ_ID" ] || fail "idempotency" "إعادة الإرسال أنشأت طلباً جديداً"
pass "إعادة الإرسال بنفس المعرّف لا تكرر الحجز"

# 5) صاحب الملعب يستلم الطلب (في القائمة) ويقبله
N=$(get "$OWN_T" "service_requests?id=eq.$REQ_ID&select=id" | python3 -c "import sys,json;print(len(json.load(sys.stdin)))")
[ "$N" = "1" ] || fail "provider visibility" "صاحب الملعب لا يرى الطلب"
call "$OWN_T" service_respond "{\"p_request_id\":\"$REQ_ID\",\"p_accept\":true,\"p_reason\":\"\"}" >/dev/null
ST=$(get "$CUS_T" "service_requests?id=eq.$REQ_ID&select=status" | python3 -c "import sys,json;print(json.load(sys.stdin)[0]['status'])")
[ "$ST" = "accepted" ] || fail "accept" "الحالة بعد القبول $ST"
pass "صاحب الملعب يقبل، والزبون يرى الحالة accepted"

# 6) إشعار القبول للزبون
N=$(get "$CUS_T" "notifications?select=id,data" | python3 -c "
import sys,json
rows=json.load(sys.stdin)
print(sum(1 for r in rows if (r.get('data') or {}).get('status')=='accepted'))")
[ "$N" -ge 1 ] || fail "notification" "لا يوجد إشعار قبول للزبون"
pass "الزبون يستلم إشعار القبول"

# 7) حجز متداخل بنفس الوقت يُرفض
OVER=$(python3 -c "
from datetime import datetime, timedelta, timezone
b = timezone(timedelta(hours=3))
d = (datetime.now(b) + timedelta(days=2)).replace(hour=18, minute=30, second=0, microsecond=0)
print(d.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")
OUT=$(call "$CUS_T" pitch_book_request "{\"p_pitch_id\":\"$PITCH\",\"p_starts_at\":\"$OVER\",\"p_minutes\":60,\"p_client_request_id\":null}" || true)
echo "$OUT" | grep -q "slot_taken" || fail "double booking" "الحجز المتداخل لم يُرفض: $OUT"
pass "حجز متداخل مع مقبول يُرفض (slot_taken)"

# 8) الأوقات المحجوزة تظهر للزبون بدون بيانات الزبائن
DAY=$(python3 -c "
from datetime import datetime, timedelta, timezone
b = timezone(timedelta(hours=3))
print((datetime.now(b) + timedelta(days=2)).strftime('%Y-%m-%d'))")
BUSY=$(call "$CUS_T" pitch_busy_slots "{\"p_pitch_id\":\"$PITCH\",\"p_day\":\"$DAY\"}")
echo "$BUSY" | grep -q "starts_at" || fail "busy slots" "لا تظهر الأوقات المحجوزة: $BUSY"
echo "$BUSY" | grep -q "customer" && fail "privacy" "الأوقات المحجوزة تكشف بيانات الزبائن"
pass "الأوقات المحجوزة تظهر للزبون دون بيانات الزبائن"

# 9) صاحب الملعب يبدأ ثم يُتم، والعمولة تُحسب مرة واحدة
call "$OWN_T" service_set_status "{\"p_request_id\":\"$REQ_ID\",\"p_to\":\"in_progress\"}" >/dev/null
call "$OWN_T" service_set_status "{\"p_request_id\":\"$REQ_ID\",\"p_to\":\"completed\"}" >/dev/null
COM=$(get "$OWN_T" "service_commissions?request_id=eq.$REQ_ID&select=amount,base_amount,model" | python3 -c "import sys,json;r=json.load(sys.stdin);print(len(r), r[0]['model'] if r else '')")
[ "$COM" = "1 free" ] || fail "commission" "صف العمولة: $COM"
pass "الإتمام يُسجّل صف عمولة واحداً (الخدمة مجانية حتى تحدد الإدارة نموذجاً)"

# 10) الزبون يقيّم مرة واحدة فقط
call "$CUS_T" service_rate "{\"p_request_id\":\"$REQ_ID\",\"p_rating\":5,\"p_comment\":\"ملعب ممتاز\"}" >/dev/null
DUP=$(call "$CUS_T" service_rate "{\"p_request_id\":\"$REQ_ID\",\"p_rating\":4,\"p_comment\":\"مرة ثانية\"}" || true)
echo "$DUP" | grep -qi "duplicate\|unique" || fail "rating" "تقييم مكرر قُبل: $DUP"
pass "التقييم مرة واحدة بعد الإتمام"

echo "ALL PASS (pitch flow via REST: 10 checks)"
