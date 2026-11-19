#!/bin/sh
# PreToolUse hook（Bash）。plugin cache の下の SKILL.md とプレイブックを、cat・sed・head・tail・less・bat・awk で読むのを止め、Read ツールか Skill ツールへ誘導する。pstack の skill は disable-model-invocation で Skill ツールから起動できないので Read ツール、それ以外（bigdaddy・yomiyasu など）は Skill ツール。
# Why: cache の版番号つきパスを Bash で読むと、起動した skill とは別の版を読んだり、skill の読み込み記録に残らなかったりする。同じ訂正を文章で重ねず、hook で止める。
# Why: シェルの文法を正確には読まない。引用符・括弧・バックスラッシュを外して区切りで割り、読み取りコマンドの名前が出るセグメントだけを点検する。
#      変数経由（P=<cache>/...; cat $P/playbooks/x.md）や cd してからの相対読みも拾う。素通りより止めすぎを選ぶ。
# Why: jq が無い環境では入力を読めないので止めない。bigdaddy の hook はすべて jq を前提にしている。
set -u

command -v jq >/dev/null 2>&1 || exit 0
input=$(cat) || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0

case "$cmd" in *cache/*) ;; *) exit 0 ;; esac

set -f

# 行継続をつなぎ、引用符を外す。ここまでを raw とし、パスの取り出しと $ の判定に使う。
norm=$(printf '%s\n' "$cmd" | sed -e ':a' -e '/\\$/{N;s/\\\n//;ba' -e '}' | tr -d "\"'")
segs=$(printf '%s\n' "$norm" | sed 's/[&|;]/\
/g')

is_read() {
  for w in $1; do
    case "$w" in
      cat|sed|head|tail|less|bat|awk|*/cat|*/sed|*/head|*/tail|*/less|*/bat|*/awk) return 0 ;;
    esac
  done
  return 1
}

has_target() {
  case "$1" in *SKILL.md*|*playbooks/*) return 0 ;; esac
  return 1
}

violation=""
after_cd=""
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  # shellcheck disable=SC1003
  tok=$(printf '%s' "$seg" | tr -d '\\' | tr '(){}`' '     ')
  reads=""
  is_read "$tok" && reads=1

  if [ -n "$reads" ]; then
    case "$seg" in
      *plugins/cache/*) has_target "$seg" && violation=1 ;;
    esac
    case "$seg" in
      *plugins/cache/*) ;;
      *cache/*) has_target "$seg" && violation=1 ;;
    esac
    printf '%s' "$seg" | grep -Eq '\$[{(]?[A-Za-z_]' && violation=1
    [ -n "$after_cd" ] && violation=1
    case " $tok " in *" xargs "*) has_target "$cmd" && violation=1 ;; esac
  fi

  prev=""
  for w in $tok; do
    case "$prev" in
      cd|pushd)
        case "$seg" in
          *plugins/cache/*) after_cd=1 ;;
          *) case "$w" in /*|~*|'$'*) after_cd="" ;; esac ;;
        esac ;;
    esac
    prev=$w
  done
done <<EOF
$segs
EOF

[ -n "$violation" ] || exit 0

cls='[^[:space:]()=;&|<>`]'
steps=""
unresolved=""

skill_paths=$(printf '%s\n' "$norm" | grep -oE "${cls}*plugins/cache/${cls}*/skills/[^/[:space:]]+/SKILL\.md" | sort -u)
while IFS= read -r p; do
  [ -n "$p" ] || continue
  name=$(printf '%s\n' "$p" | sed -E 's|^.*plugins/cache/[^/]+/([^/]+)/[^/]+/skills/([^/]+)/SKILL\.md$|\1:\2|')
  case "$name" in
    ''|*[!A-Za-z0-9._:-]*) unresolved=1 ;;
    pstack:*)
      # shellcheck disable=SC2088
      case "$p" in "~/"*) p="$HOME/${p#\~/}" ;; esac
      steps="${steps}Read ツールで ${p} を読む（pstack の ${name} は Skill ツールで起動できない。Bash で読まない）。
" ;;
    *) steps="${steps}Skill ツールで ${name} を起動する（${p} を Bash で読まない）。
" ;;
  esac
done <<EOF
$skill_paths
EOF

playbook_paths=$(printf '%s\n' "$norm" | grep -oE "${cls}*plugins/cache/${cls}*/playbooks/${cls}+\.md" | sort -u)
while IFS= read -r p; do
  [ -n "$p" ] || continue
  # shellcheck disable=SC2088
  case "$p" in "~/"*) p="$HOME/${p#\~/}" ;; esac
  config=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
  p=$(printf '%s' "$p" | sed -e "s#\${CLAUDE_CONFIG_DIR:-\$HOME/.claude}#$config#" -e "s#\$HOME#$HOME#")
  steps="${steps}Read ツールで ${p} を読む。
"
done <<EOF
$playbook_paths
EOF

if [ -z "$steps" ] || [ -n "$unresolved" ]; then
  steps="${steps}pstack の SKILL.md（原則を含む）とプレイブックは Read ツールで絶対パスを読み、bigdaddy・yomiyasu の SKILL.md は Skill ツールで <plugin>:<skill> を起動する。
"
fi

reason="bigdaddy skill-read-guard: plugin cache の SKILL.md かプレイブックを Bash の読み取りコマンド（cat sed head tail less bat awk）で読もうとしたので止めた。
${steps}cache の外のファイルや、ls・rg・grep・find・スクリプトの実行は止めない。"

jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
