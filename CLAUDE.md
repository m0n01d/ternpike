# Alaska Expense Tracker — Claude Notes

## Stack
- Elm 0.19.1, single file: `src/Main.elm`
- Google Sheets backend via REST API
- Anthropic API for OCR (receipt scanning)
- Tailwind CSS via Play CDN
- GitHub Pages deployment (CI triggers on push to main)
- Elm binary: `/root/.npm/_npx/5bf0f3665e572b9f/node_modules/elm/bin/elm`

## Compile before committing
Always run the compiler before staging:
```
/root/.npm/_npx/5bf0f3665e572b9f/node_modules/elm/bin/elm make src/Main.elm --output=main.js
```

## Git discipline — do NOT repeat this mistake
**Never use `git checkout <branch> -- <file>` to resolve a stash conflict.**
That silently replaces the file with the committed branch version, discarding
all stash changes. The correct sequence when a stash pop conflicts:

1. Commit (or at least stage) work-in-progress BEFORE switching branches.
2. If a stash pop conflicts, resolve the conflict markers manually, or use
   `git checkout --theirs <file>` / `git checkout --ours <file>` deliberately.
3. If a stash is accidentally dropped, recover it:
   `git fsck --lost-found` → find the dangling commit → `git show <sha>:<file>`

## Model architecture (GuestModel / AuthModel split)
`Model = GuestModel GuestState | AuthModel AuthState`
- Compiler enforces that auth-only pages (Scan, Add, Ledger, Stats) cannot
  be reached while signed out.
- 401 from any HTTP call → `GuestModel (toGuestState SessionExpired as_) + clearStorage ()`.
  No silent re-auth — the app is unverified by Google so tokens expire aggressively.
- Auth error messages live in `GuestReason` (FreshGuest | SessionExpired | MissingConfig),
  NOT in `model.error`.

## Elm style guide
- **Alphabetize** all record fields and all type constructor lists.
  Apply to every new type and every edit of an existing type.

## Sheet columns
A=id, B=date, C=amount, D=category, E=note, F=merchant, G=createdAt, H=lat, I=lon, J=longNote
Range: A:J
