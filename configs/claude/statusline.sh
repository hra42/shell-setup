#!/usr/bin/env bash
# Claude Code status line — two-line, Catppuccin Mocha themed.
# Line 1: model (effort) · folder · git branch (+staged ~modified) · PR
# Line 2: context bar · 5h/7d rate limits · lines changed · cost · duration
# Reads session JSON on stdin (see https://code.claude.com/docs/en/statusline).

input=$(cat)

# --- parse all fields in one jq call (unit-separator delimited, null-safe) ---
IFS=$'\x1f' read -r MODEL EFFORT DIR PCT COST DURATION_MS SESSION_ID \
  ADDED REMOVED RL5 RL7 PR_NUM < <(printf '%s' "$input" | jq -r '[
    (.model.display_name // "?"),
    (.effort.level // ""),
    (.workspace.current_dir // .cwd // ""),
    ((.context_window.used_percentage // 0) | floor),
    (.cost.total_cost_usd // 0),
    (.cost.total_duration_ms // 0),
    (.session_id // "nosession"),
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0),
    (.rate_limits.five_hour.used_percentage // "" | if . == "" then . else floor end),
    (.rate_limits.seven_day.used_percentage // "" | if . == "" then . else floor end),
    (.pr.number // "")
  ] | map(tostring) | join("\u001f")')

# --- Catppuccin Mocha truecolor palette (24-bit ANSI) ---
ESC=$'\033'
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
MAUVE="${ESC}[38;2;203;166;247m"   # model
LAVENDER="${ESC}[38;2;180;190;254m" # effort
BLUE="${ESC}[38;2;137;180;250m"    # folder
SAPPHIRE="${ESC}[38;2;116;199;236m" # PR
GREEN="${ESC}[38;2;166;227;161m"   # branch / low usage / lines added
YELLOW="${ESC}[38;2;249;226;175m"  # staged / mid usage / cost
PEACH="${ESC}[38;2;250;179;135m"   # modified
RED="${ESC}[38;2;243;139;168m"     # high usage / lines removed
SUBTEXT="${ESC}[38;2;166;173;200m" # dim labels
OVERLAY="${ESC}[38;2;108;112;134m" # separators / empty bar

SEP=" ${OVERLAY}│${RESET} "

# Color for a usage percentage: green < 70 <= yellow < 90 <= red
usage_color() {
  if   [ "${1:-0}" -ge 90 ]; then printf '%s' "$RED"
  elif [ "${1:-0}" -ge 70 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"; fi
}

# --- git info, cached per session for ~3s to avoid lag in big repos ---
CACHE_FILE="${TMPDIR:-/tmp}/claude-statusline-git-$SESSION_ID"
cache_is_stale() {
  [ ! -f "$CACHE_FILE" ] || \
  [ $(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ) ) -gt 3 ]
}
if cache_is_stale; then
  if git -C "${DIR:-.}" rev-parse --git-dir >/dev/null 2>&1; then
    BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
    STAGED=$(git -C "$DIR" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    MODIFIED=$(git -C "$DIR" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    printf '%s|%s|%s' "$BRANCH" "$STAGED" "$MODIFIED" > "$CACHE_FILE"
  else
    printf '||' > "$CACHE_FILE"
  fi
fi
IFS='|' read -r BRANCH STAGED MODIFIED < "$CACHE_FILE"

# --- line 1: model · folder · git · PR ---
LINE1="${BOLD}${MAUVE}${MODEL}${RESET}"
[ -n "$EFFORT" ] && LINE1="${LINE1} ${LAVENDER}(${EFFORT})${RESET}"
LINE1="${LINE1}${SEP}${BLUE} ${DIR##*/}${RESET}"
if [ -n "$BRANCH" ]; then
  LINE1="${LINE1}${SEP}${GREEN} ${BRANCH}${RESET}"
  [ "${STAGED:-0}" -gt 0 ] 2>/dev/null && LINE1="${LINE1} ${YELLOW}+${STAGED}${RESET}"
  [ "${MODIFIED:-0}" -gt 0 ] 2>/dev/null && LINE1="${LINE1} ${PEACH}~${MODIFIED}${RESET}"
fi
[ -n "$PR_NUM" ] && LINE1="${LINE1}${SEP}${SAPPHIRE} #${PR_NUM}${RESET}"

# --- line 2: context bar · rate limits · lines · cost · duration ---
FILLED=$(( PCT / 10 )); [ "$FILLED" -gt 10 ] && FILLED=10
EMPTY=$(( 10 - FILLED ))
BAR=""; FILL=""; PAD=""
[ "$FILLED" -gt 0 ] && printf -v FILL "%${FILLED}s" && FILL="${FILL// /█}"
[ "$EMPTY"  -gt 0 ] && printf -v PAD  "%${EMPTY}s"  && PAD="${PAD// /░}"
BAR="$(usage_color "$PCT")${FILL}${OVERLAY}${PAD}${RESET}"
LINE2="${BAR} $(usage_color "$PCT")${PCT}%${RESET}"

if [ -n "$RL5" ] || [ -n "$RL7" ]; then
  LIMITS=""
  [ -n "$RL5" ] && LIMITS="${SUBTEXT}5h${RESET} $(usage_color "$RL5")${RL5}%${RESET}"
  [ -n "$RL7" ] && LIMITS="${LIMITS:+$LIMITS }${SUBTEXT}7d${RESET} $(usage_color "$RL7")${RL7}%${RESET}"
  LINE2="${LINE2}${SEP}${LIMITS}"
fi

if [ "${ADDED:-0}" -gt 0 ] || [ "${REMOVED:-0}" -gt 0 ]; then
  LINE2="${LINE2}${SEP}${GREEN}+${ADDED}${RESET} ${RED}-${REMOVED}${RESET}"
fi

COST_FMT=$(LC_NUMERIC=C printf '$%.2f' "$COST")
SEC=$(( DURATION_MS / 1000 )); HRS=$(( SEC / 3600 )); MINS=$(( SEC % 3600 / 60 )); SECS=$(( SEC % 60 ))
if [ "$HRS" -gt 0 ]; then DUR="${HRS}h ${MINS}m"; else DUR="${MINS}m ${SECS}s"; fi
LINE2="${LINE2}${SEP}${YELLOW}${COST_FMT}${RESET}${SEP}${SUBTEXT} ${DUR}${RESET}"

printf '%b\n' "$LINE1"
printf '%b\n' "$LINE2"
