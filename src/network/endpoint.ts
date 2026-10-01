export function onlineEndpoint(
  location: Pick<Location, 'protocol' | 'host'>,
  configured: string | undefined = import.meta.env.VITE_ONLINE_URL,
): string {
  if (configured) {
    const endpoint = new URL(configured);
    if (!['ws:', 'wss:'].includes(endpoint.protocol)) {
      throw new Error('Online endpoint must use ws:// or wss://');
    }
    return endpoint.href;
  }
  return `${location.protocol === 'https:' ? 'wss:' : 'ws:'}//${location.host}/online`;
}
