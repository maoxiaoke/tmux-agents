# tmux-agents

在 tmux 状态栏里常驻显示正在运行的 **AI coding agent**（Claude Code、aider、codex…），
带 **active / working / needs-you / idle** 状态，点击或弹窗即可跳到对应 pane。

把 [herdr](https://herdr.dev) 那种「agent 仪表盘」体验做成一个**纯 tmux 插件** —— 零迁移、终端无关、可改、开源。

```
 ✓ api · idle    ⠴ web · working 1m12s    ! infra · needs you
 └ 空闲(绿)      └ 工作中(spinner+时长)     └ 等你确认(红)
```

- **跨 window / session 可见**：不管切到哪，状态栏都列出所有 agent
- **状态准且即时**：Claude Code 通过 hooks 主动上报状态（非截屏猜测）；其它 agent 截屏兜底
- **active 跟随焦点**：你在哪个 agent，哪个高亮，不受响铃/完成干扰
- **点击跳转** + **fzf 实时预览弹窗**（撞名也能一眼分清）
- 按启动时间排序，位置稳定；同名目录自动补 pane 号；窄屏自动折叠

## 安装

### TPM（推荐）

```tmux
set -g @plugin 'you/tmux-agents'
```

在状态栏里放占位符 `#{agents}`，插件会替换成实际内容：

```tmux
# 放右边
set -g status-right '#{agents} | %H:%M '

# 或放左边
set -g status-left '#S #{agents}'
```

按 `prefix + I` 安装。

### 手动

```tmux
run-shell /path/to/tmux-agents/agents.tmux
```

### 居中（可选）

居中需要自定义 `status-format`：

```tmux
set -g status-format[0] '#[align=left]#{T:status-left}#[align=centre]#{agents}#[align=right]#{T:status-right}'
```

## 让 Claude Code 上报状态（强烈推荐）

不配也能用（截屏兜底），但配了 hooks 后状态**最准、最即时**。在 `~/.claude/settings.json` 加：

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "/path/to/tmux-agents/scripts/claude-hook.sh working" } ] }
    ],
    "PreToolUse": [
      { "matcher": "AskUserQuestion|ExitPlanMode",
        "hooks": [ { "type": "command", "command": "/path/to/tmux-agents/scripts/claude-hook.sh needs-you" } ] }
    ],
    "PostToolUse": [
      { "hooks": [ { "type": "command", "command": "/path/to/tmux-agents/scripts/claude-hook.sh working" } ] }
    ],
    "Notification": [
      { "matcher": "permission_prompt|elicitation_dialog",
        "hooks": [ { "type": "command", "command": "/path/to/tmux-agents/scripts/claude-hook.sh needs-you" } ] },
      { "matcher": "elicitation_complete|elicitation_response",
        "hooks": [ { "type": "command", "command": "/path/to/tmux-agents/scripts/claude-hook.sh working" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "/path/to/tmux-agents/scripts/claude-hook.sh idle" } ] }
    ],
    "StopFailure": [
      { "hooks": [ { "type": "command", "command": "/path/to/tmux-agents/scripts/claude-hook.sh idle" } ] }
    ]
  }
}
```

各 hook 的作用：
- `UserPromptSubmit` → **working**（开始干活）
- `PreToolUse` `AskUserQuestion|ExitPlanMode` → **needs-you**。**这条是关键**：AskUserQuestion（多选提问）/ ExitPlanMode（计划待批）是 claude 内部工具，不走权限、也不走 MCP，只能靠这个 matcher 标红。**不能给 PreToolUse 挂无 matcher 的 working**，会和它抢写。
- `PostToolUse` → **working**。工具跑完（= 你答完提问 / 批准权限后工具执行完）立刻从红色恢复 working。
- `Notification` `permission_prompt|elicitation_dialog` → **needs-you**；`elicitation_complete|elicitation_response` → **working**。**matcher 不能省**，否则 `idle_prompt`（空闲 60s）、`auth_success` 会被误判成红。
- `Stop` / `StopFailure` → **idle**（正常结束 / API 报错结束都要归位，否则卡在 working）

hook 进程继承所在 pane 的 `$TMUX_PANE`，所以天然知道是哪个 agent。

## 选项

| 选项 | 默认 | 说明 |
|---|---|---|
| `@agents-interval` | `2` | 状态栏刷新秒数（影响 spinner/时长） |
| `@agents-key` | `a` | `prefix + <key>` 唤起弹窗菜单 |
| `@agents-next-key` | `Tab` | `prefix + <key>` 切到下一个 agent（可 `-r` 连按） |
| `@agents-prev-key` | `BTab` | `prefix + <key>` 切到上一个 agent（BTab = Shift+Tab） |
| `AGENT_PATTERN` (env) | `claude\|aider\|codex\|opencode\|gemini\|cursor-agent` | 识别 agent 进程的正则 |
| `AGENT_WORKING_RE` (env) | `esc to interrupt` | 截屏兜底时「工作中」文本 |
| `AGENT_BLOCKED_RE` (env) | 见脚本 | 截屏兜底时「需要你」文本 |

## 操作

| 操作 | 行为 |
|---|---|
| 左键点状态栏里的 agent | 跳到该 pane |
| `prefix + a` / 右键状态栏 | 弹窗菜单（有 fzf 用实时预览） |
| `prefix + Tab` / `prefix + Shift+Tab` | 在 agent 间循环切下一个 / 上一个（可连按） |

## 工作原理

- **presence**：`tmux list-panes` + `ps` 找出哪些 pane 在跑 agent。
- **state**：优先读 hook store（`~/.cache/tmux-agents/hook/<pane>`，由 agent 自己写）；
  没有则截屏底部几行做兜底判断（只看 footer，避免对话正文里的同名文字误判）。
- **render**：`bar.sh` 输出带 `#[range=...]` 的可点击状态栏文本。

## 依赖

- tmux ≥ 3.0（多行/range 需 3.2+，居中需 3.3+）
- bash、coreutils（macOS/Linux 均可）
- 可选：`fzf`（实时预览弹窗）

## License

MIT
