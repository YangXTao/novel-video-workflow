const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');

const playwrightPath = process.env.CODEX_PLAYWRIGHT_PATH
  || 'C:\\Users\\Y\\.cache\\codex-runtimes\\codex-primary-runtime\\dependencies\\node\\node_modules\\playwright';
const { chromium } = require(playwrightPath);

async function loadVideo(page, input) {
  await page.goto(pathToFileURL(path.resolve(input)).href, { waitUntil: 'commit', timeout: 15000 });
  await page.waitForSelector('video', { timeout: 15000 });
  return page.evaluate(async () => {
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
}

async function main() {
  const [mode, input, output] = process.argv.slice(2);
  if (!['inspect', 'extract-tail', 'contact-sheet', 'contact-sheet-dense'].includes(mode) || !input || (mode !== 'inspect' && !output)) {
    throw new Error('usage: node playwright_video_backend.cjs <inspect|extract-tail|contact-sheet|contact-sheet-dense> <input.mp4> [output.png]');
  }
  const browser = await chromium.launch({
    channel: 'msedge',
    headless: true,
    args: ['--allow-file-access-from-files', '--autoplay-policy=no-user-gesture-required'],
  });
  try {
    const page = await browser.newPage();
    const meta = await loadVideo(page, input);
    if (mode === 'inspect') {
      process.stdout.write(JSON.stringify({
        path: path.resolve(input), readable: true, size_bytes: fs.statSync(input).size,
        frames: null, fps: null, duration_seconds: meta.duration,
        width: meta.width, height: meta.height, backend: 'playwright-msedge',
      }));
      return;
    }
    const dataUrl = await page.evaluate(async ({ mode }) => {
      const video = document.querySelector('video');
      const seek = async (time) => {
        await new Promise((resolve, reject) => {
          video.addEventListener('seeked', resolve, { once: true });
          video.addEventListener('error', () => reject(new Error('video seek failed')), { once: true });
          video.currentTime = time;
          setTimeout(() => reject(new Error('video seek timed out')), 10000);
        });
        await new Promise(resolve => setTimeout(resolve, 120));
      };
      if (mode === 'contact-sheet' || mode === 'contact-sheet-dense') {
        const dense = mode === 'contact-sheet-dense';
        const columns = dense ? 4 : 3;
        const rows = dense ? 3 : 2;
        const cellWidth = dense ? 320 : 426;
        const cellHeight = dense ? 180 : 240;
        const canvas = document.createElement('canvas');
        canvas.width = cellWidth * columns;
        canvas.height = cellHeight * rows;
        const context = canvas.getContext('2d');
        const fractions = dense
          ? [0.03, 0.12, 0.21, 0.30, 0.39, 0.48, 0.57, 0.66, 0.75, 0.84, 0.92, 0.98]
          : [0.05, 0.22, 0.39, 0.56, 0.75, 0.96];
        for (let index = 0; index < fractions.length; index += 1) {
          const time = Math.min(Math.max(0, video.duration - (1 / 24)), video.duration * fractions[index]);
          await seek(time);
          const x = (index % columns) * cellWidth;
          const y = Math.floor(index / columns) * cellHeight;
          context.drawImage(video, x, y, cellWidth, cellHeight);
          context.fillStyle = 'rgba(0,0,0,0.72)';
          context.fillRect(x + 8, y + 8, 72, 28);
          context.fillStyle = '#fff';
          context.font = '18px sans-serif';
          context.fillText(`${time.toFixed(1)}s`, x + 16, y + 29);
        }
        return canvas.toDataURL('image/png');
      }
      const frameStep = 1 / 24;
      let selectedTime = Math.max(0, video.duration - frameStep);
      if (mode === 'extract-tail') {
        const probe = document.createElement('canvas');
        probe.width = 64;
        probe.height = 36;
        const probeContext = probe.getContext('2d', { willReadFrequently: true });
        const lowerBound = Math.max(0, video.duration - 1.5);
        for (let candidate = selectedTime; candidate >= lowerBound; candidate -= 0.1) {
          await seek(candidate);
          probeContext.drawImage(video, 0, 0, probe.width, probe.height);
          const pixels = probeContext.getImageData(0, 0, probe.width, probe.height).data;
          let luminance = 0;
          for (let index = 0; index < pixels.length; index += 4) {
            luminance += (pixels[index] + pixels[index + 1] + pixels[index + 2]) / 3;
          }
          luminance /= pixels.length / 4;
          if (luminance >= 15) {
            selectedTime = candidate;
            break;
          }
        }
      }
      await seek(selectedTime);
      const canvas = document.createElement('canvas');
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
      return canvas.toDataURL('image/png');
    }, { mode });
    const png = Buffer.from(dataUrl.split(',')[1], 'base64');
    fs.writeFileSync(output, png);
    process.stdout.write(JSON.stringify({ ok: true, input: path.resolve(input), output: path.resolve(output), backend: 'playwright-msedge', bytes: png.length }));
  } finally {
    await browser.close();
  }
}

main().catch(error => { process.stderr.write(error.stack || String(error)); process.exit(1); });
