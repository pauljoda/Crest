#!/usr/bin/env python3
"""Commit a built upstream update and open it as a draft for review.

The engine is not published here. A maintainer tests the build, publishes it
from the build Mac with `publish-chromium-engine.py`, and only then merges, so
nothing an update builds reaches people without that decision.
"""
import argparse
import json
import os
from pathlib import Path
import re
import sys

from chromium_fork import ENGINE, REPO, read_json, run
import chromium_engine

sys.path.insert(0, str(REPO / "Scripts"))
import release_note_catalog  # noqa: E402


def update_plan(receipt, *, version, base_sha, engine_key):
    """The plan behind `receipt`, once the receipt is shown to be this update's own build.

    The receipt is read after the build has released the workspace, so another
    build may have replaced it with one for a different release or commit.
    """
    if "plan" not in receipt:
        raise ValueError("The receipt has no update plan; pass the receipt of this update's build")
    found = {"chromium": receipt.get("chromium"), "commit": receipt.get("commit"), "engineKey": receipt.get("engineKey")}
    expected = {"chromium": version, "commit": base_sha, "engineKey": engine_key}
    if found != expected:
        raise ValueError(f"The receipt belongs to another build: {found}, expected {expected}")
    plan = read_json(Path(receipt["plan"]) / "plan.json")
    if plan["version"] != version:
        raise ValueError(f"The receipt's plan is for {plan['version']}, not {version}")
    return plan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-sha", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--receipt", type=Path, required=True, help="The build's last-build.json")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-f0-9]{40}", args.base_sha):
        parser.error("Expected an immutable base commit")
    policy = read_json(REPO / ENGINE / "fork.json")
    base = policy["integrationBranch"]
    version = read_json(REPO / ENGINE / "source.lock.json")["chromium"]["version"]
    receipt = read_json(args.receipt)
    try:
        plan = update_plan(receipt, version=version, base_sha=args.base_sha,
                           engine_key=chromium_engine.engine_key(REPO))
    except ValueError as error:
        parser.error(str(error))
    branch = f"codex/chromium-upstream-{version}-{args.base_sha[:12]}"
    allowed_paths = {str(ENGINE / "source.lock.json"), str(ENGINE / "host-inputs.json")}
    changed = set(run("git", "diff", "--name-only", capture=True).splitlines())
    if not changed or not changed <= allowed_paths:
        parser.error("Upstream preparation changed unexpected files, or produced no update")
    if run("git", "ls-files", "--others", "--exclude-standard", capture=True).strip():
        parser.error("Unexpected untracked files in the update checkout")
    if run("git", "rev-parse", "HEAD", capture=True).strip() != args.base_sha:
        parser.error("The update checkout moved since preparation")
    run("git", "switch", "-c", branch)
    run("git", "config", "user.name", "github-actions[bot]")
    run("git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com")
    run(REPO / "Scripts/set-version.sh", "--patch")
    crest_version = release_note_catalog.Version.from_version_file(
        (REPO / "Config/Version.xcconfig").read_text(), "Config/Version.xcconfig")
    note = {"id": f"chromium-upstream-{version.replace('.', '-')}-{args.base_sha[:12]}", "category": "fixed",
            "message": f"Chromium is updated to {version} with upstream security and compatibility fixes.",
            "platforms": ["mac"]}
    notes_path = release_note_catalog.append_entry(REPO, crest_version, note)
    run("git", "add", *sorted(allowed_paths), "Config/Version.xcconfig", str(notes_path.relative_to(REPO)))
    run(REPO / "Scripts/check-version.sh", "--fix-commit")
    run("git", "commit", "-s", "-m", f"Update Chromium to {version}")
    run("git", "push", "origin", f"HEAD:refs/heads/{branch}")
    body = review_body(version, plan, receipt, chromium_engine.release_tag(chromium_engine.engine_key(REPO)))
    existing = json.loads(run("gh", "pr", "list", "--repo", args.repository, "--head", branch,
                              "--base", base, "--state", "open", "--json", "url", capture=True))
    url = existing[0]["url"] if existing else run("gh", "pr", "create", "--repo", args.repository, "--draft",
        "--base", base, "--head", branch, "--title", f"Update Chromium to {version}", "--body", body, capture=True).strip()
    print(url)
    if output := os.environ.get("GITHUB_OUTPUT"):
        with Path(output).open("a") as stream:
            stream.write(f"pull_request={url}\n")


def review_body(version, plan, receipt, tag):
    """The draft's description: what upstream fixed, how the update went, and what is left before it ships."""
    notes = plan.get("releaseNotes", {})
    if "error" in notes:
        security = notes["error"] + "."
    else:
        covered = "" if notes["exact"] else f" (the note for {notes['notedVersion']}, the latest release it covers)"
        security = (f"Upstream's release note{covered}: {notes['securityFixes']} security fixes, "
                    f"{notes['critical']} Critical and {notes['high']} High"
                    f"{', one of them exploited in the wild' if notes['exploited'] else ''}"
                    f"{'. This is an early stable release, which reaches a small share of people first' if notes['earlyStable'] else ''}.")
    minutes = {step: round(seconds / 60) for step, seconds in receipt.get("secondsPerStep", {}).items()}
    return (f"Updates Chromium from {plan['current']} to {version}"
            f"{', a new milestone' if plan['milestone'] else ''}.\n\n{security}\n\n"
            f"The build {'advanced the pinned source in place' if plan['path'] == 'advance' else 'prepared a new source'}"
            f"{' and recompiled everything for the new PGO profile' if plan['pgoChanged'] else ''}. "
            f"Every Crest patch applied without fuzz, and the engine passed its headless smoke check. "
            f"Minutes per step: {json.dumps(minutes)}.\n\n"
            f"Engine `{tag}` is built on the build Mac and **not published**. Before this leaves draft:\n\n"
            "1. Package Crest with `package-chromium-host.py --product --distribution` from the built engine and "
            "load real pages, extensions and sign-ins in an isolated copy.\n"
            "2. A maintainer publishes the engine with `publish-chromium-engine.py`.\n"
            "3. Merging then publishes it to Development.\n")


if __name__ == "__main__":
    main()
