const fs = require('fs');
const fsp = fs.promises;
const path = require('path');
const crypto = require('crypto');

const ledgerPath = path.join('D:\\jimeng\\novel-video-browser\\chatgpt-image-worker', 'jobs.json');
const jobId = process.argv[2];
const targetPath = process.argv[3];
if (!jobId || !targetPath || !fs.existsSync(targetPath)) throw new Error('Usage: mark-rescued-download.cjs <job-id> <existing-target>');

(async () => {
  const ledger = JSON.parse(await fsp.readFile(ledgerPath, 'utf8'));
  const job = ledger.jobs[jobId];
  if (!job) throw new Error(`Unknown job: ${jobId}`);
  if (path.resolve(job.target_file_path) !== path.resolve(targetPath)) throw new Error('Target path does not match durable job.');
  const sha256 = crypto.createHash('sha256').update(await fsp.readFile(targetPath)).digest('hex');
  const at = new Date().toISOString();
  job.status = 'downloaded';
  job.output_file = targetPath;
  job.output_sha256 = sha256;
  job.updated_at = at;
  job.events = [...(job.events || []), { at, type: 'downloaded', message: `Recovered from the original conversation and saved to stable path: ${targetPath}` }];
  ledger.events = [...(ledger.events || []), { at, job_id: jobId, type: 'downloaded', message: `Recovered from the original conversation and saved to stable path: ${targetPath}` }];
  ledger.updated_at = at;
  const temp = `${ledgerPath}.${process.pid}.tmp`;
  await fsp.writeFile(temp, `${JSON.stringify(ledger, null, 2)}\n`, 'utf8');
  await fsp.rename(temp, ledgerPath);
  process.stdout.write(JSON.stringify({ jobId, status: job.status, sha256 }));
})().catch(error => {
  process.stderr.write(String(error.stack || error));
  process.exitCode = 1;
});
