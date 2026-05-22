#!/usr/bin/env bash
# install-mac.sh — run once on the Mac to set up the hourly push to VPS.
#
# What this does:
#   1. Installs mac-push.sh to ~/bin/
#   2. Loads the launchd plist for hourly execution
#   3. Runs the first push immediately
#
# Prerequisites:
#   - SSH alias "vps" must exist in ~/.ssh/config pointing at the VPS
#   - SSH key auth must already work: ssh vps 'ls' should succeed without a password
#   - The VPS must have ~/claude-sessions/ created (run install.sh on VPS first)
#
# Copyright (c) 2026 VGX Global Consulting (OPC) Pvt Ltd

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/bin"
PLIST_NAME="com.vgx.claude-push"
PLIST_DST="${HOME}/Library/LaunchAgents/${PLIST_NAME}.plist"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

echo "=== Mac push installer ==="
echo

# ── Check SSH to VPS ──────────────────────────────────────────────────────────
ssh -q -o BatchMode=yes -o ConnectTimeout=5 vps exit 2>/dev/null \
    || die "Cannot reach VPS via SSH alias 'vps'. Check ~/.ssh/config and key auth."
ok "SSH to VPS works"

# ── Install push script ───────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
cp "$SCRIPT_DIR/mac-push.sh" "$BIN_DIR/mac-push.sh"
chmod +x "$BIN_DIR/mac-push.sh"
ok "Push script installed to $BIN_DIR/mac-push.sh"

# ── Install launchd plist ─────────────────────────────────────────────────────
mkdir -p "${HOME}/Library/LaunchAgents"
cp "$SCRIPT_DIR/com.vgx.claude-push.plist" "$PLIST_DST"

# Unload first if already loaded (idempotent reinstall)
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"
ok "launchd agent loaded (runs every hour, survives logout)"

# ── First push ────────────────────────────────────────────────────────────────
echo
echo "Running first push..."
"$BIN_DIR/mac-push.sh"

echo
ok "Done. Mac will push sessions to VPS every hour automatically."
echo
echo "Monitor with:"
echo "  tail -f ~/Library/Logs/claude-push.log"
echo
echo "Force a push now:"
echo "  ~/bin/mac-push.sh"
