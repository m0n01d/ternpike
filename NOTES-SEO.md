# SEO notes

Operational notes for the marketing site (`ternpike.com`). The actual SEO surface lives in `marketing/src/_layout.njk` (canonical, OG, Twitter, JSON-LD Organization), `marketing/src/index.njk` (JSON-LD SoftwareApplication), `marketing/src/robots.txt`, and `marketing/build.mjs` (`pages` array + sitemap generation).

## Adding a new page

1. Add a `.njk` template under `marketing/src/` that extends `_layout.njk`.
2. Add a new entry to the `pages` array in `marketing/build.mjs` with `slug`, `url`, `title`, `description`.

That's it — the layout picks up the metadata and the sitemap regenerates. Per-page OG image overrides go on the page entry as `ogImage`.

## Per-page OG image

`_layout.njk` falls back to `/img/og-default.png` (1200×630, source SVG at `marketing/src/img/og-default.svg`). To override on a single page, set `ogImage` on its entry in `pages`. The SVG can be re-rasterized with:

```
sips -s format png marketing/src/img/og-default.svg --out marketing/src/img/og-default.png
```

(Avoid `qlmanage` — it produces square output regardless of viewBox.)

## The root-URL "empty body" report — non-issue

An external SEO audit reported `https://ternpike.com/` returning an empty body to bots while `/index.html` returned the full page. **This could not be reproduced.** Behavior observed on 2026-05-27:

| URL | Response |
|---|---|
| `https://ternpike.com/` | `HTTP/2 200`, full HTML (~40 KB), across Googlebot UA, Mozilla UA, no-UA, and cache-busted queries |
| `https://ternpike.com/index.html` | `HTTP/2 307` redirect to `/` |

The `307` on `/index.html` is **standard Cloudflare Pages behavior** — Pages strips the `.html` extension to avoid duplicate-content SEO penalties. The audit tool likely did not follow redirects and treated the `307`'s near-empty body as the page's content, possibly inverting the description in its report.

There is no dashboard knob to change this in the current setup, and the canonical URL is `/` (now declared via `<link rel="canonical">` on every page), so search engines will correctly converge on `/`.

If the report recurs from a fresh audit, the order of investigation is:

1. Re-run `curl -sI` + body check from a clean network; capture `cf-cache-status` and `cf-ray`.
2. Check `marketing/dist/` for an unexpected `_redirects` or `_headers` file (the build does not currently emit one).
3. Check the Cloudflare Pages project's "Bulk Redirects" and "Cache Rules" dashboards.
4. If still nothing, file an issue with the captured headers — there's nothing to fix in this repo unless a real divergence appears.
