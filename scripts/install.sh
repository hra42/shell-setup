#!/usr/bin/env sh
# Bootstrap the hra42 shell setup from a single command (macOS or Debian/Ubuntu Linux).
#
# Usage:
#   curl -fsSL https://shell-setup.hra42.lol/install | sh
#   curl -fsSL https://shell-setup.hra42.lol/install | REF=v1.0.0 sh
#   curl -fsSL https://shell-setup.hra42.lol/install | SHELL_SETUP_DIR=$HOME/code/shell-setup sh
#
# Env vars:
#   SHELL_SETUP_DIR  Where to clone/update the repo (default: $HOME/.shell-setup).
#   SHELL_SETUP_REPO Git URL to clone (default: https://github.com/hra42/shell-setup.git).
#   REF              Branch or tag to check out (default: the repo's default branch).
#
# This script clones (or updates) the shell-setup repository, then hands off to the
# repo's own install.sh, which copies dotfiles/configs into $HOME. It is the
# curl-able entry point published as a GitHub release asset for install-proxy; the
# heavy lifting lives in the repo's top-level install.sh.

set -eu

REPO_URL="${SHELL_SETUP_REPO:-https://github.com/hra42/shell-setup.git}"
TARGET_DIR="${SHELL_SETUP_DIR:-$HOME/.shell-setup}"
REF="${REF:-}"

err()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || err "missing required command: $1"; }

command -v git >/dev/null 2>&1 || err "missing required command: git (install it first, e.g. 'sudo apt install git')"

# macOS (Homebrew + casks) or Debian/Ubuntu Linux (apt + fallback installers).
os_raw="$(uname -s)"
case "$os_raw" in
  Darwin|Linux) ;;
  *) err "this setup targets macOS (Darwin) or Linux; detected: $os_raw" ;;
esac

# Clone fresh, or update an existing checkout in place (idempotent).
if [ -d "$TARGET_DIR/.git" ]; then
  info "updating existing checkout at $TARGET_DIR"
  git -C "$TARGET_DIR" fetch --quiet --all --tags --prune
  if [ -n "$REF" ]; then
    git -C "$TARGET_DIR" checkout --quiet "$REF"
    git -C "$TARGET_DIR" pull --quiet --ff-only origin "$REF" 2>/dev/null || true
  else
    branch="$(git -C "$TARGET_DIR" rev-parse --abbrev-ref HEAD)"
    git -C "$TARGET_DIR" pull --quiet --ff-only origin "$branch" 2>/dev/null || true
  fi
elif [ -e "$TARGET_DIR" ]; then
  err "$TARGET_DIR exists but is not a git checkout; move it aside or set SHELL_SETUP_DIR"
else
  info "cloning $REPO_URL -> $TARGET_DIR"
  git clone --quiet "$REPO_URL" "$TARGET_DIR"
  [ -n "$REF" ] && git -C "$TARGET_DIR" checkout --quiet "$REF"
fi

INSTALLER="$TARGET_DIR/install.sh"
[ -f "$INSTALLER" ] || err "installer not found at $INSTALLER"

info "running installer"
# Hand off to the repo's installer. It is bash-specific (arrays, [[ ]]), so invoke
# it with bash explicitly rather than the sh this bootstrap runs under.
need bash
exec bash "$INSTALLER"
