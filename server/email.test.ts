import { describe, expect, it, vi } from 'vitest';
import { ResendMailer } from './email';

describe('ResendMailer recipient validation', () => {
  it('accepts domains with a real MX record and caches the lookup', async () => {
    const resolveMx = vi.fn(async () => [{ exchange: 'mx.example.test', priority: 10 }]);
    const mailer = new ResendMailer(
      'test-key',
      'FOUR <no-reply@4inrow.ru>',
      'https://4inrow.ru',
      resolveMx,
    );

    await expect(mailer.validateRecipient('player@example.test')).resolves.toBe(true);
    await expect(mailer.validateRecipient('other@example.test')).resolves.toBe(true);
    expect(resolveMx).toHaveBeenCalledOnce();
  });

  it('rejects domains without a mail server', async () => {
    const resolveMx = vi.fn(async () => []);
    const mailer = new ResendMailer(
      'test-key',
      'FOUR <no-reply@4inrow.ru>',
      'https://4inrow.ru',
      resolveMx,
    );

    await expect(mailer.validateRecipient('player@invalid.test')).resolves.toBe(false);
  });
  it('deduplicates concurrent domain lookups and keeps rejecting explicit Null MX', async () => {
    const resolveMx = vi.fn(async () => [{ exchange: '.', priority: 0 }]);
    const mailer = new ResendMailer(
      'test-key',
      'FOUR <no-reply@4inrow.ru>',
      'https://4inrow.ru',
      resolveMx,
    );
    await expect(
      Promise.all([
        mailer.validateRecipient('one@invalid.test'),
        mailer.validateRecipient('two@invalid.test'),
      ]),
    ).resolves.toEqual([false, false]);
    expect(resolveMx).toHaveBeenCalledOnce();
  });

  it('reports a temporary DNS outage separately and retries without a negative cache', async () => {
    const resolveMx = vi.fn(async () => {
      const error = new Error('temporary failure') as NodeJS.ErrnoException;
      error.code = 'ETIMEOUT';
      throw error;
    });
    const mailer = new ResendMailer(
      'test-key',
      'FOUR <no-reply@4inrow.ru>',
      'https://4inrow.ru',
      resolveMx,
    );

    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    try {
      await expect(mailer.validateRecipient('player@example.test')).rejects.toMatchObject({
        status: 503,
      });
      await expect(mailer.validateRecipient('player@example.test')).rejects.toMatchObject({
        status: 503,
      });
      expect(resolveMx).toHaveBeenCalledTimes(2);
    } finally {
      warn.mockRestore();
    }
  });

  it('uses the dedicated branded logo in transactional emails', async () => {
    const fetchMock = vi.fn<typeof fetch>(
      async () =>
        new Response(null, {
          status: 200,
          headers: { 'x-request-id': 'test-request' },
        }),
    );
    vi.stubGlobal('fetch', fetchMock);

    try {
      const mailer = new ResendMailer(
        'test-key',
        'FOUR <no-reply@4inrow.ru>',
        'https://4inrow.ru',
        vi.fn(async () => [{ exchange: 'mx.example.test', priority: 10 }]),
      );

      await mailer.sendVerification({
        email: 'player@example.test',
        username: 'player',
        token: 'verification-token',
      });

      const request = fetchMock.mock.calls[0]?.[1] as RequestInit;
      const payload = JSON.parse(String(request.body)) as { html: string };
      expect(payload.html).toContain('https://4inrow.ru/icons/email-logo.png?v=20261001');
      expect(payload.html).not.toContain('/icons/icon-192.png');
    } finally {
      vi.unstubAllGlobals();
    }
  });
});
