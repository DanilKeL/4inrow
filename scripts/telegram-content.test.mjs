import { test } from 'node:test';
import assert from 'node:assert/strict';
import { commandReply, APP_URL } from './telegram-content.mjs';

test('start sends the cover and an actual Mini App button to its requesting chat', () => {
  const reply = commandReply({ chat: { type: 'private', id: 42 }, text: '/start launch' });
  assert.equal(reply.method, 'sendPhoto');
  assert.equal(reply.body.chat_id, 42);
  assert.equal(reply.body.reply_markup.inline_keyboard[0][0].web_app.url, APP_URL);
  assert.ok(reply.body.caption.length <= 1024);
});
test('help explains volumetric diagonals and can launch the game', () => {
  const reply = commandReply({ chat: { type: 'private', id: 42 }, text: '/help@forinrow_bot' });
  assert.equal(reply.method, 'sendMessage');
  assert.match(reply.body.text, /объёмной/);
  assert.equal(reply.body.reply_markup.inline_keyboard[0][0].web_app.url, APP_URL);
});
test('ignores groups, media and unsolicited text instead of broadcasting', () => {
  assert.equal(commandReply({ chat: { type: 'group', id: -1 }, text: '/start' }), null);
  assert.equal(commandReply({ chat: { type: 'private', id: 42 } }), null);
  assert.equal(commandReply({ chat: { type: 'private', id: 42 }, text: 'hello' }), null);
});
