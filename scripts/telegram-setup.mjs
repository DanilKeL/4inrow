// Configure the bot menu without putting a token in source, arguments or logs.
import { readFile } from 'node:fs/promises';
let token = process.env.TELEGRAM_BOT_TOKEN;
if (!token) {
  try {
    token = (
      await readFile(
        process.env.TELEGRAM_BOT_TOKEN_FILE ??
          new URL('../секреты/telegram-bot-token.txt', import.meta.url),
        'utf8',
      )
    ).trim();
  } catch {
    /* A missing token is reported below without revealing file contents. */
  }
}
const url = process.env.TELEGRAM_APP_URL ?? 'https://4inrow.ru/?telegram=1';
if (!token) {
  console.error('Save the bot token in секреты/telegram-bot-token.txt or set TELEGRAM_BOT_TOKEN.');
  process.exit(1);
}
if (new URL(url).protocol !== 'https:') throw new Error('Mini App URL must use HTTPS');
async function api(method, body) {
  let response;
  try {
    response = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(15_000),
    });
  } catch {
    throw new Error('Telegram API connection failed. Check the connection and retry.');
  }
  const result = await response.json();
  if (!result.ok)
    throw new Error(`Telegram rejected ${method}: ${result.description ?? response.status}`);
  return result.result;
}
try {
  const bot = await api('getMe', {});
  const expected = process.env.TELEGRAM_BOT_USERNAME ?? 'forinrow_bot';
  if (bot.username.toLowerCase() !== expected.replace(/^@/, '').toLowerCase())
    throw new Error('This token belongs to a different bot. Check TELEGRAM_BOT_USERNAME.');
  await api('setChatMenuButton', {
    menu_button: { type: 'web_app', text: 'Играть в FOUR³', web_app: { url } },
  });
  const menu = await api('getChatMenuButton', {});
  if (menu.type !== 'web_app' || menu.web_app?.url !== url)
    throw new Error('Telegram did not return the expected Mini App menu button.');
  console.log(`Configured https://t.me/${bot.username} with Mini App ${url}`);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
