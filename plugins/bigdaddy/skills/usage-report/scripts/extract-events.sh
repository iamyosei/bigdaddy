#!/bin/sh
# 会話ログ（jsonl）から、skill・プレイブック・原則・Jev・subagent の使用記録を TSV で出す。本文は読まず、名前とパスだけを取り出す。
# 使い方: extract-events.sh [--since YYYY-MM-DD] <transcript.jsonl>...
# 出力列: event_id, ts, session, who(main|sub), kind, name
#   event_id はツール呼び出しの id（無ければ行の uuid）を使う。記録 1 件ごとに一意になる。
set -eu

since=""
if [ "${1:-}" = "--since" ]; then since="$2"; shift 2; fi

for f in "$@"; do
  case "$f" in */subagents/*) who=sub ;; *) who=main ;; esac
  jq -r --arg since "$since" --arg who "$who" '
    # plugin cache の下は使用でしか読まれない（作成作業はリポジトリで行う）ので、Bash で読んだものも数える。
    # コマンドが /plugins/cache/ を含むときだけ、読み取りコマンド（cat・sed・head・tail・less・bat・awk）で始まる区切りから名前を取り出す。
    # リポジトリなどの cache 外の絶対パスを指す語は外し、名前は重複なしで 1 件ずつ数える。
    def bash_reads($tid):
      select(test("/plugins/cache/"))
      | [split("[;&|\n(`]+"; null)[] | sub("^\\s*((do|then)\\s+)?"; "")] as $segs
      | ($segs | map(select(test("^(cat|sed|head|tail|less|bat|awk)(\\s|$)")))) as $reads
      | select($reads | length > 0)
      | ($reads | map(split("\\s+"; null)[] | select(startswith("/") and (contains("/plugins/cache/") | not) | not)) | join(" ")) as $words
      | (
          ([$words | scan("playbooks/([a-z][a-z0-9-]*)\\.md") | .[0]] | unique | map([$tid + ":playbook:" + ., "playbook-bash", .])),
          (select($words | test("SKILL\\.md"))
           | ([$words | scan("/plugins/cache/[^ ]*/skills/([a-z][a-z0-9-]*)/SKILL\\.md") | .[0]]
              + [scan("cd [^ ]*/plugins/cache/[^ ]*/skills/([a-z][a-z0-9-]*)(\\s|/|;|&|$)") | .[0]]
              + [scan("for ([A-Za-z_]+) in ([^;]+);") as [$v, $list]
                 | select($words | test("\\$\\{?" + $v + "[^A-Za-z0-9_]"))
                 | $list | split(" ")[] | select(test("^[a-z][a-z0-9-]*$"))]
             | unique | map([$tid + ":skill:" + ., "skill-read-bash", .])))
        )
      | .[];
    select($since == "" or ((.timestamp // "") >= $since))
    | (.sessionId // "") as $sid
    | (.timestamp // "") as $ts
    | (.uuid // "") as $uuid
    | (
        (select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | .id as $tid | (
          (select(.name == "Skill") | [$tid, "skill", .input.skill]),
          (select(.name == "Agent" or .name == "Task") | [$tid, "subagent", (.input.subagent_type // "general-purpose")]),
          (select(.name == "Read") | .input.file_path // "" |
            (capture("/poteto-mode/playbooks/(?<p>[a-z-]+)\\.md$") | [$tid, "playbook", .p]),
            (capture("/skills/(?<s>[^/]+)/SKILL\\.md$") | [$tid, "skill-read", .s])),
          (select(.name == "Bash") | .input.command // "" |
            (scan("(jev|route-playbook|route-model|check-naze|audit-decision)\\.sh") | [$tid, "jev", .[0]]),
            bash_reads($tid))
        )),
        # ユーザーがスラッシュコマンドで起動した skill。組み込みコマンド（/model など）は skill ではないので外す
        (select(.type == "user") | .message.content | strings |
          scan("<command-name>/([^<]+)</command-name>") | .[0]
          | select(test("^(model|clear|compact|config|effort|fast|resume|init|review|cost|help|login|logout|memory|mcp|permissions|plugin|status|context|rename|color|add-dir|agents|doctor|hooks|ide|export|exit|web-setup|usage|autocompact|loop|btw)$") | not)
          | [$uuid, "skill-user", .])
      )
    | select(.[2] != null and .[2] != "")
    | [.[0], $ts, $sid, $who, .[1], .[2]] | @tsv
  ' "$f" 2>/dev/null || true
done
