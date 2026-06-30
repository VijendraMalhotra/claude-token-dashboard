#!/usr/bin/env bash
# sync-vps-local.sh — runs on VPS, mirrors local Claude Code sessions
# into the aggregation directory with the vps__ prefix.
#
# Mac sessions arrive via mac-push.sh (run on the Mac) and land directly
# in ~/claude-sessions/mac__<slug>/ — this script does not touch them.
#
# Called by the claude-sync systemd service (system-level).
#
# Copyright (c) 2026 VGX Global Consulting (OPC) Pvt Ltd

set -euo pipefail

VPS_PROJECTS="${HOME}/.claude/projects"
AGG_DIR="${HOME}/claude-sessions"

log() { echo "[$(date -Iseconds)] $*"; }

mkdir -p "$AGG_DIR"

if [[ ! -d "$VPS_PROJECTS" ]]; then
    log "SKIPPED — $VPS_PROJECTS does not exist yet"
    exit 0
fi

mapfile -t slugs < <(ls "$VPS_PROJECTS" 2>/dev/null || true)

for slug in "${slugs[@]:-}"; do
    [[ -z "$slug" ]] && continue
    mkdir -p "$AGG_DIR/vps__${slug}"
    rsync -a --delete \
          "$VPS_PROJECTS/$slug/" \
          "$AGG_DIR/vps__${slug}/"
done

# Prune stale vps__ dirs for projects deleted locally
for d in "$AGG_DIR"/vps__*/; do
    [[ -d "$d" ]] || continue
    slug="${d#${AGG_DIR}/vps__}"; slug="${slug%/}"
    printf '%s\n' "${slugs[@]:-}" | grep -qxF -- "$slug" || rm -rf "$d"
done

log "vps sync OK (${#slugs[@]} projects)"
