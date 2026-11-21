#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
derived_data="${CREST_DERIVED_DATA_PATH:-}"
owns_derived_data=0
if [[ -z "$derived_data" ]]; then
  derived_data="$(mktemp -d /private/tmp/crest-validation.XXXXXX)"
  owns_derived_data=1
else
  mkdir -p "$derived_data"
fi

cleanup() {
  if (( owns_derived_data )) && [[ -n "${derived_data:-}" && -d "$derived_data" ]]; then
    find "$derived_data" -depth -delete
  fi
}
trap cleanup EXIT INT TERM HUP

cd "$repository_root"
# The script tests need Python 3.11 or newer; Xcode's own python3 is older.
python=""
for candidate in python3.13 python3.12 python3.11 python3; do
  if command -v "$candidate" >/dev/null \
    && "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null; then
    python="$candidate"
    break
  fi
done
[[ -n "$python" ]] || { print -u2 "error: the script tests need Python 3.11 or newer on PATH."; exit 69; }
"$python" -m unittest discover -s Scripts/Tests
Scripts/bootstrap.sh

xcodebuild \
  -project Crest.xcodeproj \
  -scheme Crest \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data" \
  test

ios_destination="${CREST_IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=latest}"
xcodebuild \
  -project Crest.xcodeproj \
  -scheme CrestMobile \
  -destination "$ios_destination" \
  -derivedDataPath "$derived_data" \
  -only-testing:CrestMobileTests \
  test
