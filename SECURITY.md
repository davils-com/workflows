# Security policy

## Supported versions

Security fixes are released for the latest minor version of the current major release; the major
tag (`v1`) moves to them.

## Reporting a vulnerability

**Do not open a public issue for a security problem.**

Report it privately through GitHub's
[private vulnerability reporting](https://github.com/davils-com/workflows/security/advisories/new),
with the affected workflow or action, the release or commit, the caller configuration and the
steps to reproduce it.

## Scope

These workflows run with the permissions their callers grant. In scope:

- a value from a pull request, a branch name, a tag or a configuration file that becomes shell
  code or reaches a script outside an environment variable;
- a job that requests or receives more permissions than its documentation states;
- a secret that reaches a log, an artifact, a workflow that does not need it, or a pull request
  from a fork;
- a binary or image that is downloaded or run without the verification the documentation states;
- an action or workflow reference that is not pinned to an immutable commit.

Vulnerabilities of the tools the workflows run (Dart, Flutter, Inspectra, Trivy, Writerside, the
third-party actions) belong to those projects; tell us anyway when a pin should move.
