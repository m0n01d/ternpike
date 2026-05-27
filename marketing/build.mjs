import { cp, mkdir, readFile, readdir, rm, stat, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { dirname, extname, join } from 'node:path'
import nunjucks from 'nunjucks'
import yaml from 'js-yaml'
import postcss from 'postcss'
import tailwindcss from '@tailwindcss/postcss'

const here = dirname(fileURLToPath(import.meta.url))
const src = join(here, 'src')
const dist = join(here, 'dist')
const repoRoot = join(here, '..')

await rm(dist, { recursive: true, force: true })
await mkdir(dist, { recursive: true })

const contentRaw = await readFile(join(src, 'content.yaml'), 'utf8')
const content = yaml.load(contentRaw)

const env = nunjucks.configure(src, { autoescape: true, noCache: true })
const pages = ['index', 'privacy', 'terms']
for (const page of pages) {
  const html = env.render(`${page}.njk`, content)
  await writeFile(join(dist, `${page}.html`), html)
}

const siteUrl = 'https://ternpike.com'
const buildDate = new Date().toISOString().slice(0, 10)
const sitemap = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${pages
  .map((page) => {
    const path = page === 'index' ? '/' : `/${page}`
    return `  <url>\n    <loc>${siteUrl}${path}</loc>\n    <lastmod>${buildDate}</lastmod>\n  </url>`
  })
  .join('\n')}
</urlset>
`
await writeFile(join(dist, 'sitemap.xml'), sitemap)

const cssRaw = await readFile(join(src, 'styles.css'), 'utf8')
const result = await postcss([tailwindcss()]).process(cssRaw, {
  from: join(src, 'styles.css'),
  to: join(dist, 'styles.css'),
})
await writeFile(join(dist, 'styles.css'), result.css)

await cp(join(src, 'main.js'), join(dist, 'main.js'))

// Static passthrough — copy anything in src/ that isn't a template/source.
const skipExts = new Set(['.njk', '.yaml', '.yml'])
const skipNames = new Set(['styles.css', 'main.js', 'partials', 'content.yaml'])

for (const entry of await readdir(src)) {
  if (skipNames.has(entry)) continue
  if (skipExts.has(extname(entry))) continue
  const from = join(src, entry)
  const info = await stat(from)
  if (info.isDirectory()) {
    await cp(from, join(dist, entry), { recursive: true })
  } else {
    await cp(from, join(dist, entry))
  }
}

// Forward favicons / static assets shared with the app from /src/.
const appAssetsDir = join(repoRoot, 'src')
for (const entry of await readdir(appAssetsDir)) {
  const ext = extname(entry).toLowerCase()
  if (['.ico', '.png', '.svg', '.webp', '.jpg', '.jpeg'].includes(ext)) {
    await cp(join(appAssetsDir, entry), join(dist, entry))
  }
}

console.log('built marketing/dist from marketing/src')
