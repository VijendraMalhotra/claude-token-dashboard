# Deploy — multi-machine VPS setup

This directory contains everything needed to run the dashboard on an internal VPS that aggregates Claude Code sessions from multiple machines.

## Architecture

```
Mac (~/.claude/projects/)
    │  rsync over SSH (hourly, pull model)
    ▼
VPS (~/claude-sessions/)
    ├── mac__<slug>/    ← Mac sessions, prefixed
    └── vps__<slug>/   ← VPS local sessions, prefixed
         │
         ▼
    token-dashboard (reads ~/claude-sessions/)
    bound to LAN IP:8080
```

The `mac__` / `vps__` prefix on each project directory is what lets the machine filter dropdown in the UI scope results to a single machine.

## Prerequisites on the VPS

- Python 3.8+
- `git`, `rsync`
- SSH key already accepted from the VPS to the Mac (test with `ssh mac 'ls ~/.claude/projects'`)
- The Mac's SSH alias must be `mac` in `~/.ssh/config` (or edit `sync-claude-sessions.sh`)

## Install

```bash
git clone https://github.com/VijendraMalhotra/claude-token-dashboard.git ~/token-dashboard
bash ~/token-dashboard/deploy/install.sh
```

Then the one sudo step the installer can't do:

```bash
sudo loginctl enable-linger $(whoami)
```

## What install.sh does

1. Checks prerequisites
2. Auto-detects the VPS LAN IP and patches `token-dashboard.service`
3. Clones (or updates) the repo to `~/token-dashboard/`
4. Creates `~/claude-sessions/` (the aggregation dir)
5. Installs `sync-claude-sessions.sh` to `~/bin/`
6. Installs and enables three systemd user units:
   - `claude-sync.timer` — triggers the sync hourly
   - `claude-sync.service` — runs the sync script
   - `token-dashboard.service` — runs the dashboard server
7. Runs the first sync and first DB scan

## Files

| File | Purpose |
|---|---|
| `install.sh` | One-shot installer |
| `sync-claude-sessions.sh` | rsync Mac + local sessions into `~/claude-sessions/` with `mac__`/`vps__` prefixes |
| `systemd/claude-sync.service` | systemd one-shot unit that calls the sync script |
| `systemd/claude-sync.timer` | Hourly timer for the sync |
| `systemd/token-dashboard.service` | Runs `cli.py dashboard` bound to the VPS LAN IP |

## Useful commands

```bash
# Check sync timer
systemctl --user status claude-sync.timer

# View last sync log
journalctl --user -u claude-sync.service -n 30

# Force a sync now
systemctl --user start claude-sync.service

# Check dashboard service
systemctl --user status token-dashboard

# Restart dashboard
systemctl --user restart token-dashboard
```

## Updating

```bash
git -C ~/token-dashboard pull --ff-only
systemctl --user restart token-dashboard
```

## Security note

The dashboard is bound to the LAN IP (not 0.0.0.0) and is only accessible from within your home network. Do not expose port 8080 to the public internet — the JSONL files contain full prompt and response transcripts.
