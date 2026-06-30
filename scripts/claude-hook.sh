#!/usr/bin/env bash
# Claude Code hook：把当前 agent 的状态上报给 tmux-agents store。
# 在 ~/.claude/settings.json 的 hooks 里配置，参数为状态：
#   UserPromptSubmit / PreToolUse → working
#   Notification                  → needs-you
#   Stop                          → idle
new="${1:-idle}"

# 不在 tmux 里就什么都不做（claude 进程继承所在 pane 的 $TMUX_PANE）
[ -z "$TMUX_PANE" ] && { cat >/dev/null 2>&1; exit 0; }

# claude 通过 stdin 传 JSON，我们用不到——读掉以免阻塞
cat >/dev/null 2>&1

num="${TMUX_PANE#%}"
dir="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-agents/hook"
mkdir -p "$dir" 2>/dev/null
f="$dir/$num"
now=$(date +%s)

old_status=''; old_since="$now"
[ -f "$f" ] && IFS=$'\t' read -r old_status old_since _ < "$f"

# 状态不变则保留起始时间（用于计算 working 时长）
if [ "$new" = "$old_status" ] && [ -n "$old_since" ]; then
  since="$old_since"
else
  since="$now"
fi

printf '%s\t%s\t%s\n' "$new" "$since" "$now" > "$f"

# 让状态栏立刻刷新（hook 进程在 pane 内，继承 $TMUX）
tmux refresh-client -S 2>/dev/null
exit 0
