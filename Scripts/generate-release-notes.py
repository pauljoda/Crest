#!/usr/bin/env python3
"""Generate user-facing release notes directly from Crest's commit history."""

from __future__ import annotations

import argparse
import pathlib
import subprocess
import urllib.parse


CHANNEL_HEADINGS = {
    "stable": "# Crest stable release",
    "nightly": "# Crest nightly build",
    "development": "# Crest development build",
}

CHANNEL_DESCRIPTIONS = {
    "stable": "This release is signed and notarized for direct distribution.",
    "nightly": (
        "Nightly builds are signed and notarized, but contain changes that have "
        "not yet reached a stable release."
    ),
    "development": (
        "Development builds are signed and notarized, but may be less reliable "
        "than stable releases."
    ),
}


def git(repository_root: pathlib.Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repository_root), *arguments],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def commit_range(
    repository_root: pathlib.Path,
    current_ref: str,
    previous_ref: str | None,
) -> tuple[str, list[str]]:
    current_commit = git(repository_root, "rev-parse", f"{current_ref}^{{commit}}")
    if previous_ref is None:
        return current_commit, [current_commit]

    previous_commit = git(repository_root, "rev-parse", f"{previous_ref}^{{commit}}")
    subprocess.run(
        [
            "git",
            "-C",
            str(repository_root),
            "merge-base",
            "--is-ancestor",
            previous_commit,
            current_commit,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    commits = git(
        repository_root,
        "rev-list",
        "--reverse",
        f"{previous_commit}..{current_commit}",
    ).splitlines()
    return current_commit, commits


def release_notes(
    repository_root: pathlib.Path,
    repository: str,
    server_url: str,
    channel: str,
    release_tag: str,
    current_ref: str,
    previous_ref: str | None,
    asset_name: str,
) -> str:
    current_commit, commits = commit_range(repository_root, current_ref, previous_ref)
    repository_url = f"{server_url.rstrip('/')}/{repository}"
    download_url = (
        f"{repository_url}/releases/download/"
        f"{urllib.parse.quote(release_tag, safe='.-_')}/"
        f"{urllib.parse.quote(asset_name, safe='.-_')}"
    )
    short_commit = current_commit[:7]

    lines = [
        CHANNEL_HEADINGS[channel],
        "",
        f"[Download Crest for Mac (Apple silicon)]({download_url})",
        "",
        (
            f"Built from [`{short_commit}`]"
            f"({repository_url}/commit/{current_commit})."
        ),
        "",
        CHANNEL_DESCRIPTIONS[channel],
        "",
        (
            f"## Changes since the previous {channel} build"
            if previous_ref is not None
            else "## Changes in this build"
        ),
        "",
    ]

    if not commits:
        lines.extend(["No new commits are included in this build.", ""])

    for commit in commits:
        subject = git(repository_root, "show", "-s", "--format=%s", commit)
        body = git(repository_root, "show", "-s", "--format=%b", commit)
        lines.extend([f"### {subject}", ""])
        if body:
            lines.extend([body, ""])
        lines.extend(
            [
                f"[View commit `{commit[:7]}`]({repository_url}/commit/{commit})",
                "",
            ]
        )

    return "\n".join(lines).rstrip() + "\n"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--repository", required=True)
    parser.add_argument("--server-url", default="https://github.com")
    parser.add_argument("--channel", choices=CHANNEL_HEADINGS, required=True)
    parser.add_argument("--release-tag")
    parser.add_argument("--current-ref", required=True)
    parser.add_argument("--previous-ref")
    parser.add_argument("--asset-name", required=True)
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    print(
        release_notes(
            repository_root=arguments.repository_root,
            repository=arguments.repository,
            server_url=arguments.server_url,
            channel=arguments.channel,
            release_tag=arguments.release_tag or arguments.channel,
            current_ref=arguments.current_ref,
            previous_ref=arguments.previous_ref,
            asset_name=arguments.asset_name,
        ),
        end="",
    )


if __name__ == "__main__":
    main()
