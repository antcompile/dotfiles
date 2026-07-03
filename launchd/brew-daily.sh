#!/usr/bin/env bash
set -uo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$HOME/.cache/dotfiles"
MARKER_FILE="$STATE_DIR/brew-daily-last-run"
BACKUP_DIR="$REPO_DIR/launchd/brew-backups"
TODAY="$(date +%F)"
WEEKDAY="$(date +%a | tr '[:upper:]' '[:lower:]')"

mkdir -p "$STATE_DIR" "$BACKUP_DIR"

if [ -f "$MARKER_FILE" ] && [ "$(cat "$MARKER_FILE")" = "$TODAY" ]; then
    echo "$(date '+%F %T') already ran today, skipping"
    exit 0
fi

notify_failure() {
    local step="$1"
    osascript -e "display notification \"$step failed — see ~/Library/Logs/brew-daily.log\" with title \"Brew daily maintenance failed\" sound name \"Basso\"" >/dev/null 2>&1
}

echo "$(date '+%F %T') starting brew daily maintenance"

if ! brew update; then
    echo "$(date '+%F %T') brew update failed"
    notify_failure "brew update"
    exit 1
fi

if ! brew bundle dump --file="$BACKUP_DIR/Brewfile.$WEEKDAY" --force; then
    echo "$(date '+%F %T') brew bundle dump failed"
    notify_failure "brew bundle dump"
    exit 1
fi

if ! brew upgrade; then
    echo "$(date '+%F %T') brew upgrade failed"
    notify_failure "brew upgrade"
    exit 1
fi

echo "$TODAY" > "$MARKER_FILE"
echo "$(date '+%F %T') brew daily maintenance complete"
