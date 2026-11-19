#!/bin/sh
# PreToolUse hook（Bash）。git push の前に、隔離レビューの記録（review-triage-loop の scripts/review-stamp.sh）とブランチの先頭を比べる。
# 記録より後にテスト・ドキュメント以外のファイルが変わっていれば、再レビューと記録のし直しを求めて push を止める。
# Why: 記録の無いブランチは止めない。レビューの仕組みを持たないリポジトリまで巻き込まないため。
#      一度もレビューせずに push するのを防ぐのは、各リポジトリのレビュー手順の役目にする。
# Why: シェルの文法を正確には読まない。push の対象を refspec から当てにいくと、リダイレクトや略記で素通りする。
#      代わりに、移った先になりうる場所（cwd・cd・pushd・-C・GIT_DIR）を全部たどり、いまのブランチと、コマンドに名前の出る記録済みのブランチを全部点検する。
#      別のブランチの push でも止まることがある。素通りより止めすぎを選ぶ。
# Why: jq が無い環境では入力を読めないので止めない。bigdaddy の hook はすべて jq を前提にしている。
set -u

command -v jq >/dev/null 2>&1 || exit 0
input=$(cat) || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null) || exit 0
[ -n "$cwd" ] || cwd=$(pwd)

case "$cmd" in *push*) ;; *) exit 0 ;; esac

# 行継続をつなぎ、引用符を外し、コマンド置換や括弧の記号（$ ( ) ` \ { }）を空白にし、区切り（&& || ; |）を改行にする
# shellcheck disable=SC2016
text=$(printf '%s\n' "$cmd" | sed -e ':a' -e '/\\$/{N;s/\\\n//;ba' -e '}' | tr -d "\"'" | tr '$()`\\{}' '       ' | sed -E 's/(&&|\|\||;|\|)/\
/g')
printf '%s\n' "$text" | grep -Eq '(^|[[:space:]])([^[:space:]]*/)?git([[:space:]]+(-C|-c|--git-dir|--work-tree|--namespace)[[:space:]]+[^[:space:]]+|[[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)' || exit 0

# 振る舞いを変えないファイル。判定はここだけに置く。
# - agent への指示は Markdown でも振る舞いとして扱う。
# - テストはファイル名か、tests/・__tests__/・__snapshots__/ の下、ルートの test/ の下だけ。test/ や spec/ はアプリの中にもあるので、深い所は名前で見ない。
# - ドキュメントは README・CHANGELOG・LICENSE・CONTRIBUTING、ルートの docs/・doc/ の下の Markdown、.rst・.adoc だけ。
#   ほかの Markdown と MDX は、描画されたり、アプリや agent に読み込まれたりするので振る舞いとして扱う。
is_test_or_doc() {
  case "$1" in
    CLAUDE*.md|*/CLAUDE*.md|AGENTS*.md|*/AGENTS*.md|GEMINI*.md|*/GEMINI*.md|SKILL.md|*/SKILL.md) return 1 ;;
    .claude/*|*/.claude/*|.cursor/*|*/.cursor/*|.github/*|*/.github/*|.env*|*/.env*) return 1 ;;
    *.spec.yaml|*.spec.yml|*.spec.json) return 1 ;;
    skills/*|*/skills/*|hooks/*|*/hooks/*|commands/*|*/commands/*|agents/*|*/agents/*|prompts/*|*/prompts/*) return 1 ;;
    *.test.*|*.spec.*|*_test.go|*_test.py|test_*.py|*/test_*.py|conftest.py|*/conftest.py) return 0 ;;
    tests/*|*/tests/*|__tests__/*|*/__tests__/*|__snapshots__/*|*/__snapshots__/*|test/*) return 0 ;;
    README|*/README|README.md|*/README.md|README.*.md|*/README.*.md|CHANGELOG.md|*/CHANGELOG.md|CONTRIBUTING.md|*/CONTRIBUTING.md|LICENSE|*/LICENSE|LICENSE.md|*/LICENSE.md) return 0 ;;
    docs/*.md|doc/*.md|*.rst|*.adoc) return 0 ;;
  esac
  return 1
}

# 見た目に効くファイル。変わっていればスクリーンショットの撮り直しも求める。
is_ui() {
  case "$1" in
    *.tsx|*.jsx|*.vue|*.svelte|*.astro|*.html|*.mdx|*.css|*.scss|*.sass|*.less|*.svg|*.png|*.jpg|*.jpeg|*.webp|*.gif) return 0 ;;
    *.swift|*.dart|*.storyboard|*.xib|tailwind.config.*|*/tailwind.config.*) return 0 ;;
  esac
  return 1
}

abs() {
  # shellcheck disable=SC2088
  case "$1" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${1#\~/}" ;;
    /*) printf '%s' "$1" ;;
    *) printf '%s/%s' "$2" "$1" ;;
  esac
}

# 移った先になりうる場所を集める。行頭の印は d がディレクトリ（-C で渡す）、g が git ディレクトリ（--git-dir で渡す）。
set -f
base=$cwd
places="d $cwd"
all=""
prev=""
# shellcheck disable=SC2086
for tok in $text; do
  case "$prev" in
    cd|pushd) base=$(abs "$tok" "$base"); places="$places
d $base" ;;
    -C) places="$places
d $(abs "$tok" "$base")" ;;
    --git-dir) places="$places
g $(abs "$tok" "$base")" ;;
  esac
  case "$tok" in
    GIT_DIR=*) places="$places
g $(abs "${tok#GIT_DIR=}" "$base")" ;;
    --git-dir=*) places="$places
g $(abs "${tok#--git-dir=}" "$base")" ;;
    --all|--branches|--mirror) all=1 ;;
  esac
  prev=$tok
done
set +f

reasons=""
checked=""

# $1 $2 は git の場所の指定（-C <dir> か --git-dir <dir>）、$3 は記録の置き場、$4 は記録済みのブランチ名、$5 は送りうるコミット
check_stamp() {
  loc_flag=$1 loc=$2 stamps=$3 branch=$4 tip=$5
  [ -n "$tip" ] || return 0
  case "$checked" in *"
$stamps/$branch $tip
"*) return 0 ;; esac
  checked="$checked
$stamps/$branch $tip
"
  [ -f "$stamps/$branch" ] || return 0
  reviewed=$(head -n1 "$stamps/$branch")
  [ "$reviewed" = "$tip" ] && return 0

  # リネームを 1 件にまとめると消えた側のパスを見落とすので、--no-renames で両方を出す
  if ! changed=$(git "$loc_flag" "$loc" -c core.quotePath=false diff --no-renames --name-only "$reviewed" "$tip" 2>/dev/null); then
    behavior="（記録した $reviewed が見つからない）"
    ui=""
  else
    behavior=""
    ui=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      is_test_or_doc "$f" && continue
      behavior="$behavior $f"
      is_ui "$f" && ui="$ui $f"
    done <<EOF
$changed
EOF
    [ -n "$behavior" ] || return 0
  fi

  reasons="${reasons}$branch は隔離レビューを ${reviewed} で通したあと、振る舞いを変える変更が入っている（rebase で取り込んだ変更も含む）:$behavior
"
  [ -n "$ui" ] && reasons="${reasons}UI に効くファイルが変わっている:$ui
スクリーンショットを撮り直し、PR に貼り替える。
"
  return 0
}

while IFS= read -r place; do
  [ -n "$place" ] || continue
  case "$place" in g\ *) loc_flag=--git-dir ;; *) loc_flag=-C ;; esac
  loc=${place#? }
  common=$(git "$loc_flag" "$loc" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || continue
  stamps="$common/bigdaddy/review-stamps"
  [ -d "$stamps" ] || continue
  current=$(git "$loc_flag" "$loc" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  upstream=""
  [ -n "$current" ] && upstream=$(git "$loc_flag" "$loc" config "branch.$current.merge" 2>/dev/null | sed 's|^refs/heads/||')

  # 送りうるコミット: この場所の HEAD と、コマンドに名前が出るローカルのブランチの先頭。
  # worktree の別名のブランチや detached HEAD から HEAD:<記録済みのブランチ> へ送る形があるので、記録済みのブランチの先頭だけでは足りない。
  sendable=$(git "$loc_flag" "$loc" rev-parse --verify -q HEAD 2>/dev/null || true)
  locals=$(git "$loc_flag" "$loc" for-each-ref --format='%(refname:short) %(objectname)' refs/heads 2>/dev/null)
  while read -r name sha; do
    [ -n "$name" ] || continue
    printf '%s' "$cmd" | grep -Fq -- "$name" && sendable="$sendable
$sha"
  done <<LOCALS
$locals
LOCALS

  # 関わる記録済みのブランチ: いまのブランチ、その upstream、コマンドに名前が出るもの、--all 系ならすべて
  names=$(cd "$stamps" && find . -type f | sed 's|^\./||')
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    if [ -n "$all" ] || [ "$b" = "$current" ] || [ "$b" = "$upstream" ] || printf '%s' "$cmd" | grep -Fq -- "$b"; then
      own=$(git "$loc_flag" "$loc" rev-parse --verify -q "refs/heads/$b^{commit}" 2>/dev/null || true)
      while IFS= read -r c; do
        check_stamp "$loc_flag" "$loc" "$stamps" "$b" "$c"
      done <<COMMITS
$own
$sendable
COMMITS
    fi
  done <<NAMES
$names
NAMES
done <<EOF
$places
EOF

[ -n "$reasons" ] || exit 0

reason="bigdaddy review-push-guard:
${reasons}push の前に、差分全体を fresh な隔離レビュアーで再レビューし、blocking が 0 件になったら review-stamp.sh で記録し直す（再レビュー → スタンプ）。「軽い変更」は省く理由にならない。手順は review-triage-loop の references/isolated-review.md。"

jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
