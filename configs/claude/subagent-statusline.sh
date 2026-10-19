#!/usr/bin/env bash
# Claude Code subagent status line — one row per subagent, Catppuccin Mocha themed.
# Row: status icon · agent type (name) · label · model (effort) · context bar % · elapsed
# Reads {columns, tasks[]} on stdin, writes one {"id","content"} JSON line per row
# (see https://code.claude.com/docs/en/statusline#subagent-status-lines).

jq -c --argjson now "$(date +%s)" '
  def c(rgb; s): "\u001b[38;2;\(rgb)m\(s)\u001b[0m";
  def mauve(s):    c("203;166;247"; s);
  def lavender(s): c("180;190;254"; s);
  def blue(s):     c("137;180;250"; s);
  def green(s):    c("166;227;161"; s);
  def yellow(s):   c("249;226;175"; s);
  def red(s):      c("243;139;168"; s);
  def subtext(s):  c("166;173;200"; s);
  def overlay(s):  c("108;112;134"; s);
  def usage(p; s): if p >= 90 then red(s) elif p >= 70 then yellow(s) else green(s) end;
  def sep: " " + overlay("│") + " ";
  def trunc(n): if length > n then .[0:(n - 1)] + "…" else . end;

  (.columns // 100) as $cols
  | .tasks[]
  | . as $t
  | ({running: yellow("●"), completed: green("✓"), failed: red("✗"), killed: red("■")}[$t.status]
      // subtext("○")) as $icon
  | (($t.agentType // "agent") + (if $t.name then " (\($t.name))" else "" end)) as $who
  # Short model name: claude-sonnet-5-5 -> sonnet 5.5
  | (($t.model // "") | sub("^claude-"; "") | sub("\\[.*\\]$"; "")
      | capture("^(?<f>[a-z]+)-(?<v>[0-9-]+)") // {f: ., v: ""}
      | .f + (if .v != "" then " " + (.v | gsub("-"; ".")) else "" end)) as $model
  | (if $t.effort then " " + lavender("(\($t.effort))") else "" end) as $effort
  | (if $t.contextWindowSize and $t.contextWindowSize > 0
       then ($t.tokenCount * 100 / $t.contextWindowSize | floor) else null end) as $pct
  | (if $pct != null then
       ([($pct / 10 | floor), 10] | min) as $f
       | usage($pct; ("█" * $f) // "") + overlay(("░" * (10 - $f)) // "") + " " + usage($pct; "\($pct)%")
     else subtext("\(($t.tokenCount / 1000 * 10 | floor) / 10)k tok") end) as $ctx
  | (($now - ($t.startTime / 1000 | floor)) | if . < 0 then 0 else . end) as $s
  | (if $s >= 3600 then "\($s / 3600 | floor)h \($s % 3600 / 60 | floor)m"
     else "\($s / 60 | floor)m \($s % 60)s" end) as $dur
  # Label gets whatever width is left after the fixed segments
  | ([($cols - ($who | length) - ($model | length) - 50), 12] | max) as $lw
  | {id: $t.id,
     content: ($icon + " " + mauve($who) + sep + blue(($t.label // $t.description // "") | trunc($lw))
               + (if $model != "" then sep + subtext($model) + $effort else "" end)
               + sep + $ctx + sep + subtext($dur))}
'
