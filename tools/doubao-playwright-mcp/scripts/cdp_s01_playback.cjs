const { chromium } = require('../node_modules/.pnpm/playwright-core@1.63.0-alpha-2026-08-31/node_modules/playwright-core');
const fs = require('fs');
const path = require('path');

(async () => {
  const browser = await chromium.connectOverCDP('http://127.0.0.1:9223');
  const page = browser.contexts().flatMap((context) => context.pages()).find((item) => item.url().includes('/chat/38440489857354754'));
  if (!page) throw new Error('S01 task page is unavailable');
  const done = page.getByText('你的视频生成好了。').last();
  await done.scrollIntoViewIfNeeded();
  const card = done.locator('xpath=following::div[contains(@class,"block-video")][1]');
  await card.click({ position: { x: 245, y: 138 } });
  await page.waitForTimeout(1500);
  const videos = await page.locator('video').evaluateAll((items) => items.map((item) => item.currentSrc || item.src));
  let download = null;
  if (process.argv.includes('--download')) {
    await card.hover();
    const control = card.locator('.video-hover-button-group-q8qlu7 .action-nxGadz');
    if (!await control.count()) throw new Error('S01 download control is unavailable');
    try {
      const pending = page.waitForEvent('download', { timeout: 8000 });
      await control.click();
      const item = await pending;
      // Keep the browser-delivered original as a clearly labelled QA candidate.
      // It is not treated as watermark-free until the visual check completes.
      const outputDir = 'D:\\jimeng\\我的嫁妆，谁也别想拿去飞升\\第四十三章\\镜头';
      fs.mkdirSync(outputDir, { recursive: true });
      const outputPath = path.join(outputDir, '43-S01-候选01-待水印核验.mp4');
      await item.saveAs(outputPath);
      download = { event: true, suggestedFilename: item.suggestedFilename(), savedPath: outputPath };
    } catch {
      download = { event: false, note: 'No standard Playwright download event; check extension-managed downloads.' };
    }
    await page.waitForTimeout(1000);
  }
  const extension = await page.locator('#watermark-free-media-panel').evaluateAll((items) => items.map((item) => ({ text: item.innerText, html: item.outerHTML.slice(0, 4000) })));
  process.stdout.write(JSON.stringify({ videos, download, extension }, null, 2));
  await browser.close();
})().catch((error) => { console.error(error.stack || String(error)); process.exit(1); });
