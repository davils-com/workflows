# Examples

Caller workflows for consumer repositories. Copy the `.github` directory of the one that fits and
adjust `.github/davils-ci.yaml`.

| Example | For | Shows |
|---|---|---|
| [minimal](minimal) | any Dart or Flutter repository | the one-liner: every feature on auto |
| [dart-package](dart-package) | a single package on pub.dev | SDK and OS matrix, web platforms, coverage gate, pana, API docs |
| [dart-workspace](dart-workspace) | a pub workspace published package by package | affected packages, Inspectra, Writerside, Pages with coverage and quality report, `<package>-v<version>` tags |
| [flutter-app](flutter-app) | a Flutter app | golden and integration tests, signed builds for every platform, web on Pages |
| [cli](cli) | a command line tool | tests on three operating systems, native binaries attached to the release |
| [release-please](release-please) | release pull requests instead of hand-made tags | release-please with a GitHub App, linked versions |
| [granular](granular) | least privilege | each workflow on its own with only its permissions, inputs instead of a file |

`@v1` follows the latest 1.x release. Pin `@vX.Y.Z` or a commit SHA for reproducible builds;
Dependabot (`package-ecosystem: github-actions`) keeps either current.
