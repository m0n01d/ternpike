import { mkdirSync, readFileSync, writeFileSync, existsSync, unlinkSync } from 'node:fs'
import { dirname, resolve } from 'node:path'

const STATE_PATH = resolve(__dirname, '../.state/setup.json')

export type HarnessState = {
  couchAdminPassword: string
  couchAdminUser: string
  couchUrl: string
  resendMockUrl: string
  serverPort: number
  serverSecret: string
  vitePort: number
}

export const writeHarnessState = (state: HarnessState): void => {
  mkdirSync(dirname(STATE_PATH), { recursive: true })
  writeFileSync(STATE_PATH, JSON.stringify(state, null, 2))
}

export const readHarnessState = (): HarnessState => {
  if (!existsSync(STATE_PATH)) {
    throw new Error(
      `harness state file missing at ${STATE_PATH} — did globalSetup run?`,
    )
  }
  return JSON.parse(readFileSync(STATE_PATH, 'utf8')) as HarnessState
}

export const clearHarnessState = (): void => {
  if (existsSync(STATE_PATH)) {
    unlinkSync(STATE_PATH)
  }
}
