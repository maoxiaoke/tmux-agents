# tmux-agents 使用文档

在 tmux 状态栏里常驻显示正在运行的 AI coding agent（Claude Code、aider…）及其状态，
点击或弹窗即可跳到对应 pane。

```
 ✓ api · idle    ⠴ web · working 1m12s    ! infra · needs you
```

> 想了解内部原理 / 参与开发，见 [ARCHITECTURE.md](./ARCHITECTURE.md)。

---

## 1. 依赖

- **tmux ≥ 3.0**（多行/可点击需 3.2+，居中布局需 3.3+）
- bash、coreutils（macOS / Linux 均可）
- 可选：**fzf**（启用弹窗实时预览；没有则用文本菜单）

---

## 2. 安装

### 方式 A：TPM（推荐）

`~/.tmux.conf`：
```tmux
set -g @plugin 'you/tmux-agents'
```
然后 `prefix + I` 安装。

### 方式 B：手动

```tmux
run-shell /path/to/tmux-agents/agents.tmux
```

---

## 3. 把 agent 列表放到状态栏

在状态栏任意位置放占位符 **`#{agents}`**，插件加载时会替换成实际内容。

**放右边：**
```tmux
set -g status-right '#{agents} | %H:%M '
```

**放左边：**
```tmux
set -g status-left '#S #{agents}'
```

**居中**（需要 tmux ≥ 3.3，自定义 `status-format`）：
```tmux
set -g status-format[0] '#[align=left]#{T:status-left}#[align=centre]#{agents}#[align=right]#{T:status-right}'
```

> 改完 `tmux source-file ~/.tmux.conf` 或重开 tmux。

---

## 4. 让 Claude Code 精准上报状态（强烈推荐）

不配也能用（自动截屏兜底判断），**但配了之后状态最准、最即时**（不依赖屏幕文案）。

在 `~/.claude/settings.json` 的 `hooks` 里加（把路径换成你的安装路径）：

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

> **`PreToolUse` 的 matcher 是标红 AskUserQuestion / 计划审批的唯一途径**：这俩是 claude 内部工具，不走权限、不走 MCP，只能靠 `AskUserQuestion|ExitPlanMode` 标 needs-you。别给 PreToolUse 再挂无 matcher 的 working，会抢写。
> **`PostToolUse` 是「needs-you 恢复」的关键**：你答完问题 / 批准权限后，工具跑完那一刻 → 立刻从红色回到 working。
> **`Notification` 的 matcher 不能省**：`permission_prompt`/`elicitation_dialog` 是「需要你」，`elicitation_complete`/`elicitation_response` 是「答完了→working」；`idle_prompt`（空闲 60s）、`auth_success` 都不是，不加 matcher 会误报成红。
> **`StopFailure`** 覆盖「回合因 API 报错结束」，否则卡在 working。

**生效范围**：Claude Code 在**会话启动时**读 settings.json。已经在跑的会话不会立刻生效，**新开的 claude 会话**才会按 hook 上报。已有会话在此期间走截屏兜底。

> 已经在用其它 hook（如 herdr 的 SessionStart）？直接把上面三条**加进** `hooks` 即可，事件不同，互不冲突。

---

## 5. 配置项

tmux 选项（写在 `.tmux.conf`，放在加载插件之前）：

| 选项 | 默认 | 说明 |
|---|---|---|
| `@agents-interval` | `2` | 状态栏刷新秒数（影响 spinner 动画与时长 tick） |
| `@agents-key` | `a` | `prefix + <key>` 唤起弹窗菜单 |
| `@agents-next-key` | `Tab` | `prefix + <key>` 切到下一个 agent（可连按） |
| `@agents-prev-key` | `BTab` | `prefix + <key>` 切到上一个 agent（`BTab` = Shift+Tab） |

```tmux
set -g @agents-interval 1
set -g @agents-key a
set -g @agents-next-key Tab
set -g @agents-prev-key BTab
```

环境变量（高级，调检测规则）：

| 变量 | 默认 | 说明 |
|---|---|---|
| `AGENT_PATTERN` | `claude\|aider\|codex\|opencode\|gemini\|cursor-agent` | 识别 agent 进程的正则 |
| `AGENT_WORKING_RE` | `esc to interrupt` | 截屏兜底时判定「工作中」的文本 |
| `AGENT_BLOCKED_RE` | 见脚本 | 截屏兜底时判定「需要你」的文本 |

---

## 6. 操作

| 操作 | 行为 |
|---|---|
| **左键**点状态栏里某个 agent | 跳到那个 pane |
| `prefix + a`（或右键状态栏） | 弹出菜单：有 fzf → 左列表 + 右**实时预览**画面；无 fzf → 文本菜单 |
| 在 fzf 弹窗里 `↑↓` | 预览不同 agent，回车跳转，esc 取消 |
| `prefix + Tab` / `prefix + Shift+Tab` | 在 agent 间循环切下一个 / 上一个（按启动时间序，可连按） |

---

## 7. 状态含义对照

| 显示 | 状态 | 意思 |
|---|---|---|
| 蓝色高亮药丸 | **active** | 你当前所在的 agent |
| `⠿ 名字 · working 2m`（黄、转圈） | **working** | 正在干活，已 2 分钟 |
| `! 名字 · needs you`（红） | **blocked** | 在等你输入/确认 —— **该去看它** |
| `✓ 名字 · idle`（绿勾 + 暗灰） | **idle** | 空闲待命 |
| `apps#0.2` | — | 同名目录时自动补 pane 号区分 |
| `+3 ✓` | — | 窄屏放不下，折叠了 3 个 idle |
| 默认 agent 是 claude 时不显示 `· claude`；其它显示 `· aider` 等 |

---

## 8. 排错

**状态栏没出现 agent 列表**
- `#{agents}` 占位符有没有放进 status-left/right/format？
- `tmux show -gqv 'status-format[0]'` 看 `#{agents}` 是否被替换成了 `#(.../bar.sh …)`。没替换说明插件没加载（检查 `@plugin` 或 `run-shell` 路径）。

**状态一直 working / 不更新**
- 该 agent 没配 hook → 走截屏兜底，可能文案对不上。`tmux capture-pane -p -t <pane> | tail -n 6` 看底部文本，按需调 `AGENT_WORKING_RE`。
- 配了 hook 但没生效 → 是不是老会话？新开会话再试。

**「needs you」不触发**
- 你若用 `--dangerously-skip-permissions`，权限弹窗不出现；但 claude 问问题/确认时仍会经 `Notification`。截屏兜底则依赖 `AGENT_BLOCKED_RE`，按你的 claude 文案调。

**同名分不清**
- 已自动补 pane 号 `apps#0.2`；要看画面用 `prefix + a` 的 fzf 预览。

**切 agent 后高亮慢半拍**
- 焦点切换会触发 `refresh-client -S` 应即时；若仍慢，调小 `@agents-interval`。

**Linux 上时长不对**
- `scan.sh` 的 `to_epoch()` 已兼容 GNU `date -d`；若仍异常，确认 `ps -o lstart=` 输出格式。

---

## 9. 卸载

- 删掉 `.tmux.conf` 里的 `@plugin 'you/tmux-agents'`（或 `run-shell` 那行）和 `#{agents}` 占位。
- 移除 `~/.claude/settings.json` 里加的三条 hook。
- 可选清缓存：`rm -rf ~/.cache/tmux-agents`。
- `tmux source-file ~/.tmux.conf`。
