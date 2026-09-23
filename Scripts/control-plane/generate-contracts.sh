#!/bin/zsh
# Regenerates the contract codecs and models from the C# contract records in
# CrestCore/src/CrestCore.Contracts: the core's ContractCodec, the two Swift
# files under CrestShared/Infrastructure/Core/Generated and
# CrestContracts/include/crest_contracts.h. Pass --check to verify that they
# are current without writing anything.
set -euo pipefail

repository_root="${0:A:h:h:h}"
dotnet run --project "$repository_root/CrestCore/tools/CrestCore.Generator" --nologo -- --root "$repository_root" "$@"
