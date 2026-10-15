export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
eval "$(/opt/homebrew/bin/brew shellenv)"

# Added by OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init.zsh 2>/dev/null || :

export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion


# Path to your oh-my-zsh installation.
# Reevaluate the prompt string each time it's displaying a prompt
setopt prompt_subst
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
autoload bashcompinit && bashcompinit
autoload -Uz compinit
compinit

bindkey '^L' vi-forward-word
bindkey '^k' up-line-or-search
bindkey '^j' down-line-or-search

eval "$(starship init zsh)"
export STARSHIP_CONFIG=~/.config/starship/starship.toml

# You may need to manually set your language environment
export LANG=en_US.UTF-8

export EDITOR=/opt/homebrew/bin/nvim

export PATH="$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# VI Mode!!!
bindkey jj vi-cmd-mode

alias gprs="git fetch; git reset --mixed origin/main; git merge --squash HEAD@{1}"

eval "$(zoxide init zsh)"
eval "$(atuin init zsh)"

. "$HOME/.cargo/env"

# Source secrets file if it exists (not tracked in git)
if [ -f "$HOME/.zshrc.secrets" ]; then
  source "$HOME/.zshrc.secrets"
fi

export GOPATH="$HOME/go"
export PATH=$PATH:$GOPATH/bin

# dotnet
export PATH="/usr/local/share/dotnet:$PATH"
