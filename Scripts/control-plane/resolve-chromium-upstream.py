#!/usr/bin/env python3
"""Decide what a run of the Chromium maintenance workflow does on the build Mac.

Reads the integration branch's pinned release, chromiumdash's stable releases
and Google's release notes, and writes the run's operation to GITHUB_OUTPUT:

- update: build a newer full stable release, on the pinned milestone or a new
  one, and open it as a draft for review;
- build: build and publish the pinned engine (manual dispatch only);
- check: report what is available and build nothing.

Separately, `preflight` names an early stable release of a newer milestone to
check Crest's patches against, days before it reaches everyone. Nothing is
built for it.
"""
import json
import os
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chromium_fork import (ENGINE, REPO, read_json, release_feed, release_notes, release_version,  # noqa: E402
                           select_update, stable_milestone, upstream_releases)

# Branches the workflow opens its draft reviews from, one per release.
UPDATE_BRANCH = "codex/chromium-upstream-"
PREFLIGHT_BRANCH = "codex/chromium-preflight-"


def resolve(*, event, operation, requested, allow_major, upstream_enabled, build_enabled, current, releases, feed,
            reviews):
    """The run's outputs and its notice, from its inputs and what upstream and the open reviews say."""
    scheduled = event == "schedule"
    # A schedule takes a new milestone once Google promotes it to full stable.
    allow_major = scheduled or (event == "workflow_dispatch" and allow_major)
    milestone = stable_milestone(feed)
    plan = select_update(current, releases, allow_major, milestone)
    version = requested or plan["candidate"] or ""
    pinned = release_version(current)[0]
    early = plan["earlyStable"] or ""
    preflight = ""
    if operation == "preflight":
        preflight, operation = requested or early, "check"
        if not preflight:
            raise SystemExit("No early stable release of a newer milestone to check")
    elif scheduled:
        operation = "update" if upstream_enabled and version else "check"
        # Each early stable release is checked once, while it is still early,
        # unless a session already has a pull request open for it.
        if (upstream_enabled and early and release_version(early)[0] > pinned
                and not any(review["headRefName"].startswith(f"{PREFLIGHT_BRANCH}{early}-")
                            or review["state"] == "OPEN" and early in review.get("title", "") for review in reviews)):
            preflight = early
    if operation == "update":
        if not version or release_version(version) <= release_version(current):
            raise SystemExit("No newer eligible upstream release. Use check to inspect milestones requiring review.")
        if version not in releases:
            raise SystemExit(f"{version} is not a stable release")
        if release_version(version)[0] != pinned and not allow_major:
            raise SystemExit("Milestone updates require allow_major")
        # A requested release obeys the same ceiling as a selected one.
        ceiling = milestone if milestone is not None else pinned
        if release_version(version)[0] > ceiling:
            raise SystemExit(f"{version} is newer than the full stable milestone {ceiling}; "
                             "run operation=preflight to check its patches")
    if (operation != "check" or preflight) and not build_enabled:
        if not scheduled:
            raise SystemExit("Set CHROMIUM_CI_ENABLED=true after configuring the build Mac")
        operation, preflight = "check", ""
    major = bool(version) and release_version(version)[0] != pinned
    for field in ("candidate", "latest", "earlyStable"):
        if plan[field] and plan[field] != current:
            plan[f"{field}Notes"] = release_notes(plan[field], feed)

    note = ""
    if operation == "update":
        # One review per upstream release: later commits on the base must not
        # rebuild it, and a schedule leaves a closed review closed. A schedule
        # also waits while any update is in review, since the next release
        # builds on what that review changes; a pull request a session opened
        # for the release counts too.
        existing = [review for review in reviews if (
            review["headRefName"].startswith(f"{UPDATE_BRANCH}{version}-")
            and (review["state"] == "OPEN" or scheduled)
            or review["state"] == "OPEN" and (scheduled and review["headRefName"].startswith(UPDATE_BRANCH)
                                              or version in review.get("title", "")))]
        if existing:
            note = f"Chromium {version} is available; {existing[0]['url']} is {existing[0]['state'].lower()}."
            operation = "check"
    exploited = operation == "update" and bool(release_notes(version, feed).get("exploited"))
    available = version or (plan["latest"] if plan["majorReviewRequired"] else "")
    if note:
        pass
    elif operation == "update":
        note = f"Building Chromium {version}. A draft PR opens when it builds; a maintainer publishes its engine."
    elif operation == "build":
        note = f"Building and publishing the pinned Chromium {current} engine."
    elif not available:
        note = f"Chromium {current} is current."
    elif scheduled:
        note = f"Chromium {available} is available. Scheduled updates are off; set CHROMIUM_UPSTREAM_ENABLED=true."
    else:
        milestone_update = release_version(available)[0] != pinned
        note = (f"Chromium {available} is available. Run operation=update"
                f"{' with allow_major' if milestone_update else ''} to build it for review.")
    if milestone is None:
        note += " Google's release notes couldn't be read, so only fixes on the pinned milestone are considered."
    if early:
        checking = "; checking Crest's patches against it" if preflight else ""
        note += f" Chromium {early} is early stable{checking}."
    if exploited:
        note += f" Upstream reports a fix for a vulnerability exploited in the wild; ship {version} the same day."
    outputs = {"operation": operation, "version": version, "major": str(major).lower(), "preflight": preflight,
               "exploited": str(exploited).lower()}
    return outputs, note, plan


def main():
    policy = read_json(REPO / ENGINE / "fork.json")
    branch = policy["integrationBranch"]
    subprocess.run(["git", "fetch", "--depth=1", "origin", f"refs/heads/{branch}"], check=True)
    sha = subprocess.check_output(["git", "rev-parse", "FETCH_HEAD"], text=True).strip()
    lock = json.loads(subprocess.check_output(["git", "show", f"{sha}:{ENGINE}/source.lock.json"], text=True))
    reviews = json.loads(subprocess.check_output(["gh", "pr", "list", "--repo", os.environ["GITHUB_REPOSITORY"],
        "--base", branch, "--state", "all", "--limit", "1000", "--json", "headRefName,url,state,title"], text=True))
    outputs, note, plan = resolve(
        event=os.environ["GITHUB_EVENT_NAME"], operation=os.environ.get("OPERATION") or "check",
        requested=os.environ.get("UPSTREAM_VERSION", ""), allow_major=os.environ.get("ALLOW_MAJOR") == "true",
        upstream_enabled=os.environ.get("UPSTREAM_ENABLED") == "true",
        build_enabled=os.environ.get("BUILD_ENABLED") == "true", current=lock["chromium"]["version"],
        releases=upstream_releases(policy), feed=release_feed(), reviews=reviews)
    print(f"::notice title=Chromium::{note}")
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"base_sha={sha}\n" + "".join(f"{key}={value}\n" for key, value in outputs.items()))
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        summary.write(note + "\n\n```json\n" + json.dumps(plan, indent=2) + "\n```\n")


if __name__ == "__main__":
    main()
