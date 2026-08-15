#!/bin/zsh
set -euo pipefail

script_root="${0:A:h:h}"
repository_root="${CREST_VERSION_REPOSITORY_ROOT:-$script_root}"
version_file="$repository_root/Config/Version.xcconfig"
check_script="${0:A:h}/check-version.sh"

usage() {
  print -u2 "Usage: Scripts/set-version.sh X.Y.Z"
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

[[ "$#" == "1" ]] || usage
requested_version="$1"
is_strict_semver "$requested_version" || usage

"$check_script" --static >/dev/null

current_version="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p' "$version_file")"
is_version_greater "$requested_version" "$current_version" \
  || { print -u2 "error: $requested_version must be greater than current version $current_version."; exit 1; }

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

print "Updated Crest from $current_version to $requested_version."
