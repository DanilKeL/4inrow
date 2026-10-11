import { readFile, writeFile, rename, mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';
import { request } from 'node:https';
import { isIP } from 'node:net';
import { commandReply, commands } from './telegram-content.mjs';

const token = process.env.TELEGRAM_BOT_TOKEN;
if (!token) {
  console.error('Bot credential is not configured');
  process.exit(1);
}
const stateFile = process.env.TELEGRAM_STATE_FILE ?? '/srv/four-game-data/telegram-state.json';
const control = new AbortController();
const apiAddress = process.env.TELEGRAM_API_ADDRESS;
if (apiAddress && isIP(apiAddress) !== 4) throw new Error('Invalid Telegram API address');
let stopping = false;
for (const signal of ['SIGTERM', 'SIGINT'])
  process.on(signal, () => {
    stopping = true;
    control.abort();
  });
async function api(method, body = {}) {
  let data;
  try {
    if (apiAddress) {
      // Some routes cannot reach one of Telegram's API addresses. Keep the
      // official TLS hostname/certificate while choosing a reachable address.
      data = await new Promise((resolve, reject) => {
        const bytes = JSON.stringify(body);
        const req = request(
          {
            hostname: 'api.telegram.org',
            servername: 'api.telegram.org',
            port: 443,
            path: `/bot${token}/${method}`,
            method: 'POST',
            family: 4,
            autoSelectFamily: false,
            lookup: (_hostname, _options, callback) => callback(null, apiAddress, 4),
            headers: {
              'Content-Type': 'application/json',
              'Content-Length': Buffer.byteLength(bytes),
            },
            signal: control.signal,
          },
          (response) => {
            const chunks = [];
            let size = 0;
            response.on('data', (chunk) => {
              size += chunk.length;
              if (size > 2_000_000) req.destroy(new Error('Response too large'));
              else chunks.push(chunk);
            });
            response.on('error', reject);
            response.on('end', () => {
              try {
                resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
              } catch {
                const invalid = new Error('Invalid API response');
                invalid.code = `HTTP_${response.statusCode}`;
                reject(invalid);
              }
            });
          },
        );
        req.setTimeout(45_000, () => req.destroy(new Error('Timeout')));
        req.on('error', reject);
        req.end(bytes);
      });
    } else {
      const response = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
        signal: AbortSignal.any([control.signal, AbortSignal.timeout(45_000)]),
      });
      data = await response.json();
    }
  } catch (error) {
    throw new Error(`Telegram connection failed for ${method} (${error.code ?? error.cause?.code ?? 'NETWORK'})`);
  }
  if (!data.ok) {
    const error = new Error(`Telegram ${method} rejected (${data.error_code})`);
    error.status = data.error_code;
    error.retryAfter = data.parameters?.retry_after;
    throw error;
  }
  return data.result;
}

try {
  const bot = await api('getMe');
  if (bot.username?.toLowerCase() !== 'forinrow_bot') throw new Error('Wrong bot credential');
  if ((await api('getWebhookInfo')).url)
    throw new Error('Existing webhook: polling was not started');
  await api('setMyCommands', { commands, language_code: '' });
  await api('setMyCommands', { commands, language_code: 'ru' });
  let offset = 0;
  try {
    const saved = JSON.parse(await readFile(stateFile, 'utf8'));
    if (Number.isSafeInteger(saved.offset) && saved.offset >= 0) offset = saved.offset;
  } catch {
    /* A new bot starts at its oldest pending command. */
  }
  await mkdir(dirname(stateFile), { recursive: true });
  console.log(`FOUR³ welcome bot running: @${bot.username}`);
  while (!stopping) {
    try {
      const updates = await api('getUpdates', {
        offset,
        timeout: 30,
        allowed_updates: ['message'],
      });
      for (const update of updates) {
        const reply = commandReply(update.message);
        if (reply) {
          try {
            await api(reply.method, reply.body);
          } catch (error) {
            // A blocked account should not hold up later commands.
            if (error.status !== 403 && error.status !== 400) throw error;
            console.error(`Reply not delivered (${error.status})`);
          }
        }
        offset = update.update_id + 1;
        const temporary = `${stateFile}.new`;
        await writeFile(temporary, JSON.stringify({ offset }), { mode: 0o600 });
        await rename(temporary, stateFile);
      }
    } catch (error) {
      if (stopping) break;
      if (error.status === 409)
        throw new Error('Another consumer is active: stopping to avoid a conflict');
      console.error(error.message);
      const delay = Math.min(60_000, (error.retryAfter ?? 5) * 1000);
      await new Promise((resolve) => {
        const timer = setTimeout(done, delay);
        function done() {
          clearTimeout(timer);
          control.signal.removeEventListener('abort', done);
          resolve();
        }
        control.signal.addEventListener('abort', done, { once: true });
      });
    }
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
