import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const loadEnvFile = (): Record<string, string> => {
  const candidates = [
    process.env.TERNPIKE_ADMIN_ENV || '',
    join(process.cwd(), '.env'),
    join(process.cwd(), 'scripts/admin/.env'),
  ].filter(Boolean)
  for (const path of candidates) {
    try {
      const raw = readFileSync(path, 'utf8')
      const out: Record<string, string> = {}
      for (const line of raw.split('\n')) {
        const m = line.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*?)\s*$/)
        if (!m) continue
        out[m[1]] = m[2].replace(/^"(.*)"$/, '$1')
      }
      return out
    } catch {
      // try next
    }
  }
  return {}
}

const fileEnv = loadEnvFile()

export const config = {
  apiUrl:
    process.env.TERNPIKE_API ||
    fileEnv.TERNPIKE_API ||
    'http://localhost:4000',
  adminSecret: process.env.ADMIN_SECRET || fileEnv.ADMIN_SECRET || '',
}

const headers = () => {
  const h: Record<string, string> = {
    'Content-Type': 'application/json',
  }
  if (config.adminSecret) h['x-admin-secret'] = config.adminSecret
  return h
}

export class ApiError extends Error {
  status: number
  body: unknown
  constructor(status: number, body: unknown, message: string) {
    super(message)
    this.status = status
    this.body = body
  }
}

const request = async <T,>(
  method: string,
  path: string,
  body?: unknown,
): Promise<T> => {
  const res = await fetch(`${config.apiUrl}${path}`, {
    method,
    headers: headers(),
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  const text = await res.text()
  let parsed: unknown = null
  try {
    parsed = text ? JSON.parse(text) : null
  } catch {
    parsed = text
  }
  if (!res.ok) {
    throw new ApiError(res.status, parsed, `${method} ${path} ${res.status}`)
  }
  return parsed as T
}

export type Tier = 'tern' | 'osprey' | 'trailblazer'

export type User = { email: string; tier: Tier }

export type UserDetail = {
  email: string
  tier: Tier
  personalDb: string
  docCount: number | null
  sizeBytes: number | null
  sharedTrips: Array<{ id: string; name: string; dbName: string }>
}

export type Db = { name: string; docCount: number | null; sizeBytes: number | null }

export type Doc = Record<string, unknown> & { _id: string; _rev?: string }

export type SharedTrip = {
  id: string
  name: string
  dbName: string
  billingOwner: string
  billingStatus: string
  members: string[]
  createdAt?: string
  error?: string
}

export const api = {
  ping: () =>
    request<{ ok: true; users: User[] }>('GET', '/admin/users'),

  listUsers: () =>
    request<{ ok: true; users: User[] }>('GET', '/admin/users'),

  getUser: (email: string) =>
    request<{ ok: true } & UserDetail>(
      'GET',
      `/admin/users/${encodeURIComponent(email)}`,
    ),

  createUser: (email: string, tier: Tier) =>
    request<{ ok: true; email: string; tier: Tier; dbName: string }>(
      'POST',
      '/admin/users',
      { email, tier },
    ),

  setTier: (email: string, tier: Tier) =>
    request<{ ok: true }>('PUT', `/admin/users/${encodeURIComponent(email)}/tier`, {
      tier,
    }),

  deleteUser: (email: string) =>
    request<{ ok: true }>('DELETE', `/admin/users/${encodeURIComponent(email)}`),

  listDbs: () =>
    request<{ ok: true; dbs: Db[] }>('GET', '/admin/dbs'),

  listDocs: (db: string, opts: { limit?: number; skip?: number; prefix?: string } = {}) => {
    const params = new URLSearchParams()
    if (opts.limit !== undefined) params.set('limit', String(opts.limit))
    if (opts.skip !== undefined) params.set('skip', String(opts.skip))
    if (opts.prefix) params.set('prefix', opts.prefix)
    const qs = params.toString()
    return request<{ ok: true; total: number | null; offset: number | null; docs: Doc[] }>(
      'GET',
      `/admin/dbs/${encodeURIComponent(db)}/docs${qs ? '?' + qs : ''}`,
    )
  },

  getDoc: (db: string, id: string) =>
    request<{ ok: true; doc: Doc }>(
      'GET',
      `/admin/dbs/${encodeURIComponent(db)}/docs/${encodeURIComponent(id)}`,
    ),

  putDoc: (db: string, id: string, doc: Doc) =>
    request<{ ok: true; rev: string }>(
      'PUT',
      `/admin/dbs/${encodeURIComponent(db)}/docs/${encodeURIComponent(id)}`,
      doc,
    ),

  deleteDoc: (db: string, id: string, rev: string) =>
    request<{ ok: true }>(
      'DELETE',
      `/admin/dbs/${encodeURIComponent(db)}/docs/${encodeURIComponent(id)}?rev=${encodeURIComponent(rev)}`,
    ),

  voidDoc: (db: string, docId: string) =>
    request<{ ok: true; voidId: string }>(
      'POST',
      `/admin/dbs/${encodeURIComponent(db)}/void`,
      { docId },
    ),

  listSharedTrips: () =>
    request<{ ok: true; sharedTrips: SharedTrip[] }>(
      'GET',
      '/admin/sharedtrips',
    ),

  seedExpenses: (email: string, tripCount: number, expensesPerTrip: number) =>
    request<{ ok: true; written: number }>('POST', '/admin/seed/expenses', {
      email,
      tripCount,
      expensesPerTrip,
    }),
}
