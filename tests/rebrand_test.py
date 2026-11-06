#!/usr/bin/env python3
"""scripts/rebrand.py's rules (run: python3 tests/rebrand_test.py)."""
import importlib.util
import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_spec = importlib.util.spec_from_file_location("rebrand", os.path.join(ROOT, "scripts", "rebrand.py"))
rebrand = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rebrand)


class Rules(unittest.TestCase):
    def test_brand_in_every_case(self):
        self.assertEqual(rebrand.rebrand("Olympus II, OLYMPUS X, olympus"), "ChillZone II, CHILLZONE X, chillzone")

    def test_members(self):
        self.assertEqual(rebrand.rebrand("Olympians, OLYMPIAN, olympian"), "ChillZoners, CHILLZONER, chillzoner")

    def test_identifiers(self):
        self.assertEqual(rebrand.rebrand("IsOlympusMember(SLASH_OLYMPUS1, OlympusDB, OLYMPUS_TEST_FILTER)"),
                         "IsChillZoneMember(SLASH_CHILLZONE1, ChillZoneDB, CHILLZONE_TEST_FILTER)")

    def test_slash_commands(self):
        self.assertEqual(rebrand.rebrand('"/olympus", "/oly", /oly status, /ola, /ol hi, /olc, /oll, /ogarmy'),
                         '"/chillzone", "/cz", /cz status, /cza, /czn hi, /czc, /czl, /czarmy')

    def test_paths(self):
        self.assertEqual(rebrand.rebrand("Interface\\AddOns\\Olympus\\media\\logo64 ~/.olympus/council-key.json"),
                         "Interface\\AddOns\\ChillZone\\media\\logo64 ~/.chillzone/council-key.json")
        self.assertEqual(rebrand.words("Olympus_Arena/Olympus_Arena.toc"), "ChillZone_Arena/ChillZone_Arena.toc")
        self.assertEqual(rebrand.words("OlympusSiteAggregate/OlympusSiteAggregate.toc"),
                         "ChillZoneSiteAggregate/ChillZoneSiteAggregate.toc")

    def test_protected(self):
        for text in ("https://github.com/dnl-gentile/olympus-addon", '"olympus-record-1|"',
                     'S.SALT = "olympus-strike-1:"', '"olympus-api-authorized:"'):
            self.assertEqual(rebrand.rebrand(text), text)

    def test_other_words_untouched(self):
        text = "Olympia, Olympic, OLYMPVS, Olimpo, Developus Olympicus, /old, /olive, /ollie"
        self.assertEqual(rebrand.rebrand(text), text)

    def test_skipped_files(self):
        self.assertTrue(rebrand.skipped("LICENSE"))
        self.assertTrue(rebrand.skipped("UPSTREAM.md"))
        self.assertTrue(rebrand.skipped("docs/superpowers/specs/2026-11-06-chillzone-fork-design.md"))
        self.assertTrue(rebrand.skipped("tests/rebrand_test.py"))
        self.assertFalse(rebrand.skipped("Olympus/Core.lua"))

    def test_patch_headers(self):
        patch = ("diff --git a/Olympus/Core.lua b/Olympus/Core.lua\n--- a/Olympus/Core.lua\n"
                 "+++ b/Olympus/Core.lua\n-ns.NAME = \"Olympus\"\n")
        self.assertEqual(rebrand.rebrand(patch),
                         "diff --git a/ChillZone/Core.lua b/ChillZone/Core.lua\n--- a/ChillZone/Core.lua\n"
                         "+++ b/ChillZone/Core.lua\n-ns.NAME = \"ChillZone\"\n")


if __name__ == "__main__":
    unittest.main()
