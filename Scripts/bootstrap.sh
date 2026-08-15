#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
cd "$repository_root"

if ! command -v xcodegen >/dev/null 2>&1; then
  print -u2 "XcodeGen is required. Install it, then rerun Scripts/bootstrap.sh."
  exit 1
fi

xcodegen generate
Scripts/check-version.sh
Scripts/validate-identity.sh
Scripts/validate-cache-hygiene.sh

print "Generated $repository_root/Crest.xcodeproj"
