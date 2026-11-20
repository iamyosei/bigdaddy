#!/bin/sh
# briefing の references/topic.md にある状態の JSON と手順の番号と、手順の参照が、壊れていないことを確かめる。Jev は呼ばない。
# 使い方: sh tests/briefing-state/run.sh
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
skill="$root/plugins/bigdaddy/skills/briefing/SKILL.md"
brief="$root/plugins/bigdaddy/skills/briefing/references/brief-template.md"
topic="$root/plugins/bigdaddy/skills/briefing/references/topic.md"
failed=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failed=1; }

block=$(awk '/^     ```json$/{f=1;next} /^     ```$/{if(f){exit}} f{sub(/^     /,"");print}' "$topic")
if printf '%s' "$block" | jq -e . >/dev/null 2>&1; then pass "state JSON in topic.md parses"; else fail "state JSON in topic.md parses"; fi

for k in id depends state session pr qa card started_at reason; do
  if printf '%s' "$block" | jq -e --arg k "$k" '.briefs[0] | has($k)' >/dev/null 2>&1; then pass "briefs[0] has $k"; else fail "briefs[0] has $k"; fi
done
if printf '%s' "$block" | jq -e 'has("topic") and has("qa") and has("reason") and has("design")' >/dev/null 2>&1; then pass "state JSON has topic, design, qa and reason"; else fail "state JSON has topic, design, qa and reason"; fi

for st in 未着手 実行中 "PR あり" マージ済み 要確認; do
  if grep -q "^     | .*$st" "$topic"; then pass "transition table mentions $st"; else fail "transition table mentions $st"; fi
done

nums=$(grep -E '^ {1,2}[0-9]{1,2}\. ' "$topic" | sed -E 's/^ *([0-9]+)\..*/\1/' | awk 'NR>=1' | tr '\n' ' ')
case "$nums" in
  *"1 2 3 4 5 6 7 8 9 10 "*) pass "steps 1 to 10 are consecutive" ;;
  *) fail "steps 1 to 10 are consecutive (got: $nums)" ;;
esac

bad=""
for n in $(grep -oE '手順 [0-9]+' "$skill" "$brief" "$topic" | sed -E 's/.*手順 //' | sort -u); do
  [ "$n" -le 10 ] || bad="$bad $n"
done
if [ -z "$bad" ]; then pass "step references are within 1 to 10"; else fail "step references are within 1 to 10 (got:$bad)"; fi

if grep -q -F '`references/topic.md` を Read ツールで読んで従う' "$skill"; then pass "SKILL.md points to references/topic.md"; else fail "SKILL.md points to references/topic.md"; fi
if grep -q '^## 親に返すもの$' "$skill"; then pass "SKILL.md has the parent-return section"; else fail "SKILL.md has the parent-return section"; fi
for h in '### 設計' '### 親に返すもの'; do
  if grep -q "^$h\$" "$brief"; then pass "brief-template has $h"; else fail "brief-template has $h"; fi
done

if grep -q '^name: briefing$' "$skill"; then pass "SKILL.md name is briefing"; else fail "SKILL.md name is briefing"; fi
if grep -q '^## 指示書（briefing から）$' "$brief"; then pass "brief-template heading is briefing"; else fail "brief-template heading is briefing"; fi

leftover=$(git -C "$root" grep -n -i yosei -- . ':!tests/briefing-state/run.sh' \
  | grep -v -F -e 'iamyosei/bigdaddy' -e '"name": "Yosei Ito"' -e 'Copyright (c) 2026 Yosei Ito' -e '"url": "https://github.com/iamyosei"')
if [ -z "$leftover" ]; then pass "no personal name outside the author credit and the repo path"; else fail "no personal name outside the author credit and the repo path (got: $leftover)"; fi
if git -C "$root" grep -q -F 'yosei-mode' -- . ':!tests/briefing-state/run.sh'; then fail "no yosei-mode reference remains"; else pass "no yosei-mode reference remains"; fi

old="yst""ack"
if git -C "$root" grep -q -i -F "$old" -- .; then fail "no old name remains"; else pass "no old name remains"; fi

exit "$failed"
