#!/usr/bin/env python3
"""Generates schemas/davils-ci.schema.json from actions/resolve-config/defaults.yaml.

The defaults are the single source of every option: their structure becomes the schema, their
values its defaults. What a default cannot say (the allowed values of a choice) is listed in
CHOICES below. Run tools/gen-schema.sh; self-lint fails when the committed schema is stale.

Reads the defaults as JSON on stdin (yq -o=json) and writes the schema to stdout.
"""

import json
import sys

TOGGLE = "auto"

# The allowed values of options that are choices, by dotted path ("*" matches any key).
CHOICES = {
    "packages.external-path-dependencies": ["error", "warn"],
    "packages.affected-only": ["auto", True, False],
    "packages.granularity": ["auto", "package", "workspace", "shards"],
    "dart.coverage.source": ["auto", "dart-ci", "inspectra", "none"],
    "flutter.coverage.source": ["auto", "flutter-ci", "inspectra", "none"],
    "flutter.golden.os": ["ubuntu", "macos", "windows"],
    "flutter.integration-test.device": ["auto", "linux", "macos", "windows"],
    "inspectra.install": ["auto", "dev-dependency", "global", "binary"],
    "inspectra.check.root": ["auto", True, False],
    "inspectra.scan.fail-on": ["", "critical", "high", "medium", "low", "unknown", "none"],
    "inspectra.scan.min-severity": ["", "critical", "high", "medium", "low", "unknown"],
    "inspectra.trivy.mode": ["", "auto", "required", "disabled"],
    "writerside.builder": ["docker", "action"],
    "pages.landing-page": ["auto", True, False],
    "build.flutter.targets.*": ["auto", True, False],
    "build.flutter.build-mode": ["release", "profile", "debug"],
    "build.flutter.android-signing": ["auto", True, False],
    "build.flutter.apple-signing": ["auto", True, False],
    "build.dart-compile.archive": ["zip", "tar.gz"],
    "release.mode": ["auto", "none", "tag", "release-please"],
    "release.github.notes-source": ["auto", "inspectra", "changelog", "generate", "file", "keep"],
    "release.github.make-latest": ["auto", True, False],
    "release.release-please.token-source": ["app", "pat", "github-token"],
    "security.harden-runner.egress-policy": ["audit", "block"],
}

ITEMS = {
    "dart.os": {"enum": ["ubuntu", "ubuntu-arm", "macos", "windows", "windows-arm"]},
    "flutter.os": {"enum": ["ubuntu", "ubuntu-arm", "macos", "windows", "windows-arm"]},
    "build.dart-compile.targets": {
        "enum": ["linux-x64", "linux-arm64", "macos-arm64", "macos-x64", "windows-x64", "windows-arm64"]
    },
    "build.dart-compile.executables": {
        "type": "object",
        "additionalProperties": False,
        "required": ["package", "entrypoint"],
        "properties": {
            "package": {"type": "string"},
            "entrypoint": {"type": "string"},
            "name": {"type": "string"},
        },
    },
    "pr.title.types": {"type": "string"},
}

DESCRIPTIONS = {
    "version": "The version of this file's format.",
    "project": "Where the project lives and which branches it uses.",
    "packages": "Which packages the workflows find and how they spread over jobs.",
    "dart": "Format, analyze, test and coverage of the Dart packages.",
    "flutter": "Format, analyze, test and coverage of the Flutter packages.",
    "inspectra": "Supply-chain scans and quality gates with Inspectra.",
    "writerside": "The Writerside documentation.",
    "dartdoc": "The API documentation of the published packages.",
    "pages": "The GitHub Pages site assembled from the documentation, API docs and web builds.",
    "build": "Build artifacts: Flutter apps and native Dart executables.",
    "release": "Releases: verification, pub.dev, GitHub releases, release-please.",
    "pr": "Checks of pull requests: the title and the source branch.",
    "security": "Hardening of the runners.",
    "hooks": "Shell commands run at fixed points of every job.",
    "runners": "Runner labels; a list of labels selects self-hosted runners.",
    "dependencies": "Private package hosts and git dependencies.",
    "timeouts": "Job timeouts in minutes.",
    "artifacts": "Artifact settings.",
    "when": "When the feature runs: events (push is a branch push, tag a tag push), branch globs, path globs.",
}


def match(path, pattern_map):
    if path in pattern_map:
        return pattern_map[path]
    parent, _, _ = path.rpartition(".")
    wildcard = parent + ".*"
    return pattern_map.get(wildcard)


def node(value, path):
    key = path.rpartition(".")[2]
    schema = {}
    choices = match(path, CHOICES)
    if key == "when":
        schema = {"$ref": "#/$defs/when"}
    elif path.startswith("runners."):
        schema = {"anyOf": [{"type": "string"}, {"type": "array", "items": {"type": "string"}}]}
    elif choices is not None:
        schema = {"$ref": "#/$defs/toggle"} if set(map(str, choices)) == {"auto", "True", "False"} else {"enum": choices}
    elif key == "enabled":
        schema = {"$ref": "#/$defs/toggle"}
    elif isinstance(value, bool):
        schema = {"type": "boolean"}
    elif isinstance(value, int):
        schema = {"type": "integer", "minimum": 0}
    elif isinstance(value, str):
        schema = {"type": "string"}
    elif isinstance(value, list):
        schema = {"type": "array", "items": match(path, ITEMS) or {"type": "string"}}
    elif isinstance(value, dict):
        schema = {
            "type": "object",
            "additionalProperties": False,
            "properties": {k: node(v, f"{path}.{k}" if path else k) for k, v in value.items()},
        }
    if key in DESCRIPTIONS and "$ref" not in schema:
        schema["description"] = DESCRIPTIONS[key]
    if not isinstance(value, dict) and key != "when":
        schema["default"] = value
    return schema


def main():
    defaults = json.load(sys.stdin)
    root = node(defaults, "")
    root["properties"]["version"] = {"const": 1, "description": DESCRIPTIONS["version"]}
    schema = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://raw.githubusercontent.com/davils-com/workflows/v1/schemas/davils-ci.schema.json",
        "title": "davils-com/workflows configuration (.github/davils-ci.yaml)",
        "description": "Generated from actions/resolve-config/defaults.yaml by tools/gen-schema.sh. Do not edit by hand.",
        "type": "object",
        "additionalProperties": False,
        "required": ["version"],
        "properties": root["properties"],
        "$defs": {
            "toggle": {
                "description": "true, false or auto (on when the repository has what the feature needs); on and off work as well.",
                "anyOf": [{"type": "boolean"}, {"enum": ["auto", "true", "false", "on", "off"]}],
            },
            "when": {
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "events": {
                        "type": "array",
                        "items": {
                            "enum": [
                                "push", "tag", "pull_request", "merge_group", "schedule",
                                "workflow_dispatch", "workflow_call", "release", "repository_dispatch",
                            ]
                        },
                    },
                    "branches": {"type": "array", "items": {"type": "string"}},
                    "paths": {"type": "array", "items": {"type": "string"}},
                },
            },
        },
    }
    json.dump(schema, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
