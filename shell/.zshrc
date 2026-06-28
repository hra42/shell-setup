# start
fastfetch

# env + PATH
export EDITOR='micro'
export VISUAL='micro'
export PATH="$HOME/.local/bin:$PATH"
export ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR=/opt/homebrew/share/zsh-syntax-highlighting/highlighters

# aliases
alias zi='__zoxide_zi'
alias ls='eza --icons --git'
alias ll='eza -la --icons --git'
alias lt='eza --tree --icons'
alias cat='bat --theme="Catppuccin Mocha"'
alias nano='micro'

# brew maintenance
alias brew-clean='brew cleanup --prune=all -s && brew autoremove && rm -rf "$(brew --cache)"'
alias brew-up='brew update && brew upgrade && brew upgrade --cask && brew-clean && brew doctor'

# tools that set hooks / prompts
eval "$(starship init zsh)"
eval "$(fzf --zsh)"

# completion
autoload -Uz compinit && compinit
zstyle ':completion:*:(ssh|scp|sftp):*' hosts $(grep -E '^Host ' ~/.ssh/config | grep -v '\*' | awk '{print $2}')

# Autocomplete (registers precmd/chpwd hooks — must load before zoxide)
# Catppuccin Overlay0 (#6c7086) so suggestions are visible against the dark bg;
# default fg=8 blends into the background. Suggest from history then completions.
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6c7086'
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# syntax highlighting (registers chpwd hooks — must load before zoxide)
source /opt/homebrew/share/zsh-fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh

# zoxide — MUST be the last hook-registering line so its chpwd hook stays last
# in chpwd_functions; otherwise `cd` prints a "configuration issue" doctor warning.
eval "$(zoxide init zsh --cmd cd)"
