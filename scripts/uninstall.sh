#!/usr/bin/env bash
# 一键卸载 tmux-agents：移除 Claude hooks + 清缓存 + 撤掉运行期的键位/状态栏改动。
# 只清本插件的东西，不动你的其它配置。
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "1) 移除 Claude Code hooks（保留其它已有 hook）"
"$DIR/install-hooks.sh" uninstall || true

echo "2) 清缓存 ~/.cache/tmux-agents"
rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/tmux-agents"

# 撤掉运行期设置（仅当前 tmux server 在跑时）
if command -v tmux >/dev/null 2>&1 && tmux info >/dev/null 2>&1; then
  echo "3) 撤销运行期的键位 / hook / 状态栏段"
  for k in a Tab BTab Enter g; do tmux unbind "$k" 2>/dev/null || true; done
  tmux unbind -T root MouseDown1Status 2>/dev/null || true
  tmux unbind -T root MouseDown1StatusRight 2>/dev/null || true
  for n in 1 2 3 4 5 6 7 8 9; do tmux unbind -T agents_goto "$n" 2>/dev/null || true; done
  for h in after-select-pane after-select-window client-session-changed; do
    tmux set-hook -gu "$h" 2>/dev/null || true
  done
  # 把状态栏里本插件的 bar.sh 段抹掉（占位/自动追加两种都清）
  for o in status-left status-right status-format[0]; do
    v="$(tmux show -gqv "$o" 2>/dev/null || true)"
    case "$v" in
      *"$DIR/bar.sh"*)
        # 删掉 “#(.../bar.sh …) ” 这一段
        tmux set -g "$o" "$(printf '%s' "$v" | sed -E "s#\#\([^)]*bar\.sh[^)]*\) ?##g")" 2>/dev/null || true
        ;;
    esac
  done
  tmux refresh-client -S 2>/dev/null || true
fi

# 4) 移除 install.sh 写入的标记块（若是一键安装的）
TCONF="${TMUX_CONF:-$HOME/.tmux.conf}"
if [ -f "$TCONF" ] && grep -qF "# >>> tmux-agents >>>" "$TCONF"; then
  echo "4) 从 $TCONF 移除 tmux-agents 标记块"
  cp "$TCONF" "$TCONF.bak-$(date +%Y%m%d-%H%M%S)"
  sed '/# >>> tmux-agents >>>/,/# <<< tmux-agents <<</d' "$TCONF" > "$TCONF.tmp" && mv "$TCONF.tmp" "$TCONF"
fi

cat <<EOF

✅ 卸载完成：hooks / 缓存 / 运行期改动 / tmux.conf 标记块 都已清理。
若你是【手动】接入的（TPM @plugin 或自己写的 run-shell / #{agents} 占位 / @agents-* 选项），
那几行需你自己删；用 TPM 再 prefix + alt+u 清目录。最后 tmux source-file ~/.tmux.conf。
EOF
