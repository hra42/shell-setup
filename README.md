# shell-setup

Reproducible shell environment for **macOS and Debian/Ubuntu Linux**. Captures the packages, shell configs, and tool configs so a fresh machine can be brought to a working state with one command. On macOS it uses Homebrew (formulae + casks); on Linux it uses apt plus a few official installer scripts for tools that aren't in apt. The Linux port is **CLI-only** — GUI apps (Brave, Zed, GitKraken, Ghostty, …) are macOS-only.

## What's in here

```
.
├── Brewfile         # taps, formulae, casks (brew bundle dump)
├── install.sh       # idempotent installer (run from inside the cloned repo)
├── scripts/
│   └── install.sh   # curl-able bootstrap: clones the repo, then runs install.sh (release asset for install-proxy)
├── .github/workflows/release.yml  # publishes scripts/install.sh as the release's install.sh
├── shell/           # ~/.zshrc, ~/.gitconfig (identity-free template), ~/.hushlogin (suppresses "Last login" banner)
└── configs/         # ~/.config/* and ~/.claude/settings.json
    ├── starship.toml
    ├── catppuccin_mocha.theme
    ├── fastfetch/
    ├── micro/
    ├── btop/
    ├── eza/         # theme.yml (Catppuccin Mocha Blue)
    ├── opencode/    # tui.json + themes/catppuccin-mocha-blue.json (transparent bg)
    ├── zed/
    ├── ai/
    ├── claude/      # settings.json (no tokens), statusline.sh, output-styles/ (Concise), agents/ (29 subagents: quality/review, language specialists, infra/devops, data/AI, docs, and specialized domains)
    ├── codex/       # config.toml
    └── ghostty/     # config.ghostty (deployed to ~/Library/Application Support/com.mitchellh.ghostty/)
```

## Quick start

Works on macOS and Debian/Ubuntu Linux (apt). One line (clones to `~/.shell-setup`, then runs the installer):

```sh
curl -fsSL https://shell-setup.hra42.lol/install | sh
```

This is the bootstrap at [`scripts/install.sh`](scripts/install.sh), served by
[install-proxy](https://github.com/hra42/install-proxy) from the latest release asset.
Override the clone target with `SHELL_SETUP_DIR=...` or pin a tag with `REF=v1.0.0`.
On Linux the bootstrap needs `git` present first (`sudo apt install git`); apt steps
use `sudo`, so run as a user with sudo (or as root).

Or clone and run manually:

```sh
# 1. Get the repo onto the new machine
git clone https://github.com/hra42/shell-setup.git ~/Documents/shell-setup
cd ~/Documents/shell-setup

# 2. Run the installer
./install.sh
```

The installer detects the OS and branches:

**macOS**
1. Installs Xcode Command Line Tools if missing.
2. Installs Homebrew if missing.
3. Runs `brew bundle` against `Brewfile` (formulae + casks).

**Linux (Debian/Ubuntu)**
1. Installs the CLI toolchain via apt where possible (`zsh`, `jq`, `micro`, `btop`,
   `bat`→`batcat`, `eza`, `gh`, `tldr`, `build-essential`, zsh-autosuggestions /
   zsh-syntax-highlighting, …), adding the eza and GitHub CLI apt repos.
2. Installs the rest via official scripts/binaries: `fzf` (upstream — apt's is too old
   for `fzf --zsh`), `zsh-fast-syntax-highlighting` (git clone), `starship`, `zoxide`,
   `uv`, `bun`, `opencode`, `ai`, Node.js (NodeSource), Go (tarball), AWS CLI v2, and
   `fastfetch` (apt → PPA → upstream `.deb` fallback).
3. Rewrites the **copies** of `~/.zshrc`, `~/.gitconfig`, and the fastfetch config in
   `$HOME` to Linux paths (the committed files stay macOS-pathed). Signing switches to
   plain SSH (ssh-keygen) instead of 1Password. Sets `zsh` as the login shell.

**Both**
4. Installs **Claude Code** (latest) via the official installer (`curl -fsSL https://claude.ai/install.sh | bash`) — kept out of the package manager so you always get the newest release.
5. **Copies** every file in `shell/` to `~/` and every directory in `configs/` to `~/.config/` (and `~/.claude/`). Existing files are backed up to `~/.shell-setup-backup-<timestamp>/` first. (Ghostty's config is macOS-only.)
6. **Prompts** for your git name, email, and commit-signing SSH public key, writing them into `~/.gitconfig` (the repo's `.gitconfig` is an identity-free template). Pressing Enter reuses any existing value, or leaves signing disabled if blank.

Re-running is safe — it backs up before overwriting.

## What this doesn't do

The following can't be automated and are listed at the end of `install.sh`:

**macOS**
- 1Password sign-in + SSH agent (commit signing depends on this).
- `gh auth login` for GitHub CLI.
- Adding a `GITHUB_PERSONAL_ACCESS_TOKEN` entry under `env` in `~/.claude/settings.json` if you use the GitHub MCP server (omitted by default).
- Signing in to GUI apps installed via cask (Setapp, Raycast, Brave, Fastmail, etc.).
- The Ghostty config references **Monaspace Nerd Font** variants (Neon/Xenon/Radon/Krypton) — these come from the `font-monaspice-nerd-font` cask in the Brewfile, so they'll be present after `brew bundle`.

**Linux**
- Commit signing uses a local SSH key (no 1Password): the matching private key must be in `~/.ssh` and loaded (`ssh-add`), and the public key added to GitHub as a *signing* key.
- `gh auth login` for GitHub CLI.
- `GITHUB_PERSONAL_ACCESS_TOKEN` for the GitHub MCP server (as above).
- **Install a Nerd Font** in your terminal and select it — none is installed for you on Linux, so the starship prompt and Claude status line will show missing-glyph boxes until you do (e.g. Monaspace Nerd Font from [nerdfonts.com](https://www.nerdfonts.com)).
- The `ai` CLI reads its OpenRouter key from 1Password (`op://…`); without 1Password on Linux, set the key another way before using `ai`.
- GUI apps are out of scope on Linux.

## Releasing (for the one-line installer)

The `curl | sh` command above is served by [install-proxy](https://github.com/hra42/install-proxy),
which fetches `install.sh` from this repo's **latest GitHub release asset**. To publish/update it:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The [`release.yml`](.github/workflows/release.yml) workflow then stages `scripts/install.sh`,
syntax-checks it, and uploads it as `install.sh` on the release — matching the
[`hra42/deployer`](https://github.com/hra42/deployer) pattern (this repo ships no binary, so the
bootstrap script is the only asset). Point `shell-setup.<domain>` at install-proxy and add an entry
to its `config.yml` (`repo: hra42/shell-setup`).

## Updating the snapshot

When your live setup changes and you want to capture it:

```sh
# regenerate Brewfile
brew bundle dump --file=Brewfile --force

# re-copy the configs that changed (example)
cp ~/.zshrc shell/.zshrc
cp ~/.config/starship.toml configs/starship.toml
```

Then commit. Note: capture configs from a **macOS** machine — the committed dotfiles
are macOS-pathed (the Linux installer rewrites the copies in `$HOME` at install time).
The Linux package list lives inline in `install.sh`; if you add a tool to the `Brewfile`,
add it to the Linux branch too (the two lists aren't generated from each other).
