const { chromium } = require('../node_modules/.pnpm/playwright-core@1.63.0-alpha-2026-08-31/node_modules/playwright-core');

(async () => {
  const context = await chromium.launchPersistentContext('D:\\jimeng\\novel-video-browser\\doubao-profile', {
    executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    headless: false,
    args: ['--mute-audio'],
    viewport: { width: 1440, height: 650 },
  });
  const page = context.pages()[0] || await context.newPage();
  await page.goto('https://www.doubao.com/chat/38440489857354754', { waitUntil: 'domcontentloaded', timeout: 90000 });
  await page.waitForTimeout(3000);
  process.stdout.write(JSON.stringify({ title: await page.title(), url: page.url(), loginText: await page.locator('body').innerText().then(t => t.slice(0, 300)) }, null, 2));
  await context.close();
})().catch(error => { console.error(error.stack || String(error)); process.exit(1); });
