import { defineConfig } from 'vite'
import elm from 'vite-plugin-elm'
import path from 'path'

const commitSha = process.env.CF_PAGES_COMMIT_SHA || process.env.GITHUB_SHA || 'dev'
const sha = commitSha.slice(0, 8)

export default defineConfig({
  base: '/',
  server: {
    port: 3000,
    strictPort: true,
    proxy: { '/auth': 'http://localhost:4000' },
  },
  plugins: [elm()],
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
