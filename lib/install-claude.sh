#!/usr/bin/env bash
# Install Claude Code via Anthropic's native installer.
# The native binary lands in ~/.local/bin/claude and auto-updates itself
# in the background, so we only run the installer when the binary is
# missing. Must be sourced after lib/common.sh.
#
# Why native, not mise: claude used to be pinned in xdg/mise/config.toml
# as `claude = "latest"` via mise's aqua backend. That path lagged
# upstream releases and the in-app updater kept printing
# "Update available! Run: your package manager update command",
# pushing updates onto `mise upgrade` instead of `claude update`. The
# native installer hands binary management back to Claude Code itself
# (self-update on startup), which is what the in-app updater expects.
# `~/.local/bin` is already first on PATH via .zshenv, so the native
# binary wins over any leftover mise shim on workspaces that had the
# old config.

install_claude_native() {
  local claude_bin="$HOME/.local/bin/claude"
  if [[ -x "$claude_bin" ]]; then
    log_info "claude already installed at $claude_bin"
    return 0
  fi
  log_info "installing claude (native)"
  if ! curl -fsSL https://claude.ai/install.sh | bash; then
    log_error "claude native install failed"
    return 1
  fi
  export PATH="$HOME/.local/bin:$PATH"
  if [[ ! -x "$claude_bin" ]]; then
    log_error "claude binary missing after install"
    return 1
  fi
}
