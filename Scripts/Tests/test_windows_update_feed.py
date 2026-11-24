#!/usr/bin/env python3
"""Update trust for Crest for Windows: the installer signatures its engine
checks, and the feed that lists them."""

from __future__ import annotations

import base64
import hashlib
import pathlib
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ElementTree

REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts"))

import windows_update_feed as feed  # noqa: E402

# RFC 8032, section 7.1, test 2.
SEED = bytes.fromhex("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb")
PUBLIC_KEY = bytes.fromhex("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
MESSAGE = bytes.fromhex("72")
SIGNATURE = bytes.fromhex(
    "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da"
    "085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00")


class InstallerSignatureTests(unittest.TestCase):
    def test_signs_as_ed25519_does(self) -> None:
        key = feed.SigningKey.from_sparkle(base64.b64encode(SEED).decode())
        self.assertEqual(key.public_key, PUBLIC_KEY)
        self.assertEqual(key.sign(MESSAGE), SIGNATURE)
        self.assertTrue(feed.verify(PUBLIC_KEY, SIGNATURE, MESSAGE))

    def test_reads_sparkles_older_key_form(self) -> None:
        expanded = bytearray(hashlib.sha512(SEED).digest())
        expanded[0] &= 248
        expanded[31] = (expanded[31] & 63) | 64
        key = feed.SigningKey.from_sparkle(base64.b64encode(bytes(expanded) + PUBLIC_KEY).decode())
        self.assertEqual(key.sign(MESSAGE), SIGNATURE)
        with self.assertRaises(feed.FeedError):
            feed.SigningKey.from_sparkle(base64.b64encode(bytes(expanded) + bytes(32)).decode())

    def test_a_changed_installer_fails(self) -> None:
        key = feed.SigningKey.from_seed(SEED)
        with tempfile.TemporaryDirectory() as directory:
            installer = pathlib.Path(directory) / "Setup.exe"
            installer.write_bytes(bytes(range(256)) * 4096)
            signature = key.sign(path=installer)
            self.assertTrue(feed.verify(PUBLIC_KEY, signature, path=installer))
            changed = bytearray(installer.read_bytes())
            changed[1000] ^= 1
            installer.write_bytes(bytes(changed))
            self.assertFalse(feed.verify(PUBLIC_KEY, signature, path=installer))


class FeedTests(unittest.TestCase):
    def item(self, build: int, channel: str) -> ElementTree.Element:
        return feed.feed_item(f"0.10.{build}", build, channel, f"https://example.invalid/{build}.exe", 10,
                              "c2lnbmF0dXJl", None, 0)

    def builds(self, rss: ElementTree.Element) -> list[tuple[int, str]]:
        return [(int(item.findtext(f"{{{feed.SPARKLE}}}version")), item.findtext(f"{{{feed.SPARKLE}}}channel")
                 or "stable") for item in rss.find("channel").findall("item")]

    def test_keeps_the_newest_of_a_channel_and_every_other_channels(self) -> None:
        rss = feed.empty_feed()
        feed.add_item(rss, self.item(1, "stable"), maximum=0)
        feed.add_item(rss, self.item(2, "nightly"), maximum=1)
        feed.add_item(rss, self.item(3, "stable"), maximum=0)
        feed.add_item(rss, self.item(4, "nightly"), maximum=1)
        self.assertEqual(self.builds(rss), [(4, "nightly"), (3, "stable"), (1, "stable")])

    def test_a_rerun_replaces_its_build(self) -> None:
        rss = feed.empty_feed()
        feed.add_item(rss, self.item(5, "development"), maximum=1)
        feed.add_item(rss, self.item(5, "development"), maximum=1)
        self.assertEqual(self.builds(rss), [(5, "development")])

    def test_an_item_names_a_windows_installer_over_https(self) -> None:
        enclosure = self.item(6, "stable").find("enclosure")
        self.assertEqual(enclosure.get(f"{{{feed.SPARKLE}}}os"), "windows")
        self.assertEqual(enclosure.get(f"{{{feed.SPARKLE}}}edSignature"), "c2lnbmF0dXJl")
        with self.assertRaises(feed.FeedError):
            feed.feed_item("0.10.7", 7, "stable", "http://example.invalid/7.exe", 10, "c2lnbmF0dXJl", None, 0)
        # A local build's test serves its own feed from this device.
        feed.feed_item("0.10.8", 8, "stable", "http://127.0.0.1:8765/8.exe", 10, "c2lnbmF0dXJl", None, 0)


if __name__ == "__main__":
    unittest.main()
