# tmux-agents

> See every AI coding agent across your tmux windows and sessions in one status line — who's **working**, who's **idle**, and who **needs you** — and jump to any of them in one keystroke.

![tmux-agents status bar](docs/assets/statusbar.png)

No new app, no daemon. State is **pushed** by the agents themselves (Claude Code hooks), with a screen-scrape fallback for the rest.

## Features

- **Cross-session** — every agent in one bar, no matter which pane you're in.
- **Accurate, live state** — `working` (with elapsed time), `needs you`, `idle`; the focused pane is highlighted and bells never steal it.
- **One keystroke to act** — jump to whoever *needs you*, cycle agents, or go to agent *N* by number. Click, or open an fzf preview popup.
- **Stable & tidy** — ordered by start time, duplicate names disambiguated, narrow bars fold gracefully.

## Requirements

tmux ≥ 3.0 (≥ 3.3 for a centered layout) · bash · coreutils. Optional: [`fzf`](https://github.com/junegunn/fzf) for the preview popup.

## Install

One line — clones the repo, wires `~/.tmux.conf`, installs the Claude Code hooks, and reloads tmux. No TPM required.

```sh
curl -fsSL https://raw.githubusercontent.com/maoxiaoke/tmux-agents/main/install.sh | bash
```

Then open a **new** Claude session — that's it.

<details>
<summary>Review before running (recommended)</summary>

```sh
git clone https://github.com/maoxiaoke/tmux-agents ~/.tmux/plugins/tmux-agents
~/.tmux/plugins/tmux-agents/install.sh
```
</details>

<details>
<summary>With TPM</summary>

```tmux
set -g @plugin 'maoxiaoke/tmux-agents'
set -g @agents-auto-hooks on   # also installs the Claude Code hooks
```

Then `prefix + I`.
</details>

<details>
<summary>Claude Code hooks — what &amp; why</summary>

Agents report state through Claude Code hooks (installed automatically above, or run `scripts/install-hooks.sh` yourself — idempotent, backs up, keeps your existing hooks). Only affects **newly started** sessions.

| Event | Matcher | State |
|---|---|---|
| `UserPromptSubmit`, `PostToolUse` | — | working |
| `PreToolUse` | `AskUserQuestion\|ExitPlanMode` | needs-you |
| `Notification` | `permission_prompt\|elicitation_dialog` | needs-you |
| `Notification` | `elicitation_complete\|elicitation_response` | working |
| `Stop`, `StopFailure` | — | idle |

`PreToolUse`/`Notification` matchers are load-bearing — see [docs/USAGE.md](docs/USAGE.md) for the full config and rationale.
</details>

Placement: it mounts to `status-right` by default. For left or **centered** (keeps your window list + clock), just:

```tmux
set -g @agents-position center   # right (default) | center | left
```

Or drop the `#{agents}` placeholder anywhere in `status-left` / `status-right` / `status-format` to control it exactly.

## Update

Re-running the one-liner pulls the latest, re-syncs the hooks, and reloads — it's the update command too:

```sh
curl -fsSL https://raw.githubusercontent.com/maoxiaoke/tmux-agents/main/install.sh | bash
```

- **TPM:** `prefix + U`, then reload tmux. (Hooks re-sync on reload if `@agents-auto-hooks on`; otherwise run `scripts/install-hooks.sh`.)
- **Manual clone:** `git -C ~/.tmux/plugins/tmux-agents pull && tmux source-file ~/.tmux.conf`.

## Keybindings

`prefix` is your tmux prefix (default `Ctrl+b`).

| Key | Action |
|---|---|
| `prefix + Enter` | Jump to the next agent that **needs you** |
| `prefix + g` then a digit | Go to agent **N** (numbers shown in the bar) |
| `prefix + Tab` / `prefix + S-Tab` | Cycle to next / previous agent |
| `prefix + a` / right-click the bar | Picker (fzf preview if available) |
| Left-click an agent | Jump to its pane |

## Configuration

```tmux
set -g @agents-auto-hooks on    # auto-install Claude hooks on load (default: off)
set -g @agents-interval   1     # status refresh seconds (default: 2)
```

| Option | Default | Description |
|---|---|---|
| `@agents-position` | `right` | Where to auto-place the list: `right` / `center` / `left` (centered keeps window list + clock) |
| `@agents-auto` | `on` | Auto-mount when no `#{agents}` placeholder is set (`off` = placeholder only) |
| `@agents-auto-hooks` | `off` | Install Claude Code hooks on plugin load (idempotent) |
| `@agents-interval` | `2` | Status refresh interval (drives the spinner / elapsed time) |
| `@agents-key` | `a` | `prefix + <key>` → picker |
| `@agents-next-key` / `@agents-prev-key` | `Tab` / `BTab` | Cycle agents |
| `@agents-attention-key` | `Enter` | Jump to a `needs-you` agent |
| `@agents-goto-key` | `g` | `prefix + <key>` then a digit → agent N |

Detection is tunable via the `AGENT_PATTERN`, `AGENT_WORKING_RE`, and `AGENT_BLOCKED_RE` environment variables — see [docs/USAGE.md](docs/USAGE.md).

## How it works

**Presence** comes from `tmux list-panes` + `ps`; **state** is read from a per-pane store that agents write via hooks (falling back to scraping the bottom of the pane). `bar.sh` renders it into a clickable status segment. Full write-up in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Uninstall

```sh
~/.tmux/plugins/tmux-agents/scripts/uninstall.sh
```

Removes the hooks, cache, runtime bindings, and the `.tmux.conf` block. If you installed manually (TPM `@plugin` or your own `run-shell` / `#{agents}`), remove those lines too.

## License

[MIT](LICENSE)
