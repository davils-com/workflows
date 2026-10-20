# Inspectra

<link-summary>Supply-chain scans and quality gates with Inspectra in every repository.</link-summary>

[Inspectra](https://github.com/davils-com/Inspectra) is the supply-chain scanner and quality gate
of davils-com. `inspectra.yml` runs it the way its own CI does, for every package of a workspace.

## Jobs

| Job | Command | Result |
|---|---|---|
| Check, per package | `inspectra -C <package> check` | format, lint, style, API, API semver, changelog, Trivy scans, dependency policy, coverage gate: whatever the package's Inspectra configuration enables |
| Check, workspace root | `inspectra check` | the workspace policy of the root `pubspec.yaml` |
| Scan | `inspectra scan -r` | OSV audit, pubspec rules, typosquatting, Trivy filesystem scan |
| Configuration | `inspectra config lint`, `inspectra config diff git:<base> --fail-on-weaker` | risky settings in code scanning; pull requests that weaken a gate fail |
| Dashboard | `inspectra report -r -f html` | `/quality/` of the Pages site |

The check jobs check out the whole history, because the API semver check compares with the last
release tag, and run `build_runner build --only-check` first for packages with build_runner, so
the API dump and generated files are current.

## The scan

1. A run with `--format sarif --exit-zero` for GitHub code scanning (category `inspectra`). Each
   rule carries a `security-severity`, so GitHub ranks the alerts. Pull requests from forks skip
   the upload.
2. A run with `--format markdown --fail-on <scan.fail-on>`; the report goes to the job summary
   and the exit code decides.

`scan.fail-on: none` never fails. The Trivy database is cached between runs.

## Exit codes

| Code | Meaning | Annotation |
|---|---|---|
| 1 | findings at or above the threshold, a failed gate | the gate failed |
| 64 | usage error | an option of the workflow or the configuration does not fit the Inspectra version |
| 65 | invalid configuration or a violated policy | the configuration names the cause |
| 69 | a network service or tool was unavailable | `inspectra.tolerate-incomplete: true` makes this a warning |
| 70 | internal error | rerun with `INSPECTRA_DEBUG=1` |

## Installation

`inspectra.install`:

| Value | Inspectra comes from |
|---|---|
| `auto` | the dev dependency when the root `pubspec.yaml` has one, a global activation otherwise |
| `dev-dependency` | `dart run inspectra`, the version of the lockfile |
| `global` | `dart pub global activate inspectra [inspectra.version]` |
| `binary` | the native executable of a GitHub release of davils-com/Inspectra, verified against its `checksums.txt` |

`inspectra.config-file` and `inspectra.profile` set `INSPECTRA_CONFIG` and `INSPECTRA_PROFILE`
for every command, such as a `ci` profile with stricter thresholds.

## Configuration

```yaml
inspectra:
  install: auto
  profile: ci
  check:
    root: auto
  scan:
    fail-on: high
    min-severity: low
  trivy:
    mode: required
    cache: true
  config-diff:
    enabled: auto
  tolerate-incomplete: false
  report:
    enabled: true
```
