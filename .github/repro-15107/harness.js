// Launches pwsh the way actions/setup-dotnet does (@actions/exec -> child_process.spawn, windowsHide not set)
// and counts "Internal CLR error. (0x80131506)" crashes. Env: LAUNCHES, HIDE=1 to spawn with a hidden window.
const { spawn } = require('node:child_process');
const fs = require('node:fs');

const pwsh = 'C:\\Program Files\\PowerShell\\7\\pwsh.exe';
const total = Number(process.env.LAUNCHES || 500);
const hide = process.env.HIDE === '1';
const workers = 4;
const args = ['-NoLogo', '-Sta', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Unrestricted', '-Command', 'exit 0'];

let started = 0;
let done = 0;
const clrCrashes = [];
const otherFailures = [];

function one() {
  return new Promise(resolve => {
    const child = spawn(pwsh, args, { windowsHide: hide, stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '';
    child.stdout.on('data', d => (out += d));
    child.stderr.on('data', d => (out += d));
    child.on('close', code => {
      done++;
      if (code !== 0) {
        const entry = { launch: done, exitCode: code >>> 0, output: out.slice(0, 1500) };
        (out.includes('0x80131506') ? clrCrashes : otherFailures).push(entry);
      }
      resolve();
    });
  });
}

async function worker() {
  while (started < total) {
    started++;
    await one();
  }
}

(async () => {
  const t0 = Date.now();
  await Promise.all(Array.from({ length: workers }, worker));
  const secs = Math.round((Date.now() - t0) / 1000);
  const env = Object.keys(process.env).filter(k => k.startsWith('DOTNET_GC')).map(k => `${k}=${process.env[k]}`).join(' ') || '(none)';
  const line = `RESULT launches=${done} clrCrashes=${clrCrashes.length} otherFailures=${otherFailures.length} windowsHide=${hide} gcEnv=${env} seconds=${secs}`;
  console.log(line);
  for (const c of [...clrCrashes.slice(0, 2), ...otherFailures.slice(0, 2)]) {
    console.log(`--- launch ${c.launch}, exit code ${c.exitCode} (0x${c.exitCode.toString(16)})\n${c.output}`);
  }
  if (process.env.GITHUB_STEP_SUMMARY) {
    fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, `\`${line}\`\n`);
  }
})();
