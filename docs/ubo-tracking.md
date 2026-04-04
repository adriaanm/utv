# Ad Blocking: How It Works and How to Update

## Architecture

Ad blocking uses three layers, all configured in `Sources/AdBlocker.swift`:

| Layer | File | What it does | How to update |
|-------|------|-------------|---------------|
| Scriptlet bundle | `Sources/Resources/ubo-scriptlets.js` | Intercepts `fetch`/`XHR`/`JSON.parse` to strip ad payloads from YouTube API responses | `just sync` |
| Content rules | `Sources/Resources/content-rules.json` | WebKit content blocker — blocks network requests to ad domains | Edit manually |
| CSS hiding | `Sources/AdBlocker.swift` | Hides ad-related DOM elements | Edit manually |

The scriptlet bundle does the heavy lifting. It's a pre-compiled IIFE from the uBOL-home repo that activates `json-prune`, `prevent-fetch`, `prevent-xhr` etc. specifically for youtube.com. The content rules and CSS are a safety net for anything the scriptlets miss.

## Submodules

We track upstream uBO repos as git submodules for reference:

| Submodule | Repo | Purpose |
|-----------|------|---------|
| `third_party/uAssets` | [uBlockOrigin/uAssets](https://github.com/uBlockOrigin/uAssets) | Raw filter lists — useful for understanding what changed when ads break through |
| `third_party/uBOL-home` | [uBlockOrigin/uBOL-home](https://github.com/uBlockOrigin/uBOL-home) | Pre-compiled scriptlet bundle — this is what we actually ship |
| `third_party/uBlock` | [gorhill/uBlock](https://github.com/gorhill/uBlock) | Scriptlet source code — reference only |

## When ads start getting through

1. **Update the scriptlet bundle first** — this fixes most breakage:
   ```sh
   just sync        # pulls latest submodules, copies scriptlet bundle
   just build       # rebuild with new bundle
   just run         # test
   ```

2. **If ads still appear**, check what changed upstream:
   ```sh
   just diff-filters   # shows YouTube-relevant filter changes in uAssets
   ```
   Look for new domains or URL patterns → add them to `content-rules.json`.
   Look for new CSS selectors → add them to the CSS hiding section in `Sources/AdBlocker.swift`.

3. **If a specific ad format is new**, use Safari Web Inspector on the running app:
   - Develop menu → utv → Web Inspector
   - Network tab: find ad requests that aren't blocked
   - Elements tab: find ad DOM elements that aren't hidden
   - Add rules to `content-rules.json` or CSS in `Sources/AdBlocker.swift`

## content-rules.json format

WebKit content blocker JSON. Each rule has a trigger (URL pattern) and action (block/css-display-none):

```json
{
    "trigger": { "url-filter": "doubleclick\\.net" },
    "action": { "type": "block" }
}
```

See [WebKit Content Blockers docs](https://developer.apple.com/documentation/safariservices/creating-a-content-blocker) for the full spec. Limit: 50,000 rules per list.

## Scriptlet bundle details

The bundle at `ubo-scriptlets.js` is sourced from:
```
third_party/uBOL-home/chromium/rulesets/scripting/scriptlet/main/ublock-filters.js
```

It's a self-contained IIFE that checks `document.location` and activates the right scriptlets per-site. On youtube.com it runs:
- `json-prune` — strips `adPlacements`, `adSlots`, `playerAds` from API JSON responses
- `prevent-fetch` — blocks fetch requests to ad endpoints
- `prevent-xhr` — blocks XHR requests to ad endpoints

**Critical**: Must be injected into `WKContentWorld.page` (not `.defaultClient`) so it can intercept the page's native `fetch`/`XHR`/`JSON.parse`.

## Initial setup

```sh
just build    # inits submodules (shallow), syncs scriptlets, builds
just run      # build + assemble .app bundle + launch
```

Submodules are cloned with `--depth 1` (shallow) to keep disk usage low. `just sync` fetches latest upstream; `just build` only initialises if not already done.
