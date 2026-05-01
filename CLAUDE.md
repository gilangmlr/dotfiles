# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A single-script bootstrap that provisions a zsh + mise shell environment on any of: Coder workspaces, GitHub Codespaces, devcontainers, standalone Linux, or macOS. Layout follows the conventions those platforms expect (`~/dotfiles/install.sh` is auto-run on first attach). `install.sh` is idempotent — every change must keep it safe to re-run.

## Architecture

`install.sh` is a thin orchestrator. It sources every file under `lib/` (`common.sh` first, then `install-*.sh`, then `symlink.sh`) and invokes their top-level functions in order:

1. `install_system_deps` — apt/brew packages
2. `install_omz` — oh-my-zsh + the two plugins
3. `install_mise_binary` — mise CLI (not the runtimes yet)
4. `prune_stale_links` then `link_tree` for `home/` → `$HOME` and `xdg/` → `$XDG_CONFIG_HOME`
5. `run_mise_install` — runs *after* symlinks so the global `xdg/mise/config.toml` is in place
6. `install_claude_native` — Anthropic's installer (NOT via mise, see below)
7. `install_code_server_code_symlink` — workaround for Claude Code IDE detection on code-server
8. `set_default_shell` — `chsh` with stdin redirected from `/dev/null` (PAM-less hosts hang otherwise)

The order matters; don't reshuffle without re-reading `install.sh`.

### Lib conventions

- Every `lib/*.sh` is sourced, never executed. They share state via `set -euo pipefail` from `install.sh`.
- All output goes through `log_info` / `log_warn` / `log_error` from `lib/common.sh` (stderr, colored, `[level]` prefix).
- Privilege escalation goes through `run_sudo` (handles EUID=0, `sudo -n`, and a clean failure mode).
- `lib/symlink.sh` is a file-level stow-lite: `link_one` backs up any pre-existing non-matching file as `<target>.backup.<timestamp>` (these are gitignored). `prune_stale_links` removes dangling symlinks left behind when a source file is renamed/deleted in the repo.

### Symlink layout

- Anything under `home/` is symlinked to the same relative path under `$HOME`.
- Anything under `xdg/` is symlinked to the same relative path under `$XDG_CONFIG_HOME` (defaults to `~/.config`).
- Editing a symlinked file edits the file in this repo. Adding a new file in `home/` or `xdg/` is enough to make it appear in the target tree on the next `install.sh` run — no other registration step.

### zsh load order

`~/.zshrc` is a thin loader that sources `~/.zshrc.d/*.zsh` in glob order, so the numeric prefixes (`00-omz.zsh`, `10-plugins.zsh`, `15-history.zsh`, `20-mise.zsh`, `30-p10k.zsh`, `40-aliases.zsh`, `99-local.zsh`) are load-order-significant. New config goes into a new prefixed file in `home/.zshrc.d/`, not into `.zshrc` — with one documented exception: the **Powerlevel10k instant-prompt block** at the top of `home/.zshrc`. It must be the very first thing sourced (it paints a cached prompt before the rest of the rc finishes), so anything that writes to stdout/stderr above it will break instant prompt. `99-local.zsh` sources `~/.zshrc.local` if present — that's the documented escape hatch for per-machine, uncommitted config.

`home/.zshenv` sets `skip_global_compinit=1` because Debian/Ubuntu's `/etc/zsh/zshrc` runs `compinit` unconditionally and we manage our own. Don't move that line into `.zshrc` — it's too late there.

## Non-obvious decisions to preserve

- **mise runs in shims mode**, not `mise activate`. `home/.zshrc.d/20-mise.zsh` calls `mise activate zsh --shims` deliberately to avoid the ~20–30ms per-prompt cost of `mise hook-env`. Don't "fix" this back to full activate.
- **Powerlevel10k is installed as an oh-my-zsh custom theme** by cloning `romkatv/powerlevel10k` into `$ZSH_CUSTOM/themes/powerlevel10k` from `install_omz` (via the generic `install_omz_extra` helper). The theme is selected with `ZSH_THEME="powerlevel10k/powerlevel10k"` in `00-omz.zsh` and the user-facing config (`home/.p10k.zsh`, symlinked to `~/.p10k.zsh`) is what `p10k configure` writes — currently the **lean** preset with powerline + nerdfont-v3, 24h time, verbose instant prompt. To regenerate, run `p10k configure` and copy the resulting `~/.p10k.zsh` back to `home/.p10k.zsh`. Requires a Nerd Font v3 in the terminal.
- **Claude Code is installed natively**, not via mise. `lib/install-claude.sh` documents why: the in-app updater expects to manage its own binary, and the mise/aqua path lagged releases. Do not re-add `claude = "latest"` to `xdg/mise/config.toml`.
- **`gnupg` is a system dep** because mise's `core:node` backend verifies release tarball signatures with gpg. Ubuntu 24.04 noble doesn't ship gnupg in its base image — removing it from `install_system_deps_linux` will silently break Node installs on fresh workspaces.
- **PostgreSQL build deps** (`bison`, `flex`, `libreadline-dev`, `libssl-dev`, `libicu-dev`, `libxml2-dev`, `uuid-dev`, `zlib1g-dev`) are installed even though no project here uses them — they're there so downstream project repos that pin `postgres = "..."` via mise's vfox-postgres plugin can compile from source. The reasoning is in the header comment of `lib/install-system.sh`.
- **`ruby.compile = false`** in `xdg/mise/config.toml` pulls precompiled Ruby from `jdx/ruby` and avoids ~10 min of build time + extra `-dev` packages. Don't flip it.
- **`chsh` is fed `</dev/null`** in `set_default_shell` — without that redirect, PAM-less Coder/Codespaces images hang on a phantom password prompt.

## Common commands

```bash
~/dotfiles/install.sh        # bootstrap or re-bootstrap; idempotent
mise install                 # re-run runtime installs after editing xdg/mise/config.toml
mise reshim                  # after adding a new tool, refresh shims
```

## Testing changes to install.sh or lib/

`docs/testing.md` has the full procedure. The TL;DR:

- Use `ubuntu:24.04` (noble), **not** 22.04 — noble's minimal base image catches missing-dep bugs that older images mask (this is how the gnupg requirement was originally found).
- Bind-mount the repo read-only and copy it into a non-root user's home, since `install.sh` writes inside `$DOTFILES`.
- Three things must hold: (1) every managed CLI resolves in a fresh `zsh -i`, (2) `~/.zshrc`, `~/.zshenv`, `~/.config/mise/config.toml`, `~/.config/starship.toml` are symlinks back into `$DOTFILES`, (3) a second `install.sh` run produces only `[info] ok ...` lines and no new `*.backup.*` files.
