#!/usr/bin/env bash
# install.sh — one-shot VPS installer for claude-token-dashboard.
# Run this on the VPS. Then run deploy/mac/install-mac.sh on the Mac.
#
# What this does:
#   1. Checks prerequisites
#   2. Clones the repo to ~/token-dashboard/
#   3. Creates ~/claude-sessions/ (the aggregation directory)
#   4. Installs sync-vps-local.sh to ~/bin/
#   5. Installs 3 system-level systemd units (no loginctl linger needed)
#   6. Auto-detects the VPS LAN IP and patches the dashboard service
#   7. Runs the first VPS session mirror and first DB scan
#   8. Prints the dashboard URL and next steps
#
# Copyright (c) 2026 VGX Global Consulting (OPC) Pvt Ltd

set -euo pipefail

REPO="https://github.com/VijendraMalhotra/claude-token-dashboard.git"
DASHBOARD_DIR="/home/vijendra/token-dashboard"
AGG_DIR="/home/vijendra/claude-sessions"
BIN_DIR="/home/vijendra/bin"
PORT=8080

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

echo "=== Token Dashboard VPS installer ==="
echo

# ── Prerequisites ─────────────────────────────────────────────────────────────
for cmd in python3 git rsync; do
    command -v "$cmd" &>/dev/null || die "Required: $cmd"
done
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)' \
    || die "Python 3.8+ required"
ok "Prerequisites OK"

# ── Detect LAN IP ─────────────────────────────────────────────────────────────
LAN_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+' | head -1 || true)
if [[ -z "$LAN_IP" ]]; then
    warn "Could not auto-detect LAN IP. Edit /etc/systemd/system/token-dashboard.service and set HOST= manually."
    LAN_IP="127.0.0.1"
fi
ok "LAN IP: $LAN_IP"

# ── Clone or update repo ──────────────────────────────────────────────────────
if [[ -d "$DASHBOARD_DIR/.git" ]]; then
    warn "Repo already exists — pulling latest."
    git -C "$DASHBOARD_DIR" pull --ff-only
else
    git clone "$REPO" "$DASHBOARD_DIR"
fi
ok "Repo at $DASHBOARD_DIR"

# ── Aggregation directory ─────────────────────────────────────────────────────
mkdir -p "$AGG_DIR"
ok "Aggregation dir: $AGG_DIR"

# ── VPS local sync script ─────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
cp "$DASHBOARD_DIR/deploy/sync-vps-local.sh" "$BIN_DIR/sync-vps-local.sh"
chmod +x "$BIN_DIR/sync-vps-local.sh"
ok "VPS sync script installed to $BIN_DIR/sync-vps-local.sh"

# ── System-level systemd units ────────────────────────────────────────────────
sudo cp "$DASHBOARD_DIR/deploy/systemd/claude-sync.service"     /etc/systemd/system/
sudo cp "$DASHBOARD_DIR/deploy/systemd/claude-sync.timer"       /etc/systemd/system/
sudo cp "$DASHBOARD_DIR/deploy/systemd/token-dashboard.service" /etc/systemd/system/

# Patch the LAN IP into the dashboard service
sudo sed -i "s|HOST=192.168.1.x|HOST=${LAN_IP}|" /etc/systemd/system/token-dashboard.service

sudo systemctl daemon-reload
sudo systemctl enable --now claude-sync.timer
sudo systemctl enable --now token-dashboard.service

ok "System services installed and started (no loginctl linger needed)"

# ── First VPS session mirror ──────────────────────────────────────────────────
echo
echo "Mirroring VPS local sessions..."
"$BIN_DIR/sync-vps-local.sh" || warn "Mirror had errors — check above."

# ── First DB scan ─────────────────────────────────────────────────────────────
echo
echo "Running first DB scan..."
python3 "$DASHBOARD_DIR/cli.py" scan --projects-dir "$AGG_DIR"

# ── Done ──────────────────────────────────────────────────────────────────────
echo
ok "VPS install complete."
echo
echo "  Dashboard URL: http://${LAN_IP}:${PORT}/"
echo
echo "  Mac sessions will appear once you run install-mac.sh on the Mac:"
echo "    bash ~/token-dashboard/deploy/mac/install-mac.sh"
echo
echo "Check status:"
echo "  sudo systemctl status token-dashboard"
echo "  sudo systemctl status claude-sync.timer"
echo "  journalctl -u claude-sync.service -n 20"
