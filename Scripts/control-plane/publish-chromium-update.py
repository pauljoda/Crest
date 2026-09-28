#!/usr/bin/env python3
"""Commit a built upstream update, publish its engine, and open its review."""
import argparse
import json
import os
from pathlib import Path
import re
import sys

from chromium_fork import ENGINE, REPO, read_json, run, write_json
import chromium_engine


def automatic_release_allowed(policy, *, enabled, stable_ready, engine, default_branch, major_update):
    return (enabled == "true" and stable_ready == "true" and engine == "chromium"
            and policy["automaticChannel"] == "stable"
            and policy["integrationBranch"] == default_branch
            and (not major_update or policy["automaticMajorUpdates"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--ninja", type=Path, required=True)
    parser.add_argument("--base-sha", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--major-update", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-f0-9]{40}", args.base_sha):
        parser.error("Expected an immutable base commit")
    policy = read_json(REPO / ENGINE / "fork.json")
    base = policy["integrationBranch"]
    tag = read_json(REPO / ENGINE / "source.lock.json")["ungoogledMac"]["tag"]
    branch = f"codex/chromium-upstream-{tag}-{args.base_sha[:12]}"
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
    notes_path = REPO / "Documentation/ReleaseNotes.json"
    notes = read_json(notes_path)
    entry = f"chromium-upstream-{tag.replace('.', '-')}-{args.base_sha[:12]}"
    if entry in notes["entries"]:
        parser.error("This upstream update already has a release note")
    notes["entries"][entry] = {"category": "fixed", "message": f"Chromium is updated to {tag.split('-')[0]} with upstream security and compatibility fixes."}
    write_json(notes_path, notes)
    run("git", "add", *sorted(allowed_paths), "Config/Version.xcconfig", "Documentation/ReleaseNotes.json")
    run(REPO / "Scripts/check-version.sh", "--fix-commit")
    run("git", "commit", "-m", f"Update Chromium to {tag}")
    head = run("git", "rev-parse", "HEAD", capture=True).strip()
    # A branch is never pushed until its engine is available by the exact input key.
    run(sys.executable, REPO / "Scripts/control-plane/publish-chromium-engine.py",
        "--source", args.source, "--ninja", args.ninja, "--repository", args.repository)
    run("git", "push", "origin", f"HEAD:refs/heads/{branch}")
    body = (f"Updates the maintained Chromium fork to upstream {tag}.\n\n"
            "The unchanged Crest patch set applied without fuzz, and the performance engine built successfully. "
            f"Engine: `{chromium_engine.release_tag(chromium_engine.engine_key(REPO))}`.\n\n"
            "The app signing, notarization, and publication workflow runs after promotion. "
            "A compiled engine alone does not verify native browsing behavior.")
    existing = json.loads(run("gh", "pr", "list", "--repo", args.repository, "--head", branch,
                              "--base", base, "--state", "open", "--json", "url", capture=True))
    url = existing[0]["url"] if existing else run("gh", "pr", "create", "--repo", args.repository,
        "--base", base, "--head", branch, "--title", f"Update Chromium to {tag}", "--body", body, capture=True).strip()
    default_branch = json.loads(run("gh", "api", f"repos/{args.repository}", capture=True))["default_branch"]
    promote = automatic_release_allowed(policy, enabled=os.environ.get("CHROMIUM_AUTO_RELEASE"),
        stable_ready=os.environ.get("CHROMIUM_STABLE_READY"), engine=os.environ.get("CREST_MACOS_ENGINE"),
        default_branch=default_branch, major_update=args.major_update)
    print(url)
    if output := os.environ.get("GITHUB_OUTPUT"):
        with Path(output).open("a") as stream:
            stream.write(f"pull_request={url}\nhead={head}\nautomatic_release={str(promote).lower()}\n")


if __name__ == "__main__":
    main()
