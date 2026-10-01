import { spawn } from 'node:child_process';

const processes = [
  spawn(process.execPath, ['--import', 'tsx', 'server/index.ts'], {
    stdio: 'inherit',
    windowsHide: true,
  }),
  spawn(
    process.execPath,
    ['node_modules/vite/bin/vite.js', '--host', '0.0.0.0', ...process.argv.slice(2)],
    { stdio: 'inherit', windowsHide: true },
  ),
];
let stopping = false;
function stop(code = 0) {
  if (stopping) return;
  stopping = true;
  processes.forEach((child) => child.kill());
  process.exitCode = code;
}
processes.forEach((child) => {
  child.on('error', (error) => {
    console.error(error.message);
    stop(1);
  });
  child.on('exit', (code) => stop(code ?? 0));
});
process.on('SIGINT', () => stop());
process.on('SIGTERM', () => stop());
