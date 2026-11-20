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

require '^name: Crest$' "the Crest project name"
require '^  Crest:$' "the Crest target"
require '^  CrestMobile:$' "the CrestMobile target"
require 'CREST_MAC_BUNDLE_IDENTIFIER: com\.pauldavis\.crest$' "the Mac bundle identifier com.pauldavis.crest"
require 'CREST_MOBILE_BUNDLE_IDENTIFIER: com\.pauldavis\.crest$' "the iOS bundle identifier com.pauldavis.crest"
require 'PRODUCT_MODULE_NAME: Crest$' "the Crest module name"
require 'PRODUCT_MODULE_NAME: CrestMobile$' "the CrestMobile module name"

print "Crest identity validation passed."
