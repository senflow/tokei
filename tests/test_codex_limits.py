import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "usage.30s.py"
SPEC = importlib.util.spec_from_file_location("tokei_usage", SCRIPT)
USAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(USAGE)


class CodexQuotaValuesTests(unittest.TestCase):
    def test_legacy_primary_5h_secondary_week(self):
        limits = {
            "primary": {"used_percent": 25.0, "window_minutes": 300, "resets_at": 200},
            "secondary": {"used_percent": 40.0, "window_minutes": 10080, "resets_at": 300},
        }

        self.assertEqual(
            USAGE._codex_quota_values(limits, now_epoch=100),
            {"p5": 25.0, "pw": 40.0, "r5": 200, "rw": 300},
        )

    def test_week_only_primary(self):
        limits = {
            "primary": {"used_percent": 1.0, "window_minutes": 10080, "resets_at": 300},
            "secondary": None,
        }

        self.assertEqual(
            USAGE._codex_quota_values(limits, now_epoch=100),
            {"p5": None, "pw": 1.0, "r5": None, "rw": 300},
        )

    def test_expired_window_is_reset(self):
        limits = {
            "primary": {"used_percent": 90.0, "window_minutes": 10080, "resets_at": 99},
        }

        self.assertEqual(
            USAGE._codex_quota_values(limits, now_epoch=100),
            {"p5": None, "pw": 0.0, "r5": None, "rw": None},
        )


if __name__ == "__main__":
    unittest.main()
