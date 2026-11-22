#!/bin/zsh
set -euo pipefail

# The identities Crest's persistence rests on: the project and module names
# and both apps' bundle identifiers, which name the stores, defaults and
# Keychain items an installed Crest already holds.
repository_root="${0:A:h:h}"
cd "$repository_root"

require() {
  grep -Eq "$1" project.yml || { print -u2 "project.yml no longer declares $2."; exit 1; }
}

# Every value the target `$1` gives setting `$2`, one a line and without
# quotes: its base setting and any configuration's override, read from that
# target's own block under `targets:`, since other targets declare the same
# settings.
target_settings() {
  awk -v target="  $1:" -v key="$2:" '
    /^[^ ]/ { in_targets = ($0 == "targets:"); inside = 0; next }
    in_targets && /^  [^ ]/ { inside = ($0 == target); next }
    inside && $1 == key { value = $2; gsub(/"/, "", value); print value }
  ' project.yml
}

# Fails unless the target `$1` gives setting `$2` the value `$3` in every
# configuration.
require_setting() {
  local values value
  values="$(target_settings "$1" "$2")"
  [[ -n "$values" ]] || { print -u2 "project.yml no longer gives the $1 target $2 $3."; exit 1; }
  for value in "${(@f)values}"; do
    [[ "$value" == "$3" ]] || { print -u2 "project.yml no longer gives the $1 target $2 $3 in every configuration."; exit 1; }
  done
}

require '^name: Crest$' "the Crest project name"
require_setting Crest CREST_MAC_BUNDLE_IDENTIFIER com.pauldavis.crest
require_setting Crest PRODUCT_BUNDLE_IDENTIFIER '$(CREST_MAC_BUNDLE_IDENTIFIER)'
require_setting Crest PRODUCT_MODULE_NAME Crest
require_setting CrestMobile CREST_MOBILE_BUNDLE_IDENTIFIER com.pauldavis.crest
require_setting CrestMobile PRODUCT_BUNDLE_IDENTIFIER '$(CREST_MOBILE_BUNDLE_IDENTIFIER)'
require_setting CrestMobile PRODUCT_MODULE_NAME CrestMobile

print "Crest identity validation passed."
