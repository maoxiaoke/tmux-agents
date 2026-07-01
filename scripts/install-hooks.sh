#!/usr/bin/env bash
# 把 tmux-agents 的 Claude Code hooks 安全地装进 ~/.claude/settings.json。
# 幂等（重复运行=升级，不会重复）、可卸载、写前自动备份、保留他人 hook（如 herdr）。
#
# 用法：
#   scripts/install-hooks.sh            安装/升级
#   scripts/install-hooks.sh uninstall  卸载（只移除本插件的条目）
# 覆盖 settings 路径：CLAUDE_SETTINGS=/path scripts/install-hooks.sh
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$DIR/claude-hook.sh"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
ACTION="${1:-install}"

command -v python3 >/dev/null 2>&1 || { echo "需要 python3" >&2; exit 1; }

HOOK="$HOOK" SETTINGS="$SETTINGS" ACTION="$ACTION" python3 - <<'PY'
import json, os, sys, time, shutil

hook   = os.environ["HOOK"]
path   = os.environ["SETTINGS"]
action = os.environ["ACTION"]

# 我们管理的事件 → [(matcher 或 None, 传给 claude-hook.sh 的状态)]
SPEC = {
    "UserPromptSubmit": [(None, "working")],
    "PreToolUse":       [("AskUserQuestion|ExitPlanMode", "needs-you")],
    "PostToolUse":      [(None, "working")],
    "Notification":     [("permission_prompt|elicitation_dialog", "needs-you"),
                         ("elicitation_complete|elicitation_response", "working")],
    "Stop":             [(None, "idle")],
    "StopFailure":      [(None, "idle")],
}

try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except Exception as e:
    print(f"settings.json 解析失败，未改动：{e}", file=sys.stderr); sys.exit(1)

hooks = data.get("hooks", {}) or {}

def is_ours(entry):
    return any(hook in (h.get("command") or "") for h in entry.get("hooks", []))

# 先清掉所有指向本插件的旧条目（幂等；也用于卸载）。他人的 hook 原样保留。
for ev in list(hooks):
    hooks[ev] = [e for e in hooks[ev] if not is_ours(e)]
    if not hooks[ev]:
        del hooks[ev]

if action == "install":
    for ev, entries in SPEC.items():
        arr = hooks.setdefault(ev, [])
        for matcher, arg in entries:
            entry = {"hooks": [{"type": "command", "command": f"{hook} {arg}"}]}
            if matcher:
                entry["matcher"] = matcher
            arr.append(entry)

if hooks:
    data["hooks"] = hooks
elif "hooks" in data:
    del data["hooks"]

if os.path.exists(path):
    bak = path + ".bak-" + time.strftime("%Y%m%d-%H%M%S")
    shutil.copy2(path, bak)
    print(f"已备份 → {bak}")
os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(("✅ 已安装" if action == "install" else "🗑  已卸载") + f" tmux-agents hooks → {path}")
if action == "install":
    print("提示：hooks 在【新开的】claude 会话才生效；已在跑的会话走截屏兜底。")
PY
