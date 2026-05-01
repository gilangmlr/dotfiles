# Powerlevel10k instant prompt. MUST stay at the very top of .zshrc — it
# paints a cached prompt before the rest of the rc finishes sourcing, so
# anything that writes to stdout/stderr above this line will break it.
# Cache is rebuilt by p10k after each full prompt render.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Thin loader — all real config lives in ~/.zshrc.d/*.zsh.
# (N) is a glob qualifier that makes the pattern safe when the dir is empty.
for f in "$HOME"/.zshrc.d/*.zsh(N); do
  source "$f"
done
unset f
