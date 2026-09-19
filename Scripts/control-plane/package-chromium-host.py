#!/usr/bin/env python3
"""Assemble a separate, signed Chromium experiment from built host products."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--browser", required=True, type=Path, help="Built Chromium.app with the Crest overlay")
    parser.add_argument("--signing-identity", required=True,
                        help="Stable Apple Development or Developer ID signing identity; ad-hoc is rejected")
    parser.add_argument("--baseline", action="store_true", help="Package the stock baseline without the Crest host libraries")
    parser.add_argument("--ui", type=Path, help="Built CrestChromiumUI.framework")
    parser.add_argument("--core", type=Path, help="Published CrestCore.Native.dylib")
    parser.add_argument("--output", required=True, type=Path, help="New absolute .app path outside /Applications")
    args = parser.parse_args()
    if args.signing_identity.strip() in ("", "-"):
        parser.error("Use a stable signing identity so keychain access survives rebuilds")
    repo = Path(__file__).resolve().parents[2]
    output = args.output
    if not output.is_absolute() or output.exists() or output.suffix != ".app":
        parser.error("The output must be a new absolute .app path")
    if output.resolve().is_relative_to(Path("/Applications")) or output.resolve().is_relative_to(repo):
        parser.error("Keep experimental browser products outside /Applications and the repository")
    browser = args.browser.resolve()
    ui = args.ui.resolve() if args.ui else None
    core = args.core.resolve() if args.core else None
    if args.baseline and (ui or core):
        parser.error("A baseline package must not include host libraries")
    if not (browser / "Contents/Info.plist").is_file():
        parser.error("Provide a built Chromium app")
    if not args.baseline and (ui is None or core is None or not (ui / "CrestChromiumUI").is_file() or not core.is_file()):
        parser.error("Provide the linked browser, native UI framework, and NativeAOT library")
    # APFS clones avoid another complete copy of Chromium's framework while
    # retaining independent files for signing. No input bundle is modified.
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["cp", "-cR", str(browser), str(output)], check=True)
    frameworks = output / "Contents/Frameworks"
    if not args.baseline:
        subprocess.run(["ditto", str(ui), str(frameworks / "CrestChromiumUI.framework")], check=True)
        shutil.copy2(core, frameworks / "CrestCore.Native.dylib")
    resources = output / "Contents/Resources"
    resources.mkdir(exist_ok=True)
    (resources / "Crest-Isolated-Experiment").write_text("Explicit experimental profile required.\n")
    shutil.copy2(repo / "CrestEngines/Chromium/ThirdParty/Mori-LICENSE", resources / "Crest-Mori-LICENSE.txt")
    info_path = output / "Contents/Info.plist"
    with info_path.open("rb") as stream:
        info = plistlib.load(stream)
    info["CFBundleIdentifier"] = "com.pauldavis.crest.chromium-baseline" if args.baseline else "com.pauldavis.crest.control-plane.chromium"
    info["CFBundleDisplayName"] = "Crest Chromium Baseline" if args.baseline else "Crest Chromium Experiment"
    info["CFBundleName"] = info["CFBundleDisplayName"]
    # This experiment must not register as the system HTTP/HTTPS handler.
    info.pop("CFBundleURLTypes", None)
    info.pop("CFBundleDocumentTypes", None)
    with info_path.open("wb") as stream:
        plistlib.dump(info, stream)
    targets = [] if args.baseline else [frameworks / "CrestCore.Native.dylib", frameworks / "CrestChromiumUI.framework"]
    targets += sorted((p for p in frameworks.rglob("*.app") if not p.is_symlink()), key=lambda p: len(p.parts), reverse=True)
    targets += sorted((p for p in frameworks.glob("*.framework") if p.name != "CrestChromiumUI.framework"), key=lambda p: len(p.parts), reverse=True)
    for target in [*targets, output]:
        subprocess.run(["codesign", "--force", "--sign", args.signing_identity, "--preserve-metadata=entitlements,flags,runtime", str(target)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(output)], check=True)
    mode = "" if args.baseline else "--crest-control-plane and "
    print(f"Packaged {output}. Launch its executable with {mode}an explicit experimental --user-data-dir.")


if __name__ == "__main__":
    main()
