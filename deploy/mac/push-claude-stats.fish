# push-claude-stats — push this Mac's Claude Code sessions to the VPS dashboard.
#
# Installed to ~/.config/fish/functions/ by install-mac.sh, which replaces
# @SCRIPT_DIR@ with the repo's deploy/mac path. Fish autoloads by filename, so
# this file's name and the function name below must stay in step.
#
# Deliberately manual: macOS launchd and cron run in a TCC context that cannot
# read ~/.ssh when it symlinks into cloud storage, so a scheduled version fails
# silently forever. Session data only changes when Claude Code runs, so running
# this after a work session loses nothing.
#
# Copyright (c) 2026 VGX Global Consulting (OPC) Pvt Ltd

function __pcs_col -a name
    # Colour only when attached to a terminal, so piping stays clean.
    isatty stdout; and set_color $name
end

function __pcs_step -a n total label
    __pcs_col cyan; printf '[%s/%s] ' $n $total; __pcs_col normal
    __pcs_col --bold; printf '%s\n' $label; __pcs_col normal
end

function push-claude-stats --description 'Push Claude Code sessions from this Mac to the VPS dashboard, then rescan'
    set -l script_dir '@SCRIPT_DIR@'
    set -l vps_ssh VGUbuntu
    set -l t_start (date +%s)

    # Dashboard URL follows the SSH alias, so there is no second place to update
    # when the VPS moves. Override with TOKEN_DASHBOARD_URL.
    set -l url $TOKEN_DASHBOARD_URL
    set -l host (ssh -G $vps_ssh 2>/dev/null | awk '/^hostname /{print $2}')
    if test -z "$url"
        if test -z "$host"
            echo "push-claude-stats: cannot resolve a host for SSH alias '$vps_ssh' — check ~/.ssh/config" >&2
            return 1
        end
        set url "http://$host:8080"
    end

    __pcs_col --bold; printf 'push-claude-stats'; __pcs_col normal
    printf ' → %s (%s)\n\n' $vps_ssh (test -n "$host"; and echo $host; or echo "$url")

    # ── 1. rsync the sessions up ─────────────────────────────────────────────
    __pcs_step 1 3 "rsync sessions to $vps_ssh"
    set -l t0 (date +%s)
    bash $script_dir/mac-push.sh
    set -l push_status $status
    if test $push_status -ne 0
        __pcs_col red
        echo "  push failed — are you on the home LAN? ($vps_ssh is a LAN address)" >&2
        __pcs_col normal
        return $push_status
    end
    printf '      %ss\n\n' (math (date +%s) - $t0)

    # ── 2. rescan ────────────────────────────────────────────────────────────
    # Forces the newly-pushed JSONL into SQLite now. The dashboard also runs its
    # own scan loop every 30s (server._scan_loop), so this is about making the
    # data visible immediately, not about it arriving at all — which is why a
    # zero count here is normal rather than a failure.
    __pcs_step 2 3 "rescan on the dashboard"
    set -l t0 (date +%s)
    set -l scan (curl -s -m 600 -w '\n%{http_code}' "$url/api/scan" | string split '\n')
    if test "$scan[-1]" != 200
        __pcs_col red
        echo "  pushed OK, but the rescan failed (HTTP $scan[-1] at $url)" >&2
        echo "  is token-dashboard running on the VPS?" >&2
        __pcs_col normal
        return 1
    end
    echo "$scan[1]" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit
m, t, f = d.get("messages", 0), d.get("tools", 0), d.get("files", 0)
if m or t or f:
    print("      ingested {:,} message(s), {:,} tool call(s) from {:,} file(s)".format(m, t, f))
else:
    print("      already current — the dashboard also self-scans every 30s")
'
    printf '      %ss\n\n' (math (date +%s) - $t0)

    # ── 3. where things stand ────────────────────────────────────────────────
    __pcs_step 3 3 "verdict"
    curl -s -m 60 "$url/api/summary" | python3 -c '
import json, sys
MARK = {"good": " ok ", "watch": "warn", "act": "ACT ", "info": " -- "}
try:
    cards = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for c in cards:
    print("      [{}] {:<22} {}".format(MARK.get(c["verdict"], " ?? "), c["label"], c["value"]))
'
    curl -s -m 30 "$url/api/overview" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit
print("      {:,} sessions - {:,} turns tracked".format(d.get("sessions", 0), d.get("turns", 0)))
'
    printf '\n'
    __pcs_col blue; printf '%s/#/overview' $url; __pcs_col normal
    printf '   (%ss total)\n' (math (date +%s) - $t_start)
end
