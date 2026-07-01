#!/usr/bin/env bash
# 跳转到指定 pane。$1 = pane_id 的纯数字部分（不含 %）。
n="$1"
[ -z "$n" ] && exit 0
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/focus.sh" "%$n"
