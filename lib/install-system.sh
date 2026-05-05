#!/usr/bin/env bash
# Install system packages required before shell setup.
# Must be sourced after lib/common.sh.
#
# Two non-obvious dep groups in here:
#
# 1. `gnupg` — mise's core:node backend verifies Node release tarball
#    signatures against the Node maintainers' PGP keys via gpg-agent.
#    Ubuntu 24.04 noble does not ship gnupg in its base image, so a
#    fresh Coder workspace would otherwise fail at `mise install node@24`
#    with "gpg exited with non-zero status: exit code 2".
#
# 2. PostgreSQL source-build deps (bison, flex, libreadline-dev,
#    libssl-dev, libicu-dev, libxml2-dev, uuid-dev, zlib1g-dev) — mise's
#    vfox-postgres plugin compiles PostgreSQL from source via
#    `./configure && make`, which needs bison/flex up front and the
#    listed -dev packages for headers. Without these, projects that pin
#    `postgres = "..."` in their .mise.toml fail at the configure step.
#    For a faster alternative, project repos can use `embedded-postgres`
#    instead (precompiled binaries), but the dotfiles still install the
#    build deps so the source-compile path works out of the box.

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
  if has_cmd zsh && has_cmd git && has_cmd curl \
     && has_cmd unzip && has_cmd gpg \
     && has_cmd bison && has_cmd flex \
     && has_cmd tmux; then
    log_info "system deps already present"
    return 0
  fi
  log_info "installing system deps via apt"
  run_sudo apt-get update
  run_sudo apt-get install -y \
    zsh git curl unzip ca-certificates build-essential gnupg \
    bison flex libreadline-dev libssl-dev libicu-dev libxml2-dev \
    uuid-dev zlib1g-dev tmux
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
  if has_cmd zsh && has_cmd git && has_cmd curl \
     && has_cmd gpg && has_cmd bison && has_cmd flex \
     && has_cmd tmux; then
    log_info "system deps already present"
    return 0
  fi
  log_info "installing system deps via brew"
  # Most postgres source-build deps (readline, openssl, icu4c, libxml2)
  # are provided by Xcode CLT or system libs on macOS. bison/flex are
  # the two we need from brew because the system versions are too old.
  brew install zsh git curl gnupg bison flex tmux
}
