#!/bin/bash
set -euo pipefail
probe_source="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$probe_source/../../.." && pwd)"
for probe_argument in "$@"; do
  case "$probe_argument" in
    --enable-native|--flyout|--capture) ;;
    *) printf 'Usage: bash %s [--enable-native | --flyout] [--capture]\n' "$0" >&2; exit 2 ;;
  esac
done
if [[ " $* " == *" --enable-native "* && " $* " == *" --flyout "* ]]; then
  printf '%s\n' 'Choose either --enable-native or --flyout.' >&2
  exit 2
fi
probe_build="$(mktemp -d /tmp/crest-desktop-pip.XXXXXX)"
probe_app="$probe_build/CrestPiPProbe.app"
mkdir -p "$probe_app/Contents/MacOS" "$probe_app/Contents/Resources"
cp "$probe_source/probe.html" "$repo_root/CrestTestFixtures/sample.mp4" "$probe_app/Contents/Resources/"
cat > "$probe_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.pauldavis.crest.pip-probe</string>
<key>CFBundleName</key><string>CrestPiPProbe</string>
<key>CFBundleExecutable</key><string>CrestPiPProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
xcrun swiftc -swift-version 6 -target arm64-apple-macos26.1 -framework AppKit -framework WebKit "$probe_source/main.swift" -o "$probe_app/Contents/MacOS/CrestPiPProbe"
codesign --force --sign - --options runtime "$probe_app" >&2
printf 'Probe artifact: %s\n' "$probe_app" >&2
"$probe_app/Contents/MacOS/CrestPiPProbe" "$@"
