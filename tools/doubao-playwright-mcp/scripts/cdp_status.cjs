const { chromium } = require('../node_modules/.pnpm/playwright-core@1.63.0-alpha-2026-08-31/node_modules/playwright-core');

(async () => {
  const browser = await chromium.connectOverCDP('http://127.0.0.1:9223');
  const pages = browser.contexts().flatMap((context) => context.pages());
  if (process.argv[2]) {
    const page = pages[0] || await browser.contexts()[0].newPage();
    await page.goto(process.argv[2], { waitUntil: 'domcontentloaded', timeout: 90000 });
    await page.waitForTimeout(5000);
  }
  const result = [];
  for (const page of pages) {
    result.push({
      url: page.url(),
      title: await page.title(),
      videos: await page.locator('video').count(),
      bodyTail: (await page.locator('body').innerText()).slice(-500),
    });
  }
  process.stdout.write(JSON.stringify(result, null, 2));
  await browser.close();
})().catch((error) => {
  console.error(error.stack || String(error));
  process.exit(1);
});
