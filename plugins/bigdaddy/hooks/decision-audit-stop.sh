#!/bin/sh
# Stop hook。このターンに決定モードの対象になる判断があるのに決定モードで確かめていなければ、止まる前に確かめるよう頼む。
# 判断の有無と確かめたかどうかは、このターンの agent の本文を Jev に 1 回見せて決める。
# 異常時（jq やログが無い、Jev のキーが無い、Jev が失敗した）は何も出さずに exit 0 する（セッションを止めない）。
set -u

# 外部送信は BIGDADDY_JEV=1 のときだけ。無効なら会話ログも読まず何も出さない。
[ "${BIGDADDY_JEV:-}" = 1 ] || exit 0

DECISION_MIN=0.5
AUDITED_MIN=0.5
MAX_CHARS=12000

questions=$(cat <<'EOF'
{
  "has_decision": {"type": "noul",
    "instructions": "Does this turn's assistant output contain one of these decisions, stated as a choice the assistant made: choosing which playbook or workflow to follow; splitting work into separate briefs versus bundling it into one; whether to dig deeper in a why-why (root cause) analysis or stop; whether to fix a review comment, not fix it, or dismiss it as a false positive; choosing between approaches or designs; judging that work is complete? Ordinary explanations, status reports, or answers that contain no such choice are no."},
  "audited": {"type": "noul",
    "instructions": "Does the assistant output include a written decision record with labeled parts: the conclusion (結論), premises marked as confirmed or unconfirmed (前提 確認済み / 未確認), rejected alternatives (退けた代案), and conditions that would overturn the decision (覆る条件)? A line of the form [ran: ... audit-decision.sh ...] also counts as yes. Comparing options in ordinary prose without such a labeled record is no. If the output contains no decision, answer yes."}
}
EOF
)

command -v jq >/dev/null 2>&1 || exit 0
here=$(cd "$(dirname "$0")" && pwd) || exit 0
jev="$here/../skills/jev-gates/scripts/jev.sh"
[ -f "$jev" ] || exit 0

input=$(cat) || exit 0
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // ""' 2>/dev/null) || exit 0
stop_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null) || exit 0
[ "$stop_active" = true ] && exit 0
[ -f "$transcript" ] || exit 0

# このターン = 最後の本物のユーザー入力より後。tool_result だけの user 行や isMeta の行は入力ではない
state=$(jq -rs --argjson max "$MAX_CHARS" '
  def prompt: .type == "user" and (.isMeta != true)
    and (.message.content | (type == "string") or (type == "array" and any(.[]; .type == "text")));
  ([to_entries[] | select(.value | prompt) | .key] | last // -1) as $start
  | [ .[$start + 1:][] | select(.type == "assistant") | .message.content[]?
      | if .type == "text" then .text
        elif .type == "tool_use" and .name == "Bash" and ((.input.command // "") | contains("audit-decision.sh"))
          then "[ran: \(.input.command)]"
        else empty end ]
  | join("\n")
  | .[-$max:]
' "$transcript" 2>/dev/null) || exit 0
[ -n "$state" ] || exit 0

scores=$(jq -n --arg s "$state" --argjson q "$questions" '{state: $s, questions: $q}' \
  | sh "$jev" 2>/dev/null \
  | jq -c '{d: (.has_decision.noul * 100 | round / 100), a: (.audited.noul * 100 | round / 100)}' 2>/dev/null) || exit 0
[ -n "$scores" ] || exit 0

jq -c --argjson dmin "$DECISION_MIN" --argjson amin "$AUDITED_MIN" '
  select(.d >= $dmin and .a < $amin)
  | {decision: "block",
     reason: "bigdaddy decision-audit: このターンに決定モードの対象になる判断があるが、決定モードで確かめた跡が無い（has_decision=\(.d), audited=\(.a)）。skill bigdaddy:logic-audit の決定モードで確かめる。結論、確認済みと未確認に分けた前提、退けた代案、覆る条件の 4 項目を書き、audit-decision.sh を 1 回実行する。important が高ければ PR 本文の「判断の記録」に残してから終える。"}
' <<EOF 2>/dev/null || exit 0
$scores
EOF
exit 0
