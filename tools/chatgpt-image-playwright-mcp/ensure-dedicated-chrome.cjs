const fs = require('fs');
const { spawn } = require('child_process');

const chromePath = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const profilePath = 'D:\\jimeng\\novel-video-browser\\chatgpt-image-profile';
const endpoint = 'http://127.0.0.1:34192';
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function isReady() {
  try {
    const response = await fetch(`${endpoint}/json/version`, { signal: AbortSignal.timeout(1500) });
    return response.ok;
  } catch (_) {
    return false;
  }
}

(async () => {
  if (await isReady()) {
    process.stdout.write('Dedicated ChatGPT Chrome is already running.\n');
    return;
  }
  if (!fs.existsSync(chromePath)) throw new Error(`Chrome not found: ${chromePath}`);
  fs.mkdirSync(profilePath, { recursive: true });
  const child = spawn(chromePath, [
    '--remote-debugging-port=34192',
    '--remote-allow-origins=http://127.0.0.1:34191',
    `--user-data-dir=${profilePath}`,
    '--no-first-run',
    '--no-default-browser-check',
    'https://chatgpt.com/',
  ], { detached: true, stdio: 'ignore', windowsHide: false });
  child.unref();
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    if (await isReady()) {
      process.stdout.write('Dedicated ChatGPT Chrome launched and will outlive the MCP process.\n');
      return;
    }
    await sleep(500);
  }
  throw new Error('Dedicated ChatGPT Chrome did not expose CDP on port 34192.');
})().catch(error => {
  process.stderr.write(String(error.stack || error));
  process.exitCode = 1;
});
