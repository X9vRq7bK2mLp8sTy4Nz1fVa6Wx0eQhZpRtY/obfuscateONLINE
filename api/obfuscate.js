import { execFile } from 'child_process';
import { join } from 'path';

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).send('method not allowed');
  const { code, preset } = req.body || {};
  if (!code) return res.status(400).json({ error: 'no code provided' });

  const runner = join(process.cwd(), 'runner.lua');

  // pass code via env var; capture stdout
  execFile('luajit', [runner], {
    env: { ...process.env, USER_CODE: code, PROM_PRESET: preset || 'Strong' },
    maxBuffer: 10 * 1024 * 1024 // 10 MB stdout buffer
  }, (err, stdout, stderr) => {
    if (err) {
      return res.status(500).json({ error: stderr || err.message });
    }
    res.status(200).json({ output: stdout });
  });
}
