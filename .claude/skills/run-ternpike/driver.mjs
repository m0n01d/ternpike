#!/usr/bin/env node
// Smoke driver for ternpike. Assumes `npm run dev:vite` is running on :3000.
//
//   node .claude/skills/run-ternpike/driver.mjs                    # landing page smoke
//   node .claude/skills/run-ternpike/driver.mjs <route> <outpath>  # arbitrary route screenshot
//
// For auth-gated routes (/trips, /trip/*, /settings) use the playwright-ui
// skill instead — it handles the seed + IndexedDB auth_creds stub.

import { chromium } from 'playwright'
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname } from 'node:path'

const route = process.argv[2] ?? '/'
const out = process.argv[3] ?? '/tmp/shots/ternpike-smoke.png'

mkdirSync(dirname(out), { recursive: true })

const browser = await chromium.launch()
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } })
const page = await ctx.newPage()

const errors = []
page.on('pageerror', e => errors.push(`pageerror: ${e.message}`))
page.on('console', m => {
  if (m.type() === 'error') errors.push(`console.error: ${m.text()}`)
})

const url = `http://localhost:3000${route}`
const resp = await page.goto(url, { timeout: 15000 })
if (!resp || !resp.ok()) {
  console.error(`FAIL: GET ${url} → ${resp?.status() ?? 'no response'}`)
  await browser.close()
  process.exit(1)
}
await page.waitForLoadState('networkidle')
await page.waitForTimeout(800)

const title = await page.title()
const hasApp = await page.locator('#root, [data-elm]').count()
const bodyText = (await page.locator('body').innerText()).slice(0, 200)

await page.screenshot({ path: out })
await browser.close()

if (errors.length) {
  console.error('browser errors:')
  for (const e of errors) console.error('  ' + e)
}

const ok = title.length > 0 && bodyText.length > 0
console.log(JSON.stringify({ url, title, sample: bodyText, screenshot: out, ok }, null, 2))
process.exit(ok ? 0 : 1)
