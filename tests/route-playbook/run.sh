#!/bin/sh
# route-playbook.sh の選択肢（--criteria）が、pstack の poteto-mode の SKILL.md と playbooks/ の実物と合っているかを確かめる。Jev は呼ばないので鍵は要らない。
# 使い方: sh tests/route-playbook/run.sh [poteto-mode の SKILL.md]
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
script="$root/plugins/bigdaddy/skills/jev-gates/scripts/route-playbook.sh"
skill=${1:-$(jq -r '.plugins["pstack@bigdaddy"][0].installPath // empty' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null)/skills/poteto-mode/SKILL.md}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failed=1; }

if [ ! -f "$skill" ]; then fail "poteto-mode SKILL.md not found: $skill"; exit 1; fi

PSTACK_POTETO_SKILL="$skill" sh "$script" --criteria > "$tmp/criteria.json" 2> "$tmp/err" || { fail "--criteria runs ($(cat "$tmp/err"))"; exit 1; }

ls "$(dirname "$skill")/playbooks" | sed 's/\.md$//' | grep -vx opening-a-pr | sort > "$tmp/files"
jq -r 'keys[] | select(. != "none")' "$tmp/criteria.json" | sort > "$tmp/keys"
if diff "$tmp/files" "$tmp/keys" > "$tmp/diff"; then
  pass "criteria keys are the playbook files, without opening-a-pr"
else
  fail "criteria keys are the playbook files, without opening-a-pr ($(tr '\n' ' ' < "$tmp/diff"))"
fi

if jq -e 'to_entries | all(.value | length > 0 and (contains("File:") | not) and (contains("playbooks/") | not))' "$tmp/criteria.json" >/dev/null; then
  pass "every criterion has a description without File: or a playbook path"
else
  fail "every criterion has a description without File: or a playbook path"
fi

jq -e 'has("none")' "$tmp/criteria.json" >/dev/null && pass "none is kept" || fail "none is kept"

for v in 0.9.79 0.15.32; do mkdir -p "$tmp/home/.claude/plugins/cache/a/pstack/$v/skills/poteto-mode/playbooks"; : > "$tmp/home/.claude/plugins/cache/a/pstack/$v/skills/poteto-mode/playbooks/old.md"; done
: > "$tmp/home/.claude/plugins/cache/a/pstack/0.15.32/skills/poteto-mode/playbooks/new-thing.md"
printf '## Playbooks\n\n- **Old.** old one. File: `playbooks/old.md`.\n' > "$tmp/home/.claude/plugins/cache/a/pstack/0.9.79/skills/poteto-mode/SKILL.md"
printf '## Playbooks\n\n- **New thing.** new one.\n' > "$tmp/home/.claude/plugins/cache/a/pstack/0.15.32/skills/poteto-mode/SKILL.md"
picked=$(HOME="$tmp/home" sh "$script" --criteria 2>&1 | jq -r 'keys | map(select(. != "none")) | join(",")')
[ "$picked" = "new-thing" ] && pass "without PSTACK_POTETO_SKILL the newest version is read (0.15.32 over 0.9.79)" || fail "newest version is read (got: $picked)"

mkdir -p "$tmp/fx/skills/poteto-mode/playbooks"
fx="$tmp/fx/skills/poteto-mode"
: > "$fx/playbooks/bug-fix.md"; : > "$fx/playbooks/long-name-v2.md"; : > "$fx/playbooks/by-file.md"
printf '## Playbooks\n\n- **Bug fix.** fix it.\n- **Long name (v2).** punctuation dropped.\n- **Odd title.** has a file. File: `playbooks/by-file.md`.\n\n## Next\n- **Not a playbook.** after the section.\n' > "$fx/SKILL.md"
PSTACK_POTETO_SKILL="$fx/SKILL.md" sh "$script" --criteria 2>"$tmp/e1" | jq -r 'keys | join(",")' > "$tmp/k1"
[ "$(cat "$tmp/k1")" = "bug-fix,by-file,long-name-v2,none" ] && pass "stem: File: wins, otherwise kebab case with punctuation dropped; stops at the next ## heading" || fail "stem rules (got: $(cat "$tmp/k1") $(cat "$tmp/e1"))"

printf '## Playbooks\n\n- **Bug fix.** fix it.\n- **Gone one.** no file.\n' > "$fx/SKILL.md"
PSTACK_POTETO_SKILL="$fx/SKILL.md" sh "$script" --criteria >"$tmp/o2" 2>"$tmp/e2"; code=$?
if [ "$code" != 0 ] && grep -q 'Gone one' "$tmp/e2"; then pass "a line without playbooks/<stem>.md stops with non-zero and names the line"; else fail "missing playbook file (exit $code, stderr: $(cat "$tmp/e2"))"; fi

printf '## Playbooks\n\n- **Bug fix** no dot-space form\n' > "$fx/SKILL.md"
PSTACK_POTETO_SKILL="$fx/SKILL.md" sh "$script" --criteria >"$tmp/o3" 2>"$tmp/e3"; code=$?
[ "$code" != 0 ] && pass "an unparsable bullet stops with non-zero" || fail "an unparsable bullet stops with non-zero (exit $code)"

[ "$failed" = 0 ] && echo "all passed" || { echo "failed"; exit 1; }
