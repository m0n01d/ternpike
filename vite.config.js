import { defineConfig } from 'vite'
import elm from 'vite-plugin-elm'
import path from 'path'

const commitSha =
  process.env.WORKERS_CI_COMMIT_SHA ||
  process.env.CF_PAGES_COMMIT_SHA ||
  process.env.GITHUB_SHA ||
  'dev'
const sha = commitSha.slice(0, 8)

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
