const { chromium } = require('../node_modules/.pnpm/playwright-core@1.63.0-alpha-2026-08-31/node_modules/playwright-core');

(async () => {
  const browser = await chromium.connectOverCDP('http://127.0.0.1:9223');
  const page = browser.contexts().flatMap((context) => context.pages()).find((item) => item.url().includes('/chat/38440489857354754'));
  if (!page) throw new Error('S01 task page is unavailable');
  const done = page.getByText('你的视频生成好了。').last();
  await done.scrollIntoViewIfNeeded();
  await page.waitForTimeout(1000);
  const detail = await done.evaluate((node) => {
    let root = node;
    for (let i = 0; i < 6 && root.parentElement; i += 1) root = root.parentElement;
    return { text: root.innerText, html: root.outerHTML.slice(0, 18000) };
  });
  const videos = await page.locator('video').evaluateAll((items) => items.map((item) => item.currentSrc || item.src));
  process.stdout.write(JSON.stringify({ videos, detail }, null, 2));
  await browser.close();
})().catch((error) => { console.error(error.stack || String(error)); process.exit(1); });
