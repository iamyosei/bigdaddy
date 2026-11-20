# セットアップの詳細

[README のインストール](../README.md#インストール)の補足と、Cursor・クラウドセッションでの使い方。

## モデル表と subagent のモデル

`plugins/bigdaddy/pstack-models.md` は pstack の各役割に使うモデルと effort を `<model> <effort>` で決める。表の値の組は `opus medium`、`sonnet high`、`haiku high` の 3 つだけで、探索と実装は `sonnet high`、判断と文章は `opus medium` に寄せる。arena・architect・interrogate のパネルは `opus medium, sonnet high` の 2 本にしている。fable と xhigh・low は使わない。pstack に hook は無いので、表に hook の設定は要らない。

実装セッションの主のモデルは、この表ではなく briefing が決める。詳しくは [作業の流れ](workflow.md#実装セッションの主のモデル)。

`CLAUDE_CODE_SUBAGENT_MODEL` を `sonnet` にするのは、`model` を付けずに起動した subagent を sonnet にするため。付けない場合は親のモデル（たいてい Opus）で動いてしまう。Agent の呼び出しで `model` を明示すればそちらが優先される。

## Jev を使う（任意）

Jev（TypeSafe の API）は既定で無効。使うときだけ、`~/.claude/settings.json` の `env` に `BIGDADDY_JEV=1` と `TYPESAFE_API_KEY`（キーチェーンの `typesafe-api-key` でもよい）を置く。

```json
{ "env": { "BIGDADDY_JEV": "1", "TYPESAFE_API_KEY": "..." } }
```

有効のときだけ、jev-gates のスクリプトと hook が判断材料（Stop hook はターンの本文）を `api.typesafe.ai` に送る。無効のときは何も送らず、スクリプトは exit 3 を返し、hook は何も出さない。各 skill には Jev なしの手順があるので、無効でも手順は最後まで進む。

## 以前の手順からの移行

以前の手順で `~/.claude/` 直下に `pstack-models.md` を写し、`~/.claude/CLAUDE.md` にそれを読ませる `@` 行を足してある環境では、その `@` 行と直下の `pstack-models.md` を消す。残すと古い表（`strongest judgment`、effort の無い値）が `rules/` の表と一緒に読まれる。

## Cursor で使う

Cursor（3.23.12 で確認）は、`~/.claude/settings.json` で有効にした Claude Code のプラグインを読む。`claude plugin install bigdaddy@bigdaddy` のあとに、Cursor 側でやることはない。

- skill と hook は Claude Code のインストール先から読まれる。更新は Claude Code 側の手順（`claude plugin marketplace update bigdaddy` と `claude plugin update bigdaddy@bigdaddy`）で行う。
- SessionStart の文脈は、hook が JSON を出すので Cursor にも届く。Cursor は JSON 以外の stdout を捨てる。
- Cursor のエージェントのシェルには `CLAUDE_PLUGIN_ROOT` が入らない。skill の手順にあるスクリプトは、`~/.claude/plugins/installed_plugins.json` の `bigdaddy@bigdaddy` の `installPath` から呼ぶ。

既知の穴は次の 2 つ。

- Stop hook（`decision-audit-stop.sh`）は `transcript_path` を読むが、Cursor は null を渡すので、何も出さずに終わる。
- `review-push-guard.sh` と `decision-audit-nudge.sh` は Cursor でも動くが、そこでの挙動は確かめていない。

## クラウドセッション

クラウドセッションは手元の `~/.claude` を読まない。claude.ai の環境設定の Setup script に `cloud/setup.sh` の中身を貼る。bigdaddy は Setup script が `claude plugin marketplace add iamyosei/bigdaddy` で足す。

- Setup は毎セッション走るわけではなく、走った後の状態が以後のセッションで使い回される。bigdaddy を更新しても、次に Setup が走るまでクラウドには入らない。
- Jev を使うときだけ、環境変数に `BIGDADDY_JEV=1` と `TYPESAFE_API_KEY` を設定する。無効のままなら typesafe plugin も入らない。
- モデル表は Setup script が入った bigdaddy から `~/.claude/rules/pstack-models.md` に写す。
- Setup script は `~/.claude/settings.json` の `env` に `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` も入れる（手元では README のインストール手順で入れる）。
- 導入に失敗した項目は、セッション開始時に `bigdaddy-health` hook が警告として文脈に出す。
