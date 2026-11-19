#!/bin/sh
# 作業の難しさから、subagent に使うモデルと reasoning effort を決める。
# 調査も実装も、事実を集める、集めたものを整理する、取捨選択して決める、の順に難しくなる。層ごとにモデルを分ける。
# モデルと effort の組は 3 つに固定する。effort は Jev に聞かず、層の表から決める。
#   collect → haiku high、organize → sonnet high、decide → opus medium。
# 迷ったときは上の層に倒す。安いモデルで失敗して手戻りすると、かえって高くつくため。
#   layer の confidence が BUMP_BELOW 未満なら一段上の層にする（decide はそのまま）。
# 使い方:
#   route-model.sh "<subagent に渡す作業>"   層を Jev で判定する。
#   route-model.sh --session [<playbook>]   実装セッションの主を選ぶ。Jev は呼ばない。playbook は route-playbook.sh の stem。
#     feature・refactoring は設計が指示書で決まっているので organize。それ以外と省略時は decide に倒す。
# --session 以外は BIGDADDY_JEV=1 でなければ exit 3。
# 出力: {"model", "layer", "effort", "confidence", "bumped", "top3"}
#   model と effort は Agent ツールの `model` と `effort` にそのまま渡せる。confidence と top3 は layer の問いのもの。
#   --session では bumped は false、confidence と top3 は null。
set -eu

BUMP_BELOW=0.5

here=$(cd "$(dirname "$0")" && pwd)

pair_of='{
  collect: {model: "haiku", effort: "high"},
  organize: {model: "sonnet", effort: "high"},
  decide: {model: "opus", effort: "medium"}
}'

if [ "${1:-}" = "--session" ]; then
  case "${2:-}" in
    feature|refactoring) layer=organize ;;
    *) layer=decide ;;
  esac
  jq -n --arg layer "$layer" "$pair_of"' | .[$layer] + {layer: $layer, confidence: null, bumped: false, top3: null}'
  exit 0
fi

[ "${BIGDADDY_JEV:-}" = 1 ] || { echo 'route-model.sh: Jev は無効（BIGDADDY_JEV=1 で有効）' >&2; exit 3; }

request="${1:?usage: route-model.sh \"<subagent に渡す作業>\" | --session [<playbook>]}"

body=$(jq -n --arg state "$request" '
  {
    state: $state,
    questions: {
      layer: {
        type: "choice",
        instructions: "This is a piece of work handed to an agent. Which layer of work is it? Facts are gathered first, then organized, then used to make a decision; each layer is harder than the one before.",
        criteria: {
          collect: "Gather facts with nothing to judge: search code or logs, read files, run a given query or command and report what came back, list or count things, do a mechanical edit such as a rename or deleting files.",
          organize: "Turn given facts or a given plan into an output without choosing the direction: summarize or structure findings, write code, tests or docs to a spec whose design is already decided, fix a bug whose cause is already found, follow existing patterns.",
          decide: "Choose among options or judge: pick a design or approach, find a cause that is still unknown, weigh tradeoffs, review a change and decide if it is correct or done, decide what to keep and what to drop."
        }
      }
    }
  }')

printf '%s' "$body" | sh "$here/jev.sh" | jq --argjson below "$BUMP_BELOW" "$pair_of"' as $pair_of
  | ["collect","organize","decide"] as $order
  | .layer as $l
  | ($order | index($l.choice)) as $at
  | (if $l.confidence < $below then ([$at + 1, 2] | min) else $at end) as $to
  | $order[$to] as $layer
  | $pair_of[$layer] + {
      layer: $layer,
      confidence: $l.confidence,
      bumped: ($to != $at),
      top3: ($l.probabilities // null | if . then to_entries | sort_by(-.value) | .[:3] | from_entries else null end)
    }'
