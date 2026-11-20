#!/bin/sh
# agent が読む文章と README と docs/*.md の文字数を tests/prose-budget/limits.txt の上限と比べる。上限の扱いは docs/development.md の "Prose limits" 節。
# 使い方: sh tests/prose-budget/run.sh
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
failed=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failed=1; }

# 文字数は wc -m で数えるので、UTF-8 のロケールをここで 1 回だけ選ぶ。
utf8=""
for l in C.UTF-8 en_US.UTF-8; do
  if [ "$(printf 'あ' | LC_ALL=$l wc -m 2>/dev/null | tr -d ' ')" = 1 ]; then utf8=$l; break; fi
done
if [ -z "$utf8" ]; then
  echo "FAIL a UTF-8 locale (C.UTF-8 or en_US.UTF-8) is available"
  exit 1
fi
LC_ALL=$utf8
export LC_ALL

# $1 の下の対象ファイルを、$1 からの相対パスで 1 行ずつ出す。
targets() {
  (
    cd "$1" || exit 1
    for f in plugins/bigdaddy/skills/*/SKILL.md plugins/bigdaddy/skills/*/references/*.md README.md docs/*.md; do
      [ -f "$f" ] && echo "$f"
    done
  )
}

# $1 をリポジトリ直下とみなして調べ、問題を 1 行ずつ出す。問題が無ければ何も出さない。
check() {
  r=$1
  lim="$r/tests/prose-budget/limits.txt"
  grep -v -e '^#' -e '^[[:space:]]*$' "$lim" | while read -r max path; do
    if [ ! -f "$r/$path" ]; then echo "missing file: $path"; continue; fi
    n=$(wc -m < "$r/$path" | tr -d ' ')
    [ "$n" -le "$max" ] || echo "over limit: $path ($n > $max)"
  done
  targets "$r" | while read -r path; do
    awk -v p="$path" '$1 !~ /^#/ && $2 == p { found = 1 } END { exit !found }' "$lim" || echo "no limit line: $path"
  done
}

# テスト自身の検査。一時ディレクトリに小さなリポジトリを作り、3 つの FAIL の条件を 1 つずつ起こす。
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fx="$tmp/repo"
skill=plugins/bigdaddy/skills/a/SKILL.md
ref=plugins/bigdaddy/skills/a/references/b.md
fixture() {
  rm -rf "$fx"
  mkdir -p "$fx/plugins/bigdaddy/skills/a/references" "$fx/tests/prose-budget"
  printf 'あいう\n' > "$fx/$skill"
  printf 'ab\n' > "$fx/$ref"
  printf 'r\n' > "$fx/README.md"
  printf '# comment\n2 README.md\n4 %s\n3 %s\n' "$skill" "$ref" > "$fx/tests/prose-budget/limits.txt"
}

fixture
out=$(check "$fx")
if [ -z "$out" ]; then pass "self-test: files at their limits pass (counted in characters, not bytes)"; else fail "self-test: files at their limits pass (got: $out)"; fi

fixture
printf 'え' >> "$fx/$skill"
out=$(check "$fx")
case "$out" in *"over limit: $skill"*) pass "self-test: one character over the limit fails" ;; *) fail "self-test: one character over the limit fails (got: $out)" ;; esac

fixture
grep -v -F "$ref" "$fx/tests/prose-budget/limits.txt" > "$tmp/l" && mv "$tmp/l" "$fx/tests/prose-budget/limits.txt"
out=$(check "$fx")
case "$out" in *"no limit line: $ref"*) pass "self-test: a target without a limit line fails" ;; *) fail "self-test: a target without a limit line fails (got: $out)" ;; esac

fixture
echo "10 plugins/bigdaddy/skills/a/references/gone.md" >> "$fx/tests/prose-budget/limits.txt"
out=$(check "$fx")
case "$out" in *"missing file: plugins/bigdaddy/skills/a/references/gone.md"*) pass "self-test: a line for a missing file fails" ;; *) fail "self-test: a line for a missing file fails (got: $out)" ;; esac

out=$(check "$root")
if [ -z "$out" ]; then
  pass "every target is within its limit in tests/prose-budget/limits.txt"
else
  fail "every target is within its limit in tests/prose-budget/limits.txt"
  printf '%s\n' "$out" | sed 's/^/  /'
fi

exit "$failed"
