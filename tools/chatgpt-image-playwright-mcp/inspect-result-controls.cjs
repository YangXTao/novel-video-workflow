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
  const page = context.pages().find(item => item.url().includes('6a991981')) || context.pages()[0];
  const controls = await page.locator('button,a,textarea,[contenteditable="true"],input').evaluateAll(nodes => nodes.map((node, index) => ({
    index,
    tag: node.tagName,
    text: (node.innerText || '').trim().slice(0, 100),
    aria: node.getAttribute('aria-label'),
    title: node.getAttribute('title'),
    testid: node.getAttribute('data-testid'),
    href: node.getAttribute('href'),
    visible: Boolean(node.offsetWidth || node.offsetHeight || node.getClientRects().length),
  })).filter(item => item.visible && (item.text || item.aria || item.title || item.testid)));
  process.stdout.write(JSON.stringify({ url: page.url(), controls: controls.slice(-120) }, null, 2));
  await browser.close();
})().catch(error => {
  process.stderr.write(String(error.stack || error));
  process.exitCode = 1;
});
