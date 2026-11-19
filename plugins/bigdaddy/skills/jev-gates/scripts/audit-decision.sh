#!/bin/sh
# logic-audit の決定モード。決定の記録（結論・前提・退けた代案・覆る条件）を Jev に 1 回だけ見せ、記録の要否と危うい点を出す。
# 使い方: audit-decision.sh <decision.json>   または   echo '<json>' | audit-decision.sh
#   {"decision": "...", "conclusion": "...", "premises": {"confirmed": [...], "unconfirmed": [...]},
#    "rejected": ["代案と退けた理由", ...], "overturn_if": [...], "context": "任意"}
# BIGDADDY_JEV=1 でなければ exit 3。
# 出力: {"important", "unconfirmed_as_fact", "missing_alternatives", "record", "flags"}
#   record が true なら PR 本文の「判断の記録」に残す。flags が空でなければ logic-audit の通常手順に上げる。
set -eu

[ "${BIGDADDY_JEV:-}" = 1 ] || { echo 'audit-decision.sh: Jev は無効（BIGDADDY_JEV=1 で有効）' >&2; exit 3; }

IMPORTANT_MIN=0.5
UNCONFIRMED_MAX=0.5
MISSING_MAX=0.5

here=$(cd "$(dirname "$0")" && pwd)
if [ $# -ge 1 ]; then input=$(cat "$1"); else input=$(cat); fi

body=$(printf '%s' "$input" | jq '
  def items($xs): if ($xs // []) | length == 0 then "  (none)" else ($xs | map("  - " + .) | join("\n")) end;
  {
    state: ([
      "A coding agent recorded a decision it made.",
      "Decision: \(.decision)",
      "Conclusion: \(.conclusion)",
      "Confirmed premises (verified):\n\(items(.premises.confirmed))",
      "Unconfirmed premises (not verified):\n\(items(.premises.unconfirmed))",
      "Rejected alternatives:\n\(items(.rejected))",
      "Would be overturned if:\n\(items(.overturn_if))"
    ] + (if (.context // "") != "" then ["Context: \(.context)"] else [] end) | join("\n")),
    questions: {
      important: {type: "noul",
        instructions: "Should this decision be recorded for later readers? Answer yes if a later reader of the PR or brief needs it to understand the change, or reverting it is costly, or it affects production, data, or a public API. Trivial local choices such as naming or formatting are no."},
      unconfirmed_as_fact: {type: "noul",
        instructions: "Does the conclusion rely on a premise that is not verified (listed as unconfirmed, or stated without evidence) while treating it as established fact? Also answer yes when the reasoning is of the form \"no counterexample was found\" or \"tests passed\", therefore there is no bug."},
      missing_alternatives: {type: "noul",
        instructions: "Is there a plausible alternative to the conclusion that the rejected alternatives list does not cover, and that a careful reviewer would expect to be weighed because it could lead to a materially different outcome? Minor variations of the same choice do not count."}
    }
  }')

printf '%s' "$body" | sh "$here/jev.sh" | jq \
  --argjson imin "$IMPORTANT_MIN" --argjson umax "$UNCONFIRMED_MAX" --argjson mmax "$MISSING_MAX" '
  with_entries(.value = (.value.noul * 100 | round / 100))
  | . + {
      record: (.important >= $imin),
      flags: [
        (select(.unconfirmed_as_fact > $umax) | "unconfirmed_as_fact=\(.unconfirmed_as_fact)"),
        # 代案の漏れは命名のような小さな判断でも 0.6 前後に出るので、記録する判断でだけ上げる
        (select(.important >= $imin and .missing_alternatives > $mmax) | "missing_alternatives=\(.missing_alternatives)")
      ]
    }'
