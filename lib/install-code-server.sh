#!/usr/bin/env bash
# Create a `code` symlink next to code-server's remote-cli `code-server`
# binary, so Claude Code's IDE tools integration can locate the CLI.
# Must be sourced after lib/common.sh.
#
# Why: Claude Code's /ide integration shells out to a `code` binary inside
# the remote-cli directory to detect the running editor. code-server only
# ships `code-server` there, so the detection fails and tools integration
# silently does nothing. Upstream tracks this at
# https://github.com/anthropics/claude-code/issues/1937 — the workaround
# is a symlink: `code -> code-server` in the same remote-cli dir.

install_code_server_code_symlink() {
  local -a candidates=()

  # Standard Debian/tarball install path.
  if [[ -d /usr/lib/code-server/lib/vscode/bin/remote-cli ]]; then
    candidates+=(/usr/lib/code-server/lib/vscode/bin/remote-cli)
  fi

  # Fall back to whatever `code-server` on PATH resolves to. On tarball
  # installs the PATH entry is already the remote-cli `code-server`, so
  # its dirname is the dir we want.
  if has_cmd code-server; then
    local resolved dir
    resolved="$(readlink -f "$(command -v code-server)" 2>/dev/null || true)"
    if [[ -n "$resolved" ]]; then
      dir="$(dirname "$resolved")"
      if [[ "$(basename "$dir")" == "remote-cli" && -f "$dir/code-server" ]]; then
        candidates+=("$dir")
      fi
    fi
  fi

  if (( ${#candidates[@]} == 0 )); then
    log_info "code-server not detected; skipping code symlink"
    return 0
  fi

  # De-duplicate in case both detection paths found the same dir.
  local -A seen=()
  local dir
  for dir in "${candidates[@]}"; do
    [[ -n "${seen[$dir]:-}" ]] && continue
    seen[$dir]=1

    if [[ -e "$dir/code" || -L "$dir/code" ]]; then
      log_info "code-server code symlink already present at $dir/code"
      continue
    fi

    # Prefer unprivileged when the dir is writable (tarball installs under
    # $HOME or /tmp); fall back to sudo for /usr/lib/code-server.
    if [[ -w "$dir" ]] && ln -s "$dir/code-server" "$dir/code" 2>/dev/null; then
      log_info "created code-server code symlink at $dir/code"
    elif run_sudo ln -s "$dir/code-server" "$dir/code"; then
      log_info "created code-server code symlink at $dir/code (sudo)"
    else
      log_warn "could not create code symlink at $dir/code"
    fi
  done
}
