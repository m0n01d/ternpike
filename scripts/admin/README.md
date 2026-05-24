# ternpike-admin

k9s-style TUI for managing Ternpike users, CouchDB docs, and shared trips.

## Setup

```sh
cd scripts/admin
npm install
cp .env.example .env
# edit .env: TERNPIKE_API + ADMIN_SECRET
```

The server side needs `ADMIN_SECRET` in `server/.dev.vars` (local) or as a
Wrangler secret (`wrangler secret put ADMIN_SECRET`, production).

## Run

```sh
npm run admin       # from repo root
# or
cd scripts/admin && npm start
```

## Keys

- `↑`/`↓` — move
- `Enter` — select / drill in
- `Esc` — back
- `t` — set tier (on a user row)
- `n` — new user (on the users screen)
- `d` — delete user / doc (double-confirm)
- `v` — void a trip or expense doc
- `e` — edit doc in $EDITOR
- `s` — seed sample expenses for a user
- `/` — filter
- `q` — quit

## Notes

`scripts/admin/` is intentionally its own npm package — its Ink/React
dependency tree shouldn't pollute the main bundle.
