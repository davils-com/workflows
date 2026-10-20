# Dart and Flutter checks

<link-summary>Format, analyze, tests, coverage and the optional checks of dart-ci.yml and flutter-ci.yml.</link-summary>

`dart-ci.yml` checks the Dart packages, `flutter-ci.yml` the Flutter packages. Both are the same
workflow; flutter-ci passes its inputs to dart-ci with `toolchain: flutter`.

## Jobs

| Job | Runs | Toggle |
|---|---|---|
| Format and analyze | once for every affected package | `format.enabled`, `analyze.enabled` |
| Generated sources | `build_runner build`, then no uncommitted change | `build-runner.enabled` (auto: packages with build_runner) |
| Localizations | `flutter gen-l10n`, then no uncommitted change | `l10n.enabled` (auto: packages with `l10n.yaml`) |
| Dry run | `pub publish --dry-run` of every published package | `publish-dry-run.enabled` |
| Tests | the matrix of packages, SDKs and operating systems | `test.enabled` |
| Coverage | merges the lcov of the first job of every package, enforces `coverage.min`, Codecov | `coverage.enabled` |
| Golden tests | the tests tagged `golden` on `golden.os`, where the goldens were recorded | `golden.enabled` |
| Integration tests | `integration_test/` on a desktop device (Linux with a virtual display) | `integration-test.enabled` |
| Lowest dependencies | `pub downgrade`, analyze and test on the lowest SDK | `downgrade.enabled` |
| Package score | pana for every published package, `pana.min-points` | `pana.enabled` |

## Test platforms

`dart.test.platforms` takes `vm`, `chrome`, `firefox`, `node` and `<platform>:<compiler>`:

```yaml
dart:
  test:
    platforms: [vm, chrome, chrome:dart2wasm]
```

Platforms without a compiler run in one `dart test -p vm,chrome`, each `platform:compiler` in its
own run. Without platforms, `dart_test.yaml` decides.

## Coverage

The first test job of every package (first operating system, first SDK) writes
`coverage/lcov.info`. The coverage job merges them with paths relative to the repository, writes
the coverage per package to the job summary, fails below `coverage.min` and uploads to Codecov
when `coverage.codecov` is on (public repositories need no token; private ones the secret
`CODECOV_TOKEN`). In the pipeline, one coverage job merges the Dart, Flutter and Inspectra
coverage, so every package counts once, whichever job ran its tests.

Inspectra's coverage gate runs the tests itself. With `coverage.source: auto`, a package whose
Inspectra configuration turns `coverage.enabled` on (also through `extends`) leaves its coverage
to the Inspectra job, so its tests do not run twice. `ci` always collects here, `inspectra` never.

With `pages.parts.coverage: true` the HTML report becomes `/coverage/` of the Pages site
(`/coverage/dart/` and `/coverage/flutter/` when dart-ci.yml and flutter-ci.yml are called on
their own).

`test.other-os-platforms` sets the platforms of the other operating systems, such as `[vm]` when
Chrome and WebAssembly only run on Linux. `verify.command` runs extra checks once in the format
and analyze job, such as checks that generated files are current.

## Test reports

`test.report: true` writes JSON reports; the `test-report` job of the pipeline turns them into a
check run with an annotation on every failed test. It is a job of its own because it needs
`checks: write`.
