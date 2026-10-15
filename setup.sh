#!/usr/bin/env bash
mkdir ~/.config
chmod +x ~/.config
stow .

# Claude Code config (~/.claude) lives outside ~/.config, so it needs its own target
stow --target="$HOME" claude

# no-mistakes global config (~/.no-mistakes) also lives outside ~/.config
stow --target="$HOME" no-mistakes

# zsh dotfiles (~/.zprofile, ~/.zshrc.secrets.template) live directly in $HOME
stow --target="$HOME" zshrc

# pi coding agent (~/.pi/agent): models.json routes through the LiteLLM gateway.
# --no-folding so pi's runtime files (sessions, auth.json) stay out of the repo.
stow --no-folding --target="$HOME" pi

# Install the daily brew update/backup launchd agent
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_DEST="$HOME/Library/LaunchAgents/com.atrad.brew-daily.plist"

chmod +x "$REPO_DIR/launchd/brew-daily.sh"
mkdir -p "$HOME/Library/LaunchAgents"
sed "s|__REPO__|$REPO_DIR|g; s|__HOME__|$HOME|g" \
    "$REPO_DIR/launchd/com.atrad.brew-daily.plist.template" > "$PLIST_DEST"

launchctl unload "$PLIST_DEST" 2>/dev/null
launchctl load "$PLIST_DEST"

# MeetingBar preferences
defaults import leits.MeetingBar "$REPO_DIR/meetingbar/leits.MeetingBar.plist"

# Install brew dependencies (idempotent — skips already-installed)
if command -v brew &>/dev/null && [ "$(uname)" = "Darwin" ]; then
  brew bundle --file="$REPO_DIR/Brewfile"
fi