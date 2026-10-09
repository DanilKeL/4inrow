import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { chromium, defineConfig } from '@playwright/test';

const edge = join(
  process.env['PROGRAMFILES(X86)'] ?? '',
  'Microsoft',
  'Edge',
  'Application',
  'msedge.exe',
);
const channel =
  process.env.PLAYWRIGHT_CHANNEL ??
  (!existsSync(chromium.executablePath()) && existsSync(edge) ? 'msedge' : undefined);
export default defineConfig({
  outputDir: './artifacts/offline-test-results',
  testDir: './e2e',
  testMatch: '**/offline.spec.ts',
  timeout: 90000,
  expect: { timeout: 20000 },
  workers: 1,
  use: {
    baseURL: 'http://127.0.0.1:4183',
    channel,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  webServer: {
    command: 'node dist-server/index.js',
    url: 'http://127.0.0.1:4183/health',
    reuseExistingServer: false,
    env: {
      PORT: '4183',
      HOST: '127.0.0.1',
      NODE_ENV: 'production',
      FOUR_AUTH_FILE: 'artifacts/offline-test/accounts.json',
      FOUR_STATS_FILE: 'artifacts/offline-test/statistics.sqlite',
    },
  },
});
