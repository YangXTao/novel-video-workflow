const fs = require('fs');
const fsp = fs.promises;
const path = require('path');
const crypto = require('crypto');
const { createRequire } = require('module');

const conversationId = process.argv[2];
const targetPath = process.argv[3];
if (!conversationId || !targetPath) throw new Error('Usage: rescue-download.cjs <conversation-id> <target-path>');
if (fs.existsSync(targetPath)) throw new Error(`Refusing to overwrite existing target: ${targetPath}`);

const store = path.join(__dirname, 'node_modules', '.pnpm');
const packageDir = fs.readdirSync(store).find(name => name.startsWith('playwright@'));
const localRequire = createRequire(path.join(store, packageDir, 'node_modules', 'playwright', 'package.json'));
const { chromium } = localRequire('playwright');

(async () => {
  const browser = await chromium.connectOverCDP('http://127.0.0.1:34192');
  const context = browser.contexts()[0];
  const page = context.pages().find(item => item.url().includes(conversationId));
  if (!page) throw new Error(`Conversation page is not open: ${conversationId}`);
  const save = page.locator('button[aria-label="保存"]').filter({ visible: true }).last();
  if (!await save.count()) throw new Error('Visible image viewer save button not found.');
  const downloadPromise = page.waitForEvent('download', { timeout: 120000 });
  await save.click({ timeout: 10000 });
  const download = await downloadPromise;
  await fsp.mkdir(path.dirname(targetPath), { recursive: true });
  await download.saveAs(targetPath);
  const sha256 = crypto.createHash('sha256').update(await fsp.readFile(targetPath)).digest('hex');
  process.stdout.write(JSON.stringify({ targetPath, sha256, suggestedFilename: download.suggestedFilename() }));
  await browser.close();
})().catch(error => {
  process.stderr.write(String(error.stack || error));
  process.exitCode = 1;
});
