"""Crest's maintained Chromium patch fork and persistent build workspace."""
from __future__ import annotations

import contextlib
import difflib
import fcntl
import hashlib
import html
import importlib.util
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

import chromium_engine

REPO = Path(__file__).resolve().parents[2]
ENGINE = Path("CrestEngines/Chromium")
# The directory the workspace's Actions runner works in.
RUNNER_WORK = "runner-work"
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")
# A prepared source directory is named by its preparation key's first 20 hex digits.
SOURCE_NAME = re.compile(r"[0-9a-f]{20}")
PREPARATION_FIELDS = ("chromium", "dependencies", "cipd", "crestPatches")
# Where the architectures' browsers merge into the one universal engine a
# release packages.
UNIVERSAL_OUTPUT = "out/CrestUniversal"
# The macOS name of each architecture the lock names by its GN `target_cpu`.
MACHINES = {"arm64": "arm64", "x64": "x86_64"}
# The first bytes of a universal, 64-bit or 32-bit Mach-O file.
MACH_O_MAGIC = (bytes.fromhex("cafebabe"), bytes.fromhex("cffaedfe"), bytes.fromhex("cefaedfe"))
# Present while a tree is being moved to a new release in place.
ADVANCING = "advancing.json"
ARCHIVE = "https://commondatastorage.googleapis.com/chromium-browser-official/chromium-{version}-lite.tar.xz"
CIPD = "https://chrome-infra-packages.appspot.com/prpc/cipd.Repository/ResolveVersion"
# What gclient sets for a source-archive checkout on this host, as
# prepare-chromium.py evaluates it. A DEPS below src is read as part of
# Chromium, not as its own standalone checkout.
DEPS_HOST = {"host_os": "mac", "host_cpu": "arm64", "checkout_mac": True, "checkout_arm64": True,
             "non_git_source": True}
DEPS_EMBEDDED = {"build_with_chromium": True, "dawn_standalone": False}
CIPD_PLATFORM = {"platform": "mac-arm64", "os": "mac", "arch": "arm64"}
# Google's release notes, which say what each release fixes and whether it is an
# early stable build that reaches only a small share of people first.
RELEASE_NOTES = "https://chromereleases.googleblog.com/feeds/posts/default?alt=json&max-results=80"
NOTED_VERSIONS = re.compile(r"\b(\d+\.\d+\.\d+\.)(\d+)((?:/\.\d+)*)")
SEVERITY = re.compile(r"\b(Critical|High|Medium|Low)\s+(CVE-\d{4}-\d+)")
# Upstream files an update reads to find what changed under Crest's overlay and packaging.
HELPER_LIST = "chrome/installer/mac/signing/parts.py"
HELPER_APP = re.compile(r"Helpers/\{0\.product\} Helper( \([^)]+\))?\.app")
ANNOTATIONS = "tools/traffic_annotation/summary/annotations.xml"
ANNOTATION = re.compile(r'<item id="([^"]+)"')
PURE_VIRTUAL = re.compile(r"\bvirtual\s[^;{}]*?=\s*0\s*;")
INCLUDE = re.compile(r'^\s*#\s*(?:include|import)\s+"([^"]+)"', re.MULTILINE)
COMPILED = (".c", ".cc", ".cpp", ".m", ".mm")


def run(*args, cwd=None, capture=False):
    return subprocess.run([str(arg) for arg in args], cwd=cwd, check=True,
                          text=True, capture_output=capture).stdout


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text())


def write_json(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def release_version(version):
    if not VERSION.fullmatch(version):
        raise ValueError(f"Not a Chromium version: {version}")
    return tuple(map(int, version.split(".")))


def select_update(current, releases, allow_major=False):
    """The newest release to update to: a fix on the pinned milestone, or a new milestone when allowed."""
    current_version = release_version(current)
    candidates = [version for version in releases
                  if VERSION.fullmatch(version) and release_version(version) > current_version]
    eligible = [version for version in candidates
                if allow_major or release_version(version)[0] == current_version[0]]
    return {
        "current": current,
        "candidate": max(eligible, key=release_version) if eligible else None,
        "latest": max(candidates, key=release_version) if candidates else current,
        "majorReviewRequired": any(release_version(version)[0] > current_version[0] for version in candidates),
    }


def upstream_releases(policy):
    """Chrome's releases on the policy's channel and platform, newest first, from chromiumdash."""
    upstream = policy["upstream"]
    query = urllib.parse.urlencode({"channel": upstream["channel"], "platform": upstream["platform"], "num": 50})
    with urllib.request.urlopen(f"{upstream['releases']}?{query}", timeout=60) as response:
        return [release["version"] for release in json.load(response)]


def preparation_key(repo, lock):
    inputs = {field: lock[field] for field in PREPARATION_FIELDS}
    inputs["prepareScript"] = sha256(repo / "Scripts/control-plane/prepare-chromium.py")
    return hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()


def validate_workspace(root, repo):
    root, repo = root.expanduser().resolve(), repo.resolve()
    # The Actions runner the workspace hosts checks Crest out under its own
    # work directory, which holds no Chromium source or build output.
    checked_out_by_runner = root / RUNNER_WORK in repo.parents
    if root == repo or repo in root.parents or (root in repo.parents and not checked_out_by_runner):
        raise ValueError("The build workspace must be separate from the Crest checkout")
    if root == Path.home() or root == Path("/"):
        raise ValueError("Choose a dedicated Chromium workspace directory")
    return root


def remove_path(path):
    """Remove whatever is at `path`: a file, a link, or a directory and everything in it."""
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    elif path.exists() or path.is_symlink():
        path.unlink()


def within_directories(root, path):
    """Whether every directory between `root` and `path` is a real directory rather than a link."""
    current = root
    for part in path.relative_to(root).parts[:-1]:
        current = current / part
        if current.is_symlink() or not current.is_dir():
            return False
    return True


def make_directory(root, path):
    """Make `path` a directory, replacing any file or link at it or above it within `root`."""
    current = root
    for part in path.relative_to(root).parts:
        current = current / part
        if current.is_symlink() or (current.exists() and not current.is_dir()):
            current.unlink()
        current.mkdir(exist_ok=True)


def building():
    """Whether a Ninja build of a Chromium tree is running, managed or not."""
    processes = run("ps", "-axo", "comm=,args=", capture=True)
    return any("ninja" in line.split()[0] and "CrestBaseline" in line for line in processes.splitlines() if line.split())


@contextlib.contextmanager
def timed(timings, step):
    """Record how many seconds `step` took in `timings`."""
    start = time.monotonic()
    try:
        yield
    finally:
        timings[step] = round(time.monotonic() - start)


@contextlib.contextmanager
def exclusive_workspace(root):
    root.mkdir(parents=True, exist_ok=True)
    with (root / ".crest-build.lock").open("a+") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError(f"Another Chromium operation owns {root}") from None
        try:
            yield
        finally:
            fcntl.flock(stream, fcntl.LOCK_UN)


def prune_downloads(root, lock):
    """Remove cached source archives and PGO profiles that `lock` doesn't name, returning their names."""
    keep = {Path(lock["chromium"]["sourceArchive"]).name}
    keep |= {architecture["pgoProfile"] for architecture in lock["architectures"].values()}
    stale = [path for pattern in ("downloads/chromium-*-lite.tar.xz", "profiles/*.profdata")
             for path in sorted(root.glob(pattern)) if path.name not in keep]
    # A running build reads its PGO profile in every compile command.
    if stale and building():
        raise ValueError("A Chromium build is running; remove cached archives and profiles after it finishes")
    for path in stale:
        path.unlink()
    return [path.name for path in stale]


def prune_sources(root, keep):
    """Remove prepared sources not named in `keep`; each is a full checkout and build."""
    sources = root / "sources"
    if not sources.is_dir():
        return []
    stale = [directory for directory in sorted(sources.iterdir())
             if SOURCE_NAME.fullmatch(directory.name) and directory.name not in keep
             and directory.is_dir() and not directory.is_symlink()]
    # A build started without the workspace lock may be compiling in one of them.
    if stale and building():
        raise ValueError("A Chromium build is running; remove superseded sources after it finishes")
    for directory in stale:
        shutil.rmtree(directory)
    return [directory.name for directory in stale]


def restore_host_base(source, previous, desired):
    # A legacy build may already have installed the desired reviewed patch
    # without updating our marker. Accept that exact state, but no local edits.
    target_states = {name: set(hashes.values()) for name, hashes in desired.items()}
    target_states.update({name: {hashes["before"]} for name, hashes in previous["inputs"].items()
                          if name not in desired})
    if all((source / name).is_file() and sha256(source / name) in hashes
           for name, hashes in target_states.items()):
        return
    for name, hashes in previous["inputs"].items():
        if not (source / name).is_file() or sha256(source / name) != hashes["after"]:
            raise ValueError(f"Locally modified host source: {name}")
    subprocess.run(["patch", "--batch", "--fuzz=0", "-R", "-p1"],
                   input=chromium_engine.reversed_patch(previous["patch"]), cwd=source, text=True, check=True)


class Workspace:
    def __init__(self, root, repo=REPO):
        self.root = validate_workspace(root, repo)
        self.repo = repo
        self.lock = read_json(repo / ENGINE / "source.lock.json")
        self.key = preparation_key(repo, self.lock)
        self.directory = self.root / "sources" / self.key[:20]
        self.source = self.directory / "src"
        self.downloads = self.root / "downloads"

    def script(self, name, *args, capture=False):
        return run(sys.executable, self.repo / "Scripts/control-plane" / name, *args, capture=capture)

    def prepare(self):
        self.directory.mkdir(parents=True, exist_ok=True)
        marker = self.directory / "prepared.json"
        if (self.directory / ADVANCING).exists():
            raise ValueError(f"An advance to a new release stopped partway at {self.directory}. Inspect it before building.")
        if marker.exists():
            if read_json(marker)["preparationKey"] != self.key or not (self.source / "out/CrestBaseline/gn").is_file():
                raise ValueError("Prepared workspace is incomplete or has different inputs")
            self.script("prepare-chromium.py", "--source", self.source, "--verify-only")
        elif self.source.exists() or self.source.with_name("src.partial").exists():
            raise ValueError(f"Incomplete preparation at {self.directory}. Inspect it before removing or resuming it.")
        else:
            if shutil.disk_usage(self.directory).free < 50 * 1024**3:
                raise ValueError("A fresh Chromium source preparation needs at least 50 GiB free; existing builds are retained")
            self.script("prepare-chromium.py", "--source", self.source, "--downloads", self.downloads)
            write_json(marker, {"preparationKey": self.key})

    def apply_host(self):
        if building():
            raise ValueError("Wait for the active Chromium build before changing the host")
        installed = self.directory / "host.json"
        patch = chromium_engine.host_patch(self.repo)
        inputs = read_json(self.repo / ENGINE / "host-inputs.json")
        if installed.exists():
            previous = read_json(installed)
            if previous["patch"] != patch:
                restore_host_base(self.source, previous, inputs)
            current_files = {p.relative_to(self.repo / ENGINE / "Overlay").as_posix()
                             for p in (self.repo / ENGINE / "Overlay").rglob("*") if p.is_file()}
            for name, checksum in previous.get("overlay", {}).items():
                if name not in current_files:
                    destination = self.source / name
                    if sha256(destination) != checksum:
                        raise ValueError(f"Locally modified removed overlay: {name}")
                    destination.unlink()
        self.script("apply-chromium-host.py", "--source", self.source, "--apply")
        overlay = {p.relative_to(self.repo / ENGINE / "Overlay").as_posix(): sha256(p)
                   for p in (self.repo / ENGINE / "Overlay").rglob("*") if p.is_file()}
        write_json(installed, {"patch": patch, "inputs": inputs, "overlay": overlay})

    def build(self, sdk, ninja, jobs, reserve, timings=None):
        timings = {} if timings is None else timings
        with timed(timings, "prepare"):
            self.prepare()
        with timed(timings, "host"):
            self.apply_host()
        # Each architecture builds in its own output of the one prepared source.
        architectures = self.lock["architectures"]
        with timed(timings, "configure"):
            for cpu, architecture in architectures.items():
                profile = download_profile(self.root, architecture)
                if performance_configuration_matches(self.source, self.lock, sdk, cpu):
                    # Preserve equivalent absolute paths in an adopted build. Rewriting its
                    # PGO path alone invalidates every compile command in Ninja.
                    run(self.source / "buildtools/mac/gn", "gen", architecture["output"], "--fail-on-unused-args",
                        cwd=self.source)
                else:
                    self.script("configure-chromium.py", "--source", self.source, "--configuration", "performance",
                                "--cpu", cpu, "--sdk", sdk, "--pgo-profile", profile)
                if not performance_configuration_matches(self.source, self.lock, sdk, cpu):
                    raise ValueError(f"{architecture['output']}/args.gn contains unpinned overrides; review it before "
                                     "building a published engine")
                require_overlay_compiled(self.repo, self.source, ninja, architecture["output"])
        for cpu, architecture in architectures.items():
            with timed(timings, f"compile-{cpu}"):
                self.script("build-chromium-baseline.py", "--source", self.source, "--ninja", ninja,
                            "--jobs", jobs, "--min-free-gib", reserve, "--output", architecture["output"])
        with timed(timings, "universal"):
            browser = universal_engine(self.source, self.lock)
        with timed(timings, "smoke"):
            smoke_engine(browser, self.root, self.lock)
        return timings

    def advance(self, target, previous_archive):
        """Move this built tree in place to `target`'s release, rewriting only the files that release changes.

        For a release on the same milestone whose toolchains and tools are
        unchanged, which `plan_update` decides. Files the new archive leaves as
        they were keep their timestamps, so Ninja recompiles only what the release
        changed. The tree takes the target's directory; Crest's host is reversed
        here and installed again by the next build.
        """
        if building():
            raise ValueError("Wait for the active Chromium build before advancing its source")
        installed = read_json(self.directory / "host.json")
        for name, hashes in installed["inputs"].items():
            if sha256(self.source / name) != hashes["after"]:
                raise ValueError(f"Locally modified host source: {name}")
        if target.directory.exists():
            raise ValueError(f"A source for {target.lock['chromium']['version']} already exists at {target.directory}")
        archive = self.downloads / Path(target.lock["chromium"]["sourceArchive"]).name
        if sha256(archive) != target.lock["chromium"]["sourceArchiveSha256"]:
            raise ValueError("The new source archive does not match the lock")
        write_json(self.directory / ADVANCING, {"from": self.lock["chromium"]["version"],
                                                "to": target.lock["chromium"]["version"]})
        subprocess.run(["patch", "--batch", "--fuzz=0", "-R", "-p1", "-s"], cwd=self.source, text=True, check=True,
                       input=chromium_engine.reversed_patch(installed["patch"]))
        # Preparation puts the Mac toolchains and pinned tools at these paths; the
        # archive's own copies there are for the Linux host that exported it.
        tools = tuple(path.removeprefix("src/") + "/" for path in [*target.lock["dependencies"], *target.lock["cipd"]])
        build_patched = {}
        for relative in target.lock["crestPatches"]:
            for path, _ in chromium_engine.patch_sections((self.repo / ENGINE / relative).read_text()):
                build_patched.setdefault(path, []).append(relative)
        changed, names, originals = [], set(), {}
        for name, member, stream in archive_members(archive):
            names.add(name)
            path = self.source / name
            if name.startswith(tools):
                continue
            # A release can turn a file into a directory or the reverse; whatever
            # is in the way of the member's own type goes first.
            if member.isdir():
                if not path.is_dir() or path.is_symlink():
                    make_directory(self.source, path)
                    changed.append(name)
                continue
            if not path.parent.is_dir():
                make_directory(self.source, path.parent)
            if member.issym():
                if path.is_symlink() and os.readlink(path) == member.linkname:
                    continue
                remove_path(path)
                path.symlink_to(member.linkname)
                changed.append(name)
            elif member.isfile():
                data = stream.extractfile(member).read()
                # The mode preparation's "tar" extraction filter leaves a file.
                mode = stat.S_IMODE(member.mode) & 0o755
                if name in build_patched:
                    originals[name] = data
                    continue
                if not path.is_symlink() and path.is_file() and path.stat().st_size == len(data) and path.read_bytes() == data:
                    # Same contents: a new mode is applied, and the timestamp is kept.
                    if stat.S_IMODE(path.stat().st_mode) != mode:
                        path.chmod(mode)
                        changed.append(name)
                    continue
                if path.is_symlink() or path.is_dir():
                    remove_path(path)
                path.write_bytes(data)
                path.chmod(mode)
                changed.append(name)
        # Crest's build adjustments, applied to the new release's copies of the files they change.
        with tempfile.TemporaryDirectory(prefix="crest-advance-") as temporary:
            scratch = Path(temporary)
            for name, data in originals.items():
                (scratch / name).parent.mkdir(parents=True, exist_ok=True)
                (scratch / name).write_bytes(data)
            for relative in target.lock["crestPatches"]:
                run("patch", "--batch", "-p1", "--forward", "--fuzz=0", "-s", "--input", self.repo / ENGINE / relative,
                    cwd=scratch)
            for name in originals:
                if (self.source / name).read_bytes() != (scratch / name).read_bytes():
                    shutil.copyfile(scratch / name, self.source / name)
                    changed.append(name)
        removed = []
        for name, member, _ in archive_members(previous_archive):
            path = self.source / name
            # A directory the release replaced with a link leads elsewhere in the tree,
            # possibly to a file the release just installed; nothing is removed through it.
            if (name not in names and not name.startswith(tools) and not member.isdir()
                    and within_directories(self.source, path) and (path.exists() or path.is_symlink())):
                path.unlink()
                removed.append(name)
        # Directories the release no longer has, as a fresh source wouldn't have
        # them, deepest first so a parent is looked at after its children.
        parents = {parent for name in removed for parent in Path(name).parents if parent != Path(".")}
        for parent in sorted(parents, key=lambda parent: len(parent.parts), reverse=True):
            directory = self.source / parent
            if (parent.as_posix() not in names and within_directories(self.source, directory) and directory.is_dir()
                    and not directory.is_symlink() and not any(directory.iterdir())):
                directory.rmdir()
        if any(name.startswith("tools/gn/") for name in changed + removed):
            output = self.source / "out/CrestBaseline"
            run(sys.executable, self.source / "tools/gn/bootstrap/bootstrap.py", "-o", output / "gn",
                "--skip-generate-buildfiles", cwd=self.source)
            shutil.copy2(output / "gn", self.source / "buildtools/mac/gn")
        (self.directory / "host.json").rename(self.directory / "host-previous.json")
        self.directory.rename(target.directory)
        write_json(target.directory / "prepared.json", {"preparationKey": target.key})
        write_json(target.directory / "advanced.json", {"from": self.lock["chromium"]["version"],
            "to": target.lock["chromium"]["version"], "changed": sorted(changed), "removed": sorted(removed)})
        (target.directory / ADVANCING).unlink()
        return {"changed": len(changed), "removed": len(removed)}


def universal_engine(source, lock):
    """Merge each architecture's browser into one universal `Chromium.app`,
    with the universalizer Chromium ships for its own universal builds, and
    answer it. Every executable must then hold every architecture."""
    browsers = [source / architecture["output"] / "Chromium.app" for architecture in lock["architectures"].values()]
    merged = source / UNIVERSAL_OUTPUT / "Chromium.app"
    if merged.exists():
        shutil.rmtree(merged)
    merged.parent.mkdir(parents=True, exist_ok=True)
    run(sys.executable, source / "chrome/installer/mac/universalizer.py", *browsers, merged, cwd=source)
    require_universal(merged, lock)
    return merged


def require_universal(browser, lock):
    """Refuse a browser in which any executable or library lacks one of the
    lock's architectures."""
    machines = {MACHINES[cpu] for cpu in lock["architectures"]}
    for path in sorted(browser.rglob("*")):
        if path.is_file() and not path.is_symlink() and is_mach_o(path):
            held = set(subprocess.run(["lipo", "-archs", str(path)], capture_output=True, text=True).stdout.split())
            if missing := machines - held:
                raise ValueError(f"{path.relative_to(browser)} lacks {', '.join(sorted(missing))}")


def is_mach_o(path):
    """Whether `path` is a Mach-O file, thin or universal."""
    with path.open("rb") as stream:
        return stream.read(4) in MACH_O_MAGIC


def smoke_engine(browser, workspace, lock):
    """Require the universal `browser` to report the pinned version and to
    render a page as each of the lock's architectures, the others through
    Rosetta."""
    with (browser / "Contents/Info.plist").open("rb") as stream:
        actual = plistlib.load(stream)["CFBundleShortVersionString"]
    if lock["chromium"]["version"] != actual:
        raise ValueError(f"Built engine reports an unexpected version: {actual}")
    scratch = workspace / "scratch"
    scratch.mkdir(exist_ok=True)
    native = platform.machine()
    for cpu in lock["architectures"]:
        # Rosetta translates the whole framework on a fresh build's first
        # launch, about 35 s on the build Mac, before the page runs.
        machine = MACHINES[cpu]
        timeout = 30 if machine == native else 180
        check_renders_page(browser / "Contents/MacOS/Chromium", scratch, timeout=timeout, machine=machine)


def check_renders_page(browser, scratch, timeout=30, machine=None):
    """Require `browser`, run headless in a throwaway profile, to run a page's
    JavaScript, as `machine` (an `arch` name) where one is given."""
    with tempfile.TemporaryDirectory(prefix="smoke-", dir=scratch) as profile:
        page = "data:text/html,<script>document.title='crest-'+(6*7)</script>"
        launcher = ["arch", f"-{machine}"] if machine else []
        process = subprocess.Popen([*launcher, str(browser), "--headless", "--disable-gpu", "--disable-background-networking",
            "--no-first-run", "--no-default-browser-check", "--use-mock-keychain", "--timeout=10000",
            f"--user-data-dir={profile}", "--dump-dom", page], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, start_new_session=True)
        output, errors = bytearray(), bytearray()
        try:
            deadline = time.monotonic() + timeout
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ, output)
                selector.register(process.stderr, selectors.EVENT_READ, errors)
                while b"<title>crest-42</title>" not in output and time.monotonic() < deadline:
                    events = selector.select(timeout=min(1, max(0, deadline - time.monotonic())))
                    for key, _ in events:
                        data = os.read(key.fileobj.fileno(), 65536)
                        if data:
                            key.data.extend(data)
                        else:
                            selector.unregister(key.fileobj)
                    if not selector.get_map():
                        break
            if b"<title>crest-42</title>" not in output:
                raise ValueError(f"Engine JavaScript smoke check failed: {errors[-2000:].decode(errors='replace')}")
        finally:
            # macOS helpers can keep output pipes open after dump-dom completes.
            # This checks rendering, then explicitly closes only its own process group.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except (ProcessLookupError, PermissionError):  # The group has already exited.
                pass
            if process.poll() is None:
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()


def require_overlay_compiled(repo, source, ninja, output="out/CrestBaseline"):
    """Refuse a build whose browser target compiles none of an overlay source.

    Chromium sometimes folds the target Crest's host sources sit in into
    another one, and a list GN accepts can still compile nothing. Every
    overlay source must be an input of the `chrome` target the build makes,
    not merely of some target in the graph, before hours are spent compiling.
    """
    listing = run(ninja, "-C", source / output, "-t", "inputs", "chrome", capture=True)
    inputs = {os.path.normpath(os.path.join(output, line)) for line in listing.splitlines() if line}
    overlay = repo / ENGINE / "Overlay"
    missing = sorted(relative for path in overlay.rglob("*")
                     if path.suffix in COMPILED and (relative := path.relative_to(overlay).as_posix()) not in inputs)
    if missing:
        raise ValueError("The browser target compiles none of these overlay sources; check the target that lists them: "
                         + ", ".join(missing))


def performance_configuration_matches(source, lock, sdk=None, cpu="arm64"):
    """Whether `cpu`'s output is configured exactly as the lock pins it: its
    arguments, the SDK and its architecture's PGO profile."""
    def assignments(text):
        values = {}
        for line in text.splitlines():
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            match = re.fullmatch(r"\s*(\w+)\s*=\s*(.+?)\s*", line)
            if not match:
                raise ValueError("Unsupported GN argument expression")
            values[match[1]] = json.loads(match[2])
        return values

    architecture = lock["architectures"][cpu]
    try:
        values = assignments((source / architecture["output"] / "args.gn").read_text())
    except (ValueError, OSError):
        return False
    expected_flags = {"target_cpu": cpu, **lock["buildArguments"], **lock["performanceBuildArguments"]}
    actual_flags = {name: value for name, value in values.items() if name not in ("mac_sdk_path", "pgo_data_path")}
    if actual_flags != expected_flags:
        return False
    selected_sdk = values.get("mac_sdk_path", "")
    if not selected_sdk.startswith("//"):
        return False
    sdk_path = (source / selected_sdk[2:]).resolve()
    expected = lock["performanceInputs"]
    if sdk is not None and sdk_path != sdk.resolve():
        return False
    if not (sdk_path / "SDKSettings.json").is_file() or read_json(sdk_path / "SDKSettings.json")["Version"] != expected["macSDKVersion"]:
        return False
    profile = Path(values.get("pgo_data_path", ""))
    return (profile.is_file() and profile.name == architecture["pgoProfile"]
            and sha256(profile) == architecture["pgoSHA256"]
            and (source / architecture["pgoProfileFile"]).read_text().strip() == profile.name)


def download(url, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + ".partial")
    try:
        with urllib.request.urlopen(url, timeout=120) as response, partial.open("wb") as output:
            shutil.copyfileobj(response, output)
        partial.replace(destination)
    finally:
        partial.unlink(missing_ok=True)


def download_profile(root, inputs):
    name = inputs["pgoProfile"]
    if Path(name).name != name or not re.fullmatch(r"[A-Za-z0-9.-]+\.profdata", name):
        raise ValueError("Invalid PGO profile name")
    profile = root / "profiles" / name
    if not profile.exists():
        download(f"https://storage.googleapis.com/chromium-optimization-profiles/pgo_profiles/{name}", profile)
    if inputs.get("pgoSHA256") and sha256(profile) != inputs["pgoSHA256"]:
        raise ValueError("PGO checksum differs from source.lock.json")
    return profile


def refresh_host_inputs(repo, source, installed=None):
    """Check the host patches apply without fuzz before pinning new upstream bytes."""
    host = repo / ENGINE
    patch = chromium_engine.host_patch(repo)
    names = list(dict.fromkeys(name for name, _ in chromium_engine.patch_sections(patch)))
    if not names:
        raise ValueError("The host patches change no files")
    hashes = {}
    with tempfile.TemporaryDirectory(prefix="host-refresh-") as temporary:
        root = Path(temporary)
        previous = read_json(installed) if installed and installed.exists() else None
        copied_names = set(names) | (set(previous["inputs"]) if previous else set())
        for name in copied_names:
            relative = Path(name)
            if relative.is_absolute() or ".." in relative.parts:
                raise ValueError("Invalid path in host patch")
            destination = root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / relative, destination)
        if previous:
            for name, expected in previous["inputs"].items():
                if sha256(root / name) != expected["after"]:
                    raise ValueError(f"Existing update workspace has a modified host: {name}")
            # A retried update may already have its host installed. Reconstruct
            # pristine inputs in the temporary copy, leaving the live build intact.
            subprocess.run(["patch", "--batch", "--fuzz=0", "-R", "-p1"],
                           input=chromium_engine.reversed_patch(previous["patch"]), cwd=root, text=True, check=True)
        for name in names:
            hashes[name] = {"before": sha256(root / name)}
        subprocess.run(["patch", "--batch", "--fuzz=0", "--forward", "-p1"], input=patch, cwd=root, text=True, check=True)
        for name in names:
            hashes[name]["after"] = sha256(root / name)
    write_json(host / "host-inputs.json", hashes)


def resolve_cipd(package, version):
    """The SHA-256 instance digest CIPD holds for `package` at `version`."""
    request = urllib.request.Request(CIPD, data=json.dumps({"package": package, "version": version}).encode(),
                                     headers={"Content-Type": "application/json", "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=60) as response:
        # pRPC prefixes its JSON with an anti-XSSI line.
        instance = json.loads(response.read().decode().split("\n", 1)[1])["instance"]
    if instance["hashAlgo"] != "SHA256":
        raise ValueError(f"CIPD returned an unexpected digest for {package}")
    return instance["hexDigest"]


def deps_cipd(deps_text, directory):
    """{checkout path: [(package, version, version file)]} for the CIPD packages a DEPS file pins on this host.

    `directory` is where the DEPS file sits in the checkout, such as "src/". An
    entry whose condition is false on this host, such as an Android one, is not
    part of this build. A version kept in a file comes back as that file's
    checkout path, with no version, for the caller to read; any other form is
    an error rather than a package left out.
    """
    scope = {}
    exec(deps_text, {"Var": lambda name: "{" + name + "}", "Str": str}, scope)
    variables = {**scope.get("vars", {}), **DEPS_HOST, **(DEPS_EMBEDDED if directory != "src/" else {})}

    class Variables(dict):
        def __missing__(self, _):
            return False

    def applies(condition):
        return not condition or bool(eval(condition, {"__builtins__": {}}, Variables(variables)))

    def expand(text):
        text = re.sub(r"\$\{\{(\w+)\}\}", lambda match: CIPD_PLATFORM[match.group(1)], text)
        return re.sub(r"\{(\w+)\}", lambda match: str(variables[match.group(1)]), text)

    prefix = directory if scope.get("use_relative_paths") else ""
    packages = {}
    for path, dependency in scope["deps"].items():
        if not isinstance(dependency, dict) or dependency.get("dep_type") != "cipd":
            continue
        if not applies(dependency.get("condition")):
            continue
        for item in dependency["packages"]:
            if "version" in item:
                pinned = (expand(item["version"]), None)
            elif "version_file" in item:
                pinned = (None, directory + item["version_file"])
            else:
                raise ValueError(f"DEPS pins {prefix + path} in a form Crest does not read: {sorted(item)}")
            packages.setdefault(prefix + path, []).append((expand(item["package"]), *pinned))
    return packages


def archive_members(archive):
    """Each (path below the top directory, member, stream) of a source archive, decompressed on every core."""
    process = subprocess.Popen(["xz", "-dc", "-T0", str(archive)], stdout=subprocess.PIPE)
    try:
        with tarfile.open(fileobj=process.stdout, mode="r|") as stream:
            for member in stream:
                name = member.name.split("/", 1)[1] if "/" in member.name else ""
                if name:
                    yield name, member, stream
        # The archive's trailing padding follows its last member.
        while process.stdout.read(1 << 20):
            pass
        if process.wait():
            raise ValueError(f"Could not decompress {archive.name}")
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        process.stdout.close()


def read_archive(archive, names):
    """{path: bytes} for the regular files at `names` below the archive's top directory; absent ones are left out."""
    wanted, found = set(names), {}
    for name, member, stream in archive_members(archive):
        if name in wanted and member.isfile():
            found[name] = stream.extractfile(member).read()
            if len(found) == len(wanted):
                break
    return found


def archive_files(archive, version, paths):
    """{checkout path: text} for files under src in the Chromium source archive."""
    found = read_archive(archive, [path.removeprefix("src/") for path in paths])
    if missing := sorted(path for path in paths if path.removeprefix("src/") not in found):
        raise ValueError(f"The source archive is missing {', '.join(missing)}")
    return {path: found[path.removeprefix("src/")].decode() for path in paths}


def candidate_lock(repo, root, version):
    """The source lock for Chrome `version`, resolved from its own DEPS; the running build is untouched."""
    lock = read_json(repo / ENGINE / "source.lock.json")
    if release_version(version) <= release_version(lock["chromium"]["version"]):
        raise ValueError("Upstream updates must advance the pinned release")
    url = ARCHIVE.format(version=version)
    try:
        with urllib.request.urlopen(url + ".hashes", timeout=120) as response:
            manifest = response.read().decode()
    except urllib.error.HTTPError as error:
        raise ValueError(f"Chromium has not published the {version} source archive yet") from error
    checksums = re.findall(r"^sha256\s+([a-f0-9]{64})\s+(\S+)\s*$", manifest, re.MULTILINE)
    if len(checksums) != 1 or checksums[0][1] != url.rsplit("/", 1)[1]:
        raise ValueError("Source manifest does not identify the requested archive")
    lock["chromium"] = {"version": version, "sourceArchive": url,
                        "hashManifest": manifest, "sourceArchiveSha256": checksums[0][0]}
    archive = root / "downloads" / url.rsplit("/", 1)[1]
    if not archive.is_file() or sha256(archive) != checksums[0][0]:
        download(url, archive)
        if sha256(archive) != checksums[0][0]:
            raise ValueError("Chromium source archive does not match its published manifest")
    # The archive's own DEPS names the CIPD tool versions and the PGO profile.
    deps = ("src/", "src/third_party/dawn/", "src/third_party/devtools-frontend/src/")
    profile_files = {cpu: "src/" + architecture["pgoProfileFile"] for cpu, architecture in lock["architectures"].items()}
    found = archive_files(archive, version, [directory + "DEPS" for directory in deps] + list(profile_files.values()))
    packages = {}
    for directory in deps:
        for path, entries in deps_cipd(found[directory + "DEPS"], directory).items():
            packages.setdefault(path, []).extend(entries)
    chosen = {}
    for path, pinned in lock["cipd"].items():
        entries = packages.get(path, [])
        matching = [entry for entry in entries if entry[0] == pinned["package"]] or entries
        if len(matching) != 1:
            raise ValueError(f"DEPS pins several packages at {path}" if entries else f"DEPS no longer pins {path}")
        chosen[path] = matching[0]
    version_files = sorted({version_file for _, _, version_file in chosen.values() if version_file})
    versions = archive_files(archive, version, version_files) if version_files else {}
    for path, (package, package_version, version_file) in chosen.items():
        package_version = versions[version_file].strip() if version_file else package_version
        pinned = lock["cipd"][path]
        if (package, package_version) != (pinned["package"], pinned["version"]):
            lock["cipd"][path] = {"package": package, "version": package_version,
                                  "sha256": resolve_cipd(package, package_version)}
    for cpu, profile_file in profile_files.items():
        profile_name = found[profile_file].strip()
        profile = download_profile(root, {"pgoProfile": profile_name})
        lock["architectures"][cpu].update(pgoProfile=profile_name, pgoSHA256=sha256(profile))
    return lock


def noted_versions(text):
    """Every full version a release note names, expanding "157.0.8103.78/.79" to both."""
    versions = set()
    for prefix, last, more in NOTED_VERSIONS.findall(text):
        versions |= {prefix + last} | {prefix + extra for extra in re.findall(r"\d+", more)}
    return versions


def release_notes(version, feed=None):
    """What Google's release notes say about `version`, or the closest earlier noted release on its milestone.

    Some releases, such as a respin that only changes the version, have no note
    of their own; the summary then names the release it describes. Notes are
    advisory, so a failure to read them is reported rather than raised.
    """
    try:
        if feed is None:
            with urllib.request.urlopen(RELEASE_NOTES, timeout=60) as response:
                feed = json.load(response)
        entries = feed["feed"]["entry"]
    except (OSError, ValueError, KeyError) as error:
        return {"error": f"Release notes unavailable: {error}"}
    wanted = release_version(version)
    best = None
    for entry in entries:
        title = entry["title"]["$t"]
        if "Desktop" not in title or "Stable" not in title or "Extended" in title:
            continue
        text = html.unescape(re.sub(r"<[^>]+>", " ", entry["content"]["$t"]))
        noted = [release_version(item) for item in noted_versions(text)]
        eligible = [item for item in noted if item[0] == wanted[0] and item <= wanted]
        if eligible and (best is None or max(eligible) > best[0]):
            best = (max(eligible), title, entry["published"]["$t"], text)
    if best is None:
        return {"error": f"No release note covers {version}"}
    noted, title, published, text = best
    severities = {cve: severity for severity, cve in SEVERITY.findall(text)}
    return {"notedVersion": ".".join(map(str, noted)), "exact": noted == wanted, "title": title, "published": published,
            "earlyStable": "Early Stable" in title,
            "securityFixes": len(set(re.findall(r"CVE-\d{4}-\d+", text))),
            "critical": sum(1 for severity in severities.values() if severity == "Critical"),
            "high": sum(1 for severity in severities.values() if severity == "High"),
            "exploited": bool(re.search(r"exists in the wild", text))}


def apply_section(text, path, section):
    """`text`, the file at `path`, with one patch section applied without fuzz, or None when it does not apply."""
    with tempfile.TemporaryDirectory(prefix="crest-section-") as temporary:
        target = Path(temporary) / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        # --forward: a patch whose change the file already has must not pass by applying in reverse.
        result = subprocess.run(["patch", "--batch", "--forward", "--fuzz=0", "-p1", "-s", "--no-backup-if-mismatch"],
                                input=section, cwd=temporary, text=True, capture_output=True)
        return target.read_text() if result.returncode == 0 else None


def merge_three_way(ours, base, theirs):
    """(merged text, whether it conflicts) for Crest's change from `base` to `ours` carried onto `theirs`."""
    with tempfile.TemporaryDirectory(prefix="crest-merge-") as temporary:
        files = [Path(temporary) / name for name in ("ours", "base", "theirs")]
        for file, text in zip(files, (ours, base, theirs)):
            file.write_text(text)
        result = subprocess.run(["git", "merge-file", "-p", "--diff3", "-L", "crest", "-L", "pinned", "-L", "release",
                                 *map(str, files)], capture_output=True, text=True)
    if result.returncode < 0 or result.returncode > 127:
        raise ValueError("git merge-file failed")
    return result.stdout, result.returncode > 0


def rebase_patches(repo, pinned, release, report):
    """Carry each host patch from the pinned upstream files to a new release's, in series order.

    `pinned` and `release` map each patched path to its upstream text; a path
    the release lacks maps to None. A section that applies to the release's file
    without fuzz is kept, including one already rebased for that release.
    Otherwise Crest's change is merged three ways onto the release's file: a
    clean merge gives a rebased section, and a conflicting one is written with
    diff3 markers; a merge that leaves the release's file as it is means the
    release already has Crest's change, and the section is dropped. Writes the
    rebased patch files, conflicts and `report.json` below `report`, and returns
    {patch: {path: status}}, where each status is unchanged, applies, rebased,
    upstream, conflict or missing.
    """
    patches = repo / ENGINE / "Patches"
    series = [line.split("#", 1)[0].strip() for line in (patches / "series").read_text().splitlines()]
    shutil.rmtree(report / "Patches", ignore_errors=True)
    shutil.rmtree(report / "conflicts", ignore_errors=True)
    (report / "Patches").mkdir(parents=True)
    before, after = dict(pinned), dict(release)
    results = {}
    for name in filter(None, series):
        text = (patches / name).read_text()
        header, sections = text[:text.index("--- a/")], []
        for path, section in chromium_engine.patch_sections(text):
            base, theirs = before[path], after[path]
            # A section rebased for the release no longer applies to the pinned file,
            # which then has no known state for the patches after it.
            ours = apply_section(base, path, section) if base is not None else None
            before[path] = ours
            if theirs is None:
                status = "missing"
            elif (applied := apply_section(theirs, path, section)) is not None:
                status, after[path] = ("unchanged" if base == theirs else "applies"), applied
            else:
                merged, conflicted = merge_three_way(ours, base, theirs) if ours is not None else (section, True)
                if conflicted:
                    status = "conflict"
                    conflict = report / "conflicts" / name / path
                    conflict.parent.mkdir(parents=True, exist_ok=True)
                    conflict.write_text(merged)
                elif merged == theirs:
                    results.setdefault(name, {})[path] = "upstream"
                    continue
                else:
                    status = "rebased"
                    section = "".join(difflib.unified_diff(theirs.splitlines(keepends=True),
                                                           merged.splitlines(keepends=True), f"a/{path}", f"b/{path}"))
                    after[path] = merged
            results.setdefault(name, {})[path] = status
            sections.append(section)
        (report / "Patches" / name).write_text(header + "".join(sections))
    write_json(report / "report.json", results)
    return results


def check_build_patches(repo, lock, release):
    """{patch: "applies" or "fails"} for the lock's build adjustments, applied in order to the release's files.

    Preparation and an advance both apply them without fuzz, so a release they
    no longer fit must stop before either touches a source.
    """
    results = {}
    with tempfile.TemporaryDirectory(prefix="crest-build-patches-") as temporary:
        scratch = Path(temporary)
        for path, data in release.items():
            if data is not None:
                (scratch / path).parent.mkdir(parents=True, exist_ok=True)
                (scratch / path).write_bytes(data)
        for relative in lock["crestPatches"]:
            result = subprocess.run(["patch", "--batch", "--forward", "--fuzz=0", "-p1", "-s", "--no-backup-if-mismatch",
                                     "--input", str(repo / ENGINE / relative)], cwd=scratch, capture_output=True, text=True)
            results[relative] = "applies" if result.returncode == 0 else "fails"
    return results


def interface_changes(pinned, release):
    """{header: {"added": [...], "removed": [...]}} for the pure virtual methods that changed in each header."""
    changes = {}
    for header in sorted(set(pinned) | set(release)):
        old, new = ({" ".join(item.split()) for item in PURE_VIRTUAL.findall((files.get(header) or b"").decode(errors="replace"))}
                    for files in (pinned, release))
        if old != new:
            changes[header] = {"added": sorted(new - old), "removed": sorted(old - new)}
    return changes


def advance_obstacles(lock, candidate, pinned_toolchains, release_toolchains):
    """Why the built tree can't move to `candidate`'s release in place; none when only the source changes.

    A new milestone, a toolchain its DEPS fetches or a tool the lock pins would
    leave stale compilers or tools in an advanced tree.
    """
    version = candidate["chromium"]["version"]
    reasons = []
    if release_version(version)[0] != release_version(lock["chromium"]["version"])[0]:
        reasons.append(f"{version} starts milestone {release_version(version)[0]}")
    reasons += [f"DEPS changes the toolchain at {path}" for path in lock["dependencies"]
                if pinned_toolchains.get(path) != release_toolchains.get(path)]
    reasons += [f"The pinned tool at {path} changes" for path in sorted(set(lock["cipd"]) | set(candidate["cipd"]))
                if candidate["cipd"].get(path) != lock["cipd"].get(path)]
    return reasons


def plan_update(repo, root, version, allow_major=False, report=None):
    """Decide how to move the pinned engine to `version` and check Crest's patches against it, changing nothing.

    The path is "advance" when the release keeps the milestone, every toolchain
    DEPS fetches and every pinned tool: the built tree then moves in place and
    Ninja recompiles only what changed. Anything else needs a "fresh" source.
    The plan also reports whether the PGO profile rolled, which recompiles
    everything; how each host patch carries over; the pure virtual methods that
    changed in the headers the overlay includes; helper apps packaging doesn't
    know; and the network traffic annotations the request review must look at.
    """
    lock = read_json(repo / ENGINE / "source.lock.json")
    current = lock["chromium"]["version"]
    milestone = release_version(version)[0] != release_version(current)[0]
    if milestone and not allow_major:
        raise ValueError(f"{version} is a new milestone; pass --allow-major to plan it")
    report = report or root / "reports" / version
    report.mkdir(parents=True, exist_ok=True)
    candidate = candidate_lock(repo, root, version)
    pinned_archive = root / "downloads" / Path(lock["chromium"]["sourceArchive"]).name
    if not pinned_archive.is_file() or sha256(pinned_archive) != lock["chromium"]["sourceArchiveSha256"]:
        download(lock["chromium"]["sourceArchive"], pinned_archive)
        if sha256(pinned_archive) != lock["chromium"]["sourceArchiveSha256"]:
            raise ValueError("The pinned source archive does not match the lock")
    release_archive = root / "downloads" / Path(candidate["chromium"]["sourceArchive"]).name
    patched = list(dict.fromkeys(path for path, _ in chromium_engine.patch_sections(chromium_engine.host_patch(repo))))
    overlay = repo / ENGINE / "Overlay"
    headers = sorted({name for path in overlay.rglob("*") if path.is_file() and path.suffix in (".h", *COMPILED)
                      for name in INCLUDE.findall(path.read_text(errors="replace"))
                      if not (overlay / name).exists()})
    build_patched = {path for relative in candidate["crestPatches"]
                     for path, _ in chromium_engine.patch_sections((repo / ENGINE / relative).read_text())}
    names = {*patched, *headers, *build_patched, "DEPS", HELPER_LIST, ANNOTATIONS}
    pinned, release = read_archive(pinned_archive, names), read_archive(release_archive, names)
    if missing := sorted(set(patched) - set(pinned)):
        raise ValueError(f"The pinned archive lacks patched files: {', '.join(missing)}")

    reasons = advance_obstacles(lock, candidate, *(deps_dependencies(files["DEPS"]) for files in (pinned, release)))
    patches = rebase_patches(repo, {path: pinned[path].decode() for path in patched},
                             {path: release[path].decode() if path in release else None for path in patched}, report)
    helpers = {kind or "" for kind in HELPER_APP.findall(release.get(HELPER_LIST, b"").decode())}
    annotations = [set(ANNOTATION.findall(files.get(ANNOTATIONS, b"").decode())) for files in (pinned, release)]
    plan = {
        "current": current, "version": version, "milestone": milestone,
        "path": "fresh" if reasons else "advance", "reasons": reasons,
        "pgoChanged": any(candidate["architectures"][cpu]["pgoProfile"] != architecture["pgoProfile"]
                          for cpu, architecture in lock["architectures"].items()),
        "patches": {status: sorted(f"{name}: {path}" for name, files in patches.items()
                                   for path, value in files.items() if value == status)
                    for status in ("applies", "rebased", "upstream", "conflict", "missing")},
        "buildPatches": check_build_patches(repo, candidate, {path: release.get(path) for path in build_patched}),
        "unchangedPatchedFiles": sum(value == "unchanged" for files in patches.values() for value in files.values()),
        "interfaceChanges": interface_changes({name: pinned.get(name) for name in headers},
                                              {name: release.get(name) for name in headers}),
        "unknownHelpers": sorted(helpers - set(chromium_engine.ENGINE_HELPER_KINDS)),
        "annotations": {"added": sorted(annotations[1] - annotations[0]),
                        "removed": sorted(annotations[0] - annotations[1])},
        "releaseNotes": release_notes(version),
        "report": str(report),
    }
    plan["blocked"] = (any(plan["patches"][status] for status in ("rebased", "upstream", "conflict", "missing"))
                       or "fails" in plan["buildPatches"].values())
    write_json(report / "plan.json", plan)
    write_json(report / "source.lock.json", candidate)
    return plan, candidate


def deps_dependencies(text):
    """The toolchains a DEPS file has preparation fetch for this host, read as prepare-chromium.py reads them."""
    spec = importlib.util.spec_from_file_location("prepare_chromium", REPO / "Scripts/control-plane/prepare-chromium.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory(prefix="crest-deps-") as temporary:
        (Path(temporary) / "DEPS").write_bytes(text)
        return {"src/" + path.removeprefix("src/"): value for path, value in module.deps_dependencies(Path(temporary)).items()}


def prepare_update(repo, root, version, allow_major=False, timings=None):
    """Plan the update, then prepare its source: the pinned tree advanced in place, or a fresh one."""
    timings = {} if timings is None else timings
    with timed(timings, "plan"):
        plan, candidate = plan_update(repo, root, version, allow_major)
    print(json.dumps(plan, indent=2), flush=True)
    if plan["blocked"]:
        raise ValueError(f"Crest's patches don't apply to {version} as they are; review {plan['report']}")
    lock_path, host_path = repo / ENGINE / "source.lock.json", repo / ENGINE / "host-inputs.json"
    original_lock, original_host = lock_path.read_bytes(), host_path.read_bytes()
    pinned = Workspace(root, repo)
    if (pinned.directory / ADVANCING).exists():
        raise ValueError(f"An advance to a new release stopped partway at {pinned.directory}. Inspect it before updating.")
    # Only a pinned tree that a build installed Crest's host in can be reversed and advanced.
    advance = plan["path"] == "advance" and all((pinned.directory / name).is_file() for name in ("prepared.json", "host.json"))
    try:
        write_json(lock_path, candidate)
        workspace = Workspace(root, repo)
        with timed(timings, "source"):
            if advance:
                print(json.dumps(pinned.advance(workspace, root / "downloads" / Path(pinned.lock["chromium"]["sourceArchive"]).name)),
                      flush=True)
                refresh_host_inputs(repo, workspace.source)
            else:
                # Every fresh source needs its own directory. Keep only the checkout's own,
                # which its branch still builds from, and this update's; any other is superseded.
                for name in prune_sources(root, {pinned.directory.name, workspace.directory.name}):
                    print(f"Removed superseded Chromium source {name}", flush=True)
                workspace.prepare()
                refresh_host_inputs(repo, workspace.source, workspace.directory / "host.json")
        return Workspace(root, repo), plan
    except BaseException:
        lock_path.write_bytes(original_lock)
        host_path.write_bytes(original_host)
        raise
