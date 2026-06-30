#!/usr/bin/env bash
# 跳转到指定 pane。$1 = pane_id 的纯数字部分（不含 %）。
n="$1"
[ -z "$n" ] && exit 0
pid="%$n"
sess=$(tmux display-message -p -t "$pid" '#{session_name}' 2>/dev/null)
[ -z "$sess" ] && exit 0
tmux switch-client -t "$sess"
tmux select-window -t "$pid"
tmux select-pane -t "$pid"
