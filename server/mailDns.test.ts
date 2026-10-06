import { afterEach, describe, expect, it, vi } from 'vitest';
import { resolveMailExchangers, resolveMxOverHttps, type MxResolver } from './mailDns';

const failure = (code: string) => Object.assign(new Error(code), { code });
afterEach(() => vi.unstubAllGlobals());
describe('mail DNS fallback', () => {
  it('uses the public resolver after a hosting resolver refuses all MX requests', async () => {
    const system = vi.fn<MxResolver>().mockRejectedValue(failure('EREFUSED'));
    const backup = vi
      .fn<MxResolver>()
      .mockResolvedValue([{ exchange: 'mx.example.test', priority: 10 }]);
    const https = vi.fn<MxResolver>();
    await expect(resolveMailExchangers('example.test', [system, backup, https])).resolves.toEqual([
      { exchange: 'mx.example.test', priority: 10 },
    ]);
    expect(system).toHaveBeenCalledWith('example.test');
    expect(backup).toHaveBeenCalledOnce();
    expect(https).not.toHaveBeenCalled();
  });
  it('uses HTTPS after both UDP resolvers fail', async () => {
    const unavailable = vi.fn<MxResolver>().mockRejectedValue(failure('ETIMEOUT'));
    const https = vi
      .fn<MxResolver>()
      .mockResolvedValue([{ exchange: 'mx.example.test', priority: 5 }]);
    await expect(
      resolveMailExchangers('example.test', [unavailable, unavailable, https]),
    ).resolves.toEqual([{ exchange: 'mx.example.test', priority: 5 }]);
    expect(https).toHaveBeenCalledOnce();
  });
  it('does not bypass NXDOMAIN, missing MX, or explicit Null MX', async () => {
    const fallback = vi.fn<MxResolver>();
    await expect(
      resolveMailExchangers('invalid.test', [
        vi.fn<MxResolver>().mockRejectedValue(failure('ENOTFOUND')),
        fallback,
      ]),
    ).rejects.toMatchObject({ code: 'ENOTFOUND' });
    await expect(
      resolveMailExchangers('invalid.test', [vi.fn<MxResolver>().mockResolvedValue([]), fallback]),
    ).resolves.toEqual([]);
    await expect(
      resolveMailExchangers('invalid.test', [
        vi.fn<MxResolver>().mockResolvedValue([{ exchange: '.', priority: 0 }]),
        fallback,
      ]),
    ).resolves.toEqual([{ exchange: '.', priority: 0 }]);
    expect(fallback).not.toHaveBeenCalled();
  });
  it('parses MX records only and retains Null MX correctly', async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
      new Response(
        JSON.stringify({
          Status: 0,
          Answer: [
            { type: 5, data: 'alias.test.' },
            { type: 15, data: '10 mx.example.test.' },
            { type: 15, data: '0 .' },
          ],
        }),
        { status: 200 },
      ),
    );
    vi.stubGlobal('fetch', fetchMock);
    await expect(resolveMxOverHttps('example.test')).resolves.toEqual([
      { exchange: 'mx.example.test', priority: 10 },
      { exchange: '.', priority: 0 },
    ]);
    const url = fetchMock.mock.calls[0]?.[0] as URL;
    expect(url.searchParams.get('name')).toBe('example.test');
    expect(url.searchParams.get('type')).toBe('MX');
  });
  it('tries a second HTTPS provider on transport failure and rejects invalid responses', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockRejectedValueOnce(new Error('unavailable'))
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({ Status: 0, Answer: [{ type: 15, data: '5 mx.example.test.' }] }),
          { status: 200 },
        ),
      );
    vi.stubGlobal('fetch', fetchMock);
    await expect(resolveMxOverHttps('example.test')).resolves.toEqual([
      { exchange: 'mx.example.test', priority: 5 },
    ]);
    expect(String(fetchMock.mock.calls[1]?.[0])).toContain('dns.google');
    fetchMock.mockImplementation(
      async () => new Response(JSON.stringify({ Status: 2 }), { status: 200 }),
    );
    await expect(resolveMxOverHttps('example.test')).rejects.toMatchObject({ code: 'ESERVFAIL' });
  });
});
