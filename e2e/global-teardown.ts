import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync, unlinkSync } from 'node:fs'
import { resolve } from 'node:path'

import { clearHarnessState } from './utils/state'

const ROOT = resolve(__dirname, '..')
const PIDFILE = resolve(ROOT, 'e2e/.state/processes.json')

type ProcessRecord = { name: string; pid: number }

const killTree = (pid: number, signal: NodeJS.Signals): void => {
  try {
    // Negative pid signals the whole process group; works because globalSetup
    // spawns with detached:true.
    process.kill(-pid, signal)
  } catch {
    try {
      process.kill(pid, signal)
    } catch {
      // already dead
    }
  }
}

export default async function globalTeardown(): Promise<void> {
  if (!existsSync(PIDFILE)) {
    clearHarnessState()
    return
  }
  const records = JSON.parse(readFileSync(PIDFILE, 'utf8')) as ProcessRecord[]
  for (const rec of records) {
    if (rec.name.startsWith('couch:')) {
      const containerId = rec.name.slice('couch:'.length)
      spawnSync('docker', ['rm', '-f', containerId], { stdio: 'ignore' })
      continue
    }
    if (rec.pid > 0) killTree(rec.pid, 'SIGTERM')
  }
  // Give services a moment to release ports before the next run.
  await new Promise((r) => setTimeout(r, 750))
  for (const rec of records) {
    if (rec.pid > 0) killTree(rec.pid, 'SIGKILL')
  }
  try {
    unlinkSync(PIDFILE)
  } catch {
    // ignore
  }
  clearHarnessState()
}
