// One-shot helper: credentials stay in memory and terminal input is never echoed.
import { spawn } from 'node:child_process';
if (!process.stdin.isTTY) {
  console.error('Hidden terminal input unavailable');
  process.exit(1);
}
const [script, ...args] = process.argv.slice(2);
if (!script) {
  console.error('Missing script');
  process.exit(1);
}
process.stdin.setRawMode(true);
process.stdin.setEncoding('utf8');
process.stdin.resume();
let buffer = '';
process.stdin.on('data', (data) => {
  buffer += data;
  if (!/[\r\n]/.test(buffer)) return;
  process.stdin.removeAllListeners('data');
  process.stdin.setRawMode(false);
  process.stdin.pause();
  const child = spawn(process.execPath, [script, ...args], {
    env: { ...process.env, TELEGRAM_BOT_TOKEN: buffer.trim() },
    stdio: 'inherit',
    windowsHide: true,
  });
  buffer = '';
  child.on('error', () => {
    console.error('Could not start bot setup');
    process.exitCode = 1;
  });
  child.on('exit', (code) => {
    process.exitCode = code ?? 1;
  });
});
console.log('Ready for hidden bot credential input.');
