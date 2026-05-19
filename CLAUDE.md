# Alaska Expense Tracker — Claude Notes

## Stack
- Elm 0.19.1, single file: `src/Main.elm`
- Google Sheets backend via REST API
- Anthropic API for OCR (receipt scanning)
- Tailwind CSS via Play CDN
- GitHub Pages deployment (CI triggers on push to main)
- Elm binary: `elm` (via asdf at `~/.asdf/shims/elm`)

## Compile before committing
Always run the compiler before staging:
```
elm make src/Main.elm --output=main.js
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
  Always fully qualify imports. If you touch a module, or a function, and its imports are NOT fully qualified you should refactor the function or module to be fully qualified
  You can expose the type, but not "(..)" all.

  for example : 
  ```elm
  // don't do
  import Json.Decode as D
  import Html exposing exposing (..)
  import Html.Attributes exposing (..)

  text "hello world"

  // do 
  import Json.Decode 
  import Html exposing  (Html)
  import Html.Attributes
  Html.div [Html.Attrtibutes.class "tw-flex" ] [Html.text "hello world"]
  ```

## Sheet columns
A=id, B=date, C=amount, D=category, E=note, F=merchant, G=createdAt, H=lat, I=lon, J=longNote
Range: A:J
