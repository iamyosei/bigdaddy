---
name: review-triage-loop
description: "Devin や外部 AI/人間のレビュー指摘を鵜呑みにせず、Jev（TypeSafe System 1）を活用して偽陽性・極小リスク・仕様判断を客観トリアージする。要修正事項もアドホックなパッチ当て（if/try-catch追加）でエントロピーを増やさず、型・境界・不変条件・冪等性などシンプルで強靭な設計へ昇華させて反映する。妥当な scope creep が発生する場合は先行リファクタの切り出しをユーザーに提案する（指示書で動く実装セッションは提案せず、PR 本文に follow-up として書く）。トリガー: 'Devinの指摘' 'Devinレビュー' 'レビュー結果をトリアージ' 'レビュー対応' '偽陽性'"
argument-hint: "[PR URL or review comments]"
allowed-tools: Read, Grep, Glob, Bash, Agent
---

# Review Triage Loop

Devin や外部 AI レビュアーの指摘を盲従せず客観的にトリアージし、真に必要な修正だけを「対症療法パッチ」ではなく「シンプルで強靭な設計」へ昇華させて反映する。
LLM 特有の「指摘されたから直さねばならない」という迎合性バイアスを排すため、判定には **TypeSafe Jev（`bigdaddy:jev-gates` の `scripts/jev.sh` で HTTP 呼び出し。MCP ツールは無い）** を積極的に活用する。Jev は `BIGDADDY_JEV=1` のときだけ使う。無効（`jev.sh` が exit 3）のときは、各 Phase の Jev の判定を agent 自身の判定に置き換えてよい。基準と閾値の文はそのまま使い、記録に「Jev未使用：無効」と書く。また、根本解決に伴う scope creep が妥当な場合は、独断で PR を肥大化させず **「先行リファクタ PR の切り出し」をユーザーに提案** する。

---

## コア原則（4箇条）

1. **盲従の禁止（Skepticism First）**: AI レビュアーの指摘の 1〜2 割は偽陽性、2〜3 割は仕様・意図的判断、さらに極小リスクも多い。無条件に直さず反証・却下を第一に疑う。
2. **エントロピー増大の禁止（Anti-Band-Aid）**: 場当たり的な `if (!x) return;`、フォールバック値捏造（`x ?? []`）、状態フラグ追加、広すぎる `try-catch` は厳禁。局所パッチは将来のバグの温床。
3. **設計・方針への昇華（Design Elevation）**: 欠陥を構造・型・境界の歪みのサインと捉え、全体としてよりシンプルで強靭（Robust yet Simple）な構造へ引き上げる。
4. **まとめて 1 push & 全返信（Batch Convergence）**: 1指摘ごとに push しない。全件トリアージ → 一括設計反映 → 隔離レビュー → 1 push → 全返信で収束させる。

---

## 5象限トリアージ判定マトリクス

| カテゴリ | 判断基準 | アクション |
|---|---|---|
| **1. 偽陽性 (False Positive)** | 型システム、DB制約、上位middlewareで既に防御済み、または仕様誤認。 | **修正不要（即却下）**。該当コード・行・型定義を引用して反証クローズ。 |
| **2. 極小リスク (Negligible Risk)** | 発生確率が天文学的、または実害ゼロ。「複雑性コスト ＞ 障害リスク」。 | **修正不要（却下）**。複雑性防止と発生確率のトレードオフを言語化。 |
| **3. 仕様判断・YAGNI** | 仕様書・PR意図に基づく設計。または過度な一般化（YAGNI違反）。 | **修正不要（却下）**。仕様根拠・設計意図を説明。 |
| **4. スコープ外 (Pre-existing)** | 今回の PR 差分以前からの既存問題（今回悪化させていない）。 | **PR除外**。Follow-up Issue を起票して Issue 番号で返信。 |
| **5. 要対応 (Actionable Defect)** | 現実的な操作・入力系列で再現し、ユーザー体験・整合性・認可等に実害がある。 | **要修正**。次節の設計昇華を経て根本修正。 |

> **複雑性テスト（The Complexity Test）**:  
> `複雑性コスト (負債・分岐・認知負荷) vs 発生確率 × 発生時の実害`  
> 人間が 1ms 以内に同一非破壊リクエストを並行送信した際の順序逆転など、実害がなくロック導入リスクの方が大きいものは原則却下。

---

## 設計昇華マトリクス（Design Elevation Matrix）

「要対応」と判定された欠陥は、局所パッチではなく根本設計へ引き上げる。

### やってはいけない対症療法（Anti-Patterns）
- **バンドエイド if**: 根本的な不正状態を許容したまま、下流で `if (!x) return null;` を挟んで握りつぶす。
- **フォールバック値捏造**: `val ?? []` で空配列に潰し、既存設定を全削除する重大事故を招く（Full Replace Settings footgun）。
- **状態フラグの増殖**: `isLoading2`, `isFinished`, `hasAttempted` などの ad-hoc フラグを追加し、状態爆発を起こす。
- **ゾンビ catch**: `try { ... } catch (e) {}` で例外を呑み込み、後段で不可解なバグを引き起こす。

### 4 つの設計昇華アプローチ
1. **Make Illegal States Unrepresentable**: Discriminated Union（`{ status: 'loading' } | { status: 'success', data } | { status: 'error', error }`）等で無効な状態をコンパイル時に排除。
2. **Parse, Don't Validate**: システム境界（API 入力、Zod、DB 境界）で安全な型にパース・正規化し、コアロジックを常に無菌化。
3. **Single Source of Truth & Derived State**: 同期が必要な複数変数を廃止し、根源状態から純関数で導出して同期漏れを根絶。
4. **Idempotent by Design**: メモリ上の一時フラグではなく、DB 一意制約（P2002）、UPSERT、CAS で永続層から冪等性を保証。

---

## 作業ワークフロー

```
[全指摘の収集]
       │
       ▼
[Phase 1: 機械的反証] ────────▶ jev.sh Noul (Claim vs コードEvidence → 偽陽性却下)
       │
       ▼
[Phase 2: 5象限客観分類 ─────▶ jev.sh Choice + Noul (複雑性テスト・YAGNI・極小リスク却下、
          + 到達できる結果の保存]                 修正案が仕様を変えるか)
       │
       ├──【修正案が仕様を変える】──▶ AskQuestion で直し方を 2〜3 案、推奨付きで返す
       │                              （指示書で動く実装セッションは、方針の転換に当たるときだけ）
       │
       ▼ (actionable_defect で、仕様を変えないもの)
[Phase 3: 設計昇華 & Scope Creep判定] ──▶ jev.sh Choice
       │
       ├──【妥当な Scope Creep 発生】──▶ AskQuestion でユーザーへ先行リファクタ提案
       │                              （指示書で動く実装セッションは、PR 本文に follow-up として書く）
       │                                  (Option A: 先行リファクタ PR 切り出し)
       ▼                                  (Option B: 本 PR に含める / Option C: Issue起票)
[Phase 4: TDD & 根本実装] ────▶ jev.sh Noul (scope)
       │                        (再現テスト → Green → rg 横断点検)
       ▼
[Phase 5: 隔離レビュー & 収束] ▶ jev.sh Noul (ready)
                                (隔離レビュー → スタンプ → 1 push → 全指摘へ客観的返信)
```

### Phase 1: 現 HEAD 実在確認と、Jev・logic-audit による反証
1. 指摘されたファイルを行単位で開き、現 HEAD を直接確認（snapshot ズレや既修正を排除）。
2. レビュアーの主張（Claim）に対し、現 HEAD の型・スキーマ・guard を Evidence として `jev.sh` の Noul（「この主張は現 HEAD で成り立つか」）を実行する。
   - 値が低い指摘は偽陽性の候補。閉じる前に `bigdaddy:logic-audit` の決定モードで「偽陽性として閉じる」判断を点検する。反例（主張の前提を満たすのに欠陥が起きない、現 HEAD の具体的な行）を「確認済み」の前提に書けたときだけ閉じる。`flags` が出たら監査モードの本来の手順で精査する。Jev の値だけで閉じない。
   - 「X が無い / 呼ばれていない」型の主張は、存在の無断仮定になりやすい。該当行を自分で開いて確かめる。

### Phase 2: `jev_classify` による 5 象限客観トリアージ
残った指摘一覧を `jev.sh` の Choice にバッチ投入（`auto_accept: 0.85`, `minimum_margin: 0.50`）。
- **Classes**:
  - `false_positive`: 型・DB・上位層で防止済みの事実誤認
  - `negligible_risk`: 発生確率が極小（天文学的確率）、または実害ゼロ。防護コードの複雑性リスクが障害リスクを上回るもの
  - `intentional_yagni`: 仕様書・PR意図に基づく設計、または不要な将来拡張
  - `out_of_scope`: 今回の変更以前からの既存問題
  - `actionable_defect`: 現実的な操作系列で再現し実害がある真の欠陥
- **判定と方針**:
  - `negligible_risk` / `intentional_yagni`: トレードオフ・仕様理由を明記して却下。
  - `out_of_scope`: Follow-up Issue を起票して PR スコープから除外。
  - `actionable_defect`: Phase 3 へ進める。
  - 文章（SKILL.md、references、指示書の型、README、docs/*.md）への追加を求める指摘は、`references/isolated-review.md` の「文章への finding」で判定する。
- 同じリクエストに、次節の「到達できる結果の保存」の Noul を指摘ごとに入れる。
- 直すか直さないかの判定は、指摘ごとに `bigdaddy:logic-audit` の決定モードで点検する。`jev.sh` を実行すると hook が点検を求める。重要と判定されたものは PR 本文の「判断の記録」節に書く。

### 到達できる結果の保存
欠陥かどうかと、直し方が仕様を変えるかどうかは別の問い。欠陥と判定しても、直し方は Phase 3 に進む前にここで点検する。

1. 指摘ごとに 3 つを書く。
   - 指摘が欠陥として挙げた結果
   - 修正案（レビュアーの提案か、最も素直な直し方）を 1 行
   - 修正の前後で利用者が到達できる状態・操作・結果を比べ、修正で消える・変わる結果の一覧
2. 分ける。
   - 一覧が欠陥として挙げた結果だけなら、そのまま直す（Phase 3 へ）。
   - 欠陥以外の結果も消える、変わる、別の利用者群に効く（経路を塞ぐ、振り分け先を変える、既定値を変える）なら、仕様の判断。自分で直さず、直し方を 2〜3 案並べて推奨を付け、`AskQuestion` でユーザーに返す。PR 本文の 1 行で済ませない。指示書で動く実装セッションは、`bigdaddy:briefing` の「本人に必ず返すもの」の方針の転換に当たるときだけ、ユーザーに返す。当たらなければ自分で決めて「判断の記録」に残す。
   - 例: 条件を満たさない選択肢を押せなくする修正は、誤った実行を消すと同時に、その選択肢から先へ進む別の経路も消す。これは仕様の判断。
3. Jev では Phase 2 の Choice と同じリクエストに、指摘ごとの Noul `<id>_changes_spec` を入れる。`state` に 1. の 3 つを指摘ごとに見出しを付けて書き、問いは「[<id>] の『修正で消える・変わる結果』の中に、『指摘が欠陥として挙げた結果』に当たらないものがあるか」。0.4 以上なら仕様の判断として扱う。前後の集合を並べただけで聞くと値が分かれにくいので、差分の一覧にしてから聞く。

### Phase 3: 要対応事項の設計昇華 & Scope Creep 判定
1. **設計昇華パターンの選定 (`jev.sh` の Choice)**:
   - `actionable_defect` について、安直なパッチ当て（if/try-catch追加）を排し、4つの設計パターンから方針を決定。
   - Priorities: "Eliminate ad-hoc boolean flags. Minimize codebase entropy and cognitive overhead. Prefer compile-time safety and single-source-of-truth."
2. **変更半径（Blast Radius）と Scope Creep の判定**:
   - 根本修正にあたり、周辺の構造的歪み（責務過密、型定義の不整合、状態爆発）により変更半径が大きくなるかを評価。
   - **不当な Scope Creep**: ついでリファクタ、無関係な cleanup → 即座に排除。
   - **妥当な Scope Creep**: 根本修正に不可欠な構造改善（これを行わないとバンドエイド修正しか選べない状況）。
3. **妥当な Scope Creep 時の先行リファクタ提案（Make the change easy）**:
   - 独断で現在の PR に巨大な設計変更を混ぜず、また汚い局所パッチに妥協せず、**ユーザーに「先行リファクタ PR の切り出し」を提案**する（`AskQuestion` 使用）。指示書で動く実装セッションは提案せず、follow-up として PR 本文に書く。
   - **提案プロトコル**:
     - *現状の歪み*: 既存コードの何が根本修正のボトルネックになっているか
     - *先行リファクタの内容*: 責務分離、型定義整理、SSoT化
     - *選択肢*:
       - **Option 1 (Recommended)**: 先行リファクタ PR を切り出し、マージ後に本 PR で本来の修正をスッキリ適用する（"Make the change easy, then make the easy change"）
       - **Option 2**: 本 PR 内に含めて一括で設計昇華を実施する（PR レビュー負荷増を許容）
       - **Option 3**: 今回は安全な最小局所修正にとどめ、根本リファクタは別途 Issue 起票する（即時リリース優先）

### Phase 4: TDD & 根本実装 & 全体整合性点検
1. **再現テストの追加**: 不具合を再現する behavior test を書く（RED）。
2. **根本実装**: 設計方針に沿って実装し、テストを通過させる（GREEN）。
3. **同型パターンの横断検索**: `rg` でリポジトリ全体を検索し、同じ脆弱性や不整合を抱えた箇所があれば同時に解消する。

### Phase 5: Agentic Loop re-entry & 1 push & 全指摘返信
1. **検証と隔離レビュー**: `bun run lint` / `bun run typecheck` / テストをパスし、fresh 隔離 subagent レビューを通す。repo のレビュー手順に `references/isolated-review.md` の基準を上乗せする。
2. **スタンプ**: blocking が 0 件になったら（親が「直さない」「別 PR」と返して「判断の記録」に書いたものは数に入れない） `"${CLAUDE_PLUGIN_ROOT}/skills/review-triage-loop/scripts/review-stamp.sh"` で、レビューした head を記録する。この後に振る舞いを変えるコミットを足すと、push 前の hook が止める。そのときは記録した head からの差分を再レビューし（範囲は `references/isolated-review.md` の「回ごとの範囲」のとおり）、0 件で記録し直す。UI の変更ならスクリーンショットも撮り直す。
   Cursor ではエージェントのシェルに `CLAUDE_PLUGIN_ROOT` が入らない。`~/.claude/plugins/installed_plugins.json` の `bigdaddy@bigdaddy` の `installPath` を使う。
3. **まとめて 1 push**: 全指摘への対応・設計改善を 1 コミット / 1 プッシュに集約する。
4. **Devin への客観返信例**:
   - **偽陽性**: `Guaranteed unreachable by type/DB constraint (see packages/.../schema.ts:42). No changes needed.`
   - **極小リスク却下**: `Evaluated theoretical edge case. Negligible probability; adding locks/flags introduces state complexity & deadlock risks exceeding the benefit. Intentionally kept simple.`
   - **設計昇華修正**: `Good catch. Elevated to data model: replaced ad-hoc flags with Discriminated Union in types/state.ts, added tests in tests/state.test.ts. Resolved in <commit-hash>.`

### 2 回目以降の blocking（隔離レビューの回数と範囲）
隔離レビューを毎回全体にかけると、毎回新しい advisory や周辺の穴が出て、直しとレビューが収束しない。範囲と流れを次のとおりに固定する。

1. **範囲。** 回ごとにレビュアーに渡す差分と、返させる finding は、`references/isolated-review.md` の「回ごとの範囲」に従う。
2. **blocking が出たら。** 2 回目以降で blocking が出たら、実装役は直さずに指摘の全文を親に送る（`briefing` の「親に返すもの」の（d））。前回送った指摘と同じ周辺かも 1 行で書く。親は指摘ごとに「目的に本質的で直す」「直さない（理由）」「別 PR」に仕分けて、同じ送信元に返す。必要と判断したときだけ、全体の再レビューを指示する。実装役は、親が「直す」と返したものだけを直し、その差分を次の回のレビューにかける。親が応答できないときは、止めた部分を未決として PR 本文に書き、利用者に返す（`briefing` の「親に返すもの」の「返し方」の最後の項目。topic の子は、その間 topic にマージしない）。
3. **同じ周辺で続けて出たら。** 2 回目以降の再レビューで、同じ周辺（同じファイルの同じ節・関数、または同じ不変条件の項目）に blocking が 2 回続けて出たら、親はその部分を PR から外して別 PR にするかを判断する。外すなら、実装役がその部分の差分を戻し、follow-up として PR 本文に書く。成功条件を書き換えないと完了できなくなるときは、方針の転換なので、親が利用者に返す。
4. **記録。** 仕分けの結果と外す判断は、親が実装役に返し、実装役が PR 本文の「判断の記録」に親の決定として書く。直さない理由と、別 PR にしたものの扱いも書く。
