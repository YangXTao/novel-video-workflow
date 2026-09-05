const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');
const { chromium } = require('C:\\Users\\Y\\.cache\\codex-runtimes\\codex-primary-runtime\\dependencies\\node\\node_modules\\playwright');

async function main() {
  const input = process.argv[2];
  const output = process.argv[3];
  const requestedTime = process.argv[4] === undefined ? null : Number(process.argv[4]);
  if (!input || !output) throw new Error('usage: node extract_last_video_frame.cjs <input.mp4> <output.png>');
  if (requestedTime !== null && Number.isNaN(requestedTime)) throw new Error('time must be a number');

  const browser = await chromium.launch({
    channel: 'msedge',
    headless: true,
    args: ['--allow-file-access-from-files', '--autoplay-policy=no-user-gesture-required'],
  });

  try {
    const page = await browser.newPage();
    await page.goto(pathToFileURL(path.resolve(input)).href, { waitUntil: 'commit', timeout: 15000 });
    process.stderr.write('navigation committed\n');
    await page.waitForSelector('video', { timeout: 15000 });
    process.stderr.write('video element found\n');
    const dataUrl = await page.evaluate(async (requestedTime) => {
      const video = document.querySelector('video');
      video.muted = true;
      if (video.readyState < 1) {
        await new Promise((resolve, reject) => {
          video.addEventListener('loadedmetadata', resolve, { once: true });
          video.addEventListener('error', () => reject(new Error('video metadata load failed')), { once: true });
        });
      }
      const frameStep = 1 / 24;
      await new Promise((resolve, reject) => {
        video.addEventListener('seeked', resolve, { once: true });
        video.addEventListener('error', () => reject(new Error('video seek failed')), { once: true });
        video.currentTime = requestedTime === null
          ? Math.max(0, video.duration - frameStep)
          : Math.min(Math.max(0, requestedTime), Math.max(0, video.duration - frameStep));
        setTimeout(() => reject(new Error('video seek timed out')), 10000);
      });
      await new Promise(resolve => setTimeout(resolve, 250));
      const canvas = document.createElement('canvas');
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
      return canvas.toDataURL('image/png');
    }, requestedTime);
    process.stderr.write('frame rendered\n');
    const png = Buffer.from(dataUrl.split(',')[1], 'base64');
    fs.writeFileSync(output, png);
    process.stdout.write(JSON.stringify({ output, bytes: png.length }));
  } finally {
    await browser.close();
  }
}

main().catch(error => {
  process.stderr.write(error.stack || String(error));
  process.exit(1);
});
