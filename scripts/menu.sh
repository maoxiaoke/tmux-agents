#!/usr/bin/env bash
# 文本菜单（无 fzf 时的回退）：列出 agent，选中跳转。
DIR="$(cd "$(dirname "$0")" && pwd)"
out="$("$DIR/scan.sh" | sort -t$'\t' -k9,9n)"

if [ -z "$out" ]; then
  tmux display-message "没有正在运行的 agent"
  exit 0
fi

items=()
# shellcheck disable=SC2034  # 部分列是 TSV 占位，不是每个都用
while IFS=$'\t' read -r pid target status agent cwd wname cfull active start_epoch elapsed; do
  [ -z "$pid" ] && continue
  case "$status" in working) dot='●';; blocked) dot='!';; *) dot='○';; esac
  label="$dot $cwd  $status  ($target)"
  items+=("$label" "" "run-shell '$DIR/focus.sh $pid'")
done <<< "$out"

tmux display-menu -T "#[align=centre] 🤖 Agents " -x C -y C "${items[@]}"
