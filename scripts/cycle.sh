#!/usr/bin/env bash
# 在所有 agent pane 之间循环切换。
# 用法：cycle.sh <next|prev> [current_pane_id]
# 顺序与状态栏一致（按启动时间升序）。当前不在 agent 上时跳到第一个。
DIR="$(cd "$(dirname "$0")" && pwd)"
dir="${1:-next}"
cur="$2"
[ -z "$cur" ] && cur=$(tmux display-message -p '#{pane_id}' 2>/dev/null)

# 收集 agent pane（第 1 列 pane_id），按启动时间排序
panes=()
while IFS=$'\t' read -r pid _rest; do
  [ -n "$pid" ] && panes+=("$pid")
done < <("$DIR/scan.sh" | sort -t$'\t' -k9,9n)

n=${#panes[@]}
[ "$n" -eq 0 ] && { tmux display-message "没有正在运行的 agent"; exit 0; }

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
