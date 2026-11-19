#!/bin/sh
# Jev の無効（BIGDADDY_JEV 未設定）で外に出ないことと、決定モードの hook とスクリプトと、route-model.sh のモデルと effort の組（haiku high・sonnet high・opus medium の 3 つだけ、novel なし）と、--session がプレイブックで主を分けることを実物で確かめる。無効の検査は鍵なしで回る（呼ばれたら失敗する偽の curl を PATH の先頭に置く）。Jev を実際に呼ぶ検査は、呼び出し側が BIGDADDY_JEV=1 を付けたときだけ走り、付けなければ鍵の有無にかかわらず skip する。BIGDADDY_JEV=1 なのに鍵が無ければ jev.sh が exit 2 を返すので、その検査は失敗として扱う（明示したのに設定が足りない状態）。
# 使い方: sh tests/decision-audit/run.sh（Jev を実際に呼ぶ検査も回すときは BIGDADDY_JEV=1 sh tests/decision-audit/run.sh）
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
fx="$root/tests/decision-audit/fixtures"
hooks="$root/plugins/bigdaddy/hooks"
scripts="$root/plugins/bigdaddy/skills/jev-gates/scripts"
usage="$root/plugins/bigdaddy/skills/usage-report/scripts"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failed=1; }

bash_input() { jq -n --arg c "$1" '{hook_event_name: "PostToolUse", tool_name: "Bash", tool_input: {command: $c}}'; }
stop_input() { jq -n --arg t "$1" --argjson a "$2" '{hook_event_name: "Stop", session_id: "test", transcript_path: $t, stop_hook_active: $a}'; }

live=0
if [ "${BIGDADDY_JEV:-}" = 1 ]; then live=1; fi
skip_live() { echo "SKIP $1 (BIGDADDY_JEV=1 を付けて実行すると Jev を実際に呼ぶ)"; }

# 無効（BIGDADDY_JEV 未設定・0・空）: 外に出ない。呼ばれたら失敗する偽の curl と、鍵を返す偽の security を PATH の先頭に置き、鍵が環境にあっても出ないことを確かめる。
mkdir -p "$tmp/off"
printf '#!/bin/sh\necho called >> "%s/curl-called"\nexit 1\n' "$tmp" > "$tmp/off/curl"
printf '#!/bin/sh\necho dummy-key\n' > "$tmp/off/security"
chmod +x "$tmp/off/curl" "$tmp/off/security"
printf '{"state": "x", "questions": {"q": {"type": "noul", "instructions": "x"}}}' > "$tmp/req.json"
printf '{"symptom": "s", "steps": [{"answer": "a", "evidence": "e"}]}' > "$tmp/naze.json"
printf '{"decision": "d", "conclusion": "c", "premises": {"confirmed": [], "unconfirmed": []}, "rejected": [], "overturn_if": []}' > "$tmp/decision.json"
want_err_for() { printf '%s: Jev は無効（BIGDADDY_JEV=1 で有効）' "$1"; }
for mode in unset 0 empty; do
  case $mode in
    unset) off() { env -u BIGDADDY_JEV PATH="$tmp/off:$PATH" TYPESAFE_API_KEY=dummy "$@"; } ;;
    0) off() { env BIGDADDY_JEV=0 PATH="$tmp/off:$PATH" TYPESAFE_API_KEY=dummy "$@"; } ;;
    empty) off() { env BIGDADDY_JEV= PATH="$tmp/off:$PATH" TYPESAFE_API_KEY=dummy "$@"; } ;;
  esac
  rm -f "$tmp/curl-called"
  for spec in "jev.sh|$tmp/req.json" "route-playbook.sh|x" "check-naze.sh|$tmp/naze.json" "audit-decision.sh|$tmp/decision.json" "route-model.sh|x"; do
    name=${spec%%|*}; arg=${spec#*|}
    out=$(off sh "$scripts/$name" "$arg" 2>"$tmp/err"); code=$?
    if [ "$code" = 3 ] && [ -z "$out" ] && [ "$(cat "$tmp/err")" = "$(want_err_for "$name")" ]; then pass "disabled ($mode): $name exits 3 with one stderr line and empty stdout"; else fail "disabled ($mode): $name (exit $code, stdout: $out, stderr: $(cat "$tmp/err"))"; fi
  done
  out=$(off sh "$scripts/route-model.sh" --session feature); code=$?
  if [ "$code" = 0 ] && printf '%s' "$out" | jq -e '.model == "sonnet" and .layer == "organize"' >/dev/null 2>&1; then pass "disabled ($mode): route-model --session still works"; else fail "disabled ($mode): route-model --session (exit $code, got: $out)"; fi
  out=$(off sh "$scripts/route-playbook.sh" --criteria 2>/dev/null); code=$?
  if [ "$code" = 0 ] && printf '%s' "$out" | jq -e 'has("none")' >/dev/null 2>&1; then pass "disabled ($mode): route-playbook --criteria still works"; else echo "SKIP disabled ($mode): route-playbook --criteria (pstack の SKILL.md が見つからない: exit $code)"; fi
  out=$(bash_input "sh $scripts/jev.sh /tmp/req.json" | off "$hooks/decision-audit-nudge.sh"); code=$?
  if [ "$code" = 0 ] && [ -z "$out" ]; then pass "disabled ($mode): nudge silent"; else fail "disabled ($mode): nudge silent (exit $code, got: $out)"; fi
  out=$(stop_input "$fx/transcript-a-unaudited.jsonl" false | off "$hooks/decision-audit-stop.sh" 2>&1); code=$?
  if [ "$code" = 0 ] && [ -z "$out" ]; then pass "disabled ($mode): stop hook silent"; else fail "disabled ($mode): stop hook silent (exit $code, got: $out)"; fi
  if [ ! -e "$tmp/curl-called" ]; then pass "disabled ($mode): curl was never called"; else fail "disabled ($mode): curl was called"; fi
done

# Stop hook は無効なら会話ログも読まない（存在しないパスでも何も出さず exit 0）。
out=$(stop_input "$tmp/no-such-transcript.jsonl" false | env -u BIGDADDY_JEV "$hooks/decision-audit-stop.sh" 2>&1); code=$?
[ "$code" = 0 ] && [ -z "$out" ] && pass "disabled: stop hook silent without a transcript" || fail "disabled: stop hook silent without a transcript (exit $code, got: $out)"

# ここから先は BIGDADDY_JEV=1 で有効にして実行する。
export BIGDADDY_JEV=1

for c in \
  "sh $scripts/jev.sh /tmp/req.json" \
  "$scripts/route-playbook.sh \"ログの保存先を決めて\"" \
  "sh /Users/someone/works/bigdaddy/plugins/bigdaddy/skills/jev-gates/scripts/check-naze.sh /tmp/naze.json | jq ."; do
  out=$(bash_input "$c" | "$hooks/decision-audit-nudge.sh")
  if printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse" and (.hookSpecificOutput.additionalContext | length > 0)' >/dev/null 2>&1; then
    pass "nudge fires: $c"
  else
    fail "nudge fires: $c (got: $out)"
  fi
done

for c in "ls" "git status" "sh $scripts/audit-decision.sh /tmp/decision.json" "$scripts/route-model.sh \"rg で一覧して\"" "$scripts/route-playbook.sh --criteria" "PSTACK_POTETO_SKILL=/tmp/SKILL.md sh $scripts/route-playbook.sh --criteria | jq keys"; do
  out=$(bash_input "$c" | "$hooks/decision-audit-nudge.sh"); code=$?
  if [ "$code" = 0 ] && [ -z "$out" ]; then pass "nudge silent: $c"; else fail "nudge silent: $c (exit $code, got: $out)"; fi
done

if [ "$live" = 1 ]; then
out=$(stop_input "$fx/transcript-a-unaudited.jsonl" false | "$hooks/decision-audit-stop.sh"); code=$?
if [ "$code" = 0 ] && printf '%s' "$out" | jq -e '.decision == "block" and (.reason | contains("bigdaddy decision-audit"))' >/dev/null 2>&1; then
  pass "stop (a) unaudited decision blocks: $(printf '%s' "$out" | jq -r '.reason' | grep -o 'has_decision=[0-9.]*, audited=[0-9.]*')"
else
  fail "stop (a) unaudited decision blocks (exit $code, got: $out)"
fi

for f in transcript-b-audited transcript-c-no-decision; do
  out=$(stop_input "$fx/$f.jsonl" false | "$hooks/decision-audit-stop.sh"); code=$?
  if [ "$code" = 0 ] && [ -z "$out" ]; then pass "stop $f silent"; else fail "stop $f silent (exit $code, got: $out)"; fi
done
else
  skip_live "stop hook (a)(b)(c)"
fi

out=$(stop_input "$fx/transcript-a-unaudited.jsonl" true | "$hooks/decision-audit-stop.sh"); code=$?
if [ "$code" = 0 ] && [ -z "$out" ]; then pass "stop (a) with stop_hook_active silent"; else fail "stop (a) with stop_hook_active silent (exit $code, got: $out)"; fi

mkdir -p "$tmp/stub"
printf '#!/bin/sh\nexit 1\n' > "$tmp/stub/security"
chmod +x "$tmp/stub/security"
out=$(stop_input "$fx/transcript-a-unaudited.jsonl" false | env -u TYPESAFE_API_KEY -u TYPESAFE_API_TOKEN PATH="$tmp/stub:$PATH" "$hooks/decision-audit-stop.sh" 2>&1); code=$?
if [ "$code" = 0 ] && [ -z "$out" ]; then pass "stop (a) without Jev key silent"; else fail "stop (a) without Jev key silent (exit $code, got: $out)"; fi

if [ "$live" = 1 ]; then
for f in prod naming tests-passed; do
  out=$("$scripts/audit-decision.sh" "$fx/decision-$f.json"); code=$?
  echo "  audit-decision $f: $(printf '%s' "$out" | jq -c .)"
  if [ "$code" = 0 ] && printf '%s' "$out" | jq -e '([.important, .unconfirmed_as_fact, .missing_alternatives] | all(type == "number")) and (.record | type == "boolean") and (.flags | type == "array")' >/dev/null 2>&1; then
    pass "audit-decision $f output shape"
  else
    fail "audit-decision $f output shape (exit $code)"
  fi
  printf '%s' "$out" | jq '.important' > "$tmp/important-$f"
  printf '%s' "$out" | jq -c '.flags' > "$tmp/flags-$f"
done
if [ "$(cat "$tmp/flags-naming")" = "[]" ]; then pass "audit-decision naming has no flags"; else fail "audit-decision naming has no flags (got $(cat "$tmp/flags-naming"))"; fi
if [ "$(jq -n --slurpfile p "$tmp/important-prod" --slurpfile n "$tmp/important-naming" '$p[0] > $n[0]')" = true ]; then
  pass "audit-decision important(prod)=$(cat "$tmp/important-prod") > important(naming)=$(cat "$tmp/important-naming")"
else
  fail "audit-decision important(prod)=$(cat "$tmp/important-prod") > important(naming)=$(cat "$tmp/important-naming")"
fi
else
  skip_live "audit-decision"
fi

route_model_bump_ok() {
  printf '%s' "$1" | jq -e '
    ["collect","organize","decide"] as $l
    | (.top3 | to_entries | max_by(.value).key) as $top
    | if .bumped then .layer == $l[([($l | index($top)) + 1, 2] | min)] else .layer == $top end' >/dev/null 2>&1
}

route_model_shape_ok() {
  printf '%s' "$1" | jq -e '([.model, .effort] | IN(["haiku","high"],["sonnet","high"],["opus","medium"])) and (.layer | IN("collect","organize","decide")) and (has("novel") | not) and (.bumped | type == "boolean")' >/dev/null 2>&1
}

route_model_pair_ok() {
  printf '%s' "$1" | jq -e '{collect: "haiku", organize: "sonnet", decide: "opus"}[.layer] == .model' >/dev/null 2>&1
}

if [ "$live" = 1 ]; then
out=$("$scripts/route-model.sh" "plugins/ 配下で route-playbook を参照しているファイルを rg で全部挙げて"); code=$?
echo "  route-model collect: $(printf '%s' "$out" | jq -c .)"
if [ "$code" = 0 ] && route_model_shape_ok "$out" && printf '%s' "$out" | jq -e '(.confidence | type == "number") and (.top3 | type == "object")' >/dev/null 2>&1; then pass "route-model output shape"; else fail "route-model output shape (exit $code, got: $out)"; fi
if printf '%s' "$out" | jq -e '.layer == "collect" and .model == "haiku"' >/dev/null 2>&1; then pass "route-model file listing is collect/haiku"; else fail "route-model file listing is collect/haiku (got: $out)"; fi
if route_model_bump_ok "$out"; then pass "route-model collect bump matches top3"; else fail "route-model collect bump matches top3 (got: $out)"; fi
if route_model_shape_ok "$out" && route_model_pair_ok "$out"; then pass "route-model collect model matches layer"; else fail "route-model collect model matches layer (got: $out)"; fi

out=$("$scripts/route-model.sh" "次の設計どおりに関数を実装する: 型 X、シグネチャ Y、テストは Z。設計は決定済みで、変えない"); code=$?
echo "  route-model organize: $(printf '%s' "$out" | jq -c .)"
if [ "$code" = 0 ] && printf '%s' "$out" | jq -e '.layer == "organize"' >/dev/null 2>&1; then pass "route-model implement-to-spec is organize"; else fail "route-model implement-to-spec is organize (exit $code, got: $out)"; fi
if route_model_bump_ok "$out"; then pass "route-model organize bump matches top3"; else fail "route-model organize bump matches top3 (got: $out)"; fi
if route_model_shape_ok "$out" && route_model_pair_ok "$out"; then pass "route-model organize model matches layer"; else fail "route-model organize model matches layer (got: $out)"; fi

out=$("$scripts/route-model.sh" "3 つのキャッシュ戦略のどれを採るか、計測結果を比べて決めて"); code=$?
echo "  route-model decide: $(printf '%s' "$out" | jq -c .)"
if [ "$code" = 0 ] && printf '%s' "$out" | jq -e '.layer == "decide" and .model == "opus"' >/dev/null 2>&1; then pass "route-model choosing a strategy is decide/opus"; else fail "route-model choosing a strategy is decide/opus (exit $code, got: $out)"; fi
if route_model_bump_ok "$out"; then pass "route-model decide bump matches top3"; else fail "route-model decide bump matches top3 (got: $out)"; fi
if route_model_shape_ok "$out" && route_model_pair_ok "$out"; then pass "route-model decide model matches layer"; else fail "route-model decide model matches layer (got: $out)"; fi
else
  skip_live "route-model (Jev)"
fi

# 主のモデルはプレイブックで決まる。feature・refactoring だけ sonnet、省略や知らない名前は opus に倒す。
for case in "feature sonnet high organize" "refactoring sonnet high organize" "bug-fix opus medium decide" "perf-issue opus medium decide" "investigation opus medium decide" "- opus medium decide"; do
  set -- $case
  if [ "$1" = - ]; then out=$("$scripts/route-model.sh" --session); else out=$("$scripts/route-model.sh" --session "$1"); fi; code=$?
  if [ "$code" = 0 ] && route_model_shape_ok "$out" && printf '%s' "$out" | jq -e --arg m "$2" --arg e "$3" --arg l "$4" '.model == $m and .effort == $e and .layer == $l and .bumped == false and .confidence == null and .top3 == null' >/dev/null 2>&1; then pass "route-model session $1 is $2/$3/$4"; else fail "route-model session $1 is $2/$3/$4 (exit $code, got: $out)"; fi
done

out=$("$usage/extract-events.sh" "$fx/transcript-usage.jsonl")
if printf '%s\n' "$out" | awk -F'\t' '$5 == "jev" && $6 == "audit-decision" { found = 1 } END { exit !found }'; then
  pass "extract-events counts audit-decision.sh as jev"
else
  fail "extract-events counts audit-decision.sh as jev (got: $out)"
fi
if printf '%s\n' "$out" | awk -F'\t' '$5 == "jev" && $6 == "route-model" { found = 1 } END { exit !found }'; then
  pass "extract-events counts route-model.sh as jev"
else
  fail "extract-events counts route-model.sh as jev (got: $out)"
fi

out=$(CLAUDE_CONFIG_DIR="$fx/usage-tokens" "$usage/usage-report.sh" --since 2026-10-01 --until 2026-10-04 --json); code=$?
models=$(printf '%s' "$out" | jq -c '[.models[] | [.model, .who, .agent_type, .turns, .input, .cache_read, .cache_write, .output]]' 2>/dev/null)
want='[["claude-opus-4-7","main","main",2,30,4000,200,667],["claude-opus-4-7","sub","pstack:poteto-agent",1,7,700,70,7],["claude-sonnet-4-6","main","main",1,5,500,50,40],["claude-haiku-4-5","sub","unknown",1,1,100,10,2]]'
if [ "$code" = 0 ] && [ "$models" = "$want" ]; then
  pass "usage-report models dedupe by message id, drop <synthetic>, apply --since/--until"
else
  fail "usage-report models dedupe by message id, drop <synthetic>, apply --since/--until (exit $code, got: $models)"
fi
total=$(printf '%s' "$out" | jq -c '.models_total' 2>/dev/null)
if [ "$total" = '{"turns":5,"input":43,"cache_read":5300,"cache_write":330,"output":716}' ]; then
  pass "usage-report models_total"
else
  fail "usage-report models_total (got: $total)"
fi
if printf '%s' "$out" | jq -e '[.models[].share] as $s | ["turns", "input", "cache_read", "cache_write", "output"] | all(. as $k | ($s | map(.[$k]) | add) - 1 | fabs < 0.001)' >/dev/null 2>&1; then
  pass "usage-report model shares sum to 1"
else
  fail "usage-report model shares sum to 1 (got: $(printf '%s' "$out" | jq -c '[.models[].share]'))"
fi

for mode in on off; do
  if [ "$mode" = on ]; then out=$(BIGDADDY_JEV=1 "$hooks/session-start.sh" </dev/null); code=$?; line='Jev は有効（`BIGDADDY_JEV=1`）'; else out=$(env -u BIGDADDY_JEV "$hooks/session-start.sh" </dev/null); code=$?; line='Jev は無効。jev-gates のスクリプトは exit 3 を返す'; fi
  if [ "$code" = 0 ] && printf '%s' "$out" | jq -e --rawfile want "$hooks/session-start-context.md" --arg line "$line" '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | startswith($want) and contains($line))' >/dev/null 2>&1; then
    pass "session-start.sh prints the context as SessionStart additionalContext JSON with the Jev line ($mode)"
  else
    fail "session-start.sh prints the context as SessionStart additionalContext JSON with the Jev line ($mode) (exit $code, got: $out)"
  fi
done

if jq empty "$hooks/hooks.json"; then pass "hooks.json is valid JSON"; else fail "hooks.json is valid JSON"; fi

exit "$failed"
