#!/usr/bin/env bash
# fzf 选择器：左列表 + 右侧实时预览该 pane 的真实画面，回车跳转。
# 在 display-popup -E 里运行（继承 $TMUX）。需要 fzf。
DIR="$(cd "$(dirname "$0")" && pwd)"
out="$("$DIR/scan.sh" | sort -t$'\t' -k9,9n)"

if [ -z "$out" ]; then
  echo "没有正在运行的 agent"; sleep 1; exit 0
fi

list=$(printf '%s\n' "$out" | while IFS=$'\t' read -r pid target status agent cwd wname cfull active start_epoch elapsed; do
  case "$status" in working) dot='●';; blocked) dot='!';; *) dot='○';; esac
  printf '%s\t%s  %-8s  %-18s  %s\n' "$pid" "$dot" "$status" "$cwd" "$target"
done)

sel=$(printf '%s\n' "$list" | fzf \
  --delimiter=$'\t' --with-nth=2 \
  --preview 'tmux capture-pane -ep -t {1}' \
  --preview-window='right,72%,border-left,wrap' \
  --prompt='agent ❯ ' \
  --header='↑↓ 预览 · 回车跳转 · esc 取消' \
  --ansi --no-sort)

[ -z "$sel" ] && exit 0
pid="${sel%%$'\t'*}"
sess=$(tmux display-message -p -t "$pid" '#{session_name}' 2>/dev/null)
[ -n "$sess" ] && tmux switch-client -t "$sess"
tmux select-window -t "$pid"
tmux select-pane -t "$pid"
