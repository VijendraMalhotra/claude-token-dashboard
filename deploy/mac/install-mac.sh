#!/usr/bin/env bash
# install-mac.sh — run once on the Mac to set up the on-demand push to VPS.
#
# What this does:
#   1. Verifies SSH to the VPS works
#   2. Installs a `push-claude-stats` fish function that calls mac-push.sh
#   3. Runs the first push
#
# There is no scheduler by design. macOS launchd and cron run in a TCC context
# that cannot read ~/.ssh when it symlinks into cloud storage (OneDrive,
# Dropbox, iCloud); the key read fails with "Operation not permitted" and every
# scheduled run fails silently. Session data only changes when Claude Code runs,
# so pushing by hand costs nothing.
#
# Prerequisites:
#   - SSH alias "VGUbuntu" in ~/.ssh/config pointing at the VPS
#   - Key auth already works: ssh VGUbuntu 'ls' succeeds without a password
#   - The VPS must have ~/claude-sessions/ (run install.sh on the VPS first)
#
# Copyright (c) 2026 VGX Global Consulting (OPC) Pvt Ltd

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FISH_FUNCS="${HOME}/.config/fish/functions"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
ok()  { echo -e "${GREEN}\u2713${NC} $*"; }
die() { echo -e "${RED}\u2717${NC} $*" >&2; exit 1; }

echo "=== Mac push installer (on-demand) ==="
echo

ssh -q -o BatchMode=yes -o ConnectTimeout=5 VGUbuntu exit 2>/dev/null \
    || die "Cannot reach VPS via SSH alias 'VGUbuntu'. Check ~/.ssh/config and key auth."
ok "SSH to VPS works"

# Remove any legacy launchd agent from the old scheduled design
LEGACY_PLIST="${HOME}/Library/LaunchAgents/com.vgx.claude-push.plist"
if [[ -f "$LEGACY_PLIST" ]]; then
    launchctl unload "$LEGACY_PLIST" 2>/dev/null || true
    rm -f "$LEGACY_PLIST"
    ok "Removed legacy launchd agent (it could never read ~/.ssh)"
fi

if [[ -d "$FISH_FUNCS" ]]; then
    # Fish autoloads by filename, so the file name must match the function name.
    sed "s|@SCRIPT_DIR@|${SCRIPT_DIR}|g" \
        "$SCRIPT_DIR/push-claude-stats.fish" > "${FISH_FUNCS}/push-claude-stats.fish"
    rm -f "${FISH_FUNCS}/claude-push.fish"   # superseded name
    ok "Installed fish function: push-claude-stats (push + rescan + summary)"
else
    ok "No fish config found — run the push with: bash ${SCRIPT_DIR}/mac-push.sh"
fi

echo
echo "Running first push..."
bash "$SCRIPT_DIR/mac-push.sh"

echo
ok "Done."
echo
echo "Push now:   push-claude-stats   # rsync up, rescan, print the summary"
echo "Dashboard:  http://<vps>:8080/#/overview"
