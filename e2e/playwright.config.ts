import { defineConfig, devices } from '@playwright/test'

const isCI = !!process.env.CI

export default defineConfig({
  testDir: './specs',
  forbidOnly: isCI,
  fullyParallel: false,
  globalSetup: require.resolve('./global-setup.ts'),
  globalTeardown: require.resolve('./global-teardown.ts'),
  outputDir: './.results',
  reporter: isCI
    ? [['list'], ['html', { open: 'never', outputFolder: './.results-html' }]]
    : [['list']],
  retries: isCI ? 1 : 0,
  snapshotDir: './screenshots',
  // Create missing snapshots on first run (e.g. after a rebrand deletes stale
  // goldens). Existing snapshots are still compared strictly so regressions are
  // caught. Only updates when the file is literally absent.
  updateSnapshots: 'missing',
  timeout: 60_000,
  use: {
    // Mirrors `E2E_VITE_PORT` in `global-setup.ts`. Defaults to 3000 (CI).
    baseURL: `http://localhost:${process.env.E2E_VITE_PORT || 3000}`,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
    video: 'retain-on-failure',
  },
  workers: 1,
  projects: [
    {
      name: 'mobile',
      use: {
        ...devices['Pixel 7'],
        viewport: { width: 390, height: 844 },
      },
    },
    {
      name: 'desktop',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1280, height: 800 },
      },
    },
  ],
})
