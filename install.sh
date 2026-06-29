#!/usr/bin/env bash
# Reproducible shell setup installer for macOS and Debian/Ubuntu Linux.
# Idempotent: safe to re-run. Backs up any existing dotfiles before overwriting.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/.shell-setup-backup-$TS"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

# Detect the platform once. macOS uses Homebrew + casks; Linux uses apt plus a
# handful of official installer scripts for tools that aren't in apt (or are too
# old there). The macOS path is unchanged from the original installer.
case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  *) warn "Unsupported OS: $(uname -s) (this installer targets macOS and Linux)"; exit 1 ;;
esac

# sudo wrapper: apt needs root, but the curl|sh bootstrap runs as the user. Use
# sudo when present and not already root; error clearly if neither holds.
SUDO=""
if [[ "$OS" == "linux" && "$(id -u)" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    warn "Not running as root and 'sudo' is not installed; apt steps will fail. Install sudo or run as root."
  fi
fi

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

# ---------------------------------------------------------------------------
# Linux (Debian/Ubuntu) package installation — the apt analogue of brew bundle.
# Mirrors the CLI formulae in the Brewfile. GUI casks are out of scope on Linux.
# ---------------------------------------------------------------------------
install_linux_packages() {
  local arch deb_arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)  deb_arch=amd64 ;;
    aarch64|arm64) deb_arch=arm64 ;;
    *) warn "Unrecognized architecture '$arch'; some fallback installers may fail." ; deb_arch="$arch" ;;
  esac

  export DEBIAN_FRONTEND=noninteractive

  # --- Prerequisites FIRST: a minimal image may lack curl/gpg, which the repo
  # setup below needs. Install them before adding any third-party apt repos. ---
  log "Installing apt prerequisites (curl, gnupg, certs)"
  $SUDO apt-get update -y
  $SUDO apt-get install -y --no-install-recommends \
    curl git ca-certificates gnupg apt-transport-https

  # --- Third-party apt repos (keys + sources) so eza/gh come from apt ---
  $SUDO mkdir -p /etc/apt/keyrings

  # eza (gierens repo)
  if ! command -v eza >/dev/null 2>&1; then
    log "Adding eza apt repository"
    curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
      | $SUDO gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
      | $SUDO tee /etc/apt/sources.list.d/gierens.list >/dev/null
    $SUDO chmod 0644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
  fi

  # GitHub CLI (cli.github.com)
  if ! command -v gh >/dev/null 2>&1; then
    log "Adding GitHub CLI apt repository"
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | $SUDO dd of=/etc/apt/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
    $SUDO chmod 0644 /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$deb_arch signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  fi

  log "Updating apt and installing base packages"
  $SUDO apt-get update -y
  # Packages available directly from apt. NOTE: bat installs as 'batcat' on
  # Debian/Ubuntu; the .zshrc cat alias is rewritten to match (see step 5b).
  $SUDO apt-get install -y --no-install-recommends \
    zsh jq build-essential micro btop tldr unzip \
    bat eza gh \
    zsh-autosuggestions zsh-syntax-highlighting

  # --- fzf: install from upstream, NOT apt. The apt build on Ubuntu 22.04 /
  # Debian 11 is too old for `fzf --zsh` (used in .zshrc) and would error on
  # every new shell. Clone to ~/.fzf and install just the binary + shell files. ---
  if ! fzf --zsh >/dev/null 2>&1; then
    log "Installing fzf from upstream (apt's is too old for 'fzf --zsh')"
    rm -rf "$HOME/.fzf"
    git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
    "$HOME/.fzf/install" --bin
    $SUDO ln -sf "$HOME/.fzf/bin/fzf" /usr/local/bin/fzf
  fi

  # --- zsh-fast-syntax-highlighting: not packaged in apt. Clone it where the
  # rewritten .zshrc expects to source it from (see step 5b). ---
  local fsh_dir="$HOME/.local/share/zsh/fast-syntax-highlighting"
  if [[ ! -f "$fsh_dir/fast-syntax-highlighting.plugin.zsh" ]]; then
    log "Installing zsh-fast-syntax-highlighting"
    rm -rf "$fsh_dir"
    mkdir -p "$(dirname "$fsh_dir")"
    git clone --depth 1 https://github.com/zdharma-continuum/fast-syntax-highlighting.git "$fsh_dir"
  fi

  # --- Official installer scripts (each handles its own arch). All land in
  # ~/.local/bin or a tool-specific dir already on PATH via .zshrc. ---
  if ! command -v starship >/dev/null 2>&1; then
    log "Installing starship"
    curl -fsSL https://starship.rs/install.sh | $SUDO sh -s -- -y
  fi
  if ! command -v zoxide >/dev/null 2>&1; then
    log "Installing zoxide"
    curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
  fi
  if ! command -v uv >/dev/null 2>&1; then
    log "Installing uv"
    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi
  if ! command -v bun >/dev/null 2>&1; then
    log "Installing bun"
    curl -fsSL https://bun.sh/install | bash
  fi
  if ! command -v opencode >/dev/null 2>&1; then
    log "Installing opencode"
    curl -fsSL https://opencode.ai/install | bash
  fi
  if ! command -v ai >/dev/null 2>&1; then
    log "Installing ai (hra42)"
    curl -fsSL https://ai.hra42.lol/install | INSTALL_DIR="$HOME/.local/bin" sh
  fi

  # --- Node.js via NodeSource (apt's nodejs lags well behind current) ---
  if ! command -v node >/dev/null 2>&1; then
    log "Installing Node.js (NodeSource)"
    curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO -E bash -
    $SUDO apt-get install -y nodejs
  fi

  # --- Go via the official tarball (apt's golang lags); add to PATH in .zshrc ---
  if ! command -v go >/dev/null 2>&1 && [[ ! -x /usr/local/go/bin/go ]]; then
    log "Installing Go (official tarball)"
    local go_ver go_tarball
    go_ver="$(curl -fsSL https://go.dev/VERSION?m=text | head -n1)"
    go_tarball="${go_ver}.linux-${deb_arch}.tar.gz"
    curl -fsSL "https://go.dev/dl/${go_tarball}" -o "/tmp/${go_tarball}"
    $SUDO rm -rf /usr/local/go
    $SUDO tar -C /usr/local -xzf "/tmp/${go_tarball}"
    rm -f "/tmp/${go_tarball}"
  fi

  # --- AWS CLI v2 (apt ships an old v1) ---
  if ! command -v aws >/dev/null 2>&1; then
    log "Installing AWS CLI v2"
    local aws_arch
    case "$deb_arch" in
      amd64) aws_arch=x86_64 ;;
      arm64) aws_arch=aarch64 ;;
      *)     aws_arch="$arch" ;;
    esac
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o /tmp/awscliv2.zip
    ( cd /tmp && command -v unzip >/dev/null 2>&1 || $SUDO apt-get install -y unzip; \
      unzip -q -o awscliv2.zip && $SUDO ./aws/install --update )
    rm -rf /tmp/awscliv2.zip /tmp/aws
  fi

  # --- fastfetch: apt availability is distro-version-dependent. Best-effort
  # (never abort the install): apt, then PPA, then upstream .deb for this arch. ---
  if ! command -v fastfetch >/dev/null 2>&1; then
    log "Installing fastfetch"
    install_fastfetch "$deb_arch" || warn "fastfetch not installed; the shell will still start (fastfetch line is skipped if absent)."
  fi
}

# fastfetch installer — isolated so its failures stay non-fatal under `set -e`.
install_fastfetch() {
  local deb_arch="$1" ff_url
  if $SUDO apt-get install -y fastfetch 2>/dev/null; then
    return 0
  fi
  if command -v add-apt-repository >/dev/null 2>&1 \
     && $SUDO add-apt-repository -y ppa:zhangsongcui3371/fastfetch 2>/dev/null \
     && $SUDO apt-get update -y && $SUDO apt-get install -y fastfetch; then
    return 0
  fi
  warn "fastfetch not in apt/PPA; fetching the latest .deb release"
  # fastfetch release assets use linux-amd64.deb / linux-aarch64.deb (not arm64),
  # and ship a "-polyfilled" variant we want to avoid — match the plain name.
  local ff_arch
  case "$deb_arch" in
    amd64) ff_arch=amd64 ;;
    arm64) ff_arch=aarch64 ;;
    *)     ff_arch="$deb_arch" ;;
  esac
  ff_url="$(curl -fsSL https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest 2>/dev/null \
    | grep -oE "https://[^\"]*fastfetch-linux-${ff_arch}\.deb" | head -n1 || true)"
  [[ -n "$ff_url" ]] || return 1
  curl -fsSL "$ff_url" -o /tmp/fastfetch.deb || return 1
  $SUDO apt-get install -y /tmp/fastfetch.deb || $SUDO dpkg -i /tmp/fastfetch.deb || { rm -f /tmp/fastfetch.deb; return 1; }
  rm -f /tmp/fastfetch.deb
  return 0
}

# 1-3. Packages. macOS: Xcode CLT + Homebrew + Brewfile. Linux: apt + installers.
if [[ "$OS" == "macos" ]]; then
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
else
  # Linux: install the CLI toolchain via apt + official installer scripts.
  install_linux_packages
fi

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

# 4a. Linux: rewrite the COPIES in $HOME (never the repo files) to Linux paths.
# The committed dotfiles stay macOS-pathed as the source of truth.
if [[ "$OS" == "linux" ]]; then
  log "Adapting dotfiles for Linux"

  # .zshrc — Homebrew paths -> apt/clone paths; bat -> batcat; brew aliases out.
  ZSHRC="$HOME/.zshrc"
  if [[ -f "$ZSHRC" ]]; then
    sed -i \
      -e 's#/opt/homebrew/share/zsh-syntax-highlighting/highlighters#/usr/share/zsh-syntax-highlighting/highlighters#g' \
      -e 's#source \$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh#source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh#g' \
      -e 's#source /opt/homebrew/share/zsh-fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh#source "$HOME/.local/share/zsh/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh"#g' \
      -e "s#alias cat='bat #alias cat='batcat #g" \
      "$ZSHRC"
    # Replace the macOS brew maintenance aliases with an apt equivalent.
    sed -i \
      -e "/^alias brew-clean=/d" \
      -e "s#^alias brew-up=.*#alias apt-up='sudo apt update \&\& sudo apt upgrade -y \&\& sudo apt autoremove -y'#" \
      "$ZSHRC"
    # Append PATH entries for installers that land outside ~/.local/bin
    # (go tarball, bun, opencode — each adds itself only to ~/.bashrc, not zsh).
    if ! grep -q '/usr/local/go/bin' "$ZSHRC"; then
      cat >> "$ZSHRC" <<'ZRC'

# Linux installer PATH additions (go tarball, bun, opencode)
export PATH="$PATH:/usr/local/go/bin:$HOME/.bun/bin:$HOME/.opencode/bin"
ZRC
    fi
  fi

  # .gitconfig — drop the macOS 1Password op-ssh-sign program so git falls back
  # to ssh-keygen for plain SSH signing with a local ~/.ssh key.
  GITCFG="$HOME/.gitconfig"
  if [[ -f "$GITCFG" ]]; then
    sed -i \
      -e '/program = .*op-ssh-sign/d' \
      -e '/^\[gpg "ssh"\]$/d' \
      "$GITCFG"
  fi
fi

# 4b. Git identity + commit signing (prompted — keeps personal data out of the repo)
log "Configuring git identity"
GITCONFIG="$HOME/.gitconfig"
existing_name="$(git config --file "$GITCONFIG" user.name 2>/dev/null || true)"
existing_email="$(git config --file "$GITCONFIG" user.email 2>/dev/null || true)"
existing_key="$(git config --file "$GITCONFIG" user.signingkey 2>/dev/null || true)"

# `|| true`: a read that hits EOF (no TTY / piped input) must not abort under set -e;
# the ${var:-$existing} fallback then keeps any pre-existing value.
read -rp "  Git user name${existing_name:+ [$existing_name]}: " git_name || true
git_name="${git_name:-$existing_name}"
read -rp "  Git email${existing_email:+ [$existing_email]}: " git_email || true
git_email="${git_email:-$existing_email}"

if [[ -n "$git_name" ]]; then
  git config --file "$GITCONFIG" user.name "$git_name"
fi
if [[ -n "$git_email" ]]; then
  git config --file "$GITCONFIG" user.email "$git_email"
fi

if [[ "$OS" == "macos" ]]; then
  echo "  Commit-signing key (SSH public key, e.g. 'ssh-ed25519 AAAA...'). Signing is done"
  echo "  via 1Password's SSH agent. Leave blank to skip signing."
else
  echo "  Commit-signing key (SSH public key, e.g. 'ssh-ed25519 AAAA...'). Signing uses your"
  echo "  local ~/.ssh key via ssh-keygen — the matching private key must be in ~/.ssh and"
  echo "  loaded in ssh-agent, and the public key added to GitHub as a *signing* key."
  echo "  Leave blank to skip signing."
fi
read -rp "  Signing key${existing_key:+ [keep existing]}: " git_key || true
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

# 5b. Linux: point fastfetch at the Linux logo (repo config ships "macos").
if [[ "$OS" == "linux" && -f "$HOME/.config/fastfetch/config.jsonc" ]]; then
  sed -i 's/"source": "macos"/"source": "linux"/' "$HOME/.config/fastfetch/config.jsonc"
fi

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

# 6a. Ghostty config (macOS only — GUI terminal, lives under ~/Library/...).
# Skipped on Linux (CLI-only scope).
if [[ "$OS" == "macos" ]]; then
  log "Copying Ghostty config"
  GHOSTTY_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"
  mkdir -p "$GHOSTTY_DIR"
  backup "$GHOSTTY_DIR/config.ghostty"
  cp "$REPO_DIR/configs/ghostty/config.ghostty" "$GHOSTTY_DIR/config.ghostty"
fi

# 6b. Codex config
log "Copying Codex config"
mkdir -p "$HOME/.codex"
backup "$HOME/.codex/config.toml"
cp "$REPO_DIR/configs/codex/config.toml" "$HOME/.codex/config.toml"

# 6c. Linux: make zsh the login shell (Debian/Ubuntu default to bash).
if [[ "$OS" == "linux" ]]; then
  zsh_path="$(command -v zsh || true)"
  if [[ -n "$zsh_path" && "${SHELL:-}" != *zsh ]]; then
    log "Setting zsh as your login shell"
    if ! chsh -s "$zsh_path" 2>/dev/null; then
      warn "Could not change your login shell automatically. Run: chsh -s $zsh_path  (then log out and back in)."
    fi
  fi
fi

# 7. Done — manual steps
if [[ "$OS" == "macos" ]]; then
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
else
cat <<'EOF'

==> Setup complete (Linux).

Manual steps that cannot be automated:
  * Commit signing uses a local SSH key. Make sure the matching private key is in
    ~/.ssh and loaded (ssh-add), and add the PUBLIC key to GitHub as a *signing*
    key (Settings -> SSH and GPG keys -> New SSH key -> type "Signing Key").
    Re-run ./install.sh anytime to change name/email/key.
  * Authenticate GitHub CLI:        gh auth login
  * If you use the GitHub MCP server, add a GITHUB_PERSONAL_ACCESS_TOKEN entry
    under "env" in ~/.claude/settings.json.
  * Install a Nerd Font in your terminal and select it, or the starship prompt and
    Claude status line will show missing-glyph boxes. (No font is installed for you
    on Linux — e.g. grab Monaspace Nerd Font from nerdfonts.com.)
  * The `ai` CLI reads its OpenRouter key from 1Password (op://...). Without
    1Password on Linux, set the key another way before using `ai`.
  * GUI apps (Brave, Zed, GitKraken, Ghostty, etc.) are out of scope on Linux.
  * If your login shell didn't switch to zsh, run: chsh -s "$(command -v zsh)"
    then log out and back in. Otherwise just open a new terminal.

EOF
fi
