#!/bin/sh
# 会話ログ（jsonl）から、assistant の行ごとのトークン数を TSV で出す。本文は読まず、id・モデル・usage だけを取り出す。
# 使い方: extract-usage.sh [--since YYYY-MM-DD] [--until YYYY-MM-DD] <transcript.jsonl>...
# 出力列: msg_id, ts, session, who(main|sub), agent_type, model, input, cache_read, cache_write, output
#   --until はその日を含む。agent_type は本体なら main、subagent なら隣の agent-<id>.meta.json の agentType（無ければ unknown）。
#   1 回の API 応答が同じ msg_id の複数行に分かれて記録されるので、ここでは行のまま出し、まとめは usage-report.sh が行う。
set -eu

since=""
until=""
while [ $# -gt 0 ]; do
  case "$1" in
    --since) since="$2"; shift 2 ;;
    --until) until="$2"; shift 2 ;;
    *) break ;;
  esac
done

for f in "$@"; do
  case "$f" in
    */subagents/*)
      who=sub
      agent_type=$(jq -r '.agentType // empty' "${f%.jsonl}.meta.json" 2>/dev/null || true)
      agent_type=${agent_type:-unknown} ;;
    *) who=main; agent_type=main ;;
  esac
  jq -r --arg since "$since" --arg until "$until" --arg who "$who" --arg at "$agent_type" '
    select(.type == "assistant" and .message.usage != null and (.message.id // "") != "" and .message.model != "<synthetic>")
    | (.timestamp // "") as $ts
    | select($since == "" or $ts >= $since)
    | select($until == "" or $ts[0:10] <= $until)
    | .message.usage as $u
    | [.message.id, $ts, (.sessionId // ""), $who, $at, .message.model,
       ($u.input_tokens // 0), ($u.cache_read_input_tokens // 0), ($u.cache_creation_input_tokens // 0), ($u.output_tokens // 0)]
    | @tsv
  ' "$f" 2>/dev/null || true
done
