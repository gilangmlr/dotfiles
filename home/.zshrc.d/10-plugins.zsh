# zsh-syntax-highlighting MUST be last in the plugins list, loaded AFTER
# zsh-autosuggestions, per upstream docs:
# https://github.com/zsh-users/zsh-syntax-highlighting#faq
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source "$ZSH/oh-my-zsh.sh"
