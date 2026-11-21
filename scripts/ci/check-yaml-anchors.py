#!/usr/bin/env python3
"""Checks the YAML-anchor convention of AGENTS.md ("YAML anchors for values that must stay identical").

Inside one Flux manifest under k8s/, a value that is equal by construction has to be stated once and reused as an
alias (`&name` / `*name`), not typed twice:

  HelmRelease    metadata.name  ==  spec.chartRef.name, spec.chart.spec.chart, spec.chart.spec.sourceRef.name
  Kustomization  metadata.name  ==  an entry's `name` in spec.healthChecks

The check composes the YAML (not loads it), so it can tell an alias from a copy: an alias resolves to the very node
of its anchor, a copy is a separate node with the same text. It fires only for these named constructions, never for
"could have been an alias" in general (a lint for that would mostly false-positive, see AGENTS.md). `charts/` and
`vendor/` directories are skipped, like in check-sorting.py.

Usage: scripts/ci/check-yaml-anchors.py
Takes no arguments; run from the repo root (invoked by the check-sorting CI workflow, needs scripts/ci/requirements.txt
installed). Exits 1 and lists every violation as `file: path: message`.
"""
import sys
from pathlib import Path

import yaml


# Returns the mapping value node for `key` in a MappingNode, or None.
def get(node, key):
    if not isinstance(node, yaml.MappingNode):
        return None
    for k, v in node.value:
        if isinstance(k, yaml.ScalarNode) and k.value == key:
            return v
    return None


# Follows a key path through nested mappings, returning the node at the end or None.
def dig(node, *keys):
    for key in keys:
        node = get(node, key)
        if node is None:
            return None
    return node


# Appends an error for each candidate that repeats the scalar value of `name_node` without being the same node,
# i.e. a hand-typed copy instead of an alias.
def check_candidates(name_node, candidates, doc_path, errors):
    for where, node in candidates:
        if isinstance(node, yaml.ScalarNode) and node.value == name_node.value and node is not name_node:
            errors.append(
                f"{doc_path}: {where}: repeats metadata.name '{name_node.value}', "
                "anchor it (`metadata.name: &name ...`) and use `*name`"
            )


# Checks one composed document (a MappingNode) of a Flux HelmRelease or Kustomization.
def check_doc(root, doc_path, errors):
    api = get(root, "apiVersion")
    kind = get(root, "kind")
    name = dig(root, "metadata", "name")
    if not (api and kind and isinstance(name, yaml.ScalarNode)):
        return
    if kind.value == "HelmRelease" and api.value.startswith("helm.toolkit.fluxcd.io/"):
        candidates = [
            ("spec.chartRef.name", dig(root, "spec", "chartRef", "name")),
            ("spec.chart.spec.chart", dig(root, "spec", "chart", "spec", "chart")),
            ("spec.chart.spec.sourceRef.name", dig(root, "spec", "chart", "spec", "sourceRef", "name")),
        ]
        check_candidates(name, [c for c in candidates if c[1] is not None], doc_path, errors)
    elif kind.value == "Kustomization" and api.value.startswith("kustomize.toolkit.fluxcd.io/"):
        checks = dig(root, "spec", "healthChecks")
        if isinstance(checks, yaml.SequenceNode):
            candidates = [(f"spec.healthChecks[{i}].name", get(item, "name")) for i, item in enumerate(checks.value)]
            check_candidates(name, [c for c in candidates if c[1] is not None], doc_path, errors)


def main():
    files = sorted(p for p in Path("k8s").rglob("*.yaml") if not {"charts", "vendor"} & set(p.parts))
    errors = []
    for path in files:
        try:
            docs = list(yaml.compose_all(path.read_text()))
        except yaml.YAMLError:
            # Unparseable files (Helm templates etc.) are check-sorting.py's and kustomize-build's business.
            continue
        multi_doc = len(docs) > 1
        for index, doc in enumerate(docs):
            if doc is not None:
                check_doc(doc, f"{path}[doc {index}]" if multi_doc else str(path), errors)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        print(f"\n{len(errors)} YAML anchor violation(s) found", file=sys.stderr)
        sys.exit(1)
    print(f"OK: {len(files)} files checked, no YAML anchor violations")


if __name__ == "__main__":
    main()
