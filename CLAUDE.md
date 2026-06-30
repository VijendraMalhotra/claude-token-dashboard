# CLAUDE.md

# Copyright (c) 2026 VGX Global Consulting (OPC) Private Limited. All rights reserved.

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

**Token Dashboard** — a local dashboard for tracking Claude Code token usage, costs, and session history. Reads the JSONL transcripts Claude Code writes to `~/.claude/projects/` and turns them into per-prompt cost analytics, tool/file heatmaps, subagent attribution, cache analytics, project comparisons, and a rule-based tips engine.

Supports **multi-machine aggregation**: a Mac pushes sessions to an internal VPS via launchd + rsync, the VPS mirrors its own sessions locally, and both sets appear under `mac__` / `vps__` project prefixes. A machine filter dropdown scopes every tab to a single machine or shows all.

Runs on macOS, Windows, and Linux. No `pip install`. No Node.js. No build step.

## Commands

```bash
# Run all tests
python3 -m unittest discover tests

# Run a single test file
python3 -m unittest tests.test_scanner_dedup

# Run a single test case
python3 -m unittest tests.test_scanner_dedup.StreamingDedupTests.test_within_file_streaming_dupes_collapse_to_final

# Start the server (no browser open, useful during development)
python3 cli.py dashboard --no-open

# Sanity-check a live endpoint
curl http://127.0.0.1:8080/api/overview

# Scan only (populate DB without starting the server)
python3 cli.py scan

# Terminal summaries
python3 cli.py today    # today's totals
python3 cli.py stats    # all-time totals
python3 cli.py tips     # active tip suggestions
```

## Architecture

```
cli.py
  → scanner.py       JSONL → SQLite (incremental, mtime+byte-offset)
  → db.py            schema, migrations, query helpers
  → server.py        ThreadingHTTPServer + /api/* + SSE stream
  → skills.py        SKILL.md catalog (slug → char count → token estimate)
  → tips.py          rule-based tips engine (4 rule sets)
  → pricing.py       per-model rates + plan-aware cost formatting

web/
  app.js             router, state (incl. state.machine), fetch helpers (api/apiF), SSE listener, privacy-blur
  routes/            one JS module per tab — loaded lazily on navigation
  charts.js          ECharts wrappers (vendored, no CDN)

deploy/
  install.sh              VPS one-shot installer (system-level systemd)
  sync-vps-local.sh       VPS: mirrors ~/.claude/projects/ → ~/claude-sessions/vps__*
  systemd/                claude-sync.{service,timer} + token-dashboard.service
  mac/install-mac.sh      Mac one-shot installer (launchd)
  mac/mac-push.sh         Mac: rsync-pushes sessions to VPS mac__* prefix
  mac/com.vgx.claude-push.plist   launchd agent (hourly + at login)
```

`web/` is vanilla JS with ES module imports and a hash router (`#/overview`, `#/prompts`, etc.). No build step — the server serves it as-is. ECharts is vendored into `web/` rather than loaded from a CDN to keep the dashboard fully offline.

### Machine filter

All `/api/*` routes accept a `?machine=mac|vps` query parameter. In `db.py`, `_machine_clause()` translates this to `project_slug GLOB 'mac__*'` (or `vps__*`). All eight query helpers thread the `machine` parameter through their WHERE clauses.

In JS, `web/app.js` exports two fetch helpers:
- `api(path)` — bare fetch, used for session detail (never filtered)
- `apiF(path)` — appends `&machine=${state.machine}` automatically, used in all tab data-fetching calls

`state.machine` is persisted to `localStorage` and defaults to `""` (all machines). The filter `<select>` in the topbar updates `state.machine` and re-renders the current tab.

## Data pipeline

Claude Code writes one JSONL file per session to `~/.claude/projects/<project-slug>/<session-id>.jsonl`. The scanner is incremental: it stores each file's `mtime` and `bytes_read` in the `files` table and only reads new bytes on subsequent scans.

**Streaming-snapshot dedup**: Claude Code writes 2–3 JSONL lines per assistant response while streaming (same `message.id`, distinct top-level `uuid`). The dedup key is `(session_id, message_id)`. `scanner._evict_prior_snapshots` removes stale rows each time a newer snapshot for the same key arrives. The primary key on `messages` is `uuid`, not `message_id`. Never change the dedup logic to use `uuid` alone.

## Adding a new API route

1. Add the SQL query as a helper function in `token_dashboard/db.py`.
2. Add a handler branch in the `do_GET` block in `token_dashboard/server.py`.
3. Add a route JS module under `web/routes/` and register it in `ROUTES` in `web/app.js`.
4. Add tests under `tests/`. The existing test files show how to write JSONL fixtures into a temp dir and call `scan_dir`.

## Tips engine

`token_dashboard/tips.py` exposes four rule sets that return dismissable tip dicts:

- `cache_discipline_tips` — projects with cache-hit rate < 40% over the last 7 days
- `repeated_target_tips` — files read >10 times, Bash commands run >15 times in 7 days
- `right_size_tips` — short Opus turns (< 500 output tokens) that would fit on Sonnet
- `outlier_tips` — tool results > 50k tokens; subagent invocations that spike vs. their mean

Tips are dismissable for 14 days (`dismissed_tips` table). `all_tips` calls all four and concatenates results.

## Conventions

- **Stdlib only.** No `pip install`. Argue for a third-party dependency before adding one.
- **SQLite parameter binding always.** f-strings in SQL may only interpolate hardcoded column names or placeholder lists built from internal values. User-reachable values go through `?`.
- **Small focused files.** Split when a file exceeds ~400 lines or accretes three distinct concerns.
- **Privacy invariant.** No outbound HTTP for user data, anywhere — not in Python, not in JS. The UI only fetches from `127.0.0.1`. Verify new code with `grep -r "https://" token_dashboard/ web/` before shipping.

## Customizing

Env vars: `PORT` (default 8080), `HOST` (default 127.0.0.1), `CLAUDE_PROJECTS_DIR`, `TOKEN_DASHBOARD_DB`. Pricing rates live in `pricing.json` — edit directly when model prices change.

## Known limitations

See `docs/KNOWN_LIMITATIONS.md`. Short list: Skills `tokens_per_call` is blank for project-local and subagent-dispatched skills; cost figures are API-equivalent (not subscription value); Cowork sessions are invisible; two concurrent dashboard processes will fight over the SQLite DB.

## Schema migrations

`db._migrate_add_message_id` is the pattern: check if the column exists before altering, and clear dependent tables so the next scan replays cleanly. Source of truth is always the JSONL files on disk, not the DB.
