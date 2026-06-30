#!/usr/bin/env bash
# 文本菜单（无 fzf 时的回退）：列出 agent，选中跳转。
DIR="$(cd "$(dirname "$0")" && pwd)"
out="$("$DIR/scan.sh" | sort -t$'\t' -k9,9n)"

if [ -z "$out" ]; then
  tmux display-message "没有正在运行的 agent"
  exit 0
fi

items=()
while IFS=$'\t' read -r pid target status agent cwd wname cfull active start_epoch elapsed; do
  [ -z "$pid" ] && continue
  case "$status" in working) dot='●';; blocked) dot='!';; *) dot='○';; esac
  sess="${target%%:*}"; sw="${target%.*}"
  label="$dot $cwd  $status  ($target)"
  cmd="run-shell \"tmux switch-client -t '$sess'; tmux select-window -t '$sw'; tmux select-pane -t '$pid'\""
  items+=("$label" "" "$cmd")
done <<< "$out"

tmux display-menu -T "#[align=centre] 🤖 Agents " -x C -y C "${items[@]}"
