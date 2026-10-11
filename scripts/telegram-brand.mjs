import { readFile, writeFile, mkdir } from 'node:fs/promises';

const token = process.env.TELEGRAM_BOT_TOKEN;
if (!token) throw new Error('Bot credential is required in the process environment');
const root = new URL('../', import.meta.url);
const mode = process.argv[2] ?? 'inspect';
const copy = {
  ru: {
    name: 'FOUR³ · Четыре в ряд',
    short_description:
      'Четыре в ряд в трёх измерениях. AI, друзья, уровни и задача дня. Думай на уровень выше — прямо в Telegram.',
    description:
      'FOUR³ — думай на уровень выше.\n\nСобери четыре фишки в линию на объёмном поле 5 × 5 × 5: по горизонтали, вертикали или диагонали.\n\n◉ Сразись с AI или играй с друзьями\n◉ Пройди 40 уровней и реши задачу дня\n◉ Попробуй онлайн-партии и рейтинговую игру\n\nНажми «Играть в FOUR³» в меню — и сделай первый ход.',
  },
  en: {
    name: 'FOUR³ · 3D Connect Four',
    short_description:
      'Connect four in three dimensions. Play AI or friends, solve 40 levels and a daily challenge. Think one level higher.',
    description:
      'FOUR³ — think one level higher.\n\nConnect four pieces on a 5 × 5 × 5 board: horizontally, vertically or diagonally.\n\n◉ Play AI or challenge friends\n◉ Solve 40 levels and a daily challenge\n◉ Try online matches and ranked play\n\nTap «Играть в FOUR³» in the menu to make your first move.',
  },
};
for (const text of Object.values(copy)) {
  if (text.name.length > 64 || text.short_description.length > 120 || text.description.length > 512)
    throw new Error('Brand copy exceeds Telegram limits');
}
async function api(method, body = {}, attachment) {
  let response;
  try {
    const form = attachment ? new FormData() : null;
    if (form) {
      for (const [key, value] of Object.entries(body))
        form.set(key, typeof value === 'string' ? value : JSON.stringify(value));
      form.set(
        'avatar',
        new Blob([await readFile(attachment)], { type: 'image/jpeg' }),
        'four-avatar.jpg',
      );
    }
    response = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
      method: 'POST',
      ...(form
        ? { body: form }
        : { headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }),
      signal: AbortSignal.timeout(25_000),
    });
  } catch {
    throw new Error(`Telegram connection failed for ${method}`);
  }
  const data = await response.json();
  if (!data.ok)
    throw new Error(`Telegram rejected ${method}: ${data.description ?? response.status}`);
  return data.result;
}

async function inspect() {
  const bot = await api('getMe');
  if (bot.username?.toLowerCase() !== 'forinrow_bot')
    throw new Error('Credential belongs to a different bot');
  const languages = {};
  for (const language_code of ['', 'ru', 'en']) {
    const [name, description, short] = await Promise.all([
      api('getMyName', { language_code }),
      api('getMyDescription', { language_code }),
      api('getMyShortDescription', { language_code }),
    ]);
    languages[language_code || 'default'] = { ...name, ...description, ...short };
  }
  const webhook = await api('getWebhookInfo');
  const photos = await api('getUserProfilePhotos', { user_id: bot.id, limit: 1 });
  return {
    bot: { id: bot.id, username: bot.username, name: bot.first_name },
    languages,
    webhookConfigured: Boolean(webhook.url),
    pendingUpdates: webhook.pending_update_count,
    photos,
    menu: await api('getChatMenuButton'),
  };
}

try {
  const before = await inspect();
  if (mode === 'inspect') {
    await mkdir(new URL('artifacts/', root), { recursive: true });
    await writeFile(
      new URL('artifacts/telegram-brand-before.json', root),
      JSON.stringify(before, null, 2),
    );
    console.log(JSON.stringify(before, null, 2));
  } else if (mode === 'apply') {
    for (const language_code of ['', 'ru', 'en']) {
      const text = copy[language_code === 'en' ? 'en' : 'ru'];
      await api('setMyName', { name: text.name, language_code });
      await api('setMyDescription', { description: text.description, language_code });
      await api('setMyShortDescription', {
        short_description: text.short_description,
        language_code,
      });
    }
    await api(
      'setMyProfilePhoto',
      { photo: { type: 'static', photo: 'attach://avatar' } },
      new URL('public/telegram/four-avatar.jpg', root),
    );
    const after = await inspect();
    for (const language_code of ['default', 'ru', 'en']) {
      const expected = copy[language_code === 'en' ? 'en' : 'ru'];
      for (const key of ['name', 'description', 'short_description'])
        if (after.languages[language_code][key] !== expected[key])
          throw new Error('Branding verification mismatch');
    }
    if (after.photos.total_count < 1) throw new Error('Profile photo verification failed');
    await writeFile(
      new URL('artifacts/telegram-brand-after.json', root),
      JSON.stringify(after, null, 2),
    );
    console.log(
      JSON.stringify({
        verified: true,
        bot: after.bot,
        profilePhoto: true,
        languages: ['default', 'ru', 'en'],
      }),
    );
  } else throw new Error('Unknown branding mode');
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
