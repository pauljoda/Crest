#!/bin/zsh
set -euo pipefail

script_root="${0:A:h:h}"
repository_root="${CREST_VERSION_REPOSITORY_ROOT:-$script_root}"
version_file="$repository_root/Config/Version.xcconfig"
check_script="${0:A:h}/check-version.sh"

# Config/Version.xcconfig names the release line's base version. Changes never
# edit it: Scripts/derive-version.py derives each build's patch version from
# history. This script only starts a new release line.
usage() {
  print -u2 "Usage:"
  print -u2 "  Scripts/set-version.sh --release X.Y.Z"
  print -u2 "Print the version a commit builds as with Scripts/derive-version.py version."
  exit 64
}

is_strict_semver() {
  print -r -- "$1" | grep -Eq \
    '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
}

is_component_greater() {
  local candidate="$1"
  local current="$2"

  if (( ${#candidate} != ${#current} )); then
    (( ${#candidate} > ${#current} ))
    return
  fi

  [[ "$candidate" > "$current" ]]
}

is_version_greater() {
  local candidate="$1"
  local current="$2"
  local -a candidate_parts current_parts
  candidate_parts=("${(@s:.:)candidate}")
  current_parts=("${(@s:.:)current}")

  for index in 1 2 3; do
    if [[ "${candidate_parts[$index]}" == "${current_parts[$index]}" ]]; then
      continue
    fi

    is_component_greater "${candidate_parts[$index]}" "${current_parts[$index]}"
    return
  done

  return 1
}

"$check_script" --static >/dev/null

current_version="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p' "$version_file")"

case "${1:-}" in
  --patch)
    print -u2 "error: patch versions are derived from history; a change commit leaves Config/Version.xcconfig alone."
    print -u2 "Add a release-note entry as Documentation/ReleaseNotes/<id>.json and run Scripts/check-version.sh --fix-commit."
    print -u2 "This commit would build as $(python3 "${0:A:h}/derive-version.py" version 2>/dev/null || print "the next derived version")."
    exit 64
    ;;
  --release)
    [[ "$#" == 2 ]] || usage
    requested_version="$2"
    is_strict_semver "$requested_version" || usage
    is_version_greater "$requested_version" "$current_version" \
      || { print -u2 "error: $requested_version must be greater than current version $current_version."; exit 1; }

    current_parts=("${(@s:.:)current_version}")
    requested_parts=("${(@s:.:)requested_version}")
    if [[ "${requested_parts[1]}.${requested_parts[2]}" == "${current_parts[1]}.${current_parts[2]}" ]]; then
      print -u2 "error: a release starts a later X.Y; patch versions on the current line are derived from history (Scripts/derive-version.py)."
      exit 1
    fi
    update_kind="release line"
    ;;
  *)
    usage
    ;;
esac

backup_file="$(mktemp "${version_file}.backup.XXXXXX")"
updated_file="$(mktemp "${version_file}.updated.XXXXXX")"

cleanup() {
  [[ -f "$backup_file" ]] && rm -f "$backup_file"
  [[ -f "$updated_file" ]] && rm -f "$updated_file"
}
trap cleanup EXIT INT TERM HUP

cp "$version_file" "$backup_file"
sed -E \
  "s/^([[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*).*/\\1$requested_version/" \
  "$version_file" > "$updated_file"
mv "$updated_file" "$version_file"

if ! "$check_script"; then
  mv "$backup_file" "$version_file"
  print -u2 "error: version validation failed; restored $current_version."
  exit 1
fi

print "Updated Crest $update_kind from $current_version to $requested_version."
print "Commit Config/Version.xcconfig on its own and check it with Scripts/check-version.sh --release-commit."
print "Once it merges, builds of the default branch count patch versions up from $requested_version."
