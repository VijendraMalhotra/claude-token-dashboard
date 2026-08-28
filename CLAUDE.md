# CLAUDE.md

# Copyright (c) 2026 VGX Global Consulting (OPC) Private Limited. All rights reserved.

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

**Token Dashboard** — a local dashboard for tracking Claude Code token usage, costs, and session history. Reads the JSONL transcripts Claude Code writes to `~/.claude/projects/` and turns them into per-prompt cost analytics, tool/file heatmaps, subagent attribution, cache analytics, project comparisons, and a rule-based tips engine.

Supports **multi-machine aggregation**: a Mac pushes sessions to an internal VPS via launchd + rsync, the VPS mirrors its own sessions locally, and both sets appear under `mac__` / `vps__` project prefixes. A machine filter dropdown scopes every tab to a single machine or shows all.

Runs on macOS, Windows, and Linux. No `pip install`. No Node.js. No build step.

## Repo facts

- `origin` → `github.com/VijendraMalhotra/claude-token-dashboard` (public). `upstream` → `github.com/nateherkai/token-dashboard`, the project this is forked from. Everything under `deploy/`, the machine filter, and the `mac__`/`vps__` prefixing are local additions that do not exist upstream — keep them isolated so upstream merges stay clean.
- Not a VGXDigital remote. Do **not** add VGX copyright headers to new files; the existing headers in `CLAUDE.md` / `AGENTS.md` are historical.
- `HANDOFF.md` is gitignored — private context about the deployment and the operator, not part of the public repo. Read it for background; never commit it.
- `AGENTS.md` is a Codex-facing mirror of this file and is currently **stale and machine-mangled** (it string-replaced "Claude" with "Codex", so it claims Codex writes `~/.Codex/projects/`). Fix or delete it before committing; do not treat it as a source of truth.
- `docs/` holds `KNOWN_LIMITATIONS.md`, `inspiration.md`, and the README screenshots. `deploy/README.md` documents the two-machine install.

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
  → summary.py       exec-summary verdict cards (top of the Overview tab)
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
  README.md               two-machine install walkthrough
```

`web/` is vanilla JS with ES module imports and a hash router (`#/overview`, `#/prompts`, etc.). No build step — the server serves it as-is. ECharts is vendored into `web/` rather than loaded from a CDN to keep the dashboard fully offline.

### Machine filter

All `/api/*` routes accept a `?machine=mac|vps` query parameter. In `db.py`, `_machine_clause()` translates this to `project_slug GLOB 'mac__*'` (or `vps__*`). All eight query helpers thread the `machine` parameter through their WHERE clauses.

In JS, `web/app.js` exports two fetch helpers:
- `api(path)` — bare fetch, used for session detail (never filtered)
- `apiF(path)` — appends `&machine=${state.machine}` automatically, used in all tab data-fetching calls

`state.machine` is persisted to `localStorage` and defaults to `""` (all machines). The filter `<select>` in the topbar updates `state.machine` and re-renders the current tab.

### Mac push is on-demand — do not re-add a scheduler

`deploy/mac/mac-push.sh` is run by hand (`claude-push`, or `bash deploy/mac/mac-push.sh`). It is **deliberately not scheduled**, and a launchd agent for it was removed on 2026-08-28 after it failed 1076 consecutive times over 59 days without ever succeeding once.

Root cause, verified by probing a real launchd context: `~/.ssh` on this Mac symlinks into cloud storage (`~/OneDrive - VM/Dropbox/...`). launchd can `stat` that path but reading it returns `Operation not permitted` — TCC denies it. Both `id_rsa` **and** `config` are unreadable, so `ssh` never even resolves the `VGUbuntu` alias to its LAN IP and fails on a literal hostname lookup. macOS `cron` runs in the same restricted context and fails identically. Granting Full Disk Access or staging a plain-text key bundle outside cloud storage would work, but session data only changes when Claude Code runs, so an on-demand push loses nothing and costs no key duplication.

Also note: `Host VGUbuntu` is a **LAN address** (`192.168.1.67`). The push only works on the home network — off-LAN failures are expected, not a bug.

Target bash 3.2 — macOS ships no `mapfile`.

Three bugs the stale-dir cleanup loop has already had — do not reintroduce:
- A remote `ls -d ~/claude-sessions/mac__*/` returns **expanded** absolute paths, so stripping the literal `~/claude-sessions/mac__` prefix fails and marks every dir stale. List basenames with `cd ... && ls -1d mac__*/` instead.
- `for d in $remote_dirs` depends on IFS word-splitting and collapses to a single blob when IFS is unset. Use `while IFS= read -r`.
- `ssh` inside a `while read` loop drains the loop's stdin and silently skips every remaining line. Always `ssh -n` inside such a loop.

## Data pipeline

Claude Code writes one JSONL file per session to `~/.claude/projects/<project-slug>/<session-id>.jsonl`. The scanner is incremental: it stores each file's `mtime` and `bytes_read` in the `files` table and only reads new bytes on subsequent scans.

**Streaming-snapshot dedup**: Claude Code writes 2–3 JSONL lines per assistant response while streaming (same `message.id`, distinct top-level `uuid`). The dedup key is `(session_id, message_id)`. `scanner._evict_prior_snapshots` removes stale rows each time a newer snapshot for the same key arrives. The primary key on `messages` is `uuid`, not `message_id`. Never change the dedup logic to use `uuid` alone.

## API routes

`/api/summary`, `/api/overview`, `/api/daily`, `/api/projects`, `/api/prompts`, `/api/prompt-trend`, `/api/sessions`,
`/api/sessions/<id>`, `/api/tools`, `/api/skills`, `/api/by-model`, `/api/tips`, `/api/tips/dismiss`,
`/api/plan`, `/api/scan`, `/api/stream` (SSE). All except `/api/sessions/<id>` and `/api/stream`
honour `?machine=`.

### Prompt spans

`db.prompt_spans()` is the query behind `/api/prompts` and `/api/prompt-trend`. One row per user
prompt, covering **the full span of work it triggered** — every assistant turn, subagent sidechain,
and tool call from that prompt until the next real prompt in the same session (`LEAD()` over
timestamps). It replaced `expensive_prompts()`, which joined only `a.parent_uuid = u.uuid` — the
single immediate reply — and so dropped everything an agentic turn did after its first message.

Three filters matter, and removing any of them silently corrupts the numbers:
- `is_sidechain = 0` **on the prompt**. Sidechain user rows are subagent dispatch prompts written by
  Claude, not the user. They also fragment spans: parallel dispatches land back-to-back, so each
  one's span closes before the subagent does any work.
- The assistant join is deliberately **not** sidechain-filtered, so subagent cost rolls up into the
  real prompt that spawned it.
- Slash-command echoes (`<local-command-*>`, `<command-name>`, `<command-message>`,
  `<system-reminder>`) are excluded. Claude Code stores them as `type='user'` rows with text. On the
  live data they were 28% of all "prompts", and they broke spans at every `/exit`.

Cost is computed in `server._priced_spans`, not in `db.py` — `db` must not import `pricing`
(`pricing` imports `db`). Usage is grouped per model inside a span because a span can switch models
mid-flight and each model prices differently.

`idx_messages_sess_ts` and `idx_tools_sess_ts` exist for this query's range join: 1.17s → 0.34s on
80k messages. Do not drop them.

## Adding a new API route

1. Add the SQL query as a helper function in `token_dashboard/db.py`.
2. Add a handler branch in the `do_GET` block in `token_dashboard/server.py`.
3. Add a route JS module under `web/routes/` and register it in `ROUTES` in `web/app.js`.
4. Add tests under `tests/`. The existing test files show how to write JSONL fixtures into a temp dir and call `scan_dir`.

## Exec summary

`token_dashboard/summary.py` backs `/api/summary` and renders as the verdict band at the top of the
Overview tab. Five cards, each `{key, label, value, verdict, detail}` with `verdict` in
`good | watch | act | info` — the CSS colours the left border from that. It answers "is this fine",
not "what are the numbers"; the tabs below already carry the data.

- **value / spend** — on a subscription (`plan != api`) it shows API-equivalent usage as a multiple
  of what the plan actually costs over the active days in range. On `api` it shows spend. Never
  present the subscription figure as money owed.
- **turns** — median turns per prompt. Rising = prompts landing less cleanly.
- **cache** — median cache hit %.
- **rework** — share of prompts matching `REWORK_RE`. A keyword heuristic ("no" also matches
  "no worries"), so it is deliberately reported as a rate to watch, never an exact count. Do not
  tighten the thresholds without re-checking against real data.
- **rightsize** — Opus spans that finished in ≤2 turns with ≤1 tool call. The wording switches: on a
  subscription these cost *quota*, not money, so the dollar comparison is suppressed.

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
- **Release bookkeeping.** Meaningful changes bump `**Version x.y.z**` at the top of `README.md` and add a matching `## Changelog` entry in the same commit. Currently v1.2.0; the four `fix(deploy)`/`fix(mac)` commits after it are not yet changelogged.
- **No AI attribution in commit messages.**
- **Privacy invariant.** No outbound HTTP for user data, anywhere — not in Python, not in JS. The UI only fetches from `127.0.0.1`. Verify new code with `grep -r "https://" token_dashboard/ web/` before shipping.

## Customizing

Env vars: `PORT` (default 8080), `HOST` (default 127.0.0.1), `CLAUDE_PROJECTS_DIR`, `TOKEN_DASHBOARD_DB`. Pricing rates live in `pricing.json` — edit directly when model prices change.

## Known limitations

See `docs/KNOWN_LIMITATIONS.md`. Short list: Skills `tokens_per_call` is blank for project-local and subagent-dispatched skills; cost figures are API-equivalent (not subscription value); Cowork sessions are invisible; two concurrent dashboard processes will fight over the SQLite DB.

## Schema migrations

`db._migrate_add_message_id` is the pattern: check if the column exists before altering, and clear dependent tables so the next scan replays cleanly. Source of truth is always the JSONL files on disk, not the DB.
