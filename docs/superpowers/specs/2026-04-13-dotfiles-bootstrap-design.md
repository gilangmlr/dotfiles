# Dotfiles Repo — Design Spec

## Context

Build a standalone dotfiles repository suitable for provisioning a zsh-based
development shell on fresh remote workspaces (Coder, GitHub Codespaces,
devcontainers, generic SSH boxes) and local Linux/macOS machines. Motivation:
the user maintains multiple project working directories that already use
`mise` for project-level tool pinning, and wants a matching user-level
environment that boots quickly on any new workspace with zsh, oh-my-zsh +
syntax-highlighting + autosuggestions, `mise` as the sole tool manager,
and the `claude` and `gh` CLIs preinstalled.
The repo must be layout-compatible with the de-facto dotfiles bootstrap
convention used by tools like
[Coder workspaces](https://coder.com/docs/user-guides/workspace-dotfiles)
and
[GitHub Codespaces](https://docs.github.com/en/codespaces/setting-your-user-preferences/personalizing-github-codespaces-for-your-account#dotfiles):
clone the repo, run a single executable install script in the repo root.

Scope decisions made during brainstorming:

- **Standalone repo**, not committed inside any single project. Generic
  enough to reuse across project working directories; no per-project
  content.
- **Linux + macOS** targets. No WSL.
- **Auto-install system deps** (zsh, git, curl, unzip, build-essential) via
  `apt` (Linux) or `brew` (macOS). Prefer non-interactive `sudo -n`; fall
  back to a warning if that fails.
- **`mise` is the single tool installer** for everything installable via
  `mise`. `claude` uses mise's default aqua backend
  (<https://mise-versions.jdx.dev/tools/claude>), so `claude = "latest"` is
  sufficient. No `npm:` backend needed.
- **Starship** for the prompt (installed via `mise`). No Nerd Font
  requirement in the committed config.
- **No git user.name/email** touched by the dotfiles — out of scope.
- **Tool versions track current stable / Active LTS** as of April 2026:
  Node 24 (Active LTS), pnpm 10, Python 3.14, Go 1.26, Ruby 3.4. Each is
  a major (or major.minor) pin so `mise` resolves to the latest patch,
  letting re-runs pick up patches without churning the dotfiles repo.
- **Ruby uses precompiled binaries from `jdx/ruby`** (`ruby.compile =
  false` in the mise settings block). This avoids dragging in
  `libssl-dev` / `libyaml-dev` / `libreadline-dev` / etc. as system
  build deps and shaves ~10 minutes off cold installs.

## Repository Layout

```
dotfiles/
├── install.sh              # bootstrap entry point — chmod +x, idempotent, non-interactive
├── README.md
├── lib/
│   ├── common.sh           # log_info/warn/error, detect_os, has_cmd, run_sudo
│   ├── install-system.sh   # apt (Linux) / brew (macOS) system deps
│   ├── install-zsh.sh      # oh-my-zsh + syntax-highlighting + autosuggestions
│   ├── install-mise.sh     # mise installer + `mise install`
│   └── symlink.sh          # stow-lite file-level linker with backup
├── home/                   # files mapped 1:1 into $HOME
│   ├── .zshenv
│   ├── .zshrc              # thin loader — sources ~/.zshrc.d/*.zsh
│   └── .zshrc.d/
│       ├── 00-omz.zsh
│       ├── 10-plugins.zsh
│       ├── 20-mise.zsh
│       ├── 30-starship.zsh
│       ├── 40-aliases.zsh
│       └── 99-local.zsh    # sources ~/.zshrc.local if present (uncommitted)
└── xdg/                    # files mapped into $XDG_CONFIG_HOME (~/.config)
    ├── mise/config.toml
    └── starship.toml
```

Two mount roots (`home/`, `xdg/`) keep semantics clean so no file under
`home/` has to impersonate `.config/...`.

The `.zshrc.d/NN-*.zsh` drop-in pattern makes each concern independently
understandable and skippable.

## Install Flow

`install.sh` is thin (~50 lines) and calls `lib/*.sh` modules in this order.
Runs safely on every workspace restart (Coder, Codespaces, devcontainers,
local).

1. **Bootstrap guards** — `set -euo pipefail`, set
   `DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`,
   export `PATH="$HOME/.local/bin:$PATH"` (so a just-installed mise is
   findable for the rest of the script), detect `$OS` (`Linux` / `Darwin`),
   choose `SUDO="sudo -n"` if `$EUID != 0` else empty.

2. **System deps** (`lib/install-system.sh`)
   - Linux: `$SUDO apt-get update && $SUDO apt-get install -y zsh git curl unzip ca-certificates build-essential gnupg`
   - macOS: install Homebrew via
     `NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
     if missing, then `brew install zsh git curl gnupg`.
   - Skip cleanly if every required binary (including `gpg`) is already
     present.
   - **Why `gnupg`:** mise's `core:node` backend verifies Node release
     signatures against the Node maintainers' PGP keys before extracting
     the tarball. Without `gpg-agent` available, `mise install node@24`
     fails with `gpg exited with non-zero status: exit code 2`. This
     surfaced on a real Coder workspace running Ubuntu 24.04 noble (which,
     unlike Ubuntu 22.04 jammy, does **not** include `gnupg` in its base
     image). `has_cmd gpg` is part of the system-deps short-circuit guard
     so the fix is forced even on hosts that already have zsh/git/curl.

3. **oh-my-zsh** (`lib/install-zsh.sh`)
   - `RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"`.
     `KEEP_ZSHRC=yes` is critical so omz does not overwrite our `.zshrc`.
   - Clone `zsh-syntax-highlighting` and `zsh-autosuggestions` into
     `$ZSH_CUSTOM/plugins/` (default `~/.oh-my-zsh/custom/plugins/`).
   - Skip clones whose target dir exists.

4. **Install mise binary only** (`lib/install-mise.sh`, first half)
   - `curl https://mise.run | sh` if `~/.local/bin/mise` missing.
   - Do NOT run `mise install` yet — the global config has to be linked
     into `~/.config/mise/config.toml` first.

5. **Symlink configs** (`lib/symlink.sh`)
   - `link_tree "$DOTFILES/home" "$HOME"`
   - `link_tree "$DOTFILES/xdg" "${XDG_CONFIG_HOME:-$HOME/.config}"`
   - File-level linking (not directory-level) so adjacent unmanaged files
     under `~/.config/mise/` etc. survive.
   - If target exists and is not already the right symlink: move to
     `<target>.backup.$(date +%Y%m%d%H%M%S)` and warn.
   - `mkdir -p` parent dirs as needed.

6. **mise install** (`lib/install-mise.sh`, second half)
   - With `~/.config/mise/config.toml` now in place, run `mise install`
     followed by `mise reshim`. This pulls Node 24, pnpm 10, Python 3.14,
     Go 1.26, Ruby 3.4 (precompiled), `gh`, `starship`, and `claude`
     (via aqua).

7. **Set default shell**
   - `chsh -s "$(command -v zsh)" "$USER"`, guarded by: current `$SHELL`
     isn't already zsh AND `/etc/shells` contains the zsh path. Soft-fail
     with a warning otherwise — don't abort the script.

**Ordering rationale**: system deps → omz (needs zsh) → mise binary →
symlinks (so the mise config file is in place) → `mise install` → chsh
last.

**Failure posture**: hard-fail on missing zsh/git/curl. Soft-fail with a
warning on `chsh`, plugin git clones, and individual mise tool failures.

## Configuration File Contents

### `home/.zshenv`

```zsh
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export PATH="$HOME/.local/bin:$PATH"
```

### `home/.zshrc`

```zsh
for f in "$HOME"/.zshrc.d/*.zsh(N); do source "$f"; done
```

### `home/.zshrc.d/00-omz.zsh`

```zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""                # starship takes over
DISABLE_AUTO_UPDATE="true"  # install.sh manages updates
```

### `home/.zshrc.d/10-plugins.zsh`

```zsh
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source "$ZSH/oh-my-zsh.sh"
```

`zsh-syntax-highlighting` must be last in the `plugins=()` list, and in
particular loaded after `zsh-autosuggestions`, per its upstream docs.

### `home/.zshrc.d/20-mise.zsh`

```zsh
command -v mise >/dev/null && eval "$(mise activate zsh)"
```

### `home/.zshrc.d/30-starship.zsh`

```zsh
command -v starship >/dev/null && eval "$(starship init zsh)"
```

### `home/.zshrc.d/40-aliases.zsh`

Generic aliases only — no per-project content. Short list:

```zsh
alias ll='ls -lAh'
alias gs='git status'
alias gd='git diff'
```

### `home/.zshrc.d/99-local.zsh`

```zsh
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
```

Escape hatch for machine-specific exports (work vs personal, project paths,
secrets) without touching committed files.

### `xdg/mise/config.toml`

```toml
[tools]
node = "24"
pnpm = "10"
python = "3.14"
go = "1.26"
ruby = "3.4"
gh = "latest"
starship = "latest"
claude = "latest"

[settings]
# Download precompiled Ruby from jdx/ruby instead of compiling from
# source via ruby-build. Avoids needing libssl-dev / libyaml-dev / etc.
# on every workspace and shaves ~10 minutes off cold installs.
ruby.compile = false
```

All CLIs in one declaration. Versions are major-pinned so `mise` resolves
to the latest patch on every install (Node 24 = Active LTS as of April
2026; Python 3.14 = current stable; Go 1.26 = current stable; pnpm 10 =
current stable, 11.x is still beta; Ruby 3.4 = current stable line).
`claude` resolves to `aqua:anthropics/claude-code` via mise's default
registry. The `[settings]` block makes mise pull a precompiled Ruby tarball
from `jdx/ruby` releases instead of invoking `ruby-build`.

### `xdg/starship.toml`

Minimal (~15 lines), works without a Nerd Font. Start with Starship's sane
defaults plus `add_newline = true` and a trimmed `format` showing dir, git
branch, and relevant language versions. Don't commit the full default.

## Symlink Strategy

`lib/symlink.sh` is ~25 lines:

```
link_tree(source_pkg_dir, target_root):
  for each file under source_pkg_dir:
    rel    = file path relative to source_pkg_dir
    target = target_root/rel
    if target is already a symlink to the expected source → noop
    elif target exists → mv to target.backup.<timestamp>, then symlink
    else mkdir -p parent, then symlink
```

File-level (not directory-level) so unrelated siblings under
`~/.config/mise/` or `~/.zshrc.d/` (e.g. a user-dropped `50-custom.zsh`)
survive re-runs.

## Idempotency Guarantees

Re-running `install.sh` on a provisioned workspace must be a silent no-op:

- System deps: `apt install` / `brew install` are idempotent; we also guard
  with `has_cmd` checks first.
- oh-my-zsh installer: checks `$ZSH` dir; we guard additionally.
- Plugin clones: `[[ -d plugin_dir ]] && skip`.
- mise install: idempotent by design.
- Symlinks: "already correct symlink" branch makes re-run silent.
- `chsh`: guarded by `[[ "$SHELL" == *zsh ]] && skip`.

## Critical Files / Entry Points

- `install.sh` — bootstrap entry point. Must be `chmod +x`. First file in
  the dotfiles bootstrap precedence list shared by Coder and Codespaces
  (`install.sh` → `install` → `bootstrap.sh` → `bootstrap` →
  `script/bootstrap` → `setup.sh` → `setup` → `script/setup`).
- `lib/symlink.sh` — single source of truth for target path resolution and
  backup semantics. Reused by both `home/` and `xdg/` link passes.
- `xdg/mise/config.toml` — single declaration for all managed tools. Deleting
  this file turns `mise install` into a no-op (useful for users who only
  want the shell config).

## Verification

End-to-end testing plan:

1. **Linux clean-room via Docker** (primary test path — mirrors fresh
   Coder/Codespaces/devcontainer semantics). Use `ubuntu:24.04` (noble),
   not 22.04 — noble has a deliberately minimal base image (no `gnupg`,
   no `unzip`) that catches missing-dep bugs that older bases mask:

   ```
   docker run --rm -it ubuntu:24.04 bash
   apt-get update && apt-get install -y sudo curl git
   useradd -m -s /bin/bash test
   echo "test ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
   su - test
   git clone <dotfiles-repo> ~/dotfiles && cd ~/dotfiles && ./install.sh
   ```

   Verify:

   ```
   zsh -i -c 'echo $ZSH_VERSION; echo $plugins; \
     starship --version; mise --version; \
     claude --version; gh --version'
   ```

2. **Idempotency test** — run `./install.sh` a second time in the same
   container. Must exit 0 with no new `.backup.*` files created.

3. **macOS manual test** — run `./install.sh` locally on macOS. Verify brew
   path, `chsh` under interactive shell.

4. **Workspace simulation** — exercise the host-tool entry point in at
   least one of: `coder dotfiles <git-url>` against a real Coder workspace,
   or set the repo as the personal dotfiles in GitHub Codespaces and
   create a fresh codespace. Either is functionally a `git clone +
   ./install.sh` and verifies the layout matches what real-world tools
   expect.

5. **Interactive smoke** — open a new zsh shell, confirm starship prompt
   renders, `Ctrl+Space` accepts autosuggestions, syntax highlighting colors
   unknown commands red until they resolve to a valid binary.

## Out of Scope

- Per-project aliases / paths / helpers — those live in each project repo
  or in the user's uncommitted `~/.zshrc.local` escape hatch.
- `git` user config (`user.name`, `user.email`, signing keys).
- Secrets management (`sops`, `1password`, `age`).
- WSL-specific branches.
- A Brewfile or apt package list beyond the tiny system-deps set — mise
  owns all tool installs.
