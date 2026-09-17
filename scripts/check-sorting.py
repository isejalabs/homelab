#!/usr/bin/env python3
"""Check k8s/**/*.yaml against a subset of .agents/instructions/sorting.md.

Usage: scripts/check-sorting.py
Takes no arguments; run from the repo root (invoked by the check-sorting CI workflow). Walks every
k8s/**/*.yaml file, prints one violation per offending mapping, and exits non-zero if any are found.

Only checks that these fields, whichever are actually present, come first in
a mapping and in this relative order - nothing is asserted about the keys
that follow them:
  1. apiVersion/kind/metadata/name-or-id/namespace/spec, in any mapping at
     any level.
  2. Inside a `metadata:` mapping specifically: name/namespace/annotations/
     labels (its own narrower rule, not the general list above).

Deliberately NOT checked here, since they'd require resource-kind detection
and would conflict with a blanket "sort the rest alphabetically" pass: the
doc's own general alphabetical-everywhere default, Gateway API route-rule
ordering, kustomize `replacements[].targets[]` select/reject-lead ordering,
`kustomization.yaml`'s tiered top-level layout, and Flux `Kustomization`'s
dependsOn-last rule all dictate a non-alphabetical order for the keys that
follow the leading fields - asserting alphabetical there would false-flag
every one of those already-correct, intentionally-non-alphabetical files.
"""

import sys
from pathlib import Path

import yaml

LEADING_FIELDS = ["apiVersion", "kind", "metadata", "name", "id", "namespace", "spec"]
METADATA_FIELDS = ["name", "namespace", "annotations", "labels"]


# Builds the ordered subset of LEADING_FIELDS/METADATA_FIELDS that's actually present in `keys`, in the
# order those fields must appear. `name`/`id` are mutually exclusive (a resource has one or the other), so
# whichever one isn't present in this mapping is dropped rather than asserted absent-but-ordered.
def leading_prefix(keys, is_metadata):
    if is_metadata:
        fields = METADATA_FIELDS
    else:
        fields = list(LEADING_FIELDS)
        fields.remove("id" if "name" in keys else "name")
    return [f for f in fields if f in keys]


# Compares the mapping's actual leading keys against the wanted prefix computed above; only the leading
# slice is checked, so nothing is asserted about key order past that point.
def check_mapping_order(mapping, path, is_metadata, errors):
    keys = list(mapping.keys())
    want = leading_prefix(keys, is_metadata)
    got = keys[: len(want)]
    if got != want:
        errors.append(f"{path}: leading keys out of order\n    got:  {got}\n    want: {want}")


# Recurses through every mapping/list in a parsed YAML document, checking each mapping's leading-key order
# along the way. `parent_key` carries the key this value was found under, so a mapping nested directly under
# a `metadata:` key is checked against METADATA_FIELDS instead of the general LEADING_FIELDS rule.
def walk(value, path, parent_key, errors):
    if isinstance(value, dict):
        check_mapping_order(value, path, parent_key == "metadata", errors)
        for key, child in value.items():
            walk(child, f"{path}.{key}", key, errors)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            walk(item, f"{path}[{index}]", parent_key, errors)


def main():
    # `charts/` directories are vendored third-party Helm chart sources (argocd, sealed-secrets,
    # checkmk-agent, grafana-cloud, ...), not this repo's own manifests - not subject to sorting.md,
    # and not even always valid standalone YAML (Helm templates use non-YAML Go template syntax).
    files = sorted(p for p in Path("k8s").rglob("*.yaml") if "charts" not in p.parts)
    errors = []

    for path in files:
        try:
            docs = list(yaml.safe_load_all(path.read_text()))
        except yaml.YAMLError as exc:
            errors.append(f"{path}: failed to parse: {exc}")
            continue

        multi_doc = len(docs) > 1
        for index, doc in enumerate(docs):
            if doc is None:
                continue
            doc_path = f"{path}[doc {index}]" if multi_doc else str(path)
            walk(doc, doc_path, None, errors)

    if errors:
        print("\n".join(errors), file=sys.stderr)
        print(f"\n{len(errors)} sorting violation(s) found", file=sys.stderr)
        sys.exit(1)

    print(f"OK: {len(files)} files checked, no sorting violations")


if __name__ == "__main__":
    main()
