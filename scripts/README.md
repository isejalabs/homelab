# Scripts

Helper scripts that don't belong to a single `k8s/`/`terragrunt/` unit, grouped by how they are run. Each folder has its own README with the index of its scripts; each script documents its purpose and usage in a header comment, and the READMEs are indexes, not duplicates of that. Every file below `scripts/` must be linked from its nearest `README.md` — [`ci/check-scripts-index.sh`](ci/check-scripts-index.sh) fails CI otherwise.

| Folder | What lives there | Run by |
| --- | --- | --- |
| [`ci/`](ci/README.md) | validation entry points and the helpers they need (`requirements.txt`, tool installers) | the `.github/workflows/*.yml` on every PR and push to `main`; also runnable locally |
| [`ops/`](ops/README.md) | operational scripts per domain (`kopiur`, `longhorn`, `keycloak`, `proxmox`) with the `just` module that wraps them as `mod.just` | `just <module>::<recipe>`, mostly not directly |
| [`tools/`](tools/README.md) | stand-alone scripts: SOPS bulk operations, Terragrunt state cleanup, Checkmk and RustFS checks | a human, by hand |
| [`agent/`](agent/README.md) | the Mink hook adapter for Codex and its tests | Codex, through `.codex/hooks.json` |
| [`lib/`](lib/README.md) | shell code shared by the scripts above | sourced by them, never run |

## Where a new script goes

- Called by a workflow in `.github/workflows/` → `ci/`.
- Wrapped by a `just` recipe → `ops/<domain>/`, together with its `mod.just`; a new domain gets its own folder and README (see [`ops/README.md`](ops/README.md)).
- Anything else a human runs → `tools/`.
- Used by a coding agent's tooling rather than by the repo's workflow → `agent/`.
- Sourced by more than one script → `lib/`; code only one domain needs can stay in the script.

Then add its row to the README of that folder (the index check enforces it) and give every function a comment — see [`.agents/instructions/shell-scripts.md`](../.agents/instructions/shell-scripts.md).

## Conventions

- Shell scripts default to `#!/bin/sh` unless a feature genuinely requires bash (e.g. arrays, `[[ ]]`, `set -o pipefail`); the `longhorn` and `proxmox` scripts, `ops/kopiur/create.sh` and the SOPS bulk scripts are bash, the rest is POSIX `sh`.
- A script finds `lib/` through `SCRIPTS_DIR`, which every script sets to this folder itself: `$(dirname -- "$0")/..` in `ci/` and `tools/`, `/../..` in `ops/<domain>/` (the exact line is in the usage comment of [`lib/common.sh`](lib/common.sh)). The `check-*` scripts derive the repo root from it.
