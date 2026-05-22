#!/usr/bin/env bash
# sync-claude-sessions.sh
# Pulls Claude Code sessions from the Mac and mirrors local VPS sessions
# into ~/claude-sessions/ with machine-prefix subdirectories.
#
# Mac projects  → ~/claude-sessions/mac__<slug>/
# VPS projects  → ~/claude-sessions/vps__<slug>/
#
# The token dashboard reads ~/claude-sessions/ as its projects root.
# Prefixed directory names are how the machine filter in the UI tells
# mac__ rows from vps__ rows.
#
# Copyright (c) 2026 VGX Global Consulting (OPC) Pvt Ltd

set -euo pipefail

MAC_SSH="mac"
MAC_PROJECTS="/Users/vijendra/.claude/projects"
VPS_PROJECTS="${HOME}/.claude/projects"
AGG_DIR="${HOME}/claude-sessions"

mkdir -p "$AGG_DIR"

log() { echo "[$(date -Iseconds)] $*"; }

# ── Pull from Mac ─────────────────────────────────────────────────────────────
if ssh -q -o BatchMode=yes -o ConnectTimeout=5 "$MAC_SSH" exit 2>/dev/null; then
    mapfile -t mac_slugs < <(ssh "$MAC_SSH" ls "$MAC_PROJECTS" 2>/dev/null || true)
    for slug in "${mac_slugs[@]:-}"; do
        [[ -z "$slug" ]] && continue
        mkdir -p "$AGG_DIR/mac__${slug}"
        rsync -a --delete \
              "$MAC_SSH:$MAC_PROJECTS/$slug/" \
              "$AGG_DIR/mac__${slug}/"
    done
    # Remove stale mac__ dirs for projects that no longer exist on Mac
    for d in "$AGG_DIR"/mac__*/; do
        [[ -d "$d" ]] || continue
        slug="${d#${AGG_DIR}/mac__}"; slug="${slug%/}"
        printf '%s\n' "${mac_slugs[@]:-}" | grep -qxF "$slug" || rm -rf "$d"
    done
    log "mac pull OK (${#mac_slugs[@]:-0} projects)"
else
    log "mac pull SKIPPED — $MAC_SSH unreachable, will retry on next run"
fi

# ── Mirror VPS local sessions ─────────────────────────────────────────────────
if [[ -d "$VPS_PROJECTS" ]]; then
    mapfile -t vps_slugs < <(ls "$VPS_PROJECTS" 2>/dev/null || true)
    for slug in "${vps_slugs[@]:-}"; do
        [[ -z "$slug" ]] && continue
        mkdir -p "$AGG_DIR/vps__${slug}"
        rsync -a --delete \
              "$VPS_PROJECTS/$slug/" \
              "$AGG_DIR/vps__${slug}/"
    done
    # Remove stale vps__ dirs
    for d in "$AGG_DIR"/vps__*/; do
        [[ -d "$d" ]] || continue
        slug="${d#${AGG_DIR}/vps__}"; slug="${slug%/}"
        printf '%s\n' "${vps_slugs[@]:-}" | grep -qxF "$slug" || rm -rf "$d"
    done
    log "vps sync OK (${#vps_slugs[@]:-0} projects)"
else
    log "vps sync SKIPPED — $VPS_PROJECTS does not exist yet"
fi
