---
name: usage-report
description: >-
  作業中にどの skill・プレイブック・原則・Jev のスクリプト・subagent が何回使われたかと、モデルごとのトークン数を、会話ログから集計する。
  bigdaddy や pstack の改善点を探すとき、使われていない skill や読まれていない手順を見つけるときに使う。
  Use for "どの skill が使われた", "使用状況を集計", "トークン使用量", "usage report", or improving bigdaddy based on actual use.
---

# Usage report

会話ログ（`~/.claude/projects/**/*.jsonl`、subagent 分を含む）から、ツール呼び出しの名前とパス、応答のモデル名とトークン数だけを取り出して数える。会話の本文は読まない。

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/usage-report/scripts/usage-report.sh" --since 2026-10-01 --project myapp
```

Cursor ではエージェントのシェルに `CLAUDE_PLUGIN_ROOT` が入らない。`~/.claude/plugins/installed_plugins.json` の `bigdaddy@bigdaddy` の `installPath` を使う。

- `--since`: この日以降の記録だけ数える。
- `--until`: この日までの記録だけ数える。この日を含む。
- `--project`: `~/.claude/projects` の下のディレクトリ名に含まれる文字列で絞る（例: `myapp`）。
- `--json`: JSON で出す。期間ごとに比べるときに使う。

## 区分

| 区分 | 数えているもの |
|---|---|
| skills | Skill ツールでの起動と、ユーザーのスラッシュコマンドでの起動。pstack の skill は `disable-model-invocation` でモデルが Skill ツールで起動できないので、ここに出るのはユーザーが打ったものだけ |
| skills_by_user | そのうちユーザーが起動したもの |
| playbooks | poteto-mode のプレイブックのファイルを読んだ回数。Read ツールと、plugin cache の下を Bash で読んだもの（`Read` / `Bash` に分けて表示） |
| principles | pstack の原則 skill の起動（`Skill`）と読み込み（`Read` / `Bash`）。モデルが原則を使うと `Read` に出る |
| skill_files_read | Skill ツールを通さず SKILL.md を読んだ回数。Read ツールと、plugin cache の下を Bash で読んだもの。pstack の skill（`poteto-mode`、`how` など）のモデルによる起動はここに出る。原則は principles に分ける |
| jev_scripts | `jev.sh`・`route-playbook.sh`・`route-model.sh`・`check-naze.sh`・`audit-decision.sh` の実行回数 |
| subagents | subagent の種類ごとの起動回数 |
| models | モデル・本体か subagent か（`who`）・agent の種類（`agent_type`）の組ごとのターン数とトークン数 |

playbooks・principles・skill_files_read は、行の末尾に読み方の内訳（例: `(Read 2 / Bash 5)`）が付く。`--json` では各行の `skill`・`read`・`bash` の件数になる。

`sessions` 列は、その項目が出たセッションの数。1 セッションで何度も使われたものと、多くのセッションで使われたものを見分ける。

## models

組ごとに、ターン数、input、cache read、cache write、output のトークン数と、それぞれが全体に占める割合を出す。cache read の多い順に並べる。全体の合計は JSON の `models_total` と、表の `total` 行に出る。

- ターン数は、異なる `message.id` の数。Claude Code は 1 回の API 応答を content block ごとに複数の行に分けて記録し、どの行にも同じ usage を書く。行のまま足すと約 2 倍になるので、`message.id` ごとにまとめる。
- 同じ `message.id` の行どうしでは input と cache の値は同じだが、output は最後の行で増えることがある（例: 2、2、617）。そこで 4 つの値それぞれの最大を取る。
- `message.id` の重複は、集計するすべてのファイルをまたいで除く。同じ応答が複数のファイルに出ることがある（2026-09-26 からの 14 日で 60 件）。
- `agent_type` は、本体なら `main`。subagent なら、ログ `subagents/agent-<id>.jsonl` の隣にある `agent-<id>.meta.json` の `agentType`（例: `general-purpose`、`pstack:poteto-agent`、`Explore`）。meta が無ければ `unknown`。
- モデルが `<synthetic>` の行と、usage の無い行は数えない。
- 料金には換算しない。トークン数だけを出す。

## 読み方の注意

- pstack の skill は SKILL.md を Read ツールで読んで起動するので、Read の SKILL.md は起動と同じ扱いで数える。パスで pstack に絞ってはいない。リポジトリ内の SKILL.md を Read した分も同じ区分に入る。
- Bash で読んだ記録は、コマンドに `/plugins/cache/` を含み、`cat`・`sed`・`head`・`tail`・`less`・`bat`・`awk` のどれかをコマンドの位置で使っているときだけ数える。作成作業で触るのはリポジトリで、plugin cache の下を読むのは使用だけとみなせるため。リポジトリ内のパスで読んだものや、`ls`・`rg` などの読み取りでないコマンドは数えない。
- Bash 経由は 1 つのコマンドに出てくる名前ごとに 1 件で数える（`for` ループで原則を 3 つ読めば 3 件）。コマンド全体で cache と読み取りコマンドを見るので、1 つのコマンドにリポジトリ内のパスと cache の両方があると、リポジトリ側の名前も数える。
- 数は「呼ばれた回数」で、「役に立った回数」ではない。改善点を探すときは、回数に加えて、呼ばれるべき場面で呼ばれていないものを見る（例: レビュー指摘があったセッションで `review-triage-loop` が 0 回）。
- クラウドセッションのログはクラウドのコンテナに残り、手元には来ない。
