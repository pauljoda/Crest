#!/usr/bin/env python3
"""Publish the content filter archive `content_filter.py build` made.

Run after `content_filter.py build` for the current sources, with the lock it
wrote committed. The archive is only published when the sources hash to the
lock's key and the archive matches the lock's digest, so every build that
downloads it by key gets the libraries the sources compile to. Publishing is
idempotent: an archive already released under its key is left as it is, and a
release that holds anything else is never replaced.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import content_filter  # noqa: E402


def run(*command, **kwargs):
    return subprocess.run(list(map(str, command)), check=True, text=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="The built archive (default: the crate's target/artifact)")
    parser.add_argument("--repository", default="pauljoda/Crest")
    parser.add_argument("--dry-run", action="store_true", help="Verify without uploading")
    args = parser.parse_args()

    repo = content_filter.REPOSITORY
    lock = content_filter.read_lock(repo)
    key = content_filter.artifact_key(repo)
    if lock["key"] != key:
        raise SystemExit(f"{content_filter.LOCK} is for key {lock['key'][:16]}, but the sources hash to {key[:16]}: "
                         "run content_filter.py build and commit the lock")
    tag, asset = content_filter.release_tag(key), content_filter.asset_name(key)
    archive = args.archive or repo / content_filter.CRATE / "target/artifact" / asset
    if archive.name != asset or not archive.is_file():
        raise SystemExit(f"No {asset} to publish; run content_filter.py build first")
    if content_filter.sha256(archive) != lock["sha256"]:
        raise SystemExit(f"{asset} does not match the digest in {content_filter.LOCK}; build it again")

    existing = subprocess.run(["gh", "release", "view", tag, "--repo", args.repository, "--json", "assets,isDraft,body"],
                              capture_output=True, text=True)
    release = json.loads(existing.stdout) if existing.returncode == 0 else None
    if release and not release["isDraft"]:
        names = {item["name"] for item in release["assets"]}
        if {asset, f"{asset}.sha256"} <= names and key in release["body"]:
            print(f"{tag} is already published.")
            return
        raise SystemExit("The published content filter release is incomplete or has a different key; "
                         "refusing to overwrite it")
    print(f"Verified {asset} ({archive.stat().st_size // (1 << 20)} MiB, sha256 {lock['sha256']}).")
    if args.dry_run:
        return

    commit = run("git", "-C", repo, "rev-parse", "HEAD", capture_output=True).stdout.strip()
    with tempfile.TemporaryDirectory(prefix="crest-content-filter-") as temporary:
        checksum = Path(temporary) / f"{asset}.sha256"
        checksum.write_text(f"{lock['sha256']}  {asset}\n")
        notes = ("Crest's content filter, Brave's adblock engine behind Crest's C interface, compiled for "
                 "macOS, iOS and the iOS Simulator for the native core to link.\n\n"
                 f"Content filter key `{key}`, computed by `Scripts/control-plane/content_filter.py` over the "
                 f"crate and its recipe at commit `{commit}`.")
        if existing.returncode != 0:
            run("gh", "release", "create", tag, "--repo", args.repository, "--draft", "--prerelease", "--latest=false",
                "--title", f"Crest content filter {key[:16]}", "--notes", notes)
        # Only an unpublished draft can be resumed or replaced. The release
        # becomes visible to builds after every asset has uploaded.
        run("gh", "release", "upload", tag, archive, checksum, "--repo", args.repository, "--clobber")
        run("gh", "release", "edit", tag, "--repo", args.repository, "--draft=false", "--latest=false")
    print(f"Published {tag}.")


if __name__ == "__main__":
    main()
