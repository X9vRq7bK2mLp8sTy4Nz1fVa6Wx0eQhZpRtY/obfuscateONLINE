import { execFile } from 'child_process';
import { join } from 'path';

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).send('Method not allowed');
  
  const { code } = req.body;
  if (!code) return res.status(400).json({ error: 'no code provided' });

  // path to your runner lua script
  const runner = join(process.cwd(), 'runner.lua');

  // pass the user code via environment variable to runner.lua
  execFile('luajit', [runner], { env: { ...process.env, USER_CODE: code } }, (err, stdout, stderr) => {
    if (err) return res.status(500).json({ error: stderr || err.message });
    res.status(200).json({ output: stdout });
  });
}
