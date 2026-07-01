#!/usr/bin/env bash
# 在 agent pane 之间循环切换。
# 用法：cycle.sh <next|prev> [current_pane_id] [status_filter]
#   status_filter：只在该状态的 agent 间跳（如 needs-you）。省略=所有 agent。
# 顺序与状态栏一致（按启动时间升序）。当前不在候选里时跳到第一个。
DIR="$(cd "$(dirname "$0")" && pwd)"
dir="${1:-next}"
cur="$2"
filter="$3"
[ -z "$cur" ] && cur=$(tmux display-message -p '#{pane_id}' 2>/dev/null)

# 收集候选 pane（可按状态过滤），按启动时间排序
panes=()
while IFS=$'\t' read -r pid _target status _rest; do
  [ -z "$pid" ] && continue
  [ -n "$filter" ] && [ "$status" != "$filter" ] && continue
  panes+=("$pid")
done < <("$DIR/scan.sh" | sort -t$'\t' -k9,9n)

n=${#panes[@]}
if [ "$n" -eq 0 ]; then
  [ "$filter" = needs-you ] && tmux display-message "没有需要你处理的 agent" \
                            || tmux display-message "没有正在运行的 agent"
  exit 0
fi

# 找当前 pane 的下标
idx=-1
for i in "${!panes[@]}"; do
  [ "${panes[$i]}" = "$cur" ] && { idx=$i; break; }
done

if [ "$idx" -lt 0 ]; then
  target="${panes[0]}"                       # 不在任何 agent 上 → 跳第一个
elif [ "$dir" = prev ]; then
  target="${panes[$(( (idx - 1 + n) % n ))]}"
else
  target="${panes[$(( (idx + 1) % n ))]}"
fi

sess=$(tmux display-message -p -t "$target" '#{session_name}' 2>/dev/null)
[ -n "$sess" ] && tmux switch-client -t "$sess"
tmux select-window -t "$target"
tmux select-pane -t "$target"
