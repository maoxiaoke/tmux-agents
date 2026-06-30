# tmux-agents 技术文档

面向贡献者 / 维护者。讲清楚它**怎么工作的**、**为什么这么设计**、**怎么扩展**。
用户安装与使用见 [USAGE.md](./USAGE.md)。

---

## 1. 设计目标与取舍

| 目标 | 取舍 |
|---|---|
| 寄生在 tmux 里，零迁移、终端无关 | 不做独立 app/daemon（那是 [herdr](https://herdr.dev) 的路子，拼不过也不该拼） |
| 状态**准且即时** | 优先让 agent 主动上报（hooks），**不靠截屏猜**；截屏只做兜底 |
| 纯 shell + tmux，可改可读 | 不引入运行时依赖（fzf 可选） |
| 跨 macOS / Linux | `date` / `ps` 做兼容分支 |

核心理念一句话：**presence 由 tmux/ps 决定，state 由 agent 上报决定。**

---

## 2. 架构总览

```
                        ┌─────────────────────────────────────────┐
   Claude Code 进程      │  ~/.claude/settings.json  hooks          │
   （在某个 tmux pane）  │   UserPromptSubmit → claude-hook.sh working
        │               │   Notification     → claude-hook.sh needs-you
        │  事件触发       │   Stop             → claude-hook.sh idle  │
        ▼               └─────────────────────────────────────────┘
   claude-hook.sh ──写──▶  hook store   ~/.cache/tmux-agents/hook/<pane>
        │                      ▲  (status, since, last)
        │ refresh-client -S    │ 读
        ▼                      │
   ┌──────────┐   调用    ┌────────┐  presence: tmux list-panes + ps
   │ tmux     │──────────▶│ bar.sh │──▶ scan.sh ─┤ state: hook store 优先
   │ status   │  #(...)   └────────┘             └ 兜底: capture-pane 底部
   │ -format  │◀──────────  渲染文本（含 #[range=user|N] 可点击区域）
   └──────────┘
        │  点击 / prefix+a / 右键
        ▼
   jump.sh（跳转） / menu.sh（文本菜单） / pick.sh（fzf 预览）
```

数据流分两条：
- **写状态**：agent 的 hook 进程 → hook store（事件驱动，瞬时）。
- **读+渲染**：tmux 状态栏每 `status-interval` 秒 + 每次焦点切换（`refresh-client -S`）调用 `bar.sh` → `scan.sh` 聚合 → 输出带可点击 range 的文本。

---

## 3. 组件职责

| 文件 | 角色 | 职责 |
|---|---|---|
| `agents.tmux` | 插件入口（TPM） | 把状态栏里的 `#{agents}` 占位替换成 `#(bar.sh #{pane_id})`；设刷新间隔、焦点刷新 hook、点击/弹窗键位；读 `@agents-*` 选项 |
| `scripts/scan.sh` | 聚合器 | 列出所有 pane，找出跑 agent 的，确定每个的 `status` 和 `working` 时长，输出 TSV |
| `scripts/bar.sh` | 渲染器 | 调 `scan.sh`，排序/消歧/溢出折叠/上色，输出 tmux 状态栏文本 |
| `scripts/claude-hook.sh` | Claude 适配器 | 作为 Claude Code hook 被调用，把状态写进 hook store |
| `scripts/jump.sh` | 跳转 | 给定 pane 号，切 session→window→pane |
| `scripts/menu.sh` | 文本菜单 | 无 fzf 时的 `display-menu` 回退 |
| `scripts/pick.sh` | fzf 选择器 | `display-popup` 里跑 fzf，右侧实时预览 pane 画面 |

---

## 4. 状态模型

四个状态，**渲染时**区分（`active` 是渲染期叠加的，不进 store）：

| 状态 | 含义 | 视觉 |
|---|---|---|
| `active` | 当前客户端**聚焦**的 agent | 高亮药丸（蓝；若同时 blocked 则红） |
| `working` | 正在干活 | spinner `⠋⠙…` + 时长 `working 2m`（黄） |
| `blocked` | **需要你**（等输入/确认） | `! 名字 · needs you`（红） |
| `idle` | 空闲待命 | `✓ 名字 · idle`（绿勾 + 暗灰） |

**判定优先级（scan.sh）**：先看 hook store；store 没有才截屏兜底。
**渲染优先级（bar.sh）**：`active` 高亮覆盖一切；其余按 store/兜底给出的 working/blocked/idle。

> `active` 为什么单独算、且只认 `#{pane_id}`？因为「聚焦」是**客户端**概念。早期版本用 `pane_active && window_active` 推断，会被 agent 完成时的**响铃**干扰（bell 让 pane 被标活动）。现在 `bar.sh $1 = #{pane_id}`（状态栏绘制时 tmux 传入的聚焦 pane），严格跟随焦点。副作用利好：`#{pane_id}` 是 `#()` 命令串的一部分，焦点一变命令串变 → tmux 立即重跑 → 高亮瞬时跟手。

---

## 5. 状态来源

### 5.1 Hook store（主，准）

- 路径：`${XDG_CACHE_HOME:-~/.cache}/tmux-agents/hook/<pane-number>`
  （`<pane-number>` = `$TMUX_PANE` 去掉 `%`，如 `%9`→`9`）
- 内容（单行 TSV）：`status \t since_epoch \t last_epoch`
  - `status` ∈ `working | needs-you | idle`
  - `since_epoch`：进入**当前状态**的时刻（用于 working 时长）
  - `last_epoch`：最后一次上报时刻
- 由 `claude-hook.sh` 写；`scan.sh` 只读。

### 5.2 截屏兜底（次，猜）

没 hook 的 agent（aider/codex…）或还没触发过 hook 的 claude，`scan.sh` 退回截屏：

```sh
footer=$(tmux capture-pane -p -t "$pid" | grep -v '^[[:space:]]*$' | tail -n 6)
```

**只看底部 6 行**，因为 claude 的工作指示/提示恒在 footer。
> 早期扫整屏导致 bug：pane 显示的对话正文里若出现 “esc to interrupt” 这几个字（比如在讨论本项目），会被误判为 working。只看 footer 后正文不再干扰。

匹配规则（可用环境变量覆盖）：
- `AGENT_WORKING_RE`（默认 `esc to interrupt`）→ working
- `AGENT_BLOCKED_RE`（默认含 `Do you want|❯ 1\.|(y/n)…`）→ blocked
- 都不中 → idle

兜底场景的 working 起始时间存在 `~/.cache/tmux-agents/scrape/<pane>`，由 `scan.sh` 维护。

---

## 6. Claude hook 适配器

`claude-hook.sh <state>` 被 Claude Code 在不同事件调用：

| Claude 事件 | 传参 | 落库 status |
|---|---|---|
| `UserPromptSubmit`（用户发消息，开始干活） | `working` | working |
| `Notification`（claude 需要你） | `needs-you` | needs-you |
| `Stop`（一轮回答结束） | `idle` | idle |

关键点：
- **pane 定位**：hook 进程继承 claude 所在 pane 的 `$TMUX_PANE`，天然知道写哪个文件。无 `$TMUX_PANE`（如 herdr 自管的 PTY）→ 直接退出，不污染。
- **working 时长保持**：若新状态 == 旧状态，保留 `since_epoch`（否则每次 `PreToolUse`/重复 working 都会重置计时）。
- **即时刷新**：写完 `tmux refresh-client -S`，状态栏立刻更新。
- **不读 stdin 会阻塞**：claude 把事件 JSON 写到 hook 的 stdin，脚本 `cat >/dev/null` 读掉。

---

## 7. 时序示例

**(a) 一轮对话**
```
你发消息 → UserPromptSubmit hook → store=working,since=T0 → 刷新 → 状态栏 ⠿ working 0s
（每秒 status-interval 重跑 bar，时长累加：working 5s, 12s…）
claude 问你确认 → Notification hook → store=needs-you → 状态栏变红 ! needs you
你回答、claude 干完 → Stop hook → store=idle → 状态栏 ✓ idle
```

**(b) 切换焦点**
```
你切到另一个 agent pane → tmux 重绘状态栏，#{pane_id} 变 → bar.sh 收到新 FOCUS
→ 新 pane 高亮蓝药丸，旧的恢复普通样式（同一秒内）
```

---

## 8. 渲染细节（bar.sh）

- **排序**：按 `start_epoch`（agent 进程启动时间）升序 → 位置稳定，不随状态变化跳动。
- **同名消歧**：先统计 `cwd` basename 次数；撞名的追加 pane 号 `apps#0.2`。
- **spinner**：`frames[ now % 10 ]`，用 bash **数组**索引（不能用 `${str:i:1}` 字节切片，多字节会断）。
- **时长**：`fmt()` → `45s` / `2m` / `1h3m`。
- **溢出折叠**：按 `client_width` 估预算；`working/blocked/active` 必显，多余的 `idle` 折叠成 `+N ✓`。
- **可点击**：每段包 `#[range=user|<num>]…#[norange]`，`<num>` 是 pane 号纯数字（避开 `%` 与 strftime 的 `%H` 冲突）。

### 点击如何跳转
`agents.tmux` 绑定：
```tmux
bind -n MouseDown1Status if-shell -F "#{m:[0-9]*,#{mouse_status_range}}" \
  "run-shell 'jump.sh #{mouse_status_range}'" \
  "switch-client -t ="
```
点到 agent 区域 → `mouse_status_range` 是数字 → 调 `jump.sh`；点到窗口列表等 → 数字不匹配 → 走默认 `switch-client -t =`（不破坏原生点窗口）。

---

## 9. 性能与刷新

- 每个刷新周期：`tmux list-panes` 1 次 + 每个 pane `ps -t` 1 次；**只有没 hook 的 pane** 才额外 `capture-pane`。hook 让 claude 跳过截屏，是主要省开销点。
- 刷新来源：`status-interval`（默认 2s，影响 spinner/时长 tick）+ 焦点切换 hook（`refresh-client -S`）+ claude-hook 写完的主动刷新。
- `#()` 输出被 tmux 按 `status-interval` 缓存；`#{pane_id}` 作为参数变化时缓存键变 → 立即重跑。

---

## 10. 跨平台注意

| 点 | macOS / BSD | Linux / GNU |
|---|---|---|
| lstart→epoch | `date -j -f '%a %b %e %T %Y'` | `date -d` |
| `ps -o lstart=` | 支持 | 支持 |
| `${#str}` 计数 | UTF-8 locale 下按字符 | 同 |

`scan.sh` 的 `to_epoch()` 先试 BSD 形式失败再试 GNU。

---

## 11. 扩展：新增一个 agent 适配器

两条路：

1. **有 hook/状态机制的 agent（首选，像 claude）**：写一个 `<agent>-hook.sh`（或复用 `claude-hook.sh` 的形式），在该 agent 的事件里把 `working/needs-you/idle` 写进 hook store。`scan.sh` 自动认。
2. **没有 hook 的 agent**：把它的进程名加进 `AGENT_PATTERN`，并按它的 TUI 调 `AGENT_WORKING_RE` / `AGENT_BLOCKED_RE`。走截屏兜底。

> store 格式与 pane 定位是通用契约，任何能拿到 `$TMUX_PANE` 的适配器都能复用。

---

## 12. 已知限制

- 截屏兜底的状态判定是**启发式**，依赖 agent TUI 文案，版本变了要调正则。
- 只追踪**直接跑在 tmux pane** 里的 agent；herdr 等自管 PTY 的 agent 看不到（也不应该，由它自己管）。
- session/window 名含空格可能影响 `jump.sh` 的 target 解析（v0.1 未加引号加固）。
- hook store 文件在 agent 退出后会残留（很小、pane id 不复用，无害；可加 SessionEnd 清理）。
- 居中布局依赖自定义 `status-format`，tmux 需 ≥ 3.3。

---

## 13. 目录

```
agents.tmux                 # TPM 入口
scripts/
  scan.sh                   # 聚合（presence + state + 时长）
  bar.sh                    # 渲染
  claude-hook.sh            # Claude 状态上报
  jump.sh menu.sh pick.sh   # 跳转 / 菜单 / fzf 预览
docs/
  ARCHITECTURE.md           # 本文
  USAGE.md                  # 用户文档
```
