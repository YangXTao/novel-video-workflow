/*
 * Persistent, local-only ChatGPT image worker.
 * It intentionally never reads browser storage.  Its durable job ledger is
 * independent of the MCP/client transport, so a Codex restart cannot erase a
 * submitted generation or cause a duplicate submission.
 */
const http = require('http');
const fs = require('fs');
const fsp = fs.promises;
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');
const { createRequire } = require('module');

const ROOT = __dirname;
const runtimeNode = 'C:\\Users\\Y\\.cache\\codex-runtimes\\codex-primary-runtime\\dependencies\\node\\bin\\node.exe';
const chromePath = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const profilePath = 'D:\\jimeng\\novel-video-browser\\chatgpt-image-profile';
const runtimeDir = 'D:\\jimeng\\novel-video-browser\\chatgpt-image-worker';
const ledgerPath = path.join(runtimeDir, 'jobs.json');
const logPath = path.join(runtimeDir, 'worker.log');
const port = 34191;
const cdpPort = 34192;
// pnpm keeps Playwright under its virtual store instead of exposing a root
// symlink. Resolve it from the installed store so this service has no second
// dependency installation or network requirement.
const pnpmStore = path.join(ROOT, 'node_modules', '.pnpm');
const playwrightStore = fs.readdirSync(pnpmStore).find(name => name.startsWith('playwright@'));
if (!playwrightStore) throw new Error('The existing @playwright/mcp Playwright runtime is missing.');
const playwrightRequire = createRequire(path.join(pnpmStore, playwrightStore, 'node_modules', 'playwright', 'package.json'));
const { chromium } = playwrightRequire('playwright');

let browser;
let context;
let activeRun = false;
const runQueue = [];

const iso = () => new Date().toISOString();
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
function sha256(value) { return crypto.createHash('sha256').update(value, 'utf8').digest('hex'); }
function normalizeText(value) { return String(value || '').replace(/\r\n/g, '\n'); }
function normalizeForSearch(value) { return normalizeText(value).replace(/\s+/g, ' ').trim(); }

async function ensureDirs() { await fsp.mkdir(runtimeDir, { recursive: true }); }
async function readLedger() {
  await ensureDirs();
  try { return JSON.parse(await fsp.readFile(ledgerPath, 'utf8')); }
  catch (error) {
    if (error.code !== 'ENOENT') throw error;
    return { schema_version: 'chatgpt-image-worker-v1', created_at: iso(), updated_at: iso(), jobs: {}, events: [] };
  }
}
async function writeLedger(ledger) {
  ledger.updated_at = iso();
  const temp = `${ledgerPath}.${process.pid}.tmp`;
  await fsp.writeFile(temp, `${JSON.stringify(ledger, null, 2)}\n`, 'utf8');
  await fsp.rename(temp, ledgerPath);
}
async function event(ledger, job, type, message) {
  const at = iso();
  job.updated_at = at;
  job.events = job.events || [];
  job.events.push({ at, type, message });
  ledger.events.push({ at, job_id: job.job_id, type, message });
  await writeLedger(ledger);
}
async function log(line) { await ensureDirs(); await fsp.appendFile(logPath, `${iso()} ${line}\n`, 'utf8'); }

async function ensureContext() {
  if (context && browser?.isConnected()) return context;
  await ensureDirs();
  if (!fs.existsSync(chromePath)) throw new Error(`Chrome not found: ${chromePath}`);
  const endpoint = `http://127.0.0.1:${cdpPort}`;
  let version;
  try { version = await fetch(`${endpoint}/json/version`, { signal: AbortSignal.timeout(1500) }); } catch (_) { /* launch below */ }
  if (!version?.ok) {
    // Chrome is deliberately independent of this worker.  It remains open if
    // Codex or the worker exits, preserving the dedicated profile and login.
    const child = spawn(chromePath, [
      `--remote-debugging-port=${cdpPort}`,
      '--remote-allow-origins=http://127.0.0.1:34191',
      `--user-data-dir=${profilePath}`,
      '--no-first-run', '--no-default-browser-check', 'https://chatgpt.com/',
    ], { detached: true, stdio: 'ignore', windowsHide: false });
    child.unref();
    const deadline = Date.now() + 30000;
    while (Date.now() < deadline) {
      await sleep(500);
      try { version = await fetch(`${endpoint}/json/version`, { signal: AbortSignal.timeout(1500) }); if (version.ok) break; } catch (_) { }
    }
    if (!version?.ok) throw new Error('Dedicated ChatGPT Chrome did not expose its local control endpoint.');
    await log('Independent CDP Chrome launched.');
  }
  browser = await chromium.connectOverCDP(endpoint);
  context = browser.contexts()[0] || await browser.newContext({ acceptDownloads: true, viewport: { width: 1440, height: 800 } });
  browser.on('disconnected', () => { browser = undefined; context = undefined; });
  await log('Worker attached to independent Chrome through CDP.');
  return context;
}
async function resetContext() {
  // Do not close the independent dedicated Chrome.  A worker restart must
  // only detach, so the visible browser and its authenticated profile survive.
  context = undefined;
  browser = undefined;
}
async function pageFor(url) {
  const ctx = await ensureContext();
  const existing = ctx.pages().find(item => !item.isClosed() && canonicalConversationUrl(item.url()) === canonicalConversationUrl(url) && isStableConversationUrl(url));
  if (existing) return existing;
  const page = await ctx.newPage();
  if (url) await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 90000 });
  return page;
}
async function requireVisibleLogin(page) {
  const body = await page.locator('body').innerText({ timeout: 10000 }).catch(() => '');
  if (/登录|Log in|Sign in/.test(body) && !/退出登录|Log out/.test(body)) {
    const error = new Error('ChatGPT requires login or security verification.');
    error.code = 'USER_ACTION';
    throw error;
  }
}
async function textFromComposer(page) {
  return page.locator('div[contenteditable="true"]').last().evaluate(node => {
    const children = [...node.children];
    return children.length ? children.map(child => child.textContent || '').join('\n') : (node.textContent || '');
  }).catch(() => '');
}
function imageComposer(page) {
  return page.locator([
    'textarea[placeholder="描述新图片"]',
    'textarea[aria-label="与 ChatGPT 聊天"]',
    'div[contenteditable="true"][aria-label="与 ChatGPT 聊天"]',
    '#prompt-textarea[contenteditable="true"]',
  ].join(', ')).filter({ visible: true }).last();
}
async function imageComposerText(composer) {
  const tag = await composer.evaluate(node => node.tagName);
  if (tag === 'TEXTAREA' || tag === 'INPUT') return composer.inputValue();
  return composer.evaluate(node => {
    const children = [...node.children];
    return children.length ? children.map(child => child.textContent || '').join('\n') : (node.textContent || '');
  });
}
async function enterImageMode(page) {
  const buttons = [
    page.getByText('创建图像或贴纸', { exact: true }),
    page.getByRole('button', { name: /创建图像|图像或贴纸/i }),
  ];
  for (const button of buttons) {
    if (await button.count().catch(() => 0)) { await button.first().click({ timeout: 10000 }); return; }
  }
  // Some ChatGPT revisions already expose image generation in the normal composer.
}
async function submitNew(job) {
  // Start every asset in a fresh browser tab.  Reusing the previous tab can
  // leave ChatGPT's full-screen image viewer mounted over /images/, exposing
  // only a hidden fallback textarea and making the next prompt impossible to
  // enter.  A fresh tab also makes conversation isolation explicit.
  const ctx = await ensureContext();
  const page = await ctx.newPage();
  await page.goto('https://chatgpt.com/images/', { waitUntil: 'domcontentloaded', timeout: 90000 });
  await requireVisibleLogin(page);
  const composer = imageComposer(page);
  await composer.waitFor({ state: 'visible', timeout: 20000 });
  // The images landing page hydrates after the textarea becomes visible and
  // can replace that DOM node once.  Wait for the replacement before filling,
  // then retry the local fill only; this never submits twice.
  await page.waitForTimeout(1500);
  if (await page.locator('[data-message-author-role="user"]').count()) throw new Error('Image input is not a blank isolated conversation; submission stopped.');
  // ChatGPT persists an unsent Images draft across tabs.  Replace it instead
  // of appending; every durable job retains its exact original prompt and hash.
  if (normalizeText(await imageComposerText(composer)).trim()) await composer.fill('');
  if (job.reference_paths?.length) {
    const input = page.locator('input[aria-label="附加图片"], input[type="file"]').last();
    await input.setInputFiles(job.reference_paths);
  }
  const expectedReadback = normalizeText(job.prompt);
  let readback = '';
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const liveComposer = imageComposer(page);
    await liveComposer.fill(job.prompt);
    await page.waitForTimeout(400);
    readback = normalizeText(await imageComposerText(liveComposer));
    if (readback === expectedReadback) break;
    await page.waitForTimeout(800);
  }
  if (readback !== expectedReadback) throw new Error(`Prompt readback mismatch; expected normalized sha=${sha256(expectedReadback)}, actual sha=${sha256(readback)}`);
  const send = page.getByRole('button', { name: /发送|Send/i }).last();
  await send.waitFor({ state: 'visible', timeout: 20000 });
  await send.click();
  await page.waitForURL(url => /\/c\//.test(url.pathname), { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(500);
  return page;
}
function isStableConversationUrl(value) {
  try { const url = new URL(String(value || '')); return url.origin === 'https://chatgpt.com' && /^\/c\/[0-9a-f-]{20,}$/i.test(url.pathname); }
  catch (_) { return false; }
}
function canonicalConversationUrl(value) {
  if (!isStableConversationUrl(value)) return null;
  const url = new URL(String(value));
  return `${url.origin}${url.pathname}`.toLowerCase();
}
function assertConversationIsolation(ledger, job, value) {
  const canonical = canonicalConversationUrl(value);
  if (!canonical) return;
  for (const other of Object.values(ledger.jobs)) {
    if (other.job_id === job.job_id || other.asset_id === job.asset_id) continue;
    if (canonicalConversationUrl(other.conversation_url) === canonical) {
      throw new Error(`Conversation isolation violation: ${job.asset_id} and ${other.asset_id} share ${canonical}`);
    }
  }
}
async function findConversationForPrompt(job) {
  const ctx = await ensureContext();
  const needle = normalizeForSearch(job.prompt);
  const needleStart = needle.slice(0, 180);
  const needleEnd = needle.slice(-120);

  // Check every already-open stable conversation first. Never navigate an
  // existing result page away merely to open the history list: that destroys
  // the easiest recovery handle for a freshly generated image.
  for (const existing of ctx.pages()) {
    if (existing.isClosed() || !isStableConversationUrl(existing.url())) continue;
    const body = normalizeForSearch(await existing.locator('body').innerText({ timeout: 15000 }).catch(() => ''));
    if (body.includes(needleStart) && body.includes(needleEnd)) return existing;
  }

  const page = await ctx.newPage();
  await page.goto('https://chatgpt.com/', { waitUntil: 'domcontentloaded', timeout: 90000 });
  await requireVisibleLogin(page);
  // The recent-conversation list is hydrated after DOMContentLoaded.
  await page.locator('a[href*="/c/"]').first().waitFor({ state: 'attached', timeout: 10000 }).catch(() => {});
  const hrefs = await page.locator('a[href*="/c/"]').evaluateAll(nodes => [...new Set(nodes.map(node => node.href).filter(Boolean))]).catch(() => []);
  for (const href of hrefs.slice(0, 40)) {
    if (!isStableConversationUrl(href)) continue;
    await page.goto(href, { waitUntil: 'domcontentloaded', timeout: 90000 });
    await page.locator('[data-message-author-role="user"], img[alt*="已生成图片"], img[alt*="Generated image" i]').first().waitFor({ state: 'attached', timeout: 12000 }).catch(() => {});
    const body = normalizeForSearch(await page.locator('body').innerText({ timeout: 15000 }).catch(() => ''));
    if (body.includes(needleStart) && body.includes(needleEnd)) return page;
  }
  return null;
}
async function generationFinished(page, job) {
  // The Images landing page contains old gallery canvases and uploaded inputs.
  // A send click can take longer than the URL wait to create its conversation.
  // Only a conversation containing this exact user prompt may produce a result.
  if (!/^https:\/\/chatgpt\.com\/c\//i.test(page.url())) return { state: 'pending' };
  const userMessages = await page.locator('[data-message-author-role="user"]').allTextContents();
  const expectedPrompt = normalizeForSearch(job.prompt);
  if (!userMessages.some(value => normalizeForSearch(value).includes(expectedPrompt))) return { state: 'pending' };
  // Generated-result semantics take precedence over stale/hidden image nodes.
  // Scanning every historical image bounding box can stall on a replaced node.
  const published = await page.locator('img[alt*="已生成图片"], img[alt*="Generated image" i]').evaluateAll(nodes => nodes.filter(node => node.complete && node.naturalWidth > 0).length).catch(() => 0);
  if (published > 0) return { state: 'complete', images: published };
  const body = await page.locator('body').innerText({ timeout: 10000 }).catch(() => '');
  if (/生成失败|generation failed|出错|发生错误/i.test(body)) return { state: 'failed', message: body.slice(-500) };
  const locator = page.locator('img');
  const count = await locator.count().catch(() => 0);
  let largeImages = 0;
  for (let index = 0; index < count; index += 1) {
    const box = await locator.nth(index).boundingBox({ timeout: 1000 }).catch(() => null);
    if (box && box.width * box.height >= 40000) largeImages += 1;
  }
  const generatedImages = await page.locator('img[alt*="已生成图片"], img[alt*="Generated image" i]').count().catch(() => 0);
  const referenceCount = Array.isArray(job.reference_paths) ? job.reference_paths.length : (job.reference_paths ? 1 : 0);
  const hasNewCanvas = generatedImages > 0 || (referenceCount === 0 && largeImages > 0) || largeImages > referenceCount;
  const stopButtons = page.locator('button[data-testid="stop-button"], button[aria-label*="停止"], button[aria-label*="Stop" i]');
  const stopButtonCount = await stopButtons.count().catch(() => 0);
  let visibleStopButton = false;
  for (let index = 0; index < stopButtonCount; index += 1) {
    if (await stopButtons.nth(index).isVisible().catch(() => false)) { visibleStopButton = true; break; }
  }
  // ChatGPT can leave stale hidden or historical “正在生成” text in the DOM
  // after the image canvas is complete.  The live stop button is the reliable
  // activity signal; a generated canvas with no stop button is complete.
  // A generated-image alt node is only attached after ChatGPT has published
  // the result asset; it is stronger evidence than stale composer controls.
  if (generatedImages > 0) return { state: 'complete', images: Math.max(generatedImages, largeImages) };
  // A reference or a gallery preview is never sufficient completion evidence.
  // An empty assistant shell can appear before the image renderer and its
  // stop button mount. It is not proof of a completed text-only response.
  // With no positively identified result, retain unknown/pending semantics;
  // the deadline requires inspection of this conversation, never resubmission.
  return { state: 'pending' };
}
async function waitForGeneration(page, job, timeoutMs = 12 * 60 * 1000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (page.isClosed()) return { state: 'unknown', message: 'Original page closed; recover the original conversation, never resubmit.' };
    if (isStableConversationUrl(page.url()) && page.url() !== job.conversation_url) {
      const ledger = await readLedger();
      assertConversationIsolation(ledger, job, page.url());
      job.conversation_url = page.url();
      ledger.jobs[job.job_id] = job;
      await event(ledger, job, 'conversation_stabilized', `Stable conversation URL recorded during wait: ${job.conversation_url}`);
    }
    let inspectionTimer;
    const state = await Promise.race([
      generationFinished(page, job),
      new Promise(resolve => {
        inspectionTimer = setTimeout(() => resolve({ state: 'unknown', message: 'Read-only result inspection stalled; recover this conversation without resubmission.' }), 20000);
      }),
    ]).finally(() => clearTimeout(inspectionTimer));
    if (state.state !== 'pending') return state;
    await sleep(5000);
  }
  return { state: 'unknown', message: 'Generation wait timed out; recover from the same conversation URL.' };
}
async function clickDownload(page, openedImage = false) {
  // Native <dialog> elements need not carry an explicit role attribute.
  const nativeSave = page.getByRole('dialog').getByRole('button', { name: /^(保存|下载|Save|Download)$/i }).filter({ visible: true });
  if (await nativeSave.count() === 1) {
    const pending = page.waitForEvent('download', { timeout: 120000 });
    await nativeSave.click({ timeout: 10000 });
    return await pending;
  }
  const selectors = [
    '[role="dialog"] button[aria-label*="下载"]', '[role="dialog"] button[aria-label*="保存"]',
    '[role="dialog"] a[aria-label*="下载"]', '[role="dialog"] a[aria-label*="保存"]',
    '[role="dialog"] [data-testid*="download"]', '[role="dialog"] [data-testid*="save"]',
  ];
  for (const selector of selectors) {
    const locator = page.locator(selector);
    const count = await locator.count().catch(() => 0);
    for (let index = count - 1; index >= 0; index -= 1) {
      try {
        if (!await locator.nth(index).isVisible()) continue;
        const downloadPromise = page.waitForEvent('download', { timeout: 120000 });
        await locator.nth(index).click({ timeout: 10000 });
        return await downloadPromise;
      } catch (_) { /* try the next visible download action */ }
    }
  }
  // Image actions can be hidden until the latest result is opened.
  const generated = page.locator('img[alt*="已生成图片"], img[alt*="Generated image" i]');
  const generatedCount = await generated.count().catch(() => 0);
  if (generatedCount && !openedImage) {
    await generated.last().click({ timeout: 10000 });
    await page.waitForTimeout(2500);
    return clickDownload(page, true);
  }
  throw new Error('No verified image-viewer download action was found; no generic page button was clicked.');
}
async function drainQueue() {
  if (activeRun) return;
  while (runQueue.length) {
    const next = runQueue.shift();
    await execute(next.jobId, next.mode).catch(() => {});
  }
}
async function copyDownloaded(download, targetPath) {
  await fsp.mkdir(path.dirname(targetPath), { recursive: true });
  const temporary = `${targetPath}.${process.pid}.download`;
  await download.saveAs(temporary);
  const sourceHash = crypto.createHash('sha256').update(await fsp.readFile(temporary)).digest('hex');
  if (fs.existsSync(targetPath)) {
    const targetHash = crypto.createHash('sha256').update(await fsp.readFile(targetPath)).digest('hex');
    if (sourceHash !== targetHash) throw new Error(`Refusing to overwrite nonmatching approved target: ${targetPath}`);
    await fsp.unlink(temporary);
  } else {
    await fsp.rename(temporary, targetPath);
  }
  return sourceHash;
}
async function execute(jobId, mode = 'full') {
  if (activeRun) throw new Error('Another image job is already running.');
  activeRun = true;
  try {
    const ledger = await readLedger();
    const job = ledger.jobs[jobId];
    if (!job) throw new Error(`Unknown job: ${jobId}`);
    if (job.target_file_path && fs.existsSync(job.target_file_path)) {
      const existingHash = crypto.createHash('sha256').update(await fsp.readFile(job.target_file_path)).digest('hex');
      if (job.output_sha256 && existingHash.toLowerCase() !== String(job.output_sha256).toLowerCase()) {
        throw new Error(`Existing target hash differs from the recorded download; refusing to overwrite: ${job.target_file_path}`);
      }
      if (job.output_sha256) {
        job.status = 'downloaded';
        job.output_file = job.target_file_path;
        job.output_sha256 = existingHash;
        await event(ledger, job, 'downloaded', 'Stable target already exists with the recorded hash; browser action skipped.');
        return job;
      }
      throw new Error(`Target already exists without a trusted worker hash; manual QA is required before any browser action: ${job.target_file_path}`);
    }
    let page;
    if (mode === 'full' && !job.conversation_url) {
      job.status = 'submitting';
      await event(ledger, job, 'submitting', 'Creating a dedicated ChatGPT image conversation.');
      page = await submitNew(job);
      job.conversation_url = page.url();
      job.status = 'submitted';
      await event(ledger, job, 'submitted', `Submitted once; recovery URL recorded: ${job.conversation_url}`);
    }
    if (!job.conversation_url) throw new Error('A recovery URL is required before waiting or downloading.');
    if (!page) {
      if (isStableConversationUrl(job.conversation_url)) page = await pageFor(job.conversation_url);
      else page = await findConversationForPrompt(job);
    }
    if (!page) {
      job.status = 'result_unknown';
      await event(ledger, job, 'result_unknown', 'Submitted task has only a temporary WEB URL and was not yet recoverable from recent conversations; duplicate submission forbidden.');
      return job;
    }
    if (isStableConversationUrl(page.url()) && page.url() !== job.conversation_url) {
      assertConversationIsolation(ledger, job, page.url());
      job.conversation_url = page.url();
      await event(ledger, job, 'conversation_recovered', `Stable conversation URL recovered: ${job.conversation_url}`);
    }
    await requireVisibleLogin(page);
    job.status = mode === 'download' ? 'recovering_result' : 'generating';
    await event(ledger, job, job.status, mode === 'download' ? 'Checking the original conversation before download.' : 'Waiting in the original ChatGPT conversation.');
    const result = await waitForGeneration(page, job);
    if (result.state === 'failed') throw new Error(result.message);
    if (result.state === 'unknown') {
      job.status = 'result_unknown';
      await event(ledger, job, 'result_unknown', result.message);
      return job;
    }
    if (isStableConversationUrl(page.url()) && page.url() !== job.conversation_url) {
      assertConversationIsolation(ledger, job, page.url());
      job.conversation_url = page.url();
      await event(ledger, job, 'conversation_stabilized', `Stable conversation URL recorded: ${job.conversation_url}`);
    }
    job.status = 'result_detected';
    await event(ledger, job, 'result_detected', 'Result detected in original conversation; starting idempotent download.');
    const download = await clickDownload(page);
    const fileSha256 = await copyDownloaded(download, job.target_file_path);
    job.status = 'downloaded';
    job.output_file = job.target_file_path;
    job.output_sha256 = fileSha256;
    await event(ledger, job, 'downloaded', `Saved to stable path: ${job.target_file_path}`);
    // A completed asset no longer needs a live tab.  Keep only failed or
    // unknown-result conversations open for recovery so serial production
    // never floods the user's Chrome with tabs.
    await page.close().catch(() => {});
    return job;
  } catch (error) {
    const ledger = await readLedger();
    const job = ledger.jobs[jobId];
    if (job) {
      const isUserAction = error.code === 'USER_ACTION';
      job.status = isUserAction ? 'blocked_user_action' : 'retryable';
      await event(ledger, job, job.status, String(error.message || error));
    }
    await log(`job=${jobId} error=${error.stack || error}`);
    throw error;
  } finally { activeRun = false; }
}
function send(res, status, body) { res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' }); res.end(JSON.stringify(body)); }
async function bodyJson(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  const data = Buffer.concat(chunks).toString('utf8');
  return data ? JSON.parse(data) : {};
}
async function route(req, res) {
  try {
    const url = new URL(req.url, `http://127.0.0.1:${port}`);
    if (req.method === 'GET' && url.pathname === '/health') return send(res, 200, { ok: true, active_run: activeRun, pid: process.pid, ledger: ledgerPath });
    if (req.method === 'GET' && url.pathname === '/visible-pages') {
      const ctx = await ensureContext();
      const pages = [];
      for (const page of ctx.pages()) {
        const images = [];
        const locator = page.locator('img');
        const count = await locator.count().catch(() => 0);
        for (let index = 0; index < count; index += 1) {
          const box = await locator.nth(index).boundingBox().catch(() => null);
          if (box && box.width * box.height >= 10000) images.push({ index, width: Math.round(box.width), height: Math.round(box.height), alt: await locator.nth(index).getAttribute('alt').catch(() => null) });
        }
        pages.push({ url: page.url(), title: await page.title().catch(() => ''), large_images: images, visible_text: (await page.locator('body').innerText().catch(() => '')).slice(0, 1200) });
      }
      return send(res, 200, { pages });
    }
    if (req.method === 'GET' && url.pathname === '/jobs') { const ledger = await readLedger(); return send(res, 200, ledger); }
    if (req.method === 'POST' && url.pathname === '/jobs') {
      const input = await bodyJson(req);
      for (const key of ['job_id', 'asset_id', 'name', 'prompt', 'prompt_sha256', 'target_file_path']) if (!input[key]) throw new Error(`Missing ${key}`);
      // The source job hash protects the original Markdown extraction, including
      // its original line ending convention.  The separately normalized check
      // above is only for the browser's ProseMirror round-trip.
      const receivedHash = sha256(input.prompt).toLowerCase();
      const declaredHash = String(input.prompt_sha256).toLowerCase();
      if (receivedHash !== declaredHash) throw new Error(`prompt_sha256 does not match the supplied prompt (received=${receivedHash}, declared=${declaredHash}).`);
      const ledger = await readLedger();
      if (ledger.jobs[input.job_id]) return send(res, 200, { job: ledger.jobs[input.job_id], duplicate: true });
      const job = { ...input, status: input.status || 'authorized', created_at: iso(), updated_at: iso(), attempts: input.attempts || 0, events: [] };
      ledger.jobs[job.job_id] = job;
      await event(ledger, job, 'queued', 'Durable job created; no external action has occurred.');
      return send(res, 201, { job });
    }
    const match = url.pathname.match(/^\/jobs\/([^/]+)\/(run|download)$/);
    if (req.method === 'POST' && match) {
      const jobId = decodeURIComponent(match[1]);
      const mode = match[2] === 'download' ? 'download' : 'full';
      if (!runQueue.some(item => item.jobId === jobId) && !(activeRun && false)) runQueue.push({ jobId, mode });
      setImmediate(() => drainQueue().catch(() => {}));
      return send(res, 202, { accepted: true, job_id: jobId, mode, queue_length: runQueue.length });
    }
    if (req.method === 'POST' && url.pathname === '/shutdown') { send(res, 200, { stopping: true }); setTimeout(() => process.exit(0), 100); return; }
    return send(res, 404, { error: 'Not found' });
  } catch (error) { return send(res, 400, { error: String(error.message || error) }); }
}
async function main() {
  await ensureDirs();
  const server = http.createServer((req, res) => { route(req, res); });
  server.listen(port, '127.0.0.1', () => log(`worker listening on 127.0.0.1:${port} pid=${process.pid}`));
  const stop = async () => { await resetContext(); server.close(() => process.exit(0)); };
  process.on('SIGINT', stop); process.on('SIGTERM', stop);
}
main().catch(error => { process.stderr.write(`${error.stack || error}\n`); process.exit(1); });
