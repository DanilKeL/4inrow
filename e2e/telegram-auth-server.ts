import { createLocalJWKSet } from 'jose';
import type { AddressInfo } from 'node:net';
import { createOnlineServer } from '../server/app';

// Only launched by the isolated browser suite, never by production entry points.
const app = createOnlineServer({
  authFile: null,
  statsFile: null,
  staticDir: null,
  mailer:
    process.env.FOUR_TEST_MAIL === '1'
      ? {
          sendVerification: async (message) => {
            process.send?.({ type: 'mail', ...message });
          },
          sendPasswordReset: async (message) => {
            process.send?.({ type: 'mail', ...message });
          },
        }
      : null,
  telegram: {
    botToken: '8834741855:isolated-browser-test',
    clientId: '8834741855',
    keys: createLocalJWKSet(JSON.parse(process.env.FOUR_TEST_TELEGRAM_JWKS!)),
  },
});
app.httpServer.listen(0, '127.0.0.1', () => {
  process.stdout.write(`http://127.0.0.1:${(app.httpServer.address() as AddressInfo).port}\n`);
});
process.on('SIGTERM', () => {
  void app.close().then(() => process.exit());
});
