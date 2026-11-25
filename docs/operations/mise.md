---
status: current
---

# Working with mise

[mise](https://mise.jdx.dev/) installs the tools this repository pins (`just`, `kubectl`, `helm`, `sops`, `flate`, ...). The versions live in the repository; this page covers how to use mise on a developer machine, what its warnings mean and which commands to leave alone. For how Renovate bumps the pins, see [`update-handling.md`](update-handling.md).

## Where the pins live

| File | Holds |
| --- | --- |
| [`.mise.toml`](../../.mise.toml) and [`mise.lock`](../../mise.lock) | Tools shared by several workflows and scripts |
| [`terragrunt/.mise.toml`](../../terragrunt/.mise.toml) and [`terragrunt/mise.lock`](../../terragrunt/mise.lock) | `opentofu`, `talosctl`, `terragrunt` |
| [`k8s/.mise.toml`](../../k8s/.mise.toml) and [`k8s/mise.lock`](../../k8s/mise.lock) | `kustomize`, `kubeconform` |

mise merges every `.mise.toml` it finds from the current directory upwards, so a tool in `terragrunt/` or `k8s/` is only available there. The split is explained in [`architecture/ci.md`](../architecture/ci.md).

Renovate owns the pins and the lockfiles. A tool version changes through a Renovate PR or a normal PR, never by running a mise command on a laptop.

## Fresh checkout

Run this in the repository root, in `terragrunt/` and in `k8s/`:

```sh
mise install
```

Each `.mise.toml` sets `locked = true`, so `mise install` already behaves as `mise install --locked`: it installs exactly what `mise.lock` records, checks the stored checksums and does not rewrite the lockfile. Repeat the command after pulling a Renovate bump to get the new version.

## The two warnings

### `missing: <tool>@<version>`

The pinned version is not installed on this machine yet, usually after a Renovate bump. Run `mise install` in the folder the warning comes from. Nothing else is needed and the lockfile stays unchanged.

### `<tool>@latest is not in the lockfile`

This repository does not use that tool (it was `uv` the first time). It comes from your own global config, `~/.config/mise/config.toml`, with a version of `latest`. Because the repository sets `locked = true`, mise refuses to resolve `latest` for a tool that `mise.lock` does not list, and prints a hint to run `mise install` without `--locked`. Do not follow that hint: it would rewrite a lockfile that Renovate owns.

Fix it in the global config, not in the repository:

- Remove the tool if you do not need it: `mise unuse -g <tool>`.
- Or pin a concrete version instead of `latest`: `mise use -g <tool>@<version>`. Check afterwards that the warning is gone inside the repository; a tool without a lock entry can still warn there.

## Commands

### Everyday

| Command | Use |
| --- | --- |
| `mise install` | Install the pinned tools of the current directory. Safe, never touches the lock. |
| `mise ls --missing` | List pinned tools that are not installed. |
| `mise ls --current` | Show the version in use and the config file it comes from. |
| `mise outdated` | Show which tools have a newer version. Read-only. |
| `mise self-update` | Update mise itself. |
| `mise prune --dry-run` | Preview which old versions no config references any more, then run `mise prune` to remove them. |

### Investigating a problem

| Command | Use |
| --- | --- |
| `mise config ls` | Which config files apply here, and which tools each one adds. |
| `mise which <tool>` | Which binary a command resolves to. |
| `mise doctor` | Check the mise setup, `PATH` and shell activation. |
| `mise install --locked <tool>` | Explicit locked install of one tool. The same as the default here. |

### Do not use

| Command | Why |
| --- | --- |
| `mise lock` | It rewrites `mise.lock`, which Renovate owns. |
| `mise use <tool>@<version>` in the repository | It edits `.mise.toml` and the lock. |
| `mise upgrade` | It bumps pinned versions. |
| `mise install --no-locked` | It resolves versions outside the lockfile and gives up the pin guarantee. |
| `mise use -g <tool>@latest` | A global `latest` is what causes the `is not in the lockfile` warning inside this repository. |
