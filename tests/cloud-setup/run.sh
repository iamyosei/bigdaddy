#!/bin/sh
# cloud/setup.sh を一時 HOME で実行し、bigdaddy のモデル表が ~/.claude/rules/ に置かれ、CLAUDE.md の @ 行からは読まれないことを確かめる。
# 表の役割名が pstack の setup-pstack の役割名と一致することも確かめる（pstack を上げて役割名が変わったら落ちる）。
# 表の値が opus medium・sonnet high・haiku high の 3 組だけであることと、setup が settings.json の env に CLAUDE_CODE_SUBAGENT_MODEL=sonnet を入れることも確かめる。
# bigdaddy は owner/repo 指定の marketplace add で足すことも確かめる。
# 使い方: sh tests/cloud-setup/run.sh [setup-pstack の SKILL.md]
#   引数が無く、手元の pstack が公式の Claude Code 版でない（docs/harness/claude-code.md が無い）ときは、役割名の比較を SKIP する。
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
sheet="$root/plugins/bigdaddy/pstack-models.md"
given=${1:-}
pstack_setup=${1:-$(jq -r '.plugins["pstack@bigdaddy"][0].installPath // empty' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null)/skills/setup-pstack/SKILL.md}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failed=1; }

mkdir -p "$tmp/bin" "$tmp/home/.claude/plugins/cache/bigdaddy/bigdaddy/0.9.0" "$tmp/home/.claude/plugins/cache/bigdaddy/bigdaddy/0.10.0"
for c in npm ast-grep; do printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/$c"; done
printf '#!/bin/sh\necho "$*" >> "%s/claude.log"\n' "$tmp" > "$tmp/bin/claude"
printf '#!/bin/sh\nshift\nexec "$@"\n' > "$tmp/bin/timeout"
chmod +x "$tmp/bin/"*
echo 'stale' > "$tmp/home/.claude/plugins/cache/bigdaddy/bigdaddy/0.9.0/pstack-models.md"
cp "$sheet" "$tmp/home/.claude/plugins/cache/bigdaddy/bigdaddy/0.10.0/pstack-models.md"

HOME="$tmp/home" PATH="$tmp/bin:$PATH" bash "$root/cloud/setup.sh" > "$tmp/log" 2>&1

if cmp -s "$sheet" "$tmp/home/.claude/rules/pstack-models.md"; then
  pass "setup places the newest bigdaddy sheet"
else
  fail "setup places the newest bigdaddy sheet (log: $(cat "$tmp/log"))"
fi

if grep -qx "plugin marketplace add iamyosei/bigdaddy" "$tmp/claude.log" 2>/dev/null && ! grep -q '^plugin marketplace add [/~.]' "$tmp/claude.log"; then
  pass "setup adds bigdaddy by owner/repo and not from a local path"
else
  fail "setup adds bigdaddy by owner/repo and not from a local path (claude calls: $(tr '\n' '|' < "$tmp/claude.log" 2>&1))"
fi

if grep -q 'pstack-models' "$tmp/home/.claude/CLAUDE.md"; then
  fail "cloud CLAUDE.md does not reference the sheet (Claude Code reads rules/ itself)"
else
  pass "cloud CLAUDE.md does not reference the sheet (Claude Code reads rules/ itself)"
fi
[ ! -e "$tmp/home/.claude/pstack-models.md" ] && pass "sheet is not left directly under .claude" || fail "sheet is not left directly under .claude"

if jq -e '.env.CLAUDE_CODE_SUBAGENT_MODEL == "sonnet"' "$tmp/home/.claude/settings.json" >/dev/null 2>&1; then
  pass "setup sets CLAUDE_CODE_SUBAGENT_MODEL=sonnet in settings.json env"
else
  fail "setup sets CLAUDE_CODE_SUBAGENT_MODEL=sonnet in settings.json env ($(cat "$tmp/home/.claude/settings.json" 2>&1))"
fi

bad=$(awk '/^[a-z][a-z ,-]*: / {
  v = $0; sub(/^[^:]*: /, "", v)
  n = split(v, a, ", ")
  for (i = 1; i <= n; i++) if (a[i] != "opus medium" && a[i] != "sonnet high" && a[i] != "haiku high") { print; break }
}' "$sheet")
if [ -z "$bad" ]; then
  pass "sheet values are only opus medium, sonnet high, haiku high"
else
  fail "sheet values are only opus medium, sonnet high, haiku high (offending: $(printf '%s' "$bad" | tr '\n' '|'))"
fi

# setup-pstack が書く rule の形: frontmatter なし、# budget 行あり
if [ "$(head -n1 "$sheet")" != "---" ] && grep -q '^# budget' "$sheet"; then
  pass "sheet has no frontmatter and has a # budget line"
else
  fail "sheet has no frontmatter and has a # budget line"
fi

roles() { sed -n 's/^\([a-z][a-z ,-]*\): .*/\1/p' | sort; }
if [ -z "$given" ] && [ ! -f "$(dirname "$pstack_setup")/../../docs/harness/claude-code.md" ]; then
  echo "SKIP sheet roles match setup-pstack (手元の pstack が公式の Claude Code 版ではない: $pstack_setup。公式の setup-pstack の SKILL.md を引数で渡すと比べる)"
elif [ ! -f "$pstack_setup" ]; then
  fail "setup-pstack SKILL.md not found: $pstack_setup"
else
  # 公式の setup-pstack は、手順 5 の最初のコードブロックに rule の形を書く。frontmatter の description と alwaysApply は役割ではない。
  awk '/^```/ { if (f) exit; f = 1; next } f' "$pstack_setup" | roles | grep -vx -e description -e alwaysApply > "$tmp/pstack-roles"
  roles < "$sheet" > "$tmp/bigdaddy-roles"
  if [ -s "$tmp/pstack-roles" ] && diff "$tmp/pstack-roles" "$tmp/bigdaddy-roles" > "$tmp/roles.diff"; then
    pass "sheet roles match setup-pstack"
  else
    fail "sheet roles match setup-pstack ($(tr '\n' ' ' < "$tmp/roles.diff" 2>/dev/null))"
  fi
fi

# BIGDADDY_JEV: 無効（既定）では typesafe plugin を入れず、bigdaddy-health は鍵の有無を見ない。有効のときだけ入れ、鍵が無ければ警告する。
if ! grep -q typesafe "$tmp/claude.log" 2>/dev/null; then pass "setup without BIGDADDY_JEV does not install the typesafe plugin"; else fail "setup without BIGDADDY_JEV does not install the typesafe plugin ($(tr '\n' '|' < "$tmp/claude.log"))"; fi
health="$tmp/home/.claude/hooks/bigdaddy-health.sh"
out=$(env -u BIGDADDY_JEV -u TYPESAFE_API_KEY HOME="$tmp/home" sh "$health" 2>&1)
if ! printf '%s' "$out" | grep -q TYPESAFE_API_KEY; then pass "bigdaddy-health without BIGDADDY_JEV does not warn about TYPESAFE_API_KEY"; else fail "bigdaddy-health without BIGDADDY_JEV does not warn about TYPESAFE_API_KEY ($out)"; fi
out=$(env -u TYPESAFE_API_KEY BIGDADDY_JEV=1 HOME="$tmp/home" sh "$health" 2>&1)
if printf '%s' "$out" | grep -q 'TYPESAFE_API_KEY が無い。bigdaddy:jev-gates'; then pass "bigdaddy-health with BIGDADDY_JEV=1 and no key warns"; else fail "bigdaddy-health with BIGDADDY_JEV=1 and no key warns ($out)"; fi
out=$(env BIGDADDY_JEV=1 TYPESAFE_API_KEY=x HOME="$tmp/home" sh "$health" 2>&1)
if ! printf '%s' "$out" | grep -q TYPESAFE_API_KEY; then pass "bigdaddy-health with BIGDADDY_JEV=1 and a key is silent about the key"; else fail "bigdaddy-health with BIGDADDY_JEV=1 and a key is silent about the key ($out)"; fi

rm -f "$tmp/claude.log"
HOME="$tmp/home" PATH="$tmp/bin:$PATH" BIGDADDY_JEV=1 bash "$root/cloud/setup.sh" > "$tmp/log2" 2>&1
if grep -qx 'plugin install typesafe@typesafe-ai --scope user' "$tmp/claude.log" 2>/dev/null; then pass "setup with BIGDADDY_JEV=1 installs the typesafe plugin"; else fail "setup with BIGDADDY_JEV=1 installs the typesafe plugin ($(tr '\n' '|' < "$tmp/claude.log" 2>&1))"; fi

exit "$failed"
