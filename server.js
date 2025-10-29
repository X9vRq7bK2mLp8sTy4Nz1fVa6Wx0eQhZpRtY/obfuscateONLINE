// server.js
import express from 'express';
import { spawn } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
app.use(express.json({ limit: '20mb' }));
app.use(express.static(path.join(__dirname, 'public')));

app.post('/api/obfuscate', (req, res) => {
  const code = req.body.code;
  const preset = req.body.preset || 'Strong';
  if (!code) return res.status(400).json({ error: 'no code provided' });

  const runner = path.join(__dirname, 'runner.lua');

  const child = spawn('luajit', [runner], {
    env: { ...process.env, USER_CODE: code, PROM_PRESET: preset },
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 20 * 1024 * 1024
  });

  let stdout = '';
  let stderr = '';

  child.stdout.on('data', (d) => { stdout += d.toString(); });
  child.stderr.on('data', (d) => { stderr += d.toString(); });

  child.on('close', (codeExit) => {
    if (codeExit !== 0) {
      return res.status(500).json({ error: stderr || 'runner failed' });
    }
    res.json({ output: stdout });
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`listening ${PORT}`));
