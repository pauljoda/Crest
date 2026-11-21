#!/usr/bin/env python3
"""The credits page lists supporters only as the person allows."""

from __future__ import annotations

import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts"))
SPECIFICATION = importlib.util.spec_from_file_location("build_credits_page", REPOSITORY_ROOT / "Scripts" / "build-credits-page.py")
assert SPECIFICATION and SPECIFICATION.loader
credits = importlib.util.module_from_spec(SPECIFICATION)
# Its dataclasses look their module up by name while they are made.
sys.modules[SPECIFICATION.name] = credits
SPECIFICATION.loader.exec_module(credits)


def patreon_page() -> dict:
    """One page of Patreon's member list: three tiers and five members."""
    def member(identifier: str, name: str, status: str, tier: str | None) -> dict:
        tiers = [{"id": tier, "type": "tier"}] if tier else []
        return {
            "id": identifier,
            "type": "member",
            "attributes": {"full_name": name, "patron_status": status},
            "relationships": {"currently_entitled_tiers": {"data": tiers}},
        }

    return {
        "data": [
            member("1", "Avery Sponsor", "active_patron", "t25"),
            member("2", "Blake Sustainer", "active_patron", "t10"),
            member("3", "Casey Hidden", "active_patron", "t25"),
            member("4", "Drew Former", "former_patron", "t25"),
            member("5", "Jesus Rojas", "active_patron", "t10"),
            member("6", "Emery Small", "active_patron", "t2"),
        ],
        "included": [
            {"id": "t25", "type": "tier", "attributes": {"title": "Sponsor", "amount_cents": 2500}},
            {"id": "t10", "type": "tier", "attributes": {"title": "Sustainer", "amount_cents": 1000}},
            {"id": "t2", "type": "tier", "attributes": {"title": "Fan", "amount_cents": 200}},
        ],
    }


class CreditsPageTests(unittest.TestCase):
    def build(self, supporters: dict) -> tuple[str, dict]:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = pathlib.Path(temporary.name)
        document = json.loads((REPOSITORY_ROOT / "Documentation" / "Credits.json").read_text())
        document["supporters"] = {**document["supporters"], **supporters}
        (root / "Documentation").mkdir()
        (root / "Documentation" / "Credits.json").write_text(json.dumps(document))
        output = root / "credits"
        credits.build(
            root, output, contributors=[], patrons=credits.patrons_on_page(patreon_page()), fetcher=lambda _: None
        )
        return (output / "index.html").read_text(), json.loads((output / "credits.json").read_text())

    def test_hidden_supporters_never_appear_from_the_file_or_patreon(self) -> None:
        page, document = self.build({
            "people": [{"name": "Riley Listed", "tier": "supporter"}, {"name": "Sam Private", "tier": "sponsor"}],
            # By Patreon name, member ID and the name the page shows.
            "hidden": ["casey hidden", "2", "Sam Private"],
        })
        listed = {person["name"] for tier in document["supporters"] for person in tier["people"]}
        self.assertIn("Riley Listed", listed)
        for name in ("Casey", "Blake", "Sam Private"):
            self.assertFalse(any(shown.startswith(name) for shown in listed), name)
            self.assertNotIn(name, page)

    def test_hidden_member_ids_hold_without_patreon_and_over_entries_of_the_same_name(self) -> None:
        supporters = {
            "people": [
                {"name": "Chris F", "patreon": "9", "tier": "supporter"},
                {"name": "Blake Sustainer", "source": "ko-fi", "tier": "supporter"},
            ],
            "hidden": ["9", "2"],
        }
        tiers = credits.read_tiers(json.loads((REPOSITORY_ROOT / "Documentation" / "Credits.json").read_text())["supporters"])
        # Without Patreon, the entry that holds a hidden member ID is left out;
        # nothing yet ties the Ko-fi entry to patron 2.
        offline = credits.resolve_supporters(supporters, tiers, None)
        self.assertEqual(["Blake Sustainer"], [person.name for people in offline.values() for person in people])
        # With Patreon, an entry with the name of a patron hidden by member ID
        # is left out too.
        live = credits.resolve_supporters(supporters, tiers, credits.patrons_on_page(patreon_page()))
        names = [person.name for people in live.values() for person in people]
        self.assertFalse(any(name.startswith(("Blake", "Chris")) for name in names), names)

    def test_two_patrons_with_one_name_stay_two(self) -> None:
        page = patreon_page()
        page["data"].append(dict(page["data"][1], id="7"))
        tiers = credits.read_tiers(json.loads((REPOSITORY_ROOT / "Documentation" / "Credits.json").read_text())["supporters"])
        live = credits.resolve_supporters({"people": [], "hidden": []}, tiers, credits.patrons_on_page(page))
        self.assertEqual(2, [person.name for person in live["sustainer"]].count("Blake S"))

    def test_patrons_are_listed_live_with_the_links_the_file_gives(self) -> None:
        page, document = self.build({
            "people": [
                {"name": "Jesus Rojas", "tier": "sponsor", "link": "jesusvr.dev"},
                {"name": "Blake", "patreon": "2", "tier": "supporter", "link": "https://blake.example"},
                {"name": "Drew Former", "tier": "sponsor", "patreon": "4"},
                {"name": "Morgan Base", "tier": "supporter", "source": "ko-fi", "link": "https://example.com"},
            ],
            "hidden": [],
        })
        tiers = {tier["tier"]: tier["people"] for tier in document["supporters"]}
        # A patron the file doesn't stand for shows their first name and initial.
        self.assertEqual(
            tiers["sponsor"], [{"name": "Avery S", "source": "patreon"}, {"name": "Casey H", "source": "patreon"}]
        )
        # Patreon's tier wins, and the entry that stands for a patron, by name or
        # member ID, gives their spelling and link.
        self.assertEqual(
            tiers["sustainer"],
            [
                {"name": "Blake", "link": "https://blake.example", "source": "patreon"},
                {"name": "Jesus Rojas", "link": "https://jesusvr.dev", "source": "patreon"},
            ],
        )
        # A tier without links drops the link; a Patreon entry whose membership
        # ended, a former patron and a pledge below the lowest tier are not listed.
        self.assertEqual(tiers["supporter"], [{"name": "Morgan Base", "source": "ko-fi"}])
        for name in ("Drew Former", "Emery S", "example.com", "Blake Sustainer", "Avery Sponsor"):
            self.assertNotIn(name, page)

if __name__ == "__main__":
    unittest.main()
