#!/usr/bin/env python3
"""Open an upstream Chromium release as a draft for review.

- A built update (the default) commits the new pins and host hashes with a
  release-note fragment; it takes its version from git when it merges. Its
  engine is not published here: a maintainer tests the build, publishes it
  from the build Mac with `publish-chromium-engine.py`, and only then merges,
  so nothing an update builds reaches people without that decision.
- `--rebase` opens a full stable release whose plan stopped on Crest's patches.
  It commits the patches as the plan carried them over, keeping the pinned
  release, and lists what a session must resolve before the engine can be
  built.
- `--preflight` does the same for an early stable release, days before it
  reaches everyone, including one whose patches all apply. Nothing is built
  for it, and the draft closes once its milestone's update opens.

Each draft is assigned to the maintainer named by `--reviewer`, who is asked
to review it. A release that fixes a vulnerability exploited in the wild is
titled and labelled as such, and the maintainer is mentioned.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

from chromium_fork import ENGINE, REPO, read_json, run
import chromium_engine

sys.path.insert(0, str(REPO / "Scripts"))
import release_note_catalog  # noqa: E402

UPDATE_BRANCH = "codex/chromium-upstream-"
PREFLIGHT_BRANCH = "codex/chromium-preflight-"
EXPLOITED_LABEL = "exploited-in-the-wild"
BLOCKING = ("rebased", "upstream", "conflict", "missing")


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


def carry_plan(report, early=False):
    """Put a plan's carried-over patches in the checkout, returning the plan and the paths they may change.

    The patches are as the plan left them: rebased sections merged, sections
    upstream already has dropped, and conflicting ones as they were, for a
    session to resolve. The pinned release stays, so the session's `plan` and
    `update` start from it.
    """
    plan = read_json(report / "plan.json")
    if not plan["blocked"] and not early:
        raise ValueError(f"The plan for {plan['version']} isn't blocked; build it as an update")
    patches, paths, retired = REPO / ENGINE / "Patches", set(), set()
    for patch in sorted((report / "Patches").iterdir()):
        if chromium_engine.patch_sections(patch.read_text()):
            shutil.copyfile(patch, patches / patch.name)
        else:
            # Upstream has every section of this patch, so it leaves the series.
            (patches / patch.name).unlink(missing_ok=True)
            retired.add(patch.name)
        paths.add(str(ENGINE / "Patches" / patch.name))
    if retired:
        series = patches / "series"
        series.write_text("".join(line for line in series.read_text().splitlines(keepends=True)
                                  if line.split("#", 1)[0].strip() not in retired))
        paths.add(str(ENGINE / "Patches/series"))
    return plan, paths


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base-sha", required=True)
    parser.add_argument("--repository", required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--receipt", type=Path, help="The build's last-build.json, for a built update")
    mode.add_argument("--rebase", type=Path, metavar="REPORT", help="A blocked plan's report for a full stable release")
    mode.add_argument("--preflight", type=Path, metavar="REPORT", help="A plan's report for an early stable release")
    parser.add_argument("--candidate", help="The draft release holding the built engine")
    parser.add_argument("--reviewer", help="The maintainer each draft is assigned to")
    parser.add_argument("--exploited", action="store_true",
                        help="Upstream reports a fix for a vulnerability exploited in the wild")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-f0-9]{40}", args.base_sha):
        parser.error("Expected an immutable base commit")
    if args.reviewer and not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})", args.reviewer):
        parser.error("Expected a GitHub login for the reviewer")
    base = read_json(REPO / ENGINE / "fork.json")["integrationBranch"]
    if run("git", "rev-parse", "HEAD", capture=True).strip() != args.base_sha:
        parser.error("The update checkout moved since preparation")
    if run("git", "ls-files", "--others", "--exclude-standard", capture=True).strip():
        parser.error("Unexpected untracked files in the update checkout")

    if args.receipt:
        version = read_json(REPO / ENGINE / "source.lock.json")["chromium"]["version"]
        try:
            plan = update_plan(read_json(args.receipt), version=version, base_sha=args.base_sha,
                               engine_key=chromium_engine.engine_key(REPO))
        except ValueError as error:
            parser.error(str(error))
        paths = {str(ENGINE / "source.lock.json"), str(ENGINE / "host-inputs.json")}
        branch, receipt = f"{UPDATE_BRANCH}{version}-{args.base_sha[:12]}", read_json(args.receipt)
    else:
        if run("git", "status", "--porcelain", capture=True).strip():
            parser.error("Start from a clean update checkout")
        plan, paths = carry_plan(args.rebase or args.preflight, early=bool(args.preflight))
        version, receipt = plan["version"], None
        prefix = UPDATE_BRANCH if args.rebase else PREFLIGHT_BRANCH
        branch = f"{prefix}{version}-{args.base_sha[:12]}"
    changed = set(run("git", "diff", "--name-only", capture=True).splitlines())
    # A plan stopped only by a helper app or a build patch carries no patch change.
    if not changed <= paths or (args.receipt and not changed):
        parser.error("Upstream preparation changed unexpected files, or produced no update")

    run("git", "switch", "-c", branch)
    run("git", "config", "user.name", "github-actions[bot]")
    run("git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com")
    staged = sorted(changed)
    if args.receipt:
        # A built update reaches people, so it says what changed in its own fragment.
        slug = f"chromium-upstream-{version.replace('.', '-')}-{args.base_sha[:12]}"
        note = {"id": slug, "category": "fixed",
                "message": f"Chromium is updated to {version} with upstream security and compatibility fixes.",
                "platforms": ["mac"]}
        notes_path = release_note_catalog.write_fragment(REPO, slug, [note])
        staged.append(str(notes_path.relative_to(REPO)))
    if staged:
        run("git", "add", *staged)
    if args.receipt:
        subject = f"Update Chromium to {version}"
    elif args.rebase:
        subject = f"Rebase Crest's patches for Chromium {version}"
    else:
        subject = f"Check Crest's patches against Chromium {version}"
    run("git", "commit", "-s", "--allow-empty", "-m", subject)
    if args.receipt:
        # The checks the pull request will face.
        run(sys.executable, REPO / "Scripts/release_note_catalog.py", "--repository-root", REPO,
            "--pull-request", args.base_sha)
    # The branch is named for the release and its base. An earlier run that
    # pushed it but didn't open its PR left it there, so reuse it as it is.
    if run("git", "ls-remote", "--heads", "origin", f"refs/heads/{branch}", capture=True).strip():
        print(f"{branch} was pushed by an earlier run; opening its pull request from it.")
    else:
        run("git", "push", "origin", f"HEAD:refs/heads/{branch}")

    if args.receipt:
        body = review_body(version, plan, receipt, chromium_engine.release_tag(chromium_engine.engine_key(REPO)),
                           args.candidate)
    else:
        body = blocked_body(version, plan, early=bool(args.preflight))
    # The plan read the release's notes; the flag lets a caller say so regardless.
    exploited = args.exploited or bool(plan.get("releaseNotes", {}).get("exploited"))
    title = f"Exploited in the wild: {subject}" if exploited else subject
    existing = json.loads(run("gh", "pr", "list", "--repo", args.repository, "--head", branch,
                              "--base", base, "--state", "open", "--json", "url", capture=True))
    url = existing[0]["url"] if existing else run("gh", "pr", "create", "--repo", args.repository, "--draft",
        "--base", base, "--head", branch, "--title", title, "--body", body, capture=True).strip()
    print(url)
    notify(args.repository, url, args.reviewer, exploited, version)
    if not args.preflight:
        close_preflights(args.repository, base, version, url)
    if output := os.environ.get("GITHUB_OUTPUT"):
        with Path(output).open("a") as stream:
            stream.write(f"pull_request={url}\n")


def notify(repository, url, reviewer, exploited, version):
    """Assign the draft to the maintainer and ask for their review.

    A fix for a vulnerability exploited in the wild is labelled and mentions
    them too.

    The draft is open by now, so a failure here is reported in the run rather
    than raised.
    """
    number = url.rstrip("/").rsplit("/", 1)[1]

    def attempt(*arguments):
        try:
            run("gh", "api", "--silent", *arguments)
        except subprocess.CalledProcessError as error:
            print(f"::warning title=Chromium::{arguments[2]} failed for {url}: exit {error.returncode}")

    if exploited:
        try:
            run("gh", "api", "--silent", f"repos/{repository}/labels/{EXPLOITED_LABEL}")
        except subprocess.CalledProcessError:
            attempt("-X", "POST", f"repos/{repository}/labels", "-f", f"name={EXPLOITED_LABEL}", "-f", "color=B60205",
                    "-f", "description=Upstream fixes a vulnerability exploited in the wild")
        attempt("-X", "POST", f"repos/{repository}/issues/{number}/labels", "-f", f"labels[]={EXPLOITED_LABEL}")
    if not reviewer:
        print("::notice title=Chromium::No reviewer is configured; set CHROMIUM_UPDATE_REVIEWER to be told of drafts.")
        return
    attempt("-X", "POST", f"repos/{repository}/issues/{number}/assignees", "-f", f"assignees[]={reviewer}")
    attempt("-X", "POST", f"repos/{repository}/pulls/{number}/requested_reviewers", "-f", f"reviewers[]={reviewer}")
    if exploited:
        attempt("-X", "POST", f"repos/{repository}/issues/{number}/comments", "-f",
                f"body=@{reviewer} Upstream reports that Chromium {version} fixes a vulnerability exploited in the "
                "wild. Test, publish and ship it the same day.")


def close_preflights(repository, base, version, url):
    """Close the early stable checks of `version`'s milestone, which this draft takes over."""
    milestone = version.split(".", 1)[0] + "."
    open_checks = json.loads(run("gh", "pr", "list", "--repo", repository, "--base", base, "--state", "open",
                                 "--limit", "100", "--json", "headRefName,url", capture=True))
    for check in open_checks:
        if check["headRefName"].startswith(f"{PREFLIGHT_BRANCH}{milestone}"):
            try:
                run("gh", "pr", "close", check["url"], "--repo", repository, "--delete-branch",
                    "--comment", f"Chromium {version} is full stable; {url} takes this over.")
            except subprocess.CalledProcessError as error:
                # The new draft is open already; an early check left open is only clutter.
                print(f"::warning title=Chromium::Could not close {check['url']}: exit {error.returncode}")


def security_summary(notes):
    """What Google's release note says the release fixes."""
    if "error" in notes:
        return notes["error"] + "."
    covered = "" if notes["exact"] else f" (the note for {notes['notedVersion']}, the latest release it covers)"
    return (f"Upstream's release note{covered}: {notes['securityFixes']} security fixes, "
            f"{notes['critical']} Critical and {notes['high']} High"
            f"{', one of them exploited in the wild' if notes['exploited'] else ''}"
            f"{'. This is an early stable release, which reaches a small share of people first' if notes['earlyStable'] else ''}.")


def requests(plan):
    """The network requests the release adds or removes, for the request review."""
    annotations = plan.get("annotations", {})
    lines = [f"- Added `{name}`" for name in annotations.get("added", [])]
    lines += [f"- Removed `{name}`" for name in annotations.get("removed", [])]
    if not lines:
        return ""
    return ("Network traffic annotations to review in `crest_request_policy.cc` (ForkMaintenance.md, "
            "\"Browser requests to Google\"):\n\n" + "\n".join(lines) + "\n\n")


def review_body(version, plan, receipt, tag, candidate=None):
    """The draft's description: what upstream fixed, how the update went, and what is left before it ships."""
    minutes = {step: round(seconds / 60) for step, seconds in receipt.get("secondsPerStep", {}).items()}
    if candidate:
        waiting = (f"Engine `{tag}` is built and **not published**. It waits in the draft release `{candidate}`, "
                   "which release packaging never reads.")
    else:
        waiting = f"Engine `{tag}` is built on the build Mac and **not published**."
    return (f"Updates Chromium from {plan['current']} to {version}"
            f"{', a new milestone' if plan['milestone'] else ''}.\n\n{security_summary(plan.get('releaseNotes', {}))}\n\n"
            f"The build {'advanced the pinned source in place' if plan['path'] == 'advance' else 'prepared a new source'}"
            f"{' and recompiled everything for the new PGO profile' if plan['pgoChanged'] else ''}. "
            f"Every Crest patch applied without fuzz, and the engine passed its headless smoke check. "
            f"Minutes per step: {json.dumps(minutes)}.\n\n{requests(plan)}"
            f"{waiting} Before this leaves draft:\n\n"
            "1. Package Crest with `package-chromium-host.py --product --distribution` from the built engine and "
            "load real pages, extensions and sign-ins in an isolated copy.\n"
            "2. A maintainer publishes the engine with `publish-chromium-engine.py`.\n"
            "3. Merging then publishes it to Development.\n")


def blocked_body(version, plan, early):
    """The description of a release whose patches need a session before anything is built."""
    patches = "".join(f"- {status.capitalize()}: {item}\n" for status in BLOCKING for item in plan["patches"][status])
    if not plan["blocked"]:
        return (f"Checks Crest's patches against Chromium {version}, from {plan['current']}"
                f"{', a new milestone' if plan['milestone'] else ''}. This is an early stable release, which reaches "
                "a small share of people about a week before everyone.\n\n"
                f"{security_summary(plan.get('releaseNotes', {}))}\n\n"
                "Every Crest patch and build adjustment applies to it, so its update builds and opens as a draft "
                "once it reaches full stable, which closes this one.\n\n" + requests(plan))
    build = "".join(f"- Build patch fails: {name}\n"
                    for name, result in plan["buildPatches"].items() if result == "fails")
    helpers = "".join(f"- Unknown helper app: {name}\n" for name in plan["unknownHelpers"])
    interfaces = "".join(f"- `{header}` changes pure virtual methods\n" for header in plan["interfaceChanges"])
    major = "--allow-major " if plan["milestone"] else ""
    stage = ("This is an early stable release, which reaches a small share of people about a week before everyone. "
             "Nothing is built until it reaches full stable." if early else
             "This release is full stable, so Crest is behind it until a session finishes this.")
    return (f"Checks Crest's patches against Chromium {version}, from {plan['current']}"
            f"{', a new milestone' if plan['milestone'] else ''}. {stage}\n\n"
            f"{security_summary(plan.get('releaseNotes', {}))}\n\n"
            "This branch keeps the pinned release and has Crest's patches as the plan carried them over. "
            "These stop the build:\n\n" + patches + build + helpers + "\n" +
            ("Upstream headers the overlay includes that change their interface:\n\n" + interfaces + "\n"
             if interfaces else "") + requests(plan) +
            f"To finish it in a session, from this branch: run `chromium-fork.py plan {major}--version {version}`, "
            "resolve each conflict in the report's `conflicts`, and commit the patches. Plan again until nothing "
            f"stops it, then run `chromium-fork.py update {major}--version {version} --sdk <macOS SDK>` from the "
            "clean checkout: it "
            "pins the release, refreshes the host hashes and builds the engine. Add a release-note fragment under "
            "`Documentation/ReleaseNotes/changes/` before review; the version comes from git.\n")


if __name__ == "__main__":
    main()
