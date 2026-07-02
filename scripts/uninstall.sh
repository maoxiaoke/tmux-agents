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
  tmux unbind -T agents_goto 1 2>/dev/null || true   # 表整体随会话消失，无需逐个
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

cat <<EOF

✅ 运行期改动已撤销、hooks 已移除、缓存已清。
还需你手动做两件（无法安全代改配置文件）：
  • 从 ~/.tmux.conf 删掉：set -g @plugin 'maoxiaoke/tmux-agents'（或 run-shell .../agents.tmux）
    以及你放的 #{agents} 占位 / @agents-* 选项
  • 若用 TPM：prefix + alt+u 清理插件目录
然后 tmux source-file ~/.tmux.conf（或重开 tmux）。
EOF
