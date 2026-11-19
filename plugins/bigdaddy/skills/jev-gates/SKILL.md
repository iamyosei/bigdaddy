---
name: jev-gates
description: >-
  二値判定・候補の絞り込み・アプローチ選定・完了判定を、長い思考や全件 Read やサブエージェントではなく
  Jev（TypeSafe System One）の型付き判断で済ませる手順。briefing と review-triage-loop から呼ばれる。
  Use when a branch decision, candidate pick, scope check, or "is it done" check comes up in the bigdaddy workflow.
---

# Jev gates

Jev は ~100ms で Noul（yes の確率）/ Choice（選択肢の分布）/ Score を返す。入力は安く出力は無料。
長い推論・全件 Read・subagent の代わりに使い、トークンを減らす。

## 有効にする

Jev は既定で無効。`BIGDADDY_JEV=1` を環境変数に置いたときだけ有効になる。`~/.claude/settings.json` の `env` か、クラウドの環境変数に書く。有効のときだけ、`scripts/jev.sh` と hook が判断材料（Stop hook はターンの本文）を `api.typesafe.ai` に送る。

- 鍵は `TYPESAFE_API_KEY`（または `TYPESAFE_API_TOKEN`、キーチェーンの `typesafe-api-key`）に置く。有効なのに鍵が無いと exit 2。
- 無効のときは、`jev.sh`・`route-playbook.sh`（`--criteria` 以外）・`check-naze.sh`・`audit-decision.sh`・`route-model.sh`（`--session` 以外）が stderr に 1 行（`<script>: Jev は無効（BIGDADDY_JEV=1 で有効）`）を出して exit 3 を返す。Stop hook と PostToolUse hook は何も出さない。
- exit 3 のときは、スクリプトの代わりに agent が自分で判断して進める。各 skill に Jev なしの手順がある。決定の記録には「Jev未使用：無効」と書く。exit 3 は失敗ではないので、再試行したり鍵を探したりしない。
- 判定の分岐は `jev.sh` と呼び出しスクリプトの入口、hook の入口にだけある。skill の本文は exit 3 の扱いだけを書く。

## 呼び方

`scripts/jev.sh` を使う。MCP ツール（`jev_verify` など）はこの環境に無い。
Cursor ではエージェントのシェルに `CLAUDE_PLUGIN_ROOT` が入らない。`~/.claude/plugins/installed_plugins.json` の `bigdaddy@bigdaddy` の `installPath` を使う。cursor-jev の MCP（`jev_ask` など）を入れていれば、Cursor ではそれを呼んでもよい。

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/jev-gates/scripts/jev.sh" request.json
```

```json
{
  "state": "判断材料（diff の要約、指摘本文、候補一覧など）",
  "questions": {
    "needs_fix": {"type": "noul", "instructions": "この指摘は現 HEAD で再現する欠陥か？"},
    "approach": {"type": "choice", "instructions": "どの方針が最小か？", "criteria": {"a": "...", "b": "..."}}
  }
}
```

- 出力は `answers` だけ。`.needs_fix.noul`、`.approach.choice` と `.approach.probabilities` を読む。
- `criteria` は文字列で始める。足りなければオブジェクトにする（詳細は typesafe-ai skill）。
- キーの値は表示しない。

### プレイブックの判定

依頼文から pstack の poteto-mode のプレイブックを選ぶときは `scripts/route-playbook.sh "<依頼文と文脈>"` を使う。選択肢は poteto-mode の SKILL.md から毎回作るので、pstack を更新してもずれない。

- 一覧の行を `playbooks/<stem>.md` に解決できないときは、行を出して exit 2 で止まる（pstack の書式が変わった印）。
- `confidence` が 0.5 未満なら top3 を見て自分で決める。
- `none` は本番を書き換える運用作業など、どのプレイブックにも当たらないもの。
- 精度: 2026-10 の履歴 20 件で 19 件正解、1 件あたり約 0.25 秒。外れた 1 件は「件数実測の SQL を実行して」を `none`（0.74）にしたもの。読み取りだけだと分かる文脈を添えると避けられる。

### モデルの判定

調査も実装も、事実を集める、集めたものを整理する、取捨選択して決める、の順に難しくなる。層ごとにモデルを分ける。

| 層 | モデル | effort | 例 |
|---|---|---|---|
| collect（事実を集める） | haiku | high | コードやログを検索する、決まったクエリやコマンドを実行して結果を返す、名前の置換やファイルの削除 |
| organize（整理する） | sonnet | high | 集めた事実をまとめる、設計の決まったコード・テスト・文書を書く、原因の分かったバグを直す |
| decide（決める） | opus | medium | 設計や方針を選ぶ、原因の分からない問題を調べる、差分の正しさや完了を判定する |

モデルと effort の組はこの 3 つに固定する。effort はモデルから決まり、Jev には聞かない。

`scripts/route-model.sh` で層を選ぶ。

- `route-model.sh "<subagent に渡す作業>"` は層を Jev で判定する。
- `route-model.sh --session <playbook>` は実装セッションの主を選ぶ。Jev は呼ばない。`<playbook>` は `route-playbook.sh` が返す stem。
  - `feature`・`refactoring` は sonnet high（organize）。設計の選択は指示書で済んでいるので、主の仕事は決まった設計をコードにする整理になる。完了の判定が要る場面は opus medium の subagent に出し、完了判定の隔離レビューも opus にする。指示書の外に出る設計の選択は、`bigdaddy:briefing` の「親に返すもの」に当たれば親に返し、当たらない局所的なものは自分で決めて「判断の記録」に残す。「本人に必ず返すもの」に当たるときだけ、利用者に返す。
  - `bug-fix`・`perf-issue`・その他のプレイブックと、省略したときは opus medium（decide）。原因がまだ分からず、主が調べて決める役になるため。迷ったら上の層、の方針に合わせて、知らない名前もこちらに倒す。
- 出力は `{model, layer, effort, confidence, bumped, top3}`。`model` は Agent ツールの `model` に、`effort` は `effort` にそのまま渡せる。effort はモデルごとに固定（haiku と sonnet は high、opus は medium）。`--session` では `bumped` は false、`confidence` と `top3` は null。
- layer の `confidence` が 0.5 未満なら一段上の層にする（`bumped` が true、decide はそのまま）。安いモデルで失敗して手戻りすると、かえって高くつくため、迷ったら上の層にする。
- 精度（2026-10 の履歴、1 件あたり約 0.25 秒）:
  - subagent への依頼 20 件の層の判定で 17 件一致。2 回当てて同じ結果。正解は層の定義で付け、判断が割れそうな 3 件は利用者と合意した。外れた 3 件はすべて正解より上の層（collect を decide、organize を decide 2 件）。うち 2 件は依頼の中に案の作成や「守れている / 乖離」の判定を含んでいた。
- 効果は usage-report のモデル別集計（`--json` の `models`）で導入前後を比べる。導入前（2026-09-26〜10-09）の cache read は、Opus が全体の 88.0%、うちメインセッションの Opus が 70.5%、haiku が 0%。主を sonnet に分ける前（2026-10-10〜10-22）の cache read は、opus の本体が 56%、opus の subagent が 26%、sonnet が 18%（本体 4%、subagent 14%）、haiku はほぼ 0%。Feature・Refactoring の主を sonnet に変えたあとは、この値を基準に比べる。見る値は、opus の本体の割合、sonnet の本体の割合、haiku と sonnet の subagent の割合。

## 5 つのゲート

1. **まとめて聞く。** 分岐条件や観点（直す要否・テスト要否・破壊的変更・セキュリティ）は 1 リクエストに束ね、結果で分岐する。1 問ずつ聞かない。
2. **安く篩ってから上げる。** 下書きや静的チェックの結果を Jev で篩い、`P(wrong) > 0.7` などフラグが立った箇所だけ強いモデルで精査する。
3. **該当があるかを先に聞く。** 候補（ファイル・関数・行）を Choice で選ぶときは、同じリクエストに「そもそも該当があるか」の Noul を入れる。`exists < 0.35` なら全件 Read に進まず止まる。
4. **skill を絞る。** タスク開始時に、このターンで本当に要る skill を 1〜2 個に絞ってから読む。
5. **起動前と完了時に聞く。**
   - subagent や大きい探索の前に「インラインで済むか」を Noul で聞き、済むなら起動しない。
   - 起動するなら、渡す作業を `route-model.sh` にかけ、返った `model` と `effort` を Agent の `model` と `effort` に渡す。`subagent_type` は既定で `general-purpose`。poteto-mode のプレイブックの中でコードを書かせる委任先だけ `pstack:poteto-agent` にし、その prompt に poteto-mode の SKILL.md の絶対パスを入れる（poteto-agent はそのパスから skill を読む。パスが無いと止まる）。pstack のスキルが model を指定する役（review、panel など）は、その指定を優先する。
   - `model` を付けずに起動した subagent は、`CLAUDE_CODE_SUBAGENT_MODEL` により sonnet で動く（設定は README のインストール節）。`model` を付ければそちらが優先される。
   - 編集とテストが終わったら「完了か」を Noul で聞き、高ければ念のための再検索をせずに渡す。

### 決定の点検

意思決定を `bigdaddy:logic-audit` の決定モードで点検するときは `scripts/audit-decision.sh <decision.json>` を使う。入力の形と結果の使い方は logic-audit の「決定モード」に書いた。

- 問いは固定で、1 回のリクエストで `important`・`unconfirmed_as_fact`・`missing_alternatives` を返す。
- 閾値はスクリプトの先頭の定数で、初期値はすべて 0.5。
- `jev.sh`・`route-playbook.sh`・`check-naze.sh` を実行すると、PostToolUse hook が決定モードの点検を求める。`route-model.sh` は対象にしない。モデルの選択は後から変えられて重要度が低い。subagent を起動するたびに呼ぶので、毎回点検すると、その手間が節約できる分を減らす見込みが高い（測ってはいない）。

## 判断の記録

決定モードで重要（`record` が true）と判定した判断と、Jev で決めた分岐を、PR 本文の「判断の記録」節に 1 つの表で残す。細かい判断は記録せず、結論の言い方に反映するだけにする。

```markdown
## 判断の記録

| 判断 | 結論 | 前提（確認済み / 未確認） | 退けた代案 | 覆る条件 | Jev |
|---|---|---|---|---|---|
| 指摘 3 を直すか | 直さない | 確認済み: 現 HEAD で型が防ぐ / 未確認: なし | 防御コードを足す | 型の外から値が入る経路が見つかる | needs_fix 0.12、important 0.71 |
```

Jev の列には、決めた問いの値（例: `needs_fix 0.12`）と `important` の値を書く。指示書を作る前段では、PR 本文ではなく指示書の「代理で決めたこと」に同じ項目を書く。
