const { chromium } = require('playwright');
const { execSync } = require('child_process');
const S = process.argv[2];
const DB = 'postgres://supabase_admin:localpw@127.0.0.1:54322/postgres';
const sql = (q) => execSync(`psql ${DB} -tAc "${q}"`).toString().trim();
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
  await p.goto('http://localhost:8080/', { waitUntil: 'networkidle' });
  await p.waitForTimeout(3000);
  // الجلسة محفوظة من التشغيل السابق؟ إذا لا، نسجّل دخول
  await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await p.waitForTimeout(800);
  {
    await p.getByRole('textbox', { name: /رقم الهاتف/ }).click(); await p.waitForTimeout(300); await p.keyboard.type('07801112233', { delay: 30 });
    await p.getByRole('textbox', { name: /كلمة المرور/ }).click(); await p.waitForTimeout(300); await p.keyboard.type('demo1234', { delay: 30 });
    await p.getByRole('button', { name: 'دخول' }).click();
    await p.waitForTimeout(6000);
  }
  await p.screenshot({ path: `${S}/live_dbg.png` });
  await p.mouse.click(250, 815);
  await p.waitForTimeout(2500);
  const code = sql("select code from orders where customer_phone='07801112233' order by created_at desc limit 1");
  console.log('order', code);
  await p.locator('flt-semantics').filter({ hasText: code }).last().click();
  await p.waitForTimeout(3500);
  await p.screenshot({ path: `${S}/live_0.png` });
  const t0 = Date.now();
  sql(`update orders set status='accepted' where code='${code}'`);
  // ننتظر ظهور الحالة الجديدة بالواجهة بدون أي تحديث يدوي
  for (let i = 0; i < 40; i++) {
    await p.waitForTimeout(250);
    if (await p.locator('flt-semantics').filter({ hasText: 'المحل وافق على الطلب' }).count()) {
      const txt = await p.locator('flt-semantics').filter({ hasText: 'المحل وافق على الطلب' }).first().textContent();
      if (txt) { console.log('UI updated live after', Date.now() - t0, 'ms'); break; }
    }
  }
  sql(`update orders set status='preparing' where code='${code}'`);
  await p.waitForTimeout(2500);
  await p.screenshot({ path: `${S}/live_1.png` });
  await b.close();
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
