export const APP_URL = 'https://4inrow.ru/?telegram=1';
export const WELCOME_IMAGE = 'https://4inrow.ru/telegram/four-cover.jpg';
export const commands = [
  { command: 'start', description: 'Открыть FOUR³' },
  { command: 'play', description: 'Начать игру' },
  { command: 'help', description: 'Правила игры' },
  { command: 'reset', description: 'Восстановить пароль' },
];
const playButton = { inline_keyboard: [[{ text: 'Играть в FOUR³ ↗', web_app: { url: APP_URL } }]] };

/** Replies are sent only in a private chat in response to its user's command. */
export function commandReply(message) {
  if (message?.chat?.type !== 'private' || typeof message.text !== 'string') return null;
  const command = message.text.trim().split(/\s+/)[0].split('@')[0].toLowerCase();
  const chat_id = message.chat.id;
  if (command === '/start' || command === '/play')
    return {
      method: 'sendPhoto',
      body: {
        chat_id,
        photo: WELCOME_IMAGE,
        parse_mode: 'HTML',
        caption:
          '<b>FOUR³ — думай на уровень выше.</b>\n\nКлассическая стратегия в трёх измерениях. Собери четыре фишки в линию — на плоскости или в пространстве.\n\nСыграй с AI или друзьями, пройди 40 уровней и реши задачу дня.\n\n<b>Твой первый ход — по кнопке ниже.</b>',
        reply_markup: playButton,
      },
    };
  if (command === '/help')
    return {
      method: 'sendMessage',
      body: {
        chat_id,
        parse_mode: 'HTML',
        text: '<b>Как играть в FOUR³</b>\n\n1. Нажми на столбец, чтобы поставить фишку. Она займёт нижнее свободное место.\n2. Собери четыре свои фишки в линию: по горизонтали, вертикали или диагонали — в том числе объёмной.\n3. Вращай поле, переключай вид и включай рентген, чтобы заметить скрытые линии.\n\n<b>Поле: 5 × 5 × 5. Ходы — по очереди.</b>\n\nВ игре есть AI, режим на двоих, онлайн-партии, 40 уровней и задача дня.',
        reply_markup: playButton,
      },
    };
  return null;
}
