# bigdaddy

依頼を指示書にして、pstack の `poteto-mode` を動かす別セッションへ渡し、隔離レビュー済みの PR まで進める Claude Code プラグイン。利用者の作業流儀で [pstack](https://github.com/cursor/plugins/tree/main/harness/pstack/claude-code)（`cursor/plugins` の Claude Code 版）をラップしている。

## 仕組み

1. 依頼を `bigdaddy:briefing` が受け、`poteto-mode` が着手できる指示書にする。
2. 指示書を別セッションの `poteto-mode` に渡し、実装させる。
3. 実装の差分を、実装役とは別の agent が隔離レビューする。
4. レビュー済みの差分を PR にする。
5. 利用者が PR をマージする。

指示書が 2 枚以上のときは、`topic/<slug>` に子 PR を集め、最終 PR 1 本を利用者が確かめる。詳しくは [docs/workflow.md](docs/workflow.md)。

## 必要なもの

Claude Code と、hook と skill の手順が呼ぶ `git`、`jq`、`gh`。

## インストール

```bash
claude plugin marketplace add iamyosei/bigdaddy
claude plugin install bigdaddy@bigdaddy
```

pstack は依存として一緒に入る。続けて、bigdaddy が持つ pstack のモデル表（`plugins/bigdaddy/pstack-models.md`）を `~/.claude/rules/` に写す。Claude Code は `~/.claude/rules/` の `.md` を毎セッション読むので、`~/.claude/CLAUDE.md` に `@` 行は足さない。bigdaddy を上げたら同じ `cp` をやり直す。

```bash
mkdir -p ~/.claude/rules && cp "$(printf '%s\n' ~/.claude/plugins/cache/bigdaddy/bigdaddy/*/pstack-models.md | sort -V | tail -n1)" ~/.claude/rules/pstack-models.md
```

最後に、`model` を付けずに起動した subagent を sonnet にする。plugin は env を設定できないので、`~/.claude/settings.json` の `env` に自分で入れる。何度実行しても同じ結果になる。

```bash
f=~/.claude/settings.json; [ -s "$f" ] || echo '{}' > "$f"; jq '.env.CLAUDE_CODE_SUBAGENT_MODEL = "sonnet"' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
```

モデル表の考え方、Jev（任意）、以前の手順からの移行は [docs/setup.md](docs/setup.md)。

## 使い方

Claude Code で普段どおり依頼する。SessionStart hook が briefing の使い方を文脈に出すので、依頼は `bigdaddy:briefing` が受ける。briefing が指示書を作って実装セッションに渡し、実装と隔離レビューが終わると PR が返ってくる。default branch へのマージは利用者がする。

- 「検索 API の遅いクエリを直して」
- 「`docs/` の古い手順を今の実装に合わせて更新して」

pstack の skill を直接使うときは `/pstack:<name>` と打つ。

## 中身

| skill | 役割 |
|---|---|
| `briefing` | 依頼を受けて指示書にし、別セッションへ渡す。コードは書かない |
| `jev-gates` | 分岐・絞り込み・完了判定を Jev で決める手順とスクリプト |
| `review-triage-loop` | 外部レビューの指摘を仕分けて直す。隔離レビューの回数と範囲も決める |
| `agent-reasoning-playbook` | 推論・検証・分解・メタ認知のチェックリスト |
| `logic-audit` | 主張と推論を形式論理で検査し、作業中の意思決定を点検する |
| `usage-report` | 会話ログから skill と subagent の使用回数とトークン数を集計する |

| hook | 動き |
|---|---|
| SessionStart | briefing と poteto-mode の使い分けを文脈に出す |
| `review-push-guard` | `git push` の前に、記録した隔離レビュー済みの head と比べ、記録の後にテスト・ドキュメント以外が変わっていれば止める |
| `topic-merge-guard` | default branch に変更を入れる agent のツール呼び出しを止める |
| `skill-read-guard` | plugin cache の `SKILL.md` とプレイブックを、cat・sed などの Bash の読み取りコマンドで読もうとすると止める |
| 決定の点検（PostToolUse・Stop） | `BIGDADDY_JEV=1` のときだけ、決定モードの点検を求める |

hook の詳細は [docs/hooks.md](docs/hooks.md)。

## ドキュメント

- [docs/workflow.md](docs/workflow.md): 依頼から PR までの規則と、skill の役割。
- [docs/hooks.md](docs/hooks.md): hook の動きと、`topic-merge-guard` の前提。
- [docs/setup.md](docs/setup.md): モデル表、Jev、移行、Cursor、クラウドセッション。
- [docs/development.md](docs/development.md): テスト、文章の上限、pstack を上げる手順。

## ライセンス

MIT（[LICENSE](LICENSE)）。
