#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h:h}"
fixture_root="$(mktemp -d /private/tmp/crest-cache-hygiene-tests.XXXXXX)"

cleanup() {
  if [[ -d "$fixture_root" ]]; then
    find "$fixture_root" -depth -delete
  fi
}
trap cleanup EXIT INT TERM HUP

mkdir -p "$fixture_root/DerivedData/Build"

if "$repository_root/Scripts/validate-cache-hygiene.sh" "$fixture_root" >/dev/null 2>&1; then
  print -u2 "Expected repository-owned Derived Data to fail validation."
  exit 1
fi

find "$fixture_root/DerivedData" -depth -delete
"$repository_root/Scripts/validate-cache-hygiene.sh" "$fixture_root" >/dev/null

mkdir "$fixture_root/Uncommitted.xcresult"

if "$repository_root/Scripts/validate-cache-hygiene.sh" "$fixture_root" >/dev/null 2>&1; then
  print -u2 "Expected an orphaned result bundle to fail validation."
  exit 1
fi

print "Cache-hygiene validation tests passed."
