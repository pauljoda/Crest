#!/bin/sh

set -eu

if [ "${CI_XCODE_CLOUD:-FALSE}" != "TRUE" ]; then
    echo "Crest Xcode Cloud guard skipped outside Xcode Cloud."
    exit 0
fi

fail() {
    echo "error: $1" >&2
    exit 64
}

case "${CI_START_CONDITION:-}" in
    manual|manual_rebuild)
        ;;
    *)
        fail "Crest release archives must be started manually; received '${CI_START_CONDITION:-unset}'."
        ;;
esac

[ "${CI_XCODEBUILD_ACTION:-}" = "archive" ] \
    || fail "The manual Crest workflow only permits archive actions."

case "${CI_PRODUCT_PLATFORM:-}" in
    iOS)
        expected_scheme="CrestMobile"
        ;;
    macOS)
        expected_scheme="Crest"
        ;;
    *)
        fail "Unsupported Xcode Cloud platform '${CI_PRODUCT_PLATFORM:-unset}'."
        ;;
esac

[ "${CI_XCODE_SCHEME:-}" = "$expected_scheme" ] \
    || fail "${CI_PRODUCT_PLATFORM} archives must use the ${expected_scheme} scheme."

xcode_version="$(xcodebuild -version | awk 'NR == 1 { print $2 }')"
xcode_build="$(xcodebuild -version | awk 'NR == 2 { print $3 }')"
xcode_major="${xcode_version%%.*}"
case "$xcode_major" in
    ''|*[!0-9]*)
        fail "Unable to determine the Xcode major version from '$xcode_version'."
        ;;
esac
[ "$xcode_major" -ge 26 ] \
    || fail "Crest requires Xcode 26 or newer; Xcode Cloud selected $xcode_version."
case "$xcode_build" in
    *[abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ])
        fail "Crest Cloud archives require a release Xcode; build $xcode_build is a beta or prerelease image."
        ;;
esac

repository_path="${CI_PRIMARY_REPOSITORY_PATH:-}"
[ -n "$repository_path" ] \
    || fail "CI_PRIMARY_REPOSITORY_PATH is unavailable."

project="$repository_path/project.yml"
scheme="$repository_path/Crest.xcodeproj/xcshareddata/xcschemes/${expected_scheme}.xcscheme"
[ -f "$project" ] || fail "project.yml is missing from the primary repository."
[ -f "$scheme" ] || fail "The shared ${expected_scheme} archive scheme is missing."

grep -q 'xcodeVersion: "27.0"' "$project" \
    || fail "project.yml must remain pinned to the Xcode 27 project format."
grep -q 'iOS: "26.1"' "$project" \
    || fail "The iOS deployment target must remain 26.1."
grep -q 'macOS: "26.1"' "$project" \
    || fail "The macOS deployment target must remain 26.1."

CREST_VERSION_REPOSITORY_ROOT="$repository_path" \
    "$repository_path/Scripts/check-version.sh" --static

echo "Validated manual ${CI_PRODUCT_PLATFORM} archive with ${expected_scheme} on release Xcode ${xcode_version}."
