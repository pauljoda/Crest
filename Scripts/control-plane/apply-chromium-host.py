#!/usr/bin/env python3
"""Validate or install Crest's native host overlay into its pinned external Chromium tree.

The host installs the shared patches and overlay, then each layer its
profile names, in order. `--record-layers` writes each of those layers'
reviewed hashes from a freshly prepared tree, as a Chromium update needs.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import chromium_engine  # noqa: E402
import chromium_host  # noqa: E402

# The engine contract's headers in CrestContracts/include that the binding
# compiles against. chromium_engine.py keys the published engine on them.
ENGINE_CONTRACT = ("crest_core.h", "crest_app.h", "crest_engine.h", "crest_engine_contract.h")
# The content filter's C interface, which the binding's request filter calls.
CONTENT_FILTER_HEADER = "CrestCore/native/ContentFilter/include/crest_content_filter.h"


def record_layers(parser, repo: Path, source: Path, host_name: str):
    """Writes the reviewed hashes of each of `host_name`'s layers from a
    tree no host is installed in: each file as the shared patches and the
    layers before leave it, and as the layer leaves it. The shared
    patches' own hashes, which the Mac's fork maintenance refreshes, must
    already describe the tree."""
    roots = chromium_engine.layer_roots(host_name, repo)
    shared = json.loads((roots[0] / "host-inputs.json").read_text(encoding="utf-8"))
    layers = [(root, chromium_engine.patch_sections(chromium_engine.layer_patch(root))) for root in roots]
    names = {name for _, sections in layers for name, _ in sections}
    with tempfile.TemporaryDirectory(prefix="crest-layers-") as temporary:
        scratch = Path(temporary)
        for name in names:
            if not (source / name).is_file():
                parser.error(f"Missing pinned Chromium input: {name}")
            (scratch / name).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / name, scratch / name)
        for name, hashes in shared.items():
            if hashlib.sha256((scratch / name).read_bytes()).hexdigest() != hashes["before"]:
                parser.error(f"Record layers in a tree no host is installed in; {name} is not the pinned source's")
        for index, (root, sections) in enumerate(layers):
            changed = list(dict.fromkeys(name for name, _ in sections))
            recorded = {name: {"before": hashlib.sha256((scratch / name).read_bytes()).hexdigest()} for name in changed}
            subprocess.run([chromium_host.patch_tool(), "--batch", "--fuzz=0", "--forward", "-p1", "-s"],
                           input="".join(section for _, section in sections).encode("utf-8"), cwd=scratch, check=True)
            for name in changed:
                recorded[name]["after"] = hashlib.sha256((scratch / name).read_bytes()).hexdigest()
            if index == 0:
                if recorded != shared:
                    parser.error("The shared patches no longer produce host-inputs.json; refresh them first")
                continue
            (root / "host-inputs.json").write_text(json.dumps(recorded, indent=2, sort_keys=True) + "\n",
                                                  encoding="utf-8", newline="\n")
            print(f"Recorded {len(recorded)} inputs for the {root.name} layer.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--apply", action="store_true", help="Install after validation; default is read-only")
    parser.add_argument("--host", help="The host profile to install (default: this machine's)")
    parser.add_argument("--record-layers", action="store_true",
                        help="Write the host's layers' reviewed hashes from a tree no host is installed in")
    args = parser.parse_args()
    source = args.source.resolve()
    repo = Path(__file__).resolve().parents[2]
    host = repo / "CrestEngines/Chromium"
    host_name = args.host or chromium_host.detected()
    if source == repo or repo in source.parents:
        parser.error("Use the external, pinned Chromium checkout")
    if args.record_layers:
        record_layers(parser, repo, source, host_name)
        return
    try:
        inputs = chromium_engine.host_inputs(repo, host_name)
    except ValueError as error:
        parser.error(str(error))
    states = {}
    for name, hashes in inputs.items():
        path = source / name
        if not path.is_file():
            parser.error(f"Missing pinned Chromium input: {name}")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        state = next((key for key, value in hashes.items() if value == digest), None)
        if state is None:
            parser.error(f"Changed Chromium input; review against the pinned host patches: {name}")
        states[name] = state
    # Each input was matched against its reviewed before/after hash. A new host
    # revision may introduce another input after earlier files were installed.
    sections = chromium_engine.patch_sections(chromium_engine.host_patch(repo, host_name))
    if {name for name, _ in sections} != set(inputs):
        parser.error("The host's input hashes do not cover exactly the files its patches change")
    pending = [(name, section) for name, section in sections if states[name] == "before"]
    # A file several patches change takes them in order, which `patch
    # --dry-run` cannot check, so the result is made in a scratch copy first.
    with tempfile.TemporaryDirectory(prefix="crest-host-") as temporary:
        scratch = Path(temporary)
        for name in {name for name, _ in pending}:
            (scratch / name).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / name, scratch / name)
        if pending:
            # Bytes, so Windows does not turn the patch's line endings into CRLF.
            subprocess.run([chromium_host.patch_tool(), "--batch", "--fuzz=0", "--forward", "-p1", "-s"],
                           input="".join(section for _, section in pending).encode("utf-8"), cwd=scratch, check=True)
        for name in {name for name, _ in pending}:
            if hashlib.sha256((scratch / name).read_bytes()).hexdigest() != inputs[name]["after"]:
                parser.error(f"Host patches do not produce their reviewed output: {name}")
        state = "after" if not pending else "pending"
        if not args.apply:
            print(f"Host inputs validated ({state}); no source was changed.")
            return
        # Never alter inputs under an active compiler. The build wrapper uses a
        # dedicated process group, but other Ninja invocations must also be quiet.
        if os.name == "nt":
            # Windows lists no arguments without elevation, so any Ninja counts.
            processes = subprocess.check_output(["tasklist", "/FI", "IMAGENAME eq ninja.exe", "/FO", "CSV", "/NH"], text=True)
            if "ninja.exe" in processes.lower():
                parser.error("Stop the Chromium Ninja build before installing the overlay")
        else:
            processes = subprocess.check_output(["ps", "-axo", "comm=,args="], text=True)
            if any("ninja" in line.split()[0] and "CrestBaseline" in line for line in processes.splitlines() if line.split()):
                parser.error("Stop the task's Chromium Ninja build before installing the overlay")
        for name in {name for name, _ in pending}:
            shutil.copyfile(scratch / name, source / name)
    # An installed file takes the time it was installed, never its source's:
    # an object built after the source was edited, from the previous install,
    # must still be older than the file that replaces its input, or Ninja
    # links it again.
    for overlay in (root / "Overlay" for root in chromium_engine.layer_roots(host_name, repo)):
        for path in overlay.rglob("*"):
            if path.is_file():
                destination = source / path.relative_to(overlay)
                destination.parent.mkdir(parents=True, exist_ok=True)
                if not destination.is_file() or destination.read_bytes() != path.read_bytes():
                    shutil.copy(path, destination)
    # The host header, the engine contract the binding implements (the C ABI
    # it registers through and the generated C++ codec), and the content
    # filter's C interface it checks requests through.
    headers = [host / "Apple/CrestChromiumHost.h", repo / CONTENT_FILTER_HEADER]
    headers += [repo / "CrestContracts/include" / name for name in ENGINE_CONTRACT]
    for header in headers:
        destination = source / "chrome/browser/ui/crest" / header.name
        if not destination.is_file() or destination.read_bytes() != header.read_bytes():
            shutil.copy(header, destination)
    print("Installed host sources. Regenerate GN and build before packaging the native UI framework.")


if __name__ == "__main__":
    main()
