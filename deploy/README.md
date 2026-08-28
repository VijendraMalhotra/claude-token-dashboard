# Deploy — multi-machine VPS setup

This directory contains everything needed to run the dashboard on an internal VPS that aggregates Claude Code sessions from multiple machines.

## Architecture

```
Mac (~/.claude/projects/)
    │  rsync push over SSH — on demand (`push-claude-stats`)
    │  not scheduled: see "Why the Mac push is manual" below
    ▼
VPS (~/claude-sessions/)
    ├── mac__<slug>/    ← pushed from Mac
    └── vps__<slug>/   ← mirrored locally by VPS sync service
         │
         ▼
    token-dashboard reads ~/claude-sessions/
    system service, bound to LAN IP:8080
```

**Why Mac pushes (not VPS pulls):** The VPS is always on and reachable at a fixed LAN IP — it's the stable target. The Mac only needs SSH to `VGUbuntu`, not the other way around.

**Why the Mac push is manual:** macOS `launchd` and `cron` run in a TCC-restricted context that cannot read `~/.ssh` when that directory symlinks into cloud storage (OneDrive, Dropbox, iCloud). The key read returns `Operation not permitted`, so every scheduled run fails — silently, forever. Session data only changes when Claude Code runs, so `push-claude-stats` after a work session is equivalent. The VPS side *is* scheduled (systemd timer), because it has no such restriction.

Note the SSH alias points at a **LAN IP**, so the push only works on the home network.

The `mac__` / `vps__` prefix on each project directory is what lets the machine filter dropdown in the UI scope results to a single machine.

## Install order

### 1. VPS first

```bash
git clone https://github.com/VijendraMalhotra/claude-token-dashboard.git ~/token-dashboard
bash ~/token-dashboard/deploy/install.sh
```

This sets up:
- `~/claude-sessions/` (aggregation dir the dashboard reads from)
- `~/bin/sync-vps-local.sh` (mirrors VPS local sessions to `vps__` prefix)
- Three system-level systemd services (no `loginctl enable-linger` needed)
- The dashboard bound to the detected LAN IP on port 8080

### 2. Mac second

```bash
# On the Mac — repo must already be cloned here too
bash ~/token-dashboard/deploy/mac/install-mac.sh
```

This sets up:
- A `push-claude-stats` fish function that runs `deploy/mac/mac-push.sh` from the repo
- Nothing else — no daemon, no timer

**Prerequisites for the Mac step:**
- SSH alias `VGUbuntu` must exist in `~/.ssh/config` pointing at the VPS
- Key-based auth must already work: `ssh VGUbuntu 'ls'` succeeds without a password
- VPS install must be done first so `~/claude-sessions/` exists there
- You must be on the home LAN

## Files

| File | Runs on | Purpose |
|---|---|---|
| `install.sh` | VPS | One-shot VPS installer |
| `sync-vps-local.sh` | VPS | Mirrors `~/.claude/projects/` → `~/claude-sessions/vps__*` |
| `systemd/claude-sync.service` | VPS | Calls `sync-vps-local.sh` as a system service |
| `systemd/claude-sync.timer` | VPS | Hourly timer for the VPS sync |
| `systemd/token-dashboard.service` | VPS | Runs the dashboard, bound to LAN IP |
| `mac/mac-push.sh` | Mac | rsync pushes Mac sessions to VPS `mac__` prefix |
| `mac/push-claude-stats.fish` | Mac | the `push-claude-stats` command — push + rescan + summary |
| `mac/install-mac.sh` | Mac | One-shot Mac installer (verifies SSH, installs `push-claude-stats`) |

## Useful commands

```bash
# VPS — check services
sudo systemctl status token-dashboard
sudo systemctl status claude-sync.timer
journalctl -u claude-sync.service -n 30
journalctl -u token-dashboard.service -n 30

# VPS — force a local sync now
sudo systemctl start claude-sync.service

# VPS — update dashboard
git -C ~/token-dashboard pull --ff-only
sudo systemctl restart token-dashboard

# Mac — push sessions to the VPS, rescan, print the summary (home LAN only)
push-claude-stats

# Mac — push only, no rescan (dashboard will show stale numbers)
bash deploy/mac/mac-push.sh
```

## Security note

The dashboard is bound to the VPS LAN IP (not `0.0.0.0`) and is only accessible from within your home network. Do not expose port 8080 to the public internet — the JSONL files contain full prompt and response transcripts.
