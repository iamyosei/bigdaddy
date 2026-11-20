# Development

Steps for people who change bigdaddy. It covers tests, prose limits and updating pstack.

Add personal skills and workflows to bigdaddy. Do not put them directly in `~/.claude/skills`.

## Tests

Run the hook tests with `tests/decision-audit/run.sh` (the disabled behavior with `BIGDADDY_JEV` unset is checked without a key. Checks that actually call Jev run only with `BIGDADDY_JEV=1`, and are skipped without it even if a key exists), `tests/review-push-guard/run.sh` (runs in a temporary git repository, no key needed), `tests/skill-read-guard/run.sh` (no key needed), `tests/topic-merge-guard/run.sh` (runs with a temporary git repository and a fake `gh`, so neither a key nor a real `gh` is needed), `tests/briefing-state/run.sh` (checks the state JSON and the step numbers in `SKILL.md`, no key needed), and `tests/prose-budget/run.sh` (checks the "Prose limits" section below, no key needed). That the choices of `route-playbook.sh` match the `poteto-mode` list in pstack and `playbooks/` is checked with `tests/route-playbook/run.sh` (no key needed). Run the tests of `cloud/setup.sh` and the model table (including that the table is placed in `~/.claude/rules/`, that the table has only three pairs of values, and that `CLAUDE_CODE_SUBAGENT_MODEL` is set) with `tests/cloud-setup/run.sh`. `tests/decision-audit/run.sh` also checks the model and effort pairs of `route-model.sh`, and that `--session` splits the main model by playbook.

## Prose limits

The prose that the agent reads (`plugins/bigdaddy/skills/*/SKILL.md` and `plugins/bigdaddy/skills/*/references/*.md`), the README and `docs/*.md` each have an upper limit on the number of Unicode characters in `tests/prose-budget/limits.txt`. `tests/prose-budget/run.sh` fails on a file over its limit, a file with no line in `limits.txt`, and a line that points to a file that does not exist.

- If a rewrite reduces the character count, lower the limit to that value.
- When raising a limit, write in one sentence in the PR body what goes wrong, and in which situation, without the added sentences.
- Add a line for a new file with its current character count. Keep the lines in ascending path order.

## Updating pstack

1. Read the diff of `harness/pstack/claude-code` in [`cursor/plugins`](https://github.com/cursor/plugins), from the current sha to main of the target. In particular, look at `docs/harness/claude-code.md` (the items on the model table, skill start and subagents), `skills/setup-pstack/SKILL.md` (role names), and `skills/poteto-mode/SKILL.md` (the playbook list and format).
2. Rewrite `sha` in `.claude-plugin/marketplace.json`.
3. Run `sh tests/cloud-setup/run.sh <new pstack's setup-pstack/SKILL.md>` and `sh tests/route-playbook/run.sh <new pstack's poteto-mode/SKILL.md>`. They fail if the role names or the playbook list changed.
4. Run `claude plugin marketplace update bigdaddy`, then run `claude plugin update pstack@bigdaddy`.
