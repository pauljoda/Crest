#!/bin/zsh
set -euo pipefail

script_repository_root="${0:A:h:h}"
repository_root="${CREST_PERIPHERY_REPOSITORY_ROOT:-$script_repository_root}"
periphery="${CREST_PERIPHERY:-}"

if [[ -z "$periphery" ]]; then
  periphery="$(command -v periphery || true)"
fi

if [[ -z "$periphery" || ! -x "$periphery" ]]; then
  print -u2 "Periphery is not installed. Install it with:"
  print -u2 "  brew install periphery"
  print -u2 "This audit produces evidence for review; it never authorizes automatic deletion."
  exit 69
fi

project="$repository_root/Crest.xcodeproj"
[[ -d "$project" ]] \
  || { print -u2 "error: Crest.xcodeproj is missing; run XcodeGen first."; exit 2; }

print "Periphery findings are evidence, not deletion instructions."
print "Confirm references, builds, and tests before removing declarations; dynamic WebKit and AppKit entry points need manual review."
print "Periphery builds into its own cache under ~/Library/Caches; remove it when the audit is done."

# The Chromium product's callers count as uses only when its scheme is scanned
# too; the Crest scheme alone builds the WebKit app.
typeset -a schemes=(Crest CrestChromiumUIProduct CrestMobile)
typeset -a configurations=(Debug Release)

for scheme in "${schemes[@]}"; do
  if [[ "$scheme" == "CrestMobile" ]]; then
    destination="generic/platform=iOS Simulator"
  else
    destination="platform=macOS,arch=arm64"
  fi

  for configuration in "${configurations[@]}"; do
    print "Auditing $scheme ($configuration)..."
    "$periphery" scan \
      --project "$project" \
      --schemes "$scheme" \
      --format xcode \
      --retain-objc-accessible \
      --retain-codable-properties \
      -- \
      -configuration "$configuration" \
      -destination "$destination"
  done
done

print "Completed the Crest Periphery evidence matrix."
