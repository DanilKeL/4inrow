import { spawn } from 'node:child_process';
import { chromium } from '@playwright/test';
import { existsSync } from 'node:fs';
import { WebSocket } from 'ws';
const base = process.env.PRODUCTION_URL ?? 'http://127.0.0.1:4174';
const server = process.env.PRODUCTION_URL
  ? null
  : spawn(process.execPath, ['dist-server/index.js'], {
      windowsHide: true,
      stdio: 'ignore',
      env: { ...process.env, PORT: '4174' },
    });
let browser;
const sockets = [];
function event(ws, predicate) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      ws.off('message', receive);
      reject(Error('Timed out waiting for lobby state'));
    }, 10000);
    const receive = (data) => {
      const value = JSON.parse(data.toString());
      if (value.type === 'error' || predicate(value)) {
        clearTimeout(timer);
        ws.off('message', receive);
        if (value.type === 'error') reject(Error(value.message));
        else resolve(value);
      }
    };
    ws.on('message', receive);
  });
}
async function client() {
  const ws = new WebSocket(base.replace(/^http/, 'ws') + '/online');
  sockets.push(ws);
  await new Promise((resolve, reject) => {
    ws.once('open', resolve);
    ws.once('error', reject);
  });
  return ws;
}
try {
  for (let i = 0; i < 40; i++) {
    try {
      if ((await fetch(base + '/health')).ok) break;
    } catch {
      /* Wait for startup. */
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  browser = await chromium.launch({
    channel:
      process.env.PLAYWRIGHT_CHANNEL ??
      (existsSync(chromium.executablePath()) ? undefined : 'msedge'),
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, hasTouch: true });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (message) => {
    if (['error', 'warning'].includes(message.type())) errors.push(message.text());
  });
  await page.goto(base);
  // Read a saved second-player-start match through the production archive and replay.
  // Automatic saving is covered by the real-play browser suite.
  const game = JSON.stringify({
    version: 1,
    size: 5,
    connect: 4,
    firstPlayer: 2,
    moves: [
      [0, 0],
      [0, 4],
      [1, 0],
      [1, 4],
      [2, 0],
      [2, 4],
      [4, 2],
      [3, 4],
    ].map(([x, y]) => ({ x, y })),
  });
  await page.evaluate(
    (game) =>
      localStorage.setItem(
        'four-cubed-match-history-v1',
        JSON.stringify([
          {
            id: 'smoke',
            title: 'Проверка второй партии',
            date: Date.now(),
            names: ['Создатель', 'Гость'],
            mode: 'online',
            elapsed: 60,
            game,
          },
        ]),
      ),
    game,
  );
  await page.setViewportSize({ width: 390, height: 844 });
  await page.reload();
  await page.getByRole('button', { name: 'История партий', exact: true }).click();
  await page.getByRole('button', { name: 'Смотреть', exact: true }).click();
  await page.getByRole('button', { name: 'В начало повтора' }).click();
  await page.getByRole('button', { name: 'Следующий ход' }).click();
  if (!(await page.getByTestId('move-count').innerText()).startsWith('1'))
    throw Error('Wrong replay position');
  await page.waitForTimeout(1000);
  await page.screenshot({ path: 'artifacts/history-mobile.png' });
  if (errors.length) throw Error(errors.join('\n'));

  const host = await client();
  let pending = event(host, (value) => value.type === 'session');
  host.send(JSON.stringify({ type: 'create', name: 'Проверка создатель' }));
  const session = await pending;
  const guest = await client();
  pending = event(guest, (value) => value.type === 'session');
  guest.send(JSON.stringify({ type: 'join', code: session.code, name: 'Проверка гость' }));
  let snapshot = (await pending).snapshot;
  for (let round = 1; round <= 3; round++) {
    const first = round % 2 ? 1 : 2;
    if (snapshot.game.currentPlayer !== first) throw Error(`Wrong starter in round ${round}`);
    for (let i = 0; i < 7; i++) {
      const actor = snapshot.game.currentPlayer === 1 ? host : guest;
      pending = event(
        host,
        (value) =>
          value.type === 'state' &&
          value.snapshot.round === round &&
          value.snapshot.game.history.length === i + 1,
      );
      actor.send(
        JSON.stringify({
          type: 'move',
          x: Math.floor(i / 2),
          y: i % 2,
          revision: snapshot.revision,
          round,
        }),
      );
      snapshot = (await pending).snapshot;
    }
    if (snapshot.game.winner !== first) throw Error('Incorrect winner');
    if (round < 3) {
      pending = event(
        host,
        (value) => value.type === 'state' && value.snapshot.round === round + 1,
      );
      host.send(JSON.stringify({ type: 'rematch', round }));
      guest.send(JSON.stringify({ type: 'rematch', round }));
      snapshot = (await pending).snapshot;
    }
  }
  host.send(JSON.stringify({ type: 'leave' }));
  console.log(
    'History production passed: saved second-player replay, three online rounds with starters 1/2/1 and correct winners.',
  );
} finally {
  sockets.forEach((ws) => ws.close());
  await browser?.close();
  server?.kill();
}
