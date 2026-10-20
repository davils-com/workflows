# Third-party software

The workflows run, but do not redistribute, the following software. Their pins are in the
workflows and actions; Dependabot and `self-update-pins.yml` keep them current.

| Software | Used for | License |
|---|---|---|
| actions/checkout, cache, upload-artifact, download-artifact, configure-pages, upload-pages-artifact, deploy-pages, attest-build-provenance, create-github-app-token, setup-java | checkout, caches, artifacts, Pages, attestations, tokens | MIT |
| dart-lang/setup-dart | Dart SDK, pub.dev OIDC token | BSD-3-Clause |
| subosito/flutter-action | Flutter SDK | MIT |
| github/codeql-action (upload-sarif) | code scanning uploads | MIT |
| JetBrains/writerside-github-action, JetBrains/writerside-checker-action, jetbrains/writerside-builder | Writerside builds and checks | Apache-2.0 |
| softprops/action-gh-release | GitHub releases | MIT |
| googleapis/release-please-action | release pull requests | Apache-2.0 |
| codecov/codecov-action | coverage uploads | MIT |
| dorny/test-reporter | test check runs | MIT |
| step-security/harden-runner | runner hardening | Apache-2.0 |
| amannn/action-semantic-pull-request | pull request titles | MIT |
| Inspectra | quality gates and supply-chain scans | Apache-2.0 |
| actionlint, ShellCheck, zizmor, check-jsonschema, bats | linting and tests of this repository | MIT, GPL-3.0, MIT, Apache-2.0, MIT |
