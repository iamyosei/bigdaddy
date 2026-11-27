# 指示書の型

`spawn_task` のプロンプトにそのまま入れる。実装セッションはこの指示書だけを持って始まるので、前段の会話を読まなくても動ける量を書く。`spawn_task` が使えない環境（Cursor など）では、同じ指示書を返信の本文に出し、利用者が新しいチャットに貼れるようにする。
項目は pstack の poteto-mode が着手時に前提にするものから逆算している。推奨モデルの行は、`route-model.sh --session <playbook>` が返すモデルと effort を書き、プレイブックに合う方の役割の文を残す。埋まらない項目は「未定: <理由>」と書き、空欄で渡さない。
指示書が 2 枚以上のときは、各子にこの型を使う（「親に返すもの」の親の id は、どの子も同じ親のもの）。全部の子が topic に入ったあとの QA は、親が subagent に回す。その依頼の型は末尾の「QA subagent への依頼の型」。

```markdown
## 指示書（briefing から）

pstack の `poteto-mode` の SKILL.md と、「使う原則」の原則の SKILL.md を Read ツールで読んでから、<Bug fix / Feature / Refactoring / Perf issue / Visual parity> プレイブックで進める。
推奨モデル: <route-model.sh --session <playbook> の model>、effort: <同 effort>。
<Feature・Refactoring（sonnet high）のとき> このセッションは指示書で決まった設計をコードにする。完了の判定が要る場面は opus medium の subagent に出す（完了判定の隔離レビューも opus）。指示書の外に出る設計の選択は、「親に返すもの」に当たれば親に返し、当たらない局所的なものは自分で決めて「判断の記録」に残す。「本人に返すもの」に当たるときだけ利用者に返す。
<Bug fix・Perf issue など（opus medium）のとき> このセッションは原因の調査、設計、レビュー、完了の判定を受け持つ。
事実の収集と整理の作業は subagent に渡し、モデルは `bigdaddy:jev-gates` の route-model.sh で選ぶ（Jev が無効で exit 3 のときは、次の層の表から自分で選ぶ）（collect は haiku high、organize は sonnet high、decide は opus medium）。
隔離レビューの回し方（どの役割でも同じ）。回ごとの範囲は `bigdaddy:review-triage-loop` の `references/isolated-review.md` の「回ごとの範囲」、2 回目以降の blocking の扱い（直さずに親に送る。「親に返すもの」の（d））は同じ skill の SKILL.md の「2 回目以降の blocking」に従う。

### なぜ
<利用者の言葉での症状と、なぜなぜ分析で特定した根本原因。証拠のパス・URL を付ける>

### 対象
<リポジトリ、ルート、コンポーネント・関数のパス。スクショがあればパス>

### 今 → 望む状態
- 今: <観察した現状>
- 望む: <完了後に観察できる状態>

### データの形
<扱う値・型・持ち主。新しく足すなら名前を付ける。無関係なら n/a: <理由>>

### 設計
<「未定」にしない（opus medium に渡すものを除く）。実装役が設計の選択をせずに進められる状態まで決める。型とシグネチャ（親はコードを書かず、ここに書くだけ）、モジュールやファイルの境界、変えるファイルと関数、要になる手順。データの形は上の節、画面は下の「画面設計」、状態遷移は「状態設計」に書く。重い設計は親が `architect`（SKILL.md を Read ツールで読む）で詰めてから書く。opus medium に渡すもの（原因が未確定の Bug fix など）は「調査のあとに子が決める」と書いてよい。設計が「なぜ」に本質的に沿っているかの点検結果は、「代理で決めたこと」か「仕様で決めたこと」に書く>

### 画面設計
<画面が変わる依頼: 利用者が合意した画面設計の URL を 1 つと、使った道具（Claude Design か、作業リポジトリが指定した道具）と、揃えたデザインシステム。実装役はこの画面設計を見た目と操作の正本にする。画面設計が決めていない細部は DESIGN.md・デザイントークン・周りの画面に揃え、見た目を利用者に聞かない。画面設計どおりに作れないときは、自分で決めず、「親に返すもの」の（c）として親に返す。親が決めた差は、「判断の記録」に親の決定として書く。完了の前に、実装の画面（ブラウザ・シミュレータ）を画面設計と並べて照合し、見つけた差は、「親に返すもの」の（c）として親に返す。親が決めたあとの照合結果は、この URL と一緒に PR 本文に書く。画面設計を開けない（認証切れなど）ときは、利用者に聞かず、照合できなかったと PR 本文に書いて進める。隔離レビュアーにも、この URL を渡して画面を照合させる。topic の子は、最後に QA が全体を照合し直す。
除外のとき（`briefing` の「画面設計」節の基準）: n/a: <理由>>

### 状態設計
<状態遷移が変わる依頼: 利用者が合意した状態設計の Mermaid ソースをコードブロックで貼り、ルールを 1 行ずつ並べる（同じ文を「受入条件・不変条件」の不変条件にも写す）。実装役はこれを状態と移り方の正本にし、ルールごとに、守ることを確かめるテストか確認手順を作り、PR 本文にルールごとの確かめた結果を書く。状態設計どおりに作れないときは、自分で決めず、「親に返すもの」の（c）として親に返す。
実装の後、pstack の `statechart`（SKILL.md を Read ツールで読む）で、コードが状態設計どおりかを照合する。作業はリポジトリの外で行う。
1. 上の Mermaid ソースを `.mmd` に保存して `from-chart` を実行する。書き出された `.tla`・`.cfg` を、合意した spec とする（終了コード 1 は図と spec の差でも出るので、壊れたルールは出力の `is broken` の行で見る）。
2. その `.tla`・`.cfg`・`.map.mjs` を、拡張子の前が同じ新しい名前（例: `Code`）で写し、`.tla` の `MODULE` 行もその名前にして、コードがする状態と移り方のモデルに直す（statechart の SKILL.md の「Pick the direction」の、spec に照らしてコードを監査する段落のとおり。各条件に file:line のコメントを付ける）。
3. `from-spec <コードのモデル> --against <合意した spec> --png` を実行する（合意のときに壊れたままと記録したルールは `--expect-broken` で渡す）。壊れたルールと差のうち、コードの誤りは直し、状態設計どおりに作れないものは（c）で親に返す。バグの経路は、実コードのテストで再現する（同じ SKILL.md の Spec to chart の手順 6）。
4. PR 本文に、ルールごとの結果と、照合に使ったコマンドを書き、コードのモデルの 3 ファイルを `<details>` に貼る。隔離レビュアーにも、この 3 ファイルとコマンドを渡す。file:line の無い条件が残るうちは、ルールが守られているとは書かない。TLC が動かない（mise・ネットワーク・Java）ときは、利用者に聞かず、照合できなかったと PR 本文に書く。
除外のとき（`briefing` の「状態設計」節の基準）: n/a: <理由>>

### 使う原則
着手時に SKILL.md を Read ツールで読む。pstack の skill は（`setup-pstack` 以外）`disable-model-invocation` で Skill ツールから起動できない。途中で一覧に無い原則を使うときも Read ツールで読み、Bash では読まない。SKILL.md は `~/.claude/plugins/installed_plugins.json` の `pstack@bigdaddy` の `installPath` の下の `skills/<名前>/SKILL.md`（原則は `skills/principle-<name>/SKILL.md`）。bigdaddy の skill と yomiyasu は Skill ツールで起動する。
- `principle-<name>`: <この作業でどう効くか>
<2〜4 行>

### 成功条件と確かめ方
<どの画面・API で、どの条件（ログイン状態、端末、件数）で、何が見えたら完了か。数字で言えるものは数字で>
Bug fix で、安く局所的な回帰テストが書けるなら、pstack の `tdd`（SKILL.md を Read ツールで読む）で、直す前に失敗するテストを先に書く。成功条件が画面・CLI・サービスの振る舞いで、作業リポジトリにそれを操作して確かめるスクリプトも project の verification skill も無ければ、pstack の `create-verification-skill`（SKILL.md を Read ツールで読む）で project-local の verification skill（Claude Code では `.claude/skills/verify-<app>/`）を作り、それで確かめる。作った skill は同じ PR の別コミットに入れ、作ったことを PR 本文に書く。
完了の判定と、局所的な設計の選択は `bigdaddy:logic-audit` の決定モードで点検し、重要と判定されたものを PR 本文の「判断の記録」節に書く（「テストが通ったのでバグは無い」ではなく「実行したテストの範囲では再現しない」）。本番影響の「安全」も、隠れた前提（例: feature flag は FE しか守らない）を表に出してから書く。

### 受入条件・不変条件
隔離レビュアーには、この節の原文と差分を渡す。実装役の設計書や判断理由は渡さない。レビューの上乗せ基準は `bigdaddy:review-triage-loop` の `references/isolated-review.md`。
- 不変条件: <「〜は全部。除外は X だけ」の形の閉じた全称で書く。例: 「確認画面に見せた値は全部、確定時の値と照合する。除外は表示用の文言だけ」>
- 列挙: <比べる項目・守る項目を列挙するなら、列挙が不変条件の全量と一致するかを点検してから書く。食い違えば不変条件の側を正本にして列挙を直す>
- 確かめ方: レビュアーは、`bigdaddy:review-triage-loop` の `references/isolated-review.md` の「レビュアーへの指示」のとおり、利用者に見える値から逆にたどって不変条件を確かめる。

### 範囲外
<ついでにやりそうだがやらないこと。別 TODO にしたもの>

### 仕様で決めたこと
<外部への送信（宛先・内容）と新しい feature flag（名前・既定値）のうち、この作業に含めると決めたもの。実装セッションは、ここに書いてある範囲なら聞かずに実行する。含まなければ「なし」。画面設計・状態設計の合意（利用者の返答の要約と日付）もここに書く>

### 代理で決めたこと
<利用者に聞かずに proxy-answers.md で決めた項目と、その根拠>

### 本人に返すもの
<`briefing` の SKILL.md の「本人に必ず返すもの」の節を、そのまま貼る>

### 親に返すもの
親セッションの id: <親が `mcp__ccd_session_mgmt__get_session` の `session_id: "self"` で得た `sessionId`（`local_…`）。得られない環境では「なし。親に返すものは利用者に返す」と書く>
<`briefing` の SKILL.md の「親に返すもの」の節を、そのまま貼る>

### PR とマージ
<次の 2 つのうち、この指示書に当たる方だけを残す>

**単独の指示書（base は default branch）。** PR を作ったら、PR の URL を返して止まる。マージは利用者がする。

**topic の子（base は「repo の約束」の topic）。**
0. PR のタイトルは、「repo の約束」にある ID を使い、`<ID>: <要約>` にする。ブランチ名は `<ID>/<要約>` で、ID が入っている。PR のタイトルとブランチ名とセッションの title は変えない（親が実状態を照合する手がかりにする）。状態の JSON は親だけが書き換え、子は触らない。子はマージしたら終わり、QA は始めない。
1. push の前に、fresh な隔離レビュアーにかける。回ごとの範囲は `bigdaddy:review-triage-loop` の `references/isolated-review.md` の「回ごとの範囲」。2 回目以降の blocking は、冒頭の「隔離レビューの回し方」のとおり親に送る。blocking が 0 件になったら、`review-triage-loop` の `scripts/review-stamp.sh` で head を記録する。
2. 作業ブランチを push し、base=topic の PR を作る。本文に「判断の記録」節を置く。重要と判定されたものが無ければ「なし」と書く。push のあとで head が動いたら（先にマージされた子に追従したときを含む）、記録した head からの差分を 2 回目以降の範囲で再レビューし、記録をし直して、もう一度 push する。
3. CI が緑なら、`gh pr merge <番号> --squash --match-head-commit <記録した head の SHA>`（方式はリポジトリの慣習に従う）を単独のコマンドで自分で実行する。SHA はコマンド置換にせず、そのまま書く（`gh pr view <番号> --json headRefOid` で読める）。PR の指定は番号 1 つだけにする。CI が無いリポジトリでは、記録と PR の head が一致していればよい。`--auto` は使えない。解消の子（default branch を取り込んでコンフリクトを解く指示書）だけは、`--squash` を `--merge` に替える（squash だと default branch のコミットが topic の祖先にならず、親の追従が同じコンフリクトで止まる）。また、default branch の取り込み（`git merge origin/<default branch>`）と push は、別のコマンドで実行する（つなぐと hook が止める）。リポジトリが merge コミットを許さないときは、マージせず利用者に返す。
4. マージしたら worktree と作業ブランチを消す。
5. 解消の子の隔離レビューでは、解消した箇所と、取り込んだ変更との組み合わせを見る。
6. `topic-merge-guard` が止めたら、理由のとおりに直す。base が default branch と言われたら、マージしない。base を topic に直せるなら直す。直せないときは、完了を報告して止まる（default branch 向けの PR のマージは利用者がする）。default branch への `git push` も止まる。
7. 完了の報告には、PR の URL と、topic にマージしたことを書く。

### 文章
PR の概要、Issue、コミット本文、ドキュメントを日本語で書くときは、pstack の `technical-writing` と `unslop`（SKILL.md を Read ツールで読む。Skill ツールでは起動できない）で下書きを書いたあと、最後に `yomiyasu:yomiyasu` を Skill ツールで起動して推敲する。食い違ったときは日本語の表現について yomiyasu を優先する（ドメインは PR・Issue・仕様なら business、設計書・技術記事なら tech）。PR の章立ては repo の PR テンプレートや CLAUDE.md の指定があればそれに従い、無ければ poteto-mode の Opening a PR に従う。英語の文章は `technical-writing` と `unslop` を同じく Read ツールで読む。

### repo の約束
<project の CLAUDE.md が PR に求めるもの。例: バックログの URL（<URL>）、本番への影響を書く節>
<topic の子なら、PR の base（`topic/<slug>`）、ID（ブランチ名・PR のタイトル・セッションの title に入れる）、worktree を topic から切ること>
```

## QA subagent への依頼の型

親は、子が全部 topic にマージされたと確かめたあと、opus medium の新しい subagent に QA を回す（`route-model.sh` に QA の組は無く、判断が主なので決め打ちする）。subagent は変更を書かない。親が `git worktree add <path> origin/topic/<slug>` で topic の checkout を用意し、そのパスを渡す。
渡すのは、各指示書の「受入条件・不変条件」と「成功条件と確かめ方」の原文と、topic と default branch の差分と、画面設計の URL。原文は最終 PR の本文の `<details>` の全文から読む。状態設計のルールは不変条件に写してあるので、「受入条件・不変条件」の原文で一緒に渡る。実装役の判断理由と、子 PR 本文の「判断の記録」は渡さない。レビューの上乗せ基準は `bigdaddy:review-triage-loop` の `references/isolated-review.md`。

```markdown
`topic/<slug>` と default branch の差分を、変更せずに点検する。ファイルを編集しない。topic の checkout は <親が用意した worktree のパス>。

### 受入条件・不変条件
<指示書ごとに、ID と、「受入条件・不変条件」の原文を貼る>

### 成功条件と確かめ方
<指示書ごとに、「成功条件と確かめ方」の原文を貼る>

### 画面設計
<最終 PR の状態の JSON の `design` の URL。null なら「なし」。URL は `Artifact` の `action: "read"` で読める（Claude Design の画面は `project/canvas.json` と、そこに載る `.dc.html`）。作業リポジトリが指定した道具の画面設計は、その道具で開く>

### やること
作業リポジトリの CLAUDE.md・AGENTS.md や project の skill（`.claude/skills/` など。`create-verification-skill` で作った `verify-<app>` を含む）が QA・検証の手順を指定していれば、それを最優先で使う。指定が無いと決める前に、ToolSearch や skill の一覧で探す。指定が置き換えるのは、手順 2 の成功条件の確かめ方（画面・API・CLI・データなど）だけで、手順 1・3・4 は必ず行う。指定が無ければ、手順 2 の画面は標準（ブラウザと iOS シミュレータ）で行い、画面以外は各指示書の「成功条件と確かめ方」に従う。手順の出どころ（リポジトリの指定か標準か）を返す。
1. 差分全体を、`bigdaddy:review-triage-loop` の `references/isolated-review.md` の「レビュアーへの指示」のとおり、利用者に見える値から逆にたどり、各指示書の不変条件に反しないか確かめる。
2. 各指示書の成功条件を、topic の checkout の上で確かめ直す。画面は、リポジトリの指定が無いときは、ブラウザ（built-in browser など）と iOS シミュレータで自分で確かめる。
3. 成功条件を 1 つずつ「確かめた」（証拠: コマンド出力、スクリーンショットのパス、URL と条件）か「確かめられなかった」（理由と、人間が確かめる手順）に分ける。推測で通さない。
3a. 「画面設計」に URL があるときは、画面設計を `Artifact` の `action: "read"` で読み、画面設計の各画面・各状態を、実装の同じ画面・状態のスクリーンショット（ブラウザ・シミュレータ）と並べて照合する。構成・文言・操作・状態の食い違いを finding にする。画面設計が決めている見た目・文言・操作との食い違いは blocking、画面設計が決めていない細部の差は advisory にする。作業リポジトリが指定した道具の画面設計も、その道具で開いて同じように照合する。画面設計の URL をブラウザで開けない（サインインや認証が要るなど）ときは、読んだ `.dc.html` のソースから構成・文言・色・操作を照合し、見た目の並べ比べは「確かめられなかった」にする。画面ごとに「確かめた」（画面設計と実装のスクリーンショットのパス、またはソースとの照合の根拠）か「確かめられなかった」（読めない、画面に着けない、など。理由と人間が確かめる手順）に分ける。
4. 次の 3 つを返す。手順の出どころ（リポジトリの指定か標準か）と確認を行った者、blocking と advisory の一覧（ファイル:行と再現手順つき。blocking が 0 件ならそう書く）と、指示書・条件（画面設計の照合は画面・状態）・結果（確かめた／確かめられなかった）・証拠か理由の表。
```

親は結果を受けて、次のように進める。

- blocking があれば、結果を最終 PR の本文に書き、全体の `qa` を「要確認」にして `reason` に blocking の要約を書き、ready にせず、利用者に返す（`references/topic.md` の手順 4）。利用者の指示（直す指示書を足す、成功条件を書き換える、など）を受けたら、親がその指示どおりに書き換える。直す指示書が画面の構成・操作・状態を変えるときは、先に「画面設計」節のとおり合意を取り直す。直す指示書を足すときは、最終 PR の JSON に新しい行（状態は未着手、`qa` は未）として足し、`references/topic.md` の手順 6 の `start_session` で新しい子を始める。その子が topic にマージされたら、同じファイルの手順 5 の判定に戻る（QA の直前の追従を含む）。再 QA で blocking が 0 件なら、全部の行の `qa` と全体の `qa` を済にする。
- blocking が 0 件なら、対象の行の `qa` と全体の `qa` を済にし、最終 PR（draft）の本文に、poteto-mode の Opening a PR の章立てに沿って、次を書く。
  - `## QA の結果`: subagent の結果の要点、指示書ごとの成功条件の表、確認を行った者（subagent か親か）、手順がリポジトリの指定か標準か
  - `## 人間が確かめること`: 「確かめられなかった」ものだけをチェックリストで（URL・ログイン状態・端末などの条件つき）。無ければ「なし」
  - `## 判断の記録（全子分）`: 子 PR 本文の「判断の記録」（`gh pr view <番号> --json body`）を、指示書ごとに載せる
  - QA の間に default branch が進んで、追従が要るときは、追加の作業として書く。QA の直前の追従は済んでいる。rebase は自動でしない
  - マージのあとで topic を消してよいこと
- 本文は `gh pr edit <番号> --body-file <ファイル>` で渡す（本文の中の語を hook がコマンドと取り違えないようにするため）。そのあと `gh pr ready <番号>` で ready にする。マージはしない（`topic-merge-guard` が止める）。PR の URL を利用者に渡す。
