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
