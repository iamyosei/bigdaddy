# topic の手順（指示書が 2 枚以上のとき）

briefing の SKILL.md の「分ける」節から、指示書が 2 枚以上のときに読む。ここで「「画面設計」節」「「本人に必ず返すもの」」などと書いた節は briefing の SKILL.md の節、`references/` のパスは briefing の skill のフォルダからのパス。

  1. 親（このセッション）が、画面設計の合意（「画面設計」節）を取ったあと（合意した URL は、状態の JSON の `design` に書く）、親の worktree で default branch から `topic/<slug>` を切る。slug は依頼を表す短い英小文字にする。差分が 0 だと PR を作れないので、空のコミットを 1 つ足す。そのあと `git push -u origin topic/<slug>` を単独のコマンドで実行し（`git switch` などとつなぐと hook が止める）、topic から default branch への PR を draft で作る。各指示書に ID（例: `<slug>-01`）を付ける。draft PR の本文に、状態の JSON（手順 2）と、指示書の全文（指示書ごとに `<details>` で折りたたむ）を書く。各指示書の「repo の約束」には、PR の base（topic）と ID を書く。子のブランチ名、子 PR のタイトル、セッションの title には、必ずその ID を入れる（ブランチは `start_session` の `branch_name` を `<ID>/<要約>` にする。title と PR のタイトルは `<ID>: <要約>`）。
  2. 状態は、会話の外に置く。正本は、最終 PR の本文の `## 指示書の状態` 節にある JSON のコードブロック 1 つ。人が読む要約を JSON から書いてよいが、正本は JSON で、親が書き換えるのもこのブロックだけ（本文を `gh pr view --json body -q .body` で読み、このブロックだけを置き換えて、`gh pr edit --body-file` で渡す）。親だけが書き換え、子は触らない。形は次のとおり。

     ```json
     {
       "topic": "topic/<slug>",
       "design": null,
       "briefs": [
         {"id": "<slug>-01", "depends": [], "state": "未着手", "session": null, "pr": null, "qa": "未", "card": null, "started_at": null, "reason": null}
       ],
       "qa": "未実施",
       "reason": null
     }
     ```

     `design` は、利用者が合意した画面設計の URL（画面が変わる依頼でなければ null）。親だけが書き、QA に渡す。
     `state` は 未着手／実行中／PR あり／マージ済み／要確認 の 5 つだけ。`session` は `start_session` が返した id（起動の前は `"starting"`）、`pr` は子 PR の番号、`card` は offer や提案カードの task_id、`started_at` は `start_session` を呼んだ時刻。行の `qa` は 未／済、全体の `qa` は 未実施／実施中／済／要確認。`reason` は、「要確認」のときに理由を短く書く欄（それ以外は null）。遷移は次の表のとおり。

     | 状態 | 次の状態 | 遷移を起こす出来事（親が確かめて書き換える） |
     |---|---|---|
     | 未着手 | 実行中 | 親が `start_session` を呼ぶ前に、状態を実行中、`session` を `"starting"` にして書く。起動できたら id に書き換える。`offer` や提案カードで利用者が始める行も、カードを出す前に `"starting"` にする |
     | 実行中（`"starting"`） | 未着手 | 照合で、起動の実状態（ブランチ、PR、動いているセッション）が無いと確かめた。`session` を null に戻す。`card` があれば、先に `dismiss_task` で片付ける。`start_session` が失敗したときも同じ |
     | 実行中 | PR あり | base が topic の子 PR を見つけた。`pr` に番号を書く |
     | 実行中、PR あり | マージ済み | `gh pr view` で、子 PR が topic にマージされたと確かめた |
     | マージ済み以外のどの行も、全体の `qa` も | 要確認 | 親が、手順 4 の例外を見つけた。`reason` に理由を書き、利用者に返す |
     | 要確認 | 利用者の指示どおり | 利用者の指示を受け、親がその指示どおりに行を書き換え、「要確認」を外す。指示の中身ごとの遷移は決めない |
     | マージ済み | なし | 終わりの状態 |

  3. 表は、最後に観測した値として扱う。親は起きるたびに、判定の前に必ず実状態と表を照合し、食い違えば、実状態を正として JSON を書き直してから判定する。実状態は、ID と一致する origin のブランチ（ID の直後が `/`・`:`・終端のもの）、`gh pr list --base topic/<slug> --state all --json number,title,state,mergedAt,updatedAt,isDraft` の子 PR と、最終 PR の `isDraft`、`list_sessions`（`linked` なしで引き、title が `<ID>: ` で始まるもの）、`git log` の topic。たとえば、`session` が `"starting"` の行は、ID のブランチ、PR、動いているセッションのどれかがあれば、その実状態に直し、どれも無ければ未着手に戻す。全体の `qa` が実施中なら、QA の subagent が動いているか確かめ、動いていなければ未実施に戻す。子を始める前にも、その ID のブランチ・open の PR・動いているセッションが無いか確かめ、あれば新しく始めない。照合では、「要確認」の行の `state` は書き換えず、`session` と `pr` だけを更新する（「要確認」を外すのは、利用者の指示を受けたときだけ）。照合のあとで、手順 4 に当たるものを調べ、当たれば「要確認」にしてから、表だけから判定する。
  4. 次のどれかを見つけたら、親は、該当の行（QA の blocking は全体の `qa`）を「要確認」にし、`reason` を書いて、利用者に返す。返す文面には、親への指示（例: 続けて）が要ることも書く。自動では直さない。
     - 止まった子。子 PR（無ければ子のブランチ、どちらも無ければ `started_at`）の最終更新から 3 時間以上たち、`list_sessions` でそのセッションが動いていないと確かめたとき。または、子が終了を報告したのに、子 PR が topic にマージされていないとき（PR 無しで失敗を報告したときを含む）。
     - QA の blocking。
     - default branch の取り込みや子のマージで出たコンフリクトが、解消の子（手順 6）では収まらないとき。
     - 表と実状態の食い違いを、実状態から一意に直せないとき（マージ済みの行に関わるときは、全体の `qa` を「要確認」にする）。
     - 上の 4 つに当たらなくても、親が照合の結果から次の動作を 1 つに決められないとき。その行（行が決まらなければ全体）を「要確認」にする。判定が黙って止まる経路を残さないための条件。
  5. 親は、子の終了通知（`list_sessions` の `linked: true` と、子の完了の note）で起きる。起きたら手順 3 の照合をし、そのあと表だけから、次の 1 つを選ぶ。親を閉じたあとの再開も、同じ判定から入る。
     - 「要確認」の行か、全体の `qa` が「要確認」なら、待つ（利用者の返答待ち）。新しい子は始めず、QA も回さない。予約は要らない。利用者の指示を受けたら、親がその指示どおりに行を書き換え、「要確認」を外して、手順 3 からやり直す（指示の例: 置き換える、打ち切る、成功条件を書き換えて直す指示書を足す。止まった子には「続けて」だけでは足りない）。
     - 状態が未着手で、依存がすべて「マージ済み」の行があれば、追従（default branch が進んでいたときだけ）と取り込みをしてから、始められる行をすべて始める（手順 6）。
     - 全部の行が「マージ済み」で、全体の `qa` が未実施、または、行の `qa` が未の行があるなら、追従（毎回必ず）をしてから、QA を回す（手順 8）。追従でコンフリクトが出たら、解消の行を足して手順 6 で始め、QA は回さない。全体の `qa` が実施中なら、待つ。
     - 全部の行が「マージ済み」で、行の `qa` がすべて済、全体の `qa` が済で、最終 PR の `isDraft` が false なら、利用者のマージ待ちと伝えて、終わる。`isDraft` が true なら、`gh pr ready` を実行してから伝える。
     - どれでもなければ、待つ。待つときは、待っている行と、再確認する時刻（動いている子のうち最も早い最終更新から 3 時間後。ただし今から 1 時間後より前にはしない）を利用者に伝える。動いている子（実行中、PR ありの行）が 1 つも無いのに待つことになったら、時刻が決まらないので、全体の `qa` を「要確認」にして `reason` を書き、利用者に返す。`ScheduleWakeup` や Monitor が使えるなら、その時刻の再確認を予約する。再開した親は、前の親が始めた子と linked でないので、終了通知が届かない。利用者の依頼のたびに、手順 3 からやり直す。
  6. 子を始める手順。始める前に、origin の topic をローカルの topic に取り込む（`start_session` の `source_branch` はローカルのブランチを取る）。親は topic を checkout したままにしない。push したら元のブランチに戻り、取り込みは `git fetch origin topic/<slug>:topic/<slug>` で行う。子の PR の base は topic で、タイトルは `<ID>: <要約>` にする。子を始める `start_session` の `title` も `<ID>: <要約>`、`branch_name` は `<ID>/<要約>` にする。
     topic を default branch に追従させるのは親の仕事で、rebase と force-push はしない。時機は 2 つ。新しい子を始める前（default branch が進んでいたときだけ）と、QA の直前（毎回必ず）。
     - 親は `git fetch origin` で origin の topic と default branch を取り込む。一時 worktree を `git worktree add --detach <path> origin/topic/<slug>` で作り、`git merge origin/<default branch>` を実行する。
     - きれいに merge できたら、`git push origin HEAD:topic/<slug>` を別のコマンドで実行し（merge と push をつなぐと hook が止める）、一時 worktree を消す。push が non-fast-forward で弾かれたら、worktree を消して作り直し、`git fetch origin` からやり直す。
     - コンフリクトが出たら、親は自分で解かない。途中で止まった一時 worktree で `git merge --abort` を実行し、worktree を消す。そのうえで、解消の指示書を新しい行として JSON に足し（状態は未着手）、待たせる行（子を始める前の追従なら、始めようとした子）の `depends` にも、解消の行の ID を足す。JSON にマージ前の解消の行があるうちは、追従をしない（取り込みだけで子を始める）。解消の子でも収まらないときは、手順 4 のとおり「要確認」にする。
     - 解消の子は、default branch を取り込んでコンフリクトを解き、隔離レビューを通してから、merge コミットで topic にマージする。CI が緑なら、`gh pr merge <番号> --merge --match-head-commit <SHA>` を単独のコマンドで実行する（squash だと default branch のコミットが topic の祖先にならず、追従が同じコンフリクトで止まり続ける）。リポジトリが merge コミットを許さないときは、手順 4 のとおり「要確認」にする。隔離レビューで見るのは、解消した箇所と、取り込んだ変更との組み合わせ。
  7. 子は、隔離レビューで blocking が 0 件になった head を `review-stamp.sh` で記録する。CI が緑なら、子が自分で topic へマージして worktree を消す。子はそこで終わり、QA は始めない。手順は `references/brief-template.md` の「PR とマージ」。
  8. 親は、opus medium の新しい subagent に QA を回す。回す前に、全体の `qa` を実施中にする。QA の手順のうち、成功条件の確かめ方（画面・API・CLI・データなど）は、作業リポジトリの CLAUDE.md・AGENTS.md や project の skill（`.claude/skills/` など）が指定していれば、それを最優先で使う。差分全体のレビューと、成功条件の分類は、指定があっても行う。指定が無いと決める前に、ToolSearch や skill の一覧で探す。指定が無ければ、画面は標準として、subagent がブラウザ（built-in browser など）と iOS シミュレータでの確認を自分で行う。画面以外（API・CLI・データなど）は、各指示書の「成功条件と確かめ方」に従って実行し、出力を証拠にする。QA の結果には、手順の出どころ（リポジトリの指定か標準か）と、確認を行った者（subagent か親か）を書く。subagent がそれらのツールを使えないときは、親が自分で確認する。依頼の型は `references/brief-template.md` の「QA subagent への依頼の型」。渡すのは、各指示書の「受入条件・不変条件」と「成功条件と確かめ方」の原文と、topic と default branch の差分と、状態の JSON の `design`（画面設計の URL。null なら渡さない）で、実装役の判断理由は渡さない。画面設計がある QA は、画面設計と実装の画面を並べて照合する。subagent は topic の checkout の上で確かめるので、親が `git worktree add <path> origin/topic/<slug>` で用意して、そのパスを渡す。
  9. 親は、subagent の結果と、子 PR 本文の「判断の記録」を集めたものを最終 PR の本文に書く。本文は `gh pr edit --body-file` で渡す。QA で「確かめられなかった」成功条件だけを、本文の「人間が確かめること」にチェックリストで載せる。URL・ログイン状態・端末などの条件も書く。載せるのは、物理端末でしか確かめられないもの、本番の外部サービスや本番データが要るものなどの例外に限る。QA の結果を受け取ったら、blocking が 0 件のときは、対象の行の `qa` と全体の `qa` を済にして、ready にする。blocking があるときは、結果を本文に書き、全体の `qa` を「要確認」にして `reason` に blocking の要約を書き、ready にせず、利用者に返す（手順 4）。利用者の指示（直す指示書を足す、成功条件を書き換える、など）を受けたら、親がその指示どおりに書き換える（行を消すときは、その ID を他の行の `depends` からも消す）。直す指示書を足したときは、その行がマージされたあと、QA はその行の差分と落ちた条件だけやり直す（画面の構成・操作・状態を変える修正は、先に「画面設計」節のとおり合意を取り直し、再 QA で当たる全部の画面を照合し直す。直した画面設計とマージ済みの実装との差も、足す指示書が受け持つ。画面設計を開けず確かめられなかった画面は、例外として「人間が確かめること」に載せる）。その再 QA で blocking が 0 件なら、全部の行の `qa` と全体の `qa` を済にして、ready にする。利用者の確認で落ちた条件も、利用者の指示として同じに扱う。親はマージしない。
 10. 利用者が最終 PR を確かめてマージする。マージのあとの topic の削除も利用者が決める。
  - 親を閉じたときは、最終 PR の JSON が状態を持つ。利用者が新しいセッションで briefing に「topic/<slug> の QA」と頼めば、その PR の JSON を読み、手順 3 の照合と手順 5 の判定から、同じ流れで続ける。
- 守るのは文章ではなく hook。`hooks/topic-merge-guard.sh` は、default branch に変更を入れる agent のツール呼び出しを止める。
  - default branch に向く `git push`（記録があっても止める）と `git subtree push`
  - base が default branch の `gh pr merge`（`--auto` 付きも含む）
  - `gh api` の `/merge`・`mergePullRequest`・`enablePullRequestAutoMerge`、`git/refs`・`contents`・`updateRef` などへの直接の書き込み
  - マージする MCP ツールと、ブランチに直接書く MCP ツール（書き込み先が default branch か、読めないとき）

  base が topic の `gh pr merge` は、次の 3 つがすべて成り立つときだけ通す。PR の head が `review-stamp.sh` の記録と一致する。`--match-head-commit` でその SHA を固定している。cd 以外のコマンドとつないでいない。`--disable-auto` だけの呼び出しは通す。hook は default branch をリポジトリから求め、求められないときと PR を特定できないときは止める。
  止められないのは、スクリプトファイル経由・alias・変数展開などの間接実行と、`gh repo edit` のような上に無い書き込み。守る相手は agent の勘違いと先走りで、意図的に回避する agent は想定しない。利用者が GitHub の画面や自分のシェルでマージするのは本来の経路なので、対象外。
