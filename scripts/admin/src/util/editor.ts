import { spawn } from 'node:child_process'
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

export const editJson = async (
  initial: unknown,
  hint = 'doc',
): Promise<unknown> => {
  const editor = process.env.EDITOR || process.env.VISUAL || 'vi'
  const dir = mkdtempSync(join(tmpdir(), 'ternpike-admin-'))
  const file = join(dir, `${hint}.json`)
  writeFileSync(file, JSON.stringify(initial, null, 2) + '\n', 'utf8')

  await new Promise<void>((resolve, reject) => {
    const child = spawn(editor, [file], { stdio: 'inherit' })
    child.on('exit', (code) => {
      if (code === 0) resolve()
      else reject(new Error(`${editor} exited ${code}`))
    })
    child.on('error', reject)
  })

  const raw = readFileSync(file, 'utf8')
  return JSON.parse(raw)
}
