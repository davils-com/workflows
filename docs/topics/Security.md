# Security

<link-summary>Pinning, permissions, untrusted input, forks and secrets.</link-summary>

## Pinning

- Every third-party action is pinned by its full commit SHA with the version as a comment.
  Dependabot updates the pins weekly; `self-update-pins.yml` updates the Writerside builder image
  and the lint tools.
- The workflows reference their own composite actions and workflows with the self-repository
  syntax, `$/actions/...` and `$/.github/workflows/...`. It resolves to this repository at the
  commit that is running, so the actions always match the workflow, also when a caller pins a
  commit SHA, and nothing is checked out at run time.
- Downloaded binaries are verified: Inspectra binaries against the release's `checksums.txt`,
  Trivy by Inspectra, actionlint in this repository's own lint against its checksums.

## Permissions

Every workflow starts with `permissions: {}` and each job takes only what it needs:

| Job | Permissions |
|---|---|
| checks, builds, docs | `contents: read` |
| Inspectra scan | `security-events: write` |
| test report | `checks: write` |
| Pages deployment | `pages: write`, `id-token: write` |
| pub.dev | `id-token: write` |
| GitHub release | `contents: write`, `id-token: write`, `attestations: write` |
| release-please | `contents: write`, `pull-requests: write`, `issues: write`, `actions: write` |

GitHub validates the permissions of every job before a run starts, so the pipeline's caller
grants the union. For least privilege, call the workflows separately (`examples/granular`).

## Untrusted input

Values that come from a pull request or a repository (branch names, titles, hooks, commands,
tags) reach scripts only through environment variables, never through `${{ }}` inside a script.
No workflow uses `pull_request_target`. Pull requests from forks skip SARIF uploads and check
runs, which their read-only token cannot write.

## Runners

`step-security/harden-runner` starts every Linux job; `security.harden-runner.egress-policy:
block` with `allowed-endpoints` limits the network to the listed endpoints.

## Secrets

All secrets are optional and passed explicitly from `pipeline.yml` to the workflow that needs
them, so `secrets: inherit` in the caller is enough and other workflows never see them. Signing
material is written to the runner's temporary directory and removed at the end of the job; the
macOS keychain is deleted.
