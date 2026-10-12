/** Recovery is available only in the requesting Telegram user's private chat. */
export function recoveryUser(message) {
  if (
    message?.chat?.type !== 'private' ||
    typeof message.text !== 'string' ||
    !Number.isSafeInteger(message.from?.id) ||
    message.from.id <= 0 ||
    message.from.is_bot ||
    message.chat.id !== message.from.id
  )
    return null;
  const [raw, argument] = message.text.trim().split(/\s+/);
  const command = raw.split('@')[0].toLowerCase();
  return command === '/reset' || (command === '/start' && argument === 'reset')
    ? String(message.from.id)
    : null;
}

export async function recoveryReply(
  message,
  {
    token,
    publicUrl = 'https://4inrow.ru',
    apiUrl = 'http://127.0.0.1:3001',
    fetcher = fetch,
  } = {},
) {
  const id = recoveryUser(message);
  if (!id) return null;
  const response = await fetcher(`${apiUrl}/auth/telegram/bot-reset`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ id }),
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error('Game recovery service temporarily unavailable');
  const result = await response.json();
  const reply = {
    method: 'sendMessage',
    body: {
      chat_id: message.chat.id,
      text: result.viaEmail
        ? 'К аккаунту привязана почта. Используйте «Забыли пароль?» на сайте для восстановления по email.'
        : 'К этому Telegram пока не привязан аккаунт FOUR³. Сначала зарегистрируйтесь через Telegram в игре.',
    },
  };
  if (typeof result.token === 'string' && /^[a-f0-9]{64}$/.test(result.token)) {
    const url = new URL(publicUrl);
    if (url.protocol !== 'https:') throw new Error('Recovery requires a secure public URL');
    url.pathname = '/';
    url.search = '';
    url.hash = '';
    url.searchParams.set('reset', result.token);
    reply.body.text =
      'Задайте новый пароль по кнопке ниже. Ссылка действует 15 минут и подходит только для вашего аккаунта. Если уже использовали её, отправьте /reset через минуту.';
    reply.body.reply_markup = { inline_keyboard: [[{ text: 'Сбросить пароль', url: url.href }]] };
  }
  return reply;
}
