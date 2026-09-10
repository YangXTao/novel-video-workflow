import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { execFileSync } from 'node:child_process';

const launchBrowser = process.argv.includes('--launch-browser');
const startScript = 'D:\\jimeng\\novel-video-tools\\chatgpt-image-playwright-mcp\\start-mcp.cmd';

const transport = new StdioClientTransport({
  command: 'C:\\Windows\\System32\\cmd.exe',
  args: ['/d', '/s', '/c', startScript],
  cwd: 'D:\\jimeng',
  stderr: 'inherit',
});
const client = new Client({ name: 'chatgpt-image-playwright-smoke-test', version: '1.0.0' });

try {
  await client.connect(transport);
  const listed = await client.listTools();
  const names = listed.tools.map(tool => tool.name);
  const required = ['browser_navigate', 'browser_snapshot', 'browser_file_upload', 'browser_click'];
  const missing = required.filter(name => !names.includes(name));
  if (missing.length) throw new Error(`Missing required tools: ${missing.join(', ')}`);

  const result = { connected: true, tool_count: names.length, required_tools: required };
  if (launchBrowser) {
    execFileSync(process.execPath, ['D:\\jimeng\\novel-video-tools\\chatgpt-image-playwright-mcp\\ensure-dedicated-chrome.cjs'], { stdio: 'inherit' });
    await client.callTool({ name: 'browser_navigate', arguments: { url: 'https://chatgpt.com/' } });
    const snapshot = await client.callTool({ name: 'browser_snapshot', arguments: {} });
    result.browser_launched = true;
    result.snapshot_blocks = Array.isArray(snapshot.content) ? snapshot.content.length : 0;
    // The dedicated Chrome is independent and must survive this MCP client.
  }
  process.stdout.write(`${JSON.stringify(result)}\n`);
} finally {
  await client.close();
}
