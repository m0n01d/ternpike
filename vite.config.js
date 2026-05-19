import { defineConfig } from 'vite'
import elm from 'vite-plugin-elm'

const sha = (process.env.GITHUB_SHA || 'dev').slice(0, 8)

export default defineConfig({
  plugins: [elm()],
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
