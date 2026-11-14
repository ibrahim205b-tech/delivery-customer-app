// يحوّل رسومات SVG إلى PNG شفافة بدقتين (للتطبيق: 2.0x و 3.0x)
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const dir = __dirname, out = path.resolve(dir, '../../apps/customer/assets/illustrations');
(async () => {
  const b = await chromium.launch();
  for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.svg'))) {
    const svg = fs.readFileSync(path.join(dir, f), 'utf8');
    for (const [scale, sub] of [[0.5, ''], [1, '2.0x'], [1.5, '3.0x']]) {
      const p = await b.newPage({ viewport: { width: 600, height: 460 }, deviceScaleFactor: scale });
      await p.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
      const d = sub ? path.join(out, sub) : out; fs.mkdirSync(d, { recursive: true });
      await p.locator('svg').screenshot({ path: path.join(d, f.replace('.svg', '.png')), omitBackground: true });
      await p.close();
    }
    console.log('png', f);
  }
  await b.close();
})();
