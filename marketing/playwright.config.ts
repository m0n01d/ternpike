import { defineConfig, devices } from '@playwright/test'

const port = Number(process.env.MARKETING_TEST_PORT || 8788)

export default defineConfig({
  testDir: './test',
  fullyParallel: false,
  outputDir: './.results',
  reporter: process.env.CI ? [['list'], ['html', { open: 'never', outputFolder: './.results/html' }]] : [['list']],
  retries: 0,
  timeout: 60_000,
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  webServer: {
    command: `npm run build && npx wrangler dev --port ${port}`,
    reuseExistingServer: !process.env.CI,
    timeout: 90_000,
    url: `http://127.0.0.1:${port}`,
  },
  workers: 1,
  projects: [
    {
      name: 'desktop',
      use: { ...devices['Desktop Chrome'], viewport: { width: 1280, height: 800 } },
    },
  ],
})
