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
