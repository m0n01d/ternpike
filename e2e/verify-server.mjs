// Minimal static file server with SPA fallback for the backend-free Verify DOM
// tier. Serves dist/ and falls back to index.html for extension-less paths (the
// client-side /verify/:unit/:fixture routes). No deps — `vite preview` is
// avoided because rolldown-vite's preview crashes in some sandboxed CI.
import { readFile } from 'node:fs/promises'
import http from 'node:http'
import { dirname, extname, join, normalize } from 'node:path'
import { fileURLToPath } from 'node:url'

// Resolve dist/ relative to this file (e2e/../dist), so the server works no
// matter what cwd Playwright spawns it from.
const dist = join(dirname(fileURLToPath(import.meta.url)), '..', 'dist')
const port = Number(process.env.VERIFY_PORT || 4319)

const contentTypes = {
  '.css': 'text/css',
  '.html': 'text/html; charset=utf-8',
  '.ico': 'image/x-icon',
  '.js': 'text/javascript',
  '.json': 'application/json',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.webmanifest': 'application/manifest+json',
}

const indexHtml = join(dist, 'index.html')

const server = http.createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname)
    // Extension-less paths are SPA routes → serve index.html.
    const target = !extname(pathname) || pathname === '/'
      ? indexHtml
      : normalize(join(dist, pathname))

    let file = target
    let data
    try {
      data = await readFile(file)
    } catch {
      file = indexHtml
      data = await readFile(indexHtml)
    }
    res.setHeader('content-type', contentTypes[extname(file)] || 'application/octet-stream')
    res.end(data)
  } catch (err) {
    res.statusCode = 500
    res.end(String(err))
  }
})

server.listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`verify static server listening on http://localhost:${port}`)
})
