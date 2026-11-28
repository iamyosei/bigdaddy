#!/bin/sh
# plugin cache の SKILL.md とプレイブックを Bash の読み取りコマンドで読むのを止める hook（skill-read-guard.sh）を、入力 JSON を流して確かめる。
# pstack の skill は Skill ツールで起動できないので Read ツール、bigdaddy・yomiyasu の skill は Skill ツールへ誘導することも確かめる。
# 使い方: sh tests/skill-read-guard/run.sh
# shellcheck disable=SC2016
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
hook="${HOOK:-$root/plugins/bigdaddy/hooks/skill-read-guard.sh}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failed=1; }

bash_input() { jq -n --arg c "$1" '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}}'; }
run_hook() { bash_input "$1" | "$hook"; }
denied() { printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; }

expect_allow() {
  out=$(run_hook "$2"); code=$?
  if [ "$code" = 0 ] && [ -z "$out" ]; then pass "$1"; else fail "$1 (exit $code, got: $out)"; fi
}

# $3 以降は reason に含まれるべき文字列
expect_deny() {
  name=$1; command=$2; shift 2
  out=$(run_hook "$command"); code=$?
  if [ "$code" != 0 ] || ! denied "$out"; then fail "$name (exit $code, got: $out)"; return; fi
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason')
  case "$reason" in "bigdaddy skill-read-guard:"*) ;; *) fail "$name (reason does not start with the hook name: $reason)"; return ;; esac
  for needle in "$@"; do
    case "$reason" in
      *"$needle"*) ;;
      *) fail "$name (reason lacks '$needle': $reason)"; return ;;
    esac
  done
  pass "$name"
}

# $3 は reason に含まれてはならない文字列
expect_deny_without() {
  name=$1; command=$2; needle=$3
  out=$(run_hook "$command")
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
  case "$reason" in
    "") fail "$name (not denied)" ;;
    *"$needle"*) fail "$name (reason has '$needle': $reason)" ;;
    *) pass "$name" ;;
  esac
}

c=/Users/x/.claude/plugins/cache/bigdaddy
pb="$c/pstack/0.15.32/skills/poteto-mode/playbooks/feature.md"
sk="$c/pstack/0.15.32/skills/principle-model-the-domain/SKILL.md"
skill_name=pstack:principle-model-the-domain

expect_allow "outside cache: repo SKILL.md" "cat plugins/bigdaddy/skills/briefing/SKILL.md"
expect_allow "outside cache: ~/.claude/skills" "sed -n 1,40p ~/.claude/skills/foo/SKILL.md"
expect_allow "outside cache: ~/.agents/skills" "cat ~/.agents/skills/foo/SKILL.md"
expect_allow "no cache in command at all" "cat README.md"
expect_allow "ls the playbooks directory" "ls $c/pstack/0.15.32/skills/poteto-mode/playbooks"
expect_allow "rg under skills" "rg -n foo $c/pstack/0.15.32/skills"
expect_allow "grep -rn under cache" "grep -rn foo $c/pstack/0.15.32/skills"
expect_allow "find SKILL.md by name" "find $c -name SKILL.md"
expect_allow "ls -l a playbook file" "ls -l $pb"
expect_allow "grep inside a SKILL.md" "grep -n foo $sk"
expect_allow "node script under cache" "node $c/bigdaddy/0.9.0/skills/x/scripts/check-plan.mjs"
expect_allow "sh script under cache" "sh $c/bigdaddy/0.9.0/skills/x/scripts/run.sh"
expect_allow "cache and target in different segments" "cat plugins/bigdaddy/skills/x/SKILL.md; ls $c"
expect_allow "rg piped to head" "rg -n foo $c/bigdaddy/0.9.0/skills/x/SKILL.md | head -5"

empty="$tmp/empty"
mkdir -p "$empty"
out=$(bash_input "cat $pb" | PATH="$empty" "$hook"); code=$?
if [ "$code" = 0 ] && [ -z "$out" ]; then pass "no jq: allowed"; else fail "no jq: allowed (exit $code, got: $out)"; fi

expect_deny "cat playbook" "cat $pb" Read "$pb"
expect_deny "sed SKILL.md" "sed -n 1,40p $sk" "$sk" Read
expect_deny_without "pstack SKILL.md is not sent to the Skill tool" "cat $sk" "Skill ツールで ${skill_name} を起動"
expect_deny "bigdaddy SKILL.md goes to the Skill tool" "cat $c/bigdaddy/0.12.0/skills/briefing/SKILL.md" "Skill ツールで bigdaddy:briefing を起動"
expect_deny_without "bigdaddy SKILL.md is not sent to Read" "cat $c/bigdaddy/0.12.0/skills/briefing/SKILL.md" "Read ツール"
expect_deny "yomiyasu SKILL.md goes to the Skill tool" "cat $c/yomiyasu/1.1.0/SKILL.md" "Skill ツールで yomiyasu:yomiyasu を起動"
expect_deny_without "yomiyasu SKILL.md is not sent to Read" "cat $c/yomiyasu/1.1.0/SKILL.md" "Read ツール"
expect_deny "head SKILL.md" "head -50 $sk" "$skill_name"
expect_deny "tail SKILL.md" "tail -n 20 $sk" "$skill_name"
expect_deny "less SKILL.md" "less $sk" "$skill_name"
expect_deny "bat SKILL.md" "bat $sk" "$skill_name"
expect_deny "awk SKILL.md" "awk '{print}' $sk" "$skill_name"
expect_deny "/bin/cat SKILL.md" "/bin/cat $sk" "$skill_name"
expect_deny "backslash-escaped cat" "\\cat $sk" "$skill_name"
expect_deny "xargs cat" "xargs cat $sk" "$skill_name"
expect_deny "ls SKILL.md | xargs cat" "ls $sk | xargs cat" Skill
expect_deny "find SKILL.md | xargs head" "find $c -name SKILL.md | xargs head -20" Skill
expect_deny "var without target string" "P=$c/pstack/0.15.32/skills/poteto-mode/playbooks; cat \$P/feature.md" Read
expect_deny "var chain without target string" "P=$c/pstack/0.15.32/skills/poteto-mode/playbooks; F=\$P/feature.md; head \$F" Read
expect_deny "cd to version dir then relative SKILL.md" "cd $c/pstack/0.15.32 && cat skills/poteto-mode/SKILL.md" Skill
expect_deny "cd to skills dir then relative playbook" "cd $c/pstack/0.15.32/skills && head -40 poteto-mode/playbooks/feature.md" Read
expect_deny "cd plugins then cache/ relative" "cd ~/.claude/plugins && cat cache/bigdaddy/pstack/0.15.32/skills/poteto-mode/SKILL.md" Skill
expect_deny "split command name c\\at" "c\\at $sk" "$skill_name"
expect_deny "HOME path expands to absolute" "cat \$HOME/.claude/plugins/cache/bigdaddy/pstack/0.15.32/skills/poteto-mode/playbooks/feature.md" Read "$HOME/.claude/plugins/cache"
expect_deny "CLAUDE_CONFIG_DIR path expands to absolute" "cat \${CLAUDE_CONFIG_DIR:-\$HOME/.claude}/plugins/cache/bigdaddy/pstack/0.15.32/skills/poteto-mode/playbooks/feature.md" Read "$HOME/.claude/plugins/cache"
expect_allow "positional awk field after rg" "rg -l foo $sk | awk '{print \$1}'"
expect_deny "relative cd stays under cache" "cd $c/pstack/0.15.32 && cd skills/poteto-mode && cat SKILL.md" Skill
expect_allow "cd out of cache resets" "cd $c/pstack/0.15.32/skills/poteto-mode && ls && cd /tmp && cat README.md"
expect_deny "find -exec cat" "find $c -name SKILL.md -exec cat {} \\;" Skill Read
expect_deny "bash -c 'cat ...'" "bash -c 'cat $sk'" "$skill_name"
expect_deny "cat after &&" "cat a.txt && cat $pb" Read "$pb"
expect_deny "subshell cat" "(cat $sk)" "$skill_name"
expect_deny "line continuation" "cat \\
$sk" "$skill_name"
expect_deny "two SKILL.md paths" "cat $sk $c/pstack/0.15.32/skills/principle-fix-root-causes/SKILL.md" "$skill_name" pstack:principle-fix-root-causes
expect_deny "~ path expands to HOME" "cat ~/.claude/plugins/cache/bigdaddy/pstack/0.15.32/skills/poteto-mode/playbooks/bug-fix.md" Read "$HOME/.claude/plugins/cache/bigdaddy/pstack/0.15.32/skills/poteto-mode/playbooks/bug-fix.md"

expect_deny "path form: ~/.claude" "cat ~/.claude/plugins/cache/bigdaddy/pstack/0.15.32/skills/x/SKILL.md" pstack:x
expect_deny "path form: \$HOME" "cat \$HOME/.claude/plugins/cache/bigdaddy/pstack/0.15.32/skills/x/SKILL.md" pstack:x
expect_deny "path form: CLAUDE_CONFIG_DIR default" 'cat ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/bigdaddy/pstack/0.15.32/skills/x/SKILL.md' pstack:x
expect_deny "path form: quoted CLAUDE_CONFIG_DIR default" 'cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/bigdaddy/bigdaddy/0.9.0/skills/x/SKILL.md"' bigdaddy:x
expect_deny "path form: absolute" "cat /Users/x/.claude/plugins/cache/bigdaddy/pstack/0.15.32/skills/x/SKILL.md" pstack:x
expect_deny "path form: CLAUDE_CONFIG_DIR playbook" 'cat ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/bigdaddy/pstack/0.15.32/skills/poteto-mode/playbooks/feature.md' Read 'playbooks/feature.md'

expect_deny "variable path then cat" "P=$c/pstack/0.15.32/skills/poteto-mode; cat \$P/playbooks/bug-fix.md" Skill Read
expect_deny "for loop with sed" "for s in a b c; do sed -n 1,40p $c/pstack/0.15.32/skills/principle-\$s/SKILL.md; done" Skill Read
expect_deny "for loop over glob with cat" "C=$c; for f in \$C/pstack/0.15.32/skills/principle-*/SKILL.md; do cat \$f; done" Skill Read

expect_deny "cd into playbooks then cat" "cd $c/pstack/0.15.32/skills/poteto-mode/playbooks && cat feature.md" Skill Read
expect_deny "pushd into skills then head" "pushd $c/pstack/0.15.32/skills/poteto-mode; head -20 SKILL.md" Skill Read
expect_allow "cd into cache scripts then run" "cd $c/bigdaddy/0.9.0/scripts && sh run.sh"

exit "$failed"
