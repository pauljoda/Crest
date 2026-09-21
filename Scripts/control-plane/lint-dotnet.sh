#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h:h}"
cd "$repository_root/CrestCore"

project="tests/CrestCore.Tests/CrestCore.Tests.csproj"
dotnet restore "$project" --nologo

for project in src/CrestCore.{Contracts,Domain,Application,Native}/CrestCore.*.csproj "$project"; do
  dotnet format analyzers "$project" --verify-no-changes --no-restore --verbosity quiet
  dotnet format style "$project" --verify-no-changes --no-restore --verbosity quiet
  dotnet format whitespace "$project" --verify-no-changes --no-restore --verbosity quiet
done
