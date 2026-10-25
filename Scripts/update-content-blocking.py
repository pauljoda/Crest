#!/usr/bin/env python3
"""Build Crest's native EasyList/EasyPrivacy snapshot with an offline converter."""

import argparse
import gzip
import json
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
SOURCES = {
    "easylist": "https://easylist-downloads.adblockplus.org/easylist.txt",
    "easyprivacy": "https://easylist-downloads.adblockplus.org/easyprivacy.txt",
}
RESOURCE_TYPES = [
    "child-document", "image", "style-sheet", "script", "font", "raw",
    "svg-document", "media", "popup", "ping", "fetch", "websocket", "csp-report", "other",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--converter", required=True, type=Path, help="SafariConverterLib v4.3.1 ConverterTool")
    args = parser.parse_args()
    versions = {}
    filters = []
    for name, url in SOURCES.items():
        with urllib.request.urlopen(url, timeout=45) as response:
            text = response.read(8 * 1024 * 1024 + 1).decode("utf-8")
        match = re.search(r"^! Version: (\d+)$", text, re.MULTILINE)
        if not match or len(text.splitlines()) < 10000 or len(text.encode()) > 8 * 1024 * 1024:
            raise ValueError(f"Incomplete {name} source")
        versions[name] = match[1]
        filters.extend(line for line in text.splitlines() if line and not line.startswith(("!", "[")))
    with tempfile.TemporaryDirectory(prefix="crest-content-blocking-") as directory:
        path = Path(directory)
        (path / "input.txt").write_text("\n".join(filters))
        subprocess.run([
            str(args.converter.resolve()), "convert", "--safari-version", "26.0",
            "--advanced-blocking", "false", "--input-path", str(path / "input.txt"),
            "--safari-rules-json-path", str(path / "output.json"),
        ], check=True)
        rules = json.loads((path / "output.json").read_text())
    if not 1000 <= len(rules) <= 150000:
        raise ValueError("Unexpected native rule count")
    for rule in rules:
        action = rule["action"]["type"]
        if action not in {"block", "css-display-none", "ignore-previous-rules"}:
            raise ValueError(f"Unexpected native action: {action}")
        if action == "block":
            # Preserve top-level navigation even when a filter matches its URL.
            trigger = rule["trigger"]
            types = trigger.get("resource-type", RESOURCE_TYPES)
            trigger["resource-type"] = [kind for kind in types if kind != "document"]
    rules = [rule for rule in rules if rule["action"]["type"] != "block" or rule["trigger"]["resource-type"]]
    # Generic recovery-wall service, also blocked by uBlock Origin. No site
    # names, downloaded scriptlets, or broad consent-dialog suppression.
    rules.append({
        "trigger": {
            "url-filter": r"^[^:]+://+([^:/]+\.)?fundingchoicesmessages\.google\.com[:/]",
            "load-type": ["third-party"], "resource-type": RESOURCE_TYPES,
        },
        "action": {"type": "block"},
    })
    snapshot = {"version": int(max(versions.values())), "rules": rules}
    destination = ROOT / "CrestCore/src/CrestCore/Contracts/ContentBlocking/ContentBlockingRules.json.gz"
    data = (json.dumps(snapshot, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
    destination.write_bytes(gzip.compress(data, mtime=0))
    catalog_path = ROOT / "Config/ThirdPartyDependencies.json"
    catalog = json.loads(catalog_path.read_text())
    for item in catalog["bundledData"]:
        if item["identity"] in versions:
            item["version"] = versions[item["identity"]]
    catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n")
    print(f"Updated {len(rules)} native rules: {versions}")


if __name__ == "__main__":
    main()
