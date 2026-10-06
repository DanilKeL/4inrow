import { Resolver } from 'node:dns/promises';

export type MxResolver = (
  domain: string,
) => Promise<readonly { exchange: string; priority: number }[]>;
export const permanentDnsFailure = (error: unknown) =>
  ['ENODATA', 'ENOTFOUND'].includes((error as NodeJS.ErrnoException)?.code ?? '');

function dnsError(code: string) {
  return Object.assign(new Error(`Mail domain lookup failed: ${code}`), { code });
}
function queryDns(servers?: string[]): MxResolver {
  return async (domain) => {
    // A resolver per lookup lets us cancel it without interrupting other registrations.
    const resolver = new Resolver({ timeout: 1000, tries: 1 });
    if (servers) resolver.setServers(servers);
    const timer = setTimeout(() => resolver.cancel(), 1800);
    timer.unref();
    try {
      return await resolver.resolveMx(domain);
    } finally {
      clearTimeout(timer);
      resolver.cancel();
    }
  };
}

export const resolveMxOverHttps: MxResolver = async (domain) => {
  let lastError: unknown;
  for (const endpoint of ['https://cloudflare-dns.com/dns-query', 'https://dns.google/resolve']) {
    try {
      const url = new URL(endpoint);
      url.searchParams.set('name', domain);
      url.searchParams.set('type', 'MX');
      const response = await fetch(url, {
        headers: { Accept: 'application/dns-json' },
        signal: AbortSignal.timeout(2000),
      });
      if (!response.ok) throw dnsError('ESERVFAIL');
      const body = (await response.json()) as { Status?: unknown; TC?: unknown; Answer?: unknown };
      if (body.Status === 3) throw dnsError('ENOTFOUND');
      if (
        body.Status !== 0 ||
        body.TC === true ||
        (body.Answer !== undefined && !Array.isArray(body.Answer))
      )
        throw dnsError('ESERVFAIL');
      const answers = (body.Answer ?? []) as { type?: unknown; data?: unknown }[];
      return answers
        .filter((a) => a.type === 15)
        .map((answer) => {
          const parts =
            typeof answer.data === 'string' ? /^(\d{1,5})\s+(\S+)$/.exec(answer.data) : null;
          if (!parts || Number(parts[1]) > 65535) throw dnsError('ESERVFAIL');
          return {
            priority: Number(parts[1]),
            exchange: parts[2] === '.' ? '.' : parts[2].replace(/\.$/, ''),
          };
        });
    } catch (error) {
      if (permanentDnsFailure(error)) throw error;
      lastError = error;
    }
  }
  throw lastError ?? dnsError('ESERVFAIL');
};

export async function resolveMailExchangers(
  domain: string,
  resolvers: readonly MxResolver[] = [
    queryDns(),
    queryDns(['1.1.1.1', '8.8.8.8']),
    resolveMxOverHttps,
  ],
) {
  let lastError: unknown;
  for (const resolver of resolvers) {
    try {
      return await resolver(domain);
    } catch (error) {
      // NXDOMAIN, no MX records and Null MX are real negative responses, not outages.
      if (permanentDnsFailure(error)) throw error;
      lastError = error;
    }
  }
  throw lastError ?? dnsError('ESERVFAIL');
}
