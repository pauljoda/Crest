#!/usr/bin/env python3
"""Install the Mac comparison WebUI in a dedicated, Crest-overlaid Chromium source checkout."""

import argparse
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "CrestDesktop/comparison/chromium"


def apply(source, patch, paths=()):
    command = ["git", "apply", "--no-index", *("--include=" + path for path in paths)]
    if subprocess.run([*command, "--reverse", "--check", patch], cwd=source,
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        subprocess.run([*command, "--check", patch], cwd=source, check=True)
        subprocess.run([*command, patch], cwd=source, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="A separate Chromium src tree dedicated to the comparison build")
    args = parser.parse_args()
    source = args.source.resolve()
    if not (source / "chrome/app/crest_exe_main_mac.cc").is_file():
        parser.error("Expected a Chromium src tree prepared with the Crest Mac overlay")
    apply(source, FIXTURE / "comparison.patch")
    apply(source, ROOT / "CrestEngines/Chromium/Layers/Desktop/Patches/desktop-host.patch", [
        "components/surface_embed/renderer/surface_embed_web_plugin.cc",
        "components/performance_manager/performance_manager_tab_helper.cc",
    ])
    for name in ["crest_comparison_ui.h", "crest_comparison_ui.cc"]:
        shutil.copy2(FIXTURE / name, source / "chrome/browser/ui/webui" / name)


if __name__ == "__main__":
    main()
