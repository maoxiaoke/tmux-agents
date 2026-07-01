#!/usr/bin/env bash
# 把客户端焦点切到指定 pane。$1 = pane_id（如 %9）。
# 全程用 session 名 + window_id(@N) + pane_id(%N)，都是唯一标识，
# 不拼 "sess:win.pane" 字符串 —— 于是 session/window 名带空格也不会出错。
pid="$1"
[ -z "$pid" ] && exit 0

# 一次取全，用 TAB 分隔（session 名可能含空格，不能用空格分隔）
IFS=$'\t' read -r sess win < <(tmux display-message -p -t "$pid" '#{session_name}	#{window_id}' 2>/dev/null)
[ -z "$win" ] && exit 0

tmux switch-client -t "$sess"
tmux select-window -t "$win"
tmux select-pane -t "$pid"
