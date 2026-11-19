#!/bin/sh
# Jev（TypeSafe System One）を HTTP で呼ぶ。MCP ツールはこの環境に無いので、判断系 skill はすべてここを通す。
# 使い方: jev.sh <request.json>   または   echo '<json>' | jev.sh
# request は {"state": "...", "questions": {...}}。model を省くと jev-latest を入れる。
# BIGDADDY_JEV=1 でなければ何も呼ばず exit 3（stderr に 1 行）。鍵が無ければ exit 2、HTTP 失敗は exit 1。
# 出力は answers だけ（usage はトークンを食うだけなので捨てる）。
set -eu

# 外部（api.typesafe.ai）への出口はここだけ。利用者が BIGDADDY_JEV=1 で選んだときだけ呼ぶ。
[ "${BIGDADDY_JEV:-}" = 1 ] || { echo 'jev.sh: Jev は無効（BIGDADDY_JEV=1 で有効）' >&2; exit 3; }

# キーは環境変数 TYPESAFE_API_KEY（または TYPESAFE_API_TOKEN）から読む。無ければ macOS のキーチェーン（サービス名 typesafe-api-key）から読む。
key="${TYPESAFE_API_KEY:-${TYPESAFE_API_TOKEN:-}}"
if [ -z "$key" ]; then
  key=$(security find-generic-password -s typesafe-api-key -w 2>/dev/null || true)
fi
if [ -z "$key" ]; then
  echo "jev.sh: TYPESAFE_API_KEY が無い（env にもキーチェーン typesafe-api-key にも無い）" >&2
  exit 2
fi

if [ $# -ge 1 ]; then body=$(cat "$1"); else body=$(cat); fi
body=$(printf '%s' "$body" | jq -c 'if has("model") then . else . + {model: "jev-latest"} end')

# 「upstream connect error」の平文が 200 以外で返る一時障害があるので、数秒おいて 2 回まで再試行する。
attempt=0
while :; do
  attempt=$((attempt + 1))
  out=$(curl -sS -w '\n%{http_code}' https://api.typesafe.ai/v1/systemone \
    -H "Authorization: Bearer $key" -H 'Content-Type: application/json' -d "$body")
  code=$(printf '%s' "$out" | tail -n1)
  resp=$(printf '%s' "$out" | sed '$d')
  if [ "$code" = 200 ]; then
    printf '%s' "$resp" | jq '.answers'
    exit 0
  fi
  if [ "$attempt" -ge 3 ]; then
    echo "jev.sh: HTTP $code: $(printf '%s' "$resp" | head -c 300)" >&2
    exit 1
  fi
  sleep 3
done
