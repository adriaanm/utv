# uBlock Origin Tracking

We track three upstream uBlock Origin repositories as git submodules to stay current with YouTube ad-blocking filter lists, pre-compiled rulesets, and scriptlets.

## Submodules

| Submodule | Source | What it provides |
|-----------|--------|------------------|
| `third_party/uAssets` | [uBlockOrigin/uAssets](https://github.com/uBlockOrigin/uAssets) | Raw filter lists in ABP syntax (`filters/filters.txt`, `filters/privacy.txt`, etc.) |
| `third_party/uBOL-home` | [uBlockOrigin/uBOL-home](https://github.com/uBlockOrigin/uBOL-home) | Pre-compiled declarativeNetRequest rulesets in `chromium/rulesets/` (JSON rules + scriptlet injections) |
| `third_party/uBlock` | [gorhill/uBlock](https://github.com/gorhill/uBlock) | Scriptlet source in `src/js/resources/` (json-prune, prevent-fetch, prevent-xhr, etc.) |

## Sync script

`scripts/sync-ubo.sh` updates all submodules and extracts YouTube-relevant content into `AdsFilters/`:

```
AdsFilters/
├── filters/       YouTube-specific rules + full core filter lists
├── rulesets/       Pre-compiled declarativeNetRequest JSON + scriptlet injections
└── scriptlets/    Key uBlock scriptlet source files
```

Run it:

```sh
./scripts/sync-ubo.sh
```

The script:
1. Pulls latest from all three submodules (`git submodule update --remote --merge`)
2. Greps uAssets filter lists for YouTube-related domains (`youtube.com`, `googlevideo.com`, `ytimg.com`, etc.)
3. Copies core pre-compiled rulesets and scriptlet injections from uBOL-home
4. Copies key scriptlet source files from uBlock

`AdsFilters/` is gitignored — it's derived output, regenerated on each sync.

## Initial setup

```sh
git submodule update --init --recursive
./scripts/sync-ubo.sh
```

## Checking for upstream changes

```sh
git submodule update --remote
git diff third_party/   # shows what changed
```

## Why these three repos

YouTube ad patterns change frequently. uBlock Origin is the most actively maintained filter set targeting YouTube. By tracking all three repos we get:

- **uAssets**: the source-of-truth filter rules, useful for understanding what's being blocked and writing custom rules
- **uBOL-home**: ready-to-use declarativeNetRequest JSON rulesets (the format WebKit content blockers consume) — avoids us having to compile ABP syntax ourselves
- **uBlock**: the scriptlet implementations needed for JS-level ad blocking (e.g. intercepting fetch/XHR requests to ad servers, pruning ad config from JSON responses)
