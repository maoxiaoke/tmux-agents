# tmux-agents 使用文档

在 tmux 状态栏里常驻显示正在运行的 AI coding agent（Claude Code、aider…）及其状态，
点击或弹窗即可跳到对应 pane。

![tmux-agents 状态栏：idle / working / needs-you / active 四态一览](./assets/statusbar.png)

> 想了解内部原理 / 参与开发，见 [ARCHITECTURE.md](./ARCHITECTURE.md)。

---

## 1. 依赖

- **tmux ≥ 3.0**（多行/可点击需 3.2+，居中布局需 3.3+）
- bash、coreutils（macOS / Linux 均可）

---

## 2. 安装

### 方式 A：TPM（推荐）

`~/.tmux.conf`：
```tmux
set -g @plugin 'maoxiaoke/tmux-agents'
```
然后 `prefix + I` 安装。

### 方式 B：手动

```tmux
run-shell /path/to/tmux-agents/agents.tmux
```

---

## 3. agent 列表放哪

默认挂在 `status-right`。换位置只需一行：

```tmux
set -g @agents-position center   # right（默认）| center | left
```

`center` 会保留左侧窗口列表、右侧时钟，把 agent 列表放中间（居中需 tmux ≥ 3.3；那条复杂的 `status-format` 由插件内部生成，你不用管）。

想**精确**控制，就自己在 `status-left` / `status-right` / `status-format` 里放占位符 `#{agents}`：

```tmux
set -g status-right '#{agents} | %H:%M '
```

> 改完 `tmux source-file ~/.tmux.conf` 或重开 tmux。

---

## 4. 让 Claude Code 精准上报状态（强烈推荐）

不配也能用（自动截屏兜底判断），**但配了之后状态最准、最即时**（不依赖屏幕文案）。

**一键安装（推荐）**，自动合并进 `~/.claude/settings.json`（幂等、自动备份、保留你已有的其它 hook）：

```sh
/path/to/tmux-agents/scripts/install-hooks.sh
# 卸载： scripts/install-hooks.sh uninstall
```

<details><summary>或手动加（等价）——把路径换成你的安装路径</summary>

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
</details>

> **`PreToolUse` 的 matcher 是标红 AskUserQuestion / 计划审批的唯一途径**：这俩是 claude 内部工具，不走权限、不走 MCP，只能靠 `AskUserQuestion|ExitPlanMode` 标 needs-you。别给 PreToolUse 再挂无 matcher 的 working，会抢写。
> **`PostToolUse` 是「needs-you 恢复」的关键**：你答完问题 / 批准权限后，工具跑完那一刻 → 立刻从红色回到 working。
> **`Notification` 的 matcher 不能省**：`permission_prompt`/`elicitation_dialog` 是「需要你」，`elicitation_complete`/`elicitation_response` 是「答完了→working」；`idle_prompt`（空闲 60s）、`auth_success` 都不是，不加 matcher 会误报成红。
> **`StopFailure`** 覆盖「回合因 API 报错结束」，否则卡在 working。

**生效范围**：Claude Code 在**会话启动时**读 settings.json。已经在跑的会话不会立刻生效，**新开的 claude 会话**才会按 hook 上报。已有会话在此期间走截屏兜底。

> 已经在用其它 hook？一键脚本会**原样保留**它们，只增删本插件自己的条目；手动加也不冲突（事件不同）。

---

## 5. 配置项

tmux 选项（写在 `.tmux.conf`，放在加载插件之前）：

| 选项 | 默认 | 说明 |
|---|---|---|
| `@agents-position` | `right` | 自动放置位置：`right` / `center` / `left`（`center` 保留窗口列表+时钟） |
| `@agents-auto` | `on` | 没写 `#{agents}` 占位时自动挂；`off` 则只认占位符 |
| `@agents-auto-hooks` | `off` | `on` → 插件加载时自动装 Claude hooks（幂等、无变化不写） |
| `@agents-interval` | `2` | 状态栏刷新秒数（影响 spinner 动画与时长 tick） |
| `@agents-next-key` | `Tab` | `prefix + <key>` 切到下一个 agent（可连按） |
| `@agents-prev-key` | `BTab` | `prefix + <key>` 切到上一个 agent（`BTab` = Shift+Tab） |
| `@agents-attention-key` | `Enter` | `prefix + <key>` 一键直达 needs-you 的 agent |
| `@agents-goto-key` | `g` | `prefix + <key>` 然后按数字，直达第 N 个 agent |

```tmux
set -g @agents-interval 1
set -g @agents-next-key Tab
set -g @agents-prev-key BTab
set -g @agents-attention-key Enter
set -g @agents-goto-key g
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
| `prefix + Tab` / `prefix + Shift+Tab` | 在 agent 间循环切下一个 / 上一个（按启动时间序，可连按） |
| `prefix + Enter` | **一键直达需要你的 agent**：只在 needs-you 之间跳；没有则提示 |
| `prefix + g` 然后按数字 | **直达状态栏第 N 个 agent**：状态栏每个 agent 前带序号；用一次性 key-table，不占用 `prefix+数字`（切窗口） |

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
- 已自动补 pane 号 `apps#0.2`；`prefix + g` 按号直达对应 pane。

**切 agent 后高亮慢半拍**
- 焦点切换会触发 `refresh-client -S` 应即时；若仍慢，调小 `@agents-interval`。

**Linux 上时长不对**
- `scan.sh` 的 `to_epoch()` 已兼容 GNU `date -d`；若仍异常，确认 `ps -o lstart=` 输出格式。

---

## 9. 卸载

**一键**（移除 hooks + 缓存 + 运行期键位/状态栏改动，保留你已有的其它 hook）：

```sh
scripts/uninstall.sh
```

然后手动删掉 `.tmux.conf` 里的 `@plugin 'maoxiaoke/tmux-agents'`（或 `run-shell` 那行）和 `#{agents}` 占位 / `@agents-*` 选项；用 TPM 的话 `prefix + alt+u` 清目录；最后 `tmux source-file ~/.tmux.conf`。

> 单独增删 hooks 也可以：`scripts/install-hooks.sh` / `scripts/install-hooks.sh uninstall`。
