#!/usr/bin/env bash
# tmux-agents —— 在 tmux 状态栏里显示正在运行的 AI coding agent（claude/aider/…）
# 及其状态（active/working/needs-you/idle），点击/弹窗可跳转。
#
# 安装（TPM）：  set -g @plugin 'you/tmux-agents'
# 在状态栏里放占位符 #{agents}，本插件会替换成实际内容。例如：
#   set -g status-right '#{agents} | %H:%M'
#
# 可选项：
#   @agents-interval   状态栏刷新秒数（默认 2）
#   @agents-key        prefix 后唤起弹窗菜单的键（默认 a）
set -f  # 关闭文件名通配，避免 status-format[0] 被当通配符

# 最低版本守卫：range/多行 status 需 tmux ≥ 3.0（居中布局需 3.3，见 README）
NEED=3.0
HAVE=$(tmux -V 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
if [ -z "$HAVE" ] || ! awk -v h="$HAVE" -v n="$NEED" 'BEGIN{
    split(h,H,".");split(n,N,".");
    exit ((H[1]*100+H[2]) >= (N[1]*100+N[2])) ? 0 : 1 }'; then
  tmux display-message "tmux-agents 需要 tmux ≥ ${NEED}（当前 ${HAVE:-未知}）" 2>/dev/null
  exit 0
fi

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEG="#(${CURRENT_DIR}/scripts/bar.sh #{pane_id})"

opt() { tmux show -gqv "$1" 2>/dev/null; }

# 把用户 status 各处的 #{agents} 占位符替换成实际调用
replaced=0
for o in status-left status-right 'status-format[0]' 'status-format[1]' 'status-format[2]'; do
  val="$(opt "$o")"
  case "$val" in
    *'#{agents}'*) tmux set -g "$o" "${val//'#{agents}'/$SEG}"; replaced=1 ;;
    *"$CURRENT_DIR/scripts/bar.sh"*) replaced=1 ;;   # 已就位（防重复追加）
  esac
done
# 没写占位符也没就位 → 自动挂到 status-right 开头（@agents-auto off 可关）
if [ "$replaced" = 0 ] && [ "$(opt @agents-auto)" != off ]; then
  cur="$(opt status-right)"
  tmux set -g status-right "$SEG $cur"
fi

# 可选：自动装 Claude Code hooks（@agents-auto-hooks on）。幂等 + 无变化不写，后台执行。
if [ "$(opt @agents-auto-hooks)" = on ]; then
  ( "$CURRENT_DIR/scripts/install-hooks.sh" >/dev/null 2>&1 & )
fi

# 刷新间隔（spinner / 时长 / 兜底状态）
interval="$(opt @agents-interval)"; [ -z "$interval" ] && interval=2
tmux set -g status-interval "$interval"

# active 跟手：切换 pane/窗口/会话时立即刷新
tmux set-hook -g after-select-pane    "refresh-client -S"
tmux set-hook -g after-select-window  "refresh-client -S"
tmux set-hook -g client-session-changed "refresh-client -S"

# 左键点状态栏里的 agent 区域 → 跳到该 pane；否则保持默认（点窗口切换）
tmux bind -n MouseDown1Status if-shell -F "#{m:[0-9]*,#{mouse_status_range}}" \
  "run-shell '${CURRENT_DIR}/scripts/jump.sh #{mouse_status_range}'" \
  "switch-client -t ="

# prefix + key / 右键状态栏 → 弹窗菜单（有 fzf 用实时预览，否则文本菜单）
KEY="$(opt @agents-key)"; [ -z "$KEY" ] && KEY=a
POPUP="display-popup -E -w 90% -h 80% '${CURRENT_DIR}/scripts/pick.sh'"
MENU="run-shell '${CURRENT_DIR}/scripts/menu.sh'"
tmux bind "$KEY" if-shell 'command -v fzf >/dev/null' "$POPUP" "$MENU"
tmux bind -n MouseDown1StatusRight if-shell 'command -v fzf >/dev/null' "$POPUP" "$MENU"

# prefix + Tab / Shift+Tab → 在 agent 之间循环切换（-r 可连续按）
NEXT="$(opt @agents-next-key)"; [ -z "$NEXT" ] && NEXT=Tab
PREV="$(opt @agents-prev-key)"; [ -z "$PREV" ] && PREV=BTab
tmux bind -r "$NEXT" run-shell "${CURRENT_DIR}/scripts/cycle.sh next #{pane_id}"
tmux bind -r "$PREV" run-shell "${CURRENT_DIR}/scripts/cycle.sh prev #{pane_id}"

# prefix + Enter → 一键直达「需要你」的 agent（只在 needs-you 间跳，-r 可连按）
ATTN="$(opt @agents-attention-key)"; [ -z "$ATTN" ] && ATTN=Enter
tmux bind -r "$ATTN" run-shell "${CURRENT_DIR}/scripts/cycle.sh next #{pane_id} blocked"

# prefix + g 然后按数字 → 直达状态栏里第 N 个 agent（序号见状态栏）
# 用一次性 key-table，避开 prefix+数字（切窗口）的冲突
GOTO="$(opt @agents-goto-key)"; [ -z "$GOTO" ] && GOTO=g
tmux bind "$GOTO" switch-client -T agents_goto
for i in 1 2 3 4 5 6 7 8 9; do
  tmux bind -T agents_goto "$i" run-shell "${CURRENT_DIR}/scripts/goto.sh $i"
done
