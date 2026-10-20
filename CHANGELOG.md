# Changelog

All notable changes to this project are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). release-please writes the entries of
each release from the Conventional Commits merged since the last one.

## [0.2.0](https://github.com/davils-com/workflows/compare/v0.1.0...v0.2.0) (2026-10-20)


### Added

* add the reusable workflows for Dart, Flutter, Inspectra, docs and releases ([3eff1f4](https://github.com/davils-com/workflows/commit/3eff1f4e44fa0655c71ee3a35e6418d6c3e6bc35))

## [Unreleased]

### Added

- `pipeline.yml`, which reads `.github/davils-ci.yaml`, discovers the packages and decides per event
  which of the other workflows run.
- `dart-ci.yml` and `flutter-ci.yml`: format, analyze, test matrices with `lowest` SDKs, coverage
  with an Inspectra aware source, generated sources, localizations, dry runs, pana, lowest
  dependencies, golden and integration tests.
- `inspectra.yml`: `inspectra check` per package and at the workspace root, `inspectra scan` with
  SARIF, job summary and gate, configuration lint and diff, the HTML dashboard.
- `writerside.yml`, `dartdoc.yml` and `pages.yml`, which assembles one Pages site from every part.
- `flutter-build.yml` for every Flutter target with Android and Apple signing, and
  `dart-compile.yml` for native binaries.
- `release-tag.yml`, `pub-publish.yml`, `github-release.yml` and `release-please.yml`.
- `pr-lint.yml` and `test-report.yml`.
- Composite actions for every step, the JSON schema of the configuration, presets, examples and
  this documentation.
