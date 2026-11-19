#!/bin/sh
# usage-report の集計を fixture の jsonl で確かめる。実ログは読まない。
# 使い方: sh tests/usage-report/run.sh
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
scripts="$root/plugins/bigdaddy/skills/usage-report/scripts"
fixtures="$(cd "$(dirname "$0")" && pwd)/fixtures"
failed=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failed=1; }

events=$("$scripts/extract-events.sh" "$fixtures/projects/-proj/s1.jsonl")
report=$(CLAUDE_CONFIG_DIR="$fixtures" "$scripts/usage-report.sh" --json)

has_event() { printf '%s\n' "$events" | awk -F'\t' -v k="$1" -v n="$2" '$5 == k && $6 == n { f = 1 } END { exit !f }'; }
count_kind() { printf '%s\n' "$events" | awk -F'\t' -v k="$1" '$5 == k { c++ } END { print c + 0 }'; }

expect_event() { if has_event "$2" "$3"; then pass "$1"; else fail "$1"; fi; }
expect_no_event() { if has_event "$2" "$3"; then fail "$1"; else pass "$1"; fi; }
expect_count() { n=$(count_kind "$2"); if [ "$n" = "$3" ]; then pass "$1"; else fail "$1 (got $n, want $3)"; fi; }

expect_event "Read のプレイブックは playbook のまま" playbook refactoring
expect_event "Bash の cat で cache のプレイブックを読むと数える" playbook-bash feature
expect_event "変数経由の cat も数える" playbook-bash bug-fix
expect_event "for ループの sed で読んだ原則を数える (1)" skill-read-bash principle-model-the-domain
expect_event "for ループの sed で読んだ原則を数える (2)" skill-read-bash principle-boundary-discipline
expect_event "cache の SKILL.md の直接指定も数える" skill-read-bash jev-gates
expect_no_event "cache の外のプレイブックは数えない" playbook-bash prototype
expect_no_event "ls は読み取りでないので数えない" playbook-bash poteto-mode
expect_event "cd && cat の形でも数える" playbook-bash babysit
expect_no_event "コミット本文に cache と cat の語があっても数えない" playbook-bash shipping
expect_no_event "ls の出力を head に渡すだけでは数えない" playbook-bash ls-only
expect_event "パイプの後の head でも数える" skill-read-bash pipe-skill
expect_event "|| の後の cat でも数える" skill-read-bash or-skill
expect_event "cache に cd してから SKILL.md を cat しても数える" skill-read-bash cd-skill
expect_no_event "grep で触れただけの playbook は数えない" playbook-bash perf-issue
expect_event "cache のパスと並んだ読み込みは数える" playbook-bash investigation
expect_no_event "同じ cat のリポジトリ側のパスは数えない" playbook-bash other
expect_no_event "読み込みと関係ない for ループの語は数えない" skill-read-bash alpha
expect_event "同じ名前の playbook と skill は別の行になる (playbook)" playbook-bash eval
expect_event "同じ名前の playbook と skill は別の行になる (skill)" skill-read-bash eval
expect_event "cd の次の行の cat でも skill 名を取れる" skill-read-bash nl-skill
expect_event "ループ変数を含むパスでも一覧の名前を取れる" skill-read-bash loop-skill
if printf '%s\n' "$events" | awk -F'\t' '$5 == "skill-read-bash" && $6 !~ /^[a-z][a-z0-9-]*$/ { bad = 1 } END { exit !bad }'; then fail "skill-read-bash の名前に変数や改行が混ざる"; else pass "skill-read-bash の名前は小文字とハイフンだけ"; fi
expect_no_event "rg は読み取りでないので数えない" playbook-bash hillclimb
expect_count "playbook-bash は feature・bug-fix・babysit・investigation・eval の 5 件" playbook-bash 5
expect_count "skill-read-bash は 10 件（同じ名前は 1 件）" skill-read-bash 10
expect_event "公式版の pstack は SKILL.md を Read で読む。起動として数える" skill-read poteto-mode
expect_count "Read の skill-read は 2 件（原則 1 件と poteto-mode 1 件）" skill-read 2

ids=$(printf '%s\n' "$events" | cut -f1)
if [ "$(printf '%s\n' "$ids" | sort | uniq -d | wc -l | tr -d ' ')" = 0 ]; then pass "event_id は重複しない"; else fail "event_id が重複する"; fi
if printf '%s\n' "$events" | awk -F'\t' 'NF != 6 { bad = 1 } END { exit bad }'; then pass "TSV は 6 列のまま"; else fail "TSV の列数が変わった"; fi

rep() { printf '%s' "$report" | jq -r "$1"; }
[ "$(rep '.playbooks | map(select(.name == "feature")) | .[0].bash')" = 1 ] && pass "表示: feature の Bash 件数" || fail "表示: feature の Bash 件数"
[ "$(rep '.playbooks | map(select(.name == "refactoring")) | .[0] | "\(.read)/\(.bash)"')" = "1/0" ] && pass "表示: refactoring は Read 1 / Bash 0" || fail "表示: refactoring の内訳"
[ "$(rep '.principles | map(select(.name == "principle-model-the-domain")) | .[0].bash')" = 1 ] && pass "表示: 原則の Bash 件数" || fail "表示: 原則の Bash 件数"
[ "$(rep '.skill_files_read | map(select(.name == "jev-gates")) | .[0].bash')" = 1 ] && pass "表示: skill_files_read の Bash 件数" || fail "表示: skill_files_read の Bash 件数"
[ "$(rep '.principles | map(select(.name == "principle-prove-it-works")) | .[0] | "\(.read)/\(.bash)"')" = "1/0" ] && pass "表示: Read だけの原則は Bash 0" || fail "表示: Read だけの原則"
[ "$(rep '.skill_files_read | map(select(.name == "poteto-mode")) | .[0] | "\(.read)/\(.skill)"')" = "1/0" ] && pass "表示: poteto-mode の Read は skill_files_read に出る" || fail "表示: poteto-mode の Read"
text=$(CLAUDE_CONFIG_DIR="$fixtures" "$scripts/usage-report.sh")
printf '%s\n' "$text" | grep -q 'Bash' && pass "テキスト表示に Bash が出る" || fail "テキスト表示に Bash が出ない"

[ "$failed" = 0 ] && echo "all passed" || { echo "failed"; exit 1; }
