# Getting started

<link-summary>Add the pipeline to a repository, grant its permissions and require its gate.</link-summary>

## 1. The caller workflow

Add `.github/workflows/ci.yml`:

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

Without a configuration file every feature is on `auto`: Dart checks when there is a Dart package,
Flutter checks when there is a Flutter package, Inspectra when the repository uses it, Writerside
when there is a `writerside.cfg`, API docs when a package is published, the web build and Pages
when there is a Flutter app with a `web/` directory.

### Why so many permissions

GitHub checks the permissions of every job a workflow could run before it starts the run, also
of jobs that will be skipped. The pipeline can deploy Pages, publish to pub.dev and create
releases, so the caller grants all of it, and each job inside only takes what it needs. A
repository that wants less calls the workflows one by one; see `examples/granular`.

### Pinning

`@v1` follows the latest 1.x release. `@v1.4.0` stays on one release, a commit SHA on one
commit. Dependabot with `package-ecosystem: github-actions` updates either. Inside, the workflows
reference their own actions with the self-repository syntax (`$/actions/...`), so they always
run the actions of the same commit as the workflow, whatever ref the caller chose.

## 2. The configuration

Add `.github/davils-ci.yaml` when a default does not fit:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/davils-com/workflows/v1/schemas/davils-ci.schema.json
version: 1

dart:
  sdks: [stable, lowest]
  test:
    platforms: [vm, chrome]
  coverage:
    min: 90
```

The schema line gives completion and validation in editors. Unknown options and wrong types fail
the first job with an annotation naming the option. See [](Configuration.md).

## 3. Branch protection

Require one status check: **Pipeline / Gate**. It runs after everything else, also when jobs
were skipped, and fails when any job failed or was cancelled. Adding or removing features never
changes the required checks.

## 4. GitHub settings

| Feature | Setting |
|---|---|
| Pages | Settings, Pages, Source: GitHub Actions. The `github-pages` environment deploys from the default branch only; allow `main` there when the default branch is `develop`. |
| pub.dev | On pub.dev, Admin, Automated publishing: this repository, the tag pattern and the environment `pub.dev`. Create the environment in the repository. See [](Releases.md). |
| Code scanning | Inspectra uploads SARIF; nothing to set up for public repositories. |
| release-please | A GitHub App with contents, pull requests and issues write, its id and key as secrets `RELEASE_APP_ID` and `RELEASE_APP_PRIVATE_KEY`. |
