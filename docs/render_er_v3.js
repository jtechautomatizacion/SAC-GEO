const { chromium } = require('playwright');
(async () => {
  const W = 2010, H = 1400;
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 2 });
  await page.goto('file:///home/claude/v3/docs/ER_GTQC_v3.html');
  await page.waitForTimeout(500);
  await page.screenshot({ path: '/home/claude/v3/docs/ER_GTQC_v3.png', clip: { x: 0, y: 0, width: W, height: H } });
  await page.pdf({ path: '/home/claude/v3/docs/ER_GTQC_v3.pdf', width: W + 'px', height: H + 'px', printBackground: true, pageRanges: '1' });
  await browser.close();
  console.log('rendered');
})();
