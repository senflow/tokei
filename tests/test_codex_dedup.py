import json
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from test_codex_limits import USAGE


def event(ts, day, total, last, cost):
    return [ts, day, *total, *last, cost]


class CodexDedupedDaysTests(unittest.TestCase):
    def test_replayed_parent_snapshot_is_counted_once(self):
        parent = event(
            "2026-07-10T00:00:00+00:00",
            "2026-07-10",
            (100, 80, 5, 2),
            (100, 80, 5, 2),
            1.0,
        )
        replay = event(
            "2026-07-10T01:00:00+00:00",
            "2026-07-10",
            (100, 80, 5, 2),
            (100, 80, 5, 2),
            1.0,
        )
        child_increment = event(
            "2026-07-10T01:01:00+00:00",
            "2026-07-10",
            (150, 120, 8, 3),
            (50, 40, 3, 1),
            0.5,
        )

        days = USAGE._codex_deduped_days({
            "child": {"events": [replay, child_increment]},
            "parent": {"events": [parent]},
        })

        self.assertEqual(days["parent"]["2026-07-10"]["in"], 100)
        self.assertEqual(days["child"]["2026-07-10"]["in"], 50)
        self.assertEqual(days["child"]["2026-07-10"]["out"], 3)

    def test_events_without_cumulative_total_are_kept(self):
        first = event(
            "2026-07-10T00:00:00+00:00",
            "2026-07-10",
            (None, None, None, None),
            (25, 20, 2, 1),
            0.1,
        )
        second = event(
            "2026-07-10T00:01:00+00:00",
            "2026-07-10",
            (None, None, None, None),
            (25, 20, 2, 1),
            0.1,
        )

        days = USAGE._codex_deduped_days({
            "a": {"events": [first]},
            "b": {"events": [second]},
        })

        self.assertEqual(days["a"]["2026-07-10"]["in"], 25)
        self.assertEqual(days["b"]["2026-07-10"]["in"], 25)


class CodexScanDedupTests(unittest.TestCase):
    def token_count(self, ts, total, last):
        return json.dumps({
            "timestamp": ts,
            "type": "event_msg",
            "payload": {
                "type": "token_count",
                "info": {
                    "total_token_usage": {
                        "input_tokens": total[0],
                        "cached_input_tokens": total[1],
                        "output_tokens": total[2],
                        "reasoning_output_tokens": total[3],
                    },
                    "last_token_usage": {
                        "input_tokens": last[0],
                        "cached_input_tokens": last[1],
                        "output_tokens": last[2],
                        "reasoning_output_tokens": last[3],
                    },
                },
            },
        })

    def test_scan_keeps_child_increment_and_drops_replayed_history(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            parent = root / "rollout-parent.jsonl"
            child = root / "rollout-child.jsonl"
            inherited_total = (100, 80, 5, 2)
            child_total = (150, 120, 8, 3)
            child_last = (50, 40, 3, 1)
            parent.write_text(
                self.token_count("2024-01-08T00:00:00Z", inherited_total, inherited_total) + "\n",
                encoding="utf-8",
            )
            child.write_text(
                "\n".join([
                    self.token_count("2024-01-08T01:00:00Z", inherited_total, inherited_total),
                    self.token_count("2024-01-08T01:01:00Z", child_total, child_last),
                ]) + "\n",
                encoding="utf-8",
            )
            day = datetime(2024, 1, 8, tzinfo=timezone.utc)
            bounds = {
                "today": day,
                "yesterday": day - timedelta(days=1),
                "week": day,
                "last_week": day - timedelta(days=7),
                "last_week_end": day,
                "month": day.replace(day=1),
                "year": day.replace(month=1, day=1),
            }
            old_dir = USAGE.CODEX_DIR
            USAGE.CODEX_DIR = tmp
            try:
                result = USAGE.scan_codex(bounds, {"v": USAGE._SCAN_CACHE_VERSION})
            finally:
                USAGE.CODEX_DIR = old_dir

        all_usage = result["ranges"]["all"]
        self.assertEqual(all_usage["in"], 150)
        self.assertEqual(all_usage["cached"], 120)
        self.assertEqual(all_usage["out"], 8)
        self.assertEqual(all_usage["reason"], 3)
        self.assertEqual(len(all_usage["sessions"]), 2)


if __name__ == "__main__":
    unittest.main()
