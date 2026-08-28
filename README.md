# Token Dashboard

**Version 1.5.3**

A local dashboard that reads the JSONL transcripts Claude Code writes to `~/.claude/projects/` and turns them into per-prompt cost analytics, tool/file heatmaps, subagent attribution, cache analytics, project comparisons, and a rule-based tips engine.

**Everything runs locally.** No data leaves your machine — no telemetry, no API calls for your data, no login.

Supports **multi-machine aggregation** — aggregate sessions from a Mac and a VPS under one dashboard, with a machine filter dropdown to scope any tab to a single machine.

![Overview tab — totals and daily charts](docs/images/dashboard-overview-top.jpg)

![Overview tab — per-project, per-model, top tools, recent sessions](docs/images/dashboard-overview-bottom.jpg)

## Changelog

### v1.5.3 (2026-08-28)
- `push-claude-stats` now shows what it is doing: per-project file counts during the rsync, per-step timings, what the rescan actually ingested, and the tracked session/turn totals
- Corrected the docs: the dashboard rescans itself every 30s (`server._scan_loop`), so a push alone is never lost — the explicit scan makes it visible immediately rather than within half a minute

### v1.5.2 (2026-08-28)
- Renamed the Mac command `claude-push` → **`push-claude-stats`** (`deploy/mac/push-claude-stats.fish`). Fish autoloads by filename, so the file and the function name have to match; `install-mac.sh` removes the old file on upgrade

### v1.5.1 (2026-08-28)
- `claude-push` now rescans after pushing and prints the summary band — pushing alone left the dashboard showing stale numbers
- The command lives in the repo as `deploy/mac/claude-push.fish` instead of being generated inline by the installer
- README documents the full two-machine setup: day-to-day use, first-time install order, how to deploy a code change, and why the Mac push is manual

### v1.5.0 (2026-08-28)
- **Corrected pricing.** `pricing.json` carried the retired $15/$75 Opus rates; current Opus (4.5–5) is $5/$25, so every Opus cost was ~3× too high. Added Opus 5/4.8, Sonnet 5, Fable 5, Mythos 5 and the remaining current models with exact cache-write and cache-read rates
- `claude-fable-5` matched no pricing tier and was silently costed at $0 — `_tier_from_name` now recognises the Fable/Mythos tier
- Exec summary discloses what share of a cost figure comes from tier-fallback rates instead of exact ones
- Opus right-sizing verdict now keys off whether the Opus ceiling was actually hit (one-way main-thread Opus→Sonnet fallbacks, ignoring subagents) rather than the raw count of small Opus prompts — no ceiling hits means no alarm

### v1.4.0 (2026-08-28)
- **Exec summary** at the top of the Overview tab: five colour-coded verdict cards (value, prompt health, cache discipline, rework rate, Opus right-sizing) that say whether each is fine, worth watching, or worth acting on
- Subscription-aware framing — on a Pro/Max plan the cost figure is shown as a value multiple over what the plan costs, and right-sizing is described as quota rather than money
- New `/api/summary` endpoint; `prompt_spans()` now accepts `since`/`until` so the summary follows the Overview range tabs

### v1.3.0 (2026-08-28)
- Prompts tab rebuilt around **prompt spans**: each prompt is now charged the full span of work it triggered — every assistant turn, subagent and tool call until the next prompt — instead of only the first assistant reply
- New columns: turns, tool calls, true cost across all five token classes, and cache hit %
- Weekly median cost-per-prompt trend chart, so "am I getting cheaper" is readable
- Filter out subagent dispatch prompts and Claude Code's slash-command echoes, which were 28% of listed "prompts"
- New `/api/prompt-trend` endpoint; `/api/prompts` now sorts by `cost` (default), `turns`, `tokens`, or `recent`
- **Breaking:** `/api/prompts` replaces `estimated_cost_usd` (cache-read cost only) with `cost_usd` (whole-span cost)

### v1.2.1 (2026-08-28)
- Mac push is now on-demand (`claude-push`) — the launchd agent could never read a cloud-synced `~/.ssh` and had failed 1076 times without one success
- Fix stale-dir cleanup in `mac-push.sh`: remote `ls -d ~/...` returns expanded paths, so the prefix strip misclassified every remote dir as stale
- Fix `ssh` draining the cleanup loop's stdin (`ssh -n`), which skipped all dirs after the first
- Deploy scripts: drop hardcoded paths, fix grep flag collision on dash-prefixed slugs, bash 3.2 compatibility

### v1.2.0 (2026-05-22)
- Machine filter dropdown in the topbar — scope any tab to Mac, VPS, or all machines
- Multi-machine deploy infrastructure: Mac-push model (launchd) + VPS system services (systemd)
- All `/api/*` endpoints accept `?machine=mac|vps` for server-side filtering
- Project slug prefixing (`mac__` / `vps__`) for unambiguous multi-machine aggregation

### v1.1.0 (2026-05-20)
- Privacy and input-validation hardening pass
- Scanner: preserve accounting under partial flushes and rescans
- OSS release preparation

### v1.0.0 (initial)
- Core scanner, server, and UI (forked from nateherkai/token-dashboard)
- Per-prompt cost analytics, tool/file heatmaps, cache analytics
- Tips engine (4 rule sets), Skills tab, Settings (plan selector)
- Streaming-snapshot dedup by `message.id`

## What this is useful for

- Seeing which of your prompts are expensive (surprise: they usually involve large tool results).
- Comparing token usage across projects you've worked on.
- Spotting wasteful patterns — the same file read twenty times in a session, a tool call returning 80k tokens.
- Understanding what a "cache hit" actually saves you.
- If you're on Pro or Max, confirming you're getting your money's worth in API-equivalent dollars.

## Prerequisites

- **Python 3.8 or newer** — already installed on macOS and most Linux. On Windows: `winget install Python.Python.3.12` or download from python.org.
- **Claude Code** — installed and with at least one session run. The dashboard reads those sessions. If you just installed Claude Code and haven't used it yet, run at least one prompt first.
- **A web browser.** Any modern one.

No `pip install`. No Node.js. No build step.

## Quickstart

```bash
git clone https://github.com/VijendraMalhotra/claude-token-dashboard.git
cd claude-token-dashboard
python3 cli.py dashboard
```

> On Windows, if `python3` isn't on your PATH, substitute `py -3` for `python3` in every command below.

The command:
1. Scans `~/.claude/projects/` (first run can take 20–60 seconds on a heavy user's machine).
2. Starts a local server at http://127.0.0.1:8080.
3. Opens your default browser to that URL.

Leave it running; it re-scans every 30 seconds and pushes updates live. Stop with `Ctrl+C`.

## Where the data comes from

Claude Code writes one JSONL file per session here:

| OS | Path |
|---|---|
| macOS / Linux | `~/.claude/projects/<project-slug>/<session-id>.jsonl` |
| Windows | `C:\Users\<you>\.claude\projects\<project-slug>\<session-id>.jsonl` |

The dashboard never modifies those files — it only reads them and keeps a local SQLite cache at `~/.claude/token-dashboard.db`.

To point at a different location:

```bash
python3 cli.py dashboard --projects-dir /path/to/projects --db /path/to/cache.db
```

### Environment variables

| Var | Default | Purpose |
|---|---|---|
| `PORT` | `8080` | Port the local web server listens on |
| `HOST` | `127.0.0.1` | Bind address. Keep the default. Setting `0.0.0.0` exposes your entire prompt history to anyone on your local network — don't do this on any network you don't fully control (no coffee-shop Wi-Fi, no coworking spaces). |
| `CLAUDE_PROJECTS_DIR` | `~/.claude/projects` | Where to scan for session JSONL files |
| `TOKEN_DASHBOARD_DB` | `~/.claude/token-dashboard.db` | SQLite cache location |

Pricing lives in [`pricing.json`](pricing.json). Edit it directly if model prices change or to add a new plan.

## CLI reference

```bash
python3 cli.py scan          # populate / refresh the local DB, then exit
python3 cli.py today         # today's totals (terminal)
python3 cli.py stats         # all-time totals (terminal)
python3 cli.py tips          # active suggestions (terminal)
python3 cli.py dashboard     # scan + serve the UI at http://localhost:8080

# dashboard flags
python3 cli.py dashboard --no-open   # don't auto-open the browser
python3 cli.py dashboard --no-scan   # skip the initial scan (use cached DB only)
```

Change the port: `PORT=9000 python3 cli.py dashboard`.

## Multi-machine setup

One dashboard, fed by two machines. The VPS is the host: it runs the web UI, mirrors its own
sessions on a systemd timer, and receives the Mac's sessions by rsync. Each project directory gets a
`mac__` or `vps__` prefix, which is what the machine-filter dropdown keys off.

```
Mac                                    VPS
~/.claude/projects/                    ~/claude-sessions/
        │                                ├── mac__<slug>/   ← pushed from the Mac
        └── push-claude-stats ──────▶    └── vps__<slug>/   ← mirrored by a systemd timer
            (manual, home LAN)                     │
                                       token-dashboard.service reads both
                                       http://<vps-lan-ip>:8080
```

### Day to day

One command on the Mac, after a session's worth of work:

```fish
push-claude-stats
```

It rsyncs the sessions up, triggers `/api/scan` so the dashboard actually ingests them, and prints
the verdict band:

```
[2026-08-28T07:19:47+05:30] push OK (27 projects → VGUbuntu:~/claude-sessions)
scan OK

  [ ok ] Value vs plan          15×
  [ ok ] Prompt health          3 turns
  [ ok ] Cache discipline       99%
  [ ok ] Rework rate            10%
  [ ok ] Opus on small asks     899

  http://192.168.1.67:8080/#/overview
```

`bash deploy/mac/mac-push.sh` does the rsync only. The dashboard rescans itself every 30 seconds
anyway, so a bare push is never *lost* — the explicit scan just makes it show up now instead of
within half a minute, and the summary saves you opening a browser to check. A rescan reporting
"already current" means the background loop got there first, which is normal.

### First-time install

Order matters — the VPS must exist before the Mac can push to it.

**1. VPS**

```bash
git clone https://github.com/VijendraMalhotra/claude-token-dashboard.git ~/token-dashboard
bash ~/token-dashboard/deploy/install.sh
```

Creates `~/claude-sessions/`, installs `sync-vps-local.sh`, and starts three system-level systemd
units (`claude-sync.service`, `claude-sync.timer`, `token-dashboard.service`) with the dashboard
bound to the detected LAN IP on port 8080.

**2. Mac**

Prerequisites: an SSH alias `VGUbuntu` in `~/.ssh/config` pointing at the VPS, working key auth
(`ssh VGUbuntu ls` with no password), and you on the home LAN.

```bash
git clone https://github.com/VijendraMalhotra/claude-token-dashboard.git ~/token-dashboard
bash ~/token-dashboard/deploy/mac/install-mac.sh
```

Verifies SSH, installs the `push-claude-stats` fish function, removes any legacy launchd agent, and runs
the first push.

**3. Set your plan**

Settings tab → Plan. On a subscription the cost figures reframe as a value multiple over what the
plan costs; left on API they read as pay-per-token money you do not actually owe.

### Deploying a code change to the VPS

```bash
git push origin main
ssh VGUbuntu 'git -C ~/token-dashboard pull --ff-only'
ssh VGUbuntu 'sudo systemctl restart token-dashboard'
```

The Python modules load at import, so a restart is required; `web/` files are read per request and
pick up on a browser refresh.

### Why the Mac push is manual

macOS `launchd` and `cron` run in a TCC-restricted context that cannot read `~/.ssh` when that
directory symlinks into cloud storage (OneDrive, Dropbox, iCloud) — the key read returns
`Operation not permitted`, so every scheduled run fails, silently, forever. A launchd agent here
failed 1076 times across 59 days without succeeding once. Session data only changes when Claude Code
runs, so an on-demand push loses nothing and needs no second copy of your private key. The VPS side
*is* scheduled, because Linux has no such restriction.

The SSH alias points at a **LAN IP**, so `push-claude-stats` only works on the home network.

See [`deploy/README.md`](deploy/README.md) for the file-by-file reference.

## The 7 tabs

The dashboard is a single page with a hash-router tab bar across the top. Each tab is backed by its own JSON API under `/api/`. A **machine filter dropdown** in the topbar scopes every tab to `All`, `Mac`, or `VPS` — state persists across page reloads via `localStorage`.

- **Overview** — all-time input/output/cache tokens, sessions, turns, estimated cost on your chosen plan, daily work and cache-read charts, tokens-by-project, token share by model, top tools by call count, and recent sessions. This is the landing tab.
- **Prompts** — your most expensive user prompts ranked by tokens. Click any row to see the assistant response, tool calls made, and the size of each tool result.
- **Sessions** — turn-by-turn view of any single session, with per-turn tokens and tool calls.
- **Projects** — per-project comparison: tokens, session counts, and which files were touched most.
- **Skills** — which skills you invoke most often, and (where we can measure them) their token cost. See [limitations](docs/KNOWN_LIMITATIONS.md#skills-token-counts-are-partial).
- **Tips** — rule-based suggestions for reducing token usage (repeated file reads, oversized tool results, low cache-hit rate, etc.).
- **Settings** — switch pricing between API / Pro / Max / Max-20x so cost figures everywhere else reflect your actual plan.

The Overview tab also has a built-in "What do these numbers mean?" panel that explains input/output/cache tokens in plain English.

## Troubleshooting

**"No data" or empty charts.** Run `python3 cli.py scan` once to populate the DB, then reload.

**Port 8080 already in use.** `PORT=9000 python3 cli.py dashboard`.

**Numbers look wrong / stuck.** The DB lives at `~/.claude/token-dashboard.db`. Delete it and re-run `python3 cli.py scan` to rebuild from scratch.

**Running the dashboard twice at the same time.** Don't — both processes will fight over the SQLite DB. Stop all instances before starting a new one.

## Accuracy note

Claude Code writes each assistant response 2–3 times to disk while it streams (the same API message gets snapshotted as output grows). The dashboard dedupes these by `message.id` so the final tally matches what the API actually billed. If you compare against another tool that sums every JSONL row, expect this dashboard's numbers to be lower — and closer to reality.

## Privacy

Nothing leaves your machine. No telemetry. No remote calls for your data. The browser fetches its JSON from `127.0.0.1`, and all JS/CSS/fonts are served from that same local server — ECharts is vendored into `web/`, and the UI falls back to system fonts rather than pulling from a font CDN. If you want to verify: `grep -r "https://" token_dashboard/ web/` — you'll find nothing.

## Tech stack

Python 3 (stdlib only) for the CLI, scanner, and HTTP server. SQLite for the local cache. Vanilla JS + ECharts for the UI, no build step. Dark theme, hash-based router, server-sent events for live refresh.

Data flow: `cli.py` → `token_dashboard/scanner.py` → SQLite DB; `token_dashboard/server.py` exposes `/api/*` JSON routes and serves `web/`.

## Further reading

- [`CLAUDE.md`](CLAUDE.md) — conventions and architecture overview (also picked up automatically by Claude Code)
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — how to develop and test
- [`docs/KNOWN_LIMITATIONS.md`](docs/KNOWN_LIMITATIONS.md) — rough edges
- [`docs/inspiration.md`](docs/inspiration.md) — prior art and how this project diverges

## Attribution

Forked from [nateherkai/token-dashboard](https://github.com/nateherkai/token-dashboard) by Nate Herk. The core scanner, server, and UI architecture are his work. This fork extends it with additional tooling and deployment support.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Short version: fork, `python3 -m unittest discover tests` before opening a PR, keep it stdlib-only.

## License

[MIT](LICENSE).
