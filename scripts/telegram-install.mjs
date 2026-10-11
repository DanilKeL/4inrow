import { spawn } from 'node:child_process';
const token = process.env.TELEGRAM_BOT_TOKEN;
if (!token) {
  console.error('Missing bot credential');
  process.exit(1);
}
const ssh = spawn(
  'ssh',
  [
    '-o',
    'BatchMode=yes',
    '-o',
    'ConnectTimeout=10',
    'four-game-server',
    'python3 /tmp/install-four-telegram-bot.py',
  ],
  { stdio: ['pipe', 'inherit', 'inherit'], windowsHide: true },
);
ssh.stdin.end(`${token}\n`);
ssh.stdin.on('error', () => {
  /* ssh exit reports failed installation */
});
ssh.on('error', () => {
  console.error('Could not connect to the application server');
  process.exitCode = 1;
});
ssh.on('exit', (code) => {
  process.exitCode = code ?? 1;
});
