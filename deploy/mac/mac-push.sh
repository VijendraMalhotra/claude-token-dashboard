#!/usr/bin/env bash
# mac-push.sh — runs on Mac, pushes Claude Code sessions to the VPS.
# Called hourly by launchd via com.vgx.claude-push.plist.
#
# Mac sessions land in ~/claude-sessions/mac__<slug>/ on the VPS,
# where the token dashboard picks them up via the machine filter.
#
# Copyright (c) 2026 VGX Global Consulting (OPC) Pvt Ltd

set -euo pipefail

VPS_SSH="vps"                                    # SSH alias for the internal VPS
VPS_AGG="/home/vijendra/claude-sessions"         # aggregation dir on the VPS
MAC_PROJECTS="${HOME}/.claude/projects"

log() { echo "[$(date -Iseconds)] $*"; }

if [[ ! -d "$MAC_PROJECTS" ]]; then
    log "SKIPPED — $MAC_PROJECTS does not exist"
    exit 0
fi

# Test connectivity before iterating — fail fast if VPS is unreachable
if ! ssh -q -o BatchMode=yes -o ConnectTimeout=5 "$VPS_SSH" exit 2>/dev/null; then
    log "FAILED — cannot reach $VPS_SSH (VPS down or SSH key issue)"
    exit 1
fi

mapfile -t slugs < <(ls "$MAC_PROJECTS" 2>/dev/null || true)

for slug in "${slugs[@]:-}"; do
    [[ -z "$slug" ]] && continue
    rsync -a --delete \
          "$MAC_PROJECTS/$slug/" \
          "$VPS_SSH:$VPS_AGG/mac__${slug}/"
done

# Remove stale mac__ dirs on VPS for projects deleted on Mac
remote_dirs=$(ssh "$VPS_SSH" "ls -d ${VPS_AGG}/mac__*/ 2>/dev/null || true")
for d in $remote_dirs; do
    slug="${d#${VPS_AGG}/mac__}"; slug="${slug%/}"
    printf '%s\n' "${slugs[@]:-}" | grep -qxF "$slug" \
        || ssh "$VPS_SSH" "rm -rf '${VPS_AGG}/mac__${slug}'"
done

log "push OK (${#slugs[@]:-0} projects → $VPS_SSH:$VPS_AGG)"
