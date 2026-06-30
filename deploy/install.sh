#!/usr/bin/env bash
# install.sh — one-shot VPS installer for claude-token-dashboard.
# Run this on the VPS. Then run deploy/mac/install-mac.sh on the Mac.
#
# What this does:
#   1. Checks prerequisites
#   2. Clones the repo to $DASHBOARD_DIR
#   3. Creates $AGG_DIR (aggregation directory the dashboard reads)
#   4. Installs 3 system-level systemd units (no loginctl linger needed)
#   5. Auto-detects the VPS LAN IP and patches service files
#   6. Runs the first VPS session mirror and first DB scan
#   7. Prints the dashboard URL and next steps
#
# Copyright (c) 2026 VGX Global Consulting (OPC) Pvt Ltd

set -euo pipefail

REPO="https://github.com/VijendraMalhotra/claude-token-dashboard.git"
DASHBOARD_DIR="${HOME}/Workspace/ConsultingGitRepos/VGX/claude-token-dashboard"
AGG_DIR="${HOME}/claude-sessions"
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
mkdir -p "$(dirname "$DASHBOARD_DIR")"
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

# ── System-level systemd units ────────────────────────────────────────────────
sudo cp "$DASHBOARD_DIR/deploy/systemd/claude-sync.service"     /etc/systemd/system/
sudo cp "$DASHBOARD_DIR/deploy/systemd/claude-sync.timer"       /etc/systemd/system/
sudo cp "$DASHBOARD_DIR/deploy/systemd/token-dashboard.service" /etc/systemd/system/

# Patch real values into the installed service files
sudo sed -i "s|DASHBOARD_DIR_PLACEHOLDER|${DASHBOARD_DIR}|g" /etc/systemd/system/claude-sync.service
sudo sed -i "s|DASHBOARD_DIR_PLACEHOLDER|${DASHBOARD_DIR}|g" /etc/systemd/system/token-dashboard.service
sudo sed -i "s|AGG_DIR_PLACEHOLDER|${AGG_DIR}|g"             /etc/systemd/system/token-dashboard.service
sudo sed -i "s|USER_PLACEHOLDER|$(whoami)|g"                  /etc/systemd/system/claude-sync.service
sudo sed -i "s|USER_PLACEHOLDER|$(whoami)|g"                  /etc/systemd/system/token-dashboard.service
sudo sed -i "s|HOST=LAN_IP_PLACEHOLDER|HOST=${LAN_IP}|"       /etc/systemd/system/token-dashboard.service

sudo systemctl daemon-reload
sudo systemctl enable --now claude-sync.timer
sudo systemctl enable --now token-dashboard.service

ok "System services installed and started"

# ── First VPS session mirror ──────────────────────────────────────────────────
echo
echo "Mirroring VPS local sessions..."
bash "$DASHBOARD_DIR/deploy/sync-vps-local.sh" || warn "Mirror had errors — check above."

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
echo "  Mac sessions will appear once you run on the Mac:"
echo "    bash ${DASHBOARD_DIR}/deploy/mac/install-mac.sh"
echo
echo "Check status:"
echo "  sudo systemctl status token-dashboard"
echo "  sudo systemctl status claude-sync.timer"
echo "  journalctl -u claude-sync.service -n 20"
