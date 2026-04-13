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
# shellcheck source=lib/install-code-server.sh
source "$DOTFILES/lib/install-code-server.sh"
# shellcheck source=lib/symlink.sh
source "$DOTFILES/lib/symlink.sh"

set_default_shell() {
  local zsh_path current
  zsh_path="$(command -v zsh || true)"
  if [[ -z "$zsh_path" ]]; then
    log_warn "zsh not found; skipping chsh"
    return 0
  fi
  # Check /etc/passwd directly, not $SHELL: in Coder/Codespaces the user's
  # login shell is often still bash even after a successful chsh, because
  # the session was launched before the change.
  current="$(getent passwd "$USER" 2>/dev/null | awk -F: '{print $7}')"
  if [[ "$current" == "$zsh_path" ]]; then
    log_info "zsh already default shell"
    return 0
  fi
  if ! grep -qx "$zsh_path" /etc/shells 2>/dev/null; then
    log_warn "$zsh_path not in /etc/shells; skipping chsh"
    return 0
  fi
  # Redirect stdin from /dev/null so chsh can't block on a password prompt
  # (PAM-less chsh hangs indefinitely otherwise on hosts where the coder
  # user has no password). If it needs auth, we fail fast and log a hint.
  if chsh -s "$zsh_path" "$USER" </dev/null >/dev/null 2>&1; then
    log_info "default shell set to $zsh_path"
  else
    log_warn "chsh failed (needs password or PAM restricted); manually run: chsh -s $zsh_path"
  fi
}

main() {
  log_info "bootstrapping from $DOTFILES"
  install_system_deps
  install_omz
  install_mise_binary
  prune_stale_links "$DOTFILES/home" "$HOME"
  prune_stale_links "$DOTFILES/xdg"  "${XDG_CONFIG_HOME:-$HOME/.config}"
  link_tree "$DOTFILES/home" "$HOME"
  link_tree "$DOTFILES/xdg"  "${XDG_CONFIG_HOME:-$HOME/.config}"
  run_mise_install
  install_claude_native
  install_code_server_code_symlink
  set_default_shell
  log_info "done. open a new zsh to pick up config."
}

main "$@"
