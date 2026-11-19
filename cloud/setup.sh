#!/bin/bash
# クラウド環境の Setup script。bigdaddy（pstack・yomiyasu を依存に持つ）とユーザーグローバル CLAUDE.md・hooks を配置する。
# Setup は毎セッション走るわけではない。走った後の状態が保存され、以後のセッションはそれを使い回す。
# 正本は iamyosei/bigdaddy の cloud/setup.sh。claude.ai の環境設定にはこのファイルの中身を貼る。
# 失敗してもセッション起動を止めないよう、各ステップは || で握りつぶしてログだけ残す。
# 失敗は SessionStart hook がエージェントの文脈に注入するので、黙って素通りにはならない。
#
# 環境変数（claude.ai の環境設定に書く）:
#   BIGDADDY_JEV                   1 のときだけ Jev を使う（既定は無効）。1 のときだけ typesafe plugin を入れ、bigdaddy-health が TYPESAFE_API_KEY の有無を見る
#   TYPESAFE_API_KEY             Jev を呼ぶキー（BIGDADDY_JEV=1 のときだけ要る）

log() { echo "[setup] $*"; }

# 出力を全部ファイルにも残す。Setup の出力はセッションから見えないので、失敗の理由をあとで追えるようにする
mkdir -p ~/.claude
exec > >(tee -a ~/.claude/setup.log) 2>&1
log "start $(date -u +%FT%TZ)"

# GitHub clone の一時失敗に備えて指数バックオフで再試行する
retry() {
  local n=0 delay=2
  until "$@"; do
    n=$((n + 1))
    [ "$n" -ge 4 ] && return 1
    sleep "$delay"
    delay=$((delay * 2))
  done
}

# ast-grep（/usr/bin/sg は newgrp なので、呼び出しは ast-grep 名で行う）
command -v ast-grep >/dev/null 2>&1 || npm i -g @ast-grep/cli >/dev/null 2>&1 || log "ast-grep install failed"

mkdir -p ~/.claude/hooks

# ---------------------------------------------------------------------------
# plugin: bigdaddy（pstack と yomiyasu は bigdaddy の依存として sha 固定で一緒に入る）
# ---------------------------------------------------------------------------
if command -v claude >/dev/null 2>&1; then
  retry timeout 120 claude plugin marketplace add iamyosei/bigdaddy || log "bigdaddy marketplace add failed"
  retry timeout 300 claude plugin install bigdaddy@bigdaddy --scope user || log "bigdaddy install failed"
  # typesafe は「プロダクトのコードに Jev を組み込む」ときの手引き。bigdaddy の Jev ゲートとは別物なので個別に入れる。Jev を選んだ（BIGDADDY_JEV=1）ときだけ
  if [ "${BIGDADDY_JEV:-}" = 1 ]; then
    retry timeout 120 claude plugin marketplace add typesafe-ai/skills || log "typesafe marketplace add failed"
    retry timeout 120 claude plugin install typesafe@typesafe-ai --scope user || log "typesafe install failed"
  fi
else
  log "claude CLI not found; plugins not installed"
fi

# ---------------------------------------------------------------------------
# pstack のモデル表は bigdaddy が持つコスト重視の表を置く。Claude Code は ~/.claude/rules/ の .md を毎セッション読むので、CLAUDE.md からは読ませない。
# ---------------------------------------------------------------------------
bigdaddy_sheet=$(printf '%s\n' ~/.claude/plugins/cache/bigdaddy/bigdaddy/*/pstack-models.md | sort -V | tail -n1)
if [ -f "$bigdaddy_sheet" ]; then
  mkdir -p ~/.claude/rules
  cp "$bigdaddy_sheet" ~/.claude/rules/pstack-models.md || log "pstack-models.md write failed"
else
  log "bigdaddy pstack-models.md not found; pstack uses its default models"
fi

# ---------------------------------------------------------------------------
# hooks: 入口の振り分けは bigdaddy の SessionStart hook が行う。ここでは導入の失敗と前提の欠けを見せ、毎ターン短く再注入する
# ---------------------------------------------------------------------------

# SessionStart: 導入の失敗と前提の欠けを可視化する
cat > ~/.claude/hooks/bigdaddy-health.sh <<'EOF'
#!/bin/sh
reg="$HOME/.claude/plugins/installed_plugins.json"
warn() { echo "警告: $*。作業前にユーザーへ報告すること。"; }
echo "<bigdaddy-health>"
for p in bigdaddy@bigdaddy pstack@bigdaddy yomiyasu@bigdaddy; do
  jq -e --arg p "$p" '.plugins | has($p)' "$reg" >/dev/null 2>&1 || warn "$p が未インストール（Setup script の失敗の可能性）"
done
[ "${BIGDADDY_JEV:-}" != 1 ] || [ -n "${TYPESAFE_API_KEY:-}" ] || warn "TYPESAFE_API_KEY が無い。bigdaddy:jev-gates の jev.sh が動かない（環境変数を設定する）"
loc=$(jq -r '.bigdaddy.installLocation // ""' "$HOME/.claude/plugins/known_marketplaces.json" 2>/dev/null)
[ -z "$loc" ] || [ -d "$loc" ] || warn "bigdaddy の marketplace の読み込み元 $loc が無い。bigdaddy・pstack・yomiyasu が読み込まれていない（Setup script を直して走らせ直す）"
command -v python3 >/dev/null 2>&1 || warn "python3 が無い。yomiyasu の lint が動かない"
# Setup が失敗を残していれば、その行も見せる（全文は ~/.claude/setup.log）
grep 'failed' "$HOME/.claude/setup.log" 2>/dev/null | tail -n 5
echo "</bigdaddy-health>"
EOF

# UserPromptSubmit: 毎ターン短く再注入（長い会話・compact 後でも忘れないように）
cat > ~/.claude/hooks/bigdaddy-prompt.sh <<'EOF'
#!/bin/sh
prompt=$(jq -r '.prompt // ""' 2>/dev/null)
if printf '%s' "$prompt" | grep -q '^## 指示書（briefing から）'; then
  echo "<bigdaddy-reminder>指示書のセッション。pstack の poteto-mode と指示書の「使う原則」の SKILL.md を Read ツールで読み、指示書のプレイブックで進める。</bigdaddy-reminder>"
else
  echo "<bigdaddy-reminder>作業の依頼なら bigdaddy:briefing を Skill ツールで呼び、指示書に仕立ててから進める。質問や 1 行の修正は直接やってよい。</bigdaddy-reminder>"
fi
if printf '%s' "$prompt" | grep -Eiq 'devin|review|レビュー|指摘|<event source="github"'; then
  echo "<bigdaddy-reminder>レビュー指摘への対応を含むなら、修正前に Skill ツールで bigdaddy:review-triage-loop を呼ぶ。</bigdaddy-reminder>"
fi
exit 0
EOF
chmod +x ~/.claude/hooks/bigdaddy-*.sh

# settings.json に hooks と env をマージ（plugin install が書いた enabledPlugins や他の env は保持する）。
# CLAUDE_CODE_SUBAGENT_MODEL は、model を付けずに起動した subagent を sonnet にする。plugin は env を設定できない。
settings=~/.claude/settings.json
[ -s "$settings" ] || echo '{}' > "$settings"
tmp=$(mktemp)
if jq '
  .hooks.SessionStart = [{"matcher": "startup|resume|clear|compact", "hooks": [{"type": "command", "command": "$HOME/.claude/hooks/bigdaddy-health.sh"}]}]
  | .hooks.UserPromptSubmit = [{"hooks": [{"type": "command", "command": "$HOME/.claude/hooks/bigdaddy-prompt.sh"}]}]
  | .env.CLAUDE_CODE_SUBAGENT_MODEL = "sonnet"
' "$settings" > "$tmp"; then
  mv "$tmp" "$settings"
else
  rm -f "$tmp"
  log "settings.json hooks merge failed"
fi

# ---------------------------------------------------------------------------
# ユーザーグローバル CLAUDE.md（クラウド版）
# ---------------------------------------------------------------------------
cat > ~/.claude/CLAUDE.md <<'EOF'
# CLAUDE.md (user global)

このファイルはユーザーグローバル設定。全プロジェクト・全セッション・全 sub-agent に適用される。
（クラウドセッション版：環境の Setup script から配置している。正本は iamyosei/bigdaddy の cloud/setup.sh）
plugin（bigdaddy・pstack・yomiyasu。`BIGDADDY_JEV=1` のときは typesafe も）のインストールと hook は Setup script が行う。エージェントが install を実行する必要はない。

## 作業の流儀は bigdaddy に従う

- 作業の依頼は `bigdaddy:briefing` で受ける。依頼を指示書に仕立て、実装は pstack の `poteto-mode` で進める。
- 「## 指示書（briefing から）」で始まるセッションは実装役。指示書どおり pstack の `poteto-mode` の SKILL.md と指示書の「使う原則」の SKILL.md を Read ツールで読んでから進める（pstack の skill は Skill ツールで起動できない。SKILL.md は `~/.claude/plugins/installed_plugins.json` の `pstack@bigdaddy` の `installPath` の下の `skills/<名前>/SKILL.md`）。
- クラウドセッションには `spawn_task` が無い。指示書は本文に出し、ユーザーが同じセッションでの実装を認めたら pstack の `poteto-mode` と指示書の「使う原則」の SKILL.md を Read ツールで読んで切り替える。認めなければ、ユーザーが新しいセッションに貼れる形で渡して止まる。
- PR レビュー指摘（Devin・人間・bot・GitHub の review event）への対応は、修正前に必ず `bigdaddy:review-triage-loop` を呼ぶ。
- 必要な skill が見当たらない場合は黙って進めず、ユーザーに報告する。

## コードリーディング

コードの検索・読解では ast-grep を第一選択にする。文字列マッチの grep / rg はコメントや文字列リテラル内のヒットが混じり、関数定義・呼び出し・JSX・型の検索では構文木の方が精度が高い。
クラウド環境では `/usr/bin/sg` が newgrp なので、コマンド名は `ast-grep` を使う（`ast-grep run -p '...' --lang <lang>`）。

| 用途 | ツール |
|---|---|
| 関数定義・呼び出し・JSX・型定義などコード構造の検索 | `ast-grep run -p '...' --lang <lang>` |
| 文字列リテラル・ログメッセージ・設定値・URL 等 | `rg` / `grep` |
| ファイル名検索 | `find`（クラウドには fd なし） |

sub-agent を spawn するときも「ast-grep 優先」を明示する。プロジェクトに `sgconfig.yml` があれば活用する。

## 作業環境

- 手元では、実装・修正・リファクタは専用の git worktree で行う。
- クラウドセッション（claude.ai/code）では worktree を切らない。コンテナ自体が使い捨ての隔離環境で、作業ブランチもセッションで指定されるため、指定ブランチで直接作業して push する。

## Jev / TypeSafe

- `BIGDADDY_JEV=1` のときだけ、二値判定・候補の絞り込み・アプローチ選定・完了判定は、長い思考連鎖や全件 Read や不要な sub-agent ではなく Jev で決める。手順は `bigdaddy:jev-gates`。呼び出しはその `scripts/jev.sh`（`TYPESAFE_API_KEY` を環境変数から読む）。`BIGDADDY_JEV=1` でないときは、jev-gates のスクリプトが exit 3 を返すので、各 skill の Jev なしの手順で進める。
- typesafe plugin（`typesafe:*` skill。`BIGDADDY_JEV=1` のときだけ入る）は「プロダクトのコードに Jev の判断を組み込むとき」に使う。エージェント自身の判断には bigdaddy:jev-gates を使う。

## 文章

- 日本語のドキュメント・PR の概要・Issue・コミット本文は、pstack の technical-writing と unslop で下書きを書き、最後に `yomiyasu:yomiyasu` で推敲してから出す。
- 会話の返答も、意味を変えない・情報を足さない・比喩や大げさな言葉や装飾記号を使わない、を守る。
EOF

log "done"
