import type { ServerResponse } from 'node:http';
import type { SkinCatalog } from '../src/skins/catalog.ts';

export class AppearanceEvents {
  private clients = new Set<ServerResponse>();
  subscribe(response: ServerResponse, catalog: SkinCatalog) {
    if (this.clients.size >= 512) {
      response.writeHead(503).end(JSON.stringify({ error: 'Попробуйте подключиться позже.' }));
      return;
    }
    response.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
    response.setHeader('Cache-Control', 'no-store, no-transform');
    response.setHeader('X-Accel-Buffering', 'no');
    response.flushHeaders();
    response.write('retry: 3000\n\n');
    this.clients.add(response);
    this.send(response, catalog);
    const heartbeat = setInterval(() => {
      if (!response.destroyed && response.writableLength < 128 * 1024)
        response.write(': heartbeat\n\n');
      else response.destroy();
    }, 25000);
    heartbeat.unref();
    response.once('close', () => {
      clearInterval(heartbeat);
      this.clients.delete(response);
    });
  }
  private send(response: ServerResponse, catalog: SkinCatalog) {
    if (response.destroyed || response.writableLength > 128 * 1024) {
      response.destroy();
      return;
    }
    response.write(`event: skins\ndata: ${JSON.stringify(catalog)}\n\n`);
  }
  publish(catalog: SkinCatalog) {
    for (const client of this.clients) this.send(client, catalog);
  }
  close() {
    for (const client of this.clients) client.end();
    this.clients.clear();
  }
}
