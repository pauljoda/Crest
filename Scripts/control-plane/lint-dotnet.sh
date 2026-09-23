#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h:h}"
cd "$repository_root/CrestCore"

project="tests/CrestCore.Tests/CrestCore.Tests.csproj"
generator="tools/CrestCore.Generator/CrestCore.Generator.csproj"
dotnet restore "$project" --nologo
dotnet restore "$generator" --nologo

for project in src/CrestCore.{Contracts,Domain,Application,Native}/CrestCore.*.csproj "$generator" "$project"; do
  dotnet format analyzers "$project" --verify-no-changes --no-restore --verbosity quiet
  dotnet format style "$project" --verify-no-changes --no-restore --verbosity quiet
  dotnet format whitespace "$project" --verify-no-changes --no-restore --verbosity quiet
done

"$repository_root/Scripts/control-plane/generate-contracts.sh" --check
