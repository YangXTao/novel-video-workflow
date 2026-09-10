const fs = require('fs');
const fsp = fs.promises;
const path = require('path');
const crypto = require('crypto');
const { createRequire } = require('module');
const jobId = process.argv[2];
if (!jobId) throw new Error('Usage: save-visible-generated-image.cjs <job-id>');
const ledgerPath = 'D:\\jimeng\\novel-video-browser\\chatgpt-image-worker\\jobs.json';
const store = path.join(__dirname, 'node_modules', '.pnpm');
const packageDir = fs.readdirSync(store).find(name => name.startsWith('playwright@'));
const localRequire = createRequire(path.join(store, packageDir, 'node_modules', 'playwright', 'package.json'));
const { chromium } = localRequire('playwright');

(async () => {
  const ledger = JSON.parse(await fsp.readFile(ledgerPath, 'utf8'));
  const job = ledger.jobs[jobId];
  if (!job) throw new Error(`Unknown job: ${jobId}`);
  if (fs.existsSync(job.target_file_path)) throw new Error(`Refusing to overwrite: ${job.target_file_path}`);
  const browser = await chromium.connectOverCDP('http://127.0.0.1:34192');
  const context = browser.contexts()[0];
  const page = context.pages().find(item => item.url() === job.conversation_url || item.url().includes(job.conversation_url.split('/').pop()));
  if (!page) throw new Error(`Original conversation is not open: ${job.conversation_url}`);
  const rendered = await page.locator('img:visible').evaluateAll(nodes => {
    const matches = nodes.filter(node => node.naturalWidth >= 1024 && node.naturalHeight >= 512 && /backend-api\/(estuary|files)/.test(node.src));
    const unique = [...new Map(matches.map(node => [node.src, node])).values()];
    if (unique.length !== 1) throw new Error(`Expected exactly one unique visible generated image, found ${unique.length}`);
    const image = unique[0];
    const canvas = document.createElement('canvas');
    canvas.width = image.naturalWidth;
    canvas.height = image.naturalHeight;
    const drawing = canvas.getContext('2d');
    drawing.drawImage(image, 0, 0, canvas.width, canvas.height);
    return { width: canvas.width, height: canvas.height, data: canvas.toDataURL('image/png').split(',')[1] };
  });
  if (rendered.width < 1024 || rendered.height < 512) throw new Error(`Rendered image dimensions are too small: ${rendered.width}x${rendered.height}`);
  const bytes = Buffer.from(rendered.data, 'base64');
  if (bytes.length < 100000) throw new Error(`Generated image payload is unexpectedly small: ${bytes.length}`);
  await fsp.mkdir(path.dirname(job.target_file_path), { recursive: true });
  const temp = `${job.target_file_path}.${process.pid}.download`;
  await fsp.writeFile(temp, bytes);
  await fsp.rename(temp, job.target_file_path);
  const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  const now = new Date().toISOString();
  job.status = 'downloaded';
  job.output_file = job.target_file_path;
  job.output_sha256 = sha256;
  job.updated_at = now;
  job.events = Array.isArray(job.events) ? job.events : [];
  job.events.push({ at: now, type: 'downloaded', message: `Saved the single verified visible generated image directly from its authenticated conversation URL: ${job.target_file_path}` });
  ledger.updated_at = now;
  const ledgerTemp = `${ledgerPath}.${process.pid}.tmp`;
  await fsp.writeFile(ledgerTemp, JSON.stringify(ledger, null, 2), 'utf8');
  await fsp.rename(ledgerTemp, ledgerPath);
  // This process only attaches over CDP. Never close the result page or the
  // dedicated Chrome; exit this helper and let the OS detach its CDP socket.
  process.stdout.write(JSON.stringify({ job_id: jobId, output_file: job.target_file_path, sha256, bytes: bytes.length, width: rendered.width, height: rendered.height }), () => process.exit(0));
})().catch(error => { process.stderr.write(String(error.stack || error)); process.exitCode = 1; });
