# Hooks

How the hooks that bigdaddy registers with Claude Code work. The registration is in `plugins/bigdaddy/hooks/hooks.json`. The tests are described in [docs/development.md](development.md#tests).

## SessionStart

`session-start.sh` puts two things into the context as JSON (`additionalContext`). They are how to choose between briefing and poteto-mode, and that pstack skills are read with the Read tool.

## PreToolUse (Bash), review-push-guard

Before `git push`, the hook compares the head recorded as reviewed in isolation by `review-stamp.sh` of review-triage-loop with the head of the branch. It compares the current branch and the recorded branch named in the command. If anything other than tests and documents changed after the record, the hook blocks the push and asks for a re-review and a new record (and new screenshots if the change is to the UI). It does not block a branch that has no record.

## PreToolUse (Bash, Monitor, terminal execution tools, and merge or direct-write MCP tools), topic-merge-guard

The hook blocks agent tool calls that put changes into the default branch. It derives the default branch from the repository (for a git push destination, `origin/HEAD`, or `gh repo view` if it is absent; for `gh pr merge`, `gh repo view`). It also blocks when it cannot derive the default branch.

What it blocks.

- Pushes aimed at the default branch. `git push` and `git subtree push`. It blocks them even when a record exists. It also checks the settings `push.default=matching` and `remote.*.push`.
- `gh pr merge` whose base is the default branch. This includes `--auto`. It also includes the form `gh pr -R <repo> merge`.
- `/merge`, `mergePullRequest` and `enablePullRequestAutoMerge` in `gh api`, and direct writes to `git/refs`, `contents`, `updateRef` and similar. This includes multi-line input and here-documents.
- MCP tools that merge, and direct-write MCP tools whose destination is the default branch or cannot be read.

A `gh pr merge` whose base is anything else (a topic branch) passes only when all three of the following hold.

- The head SHA of the PR matches the record of `review-stamp.sh`.
- The call pins that SHA with `--match-head-commit`.
- The call is not chained with any command other than cd.

Other handling.

- A call with only `--disable-auto` passes.
- It also blocks forms that cannot use `gh`, and forms where the PR cannot be identified (those that seem to name two or more PRs, including those through xargs).
- Without jq, it blocks input that contains merge, push or `gh api`.
- How a hook timeout is handled is a Claude Code specification. This document cannot decide it.

### Assumptions

The agent and the user act with the same GitHub authentication. GitHub-side protection alone cannot tell them apart. Only a hook on the agent side can. GitHub branch protection and rulesets are also available, so use the hook together with the GitHub-side protection. The hook guards against the agent's misunderstandings and overreach. It does not assume an agent that evades it on purpose. It cannot see indirect execution, such as execution through a script file. A user who merges on the GitHub page or in their own shell uses the intended path, and the hook does not cover it. A candidate for a further layer is an account or token dedicated to the agent.

## PreToolUse (Bash), skill-read-guard

The hook blocks reading `SKILL.md` and playbooks under the plugin cache with cat, sed, head, tail, less, bat or awk. For the pstack `SKILL.md` (including the principles) and playbooks, the hook tells the agent to read the absolute path with the Read tool. For the `SKILL.md` of bigdaddy and yomiyasu, it tells the agent to start `<plugin>:<skill>` with the Skill tool. It also blocks reads through variables and for loops, to stay on the blocking side. It does not block files outside the cache, or ls, rg, grep, find and running scripts. It does not block when jq is absent.

## PostToolUse (Bash)

Only when `BIGDADDY_JEV=1`. Only when `jev.sh`, `route-playbook.sh` or `check-naze.sh` of jev-gates was run, the hook asks for a check by logic-audit in decision mode. It does not cover `route-model.sh`. It does not call Jev.

## Stop (decision audit)

Only when `BIGDADDY_JEV=1`. If a statement in the turn contains a decision that is subject to the audit and there is no decision-mode check, the hook stops once per turn and asks for a check. It does not stop when the Jev key is absent or the call fails.
