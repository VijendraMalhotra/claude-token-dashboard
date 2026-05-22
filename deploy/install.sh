#!/usr/bin/env bash
# install.sh — one-shot VPS installer for claude-token-dashboard
#
# What this does:
#   1. Checks prerequisites (python3, git, rsync, ssh)
#   2. Clones the dashboard repo to ~/token-dashboard/
#   3. Creates ~/claude-sessions/ (the aggregation directory)
#   4. Installs the sync script to ~/bin/
#   5. Installs and enables systemd user units
#   6. Patches the dashboard service with this machine's LAN IP
#   7. Runs the first sync and first scan
#   8. Prints the dashboard URL
#
# After running, do ONE sudo step the script can't do for you:
#   sudo loginctl enable-linger $(whoami)
# This lets your systemd user units survive logout.
#
# Copyright (c) 2026 VGX Global Consulting (OPC) Pvt Ltd

set -euo pipefail

REPO="https://github.com/VijendraMalhotra/claude-token-dashboard.git"
DASHBOARD_DIR="${HOME}/token-dashboard"
AGG_DIR="${HOME}/claude-sessions"
BIN_DIR="${HOME}/bin"
SYSTEMD_DIR="${HOME}/.config/systemd/user"
PORT=8080

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

echo "=== Token Dashboard installer ==="
echo

# ── Prerequisites ──────────────────────────────────────────────────────────────
for cmd in python3 git rsync ssh; do
    command -v "$cmd" &>/dev/null || die "Required command not found: $cmd"
done

python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)' \
    || die "Python 3.8+ required (found $(python3 --version))"

ok "Prerequisites OK"

# ── Detect LAN IP ─────────────────────────────────────────────────────────────
LAN_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+' | head -1 || true)
if [[ -z "$LAN_IP" ]]; then
    warn "Could not auto-detect LAN IP. Edit $SYSTEMD_DIR/token-dashboard.service and set HOST= manually."
    LAN_IP="127.0.0.1"
fi
ok "LAN IP: $LAN_IP"

# ── Clone or update repo ───────────────────────────────────────────────────────
if [[ -d "$DASHBOARD_DIR/.git" ]]; then
    warn "Dashboard dir already exists — pulling latest."
    git -C "$DASHBOARD_DIR" pull --ff-only
else
    git clone "$REPO" "$DASHBOARD_DIR"
fi
ok "Repo at $DASHBOARD_DIR"

# ── Aggregation directory ──────────────────────────────────────────────────────
mkdir -p "$AGG_DIR"
ok "Aggregation dir: $AGG_DIR"

# ── Sync script ───────────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
cp "$DASHBOARD_DIR/deploy/sync-claude-sessions.sh" "$BIN_DIR/sync-claude-sessions.sh"
chmod +x "$BIN_DIR/sync-claude-sessions.sh"
ok "Sync script installed to $BIN_DIR/sync-claude-sessions.sh"

# ── systemd user units ─────────────────────────────────────────────────────────
mkdir -p "$SYSTEMD_DIR"

cp "$DASHBOARD_DIR/deploy/systemd/claude-sync.service"  "$SYSTEMD_DIR/"
cp "$DASHBOARD_DIR/deploy/systemd/claude-sync.timer"    "$SYSTEMD_DIR/"
cp "$DASHBOARD_DIR/deploy/systemd/token-dashboard.service" "$SYSTEMD_DIR/"

# Patch the LAN IP into the dashboard service
sed -i "s|HOST=192.168.1.x|HOST=${LAN_IP}|" "$SYSTEMD_DIR/token-dashboard.service"

systemctl --user daemon-reload
systemctl --user enable --now claude-sync.timer
systemctl --user enable --now token-dashboard.service

ok "systemd units installed and started"

# ── First sync ────────────────────────────────────────────────────────────────
echo
echo "Running first sync (Mac must be reachable via SSH alias 'mac')..."
"$BIN_DIR/sync-claude-sessions.sh" || warn "First sync had errors — check above. The timer will retry hourly."

# ── First scan ────────────────────────────────────────────────────────────────
echo
echo "Running first DB scan (may take a minute on first run)..."
python3 "$DASHBOARD_DIR/cli.py" scan --projects-dir "$AGG_DIR"

# ── Done ───────────────────────────────────────────────────────────────────────
echo
ok "Installation complete."
echo
echo "  Dashboard URL: http://${LAN_IP}:${PORT}/"
echo
echo "  Open that URL from your Mac browser."
echo
echo -e "${YELLOW}One manual step required:${NC}"
echo "  sudo loginctl enable-linger \$(whoami)"
echo "  (lets user units survive logout — do this once)"
echo
echo "Check status any time:"
echo "  systemctl --user status claude-sync.timer"
echo "  systemctl --user status token-dashboard"
echo "  journalctl --user -u claude-sync.service -n 20"
