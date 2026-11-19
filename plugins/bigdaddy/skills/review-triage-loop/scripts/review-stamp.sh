#!/bin/sh
# 隔離レビューで blocking が 0 件になった head を、ブランチごとに 1 つ記録する。
# 記録は push 前の hook（hooks/review-push-guard.sh）が読み、記録より後に振る舞いを変えるコミットがあれば push を止める。
# 使い方: review-stamp.sh   （作業ディレクトリのリポジトリで、いまの HEAD を記録する）
set -eu

git rev-parse --git-dir >/dev/null 2>&1 || { echo "review-stamp.sh: git リポジトリの中で実行する" >&2; exit 1; }
branch=$(git symbolic-ref --quiet --short HEAD) || { echo "review-stamp.sh: ブランチに居ない（detached HEAD）" >&2; exit 1; }

# レビューしたのはコミット済みの内容なので、未コミットの変更が残っていると HEAD とずれる
if ! git diff --quiet HEAD --; then
  echo "review-stamp.sh: 未コミットの変更がある。コミットしてからレビューし直し、記録する" >&2
  exit 1
fi

sha=$(git rev-parse HEAD)
# ブランチ名はリポジトリ全体で一意なので、worktree ごとではなく共通の git ディレクトリに置く
stamp="$(git rev-parse --path-format=absolute --git-common-dir)/bigdaddy/review-stamps/$branch"
mkdir -p "$(dirname "$stamp")"
printf '%s\n' "$sha" > "$stamp"
echo "review-stamp: $branch @ $sha"
