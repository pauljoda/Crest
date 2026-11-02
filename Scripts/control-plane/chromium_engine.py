#!/usr/bin/env python3
"""Identify the prebuilt Chromium engine a Crest source tree needs.

The engine — Chromium with Crest's host patch and overlay compiled in — takes
hours to build and cannot be built on a hosted runner, so releases download a
prebuilt engine published once per engine revision. Its key hashes every input
that is compiled into the engine: the pinned source lock, the host patch and
its reviewed input hashes, the overlay sources, the host header and the
engine contract headers copied into the tree, and the scripts that prepare,
configure and build it. Anything else
— the Swift UI framework, the native core, packaging — is built per release.
"""
import argparse
import hashlib
from pathlib import Path
import re

INPUTS = (
    "CrestEngines/Chromium/source.lock.json",
    "CrestEngines/Chromium/host-inputs.json",
    "CrestEngines/Chromium/Patches",
    "CrestEngines/Chromium/Overlay",
    "CrestEngines/Chromium/Apple/CrestChromiumHost.h",
    "CrestContracts/include/crest_core.h",
    "CrestContracts/include/crest_app.h",
    "CrestContracts/include/crest_engine.h",
    "CrestContracts/include/crest_engine_contract.h",
    "Scripts/control-plane/prepare-chromium.py",
    "Scripts/control-plane/apply-chromium-host.py",
    "Scripts/control-plane/configure-chromium.py",
    "Scripts/control-plane/build-chromium-baseline.py",
)


def engine_key(repo: Path) -> str:
    digest = hashlib.sha256()
    for name in INPUTS:
        path = repo / name
        files = sorted(p for p in path.rglob("*") if p.is_file()) if path.is_dir() else [path]
        if not files or not all(p.is_file() for p in files):
            raise SystemExit(f"Missing engine input: {name}")
        for file in files:
            relative = file.relative_to(repo).as_posix()
            digest.update(relative.encode() + b"\0")
            digest.update(hashlib.sha256(file.read_bytes()).hexdigest().encode() + b"\n")
    return digest.hexdigest()


SECTION = re.compile(r"^--- a/(\S+)\n\+\+\+ b/(\S+)\n", re.MULTILINE)


def patch_sections(text: str) -> list[tuple[str, str]]:
    """Each file a unified diff changes, as (path, that file's diff), in order."""
    starts = list(SECTION.finditer(text))
    sections = []
    for index, start in enumerate(starts):
        if start[1] != start[2]:
            raise ValueError(f"A host patch section renames {start[1]}")
        end = starts[index + 1].start() if index + 1 < len(starts) else len(text)
        sections.append((start[1], text[start.start():end]))
    return sections


def host_patch(repo: Path) -> str:
    """The host patches in `Patches/series`, as one diff in the order they apply.

    A file may appear in more than one patch; a later section applies to the
    earlier ones' result, so reversing the host reverses the sections' order.
    """
    patches = repo / "CrestEngines/Chromium/Patches"
    combined = []
    for line in (patches / "series").read_text().splitlines():
        name = line.split("#", 1)[0].strip()
        if not name:
            continue
        sections = patch_sections((patches / name).read_text())
        files = [path for path, _ in sections]
        if not sections or len(set(files)) != len(files):
            raise ValueError(f"{name} must change each of its files exactly once")
        combined += [section for _, section in sections]
    return "".join(combined)


def reversed_patch(text: str) -> str:
    """`text` with its sections in reverse order, for `patch -R`."""
    return "".join(section for _, section in reversed(patch_sections(text)))


def release_tag(key: str) -> str:
    return f"chromium-engine-{key[:16]}"


def asset_name(key: str) -> str:
    return f"Crest-Chromium-Engine-{key[:16]}-arm64.zip"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("field", choices=["key", "tag", "asset"])
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    key = engine_key(args.repo.resolve())
    print({"key": key, "tag": release_tag(key), "asset": asset_name(key)}[args.field])


if __name__ == "__main__":
    main()
