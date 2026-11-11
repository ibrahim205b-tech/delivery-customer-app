# فحص الواجهة بالمتصفح (اختياري)

سكربتات Playwright تشغّل نسخة الويب من تطبيق المستهلك ضد Supabase المحلي (`supabase/local/up.sh`):

- `order_flow.js` — دخول ← الرئيسية ← محل ← إضافة للسلة ← السلة ← تأكيد الطلب ← التتبع، مع لقطات شاشة.
- `live_update.js` — يفتح شاشة تتبع الطلب، يغيّر الحالة بقاعدة البيانات، ويقيس وقت ظهور التحديث بالواجهة (Realtime).

```
cd apps/customer && flutter create --platforms=web . && flutter build web --no-web-resources-cdn \
  --dart-define=SUPABASE_URL=http://localhost:54321 --dart-define=SUPABASE_ANON_KEY=<anon>
python3 -m http.server 8080 -d build/web &
node tools/web_smoke/order_flow.js /tmp/shots
```
السكربتات تفترض حساب تجريبي محلي `07801112233 / demo1234` وبيانات محلات تضيفها أنت محلياً.
