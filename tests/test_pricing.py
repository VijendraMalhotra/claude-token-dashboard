import os
import unittest

from token_dashboard.pricing import load_pricing, cost_for, format_for_user

PRICING = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "pricing.json"))


class CostTests(unittest.TestCase):
    def setUp(self):
        self.p = load_pricing(PRICING)

    def _u(self, **kw):
        base = {
            "input_tokens": 0, "output_tokens": 0, "cache_read_tokens": 0,
            "cache_create_5m_tokens": 0, "cache_create_1h_tokens": 0,
        }
        base.update(kw)
        return base

    def test_known_opus_input_cost(self):
        c = cost_for("claude-opus-5", self._u(input_tokens=1_000_000), self.p)
        self.assertAlmostEqual(c["usd"], 5.00, places=4)
        self.assertFalse(c["estimated"])

    def test_known_opus_output_cost(self):
        c = cost_for("claude-opus-5", self._u(output_tokens=1_000_000), self.p)
        self.assertAlmostEqual(c["usd"], 25.00, places=4)

    def test_known_sonnet_output_cost(self):
        c = cost_for("claude-sonnet-4-6", self._u(output_tokens=1_000_000), self.p)
        self.assertAlmostEqual(c["usd"], 15.00, places=4)

    def test_sonnet_5_is_cheaper_than_sonnet_4_6(self):
        u = self._u(input_tokens=1_000_000)
        self.assertLess(cost_for("claude-sonnet-5", u, self.p)["usd"],
                        cost_for("claude-sonnet-4-6", u, self.p)["usd"])

    def test_fable_is_priced_above_opus(self):
        u = self._u(input_tokens=1_000_000)
        c = cost_for("claude-fable-5", u, self.p)
        self.assertAlmostEqual(c["usd"], 10.00, places=4)
        self.assertFalse(c["estimated"])
        self.assertGreater(c["usd"], cost_for("claude-opus-5", u, self.p)["usd"])

    def test_unknown_fable_falls_back_to_fable_tier_not_none(self):
        # Regression: "fable" matched no tier, so Fable turns were priced at $0
        # and vanished from every cost figure.
        c = cost_for("claude-fable-9-experimental", self._u(input_tokens=1_000_000), self.p)
        self.assertIsNotNone(c["usd"])
        self.assertAlmostEqual(c["usd"], 10.00, places=4)
        self.assertTrue(c["estimated"])

    def test_unknown_opus_falls_back(self):
        c = cost_for("claude-opus-9-9-experimental", self._u(input_tokens=1_000_000), self.p)
        self.assertAlmostEqual(c["usd"], 5.00, places=4)
        self.assertTrue(c["estimated"])

    def test_cache_multipliers_match_published_ratios(self):
        # 5m write 1.25x base input, 1h write 2x, cache read 0.1x
        for model in ("claude-opus-5", "claude-sonnet-5", "claude-fable-5", "claude-haiku-4-5"):
            r = self.p["models"][model]
            self.assertAlmostEqual(r["cache_create_5m"], r["input"] * 1.25, places=4, msg=model)
            self.assertAlmostEqual(r["cache_create_1h"], r["input"] * 2.00, places=4, msg=model)
            self.assertAlmostEqual(r["cache_read"], r["input"] * 0.10, places=4, msg=model)

    def test_unknown_unparseable_returns_none(self):
        c = cost_for("custom-local-model", self._u(input_tokens=9999), self.p)
        self.assertIsNone(c["usd"])

    def test_cache_read_cheaper_than_input(self):
        c_in = cost_for("claude-opus-5", self._u(input_tokens=1_000_000), self.p)
        c_cr = cost_for("claude-opus-5", self._u(cache_read_tokens=1_000_000), self.p)
        self.assertLess(c_cr["usd"], c_in["usd"])


class PlanFormatTests(unittest.TestCase):
    def setUp(self):
        self.p = load_pricing(PRICING)

    def test_api_plan_returns_raw(self):
        out = format_for_user(12.34, "api", self.p)
        self.assertEqual(out["display_usd"], 12.34)
        self.assertIsNone(out["subscription_usd"])

    def test_pro_plan_returns_subscription_subtitle(self):
        out = format_for_user(12.34, "pro", self.p)
        self.assertEqual(out["subscription_usd"], 20)
        self.assertIn("Pro", out["subtitle"])


if __name__ == "__main__":
    unittest.main()
