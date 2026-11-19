#!/bin/sh
# SessionStart hook。session-start-context.md を additionalContext の JSON で出す。Cursor は JSON 以外の stdout を捨てるので、Claude Code と Cursor の両方で届く形にする。
# jq が無いときは本文をそのまま出す（Claude Code は通常の stdout を文脈に入れる）。常に exit 0 する。
set -u

file="$(dirname "$0")/session-start-context.md"
[ -r "$file" ] || exit 0

if [ "${BIGDADDY_JEV:-}" = 1 ]; then
  jev_line='- Jev は有効（`BIGDADDY_JEV=1`）。'
else
  jev_line='- Jev は無効。jev-gates のスクリプトは exit 3 を返すので、各 skill の Jev なしの手順で進める。'
fi

if command -v jq >/dev/null 2>&1; then
  { cat "$file"; printf '%s\n' "$jev_line"; } | jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}' 2>/dev/null && exit 0
fi
cat "$file" 2>/dev/null
printf '%s\n' "$jev_line"
exit 0
