# Monorepos and pub workspaces

<link-summary>How packages are found, which ones a change affects and how they spread over jobs.</link-summary>

## Finding the packages

1. With a `workspace:` list in the root `pubspec.yaml`, its members: plain paths, nested paths
   (`server/api`) and globs (`packages/*`). Every member has to declare `resolution: workspace`.
2. Without one, the root package.
3. Plus every directory with a `pubspec.yaml` that matches `packages.include`, for packages
   outside the workspace, such as a Flutter package next to a pure Dart workspace.
4. Minus `packages.exclude`. `build/`, `.dart_tool/` and generated Flutter directories are always
   left out.

```yaml
packages:
  include: ['*_flutter', 'apps/*']
  exclude: ['**/example']
```

For every package the workflows know its name, version, whether it is a Flutter package, whether
it is published, whether it is an app (Flutter, not published, `lib/main.dart` and a platform
directory), its platforms, executables, `build_runner`, localizations, Inspectra configuration,
the lower bounds of its SDK constraints and the packages of the repository it depends on.

A workspace with a Flutter member is resolved with `flutter pub get` as a whole. Packages outside
the workspace are resolved on their own.

### Path dependencies

A path dependency that leaves the repository (`../../inspectra`) cannot resolve on a runner,
which only checks out this repository. Discovery stops with an error naming the dependency.
Publish the dependency or use a git dependency; `packages.external-path-dependencies: warn`
turns the error into a warning for repositories that provide the dependency in a hook.

## Affected packages

On pull requests and merge groups (`packages.affected-only: auto`), the workflows compare with the
base commit and check:

- every package with a changed file,
- every package depending on one of them, as a dependency or a dev dependency, transitively.

A change to a file in `packages.always-all-paths` affects every package: `pubspec.yaml`,
`pubspec.lock`, `analysis_options.yaml`, `dart_test.yaml`, `inspectra.yaml`,
`inspectra.base.yaml`, `trivy*.yaml`, `tool/**` and `.github/**` by default.

Pushes, schedules and manual runs check every package.

## Jobs

`packages.granularity`:

| Value | Jobs |
|---|---|
| `package` | one test job per package, SDK and operating system |
| `workspace` | one test job for all packages |
| `shards` | the packages round-robin over `packages.shards` jobs |
| `auto` | `package` up to `packages.shard-threshold` packages, `shards` above |

Format and analyze run once for all affected packages, each package analyzed on its own so
packages outside the workspace keep their own resolution.

`dart.sdks` takes `stable`, `beta`, `lowest` and versions. `lowest` is the lower bound of the
`environment.sdk` constraint (for Flutter, `environment.flutter`), so the oldest SDK a package
claims to support is tested. Other operating systems than the first of `dart.os` only test the
first SDK.

## Releases of single members

Each published member is released with its own tag, `<package>-v<version>`. Its release waits on
pub.dev for the versions of the members it depends on, so tags pushed together publish in the
order of the dependencies. GitHub starts no workflow when more than three tags arrive in one
push; `tools/push-tags.sh` pushes them three at a time. See [](Releases.md).
