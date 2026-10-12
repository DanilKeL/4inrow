import { createOnlineServer } from '../server/app.ts';
import { createAdminPasswordHash } from '../server/admin.ts';
const app = createOnlineServer({
  staticDir: 'dist',
  authFile: null,
  statsFile: null,
  telegram: null,
  adminPasswordHash: await createAdminPasswordHash('skin-browser-test-123'),
});
app.httpServer.listen(0, '127.0.0.1', () => {
  const address = app.httpServer.address();
  if (address && typeof address !== 'string') console.log(`http://127.0.0.1:${address.port}`);
});
for (const signal of ['SIGTERM', 'SIGINT'] as const)
  process.once(signal, () => {
    void app.close().then(() => process.exit(0));
  });
