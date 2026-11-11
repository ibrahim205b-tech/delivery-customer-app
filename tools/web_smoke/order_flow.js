const { chromium } = require('playwright');
const S = process.argv[2];
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, locale: 'ar-IQ' });
  p.on('console', m => { if (m.type() === 'error') console.log('console:', m.text().slice(0, 160)); });
  const shot = async (n) => { await p.waitForTimeout(1800); await p.screenshot({ path: `${S}/${n}.png` }); console.log('shot', n); };
  const tap = async (re) => { const l = p.locator('flt-semantics').filter({ hasText: re }).last(); if (await l.count()) { await l.click(); return true; } const a = p.locator(`flt-semantics[aria-label]`).filter({ has: p.locator('*') }); return false; };
  const tapLabel = async (txt) => { const l = p.locator(`flt-semantics[aria-label*="${txt}"]`).first(); await l.click(); };
  await p.goto('http://localhost:8080/', { waitUntil: 'networkidle' });
  await p.waitForTimeout(3500);
  await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await p.waitForTimeout(800);
  const phone = p.getByRole('textbox', { name: /رقم الهاتف/ });
  await phone.click(); await p.waitForTimeout(400); await p.keyboard.type('07801112233', { delay: 30 });
  const pass = p.getByRole('textbox', { name: /كلمة المرور/ });
  await pass.click(); await p.waitForTimeout(400); await p.keyboard.type('demo1234', { delay: 30 });
  await p.getByRole('button', { name: 'دخول' }).click();
  await p.waitForTimeout(7000);
  await shot('s2_home');
  await p.mouse.move(195, 500); await p.mouse.wheel(0, 650); await shot('s3_home_scroll');
  await p.mouse.wheel(0, 700); await shot('s4_home_scroll2');
  // فتح محل
  try { await tapLabel('مشويات الرافدين'); await shot('s5_merchant'); } catch (e) { console.log('merchant tap failed', e.message.slice(0, 100)); }
  try { await p.getByRole('button', { name: 'أضف للسلة' }).first().click(); await p.waitForTimeout(800); await p.getByRole('button', { name: 'زيد' }).first().click(); await shot('s6_merchant_cart'); } catch (e) { console.log('add failed', e.message.slice(0, 100)); }
  try { await p.getByRole('button', { name: 'عرض السلة' }).click(); await shot('s7_cart'); } catch (e) { console.log('cart failed', e.message.slice(0, 100)); }
  try { await p.getByRole('button', { name: /تأكيد الطلب/ }).click(); await p.waitForTimeout(5000); await shot('s8_tracking'); await p.mouse.move(195, 600); await p.mouse.wheel(0, 600); await shot('s9_tracking_scroll'); } catch (e) { console.log('place failed', e.message.slice(0, 100)); }
  await b.close();
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
