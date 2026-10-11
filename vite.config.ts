import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import { realpathSync } from 'node:fs';

export default defineConfig({
  // The workspace may be a Windows directory link. Vite's assets and tests
  // must share the physical root instead of mixing drive-letter paths.
  root: realpathSync(process.cwd()),
  plugins: [react()],
  server: {
    proxy: {
      '/online': { target: 'http://127.0.0.1:3001', ws: true },
      '/health': 'http://127.0.0.1:3001',
      '/auth': 'http://127.0.0.1:3001',
      '/admin-api': 'http://127.0.0.1:3001',
      '/telemetry': 'http://127.0.0.1:3001',
      '/daily': 'http://127.0.0.1:3001',
    },
  },
  test: { include: ['src/**/*.test.{ts,tsx}', 'server/**/*.test.ts'], environment: 'node' },
  build: { chunkSizeWarningLimit: 1100 },
});
