const { chromium } = require('playwright');
(async () => {
  const [,, px, ...pairs] = process.argv;
  const size = parseInt(px);
  const browser = await chromium.launch();
  for (let i = 0; i < pairs.length; i += 3) {
    const svg = pairs[i], png = pairs[i+1], transparent = pairs[i+2] === 't';
    const page = await browser.newPage({ viewport: { width: size, height: size }, deviceScaleFactor: 1 });
    await page.goto('file://' + svg, { waitUntil: 'load', timeout: 240000 });
    await page.screenshot({ path: png, timeout: 240000, omitBackground: transparent });
    await page.close();
  }
  await browser.close();
})();
