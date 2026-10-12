import { test } from 'node:test';
import assert from 'node:assert/strict';
import { recoveryReply, recoveryUser } from './telegram-recovery.mjs';

const message = {
  chat: { type: 'private', id: 123456789 },
  from: { id: 123456789 },
  text: '/reset',
};
test('recovery accepts private requests by the actual chat owner, including the start link', () => {
  assert.equal(recoveryUser(message), '123456789');
  assert.equal(recoveryUser({ ...message, text: '/start reset' }), '123456789');
  assert.equal(recoveryUser({ ...message, text: '/play' }), null);
  assert.equal(recoveryUser({ ...message, from: { id: 999999999 } }), null);
  assert.equal(recoveryUser({ ...message, from: { id: 123456789, is_bot: true } }), null);
  assert.equal(recoveryUser({ ...message, chat: { type: 'group', id: 123456789 } }), null);
});
test('sends a short-lived reset link only to the requesting private chat', async () => {
  const credential = 'test-credential';
  const reply = await recoveryReply(message, {
    token: credential,
    fetcher: async (url, options) => {
      assert.equal(url, 'http://127.0.0.1:3001/auth/telegram/bot-reset');
      assert.equal(options.headers.Authorization, `Bearer ${credential}`);
      assert.deepEqual(JSON.parse(options.body), { id: '123456789' });
      return Response.json({ token: 'a'.repeat(64) });
    },
  });
  assert.equal(reply.body.chat_id, 123456789);
  assert.equal(
    reply.body.reply_markup.inline_keyboard[0][0].url,
    `https://4inrow.ru/?reset=${'a'.repeat(64)}`,
  );
  assert.match(reply.body.text, /15 минут/);
  assert.equal(JSON.stringify(reply).includes(credential), false);
});
test('email accounts are directed to email recovery and strangers receive no reset link', async () => {
  const email = await recoveryReply(message, {
    fetcher: async () => Response.json({ viaEmail: true }),
  });
  assert.match(email.body.text, /по email/);
  assert.equal(email.body.reply_markup, undefined);
  const unknown = await recoveryReply(message, { fetcher: async () => Response.json({}) });
  assert.match(unknown.body.text, /Сначала зарегистрируйтесь/);
  assert.equal(unknown.body.reply_markup, undefined);
});
test('no recovery calls for a group or mismatched identity, and network failure never fabricates a link', async () => {
  let calls = 0;
  const reply = await recoveryReply(
    { ...message, chat: { type: 'group', id: -42 } },
    {
      fetcher: () => {
        calls++;
        throw new Error('Unexpected request');
      },
    },
  );
  assert.equal(reply, null);
  assert.equal(calls, 0);
  await assert.rejects(
    recoveryReply(message, { fetcher: async () => new Response('', { status: 403 }) }),
    /unavailable/,
  );
});
