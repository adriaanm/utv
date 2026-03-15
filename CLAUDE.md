# CLAUDE.md — Project Guidelines

## Project

tvOS YouTube viewer app using WKWebView + content blocking, backed by uBlock Origin filter lists.

## Working principles

- **Commit often.** Small, atomic commits. Don't batch unrelated changes. Commit after each meaningful step, not at the end of a session.
- **Context is limited, the repo is forever.** Anything that might be needed in a future session belongs in the repo, not in conversation memory. Use `docs/` as a journal and work planner — write plans before starting, update as you go.
- **When a task is done, rework its doc into a guide.** Task-tracking docs in `docs/` should evolve from "what we're doing" into "how this works" once complete.
- **Automate repetitive tasks with a justfile.** Add `just` recipes for anything done more than twice (syncing, building, testing, etc.).
- **Track docs and scripts with code.** Documentation and scripts are first-class artifacts — commit them alongside the code they support.

## Key docs

- [docs/roadmap.md](docs/roadmap.md) — Project roadmap: macOS PoC → usable app → tvOS port
- [docs/ubo-tracking.md](docs/ubo-tracking.md) — How uBlock Origin filter tracking works (submodules, sync script, extracted output)

## Repo structure

```
third_party/          Git submodules (uAssets, uBOL-home, uBlock)
scripts/              Automation scripts
  sync-ubo.sh        Update submodules + extract YouTube-relevant filters
docs/                 Documentation, plans, guides
AdsFilters/           (gitignored) Derived output from sync script
```
