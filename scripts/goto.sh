#!/usr/bin/env bash
# 直达第 N 个 agent（顺序与状态栏一致：按启动时间升序）。$1 = 序号(1-based)
DIR="$(cd "$(dirname "$0")" && pwd)"
idx="$1"
case "$idx" in ''|*[!0-9]*) exit 0 ;; esac

panes=()
while IFS=$'\t' read -r pid _rest; do
  [ -n "$pid" ] && panes+=("$pid")
done < <("$DIR/scan.sh" | sort -t$'\t' -k9,9n)

n=${#panes[@]}
[ "$n" -eq 0 ] && { tmux display-message "没有正在运行的 agent"; exit 0; }
if [ "$idx" -lt 1 ] || [ "$idx" -gt "$n" ]; then
  tmux display-message "没有第 $idx 个 agent（共 $n 个）"; exit 0
fi

target="${panes[$((idx - 1))]}"
sess=$(tmux display-message -p -t "$target" '#{session_name}' 2>/dev/null)
[ -n "$sess" ] && tmux switch-client -t "$sess"
tmux select-window -t "$target"
tmux select-pane -t "$target"
