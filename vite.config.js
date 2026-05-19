import { defineConfig } from 'vite'
import elm from 'vite-plugin-elm'
import path from 'path'

const sha = (process.env.GITHUB_SHA || 'dev').slice(0, 8)
const base = process.env.GITHUB_ACTIONS ? '/ternpike/' : '/'

export default defineConfig({
  base,
  plugins: [elm()],
  resolve: {
    alias: {
      pouchdb: path.resolve('./node_modules/pouchdb/dist/pouchdb.js'),
    },
  },
  define: {
    __BUILD_SHA__: JSON.stringify(process.env.GITHUB_SHA || 'dev'),
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
