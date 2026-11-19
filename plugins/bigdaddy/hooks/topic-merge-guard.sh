#!/bin/sh
# PreToolUse hook（Bash と、マージする MCP ツール）。agent が default branch に変更を入れる経路と、topic branch に未レビューの head を入れる経路を止める。
# - default branch に向く git push を止める。refspec の先が default branch のもの、または default branch にいる状態からの push。
#   review-push-guard.sh と違い、default branch へは review-stamp の記録があっても止める。
# - gh pr merge は、base が default branch なら止める（--auto 付きも含む）。base がそれ以外（topic branch）なら、PR の head SHA が review-stamp.sh の記録と一致するときだけ通す。
# - gh api の /merge・mergePullRequest・enablePullRequestAutoMerge と、マージする MCP ツールの呼び出しを止める。
# default branch は名前で決め打ちせず、リポジトリから求める（git push は origin/HEAD、無ければ gh repo view。gh pr merge は gh repo view）。
# default branch へのマージは利用者が GitHub の画面か自分のシェルで行う。それは本来の経路で、この hook の対象外。
# Why: agent と利用者は同じ GitHub 認証で動き、GitHub 側の保護だけでは区別できないので、agent の側の hook で止める。GitHub 側のブランチ保護や ruleset も使えるので、hook はそれと重ねて使う。
#      守る相手は agent の勘違いと先走りで、意図的に回避する agent は想定しない。スクリプトファイル経由などの間接実行は見えない。
# Why: 「default branch へは人間がマージ」「topic へはレビュー済み head だけ」を、文章ではなくここで守る。
# Why: gh を使えない・PR を特定できない・記録を読めないときは止める側に倒す。通してよいと言える根拠が無いため。
#      jq が無い環境だけは入力を読めないので止めない。bigdaddy の hook はすべて jq を前提にしている。
# Why: シェルの文法は正確には読まない。review-push-guard.sh と同じく、引用符と置換の記号を空白にして区切りで行に分け、
#      行ごとに見る。曖昧なもの（PR の指定が 2 つ以上に見える、--auto、gh api での merge）は止める。
set -u

input=$(cat) || exit 0
if ! command -v jq >/dev/null 2>&1; then
  # jq が無くても、merge か push を含む入力は止める（JSON は手で組む）。それ以外は通す。
  case "$input" in
    *merge*|*Merge*|*push*|*"gh api"*)
      printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"bigdaddy topic-merge-guard: jq が無いので入力を確かめられない。jq を入れるか、利用者が実行する。"}}'
      ;;
  esac
  exit 0
fi
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null) || exit 0
[ -n "$cwd" ] || cwd=$(pwd)
# 端末ツールは、タブの開始ディレクトリ（tool_input.cwd）と、前の cd を引き継ぐタブ（tab_id）を持つ
tcwd=$(printf '%s' "$input" | jq -r '.tool_input.cwd // ""' 2>/dev/null) || tcwd=""
[ -n "$tcwd" ] && cwd=$tcwd
tabid=$(printf '%s' "$input" | jq -r '.tool_input.tab_id // ""' 2>/dev/null) || tabid=""

tool=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null) || tool=""
# Monitor や端末のツールのように command を持つものは、Bash と同じに扱う
case "$tool" in mcp__*) [ -n "$cmd" ] && tool="" ;; esac
case "$tool" in
  mcp__*)
    case "$tool" in
      *merge*|*Merge*)
        # 自動マージを切る呼び出しは止めない
        case "$tool" in *set_auto_merge) printf '%s' "$input" | jq -e '.tool_input.enabled == false' >/dev/null 2>&1 && exit 0 ;; esac
        mcp_reason="マージする MCP ツール（$tool）は使わない。base と head を確かめられない。topic branch へのマージは gh pr merge を使う。default branch へのマージは利用者がする。" ;;
      *push_files*|*create_or_update_file*|*delete_file*|*update_ref*|*create_ref*|*createCommitOnBranch*)
        # ブランチに直接書く MCP ツール。branch が default branch か、読めないときは止める
        mbranch=$(printf '%s' "$input" | jq -r '.tool_input.branch // .tool_input.ref // ""' 2>/dev/null)
        mbranch=${mbranch#refs/heads/}
        mdefault=$(git -C "$cwd" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
        [ -n "$mdefault" ] || mdefault=$(cd "$cwd" 2>/dev/null && gh repo view --json defaultBranchRef 2>/dev/null | jq -r '.defaultBranchRef.name // ""' 2>/dev/null)
        if [ -n "$mbranch" ] && [ -n "$mdefault" ] && [ "$mbranch" != "$mdefault" ]; then exit 0; fi
        mcp_reason="ブランチに直接書く MCP ツール（$tool）で、書き込み先（${mbranch:-指定なし}）が default branch（${mdefault:-読めない}）か、確かめられない。default branch への変更は利用者が PR をマージして入れる。作業ブランチを指定して PR を出す。" ;;
      *) exit 0 ;;
    esac
    jq -n --arg r "bigdaddy topic-merge-guard:
$mcp_reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0 ;;
esac

case "$cmd" in *merge*|*Merge*|*push*|*api*) ;; *) exit 0 ;; esac

# shellcheck disable=SC2016
text=$(printf '%s\n' "$cmd" | sed -e ':a' -e '/\\$/{N;s/\\\n//;ba' -e '}' | tr -d "\"'" | tr '$()`\\{}' '       ' | sed -E 's/[0-9]*>&[0-9]*//g' | sed -E 's/(&&|\|\||;|\||&)/\
/g')

repo_flag='([[:space:]]+(-R|--repo)[[:space:]=]+[^[:space:]]+|[[:space:]]+--repo=[^[:space:]]+|[[:space:]]+-R[^[:space:]=]+)*'
gh_pr_merge="(^|[[:space:]])([^[:space:]]*/)?gh${repo_flag}[[:space:]]+pr${repo_flag}[[:space:]]+merge([[:space:]]|\$)"
gh_api='(^|[[:space:]])([^[:space:]]*/)?gh[[:space:]]+api([[:space:]]|$)'
git_push='(^|[[:space:]])([^[:space:]]*/)?git([[:space:]]+(-C|-c|--git-dir|--work-tree|--namespace)[[:space:]]+[^[:space:]]+|[[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)'
git_subtree_push='(^|[[:space:]])([^[:space:]]*/)?git([[:space:]]+(-C|-c|--git-dir|--work-tree|--namespace)[[:space:]]+[^[:space:]]+|[[:space:]]+-[^[:space:]]+)*[[:space:]]+subtree[[:space:]]+push([[:space:]]|$)'
printf '%s\n' "$text" | grep -Eq "$gh_pr_merge|$gh_api|$git_push|$git_subtree_push" || exit 0

abs() {
  # shellcheck disable=SC2088
  case "$1" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${1#\~/}" ;;
    /*) printf '%s' "$1" ;;
    *) printf '%s/%s' "$2" "$1" ;;
  esac
}

reasons=""
add() {
  reasons="${reasons}$1
"
}

# $1 は gh pr merge の引数（merge より後ろ）、$2 は gh を実行する場所、$3 は行の中で gh より前の部分
check_merge() {
  rest=$1 dir=$2 before=$3
  target="" repo=$4 auto="" disable_auto="" positionals=0 skip="" match=""
  case "$before" in
    *xargs*|*parallel*)
      add "xargs・parallel から gh pr merge を呼ぶ形は、どの PR が対象か確かめられないので使わない。PR の番号を直接書く。"
      return 0 ;;
  esac
  case "$before" in
    *GH_REPO=*) [ -n "$repo" ] || { repo=${before#*GH_REPO=}; repo=${repo%%[[:space:]]*}; } ;;
  esac
  set -f
  # shellcheck disable=SC2086
  for tok in $rest; do
    case "$skip" in
      repo) repo=$tok; skip=""; continue ;;
      match) match=$tok; skip=""; continue ;;
      value) skip=""; continue ;;
    esac
    case "$tok" in
      -R|--repo) skip=repo ;;
      --repo=*) repo=${tok#--repo=} ;;
      -R=*) repo=${tok#-R=} ;;
      -R?*) repo=${tok#-R} ;;
      --match-head-commit) skip=match ;;
      --match-head-commit=*) match=${tok#--match-head-commit=} ;;
      -b|--body|-t|--subject|-F|--body-file|-A|--author-email) skip=value ;;
      \>|\>\>|[0-9]\>|[0-9]\>\>|\<) skip=value ;;
      [0-9]\>*|\>*|\<*) ;;
      --auto|--auto=*) auto=1 ;;
      --disable-auto) disable_auto=1 ;;
      -*) ;;
      *) positionals=$((positionals + 1)); [ -n "$target" ] || target=$tok ;;
    esac
  done
  set +f

  # 自動マージを切るだけの呼び出しは、マージしないので通す
  [ -n "$disable_auto" ] && [ -z "$auto" ] && return 0
  if [ -n "$auto" ]; then
    add "gh pr merge --auto は使わない。あとから入る head がレビュー済みと一致する保証が無い。"
    return 0
  fi
  if [ "$positionals" -gt 1 ]; then
    add "gh pr merge の PR の指定が 2 つ以上に見える（$rest）。どの PR を見ればよいか決められない。PR は 1 つだけ、--body や --subject の値は使わず（本文は --body-file）、--match-head-commit にはコマンド置換を使わず SHA をそのまま書く。"
    return 0
  fi

  case "$target" in
    http*://*/pull/*)
      urlrepo=$(printf '%s' "$target" | sed -E 's|^https?://[^/]+/([^/]+/[^/]+)/pull/.*$|\1|')
      [ -n "$repo" ] || repo=$urlrepo ;;
  esac

  set -- pr view
  [ -n "$target" ] && set -- "$@" "$target"
  [ -n "$repo" ] && set -- "$@" -R "$repo"
  if ! info=$(cd "$dir" 2>/dev/null && gh "$@" --json baseRefName,headRefName,headRefOid 2>/dev/null) || [ -z "$info" ]; then
    add "PR を特定できない（gh pr view ${target:-<いまのブランチ>} が失敗した）。gh を使えて、PR が 1 つに決まるときだけ通す。"
    return 0
  fi
  base=$(printf '%s' "$info" | jq -r '.baseRefName // ""' 2>/dev/null)
  head_ref=$(printf '%s' "$info" | jq -r '.headRefName // ""' 2>/dev/null)
  head_sha=$(printf '%s' "$info" | jq -r '.headRefOid // ""' 2>/dev/null)
  if [ -z "$base" ] || [ -z "$head_ref" ] || [ -z "$head_sha" ]; then
    add "PR の base・head を読めない（${target:-<いまのブランチ>}）。"
    return 0
  fi

  set -- repo view
  [ -n "$repo" ] && set -- "$@" "$repo"
  if ! default=$(cd "$dir" 2>/dev/null && gh "$@" --json defaultBranchRef 2>/dev/null | jq -r '.defaultBranchRef.name // ""' 2>/dev/null) || [ -z "$default" ]; then
    add "リポジトリの default branch を読めない。base=$base がそれかどうか決められない。"
    return 0
  fi
  if [ "$base" = "$default" ]; then
    add "base が default branch（$base）の PR（head $head_ref）は、agent がマージしない。利用者が PR の QA の結果と判断の記録を確かめてマージする。PR の URL を利用者に渡して止まる。"
    return 0
  fi

  common=$(cd "$dir" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || common=""
  stamp="$common/bigdaddy/review-stamps/$head_ref"
  reviewed=""
  [ -n "$common" ] && [ -f "$stamp" ] && reviewed=$(head -n1 "$stamp")
  if [ "$reviewed" != "$head_sha" ]; then
    add "PR の head $head_ref @ $head_sha は、隔離レビューの記録（${reviewed:-なし}）と一致しない。差分全体を fresh な隔離レビュアーで再レビューし、blocking が 0 件になったら review-stamp.sh で記録し、push してから merge する。"
    return 0
  fi
  # 確かめてからマージするまでの間に head が動いても、GitHub 側で止まるようにする
  if [ -z "$match" ] || [ "${#match}" -lt 7 ] || [ "${head_sha#"$match"}" = "$head_sha" ]; then
    add "gh pr merge に --match-head-commit $head_sha を付ける（いまは「${match:-なし}」）。確かめてからマージするまでの間に head が動いても、レビュー済みの head だけが入るようにする。"
  fi
  return 0
}

# --git-dir・GIT_DIR= で別のリポジトリを指す形に対応して、check_push_inner を呼ぶ
check_push() {
  gline=$1 gbase=$2
  gdir=""
  prev=""
  set -f
  # shellcheck disable=SC2086
  for tok in $gline; do
    case "$prev" in --git-dir) gdir=$(abs "$tok" "$gbase") ;; esac
    case "$tok" in
      --git-dir=*) gdir=$(abs "${tok#--git-dir=}" "$gbase") ;;
      GIT_DIR=*) gdir=$(abs "${tok#GIT_DIR=}" "$gbase") ;;
    esac
    prev=$tok
  done
  set +f
  if [ -n "$gdir" ]; then GIT_DIR=$gdir; export GIT_DIR; fi
  check_push_inner "$gline" "$gbase"
  unset GIT_DIR
  return 0
}

# git push の先が default branch なら理由を足す。$1 は 1 行、$2 は git の場所
check_push_inner() {
  pline=$1 pdir=$2
  set -f
  prev=""
  # shellcheck disable=SC2086
  for tok in $pline; do
    case "$prev" in -C) pdir=$(abs "$tok" "$pdir") ;; esac
    prev=$tok
  done
  set +f
  rest=$(printf '%s\n' "$pline" | sed -E 's/^.*(^|[[:space:]])git([[:space:]]+(-C|-c|--git-dir|--work-tree|--namespace)[[:space:]]+[^[:space:]]+|[[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)//')
  every="" npos=0 refs="" skip=""
  set -f
  # shellcheck disable=SC2086
  for tok in $rest; do
    case "$skip" in value) skip=""; continue ;; esac
    case "$tok" in
      --al*|--m*|--b*) every=1 ;;
      -o|--push-option|--repo|--receive-pack|--exec) skip=value ;;
      -*) ;;
      *) npos=$((npos + 1)); [ "$npos" -ge 2 ] && refs="$refs $tok" ;;
    esac
  done
  set +f

  default=$(git -C "$pdir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  [ -n "$default" ] || default=$(cd "$pdir" 2>/dev/null && gh repo view --json defaultBranchRef 2>/dev/null | jq -r '.defaultBranchRef.name // ""' 2>/dev/null)
  if [ -z "$default" ]; then
    add "git push の先が default branch かどうか決められない（origin/HEAD も gh repo view も読めない）。default branch を読めるときだけ通す。"
    return 0
  fi
  current=$(git -C "$pdir" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  hit=""
  [ -n "$every" ] && hit="--all・--mirror は default branch も送る"
  set -f
  # shellcheck disable=SC2086
  for ref in $refs; do
    ref=${ref#+}
    case "$ref" in *:*) dst=${ref#*:} ;; *) dst=$ref ;; esac
    dst=${dst#refs/heads/}
    dst=${dst#heads/}
    [ "$dst" = HEAD ] && dst=$current
    [ "$dst" = @ ] && dst=$current
    [ -z "$dst" ] && hit="$ref は一致するブランチを全部送る形で、default branch を含みうる"
    case "$dst" in *\**) hit="$ref はワイルドカードで default branch を含みうる" ;; esac
    [ "$dst" = "$default" ] && hit="$ref の送り先が default branch（$default）"
  done
  set +f
  # 同じコマンドの中でブランチを切り替えると、HEAD や現在のブランチが hook の見ている状態と変わる
  if printf '%s\n' "$text" | grep -Fqw -- "$default" && printf '%s\n' "$text" | grep -Eq '(^|[[:space:]])(checkout|switch|reset|merge|rebase|branch)([[:space:]]|$)'; then
    hit="同じコマンドの中に default branch（$default）の名前とブランチの切り替えがあり、送り先が切り替わりうる"
  fi
  if printf '%s\n' "$text" | grep -Eq '(^|[[:space:]])(checkout|switch)[[:space:]]+(-|@[[:space:]]+-[0-9]*)([[:space:]]|$)'; then
    hit="同じコマンドの中で直前のブランチへ切り替えていて、送り先が切り替わりうる"
  fi
  case " $pline " in
    *" push.default=matching "*|*" push.default=current "*) hit="push.default の指定で送り先が変わりうる" ;;
  esac
  for tok in $pline; do
    case "$tok" in
      remote.*.push=*)
        rv=${tok#*.push=}; rv=${rv#+}; rv=${rv##*:}; rv=${rv#refs/heads/}
        [ "$rv" = "$default" ] && hit="-c の remote.*.push が default branch を指している" ;;
    esac
  done
  # A6: 設定ファイルの送り先
  if [ -z "$refs" ]; then
    pdef=$(git -C "$pdir" config push.default 2>/dev/null || true)
    rpush=$(git -C "$pdir" config --get-regexp '^remote\..*\.push$' 2>/dev/null | sed 's|refs/heads/||g')
    if [ "$pdef" = matching ]; then hit="設定の push.default=matching は default branch も送る"; fi
    if [ -n "$rpush" ] && printf '%s\n' "$rpush" | grep -Eq "(^|[[:space:]:])$default([[:space:]]|\$)"; then
      hit="設定の remote.*.push が default branch を含む"
    fi
  fi
  if [ -z "$refs" ] && [ -n "$current" ]; then
    upstream=$(git -C "$pdir" config "branch.$current.merge" 2>/dev/null | sed 's|^refs/heads/||')
    if [ "$current" = "$default" ] || [ "$upstream" = "$default" ]; then
      hit="いまのブランチ（$current）の送り先が default branch（$default）"
    fi
  fi
  if [ -n "$hit" ]; then
    add "default branch（$default）への git push は、agent がしない（$hit）。変更は topic branch か作業ブランチの PR で出し、default branch へのマージは利用者がする。"
  fi
  return 0
}

base_dir=$cwd
merge_lines=0
tab_reason_added=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  set -f
  prev=""
  # shellcheck disable=SC2086
  for tok in $line; do
    case "$prev" in cd|pushd) base_dir=$(abs "$tok" "$base_dir") ;; esac
    prev=$tok
  done
  set +f
  if printf '%s\n' "$line" | grep -Eq "$git_subtree_push"; then
    add "git subtree push は、送り先が default branch かどうか確かめられないので使わない。"
  fi
  if [ -n "$tabid" ] && [ -z "$tab_reason_added" ] && printf '%s\n' "$line" | grep -Eq "$git_push|$git_subtree_push|$gh_pr_merge"; then
    add "既存のタブ（tab_id）で実行する push・merge は、前の cd の結果が見えず、送り先を確かめられない。tab_id を付けず、cwd を指定して実行する。"
    tab_reason_added=1
  fi
  if printf '%s\n' "$line" | grep -Eq "$git_push"; then
    check_push "$line" "$base_dir"
  fi
  if printf '%s\n' "$line" | grep -Eq "$gh_pr_merge"; then
    rest=$(printf '%s\n' "$line" | sed -E "s#^.*${gh_pr_merge}##")
    before=$(printf '%s\n' "$line" | sed -E "s#${gh_pr_merge}.*\$##")
    matched=$(printf '%s\n' "$line" | grep -Eo "$gh_pr_merge" | tail -n1)
    pre_repo=""
    prev=""
    set -f
    # shellcheck disable=SC2086
    for tok in $matched; do
      case "$prev" in -R|--repo) pre_repo=$tok ;; esac
      case "$tok" in --repo=*) pre_repo=${tok#--repo=} ;; -R=*) pre_repo=${tok#-R=} ;; -R?*) pre_repo=${tok#-R} ;; esac
      prev=$tok
    done
    set +f
    merge_lines=$((merge_lines + 1))
    check_merge "$rest" "$base_dir" "$before" "$pre_repo"
  fi
done <<EOF
$text
EOF

# gh api は、複数行の GraphQL やヒアドキュメントがあるので、コマンド全体を 1 行にして見る
flat=$(printf '%s' "$text" | tr '\n' ' ')
if printf '%s\n' "$flat" | grep -Eq "$gh_api"; then
  if printf '%s\n' "$flat" | grep -Eq '/merge|mergePullRequest|enablePullRequestAutoMerge'; then
    add "gh api で PR をマージする形は、base と head を確かめられないので使わない。gh pr merge を使う。"
  fi
  if printf '%s\n' "$flat" | grep -Eq '(-X|--method)[[:space:]=]*[A-Za-z]*(POST|PUT|PATCH|DELETE|post|put|patch|delete)|[[:space:]]-[fF][^[:space:]]*|[[:space:]](--field|--raw-field|--input)([[:space:]=]|$)' \
    && printf '%s\n' "$flat" | grep -Eq '/git/refs|/contents/|/branches/|/merges|updateRef|createRef|createCommitOnBranch|mergeBranch'; then
    add "gh api でブランチに直接書く形は、書き込み先が default branch かどうか確かめられないので使わない。git の push と PR を使う。"
  fi
fi

if [ "$merge_lines" -gt 0 ]; then
  # gh pr merge は、cd 以外のコマンドとつないで実行しない（確かめたあとに PR や head を変えられるため）
  others=$(printf '%s\n' "$text" | grep -Ev "$gh_pr_merge" | grep -Ev '^[[:space:]]*((cd|pushd)[[:space:]]+[^[:space:]]+)?[[:space:]]*$' || true)
  if [ -n "$others" ]; then
    add "gh pr merge は、cd 以外のコマンドとつなげない（確かめたあとに PR の base や head を変えられるため）。単独のコマンドで実行する。"
  fi
fi

[ -n "$reasons" ] || exit 0

reason="bigdaddy topic-merge-guard:
${reasons}"

jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
