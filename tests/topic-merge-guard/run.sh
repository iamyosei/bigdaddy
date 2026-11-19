#!/bin/sh
# gh pr merge の前の hook（topic-merge-guard.sh）を、一時 git リポジトリと偽の gh で確かめる。Jev も本物の gh も呼ばない。
# 使い方: sh tests/topic-merge-guard/run.sh
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
hook="$root/plugins/bigdaddy/hooks/topic-merge-guard.sh"
stamp="$root/plugins/bigdaddy/skills/review-triage-loop/scripts/review-stamp.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failed=1; }

fakebin="$tmp/bin"
mkdir -p "$fakebin"
cat > "$fakebin/gh" <<'EOF'
#!/bin/sh
# 偽の gh。FAKE_GH_BASE_13 は PR 13 だけ base を変える。FAKE_GH_BASE・FAKE_GH_HEAD_REF・FAKE_GH_HEAD_SHA・FAKE_GH_DEFAULT で返す値を決め、FAKE_GH_FAIL=1 で全部失敗させる。
[ "${FAKE_GH_FAIL:-}" = 1 ] && exit 1
echo "gh $*" >> "${FAKE_GH_LOG:-/dev/null}"
case "$1 $2" in
  "pr view")
    base=$FAKE_GH_BASE
    [ "$3" = 13 ] && base=${FAKE_GH_BASE_13:-$base}
    printf '{"baseRefName":"%s","headRefName":"%s","headRefOid":"%s"}\n' "$base" "$FAKE_GH_HEAD_REF" "$FAKE_GH_HEAD_SHA" ;;
  "repo view")
    [ "${FAKE_GH_DEFAULT_FAIL:-}" = 1 ] && exit 1
    printf '{"defaultBranchRef":{"name":"%s"}}\n' "${FAKE_GH_DEFAULT:-main}" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$fakebin/gh"

bash_input() { jq -n --arg c "$1" --arg d "$2" '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}, cwd: $d}'; }
run_hook() { bash_input "$1" "$2" | PATH="$fakebin:$PATH" "$hook"; }
denied() { printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; }

new_repo() {
  r="$tmp/$1"
  git init -q -b child/x "$r"
  git -C "$r" config user.email t@example.com
  git -C "$r" config user.name t
  echo a > "$r/a.txt"
  git -C "$r" add -A
  git -C "$r" commit -qm init
  echo "$r"
}

head_of() { git -C "$1" rev-parse HEAD; }

expect_allow() {
  out=$(run_hook "$2" "$3"); code=$?
  if [ "$code" = 0 ] && [ -z "$out" ]; then pass "$1"; else fail "$1 (exit $code, got: $out)"; fi
}

expect_deny() {
  out=$(run_hook "$2" "$3"); code=$?
  if [ "$code" = 0 ] && denied "$out"; then pass "$1"; else fail "$1 (exit $code, got: $out)"; fi
}

FAKE_GH_DEFAULT=main
export FAKE_GH_DEFAULT

r=$(new_repo repo)
(cd "$r" && "$stamp" >/dev/null)
sha=$(head_of "$r")
FAKE_GH_HEAD_REF=child/x
FAKE_GH_HEAD_SHA=$sha
export FAKE_GH_HEAD_REF FAKE_GH_HEAD_SHA

# (a) base が default branch なら止める。名前で決め打ちしない
FAKE_GH_BASE=main; export FAKE_GH_BASE
expect_deny "(a) base=main: denied" "gh pr merge 12 --squash" "$r"
out=$(run_hook "gh pr merge 12" "$r")
if printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q '利用者'; then pass "(a) deny reason sends the PR to 利用者"; else fail "(a) deny reason sends the PR to 利用者 (got: $out)"; fi
FAKE_GH_BASE=develop; FAKE_GH_DEFAULT=develop; export FAKE_GH_BASE FAKE_GH_DEFAULT
expect_deny "(a) default branch is develop, base=develop: denied" "gh pr merge 12" "$r"
FAKE_GH_BASE=main; export FAKE_GH_BASE
expect_allow "(b) default branch is develop, base=main is not it (stamped head): allowed" "gh pr merge 12 --match-head-commit $FAKE_GH_HEAD_SHA" "$r"
FAKE_GH_DEFAULT=main; export FAKE_GH_DEFAULT

# (b) base=topic で head が記録と一致すれば通す
FAKE_GH_BASE=topic/foo; export FAKE_GH_BASE
expect_allow "(b) base=topic, head == stamp: allowed" "gh pr merge 12 --squash --delete-branch --match-head-commit $FAKE_GH_HEAD_SHA" "$r"
expect_allow "(b) no PR argument (current branch): allowed" "gh pr merge --squash --match-head-commit $FAKE_GH_HEAD_SHA" "$r"
expect_allow "(b) PR URL: allowed" "gh pr merge https://github.com/o/r/pull/12 --squash --match-head-commit $FAKE_GH_HEAD_SHA" "$r"
expect_allow "(b) -R repo: allowed" "gh pr merge 12 -R o/r --squash --match-head-commit $FAKE_GH_HEAD_SHA" "$r"
expect_allow "(b) cd <repo> && gh pr merge from outside: allowed" "cd $r && gh pr merge 12 --match-head-commit $FAKE_GH_HEAD_SHA" "$tmp"

# (c) head が記録と一致しなければ止める
FAKE_GH_HEAD_SHA=0000000000000000000000000000000000000000; export FAKE_GH_HEAD_SHA
expect_deny "(c) head != stamp: denied" "gh pr merge 12 --squash" "$r"
FAKE_GH_HEAD_SHA=$sha; FAKE_GH_HEAD_REF=child/unstamped; export FAKE_GH_HEAD_SHA FAKE_GH_HEAD_REF
expect_deny "(c) no stamp for the head branch: denied" "gh pr merge 12" "$r"
FAKE_GH_HEAD_REF=child/x; export FAKE_GH_HEAD_REF
echo more >> "$r/a.txt"; git -C "$r" commit -qam more
FAKE_GH_HEAD_SHA=$(head_of "$r"); export FAKE_GH_HEAD_SHA
expect_deny "(c) commit after the stamp (PR head moved on): denied" "gh pr merge 12" "$r"
(cd "$r" && "$stamp" >/dev/null)
expect_allow "(c) re-stamped head: allowed" "gh pr merge 12 --match-head-commit $FAKE_GH_HEAD_SHA" "$r"
expect_deny "(c) outside any git repo: no stamp readable: denied" "gh pr merge 12" "$tmp"

# (d) gh が PR を返せなければ止める
out=$(FAKE_GH_FAIL=1 run_hook "gh pr merge 12" "$r"); code=$?
if [ "$code" = 0 ] && denied "$out"; then pass "(d) gh fails: denied"; else fail "(d) gh fails: denied (exit $code, got: $out)"; fi
out=$(FAKE_GH_DEFAULT_FAIL=1 run_hook "gh pr merge 12" "$r"); code=$?
if [ "$code" = 0 ] && denied "$out"; then pass "(d) default branch unreadable: denied"; else fail "(d) default branch unreadable: denied (exit $code, got: $out)"; fi
out=$(FAKE_GH_BASE= run_hook "gh pr merge 12" "$r"); code=$?
if [ "$code" = 0 ] && denied "$out"; then pass "(d) gh returns no base: denied"; else fail "(d) gh returns no base: denied (exit $code, got: $out)"; fi
if (PATH=/usr/bin:/bin command -v gh >/dev/null 2>&1); then
  echo "SKIP (d) gh not installed: gh is in /usr/bin or /bin on this machine"
else
  nogh="$tmp/nogh"
  mkdir -p "$nogh"
  ln -s "$(command -v jq)" "$nogh/jq"
  ln -s "$(command -v git)" "$nogh/git"
  out=$(bash_input "gh pr merge 12" "$r" | PATH="$nogh:/usr/bin:/bin" "$hook"); code=$?
  if [ "$code" = 0 ] && denied "$out"; then pass "(d) gh not installed: denied"; else fail "(d) gh not installed: denied (exit $code, got: $out)"; fi
fi

# (e) gh pr merge 以外は素通し。gh を呼ばない
log="$tmp/gh.log"; : > "$log"
FAKE_GH_LOG=$log; export FAKE_GH_LOG
FAKE_GH_BASE=main; export FAKE_GH_BASE
for c in "gh pr view 12" "gh pr create --base main" "gh pr list" "git merge topic/foo" "echo merged" "git status" "gh pr checks 12" "gh api repos/o/r/pulls/12"; do
  expect_allow "(e) not a merge: $c" "$c" "$r"
done
if [ ! -s "$log" ]; then pass "(e) gh is not called for non-merge commands"; else fail "(e) gh is not called for non-merge commands (log: $(cat "$log"))"; fi
unset FAKE_GH_LOG

# 曖昧な形と抜け道は止める側に倒す
FAKE_GH_BASE=topic/foo; export FAKE_GH_BASE
expect_deny "--auto: denied" "gh pr merge 12 --auto --squash" "$r"
expect_deny "two PR arguments: denied" "gh pr merge 7 8" "$r"
expect_deny "--body value that looks like a PR: denied" "gh pr merge 8 --body 'x 7'" "$r"
expect_deny "gh api pulls/N/merge: denied" "gh api -X PUT repos/o/r/pulls/12/merge" "$r"
expect_deny "gh api graphql mergePullRequest: denied" "gh api graphql -f query='mutation { mergePullRequest(input: {pullRequestId: \"x\"}) { clientMutationId } }'" "$r"
FAKE_GH_BASE_13=main; export FAKE_GH_BASE_13
expect_deny "chained: first merge is fine, second is main: denied" "gh pr merge 12 && gh pr merge 13 --squash" "$r"
unset FAKE_GH_BASE_13
FAKE_GH_BASE=main; export FAKE_GH_BASE
expect_deny "commit message that mentions gh pr merge: denied (止めすぎの側)" "git commit -m 'gh pr merge later'" "$r"
expect_deny "chained after another command: denied" "bun run lint && gh pr merge 12" "$r"
expect_deny "bash -c form: denied" "bash -c 'gh pr merge 12'" "$r"
expect_deny "absolute path gh: denied" "/opt/homebrew/bin/gh pr merge 12" "$r"
expect_deny "env prefix: denied" "GH_REPO=o/r gh pr merge 12" "$r"
expect_deny "command substitution: denied" "out=\$(gh pr merge 12 2>&1); echo \"\$out\"" "$r"

# レビューで見つかった抜け道
r=$(new_repo loopholes)
(cd "$r" && "$stamp" >/dev/null)
FAKE_GH_BASE=topic/foo; FAKE_GH_HEAD_REF=child/x; FAKE_GH_HEAD_SHA=$(head_of "$r"); export FAKE_GH_BASE FAKE_GH_HEAD_REF FAKE_GH_HEAD_SHA
sha=$FAKE_GH_HEAD_SHA
expect_allow "baseline: topic, stamped, pinned head: allowed" "gh pr merge 12 --match-head-commit $sha" "$r"
expect_allow "--merge (resolution child): allowed" "gh pr merge 12 --merge --match-head-commit $sha" "$r"
FAKE_GH_BASE=main; export FAKE_GH_BASE
expect_deny "--merge with base=default branch: denied" "gh pr merge 12 --merge --match-head-commit $sha" "$r"
FAKE_GH_BASE=topic/foo; export FAKE_GH_BASE
expect_deny "--merge with a head that differs from the stamp: denied" "gh pr merge 12 --merge --match-head-commit 1111111111111111111111111111111111111111" "$r"
expect_allow "short SHA (7+) pinned head: allowed" "gh pr merge 12 --match-head-commit $(printf %s "$sha" | cut -c1-10)" "$r"
expect_allow "redirect 2>&1: allowed" "gh pr merge 12 --match-head-commit $sha 2>&1" "$r"
expect_deny "no --match-head-commit: denied" "gh pr merge 12 --squash" "$r"
expect_deny "--match-head-commit with another SHA: denied" "gh pr merge 12 --match-head-commit 1111111111111111111111111111111111111111" "$r"
expect_deny "edit base then merge in one command: denied" "gh pr edit 12 --base main && gh pr merge 12 --match-head-commit $sha" "$r"
expect_deny "push then merge in one command: denied" "git push origin child/x && gh pr merge 12 --match-head-commit $sha" "$r"
expect_deny "xargs gh pr merge: denied" "echo 13 | xargs gh pr merge --match-head-commit $sha" "$r"
log="$tmp/gh2.log"; : > "$log"; FAKE_GH_LOG=$log; export FAKE_GH_LOG
run_hook "gh pr merge 12 -Rother/repo --match-head-commit $sha" "$r" >/dev/null
if grep -q 'pr view 12 -R other/repo' "$log"; then pass "-Rother/repo is passed to gh pr view"; else fail "-Rother/repo is passed to gh pr view (log: $(cat "$log"))"; fi
: > "$log"
run_hook "GH_REPO=other/repo gh pr merge 12 --match-head-commit $sha" "$r" >/dev/null
if grep -q 'pr view 12 -R other/repo' "$log"; then pass "GH_REPO prefix is passed to gh pr view"; else fail "GH_REPO prefix is passed to gh pr view (log: $(cat "$log"))"; fi
: > "$log"
run_hook "gh pr merge https://github.com/other/repo/pull/12 --match-head-commit $sha" "$r" >/dev/null
if grep -q 'repo view other/repo' "$log"; then pass "PR URL: default branch is read from the URL's repo"; else fail "PR URL: default branch is read from the URL's repo (log: $(cat "$log"))"; fi
unset FAKE_GH_LOG

# jq が無いとき: merge と push を含む入力は止める。それ以外は通す
nojq="$tmp/nojq"
mkdir -p "$nojq"; ln -s "$(command -v cat)" "$nojq/cat"
out=$(bash_input "gh pr merge 12" "$r" | PATH="$nojq" /bin/sh "$hook" 2>/dev/null); code=$?
if [ "$code" = 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then pass "no jq: merge denied"; else fail "no jq: merge denied (exit $code, got: $out)"; fi
out=$(printf '%s' '{"tool_input":{"command":"ls"}}' | PATH="$nojq" /bin/sh "$hook" 2>/dev/null); code=$?
if [ "$code" = 0 ] && [ -z "$out" ]; then pass "no jq: other commands allowed"; else fail "no jq: other commands allowed (exit $code, got: $out)"; fi

# default branch への git push は、記録があっても止める。topic・作業ブランチへの push は通す
mk_pushrepo() {
  pr=$(new_repo "$1")
  git -C "$pr" branch -q -m "$2"
  git -C "$pr" update-ref refs/remotes/origin/"$2" HEAD
  git -C "$pr" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/"$2"
  echo "$pr"
}
r=$(mk_pushrepo push-main main)
git -C "$r" checkout -qb topic/foo
(cd "$r" && "$stamp" >/dev/null)
expect_allow "push: plain push from a topic branch: allowed" "git push" "$r"
expect_allow "push: origin <topic> from a topic branch: allowed" "git push -u origin topic/foo" "$r"
expect_allow "push: HEAD:<work branch>: allowed" "git push origin HEAD:refs/heads/claude/work" "$r"
expect_deny "push: origin main: denied" "git push origin main" "$r"
expect_deny "push: HEAD:main: denied" "git push origin HEAD:main" "$r"
expect_deny "push: HEAD:refs/heads/main: denied" "git push origin HEAD:refs/heads/main" "$r"
expect_deny "push: topic:main: denied" "git push origin topic/foo:main" "$r"
expect_deny "push: +main (force): denied" "git push --force origin +main" "$r"
expect_deny "push: delete main: denied" "git push origin :main" "$r"
expect_deny "push: --all: denied" "git push --all origin" "$r"
expect_deny "push: wildcard refspec: denied" "git push origin refs/heads/*:refs/heads/*" "$r"
expect_deny "push: git -C <dir> push origin main from elsewhere: denied" "git -C $r push origin main" "$tmp"
expect_deny "push: chained: denied" "bun run lint && git push origin main" "$r"
expect_deny "push: checkout the default branch, merge, then plain push: denied" "git checkout main && git merge topic/foo && git push" "$r"
git -C "$r" checkout -q main
expect_deny "push: plain push from the default branch (stamped): denied" "git push" "$r"
expect_deny "push: origin HEAD from the default branch: denied" "git push origin HEAD" "$r"
git -C "$r" checkout -q topic/foo
git -C "$r" config branch.topic/foo.merge refs/heads/main
expect_deny "push: plain push whose upstream is the default branch: denied" "git push" "$r"

r=$(mk_pushrepo push-develop develop)
git -C "$r" checkout -qb topic/foo
expect_allow "push: default branch is develop, push main (not it): allowed" "git push origin main" "$r"
expect_deny "push: default branch is develop, push develop: denied" "git push origin HEAD:develop" "$r"

r=$(new_repo push-unknown)
git -C "$r" checkout -qb topic/foo
out=$(FAKE_GH_FAIL=1 run_hook "git push origin topic/foo" "$r"); code=$?
if [ "$code" = 0 ] && denied "$out"; then pass "push: default branch unreadable: denied"; else fail "push: default branch unreadable: denied (exit $code, got: $out)"; fi
expect_allow "push: default branch from gh when origin/HEAD is unset: allowed" "git push origin topic/foo" "$r"

# 2 回目のレビューで見つかった抜け道
r=$(mk_pushrepo push-main2 main)
git -C "$r" checkout -qb topic/foo
for c in "git checkout main && git merge topic/foo && git push origin HEAD" "git switch main && git push -u origin HEAD" "git checkout main && git push origin @" \
  "git push origin HEAD:heads/main" "git push origin :" "git push origin topic/foo:" "git -c push.default=matching push" "git subtree push --prefix d origin main" \
  "git push origin @:main"; do
  expect_deny "push loophole: $c" "$c" "$r"
done
expect_allow "push: plain push from a topic branch is still allowed" "git push" "$r"
sha=$(head_of "$r"); FAKE_GH_BASE=topic/foo; FAKE_GH_HEAD_REF=child/x; FAKE_GH_HEAD_SHA=$sha; export FAKE_GH_BASE FAKE_GH_HEAD_REF FAKE_GH_HEAD_SHA
git -C "$r" checkout -q child/x 2>/dev/null || git -C "$r" checkout -qb child/x
(cd "$r" && "$stamp" >/dev/null)
expect_deny "merge: base edit chained with & : denied" "gh pr edit 12 --base main & gh pr merge 12 --match-head-commit $sha" "$r"
expect_deny "merge: --auto=true: denied" "gh pr merge 12 --auto=true --match-head-commit $sha" "$r"
expect_allow "merge: --disable-auto alone: allowed" "gh pr merge 12 --disable-auto" "$r"
expect_allow "merge: redirect 2>&1 still allowed" "gh pr merge 12 --match-head-commit $sha 2>&1" "$r"
expect_deny "gh api PATCH git/refs/heads/main: denied" "gh api -X PATCH repos/o/r/git/refs/heads/main -f sha=abc" "$r"
expect_deny "gh api PUT contents on a branch: denied" "gh api -X PUT repos/o/r/contents/README.md -f branch=main -f message=m" "$r"
expect_deny "gh api graphql updateRef: denied" "gh api graphql -f query='mutation { updateRef(input: {}) { clientMutationId } }'" "$r"
expect_allow "gh api GET of contents: allowed" "gh api repos/o/r/contents/README.md" "$r"

# 3 回目のレビューで見つかった抜け道
FAKE_GH_BASE=main; export FAKE_GH_BASE
expect_deny "gh pr -R <repo> merge (base=default): denied" "gh pr -R o/r merge 12 --match-head-commit $sha" "$r"
expect_deny "gh pr --repo=<repo> merge (base=default): denied" "gh pr --repo=o/r merge 12 --match-head-commit $sha" "$r"
expect_deny "gh -R <repo> pr merge (base=default): denied" "gh -R o/r pr merge 12 --match-head-commit $sha" "$r"
FAKE_GH_BASE=topic/foo; export FAKE_GH_BASE
log="$tmp/gh3.log"; : > "$log"; FAKE_GH_LOG=$log; export FAKE_GH_LOG
run_hook "gh pr -R o/r merge 12 --match-head-commit $sha" "$r" >/dev/null
if grep -q 'pr view 12 -R o/r' "$log"; then pass "gh pr -R <repo> merge: repo is passed to gh pr view"; else fail "gh pr -R <repo> merge: repo is passed to gh pr view (log: $(cat "$log"))"; fi
unset FAKE_GH_LOG
expect_deny "multi-line GraphQL mergePullRequest: denied" "gh api graphql -f query='
mutation { mergePullRequest(input: {pullRequestId: \"x\"}) { clientMutationId } }'" "$r"
expect_deny "multi-line GraphQL updateRef: denied" "gh api graphql -f query='
mutation { updateRef(input: {}) { clientMutationId } }'" "$r"
expect_deny "heredoc GraphQL updateRef: denied" "gh api graphql --input - <<EOF
{\"query\":\"mutation{updateRef(input:{}){clientMutationId}}\"}
EOF" "$r"
expect_deny "-fquery=... updateRef: denied" "gh api graphql -fquery='mutation { updateRef(input:{}) { clientMutationId } }'" "$r"
expect_deny "-XPATCH git/refs: denied" "gh api -XPATCH repos/o/r/git/refs/heads/main -f sha=abc" "$r"
out=$(bash_input "gh api graphql -f query=updateRef" "$r" | PATH="$nojq" /bin/sh "$hook" 2>/dev/null); code=$?
if [ "$code" = 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then pass "no jq: gh api denied"; else fail "no jq: gh api denied (exit $code, got: $out)"; fi

r=$(mk_pushrepo push-config main)
git -C "$r" checkout -qb topic/foo
git -C "$r" config push.default matching
expect_deny "push: push.default=matching in config: denied" "git push" "$r"
git -C "$r" config --unset push.default
git -C "$r" config remote.origin.push HEAD:refs/heads/main
expect_deny "push: remote.origin.push targets the default branch: denied" "git push" "$r"
git -C "$r" config --unset remote.origin.push
expect_deny "push: checkout - then push HEAD: denied" "git checkout - && git push origin HEAD" "$r"
expect_deny "push: switch - then push HEAD: denied" "git switch - && git push origin HEAD" "$r"
expect_allow "push: unrelated config does not stop a topic push: allowed" "git push" "$r"

# 4 回目のレビューで見つかった抜け道
hooks_json="$root/plugins/bigdaddy/hooks/hooks.json"
if jq -e '[.hooks.PreToolUse[] | select(.matcher | test("Bash")) | .hooks[].command | select(test("topic-merge-guard"))] | length == 1' "$hooks_json" >/dev/null 2>&1; then pass "hooks.json registers topic-merge-guard for Bash"; else fail "hooks.json registers topic-merge-guard for Bash"; fi
for t in Bash Monitor mcp__terminal__run_in_terminal; do
  if jq -e --arg t "$t" '[.hooks.PreToolUse[] | select(.matcher as $m | $t | test("^(" + $m + ")$")) | .hooks[].command | select(test("topic-merge-guard"))] | length >= 1' "$hooks_json" >/dev/null 2>&1; then pass "hooks.json matcher covers $t"; else fail "hooks.json matcher covers $t"; fi
done
if jq -e --arg t mcp__github__merge_pull_request '[.hooks.PreToolUse[] | select(.matcher as $m | $t | test("^(" + $m + ")$")) | .hooks[].command | select(test("topic-merge-guard"))] | length >= 1' "$hooks_json" >/dev/null 2>&1; then pass "hooks.json matcher covers a merge MCP tool"; else fail "hooks.json matcher covers a merge MCP tool"; fi
for ev in SessionStart PreToolUse PostToolUse Stop; do
  if jq -e --arg e "$ev" '.hooks[$e] | length >= 1' "$hooks_json" >/dev/null 2>&1; then pass "hooks.json keeps the $ev hooks"; else fail "hooks.json keeps the $ev hooks"; fi
done

r=$(mk_pushrepo push-abbrev main)
git -C "$r" checkout -qb topic/foo
expect_deny "push: --al (abbreviated --all): denied" "git push --al origin" "$r"
expect_deny "push: --mirr (abbreviated --mirror): denied" "git push --mirr origin" "$r"
expect_deny "push: --bran (abbreviated --branches): denied" "git push --bran origin" "$r"
expect_deny "push: -c remote.origin.push=...:main: denied" "git -c remote.origin.push=refs/heads/topic/foo:refs/heads/main push origin" "$r"
expect_allow "push: -c remote.origin.push to a topic: allowed" "git -c remote.origin.push=refs/heads/topic/foo:refs/heads/topic/foo push origin" "$r"
mcp_cmd_input() { jq -n --arg t "$1" --arg c "$2" --arg d "$3" '{hook_event_name: "PreToolUse", tool_name: $t, tool_input: {command: $c}, cwd: $d}'; }
for tool in mcp__terminal__run_in_terminal Monitor; do
  out=$(mcp_cmd_input "$tool" "git push origin HEAD:main" "$r" | PATH="$fakebin:$PATH" "$hook"); code=$?
  if [ "$code" = 0 ] && denied "$out"; then pass "$tool: push to the default branch: denied"; else fail "$tool: push to the default branch: denied (exit $code, got: $out)"; fi
  out=$(mcp_cmd_input "$tool" "git status" "$r" | PATH="$fakebin:$PATH" "$hook"); code=$?
  if [ "$code" = 0 ] && [ -z "$out" ]; then pass "$tool: unrelated command: allowed"; else fail "$tool: unrelated command: allowed (exit $code, got: $out)"; fi
done

# 5 回目のレビューで見つかった抜け道
r=$(mk_pushrepo push-gitdir main)
git -C "$r" checkout -qb topic/foo
git -C "$r" worktree add -q -b feat/y "$tmp/gitdir-wt" topic/foo 2>/dev/null
git -C "$r" checkout -q main
expect_deny "push: --git-dir=<main repo> from a topic worktree: denied" "git --git-dir=$r/.git push origin HEAD" "$tmp/gitdir-wt"
expect_deny "push: --git-dir <main repo> --work-tree: denied" "git --git-dir $r/.git --work-tree $r push" "$tmp/gitdir-wt"
expect_deny "push: GIT_DIR=<main repo> git push: denied" "GIT_DIR=$r/.git git push" "$tmp/gitdir-wt"
expect_allow "push: topic worktree plain push: allowed" "git push" "$tmp/gitdir-wt"
term_input() { jq -n --arg c "$1" --arg d "$2" --arg td "$3" --arg tab "$4" '{hook_event_name: "PreToolUse", tool_name: "mcp__terminal__run_in_terminal", tool_input: ({command: $c} + (if $td != "" then {cwd: $td} else {} end) + (if $tab != "" then {tab_id: $tab} else {} end)), cwd: $d}'; }
out=$(term_input "git push" "$tmp/gitdir-wt" "$r" "" | PATH="$fakebin:$PATH" "$hook"); code=$?
if [ "$code" = 0 ] && denied "$out"; then pass "terminal tool: tool_input.cwd on the default branch: denied"; else fail "terminal tool: tool_input.cwd on the default branch: denied (exit $code, got: $out)"; fi
out=$(term_input "git push" "$r" "$tmp/gitdir-wt" "" | PATH="$fakebin:$PATH" "$hook"); code=$?
if [ "$code" = 0 ] && [ -z "$out" ]; then pass "terminal tool: tool_input.cwd on a topic worktree: allowed"; else fail "terminal tool: tool_input.cwd on a topic worktree: allowed (exit $code, got: $out)"; fi
out=$(term_input "git push" "$tmp/gitdir-wt" "" "tab1" | PATH="$fakebin:$PATH" "$hook"); code=$?
if [ "$code" = 0 ] && denied "$out"; then pass "terminal tool: push in an existing tab (tab_id): denied"; else fail "terminal tool: push in an existing tab (tab_id): denied (exit $code, got: $out)"; fi
out=$(term_input "git status" "$tmp/gitdir-wt" "" "tab1" | PATH="$fakebin:$PATH" "$hook"); code=$?
if [ "$code" = 0 ] && [ -z "$out" ]; then pass "terminal tool: unrelated command in a tab: allowed"; else fail "terminal tool: unrelated command in a tab: allowed (exit $code, got: $out)"; fi

# ブランチに直接書く MCP ツール
mcp_cwd_input() { jq -n --arg t "$1" --argjson i "$2" --arg d "$3" '{hook_event_name: "PreToolUse", tool_name: $t, tool_input: $i, cwd: $d}'; }
r=$(mk_pushrepo mcp-write main)
out=$(mcp_cwd_input mcp__github__push_files '{"branch":"main","files":[]}' "$r" | "$hook"); code=$?
if [ "$code" = 0 ] && denied "$out"; then pass "mcp: push_files to the default branch: denied"; else fail "mcp: push_files to the default branch: denied (exit $code, got: $out)"; fi
out=$(mcp_cwd_input mcp__github__create_or_update_file '{"path":"a"}' "$r" | "$hook"); code=$?
if [ "$code" = 0 ] && denied "$out"; then pass "mcp: create_or_update_file without a branch: denied"; else fail "mcp: create_or_update_file without a branch: denied (exit $code, got: $out)"; fi
out=$(mcp_cwd_input mcp__github__create_or_update_file '{"path":"a","branch":"topic/foo"}' "$r" | "$hook"); code=$?
if [ "$code" = 0 ] && [ -z "$out" ]; then pass "mcp: create_or_update_file to a topic branch: allowed"; else fail "mcp: create_or_update_file to a topic branch: allowed (exit $code, got: $out)"; fi
out=$(mcp_cwd_input mcp__github__merge_pull_request '{"enabled":false}' "$r" | "$hook"); code=$?
if [ "$code" = 0 ] && denied "$out"; then pass "mcp: enabled=false does not excuse other merge tools: denied"; else fail "mcp: enabled=false does not excuse other merge tools: denied (exit $code, got: $out)"; fi

# マージする MCP ツール
mcp_input() { jq -n --arg t "$1" --argjson i "$2" '{hook_event_name: "PreToolUse", tool_name: $t, tool_input: $i, cwd: "/"}'; }
out=$(mcp_input mcp__github__merge_pull_request '{"pullNumber":1}' | "$hook"); code=$?
if [ "$code" = 0 ] && denied "$out"; then pass "mcp: merge tool: denied"; else fail "mcp: merge tool: denied (exit $code, got: $out)"; fi
out=$(mcp_input mcp__ccd_pr__set_auto_merge '{"enabled":true,"url":"u"}' | "$hook"); code=$?
if [ "$code" = 0 ] && denied "$out"; then pass "mcp: enabling auto-merge: denied"; else fail "mcp: enabling auto-merge: denied (exit $code, got: $out)"; fi
out=$(mcp_input mcp__ccd_pr__set_auto_merge '{"enabled":false,"url":"u"}' | "$hook"); code=$?
if [ "$code" = 0 ] && [ -z "$out" ]; then pass "mcp: disabling auto-merge: allowed"; else fail "mcp: disabling auto-merge: allowed (exit $code, got: $out)"; fi
out=$(mcp_input mcp__github__get_pull_request '{"pullNumber":1}' | "$hook"); code=$?
if [ "$code" = 0 ] && [ -z "$out" ]; then pass "mcp: non-merge tool: allowed"; else fail "mcp: non-merge tool: allowed (exit $code, got: $out)"; fi

exit "$failed"
