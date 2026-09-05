const fs = require('fs');
const path = require('path');
const { createRequire } = require('module');
const store = path.join(__dirname, 'node_modules', '.pnpm');
const packageDir = fs.readdirSync(store).find(name => name.startsWith('playwright@'));
const localRequire = createRequire(path.join(store, packageDir, 'node_modules', 'playwright', 'package.json'));
const { chromium } = localRequire('playwright');

(async () => {
  const browser = await chromium.connectOverCDP('http://127.0.0.1:34192');
  const context = browser.contexts()[0];
  const rows = [];
  for (const page of context.pages()) {
    const body = await page.locator('body').innerText({ timeout: 3000 }).catch(() => '');
    rows.push({
      url: page.url(),
      title: await page.title().catch(() => ''),
      text_tail: body.slice(-500),
      visible_images: await page.locator('img').filter({ visible: true }).count().catch(() => 0),
      visible_edit_image: await page.locator('button[aria-label="编辑图片"]').filter({ visible: true }).count().catch(() => 0),
      visible_stop: await page.locator('button[aria-label*="停止"], button[data-testid="stop-button"]').filter({ visible: true }).count().catch(() => 0),
      images: await page.locator('img:visible').evaluateAll(nodes => nodes.slice(-10).map(node => ({
        alt: node.getAttribute('alt'),
        src: node.getAttribute('src'),
        width: node.naturalWidth,
        height: node.naturalHeight,
      }))).catch(() => []),
    });
  }
  process.stdout.write(JSON.stringify(rows, null, 2));
  await browser.close();
})().catch(error => {
  process.stderr.write(String(error.stack || error));
  process.exitCode = 1;
});
