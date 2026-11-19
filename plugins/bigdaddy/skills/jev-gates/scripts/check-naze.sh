#!/bin/sh
# なぜなぜ分析の各段を Jev で評価する。全段の問いを 1 回の問い合わせに束ねる。
# 使い方: check-naze.sh <analysis.json>
#   {"symptom": "...", "steps": [{"answer": "...", "evidence": "..."}, ...]}
#   steps[0] が「なぜ1」の答え。枝は "parent" に親の段番号（1 始まり、0 は症状）を書く。省略時は直前の段。
#   最後の要素を根本原因として扱う。
# BIGDADDY_JEV=1 でなければ exit 3。
# 出力: 段ごとの値と、引っかかった項目（flags）。
#   evidenced < 0.5      証拠が弱い。証拠を取りに戻る
#   causes_prev < 0.5    前の段とのつながりが弱い。その段を立て直す
#   blame > 0.5          人のせいで止めている。仕組みまで掘る
#   other_causes         参考値。どの分析でも 0.6〜0.9 に出て良し悪しを区別できなかったので flags には入れない
#   root_actionable / root_prevents < 0.5（最後の段）  まだ止める点ではない。掘り続ける
set -eu

[ "${BIGDADDY_JEV:-}" = 1 ] || { echo 'check-naze.sh: Jev は無効（BIGDADDY_JEV=1 で有効）' >&2; exit 3; }
here=$(cd "$(dirname "$0")" && pwd)
input="${1:?usage: check-naze.sh <analysis.json>}"

body=$(jq '
  . as $a
  | def parent($i): ($a.steps[$i].parent // $i);
    def prev($i): if parent($i) == 0 then "the symptom" else "the answer to why \(parent($i))" end;
  ($a.steps | length) as $n
  | ([("症状: " + $a.symptom)]
     + [range(0; $n) as $i
        | "なぜ\($i + 1)（\(if parent($i) == 0 then "症状" else "なぜ\(parent($i))" end) に対して）の答え: \($a.steps[$i].answer)（証拠: \($a.steps[$i].evidence)）"]
     | join("\n")) as $state
  | {
    state: ("なぜなぜ分析（トヨタ式）。症状から順に「なぜ」を重ねた鎖（枝あり）。\n" + $state),
    questions: (
      [range(0; $n) as $i | (
        {key: "s\($i + 1)_evidenced", value: {type: "noul",
          instructions: "Is the answer to why \($i + 1) supported by the evidence cited for it, as an observation rather than a guess?"}},
        {key: "s\($i + 1)_causes_prev", value: {type: "noul",
          instructions: "Would the answer to why \($i + 1) plausibly cause \(prev($i))?"}},
        {key: "s\($i + 1)_blame", value: {type: "noul",
          instructions: "Does the answer to why \($i + 1) blame a person'"'"'s carelessness, forgetting, or mistake instead of naming a mechanism or process gap?"}},
        {key: "s\($i + 1)_other_causes", value: {type: "noul",
          instructions: "Are there other plausible causes of \(prev($i)) that the answer to why \($i + 1) does not cover?"}}
      )]
      + [
        {key: "root_actionable", value: {type: "noul",
          instructions: "Is the answer to why \($n) (the last one) something the team can change directly in their own code, tools, or process?"}},
        {key: "root_prevents", value: {type: "noul",
          instructions: "If the answer to why \($n) (the last one) were fixed, would the original symptom stop recurring?"}}
      ]
      | from_entries)
  }' "$input")

printf '%s' "$body" | sh "$here/jev.sh" | jq '
  with_entries(.value = (.value.noul * 100 | round / 100))
  | . as $v
  | {
      scores: $v,
      flags: [
        ($v | to_entries[]
          | select(
              (.key | endswith("_evidenced")) and .value < 0.5
              or (.key | endswith("_causes_prev")) and .value < 0.5
              or (.key | endswith("_blame")) and .value > 0.5
              or (.key | startswith("root_")) and .value < 0.5)
          | "\(.key)=\(.value)")
      ]
    }'
