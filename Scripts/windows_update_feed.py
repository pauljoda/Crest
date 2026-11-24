#!/usr/bin/env python3
"""Sign a Windows installer and list it in Crest's Windows update feed.

Installed Windows builds read a Sparkle-format appcast from the updates
branch, as the Mac's do: `appcast-windows.xml` for Stable and Nightly, and
`appcast-development-windows.xml` for Development. Each item's enclosure is
the installer on GitHub Releases, marked `sparkle:os="windows"`, with its
length and its Ed25519 signature (`sparkle:edSignature`) by the same key that
signs the Mac's updates. Crest's engine checks both before it runs an
installer. Sparkle's own generate_appcast runs only on a Mac, so this writes
the Windows feed itself.

The private key is read from standard input, or a file, as Sparkle's tools
read it: base64 of the 32-byte seed, or of Sparkle's older 96-byte form (the
64-byte expanded key and the public key).
"""

from __future__ import annotations

import argparse
import base64
import email.utils
import hashlib
import pathlib
import sys
import time
import urllib.parse
import xml.etree.ElementTree as ElementTree

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC = "http://purl.org/dc/elements/1.1/"
ElementTree.register_namespace("sparkle", SPARKLE)
ElementTree.register_namespace("dc", DC)

CHANNELS = ("stable", "nightly", "development")
# The key Crest's releases are signed with, which the Mac app names as its
# SUPublicEDKey: Windows updates are signed by the same Ed25519 key.
RELEASE_PUBLIC_KEY = "x/dBoNAjtYIa+JKUUHY48NYepidnElHTo3w2VMyqzLA="
# Windows 10 2004, the oldest Windows Crest's Chromium runs on.
MINIMUM_SYSTEM_VERSION = "10.0.19041"
CHUNK = 1 << 20


class FeedError(Exception):
    pass


# --- Ed25519 (RFC 8032, section 5.1) ---------------------------------------

_P = 2**255 - 19
_L = 2**252 + 27742317777372353535851937790883648493
_D = -121665 * pow(121666, _P - 2, _P) % _P
_SQRT_M1 = pow(2, (_P - 1) // 4, _P)


def _inverse(value: int) -> int:
    return pow(value, _P - 2, _P)


def _add(first: tuple, second: tuple) -> tuple:
    a = (first[1] - first[0]) * (second[1] - second[0]) % _P
    b = (first[1] + first[0]) * (second[1] + second[0]) % _P
    c = 2 * first[3] * second[3] * _D % _P
    d = 2 * first[2] * second[2] % _P
    e, f, g, h = b - a, d - c, d + c, b + a
    return (e * f % _P, g * h % _P, f * g % _P, e * h % _P)


def _multiply(scalar: int, point: tuple) -> tuple:
    result = (0, 1, 1, 0)
    while scalar > 0:
        if scalar & 1:
            result = _add(result, point)
        point = _add(point, point)
        scalar >>= 1
    return result


def _equal(first: tuple, second: tuple) -> bool:
    return ((first[0] * second[2] - second[0] * first[2]) % _P == 0
            and (first[1] * second[2] - second[1] * first[2]) % _P == 0)


def _recover_x(y: int, sign: int) -> int | None:
    if y >= _P:
        return None
    x2 = (y * y - 1) * _inverse(_D * y * y + 1)
    if x2 == 0:
        return None if sign else 0
    x = pow(x2, (_P + 3) // 8, _P)
    if (x * x - x2) % _P != 0:
        x = x * _SQRT_M1 % _P
    if (x * x - x2) % _P != 0:
        return None
    if (x & 1) != sign:
        x = _P - x
    return x


_BASE_Y = 4 * _inverse(5) % _P
_BASE = (_recover_x(_BASE_Y, 0), _BASE_Y, 1, _recover_x(_BASE_Y, 0) * _BASE_Y % _P)


def _compress(point: tuple) -> bytes:
    z = _inverse(point[2])
    x, y = point[0] * z % _P, point[1] * z % _P
    return int.to_bytes(y | ((x & 1) << 255), 32, "little")


def _decompress(encoded: bytes) -> tuple | None:
    if len(encoded) != 32:
        return None
    y = int.from_bytes(encoded, "little")
    sign = y >> 255
    y &= (1 << 255) - 1
    x = _recover_x(y, sign)
    return None if x is None else (x, y, 1, x * y % _P)


def _digest_scalar(parts: list, path: pathlib.Path | None = None) -> int:
    """SHA-512 of `parts` and then the file at `path`, as a scalar mod L."""
    digest = hashlib.sha512()
    for part in parts:
        digest.update(part)
    if path is not None:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(CHUNK), b""):
                digest.update(chunk)
    return int.from_bytes(digest.digest(), "little") % _L


class SigningKey:
    """An Ed25519 private key, as its clamped scalar and the hash prefix
    that derives each signature's nonce."""

    def __init__(self, scalar: int, prefix: bytes):
        self.scalar = scalar
        self.prefix = prefix
        self.public_key = _compress(_multiply(scalar, _BASE))

    @classmethod
    def from_seed(cls, seed: bytes) -> SigningKey:
        expanded = hashlib.sha512(seed).digest()
        return cls.from_expanded(expanded)

    @classmethod
    def from_expanded(cls, expanded: bytes) -> SigningKey:
        scalar = int.from_bytes(expanded[:32], "little")
        scalar &= (1 << 254) - 8
        scalar |= 1 << 254
        return cls(scalar, expanded[32:64])

    @classmethod
    def from_sparkle(cls, text: str) -> SigningKey:
        """The key as Sparkle's tools hold it: base64 of the 32-byte seed,
        or of the older expanded key followed by the public key."""
        try:
            raw = base64.b64decode(text.strip(), validate=True)
        except ValueError as error:
            raise FeedError("The private key is not base64") from error
        if len(raw) == 32:
            return cls.from_seed(raw)
        if len(raw) in (64, 96):
            key = cls.from_expanded(raw[:64])
            if len(raw) == 96 and raw[64:] != key.public_key:
                raise FeedError("The private key's public half does not match it")
            return key
        raise FeedError(f"A {len(raw)}-byte private key is no Ed25519 key Sparkle writes")

    def sign(self, message: bytes = b"", path: pathlib.Path | None = None) -> bytes:
        """The signature of `message` followed by the file at `path`."""
        nonce = _digest_scalar([self.prefix, message], path)
        encoded_nonce = _compress(_multiply(nonce, _BASE))
        challenge = _digest_scalar([encoded_nonce, self.public_key, message], path)
        return encoded_nonce + int.to_bytes((nonce + challenge * self.scalar) % _L, 32, "little")


def verify(public_key: bytes, signature: bytes, message: bytes = b"", path: pathlib.Path | None = None) -> bool:
    """Whether `signature` is `public_key`'s over `message` and then the file
    at `path`."""
    if len(public_key) != 32 or len(signature) != 64:
        return False
    point = _decompress(public_key)
    nonce = _decompress(signature[:32])
    if point is None or nonce is None:
        return False
    proof = int.from_bytes(signature[32:], "little")
    if proof >= _L:
        return False
    challenge = _digest_scalar([signature[:32], public_key, message], path)
    return _equal(_multiply(proof, _BASE), _add(nonce, _multiply(challenge, point)))


# --- The feed ---------------------------------------------------------------

def _tag(name: str) -> str:
    return f"{{{SPARKLE}}}{name}"


def _channel_of(item: ElementTree.Element) -> str:
    return (item.findtext(_tag("channel")) or "stable").strip()


def _build_of(item: ElementTree.Element) -> int:
    try:
        return int((item.findtext(_tag("version")) or "").strip())
    except ValueError:
        return -1


def _allows_update_url(url: str) -> bool:
    """Where the engine takes an update from (crest_desktop_updates.cc): https,
    or this device, where a local build serves its own feed."""
    parts = urllib.parse.urlsplit(url)
    if parts.scheme == "https":
        return bool(parts.hostname)
    return parts.scheme == "http" and parts.hostname in ("localhost", "127.0.0.1", "::1")


def empty_feed() -> ElementTree.Element:
    rss = ElementTree.Element("rss", {"version": "2.0"})
    channel = ElementTree.SubElement(rss, "channel")
    ElementTree.SubElement(channel, "title").text = "Crest for Windows"
    ElementTree.SubElement(channel, "link").text = "https://crestbrowser.com/"
    ElementTree.SubElement(channel, "description").text = "Crest for Windows updates"
    ElementTree.SubElement(channel, "language").text = "en"
    return rss


def feed_item(version: str, build: int, channel: str, url: str, length: int, signature: str,
              release_notes_url: str | None, published: float) -> ElementTree.Element:
    if channel not in CHANNELS:
        raise FeedError(f"No channel {channel!r}")
    if not _allows_update_url(url):
        raise FeedError(f"An update's address must be https, or this device's for a local test: {url}")
    item = ElementTree.Element("item")
    ElementTree.SubElement(item, "title").text = version
    ElementTree.SubElement(item, "pubDate").text = email.utils.formatdate(published, usegmt=True)
    ElementTree.SubElement(item, _tag("version")).text = str(build)
    ElementTree.SubElement(item, _tag("shortVersionString")).text = version
    # Stable's items carry no channel, as Sparkle's default channel; the
    # others name theirs, which only a build on that channel accepts.
    if channel != "stable":
        ElementTree.SubElement(item, _tag("channel")).text = channel
    ElementTree.SubElement(item, _tag("minimumSystemVersion")).text = MINIMUM_SYSTEM_VERSION
    if release_notes_url:
        ElementTree.SubElement(item, _tag("releaseNotesLink")).text = release_notes_url
    ElementTree.SubElement(item, "enclosure", {
        "url": url,
        "length": str(length),
        "type": "application/octet-stream",
        _tag("os"): "windows",
        _tag("edSignature"): signature,
    })
    return item


def add_item(feed: ElementTree.Element, item: ElementTree.Element, maximum: int) -> None:
    """Lists `item` first in `feed`, in place of any item for the same build,
    keeping at most `maximum` items of its channel (0 keeps every one).
    Other channels' items stay as they are."""
    channel_element = feed.find("channel")
    if channel_element is None:
        raise FeedError("The feed has no channel")
    build, channel = _build_of(item), _channel_of(item)
    for existing in channel_element.findall("item"):
        if _build_of(existing) == build and _channel_of(existing) == channel:
            channel_element.remove(existing)
    children = list(channel_element)
    first_item = next((index for index, child in enumerate(children) if child.tag == "item"), len(children))
    channel_element.insert(first_item, item)
    if maximum > 0:
        same = sorted((existing for existing in channel_element.findall("item") if _channel_of(existing) == channel),
                      key=_build_of, reverse=True)
        for stale in same[maximum:]:
            channel_element.remove(stale)


def write_feed(feed: ElementTree.Element, output: pathlib.Path) -> None:
    ElementTree.indent(feed, space="  ")
    output.write_bytes(ElementTree.tostring(feed, encoding="utf-8", xml_declaration=True) + b"\n")


def _read_key(source: str) -> SigningKey:
    text = sys.stdin.read() if source == "-" else pathlib.Path(source).read_text(encoding="utf-8")
    return SigningKey.from_sparkle(text)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    sign = commands.add_parser("sign", help="Print an installer's signature")
    sign.add_argument("installer", type=pathlib.Path)
    sign.add_argument("--key-file", default="-", help="The private key's file, or - for standard input")

    publish = commands.add_parser("publish", help="Sign an installer and list it in a feed")
    publish.add_argument("installer", type=pathlib.Path)
    publish.add_argument("--key-file", default="-", help="The private key's file, or - for standard input")
    publish.add_argument("--public-key", default=RELEASE_PUBLIC_KEY,
                         help="The key builds verify with, base64 (default: the release key)")
    publish.add_argument("--feed", type=pathlib.Path, help="The feed as published, if there is one")
    publish.add_argument("--output", type=pathlib.Path, required=True)
    publish.add_argument("--version", required=True)
    publish.add_argument("--build", type=int, required=True)
    publish.add_argument("--channel", choices=CHANNELS, required=True)
    publish.add_argument("--url", required=True, help="Where the installer is downloaded from")
    publish.add_argument("--release-notes-url")
    publish.add_argument("--maximum-versions", type=int, default=0,
                         help="Items of the channel to keep, newest first (0 keeps every one)")

    check = commands.add_parser("verify", help="Check an installer's signature")
    check.add_argument("installer", type=pathlib.Path)
    check.add_argument("--public-key", required=True)
    check.add_argument("--signature", required=True)

    args = parser.parse_args()
    try:
        if args.command == "verify":
            valid = verify(base64.b64decode(args.public_key), base64.b64decode(args.signature), path=args.installer)
            print("valid" if valid else "invalid")
            return 0 if valid else 1
        key = _read_key(args.key_file)
        signature = key.sign(path=args.installer)
        if args.command == "sign":
            print(base64.b64encode(signature).decode())
            return 0
        if base64.b64decode(args.public_key) != key.public_key:
            raise FeedError("The private key is not the one builds verify updates with")
        if not verify(key.public_key, signature, path=args.installer):
            raise FeedError("The installer's signature does not verify")
        feed = ElementTree.parse(args.feed).getroot() if args.feed and args.feed.is_file() else empty_feed()
        item = feed_item(args.version, args.build, args.channel, args.url, args.installer.stat().st_size,
                         base64.b64encode(signature).decode(), args.release_notes_url, time.time())
        add_item(feed, item, args.maximum_versions)
        write_feed(feed, args.output)
        return 0
    except (FeedError, OSError, ElementTree.ParseError) as error:
        print(f"windows_update_feed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
