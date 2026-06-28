# shell-setup

Reproducible macOS shell environment. Captures the Homebrew packages, shell configs, and tool configs so a fresh Mac can be brought to a working state with one command.

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

## Quick start on a fresh Mac

One line (clones to `~/.shell-setup`, then runs the installer):

```sh
curl -fsSL https://shell-setup.hra42.lol/install | sh
```

This is the bootstrap at [`scripts/install.sh`](scripts/install.sh), served by
[install-proxy](https://github.com/hra42/install-proxy) from the latest release asset.
Override the clone target with `SHELL_SETUP_DIR=...` or pin a tag with `REF=v1.0.0`.

Or clone and run manually:

```sh
# 1. Get the repo onto the new machine
git clone https://github.com/hra42/shell-setup.git ~/Documents/shell-setup
cd ~/Documents/shell-setup

# 2. Run the installer
./install.sh
```

The installer:
1. Installs Xcode Command Line Tools if missing.
2. Installs Homebrew if missing.
3. Runs `brew bundle` against `Brewfile`.
4. Installs **Claude Code** (latest) via the official installer (`curl -fsSL https://claude.ai/install.sh | bash`) — kept out of Homebrew so you always get the newest release.
5. **Copies** every file in `shell/` to `~/` and every directory in `configs/` to `~/.config/` (and `~/.claude/`). Existing files are backed up to `~/.shell-setup-backup-<timestamp>/` first.
6. **Prompts** for your git name, email, and commit-signing SSH public key, writing them into `~/.gitconfig` (the repo's `.gitconfig` is an identity-free template). Pressing Enter reuses any existing value, or leaves signing disabled if blank.

Re-running is safe — it backs up before overwriting.

## What this doesn't do

The following can't be automated and are listed at the end of `install.sh`:

- 1Password sign-in + SSH agent (commit signing depends on this).
- `gh auth login` for GitHub CLI.
- Adding a `GITHUB_PERSONAL_ACCESS_TOKEN` entry under `env` in `~/.claude/settings.json` if you use the GitHub MCP server (omitted by default).
- Signing in to GUI apps installed via cask (Setapp, Raycast, Brave, Fastmail, etc.).
- The Ghostty config references **Monaspace Nerd Font** variants (Neon/Xenon/Radon/Krypton) — these come from the `font-monaspice-nerd-font` cask in the Brewfile, so they'll be present after `brew bundle`.

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

Then commit.
