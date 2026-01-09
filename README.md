# Dotfiles symlinked on my machine

### Install with stow:
```bash
stow .
```

### Install homebrew and Modify ~/.zprofile to include
eval "$(/opt/homebrew/bin/brew shellenv)"
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:=${HOME}/.config}
export ZDOTDIR=${ZDOTDIR:=${XDG_CONFIG_HOME}/zshrc}
source $ZDOTDIR/.zshrc
. "$HOME/.cargo/env"

### Install NerdFonts
* `brew search '/font-.*-nerd-font/' | awk '{ print $1 }' | xargs brew install --cask`
* Open Terminal settings and reference `Firacode Nerd Font Regular 13`

### Install Required Software

#### With Homebrew Bundler
* Brewfile is present in this directory
* brew bundler install pointing to this file should work
* brew bundler dump should create the file (--force)
* brew bundler cleanup should update the file (--force)

#### Tmux Plugins (TPM) (bar etc...)
* git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
* prefix capital I or prefix capital U then kill-server to install
#### Manually
* brew install --cask sf-symbols
* brew install carapace
* copy nushell commpand to init cache (carapace _carapace nushell | save --force $"($nu.cache-dir)/init.nu")
* curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
* brew install nushell
* run this in nushell: `atuin init nu | save ~/.local/share/atuin/init.nu`
* run this in nushell: `zoxide init nushell | save -f ~/.zoxide.nu`
* install starship
* starship init nu | save ~/.cache/starship/init.nu
* brew install aerpospace
* brew tap FelixKratz/formulae THEN brew install borders (JankyBorders)