const fs = require('fs');
const fsp = fs.promises;
const path = require('path');
const { createRequire } = require('module');
const jobId = process.argv[2];
if (!jobId) throw new Error('Usage: submit-existing-draft.cjs <job-id>');
const ledgerPath = 'D:\\jimeng\\novel-video-browser\\chatgpt-image-worker\\jobs.json';
const store = path.join(__dirname, 'node_modules', '.pnpm');
const packageDir = fs.readdirSync(store).find(name => name.startsWith('playwright@'));
const localRequire = createRequire(path.join(store, packageDir, 'node_modules', 'playwright', 'package.json'));
const { chromium } = localRequire('playwright');
const normalize = value => String(value || '').replace(/\r\n/g, '\n').replace(/\u00a0/g, ' ').replace(/\s+/g, ' ').trim();

(async () => {
  const ledger = JSON.parse(await fsp.readFile(ledgerPath, 'utf8'));
  const job = ledger.jobs[jobId];
  if (!job) throw new Error(`Unknown job: ${jobId}`);
  const browser = await chromium.connectOverCDP('http://127.0.0.1:34192');
  const context = browser.contexts()[0];
  let match = null;
  for (const page of context.pages()) {
    const composers = page.locator('textarea:visible, [contenteditable="true"]:visible');
    for (let i = 0; i < await composers.count(); i++) {
      const composer = composers.nth(i);
      const value = await composer.evaluate(node => 'value' in node ? node.value : node.innerText).catch(() => '');
      if (normalize(value) === normalize(job.prompt)) { match = { page, composer }; break; }
    }
    if (match) break;
  }
  if (!match) throw new Error('No visible composer contains an exact copy of the queued prompt; refusing to submit.');
  await match.composer.focus();
  await match.composer.press('Enter');
  await match.page.waitForURL(url => /chatgpt\.com\/c\//.test(url.toString()), { timeout: 30000 });
  const stableUrl = match.page.url();
  const now = new Date().toISOString();
  job.status = 'generating';
  job.conversation_url = stableUrl;
  job.attempts = Number(job.attempts || 0) + 1;
  job.updated_at = now;
  job.events = Array.isArray(job.events) ? job.events : [];
  job.events.push({ at: now, type: 'recovered_submit', message: `Exact visible draft submitted once without opening a new tab: ${stableUrl}` });
  ledger.updated_at = now;
  const temp = `${ledgerPath}.${process.pid}.tmp`;
  await fsp.writeFile(temp, JSON.stringify(ledger, null, 2), 'utf8');
  await fsp.rename(temp, ledgerPath);
  process.stdout.write(JSON.stringify({ job_id: jobId, submitted: true, conversation_url: stableUrl }));
  await browser.close();
})().catch(error => { process.stderr.write(String(error.stack || error)); process.exitCode = 1; });
