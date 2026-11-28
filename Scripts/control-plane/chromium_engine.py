#!/usr/bin/env python3
"""Identify the prebuilt Chromium engine a Crest source tree needs.

The engine — Chromium with Crest's host patch and overlay compiled in — takes
hours to build and cannot be built on a hosted runner, so releases download a
prebuilt engine published once per engine revision and host. Its key hashes
every input that is compiled into the engine: the pinned source lock, the host
patch and its reviewed input hashes, the overlay sources, the engine contract
headers copied into the tree, the scripts that prepare, configure and build it,
and the host's own inputs, such as the Mac's host header or the Windows host
profile and the layers it names. Anything else — the Swift UI framework, the desktop interface, the
native core, packaging — is built per release.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

# Every helper app an engine may contain, by what follows "Chromium Helper" in
# its name, and whether V8 in it maps executable memory and so needs the JIT
# entitlement (chrome/installer/mac/signing/parts.py). A helper kind missing here
# stops packaging and publishing: a new kind needs a decision about its
# entitlements, and getting that wrong crashes every page in a signed build while
# passing everything that runs unsigned.
ENGINE_HELPER_NAME = "Chromium Helper"
ENGINE_HELPER_KINDS = {
    "": False,
    " (Renderer)": True,
    " (GPU)": True,
    " (Alerts)": False,
    " (Aperitif)": False,
    " (Aperitif Renderer)": True,
    " (Aperitif GPU)": True,
    " (Aperitif Alerts)": False,
}

MAC = "mac-arm64"
ENGINE = "CrestEngines/Chromium"
LAYERS = f"{ENGINE}/Layers"
REPO = Path(__file__).resolve().parents[2]

# Every engine's inputs: the source, Crest's shared patches and overlay, the
# contracts the binding compiles against, and the scripts that prepare,
# configure and build it. Each host adds the inputs only its engine compiles,
# its own files and the layers its profile names, so changing one host's
# leaves every other host's published engine valid.
COMMON_INPUTS = (
    "CrestEngines/Chromium/source.lock.json",
    "CrestEngines/Chromium/host-inputs.json",
    "CrestEngines/Chromium/Patches",
    "CrestEngines/Chromium/Overlay",
    "CrestContracts/include/crest_core.h",
    "CrestContracts/include/crest_app.h",
    "CrestContracts/include/crest_engine.h",
    "CrestContracts/include/crest_engine_contract.h",
    "CrestCore/native/ContentFilter/include/crest_content_filter.h",
    "Scripts/control-plane/prepare-chromium.py",
    "Scripts/control-plane/apply-chromium-host.py",
    "Scripts/control-plane/configure-chromium.py",
    "Scripts/control-plane/build-chromium-baseline.py",
    "Scripts/control-plane/chromium_host.py",
)
HOST_INPUTS = {
    MAC: ("CrestEngines/Chromium/Apple/CrestChromiumHost.h",),
    "win-x64": ("CrestEngines/Chromium/Hosts/win-x64.json",),
}


def host_layers(host: str = MAC, repo: Path = REPO) -> list[str]:
    """The layers `host` adds to the shared engine, in the order they apply.

    A layer, `Layers/<name>`, holds what only some hosts compile, as the
    shared engine directory does for every host: patches listed in its
    `Patches/series`, overlay sources under `Overlay`, and the reviewed
    hashes of the files its patches change in `host-inputs.json`, each
    taken as the layers before it left the file. The desktop shell's
    sources are a layer Windows and Linux share; Windows' branding is
    Windows' own. The Mac adds none.
    """
    if host == MAC:
        return []
    profile = repo / ENGINE / "Hosts" / f"{host}.json"
    if not profile.is_file():
        raise SystemExit(f"No host profile at {profile.relative_to(repo)}")
    return list(json.loads(profile.read_text(encoding="utf-8")).get("layers", []))


def layer_roots(host: str = MAC, repo: Path = REPO) -> list[Path]:
    """The shared engine directory, then each of `host`'s layers, in the order they apply."""
    return [repo / ENGINE, *(repo / LAYERS / name for name in host_layers(host, repo))]


def inputs(host: str = MAC, repo: Path = REPO) -> tuple:
    """Everything compiled into `host`'s engine. The Mac keeps the order it
    had before hosts, its host header among the common inputs."""
    if host not in HOST_INPUTS:
        raise SystemExit(f"No engine inputs for host {host}")
    if host == MAC:
        return (*COMMON_INPUTS[:4], *HOST_INPUTS[MAC], *COMMON_INPUTS[4:])
    return (*COMMON_INPUTS, *HOST_INPUTS[host], *(f"{LAYERS}/{name}" for name in host_layers(host, repo)))


# The Mac engine's inputs, which callers that predate hosts read.
INPUTS = inputs(MAC)


def unknown_engine_helpers(helpers) -> list:
    """The names among `helpers`, paths to helper apps, that are no known kind."""
    return sorted(path.name for path in helpers if path.stem.startswith(ENGINE_HELPER_NAME)
                  and path.stem.removeprefix(ENGINE_HELPER_NAME) not in ENGINE_HELPER_KINDS)


def engine_key(repo: Path, host: str = MAC) -> str:
    digest = hashlib.sha256()
    for name in inputs(host, repo):
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


def layer_patch(root: Path) -> str:
    """One layer's patches, those its `Patches/series` lists, as one diff in order."""
    patches = root / "Patches"
    combined = []
    for line in (patches / "series").read_text(encoding="utf-8").splitlines():
        name = line.split("#", 1)[0].strip()
        if not name:
            continue
        sections = patch_sections((patches / name).read_text(encoding="utf-8"))
        files = [path for path, _ in sections]
        if not sections or len(set(files)) != len(files):
            raise ValueError(f"{name} must change each of its files exactly once")
        combined += [section for _, section in sections]
    return "".join(combined)


def host_patch(repo: Path, host: str = MAC) -> str:
    """`host`'s patches, the shared series and then each of its layers', as one diff in the order they apply.

    A file may appear in more than one patch; a later section applies to the
    earlier ones' result, so reversing the host reverses the sections' order.
    """
    return "".join(layer_patch(root) for root in layer_roots(host, repo))


def host_inputs(repo: Path, host: str = MAC) -> dict:
    """The reviewed hashes of every file `host`'s patches change: as the
    pinned source holds it, and as the last of its layers leaves it.

    Each layer records a file as the layers before it left it, so a layer
    whose starting point is not where the one before ends means one of them
    was reviewed against other bytes.
    """
    merged = {}
    for root in layer_roots(host, repo):
        recorded = root / "host-inputs.json"
        layer = json.loads(recorded.read_text(encoding="utf-8"))
        changed = {path for path, _ in patch_sections(layer_patch(root))}
        if set(layer) != changed:
            raise ValueError(f"{recorded.relative_to(repo)} does not cover exactly the files its layer's patches change")
        for name, states in layer.items():
            if name not in merged:
                merged[name] = dict(states)
            elif merged[name]["after"] != states["before"]:
                raise ValueError(f"{root.name} starts {name} from other bytes than the layers before it leave")
            else:
                merged[name] = {"before": merged[name]["before"], "after": states["after"]}
    return merged


def reversed_patch(text: str) -> str:
    """`text` with its sections in reverse order, for `patch -R`."""
    return "".join(section for _, section in reversed(patch_sections(text)))


def release_tag(key: str, host: str = MAC) -> str:
    """The Mac engine keeps the tag it had before hosts."""
    return f"chromium-engine-{key[:16]}" if host == MAC else f"chromium-engine-{host}-{key[:16]}"


def candidate_tag(key: str) -> str:
    """The draft release a built but unpublished engine waits in. Release
    packaging asks only for `release_tag`, so it never reads one."""
    return f"chromium-engine-candidate-{key[:16]}"


def asset_name(key: str, host: str = MAC) -> str:
    """The Mac's universal engine, or another host's own."""
    return f"Crest-Chromium-Engine-{key[:16]}-universal.zip" if host == MAC else f"Crest-Chromium-Engine-{key[:16]}-{host}.zip"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("field", choices=["key", "tag", "asset"])
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--host", default=MAC, choices=sorted(HOST_INPUTS), help="The engine's host (default: the Mac)")
    args = parser.parse_args()
    key = engine_key(args.repo.resolve(), args.host)
    print({"key": key, "tag": release_tag(key, args.host), "asset": asset_name(key, args.host)}[args.field])


if __name__ == "__main__":
    main()
