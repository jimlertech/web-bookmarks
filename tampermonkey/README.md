# WebBookmarks Command Palette (Tampermonkey userscript)

A userscript that brings the WebBookmarks command palette to any page. It reaches the public API through Cloudflare Access; Tailscale is not required. Press
`Ctrl+Alt+/` to open it, search/filter bookmarks, and navigate.

## Opening while a page loads

The userscript runs at `document-start`, so the shortcut and Tampermonkey menu
command don't wait for the host page to finish loading. The palette can open
before the page has a head or body. Cached bookmarks appear immediately; without
a cache, the palette shows its loading state while the API request is pending.

If the document root doesn't exist yet, opening waits only for that root.
Pressing the shortcut again cancels the pending open.

Tampermonkey can't display the palette on browser-owned pages, before navigation
creates a document, or while the page blocks the browser's main thread.

## Architecture — one source of truth

The palette's **pure logic** (wildcard matching, number-selection parsing, URL
resolution, entry filtering, bookmark numbering, MRU) lives in a shared module,
**not** in this userscript:

```
src/WebBookmarks.Client/src/palette-core/   ← shared, tested (vitest)
```

Both surfaces consume it:

- the **React web app** (`CommandPalette.tsx`) imports it directly, and
- **this userscript** is **built** so the same module is bundled in.

So a fix to the filtering/matching/MRU logic is made **once** in `palette-core`
and both surfaces get it. Only host-specific code (DOM, `GM_*`, keyboard
handling, styling) is genuinely different between the two.

## Files

| File | Role |
|------|------|
| `src/palette.user.js` | **Source** — the userscript body; imports from `palette-core`. Edit this. |
| `src/header.txt` | The `==UserScript==` metadata block. **`@version` lives here.** |
| `build.mjs` | esbuild build: bundles the source + core, prepends `header.txt` as a banner. |
| `webbookmarks-palette.user.js` | **Generated output** — the shippable file. **Do not edit by hand** (it is overwritten on every build). |

## Production endpoint

The API endpoint is `https://web-bookmarks.jimlertech.com/api/bookmarks`. Cloudflare Access restricts the API and web app to Microsoft identities. Sign in at `https://web-bookmarks.jimlertech.com` in the same browser and browser profile as Tampermonkey. The userscript sends the browser's session cookies and does not need an API key or Tailscale.

If the session expires, the palette shows a sign-in button. Complete sign-in in the opened tab, then reopen the palette. Browser policies that block extension requests or session cookies can still prevent access.

## Build

```bash
cd tampermonkey
npm install        # first time only
npm run build      # regenerates webbookmarks-palette.user.js
```

## Tests

Run `npm test` in this folder for the API tests. After building, run
`npm test -- src/userscript-startup.test.js` in `src/WebBookmarks.Client`
for the bundled userscript's early-DOM, shortcut, cache and loading regressions.
Those tests reuse the client's existing Vitest and jsdom dependencies.
Run `Invoke-Pester .\Publish.Tests.ps1` for the publish-and-record checks.

## Distribution

The userscript ships as a **GitHub Release asset** in the JimlerTech repository.
The `@updateURL` / `@downloadURL` in `header.txt` point to the latest release.
Tampermonkey only auto-updates a client when `@version` **increases**.

Releases use the `tampermonkey-v<version>` tag pattern. The Gist previously used
for distribution is retained as a migration bridge for existing installs.

## Publish checklist (any userscript change)

1. Edit the **source** — `src/palette.user.js` for host-specific behavior, or
   `../src/WebBookmarks.Client/src/palette-core/*` for shared logic (run its
   vitest suite: `cd ../src/WebBookmarks.Client && npm test`).
2. **Bump `@version`** in `src/header.txt` (never in the generated file — it's
   overwritten).
3. **Build:** `npm run build` (regenerates `webbookmarks-palette.user.js`).
4. Commit and push **both** the source and the regenerated file.
5. From the repository root, **publish and record** the exact pushed commit:
   ```powershell
   .\tampermonkey\Publish.ps1 -Commit HEAD
   ```

The command requires PowerShell 7.5+, GitHub CLI repository access, the sibling
`solution-deploy` checkout and key-only SSH access to the release-record folder
on `jimbrownhome1`. It checks the committed bundle's metadata, requires
a version increase for changed content, creates and verifies a tagged GitHub
Release before recording the `tampermonkey` component in Solution Directory.
The hosted app's `web` release record is unchanged.

If publication succeeded but recording failed, rerun the same command. Identical
content is verified and recorded without creating another release. Use
`-VerifyOnly` with its source `-Commit` to record an existing release.

Before publishing, test the rebuilt userscript in Tampermonkey on a page that
loads slowly. Confirm the shortcut opens the palette while loading is still
pending. Automated browser fixtures use mocked GM APIs and don't verify the
extension's injection timing.

> ⚠️ Always **build before updating the Gist** — otherwise the Gist ships a stale
> bundle. And bump the version, or Tampermonkey clients won't pick up the change.
