#!/usr/bin/env bash
# 聚合所有 tmux pane 里的 AI agent 及其状态。
# 状态优先读 hook store（claude 主动上报，准且即时）；没有则退回截屏兜底。
# 输出 TSV：pid target status agent cwd_basename window_name cwd_full(~) active start_epoch working_elapsed
#
# 可调环境变量：
#   AGENT_PATTERN     匹配 agent 进程的正则
#   AGENT_WORKING_RE  截屏兜底时“工作中”的文本
#   AGENT_BLOCKED_RE  截屏兜底时“需要你”的文本
PATTERN="${AGENT_PATTERN:-claude|aider|codex|opencode|gemini|cursor-agent}"
WORKING_RE="${AGENT_WORKING_RE:-esc to interrupt}"
BLOCKED_RE="${AGENT_BLOCKED_RE:-Do you want|Would you like|❯ 1\.|\(y/n\)|\[y/N\]|Continue\?|approve|allow this}"

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-agents"
HOOK_DIR="$CACHE/hook"
SCRAPE_DIR="$CACHE/scrape"
mkdir -p "$SCRAPE_DIR" 2>/dev/null
now=$(date +%s)

# 跨平台：lstart 字符串 → epoch（先试 macOS/BSD，再试 GNU）
to_epoch() { date -j -f '%a %b %e %T %Y' "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null; }

tmux list-panes -a -F '#{pane_id}	#{session_name}	#{window_index}	#{pane_index}	#{pane_tty}	#{window_name}	#{pane_current_path}	#{?#{&&:#{pane_active},#{&&:#{window_active},#{session_attached}}},1,0}' 2>/dev/null |
while IFS=$'\t' read -r pid sess win pane tty wname cpath active; do
  [ -z "$tty" ] && continue
  num="${pid#%}"

  # 该 pane 上是否有 agent 进程？（兼顾名字与启动时间，也用于兜底）
  aline=$(ps -t "${tty#/dev/}" -o pid=,lstart=,args= 2>/dev/null \
            | grep -iE "$PATTERN" | grep -ivE 'tmux-agents|/scripts/(scan|bar|menu|pick)\.sh|claude-hook' | head -1)
  [ -z "$aline" ] && continue

  agent=$(printf '%s' "$aline" | grep -ioE "$PATTERN" | head -1)
  lstart=$(printf '%s' "$aline" | awk '{print $2,$3,$4,$5,$6}')
  start_epoch=$(to_epoch "$lstart"); [ -z "$start_epoch" ] && start_epoch=0

  hf="$HOOK_DIR/$num"
  if [ -f "$hf" ]; then
    # —— 来自 agent hook 上报 ——
    IFS=$'\t' read -r hstatus hsince _ < "$hf"
    case "$hstatus" in
      working)          status=working; since=${hsince:-$now} ;;
      needs-you|blocked) status=blocked; since=$now ;;
      *)                status=idle;    since=$now ;;
    esac
  else
    # —— 截屏兜底：只看底部 6 行（避免对话正文里的同名文字误判）——
    footer=$(tmux capture-pane -p -t "$pid" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -n 6)
    if printf '%s' "$footer" | grep -qiE "$WORKING_RE"; then status=working
    elif printf '%s' "$footer" | grep -qE "$BLOCKED_RE"; then status=blocked
    else status=idle; fi
    # 兜底场景的 working 起始时间存在 scrape store
    sf="$SCRAPE_DIR/$num"
    if [ "$status" = working ]; then
      since=$(cat "$sf" 2>/dev/null); [ -z "$since" ] && { since=$now; echo "$since" > "$sf"; }
    else
      rm -f "$sf" 2>/dev/null; since=$now
    fi
  fi

  elapsed=$(( now - since ))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$pid" "$sess:$win.$pane" "$status" "$agent" "$(basename "$cpath")" "$wname" "${cpath/#$HOME/\~}" "$active" "$start_epoch" "$elapsed"
done
