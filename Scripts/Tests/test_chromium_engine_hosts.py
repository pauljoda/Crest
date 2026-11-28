"""Protect that each host's published engine depends only on what that host compiles."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "control-plane"))
import chromium_engine  # noqa: E402

MAC, WINDOWS = chromium_engine.MAC, "win-x64"


def section(name: str, old: str, new: str) -> str:
    return f"--- a/{name}\n+++ b/{name}\n@@ -1 +1 @@\n-{old}\n+{new}\n"


class EngineHostTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.repo = Path(self.directory.name)
        for name in chromium_engine.COMMON_INPUTS + chromium_engine.HOST_INPUTS[MAC]:
            if not name.endswith((".json", ".h", ".py")):
                continue
            self.write(name, "{}\n" if name.endswith(".json") else "// input\n")
        engine = chromium_engine.ENGINE
        self.write(f"{engine}/Patches/series", "shared.patch\n")
        self.write(f"{engine}/Patches/shared.patch", section("chrome/BUILD.gn", "a", "b"))
        self.write(f"{engine}/Overlay/chrome/browser/ui/crest/crest_engine_page.cc", "// shared\n")
        self.write(f"{engine}/host-inputs.json", json.dumps({"chrome/BUILD.gn": {"before": "a0", "after": "b0"}}))
        self.write(f"{engine}/Hosts/win-x64.json", json.dumps({"layers": ["Desktop"]}))
        layer = f"{chromium_engine.LAYERS}/Desktop"
        self.write(f"{layer}/Patches/series", "desktop-host.patch\n")
        self.write(f"{layer}/Patches/desktop-host.patch",
                   section("chrome/BUILD.gn", "b", "c") + section("chrome/app/chrome_exe.rc", "x", "y"))
        self.write(f"{layer}/Overlay/chrome/browser/ui/crest/crest_desktop_host.cc", "// desktop\n")
        self.write(f"{layer}/host-inputs.json", json.dumps({
            "chrome/BUILD.gn": {"before": "b0", "after": "c0"},
            "chrome/app/chrome_exe.rc": {"before": "x0", "after": "y0"},
        }))

    def tearDown(self):
        self.directory.cleanup()

    def write(self, name: str, text: str):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def keys(self) -> tuple[str, str]:
        return chromium_engine.engine_key(self.repo, MAC), chromium_engine.engine_key(self.repo, WINDOWS)

    def test_a_layer_change_rekeys_only_the_hosts_that_compile_it(self):
        mac, windows = self.keys()
        self.write(f"{chromium_engine.LAYERS}/Desktop/Overlay/chrome/browser/ui/crest/crest_desktop_host.cc", "// edited\n")
        self.assertEqual(self.keys()[0], mac)
        self.assertNotEqual(self.keys()[1], windows)

    def test_a_shared_change_rekeys_every_host(self):
        mac, windows = self.keys()
        self.write(f"{chromium_engine.ENGINE}/Overlay/chrome/browser/ui/crest/crest_engine_page.cc", "// edited\n")
        new_mac, new_windows = self.keys()
        self.assertNotEqual(new_mac, mac)
        self.assertNotEqual(new_windows, windows)

    def test_the_mac_applies_only_the_shared_patches(self):
        self.assertEqual([name for name, _ in chromium_engine.patch_sections(chromium_engine.host_patch(self.repo))],
                         ["chrome/BUILD.gn"])
        self.assertEqual(chromium_engine.host_inputs(self.repo), {"chrome/BUILD.gn": {"before": "a0", "after": "b0"}})

    def test_a_host_chains_its_layers_from_the_pinned_source(self):
        self.assertEqual(chromium_engine.host_inputs(self.repo, WINDOWS), {
            "chrome/BUILD.gn": {"before": "a0", "after": "c0"},
            "chrome/app/chrome_exe.rc": {"before": "x0", "after": "y0"},
        })

    def test_a_layer_reviewed_against_other_bytes_is_refused(self):
        self.write(f"{chromium_engine.LAYERS}/Desktop/host-inputs.json", json.dumps({
            "chrome/BUILD.gn": {"before": "stale", "after": "c0"},
            "chrome/app/chrome_exe.rc": {"before": "x0", "after": "y0"},
        }))
        with self.assertRaisesRegex(ValueError, "other bytes"):
            chromium_engine.host_inputs(self.repo, WINDOWS)


if __name__ == "__main__":
    unittest.main()
