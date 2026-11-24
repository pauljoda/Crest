#!/usr/bin/env python3
"""Package Crest for Windows: stage the folder Setup installs, then compile Setup.

The staged Application folder holds the engine's runtime files, flat as the
engine's build keeps them and picked by Chromium's own installer list
(chrome/installer/mini_installer/chrome.release); the native core; the
interface's built files under `interface`; Crest's licenses; and
`update.json`, which names this build, the channel it updates on, where its
feeds are and the key its updates are signed with. A launch finds the core
and the interface beside chrome.exe, which makes it the installed product.

Setup is compiled from CrestDesktop/installer/Crest.iss with Inno Setup's
ISCC. With --sign, every executable and library Crest ships, Setup and its
uninstaller are signed by the command given, in which `$f` names the file.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

from windows_update_feed import RELEASE_PUBLIC_KEY

REPOSITORY = pathlib.Path(__file__).resolve().parents[1]
INSTALLER_SCRIPT = REPOSITORY / "CrestDesktop/installer/Crest.iss"
VERSION_FILE = REPOSITORY / "Config/Version.xcconfig"

RELEASE_FEED_BASE = "https://updates.crestbrowser.com/"
CHANNELS = ("stable", "nightly", "development")

# The engine's runtime, by Chromium's installer list. Every file a launch
# cannot do without is required; the rest ship when the build made them.
REQUIRED_ENGINE_FILES = (
    "chrome.exe",
    "chrome.dll",
    "chrome_elf.dll",
    "chrome_100_percent.pak",
    "chrome_200_percent.pak",
    "resources.pak",
    "icudtl.dat",
    "libEGL.dll",
    "libGLESv2.dll",
)
OPTIONAL_ENGINE_FILES = (
    "chrome_proxy.exe",
    "chrome_pwa_launcher.exe",
    "chrome_wer.dll",
    "d3dcompiler_47.dll",
    "dxcompiler.dll",
    "dxil.dll",
    "eventlog_provider.dll",
    "ffmpeg.dll",
    "notification_helper.exe",
    "vk_swiftshader.dll",
    "vk_swiftshader_icd.json",
    "vulkan-1.dll",
)
# One of the V8 snapshots, whichever the build uses.
SNAPSHOTS = ("v8_context_snapshot.bin", "snapshot_blob.bin")
ENGINE_FOLDERS = ("locales", "MEIPreload", "IwaKeyDistribution", "Extensions")
# chrome.exe names its version's assembly, whose manifest is named for it.
VERSION_MANIFEST = re.compile(r"^\d+\.\d+\.\d+\.\d+\.manifest$")
LICENSES = ("LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md")


class PackagingError(Exception):
    pass


def marketing_version() -> str:
    match = re.search(r"^MARKETING_VERSION\s*=\s*(\S+)\s*$", VERSION_FILE.read_text(encoding="utf-8"), re.MULTILINE)
    if not match:
        raise PackagingError(f"{VERSION_FILE} names no MARKETING_VERSION")
    return match[1]


def feed_name(channel: str) -> str:
    """The Windows feed a channel's builds are listed in, as the Mac's
    appcast names carry its engine's suffix: Stable's and Nightly's share
    one, Development has its own."""
    return "appcast-development-windows.xml" if channel == "development" else "appcast-windows.xml"


def executable_version(path: pathlib.Path) -> str | None:
    """The file version in an executable's version resource, as Explorer shows it."""
    if os.name != "nt":
        return None
    import ctypes

    version = ctypes.WinDLL("version")
    size = version.GetFileVersionInfoSizeW(str(path), None)
    resource = ctypes.create_string_buffer(size)
    if not size or not version.GetFileVersionInfoW(str(path), 0, size, resource):
        return None
    fixed, length = ctypes.c_void_p(), ctypes.c_uint()
    if not version.VerQueryValueW(resource, "\\", ctypes.byref(fixed), ctypes.byref(length)) or length.value < 16:
        return None
    # VS_FIXEDFILEINFO: its signature and structure version, then the file version's high and low halves.
    _, _, high, low = ctypes.cast(fixed, ctypes.POINTER(ctypes.c_uint32 * 4)).contents
    return f"{high >> 16}.{high & 0xFFFF}.{low >> 16}.{low & 0xFFFF}"


def engine_files(engine: pathlib.Path) -> list[pathlib.Path]:
    """The engine's runtime files under `engine`, relative to it."""
    missing = [name for name in REQUIRED_ENGINE_FILES if not (engine / name).is_file()]
    snapshots = [name for name in SNAPSHOTS if (engine / name).is_file()]
    manifests = [path.name for path in engine.iterdir() if path.is_file() and VERSION_MANIFEST.match(path.name)]
    if len(manifests) > 1 and (engine / "chrome.exe").is_file():
        # An output that built an earlier Chromium keeps that version's
        # manifest beside the current one; chrome.exe loads its own version's.
        current = f"{executable_version(engine / 'chrome.exe')}.manifest"
        manifests = [name for name in manifests if name == current]
    if not snapshots:
        missing.append(" or ".join(SNAPSHOTS))
    if len(manifests) != 1:
        raise PackagingError(f"The engine must hold exactly one version manifest for chrome.exe, not {manifests or 'none'}")
    if not (engine / "locales").is_dir() or not any((engine / "locales").glob("*.pak")):
        missing.append("locales\\*.pak")
    if missing:
        raise PackagingError(f"The engine at {engine} lacks {', '.join(missing)}")
    names = [*REQUIRED_ENGINE_FILES, *snapshots, *manifests]
    names += [name for name in OPTIONAL_ENGINE_FILES if (engine / name).is_file()]
    files = [pathlib.Path(name) for name in names]
    for folder in ENGINE_FOLDERS:
        root = engine / folder
        if root.is_dir():
            files += sorted(path.relative_to(engine) for path in root.rglob("*") if path.is_file())
    return files


def update_settings(version: str, build: int, channel: str, feed_base: str, public_key: str) -> dict:
    """What update.json tells the engine and the interface about this build."""
    if not feed_base.endswith("/"):
        feed_base += "/"
    return {
        "version": version,
        "build": build,
        "channel": channel,
        "feedBase": feed_base,
        "publicKey": public_key,
    }


def stage(engine: pathlib.Path, core: pathlib.Path, interface: pathlib.Path, settings: dict,
          destination: pathlib.Path) -> None:
    if not core.is_file() or core.name != "CrestCore.Native.dll":
        raise PackagingError(f"{core} is not CrestCore.Native.dll")
    if not (interface / "index.html").is_file():
        raise PackagingError(f"{interface} holds no built interface (index.html)")
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    for relative in engine_files(engine):
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(engine / relative, target)
    shutil.copy2(core, destination / core.name)
    # The interface's source maps stay with the build that made them.
    shutil.copytree(interface, destination / "interface", ignore=shutil.ignore_patterns("*.map"))
    licenses = destination / "licenses"
    licenses.mkdir()
    for name in LICENSES:
        shutil.copy2(REPOSITORY / name, licenses / name)
    (destination / "update.json").write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")


def sign_files(command: str, files: list[pathlib.Path]) -> None:
    """Runs `command` for each file as Inno Setup runs its sign tool: a
    command line in which `$f` is the file, quoted."""
    for file in files:
        subprocess.run(command.replace("$f", f'"{file}"'), shell=True, check=True)


def find_iscc(explicit: str | None) -> pathlib.Path:
    candidates = [explicit, os.environ.get("ISCC"), shutil.which("ISCC"), shutil.which("iscc")]
    for variable in ("ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA"):
        root = os.environ.get(variable)
        for release in ("Inno Setup 7", "Inno Setup 6"):
            if root:
                candidates.append(str(pathlib.Path(root) / release / "ISCC.exe"))
                candidates.append(str(pathlib.Path(root) / "Programs" / release / "ISCC.exe"))
    for candidate in candidates:
        if candidate and pathlib.Path(candidate).is_file():
            return pathlib.Path(candidate)
    raise PackagingError("Inno Setup's ISCC.exe was not found; pass --iscc or set ISCC")


def compile_setup(iscc: pathlib.Path, staged: pathlib.Path, version: str, build: int, output: pathlib.Path,
                  name: str, sign: str | None) -> pathlib.Path:
    output.mkdir(parents=True, exist_ok=True)
    arguments = [
        str(iscc),
        "/Q",
        f"/DCrestVersion={version}",
        f"/DCrestBuild={build}",
        f"/DCrestSource={staged}",
        f"/DCrestOutput={output}",
        f"/DCrestOutputName={name}",
    ]
    if sign:
        # Inno Setup signs Setup and the uninstaller it carries.
        arguments += ["/DCrestSignTool", f"/Screst={sign}"]
    subprocess.run([*arguments, str(INSTALLER_SCRIPT)], check=True)
    installer = output / f"{name}.exe"
    if not installer.is_file():
        raise PackagingError(f"ISCC made no {installer}")
    return installer


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--engine", type=pathlib.Path, required=True,
                        help="The engine's runtime: a build's output folder or an unpacked engine archive")
    parser.add_argument("--core", type=pathlib.Path, required=True, help="CrestCore.Native.dll")
    parser.add_argument("--interface", type=pathlib.Path, required=True, help="The interface's built files")
    parser.add_argument("--build", type=int, required=True, help="The build number updates compare")
    parser.add_argument("--channel", choices=CHANNELS, default="development")
    parser.add_argument("--version", default=None, help="The marketing version (default: Config/Version.xcconfig)")
    parser.add_argument("--feed-base", default=RELEASE_FEED_BASE, help="Where the update feeds are")
    parser.add_argument("--public-key", default=RELEASE_PUBLIC_KEY,
                        help="The Ed25519 key updates are signed with, base64")
    parser.add_argument("--output", type=pathlib.Path, required=True, help="Where Setup and the staged folder go")
    parser.add_argument("--name", default=None, help="Setup's file name, without .exe")
    parser.add_argument("--iscc", default=None, help="Inno Setup's ISCC.exe")
    parser.add_argument("--sign", default=None, help="A signing command, with $f for the file")
    parser.add_argument("--stage-only", action="store_true", help="Stage the Application folder without Setup")
    args = parser.parse_args()

    try:
        version = args.version or marketing_version()
        settings = update_settings(version, args.build, args.channel, args.feed_base, args.public_key)
        staged = args.output.resolve() / "Application"
        stage(args.engine.resolve(), args.core.resolve(), args.interface.resolve(), settings, staged)
        if args.sign:
            sign_files(args.sign, sorted(path for path in staged.rglob("*") if path.suffix.lower() in (".exe", ".dll")))
        if args.stage_only:
            print(staged)
            return 0
        name = args.name or f"Crest-Setup-{version}-{args.build}"
        installer = compile_setup(find_iscc(args.iscc), staged, version, args.build, args.output.resolve(), name,
                                  args.sign)
        print(installer)
        return 0
    except (PackagingError, subprocess.CalledProcessError) as error:
        print(f"package-windows: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
