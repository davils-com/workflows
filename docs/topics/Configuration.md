# Configuration

<link-summary>Layers, presets, toggles, event rules, hooks, runners and timeouts.</link-summary>

## Layers

The pipeline merges its configuration from five layers; a later layer wins:

1. the defaults, `actions/resolve-config/defaults.yaml` (all of them in [](Configuration-Reference.md)),
2. the preset (`preset` input),
3. `.github/davils-ci.yaml` (`config-file` input; `none` ignores any file),
4. the `config` input, YAML or JSON,
5. the typed inputs of `pipeline.yml`: `dart`, `flutter`, `inspectra`, `writerside`, `dartdoc`,
   `pages`, `flutter-build`, `dart-compile`, `pr-lint`, `release`, `working-directory`.

Mappings merge key by key; lists and values replace. `dart.sdks: [stable]` replaces
`[stable, lowest]`, while `dart: {coverage: {min: 90}}` keeps every other `dart` option.

```yaml
jobs:
  pipeline:
    uses: davils-com/workflows/.github/workflows/pipeline.yml@v1
    with:
      preset: workspace
      inspectra: 'off'
      config: |
        dart:
          os: [ubuntu, windows]
```

## Presets

| Preset | For |
|---|---|
| `library` | One package on pub.dev: API docs, dry runs, tag releases |
| `workspace` | A pub workspace released package by package; also checks the workspace root with Inspectra |
| `flutter-app` | A Flutter app: web, Android, Linux, Windows and macOS builds |
| `cli` | A command line tool: tests on three operating systems, native binaries for releases |
| `docs` | Only Writerside on Pages |

## Toggles

Every feature has `enabled`: `true`, `false` or `auto`. `auto` turns it on when the repository has
what it needs:

| Feature | `auto` is on when |
|---|---|
| `dart` | a package without Flutter is found |
| `flutter` | a Flutter package is found |
| `inspectra` | a package depends on `inspectra`, has an `inspectra:` section or an `inspectra.yaml`, or the root has `inspectra.base.yaml` |
| `writerside` | a `writerside.cfg` is found |
| `dartdoc` | a Dart package is published (no `publish_to: none`) |
| `pages` | any part of the site is produced: docs, API docs, a web build, enabled coverage or quality reports |
| `build.flutter` | an app is found and a target is on (`web: auto` is on for apps with `web/`) |
| `build.dart-compile` | a package has `executables:` |
| `release.mode` | `release-please` when `release-please-config.json` exists, otherwise `tag` |

`on` and `off` work wherever `true` and `false` do. In caller workflows, write `'on'` and `'off'`
for the typed string inputs: actionlint rejects `'true'` and `'false'` for string inputs.

## When a feature runs

Every feature has `when` with `events`, `branches` and `paths`:

```yaml
writerside:
  when:
    events: [push, pull_request, workflow_dispatch]
    branches: [main, develop]
    paths: ['docs/**']
```

| Field | Meaning |
|---|---|
| `events` | `push` (a branch push), `tag` (a tag push), `pull_request`, `merge_group`, `schedule`, `workflow_dispatch` |
| `branches` | Globs; the pushed branch, or the target branch of a pull request. Empty means every branch. |
| `paths` | Globs relative to the working directory. For pull requests, merge groups and pushes the feature runs when a changed file matches. Empty means any change. |

The defaults: checks run on every event but tags; Pages deploys on pushes to `main`; builds run
on pushes to `main`; releases run on tags that match `release.tag-patterns`.

## Hooks

Shell commands at fixed points of every job, run with `bash -euo pipefail` in the working
directory:

```yaml
hooks:
  pre-setup: ./tool/generate-secrets.sh
  post-setup: dart run build_runner build --delete-conflicting-outputs
  pre-test: docker compose up -d
  post-test: docker compose logs
  pre-publish: dart run tool/stamp_version.dart
```

Every check also has a `command` that replaces it, such as `dart.analyze.command` or
`dart.test.command` (run in each package directory with `PACKAGE_NAME` and `PACKAGE_PATH`).

## Runners and timeouts

```yaml
runners:
  linux: ubuntu-latest
  linux-arm: ubuntu-24.04-arm
  macos: macos-latest
  macos-intel: macos-15-intel
  windows: windows-latest
  windows-arm: windows-11-arm

timeouts:
  ci: 45
  build: 60
```

A runner can be a JSON array of labels for self-hosted runners:
`linux: '["self-hosted", "linux", "x64"]'`. Self-hosted runners need runner 2.336.0 or newer for
the self-repository syntax the workflows use.
