# hook

bigdaddy が Claude Code に登録する hook の動き。登録は `plugins/bigdaddy/hooks/hooks.json`、テストは [docs/development.md](development.md#hook-のテスト) にある。

## SessionStart

briefing と poteto-mode の使い分けと、pstack の skill を Read ツールで読むことを、`session-start.sh` が JSON（`additionalContext`）で文脈に出す。

## PreToolUse（Bash）、review-push-guard

`git push` の前に、review-triage-loop の `review-stamp.sh` が記録した隔離レビュー済みの head と、ブランチの先頭を比べる。比べるのは、いまのブランチと、コマンドに名前が出る記録済みのブランチ。記録の後にテスト・ドキュメント以外が変わっていれば、再レビューと記録のし直し（UI の変更ならスクリーンショットの撮り直しも）を求めて止める。記録の無いブランチは止めない。

## PreToolUse（Bash・Monitor・端末の実行ツールと、マージ・直接書き込みの MCP ツール）、topic-merge-guard

default branch に変更を入れる agent のツール呼び出しを止める。default branch はリポジトリから求め（git の送り先は `origin/HEAD`、無ければ `gh repo view`。`gh pr merge` は `gh repo view`）、求められないときも止める。

止めるもの。

- default branch に向く送り。`git push`、`git subtree push`。記録があっても止める。設定の `push.default=matching` と `remote.*.push` も見る。
- base が default branch の `gh pr merge`。`--auto` 付きも含む。`gh pr -R <repo> merge` の形も。
- `gh api` の `/merge`・`mergePullRequest`・`enablePullRequestAutoMerge` と、`git/refs`・`contents`・`updateRef` などへの直接の書き込み。複数行・ヒアドキュメントも。
- マージする MCP ツールと、書き込み先が default branch か読めない直接書き込みの MCP ツール。

base がそれ以外（topic branch）の `gh pr merge` は、次の 3 つがすべて成り立つときだけ通す。

- PR の head SHA が `review-stamp.sh` の記録と一致する。
- `--match-head-commit` でその SHA を固定している。
- cd 以外のコマンドとつないでいない。

そのほかの扱い。

- `--disable-auto` だけの呼び出しは通す。
- `gh` を使えない形、PR を特定できない形（PR の指定が 2 つ以上に見えるもの、xargs 経由を含む）も止める。
- jq が無いときは、merge・push・`gh api` を含む入力を止める。
- フックがタイムアウトしたときの扱いは Claude Code 側の仕様で、ここでは決められない。

### 前提

agent と利用者は同じ GitHub 認証で動くので、GitHub 側の保護だけでは両者を区別できず、区別できるのは agent 側の hook になる。GitHub 側のブランチ保護や ruleset も使えるので、hook は GitHub 側の守りと重ねて使う。守る相手は agent の勘違いと先走りで、意図的に回避する agent は想定しない。スクリプトファイル経由などの間接実行は見えない。利用者が GitHub の画面や自分のシェルでマージするのは本来の経路で、対象外。あとから重ねる守りの候補は、agent 専用のアカウント・トークン。

## PreToolUse（Bash）、skill-read-guard

plugin cache の下の `SKILL.md` とプレイブックを、cat・sed・head・tail・less・bat・awk で読もうとすると止める。pstack の `SKILL.md`（原則を含む）とプレイブックは Read ツールで絶対パスを読み、bigdaddy と yomiyasu の `SKILL.md` は Skill ツールで `<plugin>:<skill>` を起動するよう返す。変数経由や for ループも止める側に倒す。cache の外のファイルと、ls・rg・grep・find・スクリプトの実行は止めない。jq が無いときは止めない。

## PostToolUse（Bash）

`BIGDADDY_JEV=1` のときだけ。jev-gates の `jev.sh`・`route-playbook.sh`・`check-naze.sh` を実行したときだけ、logic-audit の決定モードでの点検を求める。`route-model.sh` は対象にしない。Jev は呼ばない。

## Stop（決定の点検）

`BIGDADDY_JEV=1` のときだけ。ターン内の発言に対象の意思決定があり、決定モードの点検が無ければ、1 ターンに 1 回だけ止めて点検を求める。Jev の鍵が無いときや呼び出しに失敗したときは止めない。
