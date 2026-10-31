"""Crest's maintained Chromium patch fork and persistent build workspace."""
from __future__ import annotations

import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import selectors
import shutil
import signal
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
ARCHIVE = "https://commondatastorage.googleapis.com/chromium-browser-official/chromium-{version}-lite.tar.xz"
CIPD = "https://chrome-infra-packages.appspot.com/prpc/cipd.Repository/ResolveVersion"


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


def prune_sources(root, keep):
    """Remove prepared sources not named in `keep`; each is a full checkout and build."""
    sources = root / "sources"
    if not sources.is_dir():
        return []
    removed = []
    for directory in sorted(sources.iterdir()):
        if (SOURCE_NAME.fullmatch(directory.name) and directory.name not in keep
                and directory.is_dir() and not directory.is_symlink()):
            shutil.rmtree(directory)
            removed.append(directory.name)
    return removed


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
        processes = run("ps", "-axo", "comm=,args=", capture=True)
        if any("ninja" in line.split()[0] and "CrestBaseline" in line
               for line in processes.splitlines() if line.split()):
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

    def build(self, sdk, ninja, jobs, reserve):
        self.prepare()
        self.apply_host()
        profile = download_profile(self.root, self.lock["performanceInputs"])
        if performance_configuration_matches(self.source, self.lock, sdk):
            # Preserve equivalent absolute paths in an adopted build. Rewriting its
            # PGO path alone invalidates every compile command in Ninja.
            run(self.source / "out/CrestBaseline/gn", "gen", "out/CrestBaseline", "--fail-on-unused-args", cwd=self.source)
        else:
            self.script("configure-chromium.py", "--source", self.source, "--configuration", "performance",
                        "--sdk", sdk, "--pgo-profile", profile)
        if not performance_configuration_matches(self.source, self.lock, sdk):
            raise ValueError("GN arguments contain unpinned overrides; review args.gn before building a published engine")
        self.script("build-chromium-baseline.py", "--source", self.source, "--ninja", ninja,
                    "--jobs", jobs, "--min-free-gib", reserve)
        smoke_engine(self.source, self.root, self.lock["chromium"]["version"])


def smoke_engine(source, workspace, version):
    browser = source / "out/CrestBaseline/Chromium.app/Contents/MacOS/Chromium"
    with (browser.parent.parent / "Info.plist").open("rb") as stream:
        actual = plistlib.load(stream)["CFBundleShortVersionString"]
    if version != actual:
        raise ValueError(f"Built engine reports an unexpected version: {actual}")
    scratch = workspace / "scratch"
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="smoke-", dir=scratch) as profile:
        page = "data:text/html,<script>document.title='crest-'+(6*7)</script>"
        process = subprocess.Popen([str(browser), "--headless", "--disable-gpu", "--disable-background-networking",
            "--no-first-run", "--no-default-browser-check", "--timeout=10000",
            f"--user-data-dir={profile}", "--dump-dom", page], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, start_new_session=True)
        output, errors = bytearray(), bytearray()
        try:
            deadline = time.monotonic() + 30
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
            except ProcessLookupError:
                pass
            if process.poll() is None:
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()


def performance_configuration_matches(source, lock, sdk=None):
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

    try:
        values = assignments((source / "out/CrestBaseline/args.gn").read_text())
    except (ValueError, OSError):
        return False
    expected_flags = {**lock["buildArguments"], **lock["performanceBuildArguments"]}
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
    return (profile.is_file() and profile.name == expected["pgoProfile"]
            and sha256(profile) == expected["pgoSHA256"]
            and (source / "chrome/build/mac-arm.pgo.txt").read_text().strip() == profile.name)


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


def deps_cipd(deps_text, prefix):
    """{checkout path: (package, version)} for the CIPD packages a DEPS file pins on this host."""
    scope = {}
    exec(deps_text, {"Var": lambda name: "{" + name + "}", "Str": str}, scope)
    variables = scope.get("vars", {})
    packages = {}
    for path, dependency in scope["deps"].items():
        if isinstance(dependency, dict) and dependency.get("dep_type") == "cipd":
            for item in dependency["packages"]:
                version = item["version"].format(**variables) if item["version"].startswith("{") else item["version"]
                package = item["package"].replace("${{platform}}", "mac-arm64")
                packages[prefix + path] = (package, version)
    return packages


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
    wanted = {f"chromium-{version}/DEPS": "",
              f"chromium-{version}/third_party/dawn/DEPS": "src/third_party/dawn/",
              f"chromium-{version}/third_party/devtools-frontend/src/DEPS": "src/third_party/devtools-frontend/src/",
              f"chromium-{version}/chrome/build/mac-arm.pgo.txt": None}
    found = {}
    with tarfile.open(archive) as stream:
        for member in stream:
            if member.name in wanted and member.isfile():
                found[member.name] = stream.extractfile(member).read().decode()
                if len(found) == len(wanted):
                    break
    if len(found) != len(wanted):
        raise ValueError("The source archive is missing its DEPS or PGO profile name")
    packages = {}
    for name, prefix in wanted.items():
        if prefix is not None:
            packages.update(deps_cipd(found[name], prefix))
    for path, pinned in lock["cipd"].items():
        if path not in packages:
            raise ValueError(f"DEPS no longer pins {path}")
        package, package_version = packages[path]
        if (package, package_version) != (pinned["package"], pinned["version"]):
            lock["cipd"][path] = {"package": package, "version": package_version,
                                  "sha256": resolve_cipd(package, package_version)}
    profile_name = found[f"chromium-{version}/chrome/build/mac-arm.pgo.txt"].strip()
    profile = download_profile(root, {"pgoProfile": profile_name})
    lock["performanceInputs"].update(pgoProfile=profile_name, pgoSHA256=sha256(profile))
    return lock


def prepare_update(repo, root, version):
    lock_path, host_path = repo / ENGINE / "source.lock.json", repo / ENGINE / "host-inputs.json"
    original_lock, original_host = lock_path.read_bytes(), host_path.read_bytes()
    pinned = Workspace(root, repo).directory.name
    try:
        write_json(lock_path, candidate_lock(repo, root, version))
        workspace = Workspace(root, repo)
        # Every update needs a new source. Keep only the checkout's own, which its
        # branch still builds from, and this update's; any other is superseded.
        for name in prune_sources(root, {pinned, workspace.directory.name}):
            print(f"Removed superseded Chromium source {name}", flush=True)
        workspace.prepare()
        refresh_host_inputs(repo, workspace.source, workspace.directory / "host.json")
        return Workspace(root, repo)
    except BaseException:
        lock_path.write_bytes(original_lock)
        host_path.write_bytes(original_host)
        raise
