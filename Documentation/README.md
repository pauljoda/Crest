# Crest documentation

The product site and [Crest Help](https://crestbrowser.com/guides/) explain how
to use the browser. This directory records the architecture, release, and
engineering contracts needed to build and maintain it.

## Start here

- [Architecture](ARCHITECTURE.md) — Space isolation, persistence, credentials,
  synchronization, and the native/WebKit boundary.
- [Roadmap](ROADMAP.md) — current public release outcomes and outstanding
  platform gates.
- [Public planning sync](PlanningSync.md) — the one-way Linear-to-GitHub
  mapping for release projects, issues, completion evidence, and the roadmap.
- [Repository guardrails](RepositoryGuardrails.md) — source layout, validation,
  dependency, and public-tree contracts.
- [Distribution](Distribution.md) — release channels, signing,
  notarization, appcasts, and release verification.

## Browser and extension behavior

- [Extension compatibility](ExtensionCompatibility.md) — supported package
  shapes and current WebKit boundaries.
- [Extension emulation services](ExtensionEmulationServices.md) — bounded
  compatibility services supplied by Crest.
- [WebKit extension worker report](WebKitExtensionWorkerReport.md) — measured
  worker lifecycle behavior.
- [Split View manual verification](SplitViewManualVerification.md) — the
  interaction scenarios used for direct app validation.

## Project participation

See [SUPPORT.md](../SUPPORT.md) for community and reporting routes,
[CONTRIBUTING.md](../CONTRIBUTING.md) for local development, and
[GOVERNANCE.md](../GOVERNANCE.md) for ownership and decision making.
