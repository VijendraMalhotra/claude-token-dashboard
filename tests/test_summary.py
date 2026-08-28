import os
import tempfile
import unittest

from token_dashboard.db import init_db, connect
from token_dashboard.pricing import load_pricing
from token_dashboard.summary import exec_summary, REWORK_RE

PRICING = load_pricing(os.path.join(os.path.dirname(__file__), "..", "pricing.json"))


def _rows(n, model, turns, prompt="do the thing", start=0):
    """n prompts in their own sessions, each followed by `turns` assistant msgs."""
    out = []
    for i in range(n):
        i += start
        p = "p%d" % i
        out.append("('%s',NULL,'s%d','projA','user','2026-04-%02dT00:00:00Z',NULL,"
                   "0,0,0,0,0,0,%s,10)" % (p, i, (i % 28) + 1, repr(prompt).replace('"', "'")))
        for t in range(turns):
            out.append("('%s_a%d','%s','s%d','projA','assistant','2026-04-%02dT00:00:%02dZ','%s',"
                       "10,10,90,0,0,0,NULL,NULL)" % (p, t, p, i, (i % 28) + 1, t + 1, model))
    return out


class SummaryTests(unittest.TestCase):
    def _db(self, values):
        tmp = tempfile.mkdtemp()
        db = os.path.join(tmp, "s.db")
        init_db(db)
        if values:
            with connect(db) as c:
                c.execute(
                    "INSERT INTO messages (uuid,parent_uuid,session_id,project_slug,type,"
                    "timestamp,model,input_tokens,output_tokens,cache_read_tokens,"
                    "cache_create_5m_tokens,cache_create_1h_tokens,is_sidechain,prompt_text,"
                    "prompt_chars) VALUES " + ",".join(values))
                c.commit()
        return db

    def _by_key(self, db, plan="api"):
        return {c["key"]: c for c in exec_summary(db, PRICING, plan)}

    def test_empty_db_returns_a_single_info_card(self):
        cards = exec_summary(self._db([]), PRICING)
        self.assertEqual(len(cards), 1)
        self.assertEqual(cards[0]["verdict"], "info")

    def test_api_plan_shows_spend_subscription_shows_value_multiple(self):
        db = self._db(_rows(4, "claude-sonnet-4-6", 2))
        self.assertIn("spend", self._by_key(db, "api"))
        self.assertIn("value", self._by_key(db, "max-20x"))

    def test_low_turn_median_is_good_high_is_act(self):
        good = self._by_key(self._db(_rows(4, "claude-sonnet-4-6", 2)))["turns"]
        bad = self._by_key(self._db(_rows(4, "claude-sonnet-4-6", 12)))["turns"]
        self.assertEqual(good["verdict"], "good")
        self.assertEqual(bad["verdict"], "act")

    def test_rework_rate_counts_correction_prompts(self):
        db = self._db(_rows(3, "claude-sonnet-4-6", 1, "still not working")
                      + _rows(1, "claude-sonnet-4-6", 1, "add a feature", start=50))
        card = self._by_key(db)["rework"]
        self.assertEqual(card["value"], "75%")
        self.assertEqual(card["verdict"], "act")

    def test_rightsize_card_only_appears_when_opus_was_used(self):
        self.assertNotIn("rightsize", self._by_key(self._db(_rows(3, "claude-sonnet-4-6", 1))))
        self.assertIn("rightsize", self._by_key(self._db(_rows(3, "claude-opus-4-7", 1))))

    def test_rightsize_flags_small_opus_spans(self):
        card = self._by_key(self._db(_rows(4, "claude-opus-4-7", 1)))["rightsize"]
        self.assertEqual(card["value"], "4")
        self.assertEqual(card["verdict"], "act")

    def test_big_opus_spans_are_not_flagged_as_small(self):
        card = self._by_key(self._db(_rows(4, "claude-opus-4-7", 9)))["rightsize"]
        self.assertEqual(card["value"], "0")
        self.assertEqual(card["verdict"], "good")

    def test_subscription_wording_talks_about_quota_not_dollars(self):
        card = self._by_key(self._db(_rows(3, "claude-opus-4-7", 1)), "max-20x")["rightsize"]
        self.assertIn("quota", card["detail"])
        self.assertNotIn("instead of", card["detail"])


class ReworkRegexTests(unittest.TestCase):
    def test_matches_corrections(self):
        for s in ("no, that's wrong", "still not working", "try again",
                  "you missed the second one", "revert that", "same error"):
            self.assertTrue(REWORK_RE.search(s), s)

    def test_ignores_ordinary_prompts(self):
        for s in ("add a login page", "summarise this file",
                  "write the deploy script", "explain the scanner"):
            self.assertFalse(REWORK_RE.search(s), s)


if __name__ == "__main__":
    unittest.main()
