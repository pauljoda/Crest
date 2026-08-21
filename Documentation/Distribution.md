# Crest distribution

Crest has one official distribution path per platform:

- **macOS:** direct distribution from GitHub Releases, signed with Developer ID,
  notarized by Apple, and updated through Sparkle 2;
- **iPhone and iPad:** TestFlight and the App Store.

There is no Mac App Store build. Keeping one macOS product avoids incompatible
sandbox capabilities, duplicate update behavior, and user confusion over which
build supports native extension companions.

## Release channels

| Channel | Trigger | GitHub Release | Sparkle channel |
| --- | --- | --- | --- |
| Stable | Push an exact `v<marketing-version>` tag | Latest, non-prerelease | Default |
| Nightly | Daily schedule or manual workflow dispatch | Rolling prerelease | `nightly` |
| Development | Manual workflow dispatch after local validation | Rolling prerelease | `development` |

The marketing version comes from `Config/Version.xcconfig`. Stable tags must
match it exactly. Distributed build numbers add the GitHub Actions run number
to Crest's public-repository build epoch. The epoch keeps Sparkle ordering
strictly increasing across the repository migration; the run number keeps every
subsequent published update newer than the prior build.

The appcast is hosted at:

`https://raw.githubusercontent.com/pauljoda/Crest/updates/appcast.xml`

Development builds use a separate signed feed so frequent commits cannot prune
stable or nightly entries:

`https://raw.githubusercontent.com/pauljoda/Crest/updates/appcast-development.xml`

The `updates` branch is workflow-owned. It contains only the appcasts and a
short README. Stable binaries remain immutable GitHub Release assets. Nightly
and development builds each reuse one rolling prerelease, retain only the
current build's assets, and prefix the filenames with `Installer-`, `Checksum-`,
or `Debug-Symbols-` so their purpose is visible before GitHub truncates the
remaining name. Every filename still carries the version and, for rolling
builds, the UTC date and source commit, so Sparkle never advances to an
overwritten binary. GitHub Packages is not part of the desktop distribution
path.

Before allocating the macOS signing runner, a nightly preflight compares the
current source commit with the last nightly in the signed appcast. The appcast,
rather than the mutable rolling tag, is the completed-publication boundary. An
unchanged scheduled or manually dispatched nightly succeeds without building,
notarizing, creating a release, or advancing an appcast. After the first
successful rolling nightly publication, the workflow removes the superseded
date-stamped nightly releases and tags.

Release notes come from the explicit `Documentation/ReleaseNotes.json` catalog.
Every product or architecture commit adds a stable entry ID, category, and
purpose-written message. The generator compares the catalog stored in the last
signed publication with the current catalog, groups new public entries into
New, Improved, and Fixed highlights, omits `internal` entries, and limits long
ranges to the 12 most recent highlights. Because entry identity is independent
of commit hashes, rebases and other history rewrites do not repeat published
copy or block a nightly. The same concise notes appear on GitHub and as
structured Markdown in Sparkle's update interface.

For a channel whose last publication predates the catalog, the generator uses a
one-time compatibility path through Git history. Linear histories use the
ordinary commit range; rewritten histories first locate an exact tree-equivalent
published boundary and otherwise use patch equivalence to omit recreated
commits. Once that channel publishes a catalog-bearing build, later notes depend
only on catalog snapshots.

## Publication order

The production workflow intentionally publishes from the inside out:

1. regenerate the project and run the focused release tests;
2. import the Developer ID identity into a temporary keychain and install the
   matching release provisioning profile;
3. archive and export an arm64 Developer ID build with hardened runtime and
   Crest's production CloudKit, push, and keychain entitlements;
4. verify the app's signature, bundle identifier, and architecture;
5. notarize and staple the app;
6. create, sign, notarize, staple, and Gatekeeper-check the disk image;
7. publish the build-provenance attestation, then reconcile and digest-verify
   the disk image, checksum, and dSYM;
8. sign and publish the Sparkle appcast after the release assets exist.

If any signing or notarization step fails, no appcast is advanced. An update
therefore never points at an absent or unverified disk image.

Rolling publication is safe to repeat after an interrupted GitHub request. The
workflow reuses matching uploaded assets, removes only incomplete or mismatched
assets for the target build, and retries each replacement with state
verification. The prior complete build remains downloadable until the new
signed appcast has been pushed. Only then does the workflow prune superseded
assets. If a failure advances the rolling tag but not the appcast, the next run
still builds release notes from the last completed appcast entry.

## GitHub production environment

The `production` environment supplies release-only secrets. They are not kept
in the repository, copied into forks, or exposed to pull-request builds.

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_APPLICATION_P12_BASE64` | Developer ID certificate and private key exported as an encrypted PKCS #12 archive, then base64 encoded |
| `DEVELOPER_ID_APPLICATION_P12_PASSWORD` | Password used for that PKCS #12 archive |
| `DEVELOPER_ID_PROVISIONING_PROFILE_BASE64` | `Crest Developer ID` provisioning profile that grants the direct build access to Apple services |
| `APP_STORE_CONNECT_API_ISSUER_ID` | App Store Connect API issuer used by Xcode and `notarytool` |
| `APP_STORE_CONNECT_API_KEY_ID` | Identifier of the App Store Connect API key |
| `APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64` | Downloaded `.p8` private key, base64 encoded |
| `SPARKLE_EDDSA_PRIVATE_KEY` | Private key used only to sign appcast enclosures |

The corresponding Sparkle public key is embedded in the macOS app. The
Developer ID certificate and Sparkle key should be rotated deliberately, with
the old signing path retained long enough to update installed copies safely.

## Operator checklist

Before publishing a stable tag:

1. confirm `CHANGELOG.md`, `Documentation/ReleaseNotes.json`, and the marketing
   version are ready;
2. confirm the main-branch validation and Pages workflows are green;
3. confirm the production environment contains all seven release secrets;
4. create and push the exact version tag;
5. inspect the workflow's signature, notarization, Gatekeeper, checksum, and
   attestation results;
6. install the published disk image on a clean macOS account and exercise both
   a manual update check and the normal relaunch path.

Nightly and development builds use the same signing, notarization, and
verification gates as a stable build. Both rolling prereleases keep only their
current asset set after the signed appcast has advanced. Development
publication keeps only the latest queued public commit when dispatches arrive
faster than Apple notarization. Every distributed build defaults to its own
channel, while an existing user choice remains authoritative.

## Local macOS iteration

Maintainers can build and install the real Release configuration without
publishing an update:

```bash
Scripts/install-local-macos-release.sh
```

The command requires Crest's Developer ID identity and provisioning profile in
the local keychain/Xcode profile directory. It archives with production iCloud,
push, keychain, hardened-runtime, and extension-companion signing, verifies the
export, replaces `/Applications/Crest.app`, and relaunches it. It reuses the
greater of the installed build number and current development appcast by
default. That prevents the current public build from immediately replacing a
local iteration without outranking the next published Sparkle build. Set
`CREST_LOCAL_BUILD_NUMBER` only when a specific local bundle version is needed.

Ordinary commits to `main` do not publish or advance an appcast. After a local
build passes the signed-app extension and update checks, dispatch **Publish
macOS release** with the `development` channel from the validated commit.

## Verify a downloaded release

After mounting a published disk image, users and maintainers can inspect it
with standard macOS tools:

```bash
shasum -a 256 -c Checksum-Crest-*.dmg.sha256
codesign --verify --deep --strict --verbose=2 /Volumes/Crest/Crest.app
spctl --assess --type execute --verbose=4 /Volumes/Crest/Crest.app
xcrun stapler validate /Volumes/Crest/Crest.app
```

GitHub's build-provenance attestation and the checksum file provide independent
links from the public workflow run to the exact disk image.
