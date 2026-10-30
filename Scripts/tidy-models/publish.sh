#!/bin/zsh
set -euo pipefail

# Publishes the Core ML packages convert.py wrote as a GitHub release whose
# assets are each package's files, flat: <Package>-Manifest.json,
# <Package>-model.mlmodel and <Package>-weight.bin. Crest lays them back out
# as <Package>.mlpackage. The release also carries the models' licenses and
# SHA256SUMS, whose values TidyMethod.openModels pins.
#
# Usage: Scripts/tidy-models/publish.sh <out_dir> <owner/repo> <tag>

if (( $# != 3 )); then
  print -u2 "usage: $0 <out_dir> <owner/repo> <tag>"
  exit 64
fi
out_dir="${1:A}"
repository="$2"
tag="$3"
script_root="${0:A:h}"
assets="$(mktemp -d)"
trap 'rm -rf "$assets"' EXIT

for package in MiniLM TopicEncoder TopicDecoder; do
  source_dir="$out_dir/$package.mlpackage"
  cp "$source_dir/Manifest.json" "$assets/$package-Manifest.json"
  cp "$source_dir/Data/com.apple.CoreML/model.mlmodel" "$assets/$package-model.mlmodel"
  cp "$source_dir/Data/com.apple.CoreML/weights/weight.bin" "$assets/$package-weight.bin"
done
curl -fsSL -o "$assets/MiniLM-LICENSE.txt" https://www.apache.org/licenses/LICENSE-2.0.txt
curl -fsSL -o "$assets/smart-tab-topic-LICENSE.txt" https://www.mozilla.org/media/MPL/2.0/index.txt
(cd "$assets" && shasum -a 256 -- * > SHA256SUMS)
cat "$assets/SHA256SUMS"

gh release create "$tag" --repo "$repository" --title "Tidy models ($tag)" --latest=false \
  --notes-file "$script_root/RELEASE_NOTES.md" "$assets"/*
