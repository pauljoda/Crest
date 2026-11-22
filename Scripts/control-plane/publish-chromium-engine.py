#!/usr/bin/env python3
"""Publish the locally built Chromium engine for release workflows to download.

Run after `build-chromium-baseline.py` finishes for the current sources. The
engine is only published when the external tree holds exactly this branch's
host patch and overlay and its build output is current, so the release that
downloads it by key compiles against the same engine it was published for.
Publishing is idempotent: an engine already released under its key is left
as it is.
"""
import argparse
from contextlib import nullcontext
import json
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import chromium_engine  # noqa: E402
from chromium_fork import (exclusive_workspace, performance_configuration_matches, read_json, sha256,  # noqa: E402
                           universal_engine)
from repository import REPOSITORY  # noqa: E402


def run(*command, **kwargs):
    return subprocess.run(list(map(str, command)), check=True, text=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path, help="The pinned external Chromium checkout")
    parser.add_argument("--ninja", required=True, type=Path)
    parser.add_argument("--repository", default=REPOSITORY)
    parser.add_argument("--dry-run", action="store_true", help="Verify and package without uploading")
    args = parser.parse_args()

    source = args.source.resolve()
    # A managed source is <workspace>/sources/<preparation key>/src.
    managed = source.parent / "prepared.json"
    guard = exclusive_workspace(source.parents[2]) if managed.is_file() else nullcontext()
    with guard:
        publish(args)


def publish(args):
    repo = Path(__file__).resolve().parents[2]
    source = args.source.resolve()
    lock = read_json(repo / "CrestEngines/Chromium/source.lock.json")
    for cpu in lock["architectures"]:
        if not performance_configuration_matches(source, lock, cpu=cpu):
            raise SystemExit(f"Published engines require the pinned performance configuration, SDK and PGO profile "
                             f"for {cpu}")
    run(sys.executable, repo / "Scripts/control-plane/prepare-chromium.py", "--source", source, "--verify-only")
    key = chromium_engine.engine_key(repo)
    tag, asset = chromium_engine.release_tag(key), chromium_engine.asset_name(key)

    # The tree must hold this branch's reviewed patch output and overlay.
    validation = run(sys.executable, repo / "Scripts/control-plane/apply-chromium-host.py",
                     "--source", source, capture_output=True).stdout
    if "(after)" not in validation:
        raise SystemExit("Apply the host to the checkout before publishing: " + validation.strip())
    overlay = repo / "CrestEngines/Chromium/Overlay"
    for path in overlay.rglob("*"):
        if path.is_file() and (source / path.relative_to(overlay)).read_bytes() != path.read_bytes():
            raise SystemExit(f"The checkout's overlay differs from the branch: {path.relative_to(overlay)}")
    headers = [repo / "CrestEngines/Chromium/Apple/CrestChromiumHost.h",
               repo / "CrestCore/native/ContentFilter/include/crest_content_filter.h"]
    headers += [repo / "CrestContracts/include" / name for name in
                ("crest_core.h", "crest_app.h", "crest_engine.h", "crest_engine_contract.h")]
    for header in headers:
        if (source / "chrome/browser/ui/crest" / header.name).read_bytes() != header.read_bytes():
            raise SystemExit(f"The checkout's contract header differs from the branch: {header.name}")

    # And every architecture's build must have nothing left to do.
    for architecture in lock["architectures"].values():
        plan = run(args.ninja, "-C", source / architecture["output"], "-n", "chrome", capture_output=True).stdout
        if "no work to do" not in plan:
            raise SystemExit(f"The {architecture['output']} build is not current; run build-chromium-baseline.py first")

    # The universal engine merges them again here, so it holds exactly what
    # they built, and every executable must hold every architecture.
    try:
        browser = universal_engine(source, lock)
    except ValueError as error:
        raise SystemExit(str(error)) from None
    helpers = browser.glob("Contents/Frameworks/*.framework/Versions/*/Helpers/*.app")
    if unknown := chromium_engine.unknown_engine_helpers(helpers):
        raise SystemExit(f"Unknown engine helpers {unknown}: add each to ENGINE_HELPER_KINDS in chromium_engine.py")
    existing = subprocess.run(["gh", "release", "view", tag, "--repo", args.repository, "--json", "assets,isDraft,body"],
                              capture_output=True, text=True)
    release = json.loads(existing.stdout) if existing.returncode == 0 else None
    if release and not release["isDraft"]:
        names = {item["name"] for item in release["assets"]}
        if {asset, f"{asset}.sha256"} <= names and key in release["body"]:
            print(f"{tag} is already published.")
            return
        raise SystemExit("Published engine release is incomplete or has a different full key; refusing to overwrite it")

    with tempfile.TemporaryDirectory(prefix="crest-engine-") as temporary:
        archive = Path(temporary) / asset
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", browser, archive)
        digest = sha256(archive)
        checksum = Path(temporary) / f"{asset}.sha256"
        checksum.write_text(f"{digest}  {asset}\n")
        print(f"Packaged {asset} ({archive.stat().st_size // (1 << 20)} MiB, sha256 {digest}).")
        if args.dry_run:
            return
        provenance = Path(temporary) / f"{asset}.json"
        provenance.write_text(json.dumps({"schemaVersion": 1, "engineKey": key,
            "chromium": lock["chromium"]["version"], "sourceArchiveSHA256": lock["chromium"]["sourceArchiveSha256"],
            "configuration": "performance", "sdkVersion": lock["performanceInputs"]["macSDKVersion"],
            "pgoSHA256": {cpu: architecture["pgoSHA256"] for cpu, architecture in lock["architectures"].items()},
            "architectures": list(lock["architectures"]), "archiveSHA256": digest,
            "sourceCommit": run("git", "-C", repo, "rev-parse", "HEAD", capture_output=True).stdout.strip()}, indent=2) + "\n")
        notes = (f"Chromium {lock['chromium']['version']} with Crest's native host, for release packaging.\n\n"
                 f"Engine key `{key}`, computed by `Scripts/control-plane/chromium_engine.py` over the "
                 f"engine inputs of commit `{run('git', '-C', repo, 'rev-parse', 'HEAD', capture_output=True).stdout.strip()}`.\n"
                 "This is not an installable browser; releases package it with Crest's UI and sign it.")
        if existing.returncode != 0:
            run("gh", "release", "create", tag, "--repo", args.repository, "--draft", "--prerelease", "--latest=false",
                "--title", f"Crest Chromium engine {key[:16]}", "--notes", notes)
        # Only an unpublished draft can be resumed or replaced. The release becomes
        # visible to app packaging after all assets have uploaded successfully.
        run("gh", "release", "upload", tag, archive, checksum, provenance, "--repo", args.repository, "--clobber")
        run("gh", "release", "edit", tag, "--repo", args.repository, "--draft=false", "--latest=false")
        print(f"Published {tag}.")


if __name__ == "__main__":
    main()
