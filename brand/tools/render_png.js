// يحوّل كل ملفات SVG في brand/svg إلى PNG في brand/png باستخدام Chromium (Playwright).
// الاستخدام: node brand/tools/render_png.js
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const svgDir = path.join(root, 'svg');
const pngDir = path.join(root, 'png');
fs.mkdirSync(pngDir, { recursive: true });

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  for (const file of fs.readdirSync(svgDir).filter((f) => f.endsWith('.svg'))) {
    const svg = fs.readFileSync(path.join(svgDir, file), 'utf8');
    const m = svg.match(/viewBox="0 0 ([\d.]+) ([\d.]+)"/);
    const w = Math.round(parseFloat(m[1]));
    const h = Math.round(parseFloat(m[2]));
    // الأيقونات بحجمها (1024)، والشعارات بدقة ×4
    const scale = w >= 1024 ? 1 : 4;
    await page.setViewportSize({ width: w * scale, height: h * scale });
    await page.setContent(
      `<html><body style="margin:0;background:transparent">` +
        svg.replace('<svg ', `<svg style="width:${w * scale}px;height:${h * scale}px;display:block" `) +
        `</body></html>`,
    );
    await page.screenshot({ path: path.join(pngDir, file.replace('.svg', '.png')), omitBackground: true });
    console.log('png', file);
  }
  await browser.close();
})();
