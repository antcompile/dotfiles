# Dotfiles symlinked on my machine

### Install with stow:
```bash
stow .
```

### Claude Code config (~/.claude)
`~/.claude` lives outside `~/.config`, so it's a separate package stowed straight to `$HOME`:
```bash
stow --target="$HOME" claude
```
This links `CLAUDE.md`, `RTK.md`, `settings.json`, `.mcp.json`, `hooks/`, and `skills/` into `~/.claude`. `settings.local.json` and `~/.claude.json` are intentionally **not** part of this package — both are machine-local runtime state (accumulated permissions, session counters, cached feature flags), not shareable config.

`~/.no-mistakes` gets the same treatment via its own package:
```bash
stow --target="$HOME" no-mistakes
```
Only `config.yaml` (agent selection, auto-fix policy, CI timeout) is versioned — `state.sqlite`, `logs/`, `daemon.pid`, `socket`, `repos/`, and `worktrees/` are runtime state and stay local.

**Known limitation:** `settings.json`'s hook commands use this machine's absolute path (`/Users/admin/.claude/hooks/...`). On a second laptop with a different username, update those paths after stowing — this repo has hit the same class of bug before (see `9d5c4b7 fix envs to work on 2 laptops`).

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

### AI tooling (Claude Code plugins/MCP + adjacent tools)

* **codebase-memory-mcp** — code knowledge-graph MCP server (chosen over GitNexus: same job, but zero-dependency static binary, no API key, no Node/tree-sitter toolchain). Do not also install GitNexus — running both on one project double-indexes the repo and gives the agent two contradictory "ground truths" for the same code.
  * Install with `npm install -g --allow-scripts=codebase-memory-mcp codebase-memory-mcp`, then run `codebase-memory-mcp install -y` once per machine — it auto-detects Claude Code (and any other installed agents) and writes `~/.claude/.mcp.json` plus a `PreToolUse`/`SessionStart` hook pair and a `codebase-memory` skill directly into the versioned `claude/.claude/` package (since those paths are symlinks into the repo).
* **caveman** — Claude Code plugin that compresses response verbosity. Already installed and tracked in `enabledPlugins` in `claude/.claude/settings.json`. Installed via:
  ```bash
  claude plugin marketplace add JuliusBrussee/caveman
  claude plugin install caveman@caveman
  ```
  Use `/caveman <level>` or `/caveman off` in-session to change verbosity; it's on some level by default once installed.
* **no-mistakes** — git-push quality gate (Go binary, daemon-based). Install via `curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh`. It has no separate Claude Code skill file to install — it auto-detects and drives the native `claude` CLI binary directly (see `no-mistakes doctor`). Global config is versioned at `no-mistakes/.no-mistakes/config.yaml` (see above). To gate an individual project, run `no-mistakes init` inside it — that's per-repo and not part of dotfiles.
  * **Overlap warning:** no-mistakes's push gate covers the same ground as Claude Code's built-in `verify`/`code-review`/`security-review`/`superpowers:verification-before-completion` skills. Pick one as the actual merge gate — running both on every change is redundant, not additive.
* **Strix** — autonomous security-scanning CLI (needs Docker + its own LLM API key). Install via `curl -sSL https://strix.ai/install | bash`. Treat as an on-demand tool, not part of every session. Copy `strix/cli-config.json.template` to `~/.strix/cli-config.json` and fill in real keys — that file is gitignored since it holds an LLM API key.
* **Tolaria** — markdown-vault PKM desktop app (`cask "tolaria"` in the Brewfile). Its vault is its own separate git repo, not this dotfiles repo — clone/create it independently. Doesn't touch `~/.claude` or `~/.config`.
* **GitButler** — git client (`cask "gitbutler"` in the Brewfile). Its app-support state (`~/Library/Application Support/{gitbutler,com.gitbutler.app}/`) holds OAuth tokens and machine-specific project paths, so it's intentionally not stowed — just install the cask and sign in per machine.

### Daily brew update + backup (launchd)
* `setup.sh` installs a launchd agent (`launchd/com.atrad.brew-daily.plist.template` → `~/Library/LaunchAgents/com.atrad.brew-daily.plist`) that runs `launchd/brew-daily.sh` on every login/startup, at most once per day
* It runs `brew update`, backs up the current package list to `launchd/brew-backups/Brewfile.<mon..sun>` (rotates weekly, gitignored), then runs `brew upgrade`
* If any step fails you'll get a macOS notification — check `~/Library/Logs/brew-daily.log` for details
* To restore a backup: `brew bundle install --file=launchd/brew-backups/Brewfile.<day>`