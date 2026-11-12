const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const scale = Number(process.argv[3] || 1);
  const p = await b.newPage({ viewport: { width: 1080, height: 1350 }, deviceScaleFactor: scale });
  await p.goto('file://' + process.cwd() + '/poster.html');
  await p.waitForSelector('body[data-ready="1"]'); await p.waitForTimeout(300);
  await p.screenshot({ path: process.argv[2] });
  await b.close();
})();
