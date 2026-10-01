import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { chromium, defineConfig, devices, firefox, webkit } from '@playwright/test';

const fullMatrix = process.env.FULL_BROWSER_MATRIX === '1';
const edgePath = join(
  process.env['PROGRAMFILES(X86)'] ?? '',
  'Microsoft',
  'Edge',
  'Application',
  'msedge.exe',
);
const channel =
  process.env.PLAYWRIGHT_CHANNEL ??
  (!existsSync(chromium.executablePath()) && existsSync(edgePath) ? 'msedge' : undefined);

export default defineConfig({
  testDir: './e2e',
  timeout: 45_000,
  expect: { timeout: 10_000 },
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: 'http://127.0.0.1:5173',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    viewport: { width: 1440, height: 1000 },
  },
  projects: [
    {
      name: 'chromium',
      use: { browserName: 'chromium', channel },
      testIgnore: '**/mobile.spec.ts',
    },
    ...(fullMatrix || existsSync(firefox.executablePath())
      ? [
          {
            name: 'firefox',
            use: { browserName: 'firefox' as const },
            testIgnore: '**/mobile.spec.ts',
          },
        ]
      : []),
    ...(fullMatrix || existsSync(webkit.executablePath())
      ? [
          {
            name: 'webkit',
            use: { browserName: 'webkit' as const },
            testIgnore: '**/mobile.spec.ts',
          },
        ]
      : []),
    {
      name: 'mobile',
      use: {
        ...devices['Pixel 7'],
        channel,
        viewport: { width: 390, height: 844 },
      },
      testMatch: '**/mobile.spec.ts',
    },
  ],
  webServer: {
    command: 'npm run dev -- --host 127.0.0.1 --port 5173 --strictPort',
    url: 'http://127.0.0.1:5173',
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
  },
});
