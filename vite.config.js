import { defineConfig } from 'vite'
import elm from 'vite-plugin-elm'
import path from 'path'

const commitSha =
  process.env.WORKERS_CI_COMMIT_SHA ||
  process.env.CF_PAGES_COMMIT_SHA ||
  process.env.GITHUB_SHA ||
  'dev'
const sha = commitSha.slice(0, 8)

// The only two places an API hostname may appear in this repo's client build.
// Everything else (Elm HTTP modules, src/main.js) reads the resolved value
// through `AppConfig.backendUrl`, which is baked from `__BACKEND_URL__` below.
const PROD_API = 'https://api.ternpike.com'
const STAGING_API = 'https://ternpike-auth-staging.dwightdoane.workers.dev'

const ciBranch = process.env.WORKERS_CI_BRANCH || process.env.CF_PAGES_BRANCH || ''

// Precedence:
//   1. VITE_BACKEND_URL — explicit wins (`npm run dev:staging`, `npm run build:staging`).
//   2. No CI branch — a local build. Stays on prod so `npm run deploy` can't
//      silently ship a staging-pointed bundle to app.ternpike.com.
//   3. CI branch `main` — the app.ternpike.com deploy. Prod.
//   4. Any other CI branch — the `staging` branch and every PR/preview build.
//      Staging, so previews never read or write production billing/tier data.
const backendUrl =
  process.env.VITE_BACKEND_URL ||
  (ciBranch === '' || ciBranch === 'main' ? PROD_API : STAGING_API)

// Surface the choice in the build log — a wrong-env deploy should be visible
// here rather than discovered on device.
console.log(`[ternpike] backendUrl=${backendUrl} (branch=${ciBranch || '<local>'})`)

export default defineConfig({
  base: '/',
  server: {
    port: 3000,
    strictPort: true,
    proxy: { '/auth': 'http://localhost:4000' },
  },
  plugins: [
    elm(),
    {
      name: 'stamp-sw-cache-name',
      apply: 'build',
      async writeBundle() {
        const fs = await import('node:fs/promises')
        const path = await import('node:path')
        const swPath = path.resolve('dist/sw.js')
        const assetsDir = path.resolve('dist/assets')
        const assetFiles = await fs.readdir(assetsDir).catch(() => [])
        const precacheUrls = assetFiles.map(f => `/assets/${f}`)
        const src = await fs.readFile(swPath, 'utf8')
        const stamped = src
          .replace("'__CACHE_VERSION__'", JSON.stringify(`ternpike-${sha}`))
          .replace("'__PRECACHE_URLS__'", JSON.stringify(precacheUrls))
        await fs.writeFile(swPath, stamped)
      },
    },
  ],
  resolve: {
    alias: {
      pouchdb: path.resolve('./node_modules/pouchdb/dist/pouchdb.js'),
    },
  },
  define: {
    __BACKEND_URL__: JSON.stringify(backendUrl),
    __BUILD_SHA__: JSON.stringify(commitSha),
  },
  build: {
    outDir: 'dist',
    rollupOptions: {
      output: {
        entryFileNames: `assets/[name].${sha}.js`,
        chunkFileNames: `assets/[name].${sha}.js`,
        assetFileNames: `assets/[name].${sha}.[ext]`,
      },
    },
  },
})
