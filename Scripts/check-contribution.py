#!/usr/bin/env python3
"""Check a pull request's AI usage declaration, its commit sign-offs, and that it
leaves the shared release files alone."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys


POLICY_START = datetime(2026, 10, 9, tzinfo=timezone.utc)
AI_USED_MARKER = "AI tools helped produce this change"
SKILL_MARKER = "crest-contribution"
SIGN_OFF_LINE = re.compile(r"^Signed-off-by:\s+\S.*<[^<>\s]+@[^<>\s]+>\s*$")
CHECKBOX_LINE = re.compile(r"^\s*[-*]\s*\[([ xX])\]\s*(.*)$")
VERSION_PATH = "Config/Version.xcconfig"
CATALOG_PATH = "Documentation/ReleaseNotes.json"
ENTRY_DIRECTORY = "Documentation/ReleaseNotes/"
MARKETING_VERSION = re.compile(r"^[ \t]*MARKETING_VERSION[ \t]*=[ \t]*(\d+)\.(\d+)\.(\d+)[ \t]*$", re.MULTILINE)


def opened_before_policy(created_at: str) -> bool:
    opened = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
    return opened < POLICY_START


def checkbox_states(body: str) -> dict[str, bool]:
    states: dict[str, bool] = {}
    for line in body.splitlines():
        match = CHECKBOX_LINE.match(line)
        if match is None:
            continue
        checked = match.group(1) != " "
        label = match.group(2)
        for marker in (AI_USED_MARKER, SKILL_MARKER):
            if marker.lower() in label.lower() and marker not in states:
                states[marker] = checked
    return states


def ai_declaration_problems(body: str) -> list[str]:
    states = checkbox_states(body)
    if AI_USED_MARKER not in states or SKILL_MARKER not in states:
        return [
            "The description is missing the AI usage section from the pull request "
            "template. Restore both checkboxes, then tick the ones that apply."
        ]
    if states[AI_USED_MARKER] and not states[SKILL_MARKER]:
        return [
            "AI tools helped produce this change, so the crest-contribution skill "
            "must be run and its box ticked. See "
            ".agents/skills/crest-contribution/SKILL.md."
        ]
    return []


def exempt_from_sign_off(pull_request_author: str, exempt_logins: set[str]) -> bool:
    """The authenticated account that opened the pull request decides the exemption.

    A commit's recorded author or committer is free text, so it cannot be trusted
    to identify the repository owner or a bot.
    """
    return pull_request_author.endswith("[bot]") or pull_request_author in exempt_logins


def sign_off_problems(commits: list[dict]) -> list[str]:
    problems: list[str] = []
    for commit in commits:
        if len(commit.get("parents", [])) > 1:
            continue
        message = commit.get("commit", {}).get("message", "")
        if not any(SIGN_OFF_LINE.match(line.strip()) for line in message.splitlines()):
            sha = commit.get("sha", "")[:12]
            subject = message.splitlines()[0] if message else ""
            problems.append(
                f"{sha} {subject}: no Signed-off-by trailer. Commit with git commit -s "
                "as described in CONTRIBUTING.md."
            )
    return problems


def release_line(contents: str | None) -> tuple[int, int] | None:
    """The X.Y release line a version file names, or None."""
    match = MARKETING_VERSION.search(contents or "")
    return (int(match.group(1)), int(match.group(2))) if match else None


def release_file_problems(
    changes: list[tuple[str, str]],
    base_version: str | None,
    head_version: str | None,
) -> list[str]:
    """Why a pull request's changes to the shared release files are refused.

    The patch version is derived from history, so a change that edits
    Config/Version.xcconfig without starting a later release line would
    repeat a published version. The catalog document is frozen, and a merged
    entry file is never rewritten or removed."""
    problems = []
    for status, path in changes:
        if path == VERSION_PATH:
            base_line, head_line = release_line(base_version), release_line(head_version)
            if base_line is None or head_line is None or head_line <= base_line:
                problems.append(
                    f"{VERSION_PATH} only changes to start a later release line with "
                    "Scripts/set-version.sh --release; patch versions are derived from history")
        elif path == CATALOG_PATH:
            problems.append(f"{CATALOG_PATH} is frozen; add the entry as {ENTRY_DIRECTORY}<id>.json")
        elif path.startswith(ENTRY_DIRECTORY) and status != "A":
            problems.append(f"a merged release-note entry file is never changed or removed: {path}")
    return problems


def git_lines(*arguments: str) -> str:
    return subprocess.run(["git", *arguments], check=True, capture_output=True, text=True).stdout


def file_at(reference: str, path: str) -> str | None:
    result = subprocess.run(["git", "show", f"{reference}:{path}"], check=False, capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else None


def load_commits(path: Path) -> list[dict]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    commits: list[dict] = []
    for item in payload if isinstance(payload, list) else [payload]:
        if isinstance(item, list):
            commits.extend(item)
        else:
            commits.append(item)
    return commits


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("check", choices=("ai-declaration", "sign-off", "release-files"))
    parser.add_argument("--event", required=True, type=Path, help="GitHub event payload")
    parser.add_argument("--commits", type=Path, help="pull request commits JSON")
    parser.add_argument(
        "--exempt-login",
        action="append",
        default=[],
        help="GitHub login whose pull requests need no sign-off, such as the repository owner",
    )
    arguments = parser.parse_args()

    event = json.loads(arguments.event.read_text(encoding="utf-8"))
    pull_request = event["pull_request"]
    if opened_before_policy(pull_request["created_at"]):
        print("Pull request predates the contribution checks; nothing to verify.")
        return 0

    if arguments.check == "ai-declaration":
        problems = ai_declaration_problems(pull_request.get("body") or "")
    elif arguments.check == "release-files":
        base = pull_request["base"]["sha"]
        changes = [
            tuple(line.split("\t", 1))
            for line in git_lines("diff", "--name-status", "--no-renames", base, "HEAD").splitlines()
            if line.strip()
        ]
        problems = release_file_problems(changes, file_at(base, VERSION_PATH), file_at("HEAD", VERSION_PATH))
    else:
        if arguments.commits is None:
            parser.error("--commits is required for the sign-off check")
        author = (pull_request.get("user") or {}).get("login") or ""
        if exempt_from_sign_off(author, set(arguments.exempt_login)):
            print(f"Pull request opened by {author}; no sign-off required.")
            return 0
        problems = sign_off_problems(load_commits(arguments.commits))

    for problem in problems:
        print(f"error: {problem}", file=sys.stderr)
    if problems:
        return 1
    print(f"Validated the pull request {arguments.check.replace('-', ' ')}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
