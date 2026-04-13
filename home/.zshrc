# Thin loader — all real config lives in ~/.zshrc.d/*.zsh.
# (N) is a glob qualifier that makes the pattern safe when the dir is empty.
for f in "$HOME"/.zshrc.d/*.zsh(N); do
  source "$f"
done
unset f
