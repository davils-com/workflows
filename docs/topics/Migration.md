# Migrating a repository

<link-summary>From hand-written workflows to davils-com/workflows.</link-summary>

## Steps

1. Add the caller workflow ([](Getting-Started.md)) and a `.github/davils-ci.yaml` with what the
   old workflows did differently from the defaults.
2. Open a pull request. The pipeline runs next to the old workflows; compare their results.
3. Remove the old workflows, require **Pipeline / Gate** instead of their checks.
4. Set up pub.dev and the environments ([](Releases.md)) before the first tag.

## From the old workflows of davils-com

| Old | New |
|---|---|
| `ci.yml`: `dart run tool/verify.dart` on `stable` and the lowest SDK | `dart.sdks: [stable, lowest]` and `dart.test.platforms`; format, analyze and tests are jobs of their own, so CI no longer needs the script. `packages.granularity: workspace` keeps all tests in one job. |
| A hard-coded package list in the matrix, the tag filter and a `case` | Nothing: the packages come from the `workspace:` list. |
| `inspectra` job with a matrix over the packages and `.` | `inspectra.yml`; `inspectra.check.root: auto` adds the workspace root. |
| `security.yml` with SARIF, summary and gate | The scan job of `inspectra.yml`, `inspectra.scan.fail-on: high`. |
| `writerside.yml` with `INSTANCE` and `DOCKER_VERSION` | `writerside.instances: [docs/e]`; the builder version is kept current here. |
| `release.yml` with `<package>-v*` tags, siblings wait and OIDC publish | `release-tag.yml` through the pipeline; tag pattern `{package}-v{version}`. |
| `release.yml` with native binaries and `checksums.txt` | `build.dart-compile`; the release gets the binaries, `checksums.txt` and attestations. |
| Dependabot for `github-actions` | Keep it: it updates the pin of davils-com/workflows. |

## Notes

- **Tags.** The tag has to match a pattern: a repository tagged `2.1.0` and a workflow listening
  to `v*` never released. The release verifies that the tag and the `pubspec.yaml` version agree.
- **Path dependencies.** Repositories that depend on sibling repositories by path (`../inspectra`)
  cannot resolve on a runner. Publish the dependencies or use git dependencies first.
- **Flutter packages outside the workspace** go into `packages.include`.
- **The default branch.** When it is `develop`, allow `main` in the deployment rules of the
  `github-pages` environment.
