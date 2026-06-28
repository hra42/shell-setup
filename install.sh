#!/usr/bin/env bash
# Reproducible macOS shell setup installer.
# Idempotent: safe to re-run. Backs up any existing dotfiles before overwriting.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/.shell-setup-backup-$TS"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

backup() {
  local src="$1"
  if [[ -e "$src" || -L "$src" ]]; then
    mkdir -p "$BACKUP_DIR"
    local rel="${src#$HOME/}"
    local dst="$BACKUP_DIR/$rel"
    mkdir -p "$(dirname "$dst")"
    cp -R "$src" "$dst"
  fi
}

# 1. Xcode CLT
if ! xcode-select -p >/dev/null 2>&1; then
  log "Installing Xcode Command Line Tools (a GUI dialog will appear)"
  xcode-select --install || true
  warn "Re-run this script after Xcode CLT finishes installing."
  exit 0
fi

# 2. Homebrew
if ! command -v brew >/dev/null 2>&1; then
  log "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi

# 3. Brewfile
log "Installing packages from Brewfile"
brew bundle --file="$REPO_DIR/Brewfile"

# 3b. Claude Code (always latest, via official installer — not Homebrew)
log "Installing/updating Claude Code (latest)"
curl -fsSL https://claude.ai/install.sh | bash

# 4. Copy dotfiles
log "Copying shell dotfiles to \$HOME (backups -> $BACKUP_DIR)"
for f in "$REPO_DIR"/shell/.[!.]*; do
  [[ -e "$f" ]] || continue
  name="$(basename "$f")"
  target="$HOME/$name"
  backup "$target"
  cp -R "$f" "$target"
  echo "  $target"
done

# 4b. Git identity + commit signing (prompted — keeps personal data out of the repo)
log "Configuring git identity"
GITCONFIG="$HOME/.gitconfig"
existing_name="$(git config --file "$GITCONFIG" user.name 2>/dev/null || true)"
existing_email="$(git config --file "$GITCONFIG" user.email 2>/dev/null || true)"
existing_key="$(git config --file "$GITCONFIG" user.signingkey 2>/dev/null || true)"

read -rp "  Git user name${existing_name:+ [$existing_name]}: " git_name
git_name="${git_name:-$existing_name}"
read -rp "  Git email${existing_email:+ [$existing_email]}: " git_email
git_email="${git_email:-$existing_email}"

if [[ -n "$git_name" ]]; then
  git config --file "$GITCONFIG" user.name "$git_name"
fi
if [[ -n "$git_email" ]]; then
  git config --file "$GITCONFIG" user.email "$git_email"
fi

echo "  Commit-signing key (SSH public key, e.g. 'ssh-ed25519 AAAA...'). Leave blank to skip signing."
read -rp "  Signing key${existing_key:+ [keep existing]}: " git_key
git_key="${git_key:-$existing_key}"

if [[ -n "$git_key" ]]; then
  git config --file "$GITCONFIG" user.signingkey "$git_key"
  git config --file "$GITCONFIG" commit.gpgSign true
  git config --file "$GITCONFIG" tag.forceSignAnnotated true
else
  warn "No signing key set — commit signing left disabled. Configure later with: git config --global user.signingkey 'ssh-ed25519 ...'"
fi

# 5. Copy ~/.config/* configs
log "Copying configs to \$HOME/.config"
mkdir -p "$HOME/.config"
for entry in starship.toml catppuccin_mocha.theme fastfetch micro btop zed ai eza opencode; do
  src="$REPO_DIR/configs/$entry"
  [[ -e "$src" ]] || continue
  target="$HOME/.config/$entry"
  backup "$target"
  rm -rf "$target"
  cp -R "$src" "$target"
  echo "  $target"
done

# 6. Claude settings + status line script
log "Copying Claude settings"
mkdir -p "$HOME/.claude"
backup "$HOME/.claude/settings.json"
cp "$REPO_DIR/configs/claude/settings.json" "$HOME/.claude/settings.json"
backup "$HOME/.claude/statusline.sh"
cp "$REPO_DIR/configs/claude/statusline.sh" "$HOME/.claude/statusline.sh"
chmod +x "$HOME/.claude/statusline.sh"
backup "$HOME/.claude/output-styles"
rm -rf "$HOME/.claude/output-styles"
mkdir -p "$HOME/.claude/output-styles"
cp "$REPO_DIR"/configs/claude/output-styles/*.md "$HOME/.claude/output-styles/"
backup "$HOME/.claude/agents"
rm -rf "$HOME/.claude/agents"
mkdir -p "$HOME/.claude/agents"
cp "$REPO_DIR"/configs/claude/agents/*.md "$HOME/.claude/agents/"

# 6a. Ghostty config (lives under ~/Library/Application Support, not ~/.config)
log "Copying Ghostty config"
GHOSTTY_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"
mkdir -p "$GHOSTTY_DIR"
backup "$GHOSTTY_DIR/config.ghostty"
cp "$REPO_DIR/configs/ghostty/config.ghostty" "$GHOSTTY_DIR/config.ghostty"

# 6b. Codex config
log "Copying Codex config"
mkdir -p "$HOME/.codex"
backup "$HOME/.codex/config.toml"
cp "$REPO_DIR/configs/codex/config.toml" "$HOME/.codex/config.toml"

# 7. Done — manual steps
cat <<'EOF'

==> Setup complete.

Manual steps that cannot be automated:
  * Sign in to 1Password and enable the SSH agent (Settings -> Developer).
  * Confirm the signing key you entered matches a key held in 1Password's SSH agent
    (signing fails otherwise). Re-run ./install.sh anytime to change name/email/key.
  * Authenticate GitHub CLI:        gh auth login
  * Sign in to Codex (the config.toml references plugins, but auth is local).
  * If you use the GitHub MCP server, add a GITHUB_PERSONAL_ACCESS_TOKEN entry
    under "env" in ~/.claude/settings.json.
  * Sign in to apps installed by Homebrew Cask: Setapp, Raycast, Brave, Fastmail,
    Telegram, Discord, ChatGPT, Claude, GitKraken, Zed, Codex.
  * In Ghostty / your terminal, set the font to "Monaspice Nerd Font".
  * Restart your shell (or open a new terminal) to pick up the new config.

EOF
