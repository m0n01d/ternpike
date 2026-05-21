import { createServer, type Server } from 'node:http'

export type CapturedEmail = {
  capturedAt: string
  from: string
  html?: string
  subject: string
  text?: string
  to: string
}

export type ResendMockHandle = {
  baseUrl: string
  port: number
  stop: () => Promise<void>
}

export type ResendMockClient = {
  baseUrl: string
  all: () => Promise<CapturedEmail[]>
  clear: () => Promise<void>
  lastSentTo: (email: string) => Promise<CapturedEmail | null>
  ping: () => Promise<boolean>
}

const drainBody = (req: import('node:http').IncomingMessage): Promise<string> =>
  new Promise((resolve, reject) => {
    const chunks: Buffer[] = []
    req.on('data', (chunk) => chunks.push(chunk))
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')))
    req.on('error', reject)
  })

export const startResendMock = async (): Promise<ResendMockHandle> => {
  const captured: CapturedEmail[] = []

  const server: Server = createServer(async (req, res) => {
    const url = req.url || '/'
    try {
      if (req.method === 'POST' && url === '/emails') {
        const raw = await drainBody(req)
        const body = raw ? JSON.parse(raw) : {}
        const email: CapturedEmail = {
          capturedAt: new Date().toISOString(),
          from: String(body.from || ''),
          html: typeof body.html === 'string' ? body.html : undefined,
          subject: String(body.subject || ''),
          text: typeof body.text === 'string' ? body.text : undefined,
          to: Array.isArray(body.to) ? String(body.to[0]) : String(body.to || ''),
        }
        captured.push(email)
        res.writeHead(200, { 'Content-Type': 'application/json' })
        res.end(JSON.stringify({ id: `mock-${captured.length}` }))
        return
      }

      if (req.method === 'GET' && url === '/__captured') {
        res.writeHead(200, { 'Content-Type': 'application/json' })
        res.end(JSON.stringify(captured))
        return
      }

      if (req.method === 'POST' && url === '/__clear') {
        captured.length = 0
        res.writeHead(204)
        res.end()
        return
      }

      if (req.method === 'GET' && url === '/__ping') {
        res.writeHead(200, { 'Content-Type': 'application/json' })
        res.end(JSON.stringify({ ok: true }))
        return
      }

      res.writeHead(404)
      res.end()
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ error: String(err) }))
    }
  })

  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
  const address = server.address()
  if (!address || typeof address === 'string') {
    throw new Error('mock Resend server did not bind to an address')
  }
  const port = address.port
  const baseUrl = `http://127.0.0.1:${port}`

  return {
    baseUrl,
    port,
    stop: () =>
      new Promise((resolve, reject) => {
        server.close((err) => (err ? reject(err) : resolve()))
      }),
  }
}

export const makeResendClient = (baseUrl: string): ResendMockClient => ({
  baseUrl,
  all: async () => {
    const res = await fetch(`${baseUrl}/__captured`)
    if (!res.ok) throw new Error(`/__captured failed: ${res.status}`)
    return (await res.json()) as CapturedEmail[]
  },
  clear: async () => {
    await fetch(`${baseUrl}/__clear`, { method: 'POST' })
  },
  lastSentTo: async (email) => {
    const all = (await (await fetch(`${baseUrl}/__captured`)).json()) as CapturedEmail[]
    const match = [...all].reverse().find((m) => m.to.toLowerCase() === email.toLowerCase())
    return match || null
  },
  ping: async () => {
    try {
      const res = await fetch(`${baseUrl}/__ping`)
      return res.ok
    } catch {
      return false
    }
  },
})
