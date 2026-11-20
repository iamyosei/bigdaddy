# 開発

bigdaddy を変更する人向けの手順。テスト、文章の上限、pstack を上げる手順をまとめる。

個人の skill とワークフローは bigdaddy に足す。`~/.claude/skills` に直接置かない。

## テスト

hook のテストは `tests/decision-audit/run.sh`（`BIGDADDY_JEV` 未設定での無効の挙動は鍵なしで確かめる。Jev を実際に呼ぶ検査は `BIGDADDY_JEV=1` を付けたときだけ走り、付けなければ鍵があっても skip する）、`tests/review-push-guard/run.sh`（一時 git リポジトリで回す。鍵は要らない）、`tests/skill-read-guard/run.sh`（鍵は要らない）、`tests/topic-merge-guard/run.sh`（一時 git リポジトリと偽の `gh` で回す。鍵も本物の `gh` も要らない）、`tests/briefing-state/run.sh`（`SKILL.md` の状態の JSON と手順の番号を確かめる。鍵は要らない）、`tests/prose-budget/run.sh`（下の「文章の上限」を確かめる。鍵は要らない）で実行する。`route-playbook.sh` の選択肢が pstack の `poteto-mode` の一覧と `playbooks/` に合うことは `tests/route-playbook/run.sh`（鍵は要らない）で確かめる。`cloud/setup.sh` とモデル表のテスト（表が `~/.claude/rules/` に置かれること、表の値が 3 組だけであること、`CLAUDE_CODE_SUBAGENT_MODEL` が入ることを含む）は `tests/cloud-setup/run.sh` で実行する。`tests/decision-audit/run.sh` は `route-model.sh` のモデルと effort の組と、`--session` がプレイブックで主のモデルを分けることも確かめる。

## 文章の上限

agent が読む文章（`plugins/bigdaddy/skills/*/SKILL.md` と `plugins/bigdaddy/skills/*/references/*.md`）、README、`docs/*.md` は、`tests/prose-budget/limits.txt` に Unicode の文字数の上限を持つ。`tests/prose-budget/run.sh` は、上限を超えたファイル、`limits.txt` に行の無いファイル、無いファイルを指す行を FAIL にする。

- 書き直して文字数が減ったら、上限をその値に下げる。
- 上限を上げるときは、足した文が無いとどの場面で何を間違えるかを、PR 本文に 1 文で書く。
- 新しいファイルの行は、今の文字数で足す。行はパスの昇順に並べる。

## pstack を上げる

1. [`cursor/plugins`](https://github.com/cursor/plugins) の `harness/pstack/claude-code` の差分を、いまの sha から上げ先の main まで読む。特に `docs/harness/claude-code.md`（モデル表、skill の起動、subagent の項目）、`skills/setup-pstack/SKILL.md`（役割名）、`skills/poteto-mode/SKILL.md`（プレイブックの一覧と書式）を見る。
2. `.claude-plugin/marketplace.json` の `sha` を書き換える。
3. `sh tests/cloud-setup/run.sh <新しい pstack の setup-pstack/SKILL.md>` と `sh tests/route-playbook/run.sh <新しい pstack の poteto-mode/SKILL.md>` を実行する。役割名やプレイブックの一覧が変わっていれば落ちる。
4. `claude plugin marketplace update bigdaddy` を実行し、`claude plugin update pstack@bigdaddy` を実行する。
