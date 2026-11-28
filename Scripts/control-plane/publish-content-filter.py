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
from repository import REPOSITORY  # noqa: E402


def run(*command, **kwargs):
    return subprocess.run(list(map(str, command)), check=True, text=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="The built archive (default: the crate's target/artifact)")
    parser.add_argument("--family", choices=sorted(content_filter.FAMILY_HOSTS),
                        help="The family to publish (default: this machine's)")
    parser.add_argument("--repository", default=REPOSITORY)
    parser.add_argument("--dry-run", action="store_true", help="Verify without uploading")
    args = parser.parse_args()

    repo = content_filter.REPOSITORY
    lock = content_filter.read_lock(repo)
    key = content_filter.artifact_key(repo)
    if lock["key"] != key:
        raise SystemExit(f"{content_filter.LOCK} is for key {lock['key'][:16]}, but the sources hash to {key[:16]}: "
                         "run content_filter.py build and commit the lock")
    family = args.family or content_filter.host_family()
    entry = content_filter.family_archive(lock, family)
    if entry is None:
        raise SystemExit(f"{content_filter.LOCK} has no {family} archive; run content_filter.py build first")
    tag, asset = content_filter.release_tag(key), content_filter.asset_name(key, family)
    archive = args.archive or repo / content_filter.CRATE / "target/artifact" / asset
    if archive.name != asset or not archive.is_file():
        raise SystemExit(f"No {asset} to publish; run content_filter.py build first")
    if content_filter.sha256(archive) != entry["sha256"]:
        raise SystemExit(f"{asset} does not match the digest in {content_filter.LOCK}; build it again")

    existing = subprocess.run(["gh", "release", "view", tag, "--repo", args.repository, "--json", "assets,isDraft,body"],
                              capture_output=True, text=True)
    release = json.loads(existing.stdout) if existing.returncode == 0 else None
    checksum_text = f"{entry['sha256']}  {asset}\n"
    held = set()
    if release:
        names = {item["name"] for item in release["assets"]}
        if key not in release["body"]:
            raise SystemExit("The content filter release has a different key; refusing to change it")
        # A published release gains another family's archive beside the ones
        # builds already download; nothing it holds is ever replaced. What an
        # interrupted run left is kept when it is the locked archive and its
        # checksum, and the rest is uploaded.
        held = {name for name in (asset, f"{asset}.sha256") if name in names}
        if held:
            with tempfile.TemporaryDirectory(prefix="crest-content-filter-held-") as temporary:
                for name in held:
                    run("gh", "release", "download", tag, "--repo", args.repository, "--pattern", name,
                        "--dir", temporary)
                if asset in held and content_filter.sha256(Path(temporary) / asset) != entry["sha256"]:
                    raise SystemExit(f"{tag} holds a different {asset}; refusing to overwrite it")
                if f"{asset}.sha256" in held and \
                        (Path(temporary) / f"{asset}.sha256").read_text(encoding="utf-8") != checksum_text:
                    raise SystemExit(f"{tag} holds a different {asset}.sha256; refusing to overwrite it")
        if len(held) == 2 and not release["isDraft"]:
            print(f"{asset} is already published in {tag}.")
            return
    print(f"Verified {asset} ({archive.stat().st_size // (1 << 20)} MiB, sha256 {entry['sha256']}).")
    if args.dry_run:
        return

    commit = run("git", "-C", repo, "rev-parse", "HEAD", capture_output=True).stdout.strip()
    with tempfile.TemporaryDirectory(prefix="crest-content-filter-") as temporary:
        checksum = Path(temporary) / f"{asset}.sha256"
        checksum.write_text(checksum_text, encoding="utf-8", newline="\n")
        notes = ("Crest's content filter, Brave's adblock engine behind Crest's C interface, compiled for "
                 "each platform family's runtimes for the native core to link; each family is one archive.\n\n"
                 f"Content filter key `{key}`, computed by `Scripts/control-plane/content_filter.py` over the "
                 f"crate and its recipe at commit `{commit}`.")
        if release is None:
            run("gh", "release", "create", tag, "--repo", args.repository, "--draft", "--prerelease", "--latest=false",
                "--title", f"Crest content filter {key[:16]}", "--notes", notes)
        missing = [path for path in (archive, checksum) if path.name not in held]
        if missing:
            run("gh", "release", "upload", tag, *missing, "--repo", args.repository)
        if release is None or release["isDraft"]:
            run("gh", "release", "edit", tag, "--repo", args.repository, "--draft=false", "--latest=false")
    print(f"Published {asset} in {tag}.")


if __name__ == "__main__":
    main()
