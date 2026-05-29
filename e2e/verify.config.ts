import path from 'node:path'
import { defineConfig, devices } from '@playwright/test'

const isCI = !!process.env.CI
const PORT = Number(process.env.VERIFY_PORT || 4319)
// Playwright runs webServer.command with cwd = this config's directory (e2e/),
// so point it back at the repo root explicitly. The server itself also resolves
// dist/ relative to its own file, so it's cwd-independent regardless.
const repoRoot = path.resolve(__dirname, '..')

// Backend-free DOM tier for the Verify track. Unlike playwright.config.ts there
// is NO globalSetup — no CouchDB container, no wrangler, no mock Resend. The
// /verify/:unit/:fixture routes mount seeded fixture models client-side and JS
// skips attachPouch for them, so a plain `vite preview` of dist/ is all we need.
export default defineConfig({
  testDir: './specs',
  testMatch: '**/verify.spec.ts',
  forbidOnly: isCI,
  fullyParallel: true,
  outputDir: path.join(repoRoot, 'e2e/.results-verify'),
  reporter: [['list']],
  retries: 0,
  timeout: 30_000,
  webServer: {
    command: `node e2e/verify-server.mjs`,
    cwd: repoRoot,
    env: { VERIFY_PORT: String(PORT) },
    port: PORT,
    reuseExistingServer: !isCI,
    timeout: 60_000,
  },
  use: {
    baseURL: `http://localhost:${PORT}`,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  projects: [
    {
      name: 'verify',
      use: {
        ...devices['Pixel 7'],
        viewport: { width: 390, height: 844 },
      },
    },
  ],
})
