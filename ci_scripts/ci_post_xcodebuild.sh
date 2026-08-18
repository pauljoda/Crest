#!/bin/sh

set -eu

if [ "${CI_XCODE_CLOUD:-FALSE}" != "TRUE" ]; then
    echo "Crest archive artifact guard skipped outside Xcode Cloud."
    exit 0
fi

if [ "${CI_XCODEBUILD_EXIT_CODE:-1}" != "0" ]; then
    echo "Crest archive artifact guard skipped because xcodebuild already failed."
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

expected_build="${CI_BUILD_NUMBER:-}"
[ -n "$expected_build" ] \
    || fail "CI_BUILD_NUMBER is unavailable."

archive_path="${CI_ARCHIVE_PATH:-}"
[ -n "$archive_path" ] \
    || fail "CI_ARCHIVE_PATH is unavailable."
[ -d "$archive_path" ] \
    || fail "The Xcode Cloud archive does not exist at '$archive_path'."

archive_info="$archive_path/Info.plist"
[ -f "$archive_info" ] \
    || fail "The Xcode Cloud archive Info.plist is missing."

application_path="$(
    plutil -extract ApplicationProperties.ApplicationPath raw -o - "$archive_info" 2>/dev/null \
        || true
)"
case "$application_path" in
    Applications/*.app)
        ;;
    *)
        fail "The Xcode Cloud archive has an invalid application path '${application_path:-unset}'."
        ;;
esac

app_plist="$archive_path/Products/$application_path/Info.plist"
[ -f "$app_plist" ] \
    || fail "The archived app Info.plist is missing at '$app_plist'."

actual_version="$(plutil -extract CFBundleShortVersionString raw -o - "$app_plist")"
actual_build="$(plutil -extract CFBundleVersion raw -o - "$app_plist")"
actual_bundle_identifier="$(plutil -extract CFBundleIdentifier raw -o - "$app_plist")"

[ "$actual_bundle_identifier" = "com.pauldavis.crest" ] \
    || fail "The archived app bundle identifier is '$actual_bundle_identifier', expected com.pauldavis.crest."
[ "$actual_version" = "$expected_version" ] \
    || fail "The archived app is version $actual_version, but Config/Version.xcconfig requires $expected_version."
[ "$actual_build" = "$expected_build" ] \
    || fail "The archived app build is $actual_build, but Xcode Cloud assigned $expected_build."

echo "Validated archived ${actual_bundle_identifier} version ${actual_version} (${actual_build}) before distribution."
