#!/usr/bin/env bash
# 渲染状态栏 agent 列表（可点击 range）。$1 = 当前客户端聚焦的 pane_id（#{pane_id}）。
# active 严格跟随焦点 / blocked=需要你(红) / working=spinner+时长 / 同名消歧 / 溢出折叠。
DIR="$(cd "$(dirname "$0")" && pwd)"
FOCUS="$1"
out="$("$DIR/scan.sh" | sort -t$'\t' -k9,9n)"   # 按启动时间升序，位置稳定

[ -z "$out" ] && { printf '#[fg=#585b70] no agents #[default]'; exit 0; }

# 同名消歧：出现多次的 basename
dupnames=$(printf '%s\n' "$out" | awk -F'\t' '{c[$5]++} END{for(n in c) if(c[n]>1) print n}')
is_dup() { [ -n "$dupnames" ] && printf '%s\n' "$dupnames" | grep -qxF "$1"; }

# spinner（按秒轮转）
frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
spin=${frames[$(( $(date +%s) % ${#frames[@]} ))]}

fmt() { local s=${1:-0}; if [ "$s" -ge 3600 ]; then printf '%dh%dm' $((s/3600)) $((s%3600/60)); elif [ "$s" -ge 60 ]; then printf '%dm' $((s/60)); else printf '%ds' "$s"; fi; }

# 溢出预算（居中 bar，左留窗口列表、右留时钟）
width=$(tmux display-message -p '#{client_width}' 2>/dev/null); [ -z "$width" ] && width=120
budget=$(( width - 28 - 32 )); [ "$budget" -lt 24 ] && budget=24

used=0; hidden=0; buf=''; i=0
# shellcheck disable=SC2034  # 部分列是 TSV 占位，不是每个都用
while IFS=$'\t' read -r pid target status agent cwd wname cfull active start_epoch elapsed; do
  [ -z "$pid" ] && continue
  i=$((i + 1))                       # 序号 = 直达用的 goto 序号（含被折叠的，保持对齐）
  num="${pid#%}"; winpane="${target#*:}"
  label="$cwd"; is_dup "$cwd" && label="$cwd#$winpane"
  [ "$pid" = "$FOCUS" ] && active=1 || active=0
  alc=$(printf '%s' "$agent" | tr 'A-Z' 'a-z')
  [ "$alc" = claude ] && sfx='' || sfx=" · $agent"

  case "$status" in
    working) glyph="$spin"; state="working $(fmt "$elapsed")";;
    blocked) glyph='!';     state='needs you';;
    *)       glyph='✓';     state='idle';;
  esac

  plain="$glyph $label · $state$sfx"; len=${#plain}
  important=0
  [ "$active" = 1 ] && important=1
  [ "$status" != idle ] && important=1
  if [ "$important" != 1 ] && [ $((used + len + 3)) -gt "$budget" ]; then
    hidden=$((hidden + 1)); continue
  fi
  used=$((used + len + 3))

  if [ "$active" = 1 ]; then
    [ "$status" = blocked ] && bg='#f38ba8' || bg='#89b4fa'
    seg="#[range=user|$num]#[bg=$bg,fg=#1e1e2e,bold] $glyph $label · $state$sfx #[default]#[norange] "
  elif [ "$status" = blocked ]; then
    seg="#[range=user|$num]#[fg=#f38ba8,bold]! #[fg=#f38ba8,bold]$label #[fg=#f38ba8]· needs you$sfx#[default]#[norange]   "
  elif [ "$status" = working ]; then
    seg="#[range=user|$num]#[fg=#f9e2af]$glyph #[fg=#cdd6f4]$label #[fg=#6c7086]· $state$sfx#[default]#[norange]   "
  else
    seg="#[range=user|$num]#[fg=#a6e3a1]✓ #[fg=#6c7086]$label · $state$sfx#[default]#[norange]   "
  fi
  buf="$buf#[fg=#585b70]$i #[default]$seg"
done <<< "$out"

printf '%s' "$buf"
[ "$hidden" -gt 0 ] && printf '#[fg=#6c7086]+%s ✓#[default]' "$hidden"
