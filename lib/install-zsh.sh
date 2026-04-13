#!/usr/bin/env bash
# Install oh-my-zsh and the two user-requested plugins. Idempotent.
# Must be sourced after lib/common.sh.

install_omz() {
  local zsh_dir="${ZSH:-$HOME/.oh-my-zsh}"

  if [[ -d "$zsh_dir" ]]; then
    log_info "oh-my-zsh already installed at $zsh_dir"
  else
    log_info "installing oh-my-zsh"
    # KEEP_ZSHRC=yes is critical: prevents omz from overwriting our .zshrc
    # when it gets symlinked into place later.
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
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
