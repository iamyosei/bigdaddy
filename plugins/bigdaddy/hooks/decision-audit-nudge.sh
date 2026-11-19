#!/bin/sh
# PostToolUse hook（Bash）。Jev の判断スクリプトを実行した直後に、その結果を決定モードで確かめるよう agent に促す。
# Jev は呼ばない。異常時や対象外のコマンドでは何も出さずに exit 0 する。
set -u

# Jev は BIGDADDY_JEV=1 のときだけ使う。無効なら促さない。
[ "${BIGDADDY_JEV:-}" = 1 ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0
input=$(cat) || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0

# audit-decision.sh 自体は決定モードの実行なので、ここでは拾わない。route-playbook.sh --criteria は選択肢を出すだけで Jev を呼ばないので、これも拾わない
cmd=$(printf '%s' "$cmd" | sed -E 's/route-playbook\.sh[[:space:]]+--criteria//g')
printf '%s' "$cmd" | grep -Eq '(^|[^A-Za-z0-9_-])(jev|route-playbook|check-naze)\.sh' || exit 0

text='いま使った Jev の結果は決定モードの対象になる判断。行動に移す前に、決定モードの記録（結論、確認済みと未確認に分けた前提、退けた代案、覆る条件）を書き、audit-decision.sh を 1 回実行する。important が高ければ PR 本文の「判断の記録」に残し、低ければ書き方（「〜だ」か「〜の可能性が高い」か）にだけ反映し、flags に出た項目だけを logic-audit の通常手順に上げる（skill bigdaddy:logic-audit の決定モード）。'

jq -n --arg t "$text" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $t}}' 2>/dev/null || exit 0
exit 0
