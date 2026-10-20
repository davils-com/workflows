# davils-com/workflows

<link-summary>Reusable GitHub Actions workflows for Dart, Flutter, Inspectra, Writerside, GitHub Pages and releases.</link-summary>

Reusable GitHub Actions workflows and composite actions for the Dart and Flutter repositories of
davils-com. One caller file gives a repository its whole CI: checks, Inspectra, documentation,
GitHub Pages, app builds, native binaries, pub.dev and GitHub releases. Every feature can be
switched on and off, and every command can be replaced.

## What is in it

| Area | Workflow | What it does |
|---|---|---|
| Everything | `pipeline.yml` | Reads `.github/davils-ci.yaml`, finds the packages, decides per event what runs and calls the workflows below |
| Checks | `dart-ci.yml`, `flutter-ci.yml` | Format, analyze, tests on SDK, platform and operating system matrices, coverage, generated files, `pub publish --dry-run`, pana, lowest dependencies, golden and integration tests |
| Quality | `inspectra.yml` | `inspectra check` per package and at the workspace root, `inspectra scan` with code scanning, job summary and gate, configuration lint and diff, the HTML dashboard |
| Documentation | `writerside.yml`, `dartdoc.yml` | Writerside builds with the checker, PDF and Algolia; API docs per package |
| Pages | `pages.yml` | One GitHub Pages site from documentation, API docs, Flutter web builds, coverage and quality reports |
| Builds | `flutter-build.yml`, `dart-compile.yml` | Web, Android, iOS, macOS, Linux and Windows builds, signed when the secrets are there; native binaries for six targets |
| Releases | `release-tag.yml`, `pub-publish.yml`, `github-release.yml`, `release-please.yml` | Tag-driven releases to pub.dev with OIDC, GitHub releases with notes, checksums and attestations, release-please |
| Pull requests | `pr-lint.yml`, `test-report.yml` | Conventional Commits titles with package scopes, branch policy, test results as a check run |

## Multi-package repositories

The workflows read the `workspace:` list of the root `pubspec.yaml` (nested and globbed members
included) and add packages outside the workspace from `packages.include`. Pull requests only
check the packages they change and the packages depending on them. Large workspaces spread over
shards. Each member is released with its own `<package>-v<version>` tag. See
[](Monorepos.md).

## Start here

1. [](Getting-Started.md): the caller workflow and the first run.
2. [](Configuration.md): the configuration file, presets, toggles and hooks.
3. [](Configuration-Reference.md): every option with its default.
