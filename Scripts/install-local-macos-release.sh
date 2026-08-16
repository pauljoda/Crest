#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
application_path="/Applications/Crest.app"
team_id="3U2R97HLXF"
signing_identity="Developer ID Application"
provisioning_profile="Crest Developer ID"

cd "$repository_root"

if ! security find-identity -v -p codesigning \
  | grep -Fq "Developer ID Application:"; then
  print -u2 "Crest's Developer ID Application identity is not installed."
  exit 1
fi

profile_directory="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
profile_found=false
if [[ -d "$profile_directory" ]]; then
  for profile_path in "$profile_directory"/*; do
    [[ -f "$profile_path" ]] || continue
    profile_name="$({
      security cms -D -i "$profile_path" 2>/dev/null \
        | plutil -extract Name raw - 2>/dev/null
    } || true)"
    if [[ "$profile_name" == "$provisioning_profile" ]]; then
      profile_found=true
    fi
    [[ "$profile_found" == true ]] && break
  done
fi
if [[ "$profile_found" != true ]]; then
  print -u2 "The $provisioning_profile provisioning profile is not installed."
  exit 1
fi

build_number="${CREST_LOCAL_BUILD_NUMBER:-}"
if [[ -z "$build_number" && -d "$application_path" ]]; then
  build_number="$({
    defaults read "$application_path/Contents/Info" CFBundleVersion
  } 2>/dev/null || true)"
fi
build_number="${build_number:-1}"
if [[ ! "$build_number" =~ '^[0-9]+([.][0-9]+)*$' ]]; then
  print -u2 "Invalid local build number: $build_number"
  exit 1
fi

release_root="$(mktemp -d "${TMPDIR%/}/crest-local-release.XXXXXX")"
archive_path="$release_root/Crest.xcarchive"
export_path="$release_root/export"
previous_application_path="$release_root/Crest.previous.app"
installation_staging_path="/Applications/.Crest-local-install-${$}.app"
installation_complete=false

cleanup() {
  if [[ -e "$installation_staging_path" ]]; then
    find "$installation_staging_path" -depth -delete 2>/dev/null || true
  fi
  if [[ "$installation_complete" != true \
    && ! -e "$application_path" \
    && -e "$previous_application_path" ]]; then
    mv "$previous_application_path" "$application_path" 2>/dev/null || true
  fi
  find "$release_root" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT INT TERM HUP

print "Building Crest Release ($build_number) with production services..."
xcodebuild archive \
  -quiet \
  -project Crest.xcodeproj \
  -scheme Crest \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  CURRENT_PROJECT_VERSION="$build_number" \
  CREST_DEFAULT_UPDATE_CHANNEL=development \
  DEVELOPMENT_TEAM="$team_id" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$signing_identity" \
  PROVISIONING_PROFILE_SPECIFIER="$provisioning_profile"

xcodebuild -exportArchive \
  -quiet \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist Config/DeveloperIDExportOptions.plist

built_application_path="$export_path/Crest.app"
[[ -d "$built_application_path" ]]
codesign --verify --deep --strict --verbose=2 "$built_application_path"
[[ "$(defaults read "$built_application_path/Contents/Info" CFBundleIdentifier)" \
  == "com.pauldavis.crest" ]]

exported_entitlements="$release_root/exported-entitlements.plist"
codesign -d --entitlements :- "$built_application_path" \
  > "$exported_entitlements" 2>/dev/null
[[ "$(/usr/libexec/PlistBuddy -c \
  'Print :com.apple.developer.icloud-container-environment' \
  "$exported_entitlements")" == "Production" ]]

if pgrep -x Crest >/dev/null 2>&1; then
  osascript -e 'tell application "Crest" to quit'
  for _ in {1..100}; do
    pgrep -x Crest >/dev/null 2>&1 || break
    sleep 0.1
  done
fi
if pgrep -x Crest >/dev/null 2>&1; then
  print -u2 "Crest did not quit; the existing application was not replaced."
  exit 1
fi

ditto "$built_application_path" "$installation_staging_path"
codesign --verify --deep --strict --verbose=2 "$installation_staging_path"
if [[ -e "$application_path" ]]; then
  mv "$application_path" "$previous_application_path"
fi
mv "$installation_staging_path" "$application_path"
installation_complete=true

codesign --verify --deep --strict --verbose=2 "$application_path"
open "$application_path"
print "Installed and launched local Crest Release ($build_number)."
