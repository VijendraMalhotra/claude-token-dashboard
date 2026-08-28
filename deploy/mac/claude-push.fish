# claude-push — push this Mac's Claude Code sessions to the VPS dashboard.
#
# Installed to ~/.config/fish/functions/ by install-mac.sh, which replaces
# @SCRIPT_DIR@ with the repo's deploy/mac path.
#
# Deliberately manual: macOS launchd and cron run in a TCC context that cannot
# read ~/.ssh when it symlinks into cloud storage, so a scheduled version fails
# silently forever. Session data only changes when Claude Code runs, so running
# this after a work session loses nothing.
#
# Copyright (c) 2026 VGX Global Consulting (OPC) Pvt Ltd

function claude-push --description 'Push Claude Code sessions from this Mac to the VPS dashboard, then rescan'
    set -l script_dir '@SCRIPT_DIR@'
    set -l vps_ssh VGUbuntu

    # Dashboard URL follows the SSH alias, so there is no second place to update
    # when the VPS moves. Override with TOKEN_DASHBOARD_URL.
    set -l url $TOKEN_DASHBOARD_URL
    if test -z "$url"
        set -l host (ssh -G $vps_ssh 2>/dev/null | awk '/^hostname /{print $2}')
        if test -z "$host"
            echo "claude-push: cannot resolve a host for SSH alias '$vps_ssh' — check ~/.ssh/config" >&2
            return 1
        end
        set url "http://$host:8080"
    end

    # 1. rsync the sessions up
    bash $script_dir/mac-push.sh
    set -l push_status $status
    if test $push_status -ne 0
        echo "claude-push: push failed — are you on the home LAN?" >&2
        return $push_status
    end

    # 2. rescan. Files on disk are invisible to the dashboard until it reads
    #    them into SQLite, so pushing without scanning shows stale numbers.
    set -l code (curl -s -o /dev/null -w '%{http_code}' -m 600 "$url/api/scan")
    if test "$code" != 200
        echo "claude-push: pushed OK, but the rescan failed (HTTP $code at $url)" >&2
        echo "             is token-dashboard running on the VPS?" >&2
        return 1
    end
    echo "scan OK"

    # 3. show where things stand
    echo
    curl -s -m 60 "$url/api/summary" | python3 -c '
import json, sys
MARK = {"good": " ok ", "watch": "warn", "act": "ACT ", "info": " -- "}
try:
    cards = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for c in cards:
    print("  [{}] {:<22} {}".format(MARK.get(c["verdict"], " ?? "), c["label"], c["value"]))
'
    echo
    echo "  $url/#/overview"
end
