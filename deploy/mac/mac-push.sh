#!/usr/bin/env bash
# mac-push.sh — runs on Mac, pushes Claude Code sessions to the VPS.
# Run on demand: `push-claude-stats` (fish function) or `bash deploy/mac/mac-push.sh`.
#
# Deliberately NOT scheduled. launchd/cron on macOS cannot read ~/.ssh when it
# symlinks into cloud storage (TCC denies the read), so a background schedule
# fails silently forever. Session data only changes when Claude Code runs, so
# running this by hand loses nothing.
#
# Mac sessions land in ~/claude-sessions/mac__<slug>/ on the VPS,
# where the token dashboard picks them up via the machine filter.
#
# Copyright (c) 2026 VGX Global Consulting (OPC) Pvt Ltd

set -euo pipefail

VPS_SSH="VGUbuntu"                               # SSH alias for the internal VPS
VPS_AGG='~/claude-sessions'                      # aggregation dir on the VPS (expanded by remote shell)
MAC_PROJECTS="${HOME}/.claude/projects"

log() { echo "[$(date -Iseconds)] $*"; }

if [[ ! -d "$MAC_PROJECTS" ]]; then
    log "SKIPPED — $MAC_PROJECTS does not exist"
    exit 0
fi

# Test connectivity before iterating — fail fast if VPS is unreachable
if ! ssh -q -o BatchMode=yes -o ConnectTimeout=5 "$VPS_SSH" exit 2>/dev/null; then
    log "FAILED — cannot reach $VPS_SSH (not on home LAN, VPS down, or SSH key issue)"
    exit 1
fi

slugs=()
while IFS= read -r slug; do
    [[ -n "$slug" ]] && slugs+=("$slug")
done < <(ls "$MAC_PROJECTS" 2>/dev/null || true)

# --out-format prints one line per transferred item; count the files (not the
# directory entries, which end in /) so the caller can see what actually moved.
total_files=0
for slug in "${slugs[@]:-}"; do
    n=$(rsync -a --delete --out-format='%n' \
              "$MAC_PROJECTS/$slug/" \
              "$VPS_SSH:$VPS_AGG/mac__${slug}/" | grep -cv '/$' || true)
    if [[ "$n" -gt 0 ]]; then
        short="$slug"
        [[ ${#short} -gt 46 ]] && short="...${short: -43}"
        printf '    %-46s %4d file(s)\n' "$short" "$n"
        total_files=$((total_files + n))
    fi
done

# Remove stale mac__ dirs on VPS for projects deleted on Mac.
# List basenames only — a remote `ls -d ~/dir/*` returns EXPANDED absolute paths,
# so stripping the literal '~/claude-sessions/' prefix silently fails and every
# dir gets misclassified as stale. Let the remote shell expand $HOME instead.
# Read line-by-line: `for d in $remote_dirs` depends on IFS word-splitting and
# collapses to a single blob if IFS is unset, which classifies every dir as stale.
while IFS= read -r d; do
    slug="${d#mac__}"; slug="${slug%/}"
    [[ -n "$slug" ]] || continue
    if ! printf '%s\n' "${slugs[@]:-}" | grep -qxF -- "$slug"; then
        log "removing stale remote dir: mac__${slug}"
        # -n: without it ssh drains this loop's stdin and skips remaining dirs
        ssh -n "$VPS_SSH" "rm -rf \"\$HOME/claude-sessions/mac__${slug}\""
    fi
done < <(ssh "$VPS_SSH" "cd ${VPS_AGG} 2>/dev/null && ls -1d mac__*/ 2>/dev/null || true")

log "push OK — ${#slugs[@]} projects, ${total_files} file(s) changed → $VPS_SSH:$VPS_AGG"
