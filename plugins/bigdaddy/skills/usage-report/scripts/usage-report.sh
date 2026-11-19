#!/bin/sh
# 会話ログ（~/.claude/projects/**/*.jsonl、subagent 分を含む）から、skill・プレイブック・原則・Jev・subagent の使用回数と、モデルごとのトークン数を数える。
# 記録の取り出しは extract-events.sh と extract-usage.sh が行う。
# 使い方: usage-report.sh [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--project <ディレクトリ名に含まれる文字列>] [--json]
#   --until はその日を含む。
set -eu

since=""
until=""
project=""
json=0
while [ $# -gt 0 ]; do
  case "$1" in
    --since) since="$2"; shift 2 ;;
    --until) until="$2"; shift 2 ;;
    --project) project="$2"; shift 2 ;;
    --json) json=1; shift ;;
    *) echo "usage: usage-report.sh [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--project <substr>] [--json]" >&2; exit 2 ;;
  esac
done

here=$(cd "$(dirname "$0")" && pwd)
root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
tmp=$(mktemp)
tmp_usage=$(mktemp)
trap 'rm -f "$tmp" "$tmp_usage"' EXIT

# 日付で絞るときは、更新日時で先にファイルを減らしてから中身の timestamp で正確に絞る
if [ -n "$since" ]; then
  find "$root" -name '*.jsonl' -newermt "$since" 2>/dev/null
else
  find "$root" -name '*.jsonl' 2>/dev/null
fi | while IFS= read -r f; do
  case "$f" in *"$project"*) ;; *) continue ;; esac
  "$here/extract-events.sh" ${since:+--since "$since"} "$f" >> "$tmp"
  "$here/extract-usage.sh" ${since:+--since "$since"} ${until:+--until "$until"} "$f" >> "$tmp_usage"
done

# 原則は skill 名でも読み込みでも出てくるので、別の区分としても数える
# トークンは同じ msg_id の行が 1 回の応答なので、id ごとに各値の最大を取ってから足す（行のまま足すと約 2 倍になる）
jq -r -R -s --argjson json "$json" --arg until "$until" --rawfile usage "$tmp_usage" '
  def tsv_rows: split("\n") | map(select(length > 0) | split("\t"));
  def share($t): if $t == 0 then 0 else (. / $t * 10000 | round) / 10000 end;
  def commas: tostring | if length <= 3 then . else (.[0:length-3] | commas) + "," + .[length-3:] end;
  def pct($t): (if $t == 0 then 0 else (. / $t * 1000 | round) end) as $n | "\($n / 10 | floor).\($n % 10)%";
  def pad($w; $right): ([range($w - length)] | map(" ") | join("")) as $p | if $right then $p + . else . + $p end;
  def via: [(if .skill > 0 then "Skill \(.skill)" else empty end), (if .read > 0 then "Read \(.read)" else empty end), (if .bash > 0 then "Bash \(.bash)" else empty end)] | join(" / ");
  def fields: ["input", "cache_read", "cache_write", "output"];
  tsv_rows | map({ts: .[1], session: .[2], who: .[3], kind: .[4], name: .[5]})
  | map(select($until == "" or .ts[0:10] <= $until))
  | . as $rows
  | ($usage | tsv_rows
     | map({id: .[0], who: .[3], agent_type: .[4], model: .[5],
            input: (.[6] | tonumber), cache_read: (.[7] | tonumber), cache_write: (.[8] | tonumber), output: (.[9] | tonumber)})
     | group_by(.id)
     | map(.[0] + (. as $g | reduce fields[] as $k ({}; .[$k] = ($g | map(.[$k]) | max))))) as $turns
  | ({turns: ($turns | length)} + reduce fields[] as $k ({}; .[$k] = ($turns | map(.[$k]) | add // 0))) as $total
  # 読み方を skill（Skill ツール）・read（Read ツール）・bash（plugin cache の下を Bash で読んだもの）に分ける
  | def count(f): map(select(f)) | group_by(.name) | map({
      name: .[0].name, count: length, sessions: (map(.session) | unique | length),
      skill: (map(select(.kind == "skill" or .kind == "skill-user")) | length),
      read: (map(select(.kind == "playbook" or .kind == "skill-read")) | length),
      bash: (map(select(.kind | endswith("-bash"))) | length)
    }) | sort_by(-.count);
  {
    sessions: ($rows | map(.session) | unique | length),
    skills: count(.kind == "skill" or .kind == "skill-user"),
    skills_by_user: count(.kind == "skill-user"),
    playbooks: count(.kind == "playbook" or .kind == "playbook-bash"),
    principles: ($rows | map(select((.kind | startswith("skill")) and (.name | test("principle-"))) | .name |= sub("^pstack:"; "")) | count(true)),
    skill_files_read: count((.kind == "skill-read" or .kind == "skill-read-bash") and (.name | test("principle-") | not)),
    jev_scripts: count(.kind == "jev"),
    subagents: count(.kind == "subagent"),
    models: ($turns | group_by([.model, .who, .agent_type]) | map(
      ({model: .[0].model, who: .[0].who, agent_type: .[0].agent_type, turns: length}
       + (. as $g | reduce fields[] as $k ({}; .[$k] = ($g | map(.[$k]) | add))))
      | . + {share: (. as $r | reduce (["turns"] + fields)[] as $k ({}; .[$k] = ($r[$k] | share($total[$k]))))}
    ) | sort_by(-.cache_read)),
    models_total: $total
  }
  | if $json == 1 then . else
      . as $all
      | (["model", "who", "agent_type", "turns"] + fields) as $head
      | ($all.models + [$all.models_total + {model: "total", who: "", agent_type: ""}]
         | map(. as $r | [.model, .who, .agent_type]
               + ((["turns"] + fields) | map(. as $k | "\($r[$k] | commas) (\($r[$k] | pct($all.models_total[$k])))")))) as $cells
      | ([$head] + $cells) as $table
      | ([range($head | length)] | map(. as $i | $table | map(.[$i] | length) | max)) as $w
      | (["記録があったセッション数: \(.sessions)", ""]
         + (to_entries | map(select(.key != "models" and (.value | type == "array"))) | map(
             .key as $k
             | "## \($k)", (if (.value | length) == 0 then "（なし）" else (.value[] | "\(.count)\t\(.sessions) セッション\t\(.name)" + (if (["playbooks", "principles", "skill_files_read"] | index($k)) then "\t(\(via))" else "" end)) end), ""
           ))
         + ["## models", (if ($all.models | length) == 0 then "（なし）" else
             ($table[] | [range(length) as $i | .[$i] | pad($w[$i]; $i >= 3)] | join("  ")) end), ""])
      | join("\n")
    end
' "$tmp" | if [ "$json" = 1 ]; then cat; else sed 's/^/  /; s/^  ## /## /'; fi
