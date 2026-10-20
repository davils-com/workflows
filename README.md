# davils-com/workflows

Reusable GitHub Actions workflows for the Dart and Flutter repositories of davils-com: checks,
[Inspectra](https://github.com/davils-com/Inspectra), Writerside and API docs, one GitHub Pages
site, Flutter app builds, native Dart binaries, pub.dev and GitHub releases. Multi-package
repositories (pub workspaces, nested or globbed, plus packages outside the workspace) are built
in. Every feature can be turned on and off, every command replaced.

## Quick start

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: ['**']
    tags: ['v*', '*-v*']
  pull_request:
    branches: [main, develop]
    types: [opened, edited, synchronize, reopened]
  merge_group:
  schedule:
    - cron: '0 4 * * 1'
  workflow_dispatch:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ !startsWith(github.ref, 'refs/tags/') }}

permissions: {}

jobs:
  pipeline:
    name: Pipeline
    uses: davils-com/workflows/.github/workflows/pipeline.yml@v1
    permissions:
      contents: write
      pull-requests: write
      issues: write
      actions: write
      checks: write
      security-events: write
      pages: write
      id-token: write
      attestations: write
    secrets: inherit
```

Require the status check **Pipeline / Gate**. Without configuration every feature is on `auto`
and runs when the repository has what it needs. `.github/davils-ci.yaml` changes anything:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/davils-com/workflows/v1/schemas/davils-ci.schema.json
version: 1

packages:
  include: ['*_flutter']

dart:
  sdks: [stable, lowest]
  test:
    platforms: [vm, chrome, chrome:dart2wasm]
  coverage:
    min: 90

inspectra:
  scan:
    fail-on: high

writerside:
  instances: [docs/d]

build:
  flutter:
    targets:
      web: true
      apk: true

release:
  tag-patterns:
    package: '{package}-v{version}'
```

Pin a release for reproducible builds: `@v0.1.0` <!-- x-release-please-version -->, or a commit SHA.

## Workflows

| Workflow | Purpose |
|---|---|
| [`pipeline.yml`](.github/workflows/pipeline.yml) | Reads the configuration, finds the packages, decides per event what runs, calls the rest; one required check |
| [`dart-ci.yml`](.github/workflows/dart-ci.yml) | Format, analyze, tests on SDK, platform and OS matrices, coverage, generated files, dry run, pana, lowest dependencies |
| [`flutter-ci.yml`](.github/workflows/flutter-ci.yml) | The same for Flutter, plus golden tests, integration tests and localizations |
| [`inspectra.yml`](.github/workflows/inspectra.yml) | `inspectra check` per package and at the workspace root, `inspectra scan` with code scanning, summary and gate, config lint and diff, dashboard |
| [`writerside.yml`](.github/workflows/writerside.yml) | Writerside builds with the checker, PDF and Algolia |
| [`dartdoc.yml`](.github/workflows/dartdoc.yml) | API documentation of the published packages |
| [`pages.yml`](.github/workflows/pages.yml) | One Pages site from docs, API docs, web builds, coverage and quality reports |
| [`flutter-build.yml`](.github/workflows/flutter-build.yml) | Web, Android, iOS, macOS, Linux and Windows builds, signing and notarization |
| [`dart-compile.yml`](.github/workflows/dart-compile.yml) | Native binaries for six targets with checksums |
| [`release-tag.yml`](.github/workflows/release-tag.yml) | Tag-driven release: verify, build, pub.dev, GitHub release |
| [`pub-publish.yml`](.github/workflows/pub-publish.yml) | pub.dev with OIDC, waiting for workspace siblings |
| [`github-release.yml`](.github/workflows/github-release.yml) | Release notes, assets, `checksums.txt`, provenance attestations |
| [`release-please.yml`](.github/workflows/release-please.yml) | Release pull requests from Conventional Commits |
| [`pr-lint.yml`](.github/workflows/pr-lint.yml) | Conventional Commits titles with package scopes, branch policy |
| [`test-report.yml`](.github/workflows/test-report.yml) | Test results as a check run |

The composite actions in [`actions/`](actions) work on their own as well, such as
`davils-com/workflows/actions/setup-dart-env@v1`.

## Documentation

- [Getting started](docs/topics/Getting-Started.md)
- [Configuration](docs/topics/Configuration.md) and [every option](docs/topics/reference/Configuration-Reference.md)
- Guides: [monorepos](docs/topics/Monorepos.md), [Dart and Flutter](docs/topics/Dart-and-Flutter.md),
  [Inspectra](docs/topics/Inspectra.md), [documentation and Pages](docs/topics/Documentation-and-Pages.md),
  [builds](docs/topics/Builds.md), [releases](docs/topics/Releases.md), [security](docs/topics/Security.md),
  [migration](docs/topics/Migration.md)
- [Examples](examples)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [the development guide](docs/topics/Development.md).
Security problems: [SECURITY.md](SECURITY.md).

## License

[Apache License 2.0](LICENSE)
