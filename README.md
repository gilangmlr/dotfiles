# dotfiles

Single-script bootstrap for a zsh + mise shell environment. Layout-compatible
with the dotfiles convention used by:

- [Coder workspaces](https://coder.com/docs/user-guides/workspace-dotfiles)
- [GitHub Codespaces](https://docs.github.com/en/codespaces/setting-your-user-preferences/personalizing-github-codespaces-for-your-account#dotfiles)
- devcontainers
- standalone Linux / macOS machines

Designed to be reused across any number of project working directories — no
per-project content.

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
