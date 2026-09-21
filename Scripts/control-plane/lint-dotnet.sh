#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h:h}"
cd "$repository_root/CrestCore"

project="tests/CrestCore.Tests/CrestCore.Tests.csproj"
dotnet restore "$project" --nologo

for project in src/CrestCore.{Contracts,Domain,Application,Native}/CrestCore.*.csproj "$project"; do
  dotnet format analyzers "$project" --verify-no-changes --no-restore --verbosity quiet
  dotnet format style "$project" --verify-no-changes --no-restore --verbosity quiet
done

# The existing library mixes brace styles. Gate the newly organized domain files
# now, then extend this check as the remaining files are formatted.
dotnet format whitespace src/CrestCore.Domain/CrestCore.Domain.csproj \
  --verify-no-changes --no-restore --verbosity quiet \
  --include src/CrestCore.Domain/BrowserIdentity.cs \
            src/CrestCore.Domain/BrowserRecords.cs \
            src/CrestCore.Domain/BrowserTab.cs \
            src/CrestCore.Domain/TabContent.cs
