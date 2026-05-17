# Alaska Expense Tracker

Mobile-first expense tracker for the Florida → Juneau road trip. Google Sheets is the database. Runs entirely in the browser — no server.

## Setup

### 1. Google Cloud project

1. Go to [console.cloud.google.com](https://console.cloud.google.com) → New project
2. Enable **Google Sheets API** (APIs & Services → Library)
3. Create an **OAuth 2.0 Client ID** (APIs & Services → Credentials → Create Credentials → OAuth client ID → Web application)
4. Add authorized JavaScript origins:
   - `http://localhost:3000` (for local dev)
   - Your production domain when deployed
5. Copy the **Client ID** — you'll paste it into Settings

### 2. Google Sheet

1. Create a new Google Sheet
2. Rename the first tab to exactly: **`Expenses`** (case-sensitive)
3. Add a header row in row 1:
   ```
   id | date | amount | category | note | merchant | created_at
   ```
4. Copy the spreadsheet ID from the URL — it's the long string between `/d/` and `/edit`

### 3. Anthropic API key (for receipt OCR)

Get one at [console.anthropic.com](https://console.anthropic.com). The app calls Claude directly from the browser — your key is stored only in `localStorage`.

### 4. Run locally

```bash
npx elm make src/Main.elm --output=main.js
python3 -m http.server 3000
```

Open `http://localhost:3000` in your browser.

### 5. First launch

1. Open Settings (⚙ icon) and enter:
   - Google Client ID
   - Sheet ID
   - Anthropic API key (optional — for receipt scanning)
2. Click **Sign in with Google** → authorize the Spreadsheets scope
3. You're in

## Usage

| Tab | What it does |
|-----|-------------|
| **Scan** | Photo → Claude reads the receipt → pre-fills the form |
| **Add** | Manual entry — amount, category, note, date |
| **Ledger** | All entries grouped by date, newest first. Tap ✕ to delete |
| **Stats** | Totals, category bar chart, top 5 expenses |
| **⚙** | Settings — keys, sheet ID, trip start date |

## Categories

`fuel` · `food` · `camp` · `ferry` · `gear` · `misc`

## Build

```bash
npx elm make src/Main.elm --output=main.js        # development
npx elm make src/Main.elm --output=main.js --optimize  # production (smaller)
```

Deploy by serving `index.html` + `main.js` from any static host (Netlify, GitHub Pages, S3).

## Notes

- Token is stored in `localStorage` — Sign Out clears it
- If the token expires (typically 1 hour), Sign Out and sign back in
- The Sheet ID and API key survive sign-out — they're stored separately
- Delete physically removes the row via Sheets `batchUpdate` — row indices shift, so the ledger auto-refreshes after every delete
