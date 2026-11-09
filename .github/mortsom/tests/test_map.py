"""The map stays complete, consistent with the catalog and with the pin (§ 4.4)."""

import re
import subprocess
import sys
import unittest
from pathlib import Path

GATE = Path(__file__).resolve().parents[1]
ROOT = GATE.parents[1]
sys.path.insert(0, str(GATE))
import select_scenarios as s  # noqa: E402

MAP = s.load_map(GATE / "map.toml")
CATALOG = s.load_catalog(GATE / "scenarios.json")


def tracked():
    try:
        return subprocess.check_output(["git", "-C", str(ROOT), "ls-files"], text=True).split()
    except (OSError, subprocess.CalledProcessError):
        return []


class TestMap(unittest.TestCase):
    def test_every_tracked_file_matches_a_rule(self):
        files = tracked()
        if not files:
            self.skipTest("not a git checkout")
        self.assertEqual(s.unmatched(files, MAP), [], "map these paths in .github/mortsom/map.toml")

    def test_every_tag_and_scenario_in_the_map_exists(self):
        tags = {t for r in MAP["rule"] for t in r.get("tags", [])} | set(MAP["settings"]["always_tags"])
        names = {n for r in MAP["rule"] for n in r.get("scenarios", [])}
        s._resolve(sorted(tags), sorted(names), CATALOG)  # raises SelectionError

    def test_rules_are_one_kind_each(self):
        for r in MAP["rule"]:
            kinds = [bool(r.get("ignore")), bool(r.get("full")), bool(r.get("uncovered")),
                     bool(r.get("tags") or r.get("scenarios"))]
            self.assertEqual(sum(kinds), 1, r["name"])

    def test_workflows_use_the_pinned_mortsom(self):
        pin = MAP["settings"]["mortsom_ref"]
        for name in ("mortsom-pr.yml", "mortsom-baseline.yml"):
            text = (ROOT / ".github/workflows" / name).read_text()
            refs = re.findall(r"MostroP2P/mortsom/\.github/workflows/app-e2e\.yml@(\S+)", text)
            self.assertTrue(refs, name)
            self.assertEqual(set(refs), {pin}, name)
            self.assertEqual(set(re.findall(r"mortsom_ref:\s*(\S+)", text)), {pin}, name)

    def test_catalog_schema_is_understood(self):
        self.assertEqual(CATALOG["schema"], 1)


if __name__ == "__main__":
    unittest.main()
