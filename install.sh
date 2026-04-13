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
# shellcheck source=lib/install-claude.sh
source "$DOTFILES/lib/install-claude.sh"
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
  install_claude_native
  set_default_shell
  log_info "done. open a new zsh to pick up config."
}

main "$@"
