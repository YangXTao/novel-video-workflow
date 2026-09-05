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
  const closed = [];
  for (const page of context.pages()) {
    if (/^https:\/\/chatgpt\.com\/images\/?(?:\?.*)?$/.test(page.url())) {
      closed.push(page.url());
      await page.close();
    }
  }
  process.stdout.write(JSON.stringify({ closed: closed.length, remaining: context.pages().map(page => page.url()) }));
  await browser.close();
})().catch(error => {
  process.stderr.write(String(error.stack || error));
  process.exitCode = 1;
});
