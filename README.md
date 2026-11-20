# bigdaddy

A Claude Code plugin, an agent workflow that wraps [pstack](https://github.com/cursor/plugins/tree/main/harness/pstack/claude-code). It turns a request into a brief, hands the brief to a separate session that runs pstack's `poteto-mode`, and carries the work to a pull request that has passed isolated review.

## How it works

1. `bigdaddy:briefing` takes the request and turns it into a brief that `poteto-mode` can start from.
2. A separate session runs `poteto-mode` on the brief and implements it.
3. An agent other than the implementer reviews the diff in isolation.
4. The reviewed diff becomes a pull request.
5. You merge the pull request.

When there are two or more briefs, child PRs are collected on `topic/<slug>` and you check one final PR. See [docs/workflow.md](docs/workflow.md).

Four features set it apart.

- Planning and implementation run in separate sessions. `briefing` only writes the brief and never writes code. The child session implements from the brief.
- It limits when it asks you. It does not ask what observation and proxy answers can settle. Once implementation starts, it asks only about merging to the default branch, writing to production data, external sends and feature flags the brief does not name, and a change of direction.
- Agents do not merge. A hook blocks merges and pushes to the default branch.
- A different agent from the implementer does the review. It never sees the implementer's reasoning, and from the second round on it reviews only the fixed diff.

## Requirements

Claude Code, and `git`, `jq`, and `gh`, which the hooks and the skill procedures call.

## Install

```bash
claude plugin marketplace add iamyosei/bigdaddy
claude plugin install bigdaddy@bigdaddy
```

pstack is installed with it as a dependency. Next, copy the pstack model table that bigdaddy carries (`plugins/bigdaddy/pstack-models.md`) to `~/.claude/rules/`. Claude Code reads the `.md` files in `~/.claude/rules/` every session, so do not add an `@` line to `~/.claude/CLAUDE.md`. After you update bigdaddy, run the same `cp` again.

```bash
mkdir -p ~/.claude/rules && cp "$(printf '%s\n' ~/.claude/plugins/cache/bigdaddy/bigdaddy/*/pstack-models.md | sort -V | tail -n1)" ~/.claude/rules/pstack-models.md
```

Last, make subagents started without a `model` run on sonnet. A plugin cannot set env, so add it to `env` in `~/.claude/settings.json` yourself. Running it again gives the same result.

```bash
f=~/.claude/settings.json; [ -s "$f" ] || echo '{}' > "$f"; jq '.env.CLAUDE_CODE_SUBAGENT_MODEL = "sonnet"' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
```

For how the model table works, Jev (optional), and migrating from the earlier procedure, see [docs/setup.md](docs/setup.md).

## Usage

Ask for work in Claude Code as you normally do. The SessionStart hook puts the briefing guidance into context, so `bigdaddy:briefing` takes the request. It writes a brief, hands it to an implementation session, and a pull request comes back after implementation and isolated review. You merge into the default branch.

- "Fix the slow query in the search API"
- "Update the outdated steps in `docs/` to match the current implementation"

To use a pstack skill directly, type `/pstack:<name>`.

### When to use it

- Good fit: a change you want as a reviewed PR. Bug investigation and fixes, new features, refactoring, and work that splits into several PRs.
- Poor fit: answering a question or a one-line fix. Do those directly, without a brief.

### What you may be asked

After the request, `briefing` asks about preferences and specs that observation cannot settle, one to three questions at a time, with a recommendation. Before it hands off, it asks you to confirm when its reading differs from your request, when a proxy decision would be costly to get wrong, or when a screen changes (it shows a screen design URL). Once implementation starts, you are asked only about the four items above.

## Contents

| skill | role |
|---|---|
| `briefing` | Takes a request, turns it into a brief, and hands it to another session. Writes no code |
| `jev-gates` | Procedure and scripts for deciding branches, narrowing, and completion with Jev |
| `review-triage-loop` | Sorts external review findings and fixes them. Also sets the number and scope of isolated review rounds |
| `agent-reasoning-playbook` | Checklist for reasoning, verification, decomposition, and metacognition |
| `logic-audit` | Checks claims and inferences with formal logic and audits decisions made during work |
| `usage-report` | Counts skill and subagent uses and tokens from conversation logs |

| hook | behavior |
|---|---|
| SessionStart | Puts the guidance on when to use briefing and poteto-mode into context |
| `review-push-guard` | Before `git push`, compares against the recorded isolated-review head and blocks if anything other than tests or docs changed after it |
| `topic-merge-guard` | Blocks agent tool calls that put changes into the default branch |
| `skill-read-guard` | Blocks reading a `SKILL.md` or playbook in the plugin cache with Bash read commands such as cat and sed |
| Decision audit (PostToolUse, Stop) | Only when `BIGDADDY_JEV=1`, asks for a decision-mode audit |

For hook details, see [docs/hooks.md](docs/hooks.md).

## Documentation

- [docs/workflow.md](docs/workflow.md): the rules from request to PR, and the role of each skill.
- [docs/hooks.md](docs/hooks.md): what each hook does, and the assumptions behind `topic-merge-guard`.
- [docs/internals.md](docs/internals.md): how the parts relate, where state lives, hook decisions, topic state transitions.
- [docs/setup.md](docs/setup.md): the model table, Jev, migration, Cursor, cloud sessions.
- [docs/development.md](docs/development.md): tests, prose limits, and how to update pstack.

## License

MIT ([LICENSE](LICENSE)).
