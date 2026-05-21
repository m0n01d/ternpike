import { cp, rm } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const here = dirname(fileURLToPath(import.meta.url))
const src = join(here, 'src')
const dist = join(here, 'dist')

await rm(dist, { recursive: true, force: true })
await cp(src, dist, { recursive: true })

console.log(`built marketing/dist from marketing/src`)
