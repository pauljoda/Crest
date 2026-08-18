#!/bin/sh

set -eu

if [ "${CI_XCODE_CLOUD:-FALSE}" != "TRUE" ]; then
    echo "Crest pre-archive version guard skipped outside Xcode Cloud."
    exit 0
fi

fail() {
    echo "error: $1" >&2
    exit 64
}

[ "${CI_XCODEBUILD_ACTION:-}" = "archive" ] \
    || fail "The Crest release workflow only permits archive actions."

repository_path="${CI_PRIMARY_REPOSITORY_PATH:-}"
[ -n "$repository_path" ] \
    || fail "CI_PRIMARY_REPOSITORY_PATH is unavailable."

case "${CI_PRODUCT_PLATFORM:-}" in
    iOS)
        expected_scheme="CrestMobile"
        destination="generic/platform=iOS"
        ;;
    macOS)
        expected_scheme="Crest"
        destination="generic/platform=macOS"
        ;;
    *)
        fail "Unsupported Xcode Cloud platform '${CI_PRODUCT_PLATFORM:-unset}'."
        ;;
esac

[ "${CI_XCODE_SCHEME:-}" = "$expected_scheme" ] \
    || fail "${CI_PRODUCT_PLATFORM} archives must use the ${expected_scheme} scheme."

version_file="$repository_path/Config/Version.xcconfig"
[ -f "$version_file" ] \
    || fail "Config/Version.xcconfig is missing from the primary repository."

expected_version="$(
    sed -nE \
        's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p' \
        "$version_file"
)"
[ -n "$expected_version" ] \
    || fail "Unable to resolve MARKETING_VERSION from Config/Version.xcconfig."

if ! build_settings="$(
    xcodebuild \
        -project "$repository_path/Crest.xcodeproj" \
        -scheme "$expected_scheme" \
        -configuration Release \
        -destination "$destination" \
        -showBuildSettings \
        2>&1
)"; then
    echo "$build_settings" >&2
    fail "Unable to resolve ${expected_scheme} Release build settings."
fi

resolved_version="$(
    echo "$build_settings" \
        | awk -F ' = ' '$1 ~ /^[[:space:]]*MARKETING_VERSION$/ { print $2; exit }'
)"
[ "$resolved_version" = "$expected_version" ] \
    || fail "${expected_scheme} Release resolves MARKETING_VERSION as '${resolved_version:-unset}', expected $expected_version."

echo "Validated ${expected_scheme} Release MARKETING_VERSION $resolved_version before the Xcode Cloud archive."
