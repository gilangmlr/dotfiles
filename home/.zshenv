export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export PATH="$HOME/.local/bin:$PATH"

# Debian/Ubuntu's /etc/zsh/zshrc runs compinit unconditionally; we run our
# own cache-guarded compinit in .zshrc.d/00-compinit.zsh, so tell the system
# rc to stay out of it. Must live in .zshenv — .zshrc is too late.
skip_global_compinit=1
