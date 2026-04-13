# Shims mode (not `mise activate`): adds mise's shim dir to PATH, no
# per-prompt hooks. mise's full `activate` registers precmd + chpwd hooks
# that run `mise hook-env` on every prompt — ~20-30ms of wall time per
# prompt even when nothing changed. Shims give us version switching
# without that cost; `mise` itself stays on PATH for manual commands.
command -v mise >/dev/null && eval "$(mise activate zsh --shims)"
