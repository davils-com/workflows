#!/usr/bin/env python3
"""Generates .github/workflows/flutter-ci.yml from the inputs of dart-ci.yml.

flutter-ci.yml calls dart-ci.yml with `toolchain: flutter`. Its inputs are the ones of dart-ci.yml
with Flutter defaults, `sdks` renamed to `flutter-versions` and the Dart only inputs left out, so
the two workflows cannot drift apart. Run tools/gen-flutter-ci.sh; self-lint fails when the
committed file is stale.

Reads the inputs of dart-ci.yml as JSON on stdin and writes the workflow to stdout.
"""

import json
import sys

DART_ONLY = {"toolchain", "pana-enabled", "pana-min-points"}
RENAME = {"sdks": "flutter-versions"}
OVERRIDES = {
    "flutter-versions": {
        "description": "JSON array of Flutter versions to test with: stable, beta, lowest (the lower bound of environment.flutter) or a version.",
        "default": '["stable"]',
    },
    "format-command": {"description": "Replaces dart format --output=none --set-exit-if-changed ."},
    "analyze-command": {"description": "Replaces flutter analyze per package."},
    "build-runner-command": {"description": "Replaces flutter pub run build_runner build --delete-conflicting-outputs."},
    "test-platforms": None,
}

HEADER = """name: Flutter CI

# Format, analyze, test and coverage of every Flutter package of a repository, plus golden tests,
# integration tests on a desktop device and the check of generated localizations. This file only
# passes its inputs on to dart-ci.yml with `toolchain: flutter`.
#
# Generated from the inputs of dart-ci.yml by tools/gen-flutter-ci.sh. Do not edit by hand.

on:
  workflow_call:
    inputs:
"""


def scalar(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    if text and all(c.isalnum() or c in "-._/" for c in text) and text not in ("true", "false"):
        return text
    return "'" + text.replace("'", "''") + "'"


def main():
    inputs = json.load(sys.stdin)
    lines = [HEADER.rstrip("\n")]
    passthrough = []
    for name, spec in inputs.items():
        if name in DART_ONLY:
            continue
        if name in OVERRIDES and OVERRIDES[name] is None:
            continue
        public = RENAME.get(name, name)
        spec = dict(spec)
        spec.update(OVERRIDES.get(public, {}) or {})
        lines.append(f"      {public}:")
        lines.append(f"        description: {json.dumps(spec['description'])}")
        lines.append(f"        type: {spec['type']}")
        lines.append(f"        default: {scalar(spec.get('default', ''))}")
        passthrough.append((name, public))
    lines.append("")
    lines.append("    secrets:")
    for secret in ("PUB_HOSTED_TOKEN", "GIT_DEPS_TOKEN", "CODECOV_TOKEN"):
        lines.append(f"      {secret}:")
        lines.append("        required: false")
    lines.append("")
    lines.append("    outputs:")
    lines.append("      coverage:")
    lines.append("        description: The total line coverage in percent.")
    lines.append("        value: ${{ jobs.flutter.outputs.coverage }}")
    lines.append("      discovery:")
    lines.append("        description: The discovered packages.")
    lines.append("        value: ${{ jobs.flutter.outputs.discovery }}")
    lines.append("")
    lines.append("permissions: {}")
    lines.append("")
    lines.append("jobs:")
    lines.append("  flutter:")
    lines.append("    name: Flutter")
    lines.append("    uses: $/.github/workflows/dart-ci.yml")
    lines.append("    permissions:")
    lines.append("      contents: read")
    lines.append("    secrets:")
    for secret in ("PUB_HOSTED_TOKEN", "GIT_DEPS_TOKEN", "CODECOV_TOKEN"):
        lines.append(f"      {secret}: ${{{{ secrets.{secret} }}}}")
    lines.append("    with:")
    lines.append("      toolchain: flutter")
    for name, public in passthrough:
        lines.append(f"      {name}: ${{{{ inputs.{public} }}}}")
    sys.stdout.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
