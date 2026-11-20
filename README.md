# bigdaddy

利用者の作業流儀で [pstack](https://github.com/cursor/plugins/tree/main/harness/pstack/claude-code)（`cursor/plugins` の Claude Code 版）をラップした Claude Code プラグイン。

- 前段（依頼を十分で本質的な指示書にする）は `bigdaddy:briefing`、後段（実装）は別セッションの pstack の `poteto-mode`。
- pstack の skill はほぼ全部（`setup-pstack` 以外）が `disable-model-invocation: true` で、モデルは Skill ツールで起動できない。`SKILL.md` を Read ツールで読んで従う。利用者が打つときは `/pstack:<name>`。bigdaddy の skill と yomiyasu は Skill ツール。
- 大きい作業（指示書が 2 枚以上）は、親が default branch（例: main）から `topic/<slug>` を切り、子セッションが隔離レビュー済みの PR を自分で topic にマージする。親は、topic を切るときに topic から default branch への PR を draft で作る。各指示書の依存（同じファイルを触るものを含む）は draft PR の一覧に書き、依存がすべて topic にマージ済みの指示書だけを始める。子が全部マージされたら、親が opus medium の subagent で QA を回す。親は、その結果と子の「判断の記録」を draft PR に書いて ready にする。利用者がその PR だけを確かめてマージする。指示書が 1 枚なら default branch 向けの PR 1 本で、利用者がマージする。
- 実装セッションが利用者に聞く項目は `briefing` の「本人に必ず返すもの」の 1 か所にある（default branch へのマージ、本番データへの書き込み、指示書に無い外部送信・feature flag、方針の転換）。外部送信と feature flag は、指示書を作る段階で決める。
- 画面が変わる依頼は、指示書を渡す前に画面設計を作って利用者が合意する。道具は作業リポジトリの指定が先で、無ければ Claude Design。実装役は画面設計を見た目と操作の正本にし、QA が画面設計と実装の画面を照合する。文言・色などの値の差し替えだけの変更は除く。
- 設計や全体の方針を決める意思決定と、目的との照合は、親（briefing）が子に渡す前に済ませる。指示書の「設計」で、実装役が設計の選択をせずに進められる状態にする。指示書の外に出る設計の選択（手段の変更、他の指示書への影響、画面設計との差）は、子が親の id に `SendMessage` で返し、親が決める。
- 隔離レビューの回ごとの範囲は `review-triage-loop` の `references/isolated-review.md` の「回ごとの範囲」に、2 回目以降の blocking を親に送って仕分ける流れは `review-triage-loop` の「2 回目以降の blocking」にある。
- briefing は利用者の代理として質問を減らし、poteto-mode が着手に必要な項目を埋めた指示書を作る。
- pstack と yomiyasu（日本語の文章の推敲）は依存として一緒に入る。どちらも `marketplace.json` で sha を固定している。

## 中身

| skill | 役割 |
|---|---|
| `briefing` | 前段。形を問わず依頼を受け、指示書の空欄を観察・代理回答・質問の順で埋め、必要なときだけなぜなぜ分析で原因を特定して、poteto-mode 向けの指示書で別セッションへ渡す。コードは書かない。代理回答の既定は `references/proxy-answers.md`。手元の `~/.claude/bigdaddy/proxy-answers.md` があれば、そちらを優先して読む |
| `jev-gates` | 分岐・絞り込み・完了判定を Jev で決める手順と `scripts/jev.sh` |
| `review-triage-loop` | 外部レビューの指摘を Jev で仕分け、設計に昇華して直す。隔離レビューの回数と範囲も決める |
| `agent-reasoning-playbook` | 推論・検証・分解・メタ認知のチェックリスト |
| `logic-audit` | 主張と推論を形式論理で検査し、根拠の強さどおりの論証を組む。決定モードでは、作業中の意思決定を 4 項目の記録と 1 回の Jev リクエストで点検する |
| `usage-report` | 会話ログから skill・プレイブック・原則・Jev・subagent の使用回数と、モデル・本体か subagent か・agent の種類ごとのトークン数を集計する。改善点を探すときに使う |

## hook

| hook | 動き |
|---|---|
| SessionStart | briefing と poteto-mode の使い分けと、pstack の skill を Read ツールで読むことを、`session-start.sh` が JSON（`additionalContext`）で文脈に出す |
| PreToolUse（Bash） | `git push` の前に、review-triage-loop の `review-stamp.sh` が記録した隔離レビュー済みの head と、ブランチの先頭を比べる。比べるのは、いまのブランチと、コマンドに名前が出る記録済みのブランチ。記録の後にテスト・ドキュメント以外が変わっていれば、再レビューと記録のし直し（UI の変更ならスクリーンショットの撮り直しも）を求めて止める。記録の無いブランチは止めない |
| PreToolUse（Bash・Monitor・端末の実行ツールと、マージ・直接書き込みの MCP ツール、topic-merge-guard） | default branch に変更を入れる agent のツール呼び出しを止める。default branch はリポジトリから求め（git の送り先は `origin/HEAD`、無ければ `gh repo view`。`gh pr merge` は `gh repo view`）、求められないときも止める。止めるのは、default branch に向く送り（`git push`、`git subtree push`。記録があっても止める。設定の `push.default=matching` と `remote.*.push` も見る）、base が default branch の `gh pr merge`（`--auto` 付きも含む。`gh pr -R <repo> merge` の形も）、`gh api` の `/merge`・`mergePullRequest`・`enablePullRequestAutoMerge` と、`git/refs`・`contents`・`updateRef` などへの直接の書き込み（複数行・ヒアドキュメントも）、マージする MCP ツールと、書き込み先が default branch か読めない直接書き込みの MCP ツール。base がそれ以外（topic branch）の `gh pr merge` は、次の 3 つがすべて成り立つときだけ通す。PR の head SHA が `review-stamp.sh` の記録と一致する。`--match-head-commit` でその SHA を固定している。cd 以外のコマンドとつないでいない。`--disable-auto` だけの呼び出しは通す。`gh` を使えない形、PR を特定できない形（PR の指定が 2 つ以上に見えるもの、xargs 経由を含む）も止める。jq が無いときは、merge・push・`gh api` を含む入力を止める。フックがタイムアウトしたときの扱いは Claude Code 側の仕様で、ここでは決められない |
| PreToolUse（Bash、skill-read-guard） | plugin cache の下の `SKILL.md` とプレイブックを、cat・sed・head・tail・less・bat・awk で読もうとすると止める。pstack の `SKILL.md`（原則を含む）とプレイブックは Read ツールで絶対パスを読み、bigdaddy と yomiyasu の `SKILL.md` は Skill ツールで `<plugin>:<skill>` を起動するよう返す。変数経由や for ループも止める側に倒す。cache の外のファイルと、ls・rg・grep・find・スクリプトの実行は止めない。jq が無いときは止めない |
| PostToolUse（Bash） | `BIGDADDY_JEV=1` のときだけ。jev-gates の `jev.sh`・`route-playbook.sh`・`check-naze.sh` を実行したときだけ、logic-audit の決定モードでの点検を求める。`route-model.sh` は対象にしない。Jev は呼ばない |
| Stop（決定の点検） | `BIGDADDY_JEV=1` のときだけ。ターン内の発言に対象の意思決定があり、決定モードの点検が無ければ、1 ターンに 1 回だけ止めて点検を求める。Jev の鍵が無いときや呼び出しに失敗したときは止めない |

hook のテストは `tests/decision-audit/run.sh`（`BIGDADDY_JEV` 未設定での無効の挙動は鍵なしで確かめる。Jev を実際に呼ぶ検査は `BIGDADDY_JEV=1` を付けたときだけ走り、付けなければ鍵があっても skip する）、`tests/review-push-guard/run.sh`（一時 git リポジトリで回す。鍵は要らない）、`tests/skill-read-guard/run.sh`（鍵は要らない）、`tests/topic-merge-guard/run.sh`（一時 git リポジトリと偽の `gh` で回す。鍵も本物の `gh` も要らない）、`tests/briefing-state/run.sh`（`SKILL.md` の状態の JSON と手順の番号を確かめる。鍵は要らない）で実行する。`route-playbook.sh` の選択肢が pstack の `poteto-mode` の一覧と `playbooks/` に合うことは `tests/route-playbook/run.sh`（鍵は要らない）で確かめる。`cloud/setup.sh` とモデル表のテスト（表が `~/.claude/rules/` に置かれること、表の値が 3 組だけであること、`CLAUDE_CODE_SUBAGENT_MODEL` が入ることを含む）は `tests/cloud-setup/run.sh` で実行する。`tests/decision-audit/run.sh` は `route-model.sh` のモデルと effort の組と、`--session` がプレイブックで主のモデルを分けることも確かめる。

topic-merge-guard の前提。agent と利用者は同じ GitHub 認証で動くので、GitHub 側の保護だけでは両者を区別できず、区別できるのは agent 側の hook になる。GitHub 側のブランチ保護や ruleset も使えるので、hook は GitHub 側の守りと重ねて使う。守る相手は agent の勘違いと先走りで、意図的に回避する agent は想定しない。スクリプトファイル経由などの間接実行は見えない。利用者が GitHub の画面や自分のシェルでマージするのは本来の経路で、対象外。あとから重ねる守りの候補は、agent 専用のアカウント・トークン。

個人の skill とワークフローはここに足す。`~/.claude/skills` に直接置かない。

## インストール

```bash
claude plugin marketplace add iamyosei/bigdaddy
claude plugin install bigdaddy@bigdaddy
```

pstack は依存として一緒に入る。続けて、bigdaddy が持つ pstack のモデル表（`plugins/bigdaddy/pstack-models.md`）を `~/.claude/rules/` に写す。Claude Code は `~/.claude/rules/` の `.md` を毎セッション読むので、`~/.claude/CLAUDE.md` に `@` 行は足さない。

```bash
mkdir -p ~/.claude/rules && cp "$(printf '%s\n' ~/.claude/plugins/cache/bigdaddy/bigdaddy/*/pstack-models.md | sort -V | tail -n1)" ~/.claude/rules/pstack-models.md
```

表は pstack の各役割に使うモデルと effort を `<model> <effort>` で決める。表の値の組は `opus medium`、`sonnet high`、`haiku high` の 3 つだけで、探索と実装は `sonnet high`、判断と文章は `opus medium` に寄せる。arena・architect・interrogate のパネルは `opus medium, sonnet high` の 2 本にしている。fable と xhigh・low は使わない。pstack に hook は無いので、表に hook の設定は要らない。bigdaddy を上げたら同じ `cp` をやり直す。

### Jev を使う（任意）

Jev（TypeSafe の API）は既定で無効。使うときだけ、`~/.claude/settings.json` の `env` に `BIGDADDY_JEV=1` と `TYPESAFE_API_KEY`（キーチェーンの `typesafe-api-key` でもよい）を置く。

```json
{ "env": { "BIGDADDY_JEV": "1", "TYPESAFE_API_KEY": "..." } }
```

有効のときだけ、jev-gates のスクリプトと hook が判断材料（Stop hook はターンの本文）を `api.typesafe.ai` に送る。無効のときは何も送らず、スクリプトは exit 3 を返し、hook は何も出さない。各 skill には Jev なしの手順があるので、無効でも手順は最後まで進む。

以前の手順で `~/.claude/` 直下に `pstack-models.md` を写し、`~/.claude/CLAUDE.md` にそれを読ませる `@` 行を足してある環境では、その `@` 行と直下の `pstack-models.md` を消す。残すと古い表（`strongest judgment`、effort の無い値）が `rules/` の表と一緒に読まれる。

実装セッションの主のモデルは、この表ではなく briefing が指示書の推奨モデルで決める（jev-gates の `route-model.sh --session <playbook>`）。Feature・Refactoring は設計が指示書で決まっているので `sonnet high`、原因が未確定の Bug fix・Perf issue などは `opus medium`。sonnet の主は、完了の判定が要る場面を `opus medium` の subagent に出す。指示書の外に出る設計の選択は親に返す。subagent には `model` と `effort` を Agent の引数で渡す。

最後に、`model` を付けずに起動した subagent を sonnet にする。付けない場合は親のモデル（たいてい Opus）で動いてしまうためで、Agent の呼び出しで `model` を明示すればそちらが優先される。plugin は env を設定できないので、`~/.claude/settings.json` の `env` に自分で入れる。何度実行しても同じ結果になる。

```bash
f=~/.claude/settings.json; [ -s "$f" ] || echo '{}' > "$f"; jq '.env.CLAUDE_CODE_SUBAGENT_MODEL = "sonnet"' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
```

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
- Setup script は `~/.claude/settings.json` の `env` に `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` も入れる（手元では上のインストール手順で入れる）。
- 導入に失敗した項目は、セッション開始時に `bigdaddy-health` hook が警告として文脈に出す。

## pstack を上げる

1. [`cursor/plugins`](https://github.com/cursor/plugins) の `harness/pstack/claude-code` の差分を、いまの sha から上げ先の main まで読む。特に `docs/harness/claude-code.md`（モデル表、skill の起動、subagent の項目）、`skills/setup-pstack/SKILL.md`（役割名）、`skills/poteto-mode/SKILL.md`（プレイブックの一覧と書式）を見る。
2. `.claude-plugin/marketplace.json` の `sha` を書き換える。
3. `sh tests/cloud-setup/run.sh <新しい pstack の setup-pstack/SKILL.md>` と `sh tests/route-playbook/run.sh <新しい pstack の poteto-mode/SKILL.md>` を実行する。役割名やプレイブックの一覧が変わっていれば落ちる。
4. `claude plugin marketplace update bigdaddy` を実行し、`claude plugin update pstack@bigdaddy` を実行する。
