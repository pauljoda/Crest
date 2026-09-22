#!/usr/bin/env python3
"""Assemble a separate, signed Chromium host from built products: an isolated experiment by default, or Crest's own product identity."""
import argparse
import os
import re
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone


def default_update_channel(repo):
    override = os.environ.get("CREST_DEFAULT_UPDATE_CHANNEL", "").strip()
    if override:
        return override
    channels = set(re.findall(r"^\s*CREST_DEFAULT_UPDATE_CHANNEL:\s*([a-z]+)\s*$",
                              (repo / "project.yml").read_text(), re.MULTILINE))
    if len(channels) != 1:
        raise SystemExit(f"project.yml must name one default update channel; found {sorted(channels)}")
    return channels.pop()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--browser", required=True, type=Path, help="Built Chromium.app with the Crest overlay")
    parser.add_argument("--signing-identity", required=True,
                        help="Stable Apple Development or Developer ID signing identity; ad-hoc is rejected")
    parser.add_argument("--provisioning-profile", type=Path, help="Profile granting this app access to Crest CloudKit")
    parser.add_argument("--baseline", action="store_true", help="Package the stock baseline without the Crest host libraries")
    parser.add_argument("--product", action="store_true",
                        help="Package Crest's own desktop identity from CrestChromiumUIProduct: browser registration, "
                             "document types and the Sparkle update feed instead of the isolated review identity")
    parser.add_argument("--entitlements", type=Path,
                        help="Resolved entitlements plist for the product identity; build-setting variables must already be expanded")
    parser.add_argument("--ui", type=Path, help="Built CrestChromiumUI.framework or CrestChromiumUIProduct.framework")
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
    if args.baseline and args.product:
        parser.error("The stock baseline has no Crest product identity")
    if args.entitlements and not args.product:
        parser.error("Entitlements belong to the product identity; review packages preserve the existing signature")
    if not (browser / "Contents/Info.plist").is_file():
        parser.error("Provide a built Chromium app")
    if not args.baseline and (ui is None or core is None or not core.is_file()
                              or not (ui / "Resources/Info.plist").is_file()):
        parser.error("Provide the linked browser, native UI framework, and NativeAOT library")
    if not args.baseline:
        with (ui / "Resources/Info.plist").open("rb") as stream:
            ui_executable = plistlib.load(stream).get("CFBundleExecutable", "")
        if not ui_executable or not (ui / ui_executable).is_file():
            parser.error("The native UI framework has no linked executable")
        # Only the product target compiles without review isolation and carries
        # its marker resource. Read which composition this is instead of
        # trusting the path it was built at.
        is_product_framework = (ui / "Resources/Crest-Native-Host").is_file()
        if args.product and not is_product_framework:
            parser.error("Build CrestChromiumUIProduct for a product package; this framework is the isolated review composition")
        if not args.product and is_product_framework:
            parser.error("Build CrestChromiumUI for a review package; this framework is the normal product composition")
    identity = (
        "com.pauldavis.crest" if args.product
        else "com.pauldavis.crest.chromium-baseline" if args.baseline
        else "com.pauldavis.crest.control-plane.chromium")
    product_entitlements = None
    if args.entitlements:
        with args.entitlements.open("rb") as stream:
            product_entitlements = plistlib.load(stream)
        unexpanded = sorted(
            key for key, value in product_entitlements.items()
            if isinstance(value, str) and "$(" in value)
        if unexpanded:
            parser.error(f"Expand these entitlement build settings before packaging: {', '.join(unexpanded)}")
    cloud_entitlements = None
    if args.provisioning_profile:
        if args.baseline:
            parser.error("CloudKit is only supported by the native Crest composition")
        profile = plistlib.loads(subprocess.check_output(
            ["security", "cms", "-D", "-i", str(args.provisioning_profile)]))
        granted = profile.get("Entitlements", {})
        application_id = granted.get("com.apple.application-identifier", "")
        team = granted.get("com.apple.developer.team-identifier", "")
        expected_id = team + "." + identity
        with (repo / "CrestMac/Configuration/Crest-Info.plist").open("rb") as stream:
            container = plistlib.load(stream)["CrestCloudKitContainerIdentifier"]
        expiration = profile.get("ExpirationDate")
        # A product profile may carry either environment; an experiment profile
        # stays on development so it can never reach production records.
        environments = granted.get("com.apple.developer.icloud-container-environment", [])
        if isinstance(environments, str):
            environments = [environments]
        push = granted.get("com.apple.developer.aps-environment")
        cloud_environment = next(
            (value for value in ("Production", "Development") if value in environments), None)
        if args.product:
            granted_environment = cloud_environment is not None and push in ("development", "production")
        else:
            granted_environment = "Development" in environments and push == "development"
            cloud_environment = "Development"
        if (not team or application_id != expected_id or not expiration
                or expiration.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc)
                or container not in granted.get("com.apple.developer.icloud-container-identifiers", [])
                or not granted_environment):
            parser.error(f"The profile must grant {identity} CloudKit and push access")
        service = granted.get("com.apple.developer.icloud-services", [])
        if service != "*" and "CloudKit" not in service:
            parser.error("The provisioning profile does not grant CloudKit")
        cloud_entitlements = {
            "com.apple.application-identifier": application_id,
            "com.apple.developer.team-identifier": team,
            "com.apple.developer.icloud-container-identifiers": [container],
            "com.apple.developer.icloud-container-environment": cloud_environment,
            "com.apple.developer.icloud-services": ["CloudKit"],
            "com.apple.developer.aps-environment": push,
        }
    # APFS clones avoid another complete copy of Chromium's framework while
    # retaining independent files for signing. No input bundle is modified.
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["cp", "-cR", str(browser), str(output)], check=True)
    frameworks = output / "Contents/Frameworks"
    if not args.baseline:
        subprocess.run(["ditto", str(ui), str(frameworks / ui.name)], check=True)
        shutil.copy2(core, frameworks / "CrestCore.Native.dylib")
    resources = output / "Contents/Resources"
    resources.mkdir(exist_ok=True)
    if not args.baseline:
        # Crest's existing views resolve assets and catalogs through Bundle.main.
        # Preserve those resources when its window composition is framework-hosted.
        for resource in (ui / "Resources").iterdir():
            if resource.name == "Info.plist":
                continue
            subprocess.run(["ditto", str(resource), str(resources / resource.name)], check=True)
        sparkle = ui.parent / "Sparkle.framework"
        if not sparkle.is_dir():
            parser.error("The native UI build must supply Sparkle.framework beside the host framework")
        subprocess.run(["ditto", str(sparkle), str(frameworks / "Sparkle.framework")], check=True)
        icon = resources / "Crest.icns"
        dock_plugin = ui.parent / "CrestDockTilePlugin.docktileplugin"
        if not icon.is_file() or not dock_plugin.is_dir():
            parser.error("The native UI build must supply Crest.icns and CrestDockTilePlugin.docktileplugin")
        plugins = output / "Contents/PlugIns"
        plugins.mkdir(exist_ok=True)
        subprocess.run(["ditto", str(dock_plugin), str(plugins / dock_plugin.name)], check=True)
        # Chromium's native menus also resolve its legacy app.icns resource.
        shutil.copy2(icon, resources / "app.icns")
    if args.product:
        # The product hosts the native UI on every launch, including the ones
        # that carry no switches: Finder, a login item, the default-browser
        # role and Dock reopen.
        (resources / "Crest-Native-Host").write_text("Native Crest host composition.\n")
    else:
        (resources / "Crest-Isolated-Experiment").write_text("Explicit experimental profile required.\n")
    shutil.copy2(repo / "CrestEngines/Chromium/ThirdParty/Mori-LICENSE", resources / "Crest-Mori-LICENSE.txt")
    info_path = output / "Contents/Info.plist"
    with info_path.open("rb") as stream:
        info = plistlib.load(stream)
    info["CFBundleIdentifier"] = identity
    info["CFBundleDisplayName"] = (
        "Crest" if args.product
        else "Crest Chromium Baseline" if args.baseline
        else "Crest Chromium Experiment")
    info["CFBundleName"] = info["CFBundleDisplayName"]
    if not args.baseline:
        with (ui / "Resources/Info.plist").open("rb") as stream:
            ui_info = plistlib.load(stream)
        info["CrestChromiumEngineVersion"] = info["CFBundleShortVersionString"]
        info["CFBundleShortVersionString"] = ui_info["CFBundleShortVersionString"]
        info["CFBundleVersion"] = ui_info["CFBundleVersion"]
        info["CFBundleIconFile"] = "Crest"
        info["CFBundleIconName"] = "Crest"
        info["NSDockTilePlugIn"] = "CrestDockTilePlugin.docktileplugin"
        info["CrestAppIconPreferenceDomain"] = info["CFBundleIdentifier"]
        with (repo / "CrestMac/Configuration/Crest-Info.plist").open("rb") as stream:
            crest_info = plistlib.load(stream)
        info["CrestCloudKitContainerIdentifier"] = crest_info["CrestCloudKitContainerIdentifier"]
    if args.product:
        # Crest's own browser registration, document handling and update feed.
        # The keys stay owned by the app's Info.plist; nothing is restated here.
        for key, value in crest_info.items():
            if isinstance(value, str) and "$(" in value:
                continue
            if key.startswith("SU") or key in ("CFBundleURLTypes", "CFBundleDocumentTypes"):
                info[key] = value
        # Crest's Info.plist leaves the channel to its target's build setting;
        # a packaged product follows that same default, read from project.yml
        # unless CREST_DEFAULT_UPDATE_CHANNEL overrides it.
        info["CrestDefaultUpdateChannel"] = default_update_channel(repo)
        if "SUFeedURL" not in info or "SUPublicEDKey" not in info:
            parser.error("Crest's Info.plist must supply the Sparkle feed and public key for a product package")
    else:
        # This experiment must not register as the system HTTP/HTTPS handler.
        info.pop("CFBundleURLTypes", None)
        info.pop("CFBundleDocumentTypes", None)
    with info_path.open("wb") as stream:
        plistlib.dump(info, stream)
    targets = [] if args.baseline else [frameworks / "CrestCore.Native.dylib", frameworks / ui.name,
                                      output / "Contents/PlugIns/CrestDockTilePlugin.docktileplugin"]
    targets += sorted((p for p in frameworks.rglob("*.app") if not p.is_symlink()), key=lambda p: len(p.parts), reverse=True)
    targets += sorted((p for p in frameworks.glob("*.framework") if p.name != ui.name), key=lambda p: len(p.parts), reverse=True)
    if cloud_entitlements:
        shutil.copy2(args.provisioning_profile, output / "Contents/embedded.provisionprofile")
    for target in [*targets, output]:
        if target == output and (cloud_entitlements or product_entitlements):
            existing = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(output)],
                                      capture_output=True, check=True).stdout
            entitlements = plistlib.loads(existing) if existing.strip() else {}
            entitlements.update(product_entitlements or {})
            entitlements.update(cloud_entitlements or {})
            with tempfile.TemporaryDirectory(prefix="crest-cloud-sign-") as temporary:
                path = Path(temporary) / "entitlements.plist"
                path.write_bytes(plistlib.dumps(entitlements))
                subprocess.run(["codesign", "--force", "--sign", args.signing_identity,
                                "--preserve-metadata=flags,runtime", "--entitlements", str(path), str(target)], check=True)
            continue
        subprocess.run(["codesign", "--force", "--sign", args.signing_identity, "--preserve-metadata=entitlements,flags,runtime", str(target)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(output)], check=True)
    if args.product:
        print(f"Packaged {output} with Crest's product identity. It launches without switches and registers "
              "for HTTP, HTTPS and HTML documents once it is installed and its signature is accepted. "
              "Distribution still requires signing and provisioning that identity.")
        return
    mode = "" if args.baseline else "--crest-control-plane and "
    print(f"Packaged {output}. Launch its executable with {mode}an explicit experimental --user-data-dir.")


if __name__ == "__main__":
    main()
