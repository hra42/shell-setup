#!/usr/bin/env bash
# Claude Code status line — two-line, Catppuccin Mocha themed.
# Line 1: model · folder · git branch (+staged ~modified)
# Line 2: context bar · cost · session duration
# Reads session JSON on stdin (see https://code.claude.com/docs/en/statusline).

input=$(cat)

# --- parse fields (jq, with null-safe fallbacks) ---
MODEL=$(printf '%s' "$input" | jq -r '.model.display_name // "?"')
DIR=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // ""')
PCT=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
COST=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // 0')
DURATION_MS=$(printf '%s' "$input" | jq -r '.cost.total_duration_ms // 0')
SESSION_ID=$(printf '%s' "$input" | jq -r '.session_id // "nosession"')

# --- Catppuccin Mocha truecolor palette (24-bit ANSI) ---
ESC=$'\033'
RESET="${ESC}[0m"
MAUVE="${ESC}[38;2;203;166;247m"   # model
BLUE="${ESC}[38;2;137;180;250m"    # folder
GREEN="${ESC}[38;2;166;227;161m"   # branch / low usage
YELLOW="${ESC}[38;2;249;226;175m"  # staged / mid usage / cost
PEACH="${ESC}[38;2;250;179;135m"   # modified
RED="${ESC}[38;2;243;139;168m"     # high usage
SUBTEXT="${ESC}[38;2;166;173;200m" # dim separators / empty bar

# --- git info, cached per session for ~3s to avoid lag in big repos ---
CACHE_FILE="${TMPDIR:-/tmp}/claude-statusline-git-$SESSION_ID"
cache_is_stale() {
  [ ! -f "$CACHE_FILE" ] || \
  [ $(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ) ) -gt 3 ]
}
if cache_is_stale; then
  if git rev-parse --git-dir >/dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null)
    STAGED=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    MODIFIED=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    printf '%s|%s|%s' "$BRANCH" "$STAGED" "$MODIFIED" > "$CACHE_FILE"
  else
    printf '||' > "$CACHE_FILE"
  fi
fi
IFS='|' read -r BRANCH STAGED MODIFIED < "$CACHE_FILE"

GIT_SEG=""
if [ -n "$BRANCH" ]; then
  GIT_SEG="  ${GREEN} ${BRANCH}${RESET}"
  [ "${STAGED:-0}" -gt 0 ] 2>/dev/null && GIT_SEG="${GIT_SEG} ${YELLOW}+${STAGED}${RESET}"
  [ "${MODIFIED:-0}" -gt 0 ] 2>/dev/null && GIT_SEG="${GIT_SEG} ${PEACH}~${MODIFIED}${RESET}"
fi

# --- context bar, colored by usage threshold ---
if   [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi
FILLED=$(( PCT / 10 )); [ "$FILLED" -gt 10 ] && FILLED=10
EMPTY=$(( 10 - FILLED ))
BAR=""
[ "$FILLED" -gt 0 ] && printf -v FILL "%${FILLED}s" && BAR="${FILL// /█}"
[ "$EMPTY"  -gt 0 ] && printf -v PAD  "%${EMPTY}s"  && BAR="${BAR}${SUBTEXT}${PAD// /░}${RESET}"

# --- cost + duration ---
COST_FMT=$(printf '$%.2f' "$COST")
SEC=$(( DURATION_MS / 1000 )); MINS=$(( SEC / 60 )); SECS=$(( SEC % 60 ))
SEP="${SUBTEXT}|${RESET}"

# --- output (two lines) ---
printf '%b\n' "${MAUVE}${MODEL}${RESET}  ${BLUE} ${DIR##*/}${RESET}${GIT_SEG}"
printf '%b\n' "${BAR_COLOR}${BAR%$RESET}${RESET} ${PCT}% ${SEP} ${YELLOW}${COST_FMT}${RESET} ${SEP} ${SUBTEXT}${MINS}m ${SECS}s${RESET}"
