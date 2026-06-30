#!/usr/bin/env bash
# install-mac.sh — run once on the Mac to set up the hourly push to VPS.
#
# What this does:
#   1. Copies mac-push.sh to ~/bin/ (launchd needs an absolute path)
#   2. Patches and loads the launchd plist for hourly execution
#   3. Runs the first push immediately
#
# Prerequisites:
#   - SSH alias "VGUbuntu" must exist in ~/.ssh/config pointing at the VPS
#   - SSH key auth must already work: ssh VGUbuntu 'ls' should succeed without a password
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
ssh -q -o BatchMode=yes -o ConnectTimeout=5 VGUbuntu exit 2>/dev/null \
    || die "Cannot reach VPS via SSH alias 'VGUbuntu'. Check ~/.ssh/config and key auth."
ok "SSH to VPS works"

# ── Install push script ───────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
cp "$SCRIPT_DIR/mac-push.sh" "$BIN_DIR/mac-push.sh"
chmod +x "$BIN_DIR/mac-push.sh"
ok "Push script installed to $BIN_DIR/mac-push.sh"

# ── Install launchd plist (patch HOME first — launchd can't expand ~) ────────
mkdir -p "${HOME}/Library/LaunchAgents"
sed "s|HOME_PLACEHOLDER|${HOME}|g" "$SCRIPT_DIR/com.vgx.claude-push.plist" > "$PLIST_DST"

# Unload first if already loaded (idempotent reinstall)
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"
ok "launchd agent loaded (runs every hour + at login)"

# ── First push ────────────────────────────────────────────────────────────────
echo
echo "Running first push..."
"$BIN_DIR/mac-push.sh"

echo
ok "Done. Mac will push sessions to VPS every hour automatically."
echo
echo "Monitor:"
echo "  tail -f ~/Library/Logs/claude-push.log"
echo
echo "Force push now:"
echo "  ~/bin/mac-push.sh"
