"""Executive summary — verdicts, not data.

Every card answers "is this fine or not", with one number and one sentence.
The dashboard tabs already show the underlying data; this is the layer that
saves the reader from re-deriving the same conclusion every visit.
"""
from __future__ import annotations

import re
import statistics
from typing import Optional

from .db import prompt_spans, opus_fallback_events
from .pricing import cost_for

# Correction markers. A prompt matching one of these is usually the user telling
# Claude the previous turn was wrong. It is a HEURISTIC — "no" also matches
# "no worries" — so it is reported as a rate to watch, never as an exact count.
REWORK_RE = re.compile(r"""\b(
 no|nope|nah|wrong|incorrect|again|revert|undo|rollback|broken|failed|failing|
 still\s+(not|the\s+same|broken|failing|there)|try\s+again|not\s+working|
 does\s?n[o']?t\s+work|did\s?n[o']?t\s+work|same\s+(error|issue)|
 i\s+said|i\s+asked|as\s+i\s+said|that.s\s+not|thats\s+not|
 why\s+(is\s+it|did)|nothing\s+(seems|happen)|fix\s+it|
 you\s+(missed|forgot|removed|broke)
)\b""", re.I | re.X)

# An Opus span this small is a question, not an engineering task.
_RIGHTSIZE_TURNS = 2
_RIGHTSIZE_TOOLS = 1


def _est_note(est_cost, total):
    """Say so when the figure leans on tier-fallback rates rather than exact ones.

    A model missing from pricing.json is priced by name match against its tier,
    so a rate change or a new tier silently skews every cost on the dashboard.
    """
    if not total or est_cost <= 0:
        return ""
    share = 100.0 * est_cost / total
    return (" %.0f%% of this is estimated from tier-fallback rates — add the exact "
            "models to pricing.json to firm it up." % share)


def _card(key, label, value, verdict, detail):
    return {"key": key, "label": label, "value": value,
            "verdict": verdict, "detail": detail}


def exec_summary(db_path, pricing, plan="api", machine=None,
                 since=None, until=None) -> list:
    rows = prompt_spans(db_path, machine=machine, since=since, until=until)
    if not rows:
        return [_card("empty", "No prompts", "—", "info",
                      "Nothing in range. Run a scan or widen the date range.")]

    est_cost = 0.0
    for r in rows:
        r["cost"] = 0.0
        for u in r["usage_by_model"]:
            c = cost_for(u["model"], u, pricing)
            usd = c["usd"] or 0
            r["cost"] += usd
            if c["estimated"] or c["usd"] is None:
                est_cost += usd

    total = sum(r["cost"] for r in rows)
    monthly = pricing["plans"].get(plan, {}).get("monthly", 0)
    subscription = plan != "api" and monthly > 0
    cards = []

    # ── 1. what the usage was worth ───────────────────────────────────────────
    if subscription:
        # Value multiple only makes sense against the months actually covered.
        days = len({r["timestamp"][:10] for r in rows})
        months = max(days / 30.0, 1 / 30.0)
        mult = total / (monthly * months) if monthly else 0
        cards.append(_card(
            "value", "Value vs plan", "%.0f×" % mult,
            "good" if mult >= 3 else "info",
            "$%s of API-equivalent usage over %d active days on a $%d/mo plan. "
            "You are not billed this — it is what the same work would have cost on the API.%s"
            % ("{:,.0f}".format(total), days, monthly, _est_note(est_cost, total))))
    else:
        cards.append(_card(
            "spend", "API-equivalent spend", "$%s" % "{:,.0f}".format(total), "info",
            "Across %d prompts. Set your plan in Settings if you are on a subscription — "
            "this figure is pay-per-token pricing.%s"
            % (len(rows), _est_note(est_cost, total))))

    # ── 2. prompt health ──────────────────────────────────────────────────────
    med_turns = statistics.median(r["turns"] for r in rows)
    med_tools = statistics.median(r["tool_calls"] for r in rows)
    cards.append(_card(
        "turns", "Prompt health", "%g turns" % med_turns,
        "good" if med_turns <= 4 else ("watch" if med_turns <= 8 else "act"),
        "Median prompt resolves in %g turns and %g tool call%s. "
        "Rising medians mean prompts are landing less cleanly."
        % (med_turns, med_tools, "" if med_tools == 1 else "s")))

    # ── 3. cache discipline ───────────────────────────────────────────────────
    hits = [r["cache_hit_pct"] for r in rows if r["cache_hit_pct"] is not None]
    if hits:
        med_hit = statistics.median(hits)
        cards.append(_card(
            "cache", "Cache discipline", "%.0f%%" % med_hit,
            "good" if med_hit >= 80 else ("watch" if med_hit >= 60 else "act"),
            "Median share of context served from cache. Low values mean context churn — "
            "editing many files, or clearing sessions too often."))

    # ── 4. rework ─────────────────────────────────────────────────────────────
    rework = [r for r in rows if REWORK_RE.search((r["prompt_text"] or "")[:200])]
    rate = 100.0 * len(rework) / len(rows)
    cards.append(_card(
        "rework", "Rework rate", "%.0f%%" % rate,
        "good" if rate <= 12 else ("watch" if rate <= 20 else "act"),
        "%d of %d prompts read as corrections of the previous turn. "
        "Keyword heuristic, so treat it as a direction, not a count." % (len(rework), len(rows))))

    # ── 5. right-sizing ───────────────────────────────────────────────────────
    opus = [r for r in rows if "opus" in (r["model"] or "")]
    small = [r for r in opus
             if r["turns"] <= _RIGHTSIZE_TURNS and r["tool_calls"] <= _RIGHTSIZE_TOOLS]
    if opus:
        opus_cost = sum(r["cost"] for r in small)
        sonnet_cost = 0.0
        for r in small:
            for u in r["usage_by_model"]:
                cheap = dict(u, model="claude-sonnet-4-6")
                sonnet_cost += cost_for(cheap["model"], cheap, pricing)["usd"] or 0
        share = 100.0 * len(small) / len(opus)
        if subscription:
            # On a subscription these cost quota, not money — so the verdict is
            # driven by whether the quota ceiling was ever actually reached, not
            # by the raw count. Flagging small Opus asks on someone who never
            # hits the limit is a false alarm.
            hits = opus_fallback_events(db_path, machine=machine, since=since, until=until)
            if hits == 0:
                verdict = "good"
                detail = ("%d Opus prompts finished in ≤%d turns with ≤%d tool call — questions "
                          "rather than engineering. No Opus ceiling was hit in this range, so they "
                          "cost you nothing but a little latency. Nothing to change."
                          % (len(small), _RIGHTSIZE_TURNS, _RIGHTSIZE_TOOLS))
            else:
                verdict = "act" if share >= 25 else "watch"
                detail = ("Hit the Opus ceiling %d time%s in this range. %d Opus prompts finished "
                          "in ≤%d turns with ≤%d tool call — moving those to Sonnet buys back the "
                          "quota you ran out of."
                          % (hits, "" if hits == 1 else "s", len(small),
                             _RIGHTSIZE_TURNS, _RIGHTSIZE_TOOLS))
        else:
            verdict = "act" if share >= 25 else ("watch" if share >= 10 else "good")
            detail = ("%d Opus prompts finished in ≤%d turns with ≤%d tool call. "
                      "Same work on Sonnet: $%.0f instead of $%.0f."
                      % (len(small), _RIGHTSIZE_TURNS, _RIGHTSIZE_TOOLS, sonnet_cost, opus_cost))
        cards.append(_card("rightsize", "Opus on small asks", "%d prompts" % len(small),
                           verdict, detail))

    return cards
