#!/bin/sh
# 依頼文から pstack の poteto-mode のどのプレイブックで進めるかを Jev で決める。
# 選択肢は poteto-mode の SKILL.md のプレイブック一覧から毎回作る。pstack を更新して一覧が変わっても書き写しがずれないため。
# 使い方: route-playbook.sh "<依頼文と、分かっている文脈>"
#   route-playbook.sh --criteria は選択肢（stem と説明）だけを JSON で出し、Jev は呼ばない。
# 出力: {"playbook": <stem>, "confidence": .., "top3": {...}}
# BIGDADDY_JEV=1 でなければ exit 3（--criteria は Jev を呼ばないので今どおり動く）。
#   playbook が "none" なら既存のどのプレイブックにも当たらない（運用・データ作業など）。
#   別の Noul で「当たるか」を聞く形は、単純な調査の質問まで低く出て使えなかったので、選択肢の 1 つにしている。
#   confidence < 0.5 は外れやすい（2026-10 の履歴 20 件で、外れた 2 件はどちらも 0.5 未満）。この場合は top3 を見て呼び出し側が決める。
set -eu

[ "${1:-}" = "--criteria" ] || [ "${BIGDADDY_JEV:-}" = 1 ] || { echo 'route-playbook.sh: Jev は無効（BIGDADDY_JEV=1 で有効）' >&2; exit 3; }
request="${1:?usage: route-playbook.sh \"<request>\" | --criteria}"
here=$(cd "$(dirname "$0")" && pwd)

skill="${PSTACK_POTETO_SKILL:-}"
if [ -z "$skill" ]; then
  # 実装役が SKILL.md を読む場所（installed_plugins.json の installPath）と同じ版を使う。無ければ cache の最新版。
  install=$(jq -r '.plugins["pstack@bigdaddy"][0].installPath // empty' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json" 2>/dev/null || true)
  skill="$install/skills/poteto-mode/SKILL.md"
  [ -f "$skill" ] || skill=$(ls -d "$HOME"/.claude/plugins/cache/*/pstack/*/skills/poteto-mode/SKILL.md 2>/dev/null | sort -V | tail -n1)
fi
if [ ! -f "$skill" ]; then
  echo "route-playbook.sh: poteto-mode の SKILL.md が見つからない（PSTACK_POTETO_SKILL で指定できる）" >&2
  exit 2
fi

# 「- **Name.** 説明」の行から {stem: 説明} を作る。一覧は `## Playbooks` から次の `## ` 見出しの手前まで。
# stem は pstack の規則（poteto-mode の SKILL.md の Playbooks 節の冒頭）で決める。行に File: `playbooks/<stem>.md` があればそれ、無ければ Name を kebab case にしたもの（小文字、空白は -、ハイフンは残し、ほかの記号は落とす）。
# 読めない行や、playbooks/<stem>.md が無い行が 1 つでもあれば、行を出して止める。pstack の書式が変わったことに気づくため。
# Opening a PR は他のプレイブックの最後に必ず呼ばれるもので、依頼から選ぶ対象ではないので外す。
rows=$(awk '/^## Playbooks/ { on = 1; next } /^## / { on = 0 } on' "$skill" \
  | grep '^- \*\*' \
  | jq -R -s '
      split("\n") | map(select(length > 0))
      | map(capture("^- \\*\\*(?<name>[^*]+?)\\.\\*\\* (?<text>.*)$") // error("route-playbook.sh: 読めない行: " + .))
      | map({
          stem: ((.text | capture("`playbooks/(?<s>[a-z-]+)\\.md`").s?) // (.name | ascii_downcase | gsub(" "; "-") | gsub("[^a-z0-9-]"; ""))),
          name: .name,
          text: (.text | sub("\\s*(Full steps: |File: )?`playbooks/[a-z-]+\\.md`\\.?\\s*$"; ""))
        })') || exit 2
dir=$(dirname "$skill")/playbooks
missing=$(printf '%s' "$rows" | jq -r '.[] | "\(.stem)\t\(.name)"' | while IFS="$(printf '\t')" read -r stem name; do
  [ -f "$dir/$stem.md" ] || echo "  $name → $dir/$stem.md"
done)
if [ -n "$missing" ] || [ "$(printf '%s' "$rows" | jq length)" = 0 ]; then
  echo "route-playbook.sh: プレイブックの一覧を playbooks/<stem>.md に解決できない行がある（pstack の書式が変わった可能性）" >&2
  [ -z "$missing" ] || printf '%s\n' "$missing" >&2
  exit 2
fi
criteria=$(printf '%s' "$rows" | jq '
  map(select(.stem != "opening-a-pr") | {key: .stem, value: .text})
  | from_entries
  | . + {"none": "None of the above: operational work that writes to production (backfills, data fixes, running jobs that change production data, config changes in external services). Read-only queries and measurements are Investigation, not this."}')

if [ "$request" = "--criteria" ]; then
  printf '%s\n' "$criteria"
  exit 0
fi

body=$(jq -n --arg state "$request" --argjson criteria "$criteria" '{
  state: $state,
  questions: {
    playbook: {
      type: "choice",
      instructions: "This is a work request to a coding agent. Which playbook should the agent follow to carry it out?",
      criteria: $criteria
    }
  }
}')

printf '%s' "$body" | sh "$here/jev.sh" | jq '{
  playbook: .playbook.choice,
  confidence: .playbook.confidence,
  top3: (.playbook.probabilities | to_entries | sort_by(-.value) | .[:3] | from_entries)
}'
