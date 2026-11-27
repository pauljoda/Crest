#!/usr/bin/env python3
"""Publish the locally built Chromium engine for release workflows to download.

Run after `build-chromium-baseline.py` finishes for the current sources. The
engine is only published when the external tree holds exactly this branch's
host patch and overlay and its build output is current, so the release that
downloads it by key compiles against the same engine it was published for.
Publishing is idempotent: an engine already released under its key is left
as it is, and publishing removes the engine's draft candidate.

`--candidate` uploads the same verified engine to a draft release named by
`chromium_engine.candidate_tag` instead, where a scheduled update leaves it for
review. Release packaging never reads that release, and nothing publishes it.

`--host win-x64` publishes the Windows engine from a Windows build machine
instead: the runtime files of its one performance build in out/CrestBaseline,
picked as Crest's Windows package picks them, zipped in a `Chromium` folder.
"""
import argparse
from contextlib import nullcontext
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import chromium_engine  # noqa: E402
import chromium_host  # noqa: E402
from repository import REPOSITORY  # noqa: E402


def run(*command, **kwargs):
    return subprocess.run(list(map(str, command)), check=True, text=True, **kwargs)


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def mac_fork():
    """The Mac's fork maintenance, which merges its universal engine and locks
    its managed workspaces with POSIX file locks, so only the Mac loads it."""
    import chromium_fork
    return chromium_fork


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path, help="The pinned external Chromium checkout")
    parser.add_argument("--ninja", required=True, type=Path)
    parser.add_argument("--repository", default=REPOSITORY)
    parser.add_argument("--dry-run", action="store_true", help="Verify and package without uploading")
    parser.add_argument("--candidate", action="store_true",
                        help="Upload to the engine's draft candidate release; publish nothing")
    parser.add_argument("--host", choices=sorted(chromium_engine.HOST_INPUTS),
                        help="The engine's host (default: this machine's): the Mac's universal engine, or another host's own")
    args = parser.parse_args()
    args.host = args.host or chromium_host.detected()
    if args.candidate and args.host != chromium_engine.MAC:
        parser.error("Only the Mac's scheduled engine updates leave a candidate for review")

    source = args.source.resolve()
    # A managed source is <workspace>/sources/<preparation key>/src.
    managed = source.parent / "prepared.json"
    mac = args.host == chromium_engine.MAC
    guard = mac_fork().exclusive_workspace(source.parents[2]) if mac and managed.is_file() else nullcontext()
    with guard:
        publish(args)


def publish(args):
    repo = Path(__file__).resolve().parents[2]
    source = args.source.resolve()
    host = args.host
    mac = host == chromium_engine.MAC
    lock = read_json(repo / "CrestEngines/Chromium/source.lock.json")
    if mac:
        for cpu in lock["architectures"]:
            if not mac_fork().performance_configuration_matches(source, lock, cpu=cpu):
                raise SystemExit(f"Published engines require the pinned performance configuration, SDK and PGO "
                                 f"profile for {cpu}")
        outputs = [architecture["output"] for architecture in lock["architectures"].values()]
    else:
        if not host_configuration_matches(source, lock, host):
            raise SystemExit(f"Published engines require {host}'s pinned performance configuration in "
                             f"{HOST_OUTPUT}; run configure-chromium.py --configuration performance")
        outputs = [HOST_OUTPUT]
    run(sys.executable, repo / "Scripts/control-plane/prepare-chromium.py", "--source", source, "--verify-only")
    key = chromium_engine.engine_key(repo, host)
    tag, asset = chromium_engine.release_tag(key, host), chromium_engine.asset_name(key, host)
    candidate = chromium_engine.candidate_tag(key) if mac else None

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
    for output in outputs:
        plan = run(args.ninja, "-C", source / output, "-n", "chrome", capture_output=True).stdout
        if "no work to do" not in plan:
            raise SystemExit(f"The {output} build is not current; run build-chromium-baseline.py first")

    if mac:
        # The universal engine merges them again here, so it holds exactly what
        # they built, every executable must hold every architecture, and the
        # browser executable must be Crest's own entry point.
        try:
            browser = mac_fork().universal_engine(source, lock)
            mac_fork().require_crest_launch(browser)
        except ValueError as error:
            raise SystemExit(str(error)) from None
        helpers = browser.glob("Contents/Frameworks/*.framework/Versions/*/Helpers/*.app")
        if unknown := chromium_engine.unknown_engine_helpers(helpers):
            raise SystemExit(f"Unknown engine helpers {unknown}: add each to ENGINE_HELPER_KINDS in chromium_engine.py")
    else:
        runtime = windows_engine_files(repo, source / HOST_OUTPUT)
    existing = subprocess.run(["gh", "release", "view", tag, "--repo", args.repository, "--json", "assets,isDraft,body"],
                              capture_output=True, text=True)
    release = json.loads(existing.stdout) if existing.returncode == 0 else None
    if release and not release["isDraft"]:
        names = {item["name"] for item in release["assets"]}
        if {asset, f"{asset}.sha256"} <= names and key in release["body"]:
            print(f"{tag} is already published.")
            if mac and not args.candidate and not args.dry_run:
                remove_candidate(args.repository, candidate)
            return
        raise SystemExit("Published engine release is incomplete or has a different full key; refusing to overwrite it")
    if args.candidate:
        tag = candidate
        existing = subprocess.run(["gh", "release", "view", tag, "--repo", args.repository, "--json", "isDraft"],
                                  capture_output=True, text=True)
        if existing.returncode == 0 and not json.loads(existing.stdout)["isDraft"]:
            raise SystemExit(f"{tag} is published; a candidate must stay a draft")

    with tempfile.TemporaryDirectory(prefix="crest-engine-") as temporary:
        archive = Path(temporary) / asset
        if mac:
            run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", browser, archive)
        else:
            zip_engine(source / HOST_OUTPUT, runtime, archive)
        digest = sha256(archive)
        checksum = Path(temporary) / f"{asset}.sha256"
        checksum.write_text(f"{digest}  {asset}\n")
        print(f"Packaged {asset} ({archive.stat().st_size // (1 << 20)} MiB, sha256 {digest}).")
        if args.dry_run:
            return
        provenance = Path(temporary) / f"{asset}.json"
        source_commit = run("git", "-C", repo, "rev-parse", "HEAD", capture_output=True).stdout.strip()
        if mac:
            details = {"configuration": "performance", "sdkVersion": lock["performanceInputs"]["macSDKVersion"],
                       "pgoSHA256": {cpu: architecture["pgoSHA256"] for cpu, architecture in lock["architectures"].items()},
                       "architectures": list(lock["architectures"])}
        else:
            target = chromium_host.profile(host, lock)["performanceBuildArguments"]["target_cpu"]
            details = {"host": host, "configuration": "performance", "architectures": [target]}
        provenance.write_text(json.dumps({"schemaVersion": 1, "engineKey": key,
            "chromium": lock["chromium"]["version"], "sourceArchiveSHA256": lock["chromium"]["sourceArchiveSha256"],
            **details, "archiveSHA256": digest, "sourceCommit": source_commit}, indent=2) + "\n")
        purpose = ("an unpublished candidate for review. Release packaging never reads it; a maintainer publishes "
                   f"the engine as `{chromium_engine.release_tag(key)}`" if args.candidate else "for release packaging")
        hosted = "Crest's native host" if mac else f"Crest's desktop host, for {host}"
        notes = (f"Chromium {lock['chromium']['version']} with {hosted}, {purpose}.\n\n"
                 f"Engine key `{key}`, computed by `Scripts/control-plane/chromium_engine.py` over the "
                 f"engine inputs of commit `{source_commit}`.\n"
                 "This is not an installable browser; releases package it with Crest's UI and sign it.")
        if existing.returncode != 0:
            title = f"Crest Chromium engine {'candidate ' if args.candidate else ''}{key[:16]}"
            run("gh", "release", "create", tag, "--repo", args.repository, "--draft", "--prerelease", "--latest=false",
                "--title", title, "--notes", notes)
        # Only an unpublished draft can be resumed or replaced. The release becomes
        # visible to app packaging after all assets have uploaded successfully.
        run("gh", "release", "upload", tag, archive, checksum, provenance, "--repo", args.repository, "--clobber")
        if args.candidate:
            print(f"Uploaded the candidate engine to the draft {tag}.")
            if output := os.environ.get("GITHUB_OUTPUT"):
                with open(output, "a") as stream:
                    stream.write(f"candidate={tag}\n")
            return
        run("gh", "release", "edit", tag, "--repo", args.repository, "--draft=false", "--latest=false")
        print(f"Published {tag}.")
        if mac:
            remove_candidate(args.repository, candidate)


# Every host but the Mac builds its one architecture in the output preparation made.
HOST_OUTPUT = "out/CrestBaseline"


def host_configuration_matches(source, lock, host):
    """Whether `host`'s output is configured exactly as configure-chromium.py
    configures a performance build: the lock's arguments and the host's."""
    expected = {**lock["buildArguments"], **chromium_host.profile(host, lock)["performanceBuildArguments"]}
    try:
        text = (source / HOST_OUTPUT / "args.gn").read_text(encoding="utf-8")
    except OSError:
        return False
    values = {}
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = re.fullmatch(r"\s*(\w+)\s*=\s*(.+?)\s*", line)
        if not match:
            return False
        try:
            values[match[1]] = json.loads(match[2])
        except ValueError:
            return False
    return values == expected


def windows_engine_files(repo, output):
    """The engine's runtime files in `output`, picked as Crest's Windows
    package picks them, so the published engine holds what Setup installs."""
    sys.path.insert(0, str(repo / "Scripts"))
    specification = importlib.util.spec_from_file_location("package_windows", repo / "Scripts/package-windows.py")
    packaging = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(packaging)
    try:
        return packaging.engine_files(output)
    except packaging.PackagingError as error:
        raise SystemExit(str(error)) from None


def zip_engine(output, files, archive):
    """`files`, relative to `output`, in the archive's `Chromium` folder."""
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as engine:
        for relative in files:
            engine.write(output / relative, f"Chromium/{relative.as_posix()}")


def remove_candidate(repository, candidate):
    """Delete the engine's draft candidate, now that the engine is published."""
    found = subprocess.run(["gh", "release", "view", candidate, "--repo", repository, "--json", "isDraft"],
                           capture_output=True, text=True)
    if found.returncode == 0 and json.loads(found.stdout)["isDraft"]:
        run("gh", "release", "delete", candidate, "--repo", repository, "--yes")
        print(f"Removed the draft candidate {candidate}.")


if __name__ == "__main__":
    main()
