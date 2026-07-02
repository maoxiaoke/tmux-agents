#!/usr/bin/env bash
# tmux-agents 一键安装：clone 代码 → 接入 ~/.tmux.conf → 装 Claude hooks → 重载。
# 不需要 TPM。
#
#   curl -fsSL https://raw.githubusercontent.com/maoxiaoke/tmux-agents/main/install.sh | bash
#
# 可调环境变量：
#   TMUX_AGENTS_DIR  安装目录（默认 ~/.tmux/plugins/tmux-agents）
#   TMUX_CONF        tmux 配置（默认 ~/.tmux.conf）
#   TMUX_AGENTS_NO_HOOKS=1   跳过 Claude hooks
set -eu

REPO="https://github.com/maoxiaoke/tmux-agents"
DEST="${TMUX_AGENTS_DIR:-$HOME/.tmux/plugins/tmux-agents}"
TCONF="${TMUX_CONF:-$HOME/.tmux.conf}"
M_START="# >>> tmux-agents >>>"
M_END="# <<< tmux-agents <<<"

# 1) 拿到代码：已在仓库里就用当前目录；否则 clone / 更新到 DEST
SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$SELF" ] && [ -f "$SELF/agents.tmux" ]; then
  DIR="$SELF"
elif [ -d "$DEST/.git" ]; then
  echo "· 更新已有安装：$DEST"
  git -C "$DEST" pull --ff-only -q || true
  DIR="$DEST"
else
  command -v git >/dev/null 2>&1 || { echo "需要 git" >&2; exit 1; }
  echo "· 克隆到 $DEST"
  git clone --depth 1 "$REPO" "$DEST" -q
  DIR="$DEST"
fi

# 2) 接入 tmux.conf（用标记块，卸载可精确移除）
if [ -f "$TCONF" ] && grep -qF "$M_START" "$TCONF"; then
  echo "· $TCONF 已接入，跳过"
else
  echo "· 写入 $TCONF"
  printf '\n%s\nrun-shell "%s/agents.tmux"\n%s\n' "$M_START" "$DIR" "$M_END" >> "$TCONF"
fi

# 3) Claude hooks（让 agent 上报状态）
if [ "${TMUX_AGENTS_NO_HOOKS:-0}" != 1 ]; then
  echo "· 安装 Claude hooks"
  "$DIR/scripts/install-hooks.sh" || true
fi

# 4) 重载（若 tmux 在跑）
if command -v tmux >/dev/null 2>&1 && tmux info >/dev/null 2>&1; then
  tmux source-file "$TCONF" 2>/dev/null || true
  echo "· 已重载 tmux"
fi

cat <<EOF

✅ 安装完成（装在 ${DIR}）
   • 在 tmux 里状态栏右侧应已出现 agent 列表（不在 tmux 就下次进入生效）。
   • 新开一个 claude 会话即可上报 working / needs-you / idle。
   • 自定义位置 / 键位见 README。
   卸载： ${DIR}/scripts/uninstall.sh
EOF
