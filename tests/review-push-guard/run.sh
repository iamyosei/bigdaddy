#!/bin/sh
# 隔離レビューの記録（review-stamp.sh）と push 前の hook（review-push-guard.sh）を、一時 git リポジトリで確かめる。Jev は呼ばない。
# 使い方: sh tests/review-push-guard/run.sh
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
hook="$root/plugins/bigdaddy/hooks/review-push-guard.sh"
stamp="$root/plugins/bigdaddy/skills/review-triage-loop/scripts/review-stamp.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failed=1; }

bash_input() { jq -n --arg c "$1" --arg d "$2" '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}, cwd: $d}'; }
run_hook() { bash_input "$1" "$2" | "$hook"; }
denied() { printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; }

new_repo() {
  r="$tmp/$1"
  git init -q -b feature/x "$r"
  git -C "$r" config user.email t@example.com
  git -C "$r" config user.name t
  mkdir -p "$r/src" "$r/tests" "$r/docs"
  echo a > "$r/src/app.ts"
  echo a > "$r/src/Button.tsx"
  echo a > "$r/tests/app.test.ts"
  echo a > "$r/docs/guide.md"
  echo a > "$r/README.md"
  git -C "$r" add -A
  git -C "$r" commit -qm init
  echo "$r"
}

commit_change() {
  r=$1; shift
  for f in "$@"; do mkdir -p "$(dirname "$r/$f")"; echo "change $$" >> "$r/$f"; done
  git -C "$r" add -A
  git -C "$r" commit -qm change
}

expect_allow() {
  out=$(run_hook "$2" "$3"); code=$?
  if [ "$code" = 0 ] && [ -z "$out" ]; then pass "$1"; else fail "$1 (exit $code, got: $out)"; fi
}

expect_deny() {
  out=$(run_hook "$2" "$3"); code=$?
  if [ "$code" = 0 ] && denied "$out"; then pass "$1"; else fail "$1 (exit $code, got: $out)"; fi
}

r=$(new_repo no-stamp)
commit_change "$r" src/app.ts
expect_allow "no stamp: push allowed" "git push" "$r"

r=$(new_repo same-head)
(cd "$r" && "$stamp" >/dev/null)
expect_allow "stamp == HEAD: push allowed" "git push -u origin feature/x" "$r"

r=$(new_repo docs-only)
(cd "$r" && "$stamp" >/dev/null)
commit_change "$r" tests/app.test.ts docs/guide.md README.md tests/new_case.ts
expect_allow "tests and docs only: push allowed" "git push" "$r"

r=$(new_repo behavior)
(cd "$r" && "$stamp" >/dev/null)
commit_change "$r" src/app.ts README.md
out=$(run_hook "git push" "$r"); code=$?
reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
if [ "$code" = 0 ] && denied "$out" && printf '%s' "$reason" | grep -q 'src/app.ts' && printf '%s' "$reason" | grep -q '再レビュー → スタンプ'; then
  pass "behavior change: push denied with re-review message"
else
  fail "behavior change: push denied with re-review message (exit $code, got: $out)"
fi
if printf '%s' "$reason" | grep -q 'スクリーンショット'; then fail "non-UI change: no screenshot message"; else pass "non-UI change: no screenshot message"; fi
if printf '%s' "$reason" | grep -q 'README.md'; then fail "docs are not listed as behavior changes"; else pass "docs are not listed as behavior changes"; fi
expect_deny "git -C <dir> push from elsewhere: denied" "git -C $r push origin HEAD" "$tmp"
expect_deny "chained push: denied" "bun run lint && git push" "$r"

for c in "git status" "git commit -m push" "echo pushed" "git log --oneline"; do
  expect_allow "not a push: $c" "$c" "$r"
done

r=$(new_repo ui)
(cd "$r" && "$stamp" >/dev/null)
commit_change "$r" src/Button.tsx
out=$(run_hook "git push" "$r"); code=$?
reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
if [ "$code" = 0 ] && denied "$out" && printf '%s' "$reason" | grep -q 'スクリーンショット' && printf '%s' "$reason" | grep -q 'src/Button.tsx'; then
  pass "UI change: screenshot message"
else
  fail "UI change: screenshot message (exit $code, got: $out)"
fi

r=$(new_repo skill-md)
(cd "$r" && "$stamp" >/dev/null)
commit_change "$r" plugins/p/skills/s/SKILL.md
expect_deny "agent instructions (SKILL.md) count as behavior: denied" "git push" "$r"

r=$(new_repo restamp)
(cd "$r" && "$stamp" >/dev/null)
commit_change "$r" src/app.ts
(cd "$r" && "$stamp" >/dev/null)
expect_allow "re-stamp after re-review: push allowed" "git push" "$r"

r=$(new_repo other-branch)
(cd "$r" && "$stamp" >/dev/null)
git -C "$r" checkout -qb feature/y
commit_change "$r" src/app.ts
expect_allow "stamp is per branch: other branch allowed" "git push" "$r"

r=$(new_repo worktree)
git -C "$r" checkout -qb main
git -C "$r" worktree add -q "$tmp/wt" feature/x
(cd "$tmp/wt" && "$stamp" >/dev/null)
commit_change "$tmp/wt" src/app.ts
expect_deny "stamp in a linked worktree: denied" "git push" "$tmp/wt"

r=$(new_repo dirty)
echo dirty >> "$r/src/app.ts"
if (cd "$r" && "$stamp" >/dev/null 2>&1); then fail "stamp refuses uncommitted changes"; else pass "stamp refuses uncommitted changes"; fi

r=$(new_repo missing-sha)
(cd "$r" && "$stamp" >/dev/null)
echo 0000000000000000000000000000000000000000 > "$(git -C "$r" rev-parse --path-format=absolute --git-common-dir)/bigdaddy/review-stamps/feature/x"
commit_change "$r" README.md
expect_deny "stamped sha missing: denied" "git push" "$r"

expect_allow "outside git: push allowed" "git push" "$tmp"

r=$(new_repo send-from-elsewhere)
(cd "$r" && "$stamp" >/dev/null)
git -C "$r" checkout -qb main
git -C "$r" worktree add -q -b claude/fix "$tmp/send-wt" feature/x
commit_change "$tmp/send-wt" src/app.ts
expect_deny "worktree branch pushing HEAD:feature/x: denied" "git push origin HEAD:feature/x" "$tmp/send-wt"
expect_deny "worktree branch pushing claude/fix:feature/x: denied" "git push origin claude/fix:feature/x" "$r"
git -C "$tmp/send-wt" config branch.claude/fix.remote origin
git -C "$tmp/send-wt" config branch.claude/fix.merge refs/heads/feature/x
expect_deny "plain push to an upstream that is stamped: denied" "git push" "$tmp/send-wt"
git -C "$r" checkout -q --detach feature/x
commit_change "$r" src/app.ts
expect_deny "detached HEAD with new commits pushing HEAD:feature/x: denied" "git push origin HEAD:feature/x" "$r"

r=$(new_repo forms)
(cd "$r" && "$stamp" >/dev/null)
commit_change "$r" src/app.ts
expect_deny "cd <repo> && git push from outside: denied" "cd $r && git push" "$tmp"
expect_deny "git -c opt push: denied" "git -c push.default=current push" "$r"
expect_deny "git --no-pager push: denied" "git --no-pager push" "$r"
expect_deny "quoted -C: denied" "git -C '$r' push" "$tmp"
expect_deny "GIT_DIR=... git push: denied" "GIT_DIR=$r/.git git push" "$tmp"
expect_deny "/usr/bin/git push: denied" "/usr/bin/git push" "$r"
expect_deny "push --all: denied" "git push --all origin" "$r"
expect_deny "refspec HEAD:branch: denied" "git push origin HEAD:refs/heads/feature/x" "$r"
expect_allow "commit message about pushing: allowed" "git commit -m \"push later\"" "$r"
for c in "git push -u origin 2>&1" "git push origin 2>&1 | tail -5" "git push origin 2> err.log" "git push origin > log" \
  "git push origin @" "out=\$(git push 2>&1); echo \"\$out\"" "echo \"\$(git push origin)\"" "\\git push" "bash -c 'git push'" "sh -c \"git push origin\"" "git push origin \\
feature/x"; do
  expect_deny "push form: $c" "$c" "$r"
done
expect_deny "pushd <repo> && git push: denied" "pushd $r && git push" "$tmp"
git -C "$r" branch -q side
git -C "$r" checkout -q side
expect_allow "pushing an unstamped branch from it: allowed" "git push origin side" "$r"
expect_deny "pushing the stamped branch from another branch: denied" "git push origin feature/x" "$r"
git -C "$r" checkout -q --detach feature/x
expect_deny "detached HEAD pushing HEAD:feature/x: denied" "git push origin HEAD:feature/x" "$r"

home="$tmp/home"
mkdir -p "$home"
r=$(new_repo tilde)
mv "$r" "$home/repo"
(cd "$home/repo" && "$stamp" >/dev/null)
commit_change "$home/repo" src/app.ts
out=$(bash_input "cd ~/repo && git push" "$tmp" | HOME="$home" "$hook")
if denied "$out"; then pass "cd ~/repo && git push: denied"; else fail "cd ~/repo && git push: denied (got: $out)"; fi
out=$(bash_input "git -C ~/repo push" "$tmp" | HOME="$home" "$hook")
if denied "$out"; then pass "git -C ~/repo push: denied"; else fail "git -C ~/repo push: denied (got: $out)"; fi

for f in src/README.ts api/openapi.spec.yaml .env.test.local src/app/docs/page.tsx src/features/test/handler.ts spec/openapi.yaml api/spec/openapi.yaml docs/docusaurus.config.js app/blog/page.mdx app/docs/page.mdx pages/docs/intro.md src/llm/system-prompt.md CLAUDE.local.md GEMINI.md AGENT.md CONVENTIONS.md; do
  r=$(new_repo "cls-$(echo "$f" | tr '/.' '__')")
  (cd "$r" && "$stamp" >/dev/null)
  commit_change "$r" "$f"
  expect_deny "behavior file: $f" "git push" "$r"
done
for f in src/app.test.ts packages/a/README.md docs/a/b.md CHANGELOG.md tests/fixtures/seed.sql test/unit/a.ts src/__tests__/a.ts; do
  r=$(new_repo "cls-$(echo "$f" | tr '/.' '__')")
  (cd "$r" && "$stamp" >/dev/null)
  commit_change "$r" "$f"
  expect_allow "test or doc file: $f" "git push" "$r"
done

r=$(new_repo txt)
(cd "$r" && "$stamp" >/dev/null)
commit_change "$r" requirements.txt
expect_deny "requirements.txt counts as behavior: denied" "git push" "$r"

r=$(new_repo agent-md)
(cd "$r" && "$stamp" >/dev/null)
commit_change "$r" plugins/p/hooks/ctx.md
expect_deny "hook context Markdown counts as behavior: denied" "git push" "$r"

r=$(new_repo rename)
(cd "$r" && "$stamp" >/dev/null)
git -C "$r" mv src/app.ts tests/app.ts
git -C "$r" commit -qm mv
expect_deny "renaming code into tests/: denied" "git push" "$r"

exit "$failed"
