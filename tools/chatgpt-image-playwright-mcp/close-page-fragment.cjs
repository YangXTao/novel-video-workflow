const fs = require('fs');
const path = require('path');
const { createRequire } = require('module');
const fragment = process.argv[2];
if (!fragment) throw new Error('Usage: close-page-fragment.cjs <url-fragment>');
const store = path.join(__dirname, 'node_modules', '.pnpm');
const packageDir = fs.readdirSync(store).find(name => name.startsWith('playwright@'));
const localRequire = createRequire(path.join(store, packageDir, 'node_modules', 'playwright', 'package.json'));
const { chromium } = localRequire('playwright');

(async () => {
  const browser = await chromium.connectOverCDP('http://127.0.0.1:34192');
  const context = browser.contexts()[0];
  const matches = context.pages().filter(page => page.url().includes(fragment));
  for (const page of matches) await page.close();
  process.stdout.write(JSON.stringify({ closed: matches.length, fragment }));
  await browser.close();
})().catch(error => { process.stderr.write(String(error.stack || error)); process.exitCode = 1; });

