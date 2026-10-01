import { createOnlineServer } from './app.ts';

const port = Number(process.env.PORT ?? 3001);
if (!Number.isInteger(port) || port < 0 || port > 65535)
  throw new Error('PORT must be an integer from 0 to 65535');
const app = createOnlineServer();
const host = process.env.HOST ?? (process.env.NODE_ENV === 'production' ? '127.0.0.1' : '0.0.0.0');
app.httpServer.listen(port, host, () => {
  console.log(`FOUR³ online server: http://${host}:${port}`);
});
for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.once(signal, () => {
    void app.close().then(() => process.exit(0));
  });
}
