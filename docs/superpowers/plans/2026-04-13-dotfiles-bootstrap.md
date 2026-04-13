# Dotfiles Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone dotfiles repo at `~/dotfiles` that provisions a zsh + oh-my-zsh (syntax-highlighting + autosuggestions) + mise (managing `claude`, `gh`, Node 24, pnpm 10, Python 3.14, Go 1.26, Ruby 3.4, Starship) environment on fresh Linux/macOS machines via a single executable `install.sh`. Layout-compatible with the dotfiles bootstrap convention used by Coder, GitHub Codespaces, devcontainers, and standalone use. Designed to be reused across any number of project working directories; contains zero per-project content. Ruby uses precompiled binaries from `jdx/ruby` so the bootstrap doesn't need `libssl-dev`/`libyaml-dev`/etc. as system build deps.

**Architecture:** File-level stow-lite symlinking from `home/` → `$HOME` and `xdg/` → `$XDG_CONFIG_HOME`. Thin 7-step `install.sh` sources `lib/*.sh` modules; each module has a single responsibility. Idempotent: re-runs are silent no-ops. Non-interactive: `RUNZSH=no CHSH=no KEEP_ZSHRC=yes` for omz, `NONINTERACTIVE=1` for brew, `sudo -n` for apt.

**Tech Stack:** bash 5.x, zsh, oh-my-zsh, mise (aqua backend), Starship, shellcheck for lint, Docker (Ubuntu 22.04) for integration testing.

**Design spec:** [`../specs/2026-04-13-dotfiles-bootstrap-design.md`](../specs/2026-04-13-dotfiles-bootstrap-design.md)

---

## File Structure

Complete list of files created by this plan. Each has a single responsibility.

| Path                                       | Purpose                                                            |
| ------------------------------------------ | ------------------------------------------------------------------ |
| `~/dotfiles/README.md`                     | Usage, manual steps (`chsh` hint), local override file             |
| `~/dotfiles/.gitignore`                    | Ignore `.backup.*`, `*.swp`, `.DS_Store`                           |
| `~/dotfiles/install.sh`                    | Bootstrap entry point; sources `lib/*.sh` and calls functions in order |
| `~/dotfiles/lib/common.sh`                 | `log_info/warn/error`, `has_cmd`, `detect_os`, `run_sudo`          |
| `~/dotfiles/lib/install-system.sh`         | apt (Linux) / brew (macOS) system deps                             |
| `~/dotfiles/lib/install-zsh.sh`            | oh-my-zsh + two plugin clones                                      |
| `~/dotfiles/lib/install-mise.sh`           | mise binary install + `mise install` runner                        |
| `~/dotfiles/lib/symlink.sh`                | `link_tree` / `link_one` file-level stow-lite                      |
| `~/dotfiles/home/.zshenv`                  | XDG env vars + PATH prepend                                        |
| `~/dotfiles/home/.zshrc`                   | Thin loader for `~/.zshrc.d/*.zsh`                                 |
| `~/dotfiles/home/.zshrc.d/00-omz.zsh`      | omz vars, empty theme                                              |
| `~/dotfiles/home/.zshrc.d/10-plugins.zsh`  | plugin list + source omz                                           |
| `~/dotfiles/home/.zshrc.d/20-mise.zsh`     | mise activate                                                      |
| `~/dotfiles/home/.zshrc.d/30-starship.zsh` | starship init                                                      |
| `~/dotfiles/home/.zshrc.d/40-aliases.zsh`  | Generic aliases                                                    |
| `~/dotfiles/home/.zshrc.d/99-local.zsh`    | Escape-hatch `source ~/.zshrc.local`                               |
| `~/dotfiles/xdg/mise/config.toml`          | Global mise tool declarations                                      |
| `~/dotfiles/xdg/starship.toml`             | Minimal starship config, no Nerd Font                              |

**TDD adaptation for shell:** unit-level "tests" are `shellcheck <file>` (lint) plus a smoke invocation where feasible. End-to-end test is the Docker clean-room in Task 10.

---

## Task 0: Repo Scaffold

**Files:**

- Create: `~/dotfiles/README.md`
- Create: `~/dotfiles/.gitignore`
- Create: `~/dotfiles/lib/` (dir)
- Create: `~/dotfiles/home/.zshrc.d/` (dir)
- Create: `~/dotfiles/xdg/mise/` (dir)

- [ ] **Step 1: Create directory skeleton**

```bash
mkdir -p ~/dotfiles/lib ~/dotfiles/home/.zshrc.d ~/dotfiles/xdg/mise
cd ~/dotfiles
git init -b main
```

- [ ] **Step 2: Create `.gitignore`**

`~/dotfiles/.gitignore`:

```
*.backup.*
*.swp
.DS_Store
```

- [ ] **Step 3: Create placeholder `README.md`** (finalized in Task 9)

`~/dotfiles/README.md`:

```markdown
# dotfiles

Single-script bootstrap for a zsh + mise shell environment. Compatible
with [Coder workspaces](https://coder.com/docs/user-guides/workspace-dotfiles),
[GitHub Codespaces](https://docs.github.com/en/codespaces/setting-your-user-preferences/personalizing-github-codespaces-for-your-account#dotfiles),
devcontainers, and standalone use on Linux/macOS.

## Install

    git clone <this-repo> ~/dotfiles
    ~/dotfiles/install.sh

Full documentation will be added once implementation is complete.
```

- [ ] **Step 4: Verify scaffold**

```bash
ls -la ~/dotfiles
```

Expected: `README.md`, `.gitignore`, `lib/`, `home/.zshrc.d/`, `xdg/mise/` all present.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add README.md .gitignore
git commit -m "chore: initial repo scaffold"
```

---

## Task 1: `lib/common.sh` — shared helpers

**Files:**

- Create: `~/dotfiles/lib/common.sh`

- [ ] **Step 1: Write `lib/common.sh`**

`~/dotfiles/lib/common.sh`:

```bash
#!/usr/bin/env bash
# Shared helpers sourced by other lib scripts and install.sh.
# Do NOT run directly; this file is meant to be sourced.

# Colored logging writes to stderr so callers' stdout stays clean.
log_info()  { printf '\033[34m[info]\033[0m  %s\n' "$*" >&2; }
log_warn()  { printf '\033[33m[warn]\033[0m  %s\n' "$*" >&2; }
log_error() { printf '\033[31m[error]\033[0m %s\n' "$*" >&2; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

detect_os() {
  case "$(uname -s)" in
    Linux)  echo linux ;;
    Darwin) echo macos ;;
    *)      echo unknown ;;
  esac
}

# Run a command as root: directly if EUID=0, else via non-interactive sudo.
# Returns non-zero if privilege escalation isn't available.
run_sudo() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  elif has_cmd sudo && sudo -n true 2>/dev/null; then
    sudo "$@"
  else
    log_error "need sudo to run: $*"
    return 1
  fi
}
```

- [ ] **Step 2: Lint with shellcheck**

```bash
shellcheck ~/dotfiles/lib/common.sh
```

Expected: no output, exit 0. If `shellcheck` is not installed, `sudo apt-get install -y shellcheck` (Linux) or `brew install shellcheck` (macOS).

- [ ] **Step 3: Smoke test — source and call helpers**

```bash
bash -c 'set -eu; source ~/dotfiles/lib/common.sh; log_info "hello from common.sh"; detect_os; has_cmd bash && echo "has_cmd works"'
```

Expected output includes `[info]  hello from common.sh`, the current OS (`linux` or `macos`), and `has_cmd works`.

- [ ] **Step 4: Commit**

```bash
cd ~/dotfiles
git add lib/common.sh
git commit -m "feat: add common.sh with logging, os detection, sudo helper"
```

---

## Task 2: `lib/install-system.sh` — OS package installer

**Files:**

- Create: `~/dotfiles/lib/install-system.sh`

- [ ] **Step 1: Write `lib/install-system.sh`**

`~/dotfiles/lib/install-system.sh`:

```bash
#!/usr/bin/env bash
# Install system packages required before shell setup (zsh, git, curl, unzip).
# Must be sourced after lib/common.sh.

install_system_deps() {
  local os
  os="$(detect_os)"
  case "$os" in
    linux) install_system_deps_linux ;;
    macos) install_system_deps_macos ;;
    *)     log_error "unsupported OS: $os"; return 1 ;;
  esac
}

install_system_deps_linux() {
  if has_cmd zsh && has_cmd git && has_cmd curl && has_cmd unzip; then
    log_info "system deps already present"
    return 0
  fi
  log_info "installing system deps via apt"
  run_sudo apt-get update
  run_sudo apt-get install -y \
    zsh git curl unzip ca-certificates build-essential
}

install_system_deps_macos() {
  if ! has_cmd brew; then
    log_info "installing Homebrew"
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Put brew on PATH for the rest of the script.
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi
  if has_cmd zsh && has_cmd git && has_cmd curl; then
    log_info "system deps already present"
    return 0
  fi
  log_info "installing system deps via brew"
  brew install zsh git curl
}
```

- [ ] **Step 2: Lint with shellcheck**

```bash
shellcheck -x -e SC1091 ~/dotfiles/lib/install-system.sh
```

The `-e SC1091` silences the warning about sourced files not found (we don't source anything from this file).
Expected: exit 0.

- [ ] **Step 3: Smoke test — source alongside common.sh and verify function exists**

```bash
bash -c 'set -eu
source ~/dotfiles/lib/common.sh
source ~/dotfiles/lib/install-system.sh
declare -F install_system_deps && echo "function defined"
'
```

Expected: prints `install_system_deps` and `function defined`. Do NOT call the function here — it mutates system state.

- [ ] **Step 4: Commit**

```bash
cd ~/dotfiles
git add lib/install-system.sh
git commit -m "feat: add install-system.sh for apt/brew bootstrap"
```

---

## Task 3: `lib/install-zsh.sh` — oh-my-zsh + plugins

**Files:**

- Create: `~/dotfiles/lib/install-zsh.sh`

- [ ] **Step 1: Write `lib/install-zsh.sh`**

`~/dotfiles/lib/install-zsh.sh`:

```bash
#!/usr/bin/env bash
# Install oh-my-zsh and the two user-requested plugins. Idempotent.
# Must be sourced after lib/common.sh.

install_omz() {
  local zsh_dir="${ZSH:-$HOME/.oh-my-zsh}"

  if [[ -d "$zsh_dir" ]]; then
    log_info "oh-my-zsh already installed at $zsh_dir"
  else
    log_info "installing oh-my-zsh"
    # KEEP_ZSHRC=yes only protects a *pre-existing* .zshrc. On a fresh
    # machine with no .zshrc, omz still writes one from its template.
    # Track whether .zshrc existed before so we can clean up that
    # template afterwards (and avoid a spurious backup at link time).
    local had_zshrc=no
    [[ -e "$HOME/.zshrc" || -L "$HOME/.zshrc" ]] && had_zshrc=yes
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    if [[ "$had_zshrc" == "no" \
       && -f "$HOME/.zshrc" \
       && ! -L "$HOME/.zshrc" ]]; then
      log_info "removing omz template .zshrc (will be replaced by symlink)"
      rm -f "$HOME/.zshrc"
    fi
  fi

  local custom="${ZSH_CUSTOM:-$zsh_dir/custom}"
  install_omz_plugin \
    https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$custom/plugins/zsh-syntax-highlighting"
  install_omz_plugin \
    https://github.com/zsh-users/zsh-autosuggestions.git \
    "$custom/plugins/zsh-autosuggestions"
}

install_omz_plugin() {
  local url="$1" dest="$2"
  if [[ -d "$dest" ]]; then
    log_info "plugin already present: $(basename "$dest")"
    return 0
  fi
  log_info "cloning $(basename "$dest")"
  git clone --depth 1 "$url" "$dest" \
    || log_warn "failed to clone $url (soft-fail)"
}
```

> **Note:** the `had_zshrc` / `rm -f` block was added during integration
> testing. The Docker clean-room test exposed that omz writes a fresh
> `~/.zshrc` from its template even with `KEEP_ZSHRC=yes` — that flag
> only protects a *pre-existing* file, not the case where none exists.
> Without this cleanup, `link_tree` later finds the template, backs it
> up with a timestamp, and replaces it — leaving a `.zshrc.backup.*`
> file behind on every fresh install. The plan is updated to reflect
> the corrected version.

- [ ] **Step 2: Lint with shellcheck**

```bash
shellcheck -x -e SC1091 ~/dotfiles/lib/install-zsh.sh
```

Expected: exit 0.

- [ ] **Step 3: Smoke test — function is defined**

```bash
bash -c 'set -eu
source ~/dotfiles/lib/common.sh
source ~/dotfiles/lib/install-zsh.sh
declare -F install_omz install_omz_plugin
'
```

Expected: prints both function names.

- [ ] **Step 4: Commit**

```bash
cd ~/dotfiles
git add lib/install-zsh.sh
git commit -m "feat: add install-zsh.sh for oh-my-zsh and plugins"
```

---

## Task 4: `lib/install-mise.sh` — mise binary + tool install

**Files:**

- Create: `~/dotfiles/lib/install-mise.sh`

- [ ] **Step 1: Write `lib/install-mise.sh`**

`~/dotfiles/lib/install-mise.sh`:

```bash
#!/usr/bin/env bash
# Install the mise binary and (separately) run `mise install` against the
# global config. Must be sourced after lib/common.sh.

install_mise_binary() {
  if has_cmd mise; then
    log_info "mise already installed"
    return 0
  fi
  log_info "installing mise"
  curl -fsSL https://mise.run | sh
  # mise.run installs to ~/.local/bin; ensure it's on PATH for the rest of
  # this script even though .zshenv would add it for interactive shells.
  export PATH="$HOME/.local/bin:$PATH"
  if ! has_cmd mise; then
    log_error "mise installation failed"
    return 1
  fi
}

# Called AFTER the global mise config has been symlinked into place.
run_mise_install() {
  if ! has_cmd mise; then
    log_error "mise not found on PATH"
    return 1
  fi
  log_info "running mise install"
  if ! mise install; then
    log_warn "mise install had failures (non-fatal; re-run later)"
  fi
  mise reshim
}
```

- [ ] **Step 2: Lint with shellcheck**

```bash
shellcheck -x -e SC1091 ~/dotfiles/lib/install-mise.sh
```

Expected: exit 0.

- [ ] **Step 3: Smoke test**

```bash
bash -c 'set -eu
source ~/dotfiles/lib/common.sh
source ~/dotfiles/lib/install-mise.sh
declare -F install_mise_binary run_mise_install
'
```

Expected: prints both function names.

- [ ] **Step 4: Commit**

```bash
cd ~/dotfiles
git add lib/install-mise.sh
git commit -m "feat: add install-mise.sh for mise binary and tool install"
```

---

## Task 5: `lib/symlink.sh` — stow-lite file linker

**Files:**

- Create: `~/dotfiles/lib/symlink.sh`

This task includes an actual functional test (not just lint) because symlink logic has edge cases that deserve verification.

- [ ] **Step 1: Write `lib/symlink.sh`**

`~/dotfiles/lib/symlink.sh`:

```bash
#!/usr/bin/env bash
# File-level stow-lite: link every file under a source package directory
# into the corresponding path under a target root, backing up any existing
# non-matching file. Must be sourced after lib/common.sh.

# link_tree <source_pkg_dir> <target_root>
link_tree() {
  local src="$1" dst="$2"
  if [[ ! -d "$src" ]]; then
    log_warn "source dir not found: $src"
    return 0
  fi
  local src_file rel
  while IFS= read -r -d '' src_file; do
    rel="${src_file#"$src"/}"
    link_one "$src_file" "$dst/$rel"
  done < <(find "$src" -type f -print0)
}

# link_one <absolute_source_file> <absolute_target_path>
link_one() {
  local src_file="$1" target="$2"
  mkdir -p "$(dirname "$target")"

  if [[ -L "$target" ]]; then
    local current
    current="$(readlink "$target")"
    if [[ "$current" == "$src_file" ]]; then
      log_info "ok    $target"
      return 0
    fi
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    local backup
    backup="$target.backup.$(date +%Y%m%d%H%M%S)"
    log_warn "backup $target -> $backup"
    mv "$target" "$backup"
  fi

  ln -s "$src_file" "$target"
  log_info "link  $target -> $src_file"
}
```

- [ ] **Step 2: Lint with shellcheck**

```bash
shellcheck -x -e SC1091 ~/dotfiles/lib/symlink.sh
```

Expected: exit 0.

- [ ] **Step 3: Functional test in a temp directory**

```bash
bash -c '
set -euo pipefail
source ~/dotfiles/lib/common.sh
source ~/dotfiles/lib/symlink.sh

tmp=$(mktemp -d)
src="$tmp/pkg"
dst="$tmp/target"
mkdir -p "$src/sub"
echo a > "$src/a.txt"
echo b > "$src/sub/b.txt"

# First pass: both files should be linked fresh.
link_tree "$src" "$dst"
[[ -L "$dst/a.txt"     && "$(readlink "$dst/a.txt")"     == "$src/a.txt"     ]]
[[ -L "$dst/sub/b.txt" && "$(readlink "$dst/sub/b.txt")" == "$src/sub/b.txt" ]]

# Second pass: should be silent no-ops, no backup files created.
link_tree "$src" "$dst"
backups=$(find "$dst" -name "*.backup.*" | wc -l)
[[ "$backups" == "0" ]]

# Third pass: pre-existing non-symlink must be backed up, then replaced.
rm "$dst/a.txt"
echo existing > "$dst/a.txt"
link_tree "$src" "$dst"
backups=$(find "$dst" -name "*.backup.*" | wc -l)
[[ "$backups" == "1" ]]
[[ -L "$dst/a.txt" ]]

rm -rf "$tmp"
echo "symlink tests PASS"
'
```

Expected final line: `symlink tests PASS`. Any other failure (set -e trips) means a bug.

- [ ] **Step 4: Commit**

```bash
cd ~/dotfiles
git add lib/symlink.sh
git commit -m "feat: add symlink.sh stow-lite linker with backup"
```

---

## Task 6: zsh config files (`home/`)

**Files:**

- Create: `~/dotfiles/home/.zshenv`
- Create: `~/dotfiles/home/.zshrc`
- Create: `~/dotfiles/home/.zshrc.d/00-omz.zsh`
- Create: `~/dotfiles/home/.zshrc.d/10-plugins.zsh`
- Create: `~/dotfiles/home/.zshrc.d/20-mise.zsh`
- Create: `~/dotfiles/home/.zshrc.d/30-starship.zsh`
- Create: `~/dotfiles/home/.zshrc.d/40-aliases.zsh`
- Create: `~/dotfiles/home/.zshrc.d/99-local.zsh`

- [ ] **Step 1: Write `home/.zshenv`**

```zsh
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export PATH="$HOME/.local/bin:$PATH"
```

- [ ] **Step 2: Write `home/.zshrc`**

```zsh
# Thin loader — all real config lives in ~/.zshrc.d/*.zsh.
# (N) is a glob qualifier that makes the pattern safe when the dir is empty.
for f in "$HOME"/.zshrc.d/*.zsh(N); do
  source "$f"
done
unset f
```

- [ ] **Step 3: Write `home/.zshrc.d/00-omz.zsh`**

```zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""                # starship takes over
DISABLE_AUTO_UPDATE="true"  # install.sh manages omz updates
```

- [ ] **Step 4: Write `home/.zshrc.d/10-plugins.zsh`**

```zsh
# zsh-syntax-highlighting MUST be last in the plugins list, loaded AFTER
# zsh-autosuggestions, per upstream docs:
# https://github.com/zsh-users/zsh-syntax-highlighting#faq
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source "$ZSH/oh-my-zsh.sh"
```

- [ ] **Step 5: Write `home/.zshrc.d/20-mise.zsh`**

```zsh
command -v mise >/dev/null && eval "$(mise activate zsh)"
```

- [ ] **Step 6: Write `home/.zshrc.d/30-starship.zsh`**

```zsh
command -v starship >/dev/null && eval "$(starship init zsh)"
```

- [ ] **Step 7: Write `home/.zshrc.d/40-aliases.zsh`**

```zsh
alias ll='ls -lAh'
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate -20'
```

- [ ] **Step 8: Write `home/.zshrc.d/99-local.zsh`**

```zsh
# Escape hatch for machine-specific config. Uncommitted; user-created.
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
```

- [ ] **Step 9: Parse-check each zsh file**

zsh will syntax-check a file without executing it via `zsh -n`:

```bash
for f in ~/dotfiles/home/.zshenv ~/dotfiles/home/.zshrc ~/dotfiles/home/.zshrc.d/*.zsh; do
  zsh -n "$f" && echo "ok  $f" || echo "FAIL $f"
done
```

Expected: every line starts with `ok`. If `zsh` is not installed yet, skip this step and defer verification to the Docker integration test in Task 10.

- [ ] **Step 10: Commit**

```bash
cd ~/dotfiles
git add home/
git commit -m "feat: add zsh config files (zshenv, zshrc, zshrc.d/)"
```

---

## Task 7: XDG config files (`xdg/`)

**Files:**

- Create: `~/dotfiles/xdg/mise/config.toml`
- Create: `~/dotfiles/xdg/starship.toml`

- [ ] **Step 1: Write `xdg/mise/config.toml`**

Versions are major-pinned so `mise` resolves to the latest patch on every
install. Current as of April 2026: Node 24 (Active LTS), pnpm 10 (11.x is
beta), Python 3.14 (current stable), Go 1.26 (current stable), Ruby 3.4
(current stable line). `gh`, `starship`, and `claude` track upstream
latest. The `[settings]` block makes mise download a precompiled Ruby
binary from `jdx/ruby` releases instead of compiling from source via
`ruby-build` — that avoids needing `libssl-dev`/`libyaml-dev`/
`libreadline-dev`/etc. as system build deps and shaves ~10 minutes off
cold installs.

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

- [ ] **Step 2: Write `xdg/starship.toml`** (minimal, no Nerd Font required)

```toml
add_newline = true

format = """
$directory\
$git_branch\
$git_status\
$nodejs\
$python\
$golang\
$line_break\
$character"""

[character]
success_symbol = "[❯](bold green)"
error_symbol   = "[❯](bold red)"

[directory]
truncation_length = 3
truncate_to_repo  = true

[git_branch]
symbol = "on "

[nodejs]
symbol = "node "

[python]
symbol = "py "

[golang]
symbol = "go "
```

- [ ] **Step 3: Syntax-check the TOML**

If `python3` is available:

```bash
python3 -c '
import tomllib, sys
for p in ["~/dotfiles/xdg/mise/config.toml", "~/dotfiles/xdg/starship.toml"]:
    import os; p = os.path.expanduser(p)
    with open(p, "rb") as f: tomllib.load(f)
    print("ok", p)
'
```

Expected: `ok` line per file. If `python3` is too old (< 3.11) or unavailable, defer parse verification to `mise install` / `starship config` in Task 10.

- [ ] **Step 4: Commit**

```bash
cd ~/dotfiles
git add xdg/
git commit -m "feat: add mise and starship global config files"
```

---

## Task 8: `install.sh` entry point

**Files:**

- Create: `~/dotfiles/install.sh`

- [ ] **Step 1: Write `install.sh`**

`~/dotfiles/install.sh`:

```bash
#!/usr/bin/env bash
# Dotfiles bootstrap entry point.
# Idempotent, non-interactive, safe to re-run.
#
# Compatible with: Coder workspaces, GitHub Codespaces, devcontainers,
# standalone Linux/macOS. See README for usage.

set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES
export PATH="$HOME/.local/bin:$PATH"

# shellcheck source=lib/common.sh
source "$DOTFILES/lib/common.sh"
# shellcheck source=lib/install-system.sh
source "$DOTFILES/lib/install-system.sh"
# shellcheck source=lib/install-zsh.sh
source "$DOTFILES/lib/install-zsh.sh"
# shellcheck source=lib/install-mise.sh
source "$DOTFILES/lib/install-mise.sh"
# shellcheck source=lib/symlink.sh
source "$DOTFILES/lib/symlink.sh"

set_default_shell() {
  local zsh_path
  zsh_path="$(command -v zsh || true)"
  if [[ -z "$zsh_path" ]]; then
    log_warn "zsh not found; skipping chsh"
    return 0
  fi
  if [[ "${SHELL:-}" == *zsh ]]; then
    log_info "zsh already default shell"
    return 0
  fi
  if ! grep -qx "$zsh_path" /etc/shells 2>/dev/null; then
    log_warn "$zsh_path not in /etc/shells; skipping chsh"
    return 0
  fi
  if chsh -s "$zsh_path" "$USER" 2>/dev/null; then
    log_info "default shell set to $zsh_path"
  else
    log_warn "chsh failed; manually run: chsh -s $zsh_path"
  fi
}

main() {
  log_info "bootstrapping from $DOTFILES"
  install_system_deps
  install_omz
  install_mise_binary
  link_tree "$DOTFILES/home" "$HOME"
  link_tree "$DOTFILES/xdg"  "${XDG_CONFIG_HOME:-$HOME/.config}"
  run_mise_install
  set_default_shell
  log_info "done. open a new zsh to pick up config."
}

main "$@"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x ~/dotfiles/install.sh
```

- [ ] **Step 3: Lint with shellcheck**

```bash
cd ~/dotfiles && shellcheck -x install.sh
```

Expected: exit 0. `-x` lets shellcheck follow the `source` directives.
**Note:** run from inside the repo so the `# shellcheck source=lib/...`
hints resolve relative to the script's location.

- [ ] **Step 4: Sourcing smoke test** (verify the file parses and all functions resolve; does not execute `main`)

```bash
bash -c '
set -eu
DOTFILES=~/dotfiles
source "$DOTFILES/lib/common.sh"
source "$DOTFILES/lib/install-system.sh"
source "$DOTFILES/lib/install-zsh.sh"
source "$DOTFILES/lib/install-mise.sh"
source "$DOTFILES/lib/symlink.sh"
declare -F install_system_deps install_omz install_mise_binary \
           link_tree run_mise_install
echo OK
'
```

Expected: final line `OK`.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add install.sh
git commit -m "feat: add install.sh bootstrap entry point"
```

---

## Task 9: Finalize README

**Files:**

- Modify: `~/dotfiles/README.md`

- [ ] **Step 1: Replace README with full content**

`~/dotfiles/README.md`:

```markdown
# dotfiles

Single-script bootstrap for a zsh + mise shell environment. Layout-compatible
with the dotfiles convention used by:

- [Coder workspaces](https://coder.com/docs/user-guides/workspace-dotfiles)
- [GitHub Codespaces](https://docs.github.com/en/codespaces/setting-your-user-preferences/personalizing-github-codespaces-for-your-account#dotfiles)
- devcontainers
- standalone Linux / macOS machines

Designed to be reused across project working directories — no per-project
content.

## What it installs

- **zsh** + [oh-my-zsh](https://ohmyz.sh) with `zsh-syntax-highlighting` and
  `zsh-autosuggestions`
- **[mise](https://mise.jdx.dev)** as the sole tool manager, pinning current
  stable / Active LTS versions:
  - Node 24 (Active LTS)
  - pnpm 10
  - Python 3.14
  - Go 1.26
  - Ruby 3.4 (precompiled via `jdx/ruby`, no system build deps required)
  - `gh`, `starship`, `claude` (latest, via mise's default aqua backend)
- **[starship](https://starship.rs)** prompt (no Nerd Font required)

## Install

    git clone <this-repo-url> ~/dotfiles
    ~/dotfiles/install.sh

The script is idempotent — safe to re-run.

## In a Coder workspace

    coder dotfiles <this-repo-url>

Coder clones into `~/dotfiles` and runs `install.sh` automatically.

## In GitHub Codespaces

Set this repo as your personal dotfiles in
[GitHub → Settings → Codespaces](https://github.com/settings/codespaces)
under "Dotfiles". Codespaces will clone it and run `install.sh` on every
new codespace.

## Layout

    install.sh        # entry point
    lib/              # sourced helper modules (common, install-*, symlink)
    home/             # files mapped into $HOME (.zshenv, .zshrc, .zshrc.d/)
    xdg/              # files mapped into $XDG_CONFIG_HOME (~/.config)

Files are symlinked (not copied). Editing a linked file edits the file in
this repo — useful for iterating. Existing non-symlink files at target
paths are backed up to `<target>.backup.<timestamp>`.

## Machine-specific overrides

Create `~/.zshrc.local` for anything you don't want committed — secrets,
host-specific exports, per-project shortcuts:

    # ~/.zshrc.local
    export WORK_API_TOKEN=...
    alias proj='cd ~/path/to/project'

It's sourced automatically by `99-local.zsh`.

## Manual step: default shell

On hosts where `chsh` can't write to `/etc/passwd` non-interactively (some
Coder workspaces, some Codespaces base images), the script prints a
warning. Run:

    chsh -s "$(command -v zsh)"

then log out and back in.

## Uninstall

Delete the symlinks and restore any backups:

    find ~ -maxdepth 2 -lname "$HOME/dotfiles/*" -delete
    # restore .backup.<ts> files manually as desired
```

- [ ] **Step 2: Commit**

```bash
cd ~/dotfiles
git add README.md
git commit -m "docs: write full README with install, layout, overrides"
```

---

## Task 10: End-to-end integration test in Docker

This task has no code to commit. It verifies the whole system works on a clean Ubuntu 22.04 container (which mirrors fresh Coder / Codespaces / devcontainer semantics), then verifies idempotency.

**Note:** the dotfiles repo is local (not pushed yet). Use a bind mount instead of `git clone`.

- [ ] **Step 1: Launch a clean container with the repo mounted**

```bash
docker run --rm -it \
  -v ~/dotfiles:/mnt/dotfiles:ro \
  ubuntu:22.04 bash
```

Inside the container:

```bash
apt-get update && apt-get install -y sudo curl git ca-certificates
useradd -m -s /bin/bash test
echo "test ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
cp -r /mnt/dotfiles /home/test/dotfiles
chown -R test:test /home/test/dotfiles
su - test
```

As the `test` user inside the container:

```bash
~/dotfiles/install.sh
```

- [ ] **Step 2: Verify all tools are reachable in a fresh zsh**

Still as `test` inside the container:

```bash
zsh -i -c '
echo "ZSH_VERSION=$ZSH_VERSION"
echo "plugins=$plugins"
which starship mise claude gh
starship --version
mise --version
claude --version
gh --version
'
```

Expected:

- `ZSH_VERSION` is set (5.x).
- `plugins=git zsh-autosuggestions zsh-syntax-highlighting`
- Every `which` line resolves (no "not found").
- Every `--version` call prints a version.

- [ ] **Step 3: Verify symlinks point back into `$DOTFILES`**

```bash
ls -la ~/.zshrc ~/.zshenv ~/.config/mise/config.toml ~/.config/starship.toml
```

Expected: every file shown is a symlink (`l` in mode) pointing under `/home/test/dotfiles/`.

- [ ] **Step 4: Idempotency — run install.sh a second time**

```bash
~/dotfiles/install.sh 2>&1 | tee /tmp/run2.log
find ~ -name "*.backup.*" 2>/dev/null
```

Expected: second run exits 0 with only `[info] ok ...` lines for the symlink step, and `find` returns no results (no new backups created because every symlink already resolves correctly, and the omz template cleanup in Task 3 prevents a first-run backup as well).

- [ ] **Step 5: Interactive smoke**

```bash
zsh
```

Expected: starship prompt renders (something like `~ ❯`), typing a wrong command (`fooo`) shows red syntax highlighting until Enter, typing a real command (`ls`) shows a ghost autosuggestion from history if any exists.

Exit with `exit`. Leave the container with `exit` (twice).

- [ ] **Step 6: If any step failed**

Go back, fix the specific `lib/*.sh` or config file, re-commit, and re-run Task 10 from Step 1. Do not check off Task 10 until all sub-steps pass cleanly.

- [ ] **Step 7: macOS manual spot-check** (only if user has access to a macOS machine)

Run `~/dotfiles/install.sh` on a real macOS host (not in Docker — Docker on macOS runs Linux containers). Verify brew path, verify `chsh` finds `/opt/homebrew/bin/zsh` or equivalent in `/etc/shells`. If macOS access is unavailable, note this in the session and rely on manual retrospective testing.

---

## Self-Review Notes

- **Spec coverage:** Every file in the spec's layout maps to a task (0→scaffold, 1-5→lib/, 6→home/, 7→xdg/, 8→install.sh, 9→README, 10→verify). Every install-flow step maps to code in a lib module. Every verification plan item maps to Task 10.
- **Function-name consistency:** `install_system_deps`, `install_omz`, `install_omz_plugin`, `install_mise_binary`, `run_mise_install`, `link_tree`, `link_one`, `set_default_shell`, `log_info`, `log_warn`, `log_error`, `has_cmd`, `detect_os`, `run_sudo`. Same names everywhere they appear.
- **Ordering is enforced** by `main()` in `install.sh` (Task 8): system deps → omz → mise binary → symlinks → mise install → chsh. Matches the design spec.
- **No placeholders.** Every code block is complete and copy-pasteable.
- **Out of scope from the spec is honored:** no git user config, no secrets management, no WSL, no per-project aliases.
