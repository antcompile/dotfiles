#!/usr/bin/env bash
mkdir ~/.config
chmod +x ~/.config
stow .

# Install the daily brew update/backup launchd agent
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_DEST="$HOME/Library/LaunchAgents/com.atrad.brew-daily.plist"

chmod +x "$REPO_DIR/launchd/brew-daily.sh"
mkdir -p "$HOME/Library/LaunchAgents"
sed "s|__REPO__|$REPO_DIR|g; s|__HOME__|$HOME|g" \
    "$REPO_DIR/launchd/com.atrad.brew-daily.plist.template" > "$PLIST_DEST"

launchctl unload "$PLIST_DEST" 2>/dev/null
launchctl load "$PLIST_DEST"