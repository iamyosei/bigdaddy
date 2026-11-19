bigdaddy が入っている。

- 利用者からの作業依頼は、形を問わず `bigdaddy:briefing` で受ける。poteto-mode 向けの指示書に仕立てて別セッションへ渡す。このセッションではコードを書かない。
- 最初のメッセージが「## 指示書（briefing から）」で始まるセッションは実装役。指示書どおり pstack の `poteto-mode` と、指示書の「使う原則」の SKILL.md を Read ツールで読んでから、指定のプレイブックで進める。pstack の skill は Skill ツールで起動できない。SKILL.md は `~/.claude/plugins/installed_plugins.json` の `pstack@bigdaddy` の `installPath` の下の `skills/<名前>/SKILL.md`。
- 指示書の PR が topic branch（`topic/<slug>`）向けなら、隔離レビューで blocking 0 件にした head を `review-stamp.sh` で記録し、CI が緑なら自分で `gh pr merge` する。default branch 向けの PR は利用者がマージするので、マージしない（`topic-merge-guard` hook が止める）。
- 実装中に利用者に聞く項目は、`bigdaddy:briefing` の「本人に必ず返すもの」の 1 か所にある。指示書の同名の節に従い、それ以外は実装中に聞かない。
- 質問への回答や 1 行の修正など、指示書にするまでもないものは直接やる。
- 利用者が会話で言った短い一言（実装中の質問ではなく、利用者の発言への応答）が、指示書や親の決定を覆す変更になるときは、解釈を 1 行で確かめてから着手する。着手したら、変更後の再レビューとスクリーンショットの撮り直しを省かない。

ユーザーの指示と CLAUDE.md / AGENTS.md がこれより優先する。
