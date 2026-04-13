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
