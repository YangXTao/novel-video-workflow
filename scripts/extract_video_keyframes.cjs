const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');
const { chromium } = require('C:\\Users\\Y\\.cache\\codex-runtimes\\codex-primary-runtime\\dependencies\\node\\node_modules\\playwright');

async function main() {
  const input = process.argv[2];
  const outputDir = process.argv[3];
  const times = process.argv.slice(4).map(Number);
  if (!input || !outputDir || !times.length || times.some(Number.isNaN)) {
    throw new Error('usage: node extract_video_keyframes.cjs <input.mp4> <output-dir> <time> [time...]');
  }
  fs.mkdirSync(outputDir, { recursive: true });
  const browser = await chromium.launch({
    channel: 'msedge',
    headless: true,
    args: ['--allow-file-access-from-files', '--autoplay-policy=no-user-gesture-required'],
  });
  try {
    const page = await browser.newPage();
    await page.goto(pathToFileURL(path.resolve(input)).href, { waitUntil: 'commit', timeout: 15000 });
    await page.waitForSelector('video', { timeout: 15000 });
    const metadata = await page.evaluate(async () => {
      const video = document.querySelector('video');
      video.muted = true;
      if (video.readyState < 1) {
        await new Promise((resolve, reject) => {
          video.addEventListener('loadedmetadata', resolve, { once: true });
          video.addEventListener('error', () => reject(new Error('video metadata load failed')), { once: true });
        });
      }
      return { duration: video.duration, width: video.videoWidth, height: video.videoHeight };
    });
    for (const requestedTime of times) {
      const result = await page.evaluate(async (requestedTime) => {
        const video = document.querySelector('video');
        const time = Math.min(Math.max(0, requestedTime), Math.max(0, video.duration - 1 / 24));
        await new Promise((resolve, reject) => {
          video.addEventListener('seeked', resolve, { once: true });
          video.addEventListener('error', () => reject(new Error('video seek failed')), { once: true });
          video.currentTime = time;
          setTimeout(() => reject(new Error('video seek timed out')), 10000);
        });
        await new Promise(resolve => setTimeout(resolve, 120));
        const canvas = document.createElement('canvas');
        canvas.width = video.videoWidth;
        canvas.height = video.videoHeight;
        canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
        return { actualTime: time, dataUrl: canvas.toDataURL('image/jpeg', 0.92) };
      }, requestedTime);
      const safe = requestedTime.toFixed(2).replace('.', '_');
      const output = path.join(outputDir, `${safe}s.jpg`);
      fs.writeFileSync(output, Buffer.from(result.dataUrl.split(',')[1], 'base64'));
    }
    process.stdout.write(JSON.stringify({ input, outputDir, metadata, count: times.length }));
  } finally {
    await browser.close();
  }
}

main().catch(error => {
  process.stderr.write(error.stack || String(error));
  process.exit(1);
});
