# Setup details

Notes that supplement [the README install section](../README.md#install), and how to use it in Cursor and in cloud sessions.

## Model table and subagent model

`plugins/bigdaddy/pstack-models.md` sets the model and effort for each pstack role, as `<model> <effort>`. The table uses only three value pairs, `opus medium`, `sonnet high` and `haiku high`. Exploration and implementation go to `sonnet high`, and judgment and prose go to `opus medium`. The arena, architect and interrogate panels use two entries, `opus medium, sonnet high`. fable, xhigh and low are not used. pstack has no hook, so the table needs no hook setting.

The model of the main agent in an implementation session is decided by briefing, not by this table. For details, see [Workflow](workflow.md#main-model-of-the-implementation-session).

`CLAUDE_CODE_SUBAGENT_MODEL` is set to `sonnet` so that a subagent started without `model` runs on sonnet. Without it, such a subagent runs on the parent model (usually Opus). An explicit `model` in the Agent call takes priority.

## Using Jev (optional)

Jev (the TypeSafe API) is disabled by default. Only when you use it, put `BIGDADDY_JEV=1` and `TYPESAFE_API_KEY` (the keychain entry `typesafe-api-key` also works) in `env` of `~/.claude/settings.json`.

```json
{ "env": { "BIGDADDY_JEV": "1", "TYPESAFE_API_KEY": "..." } }
```

Only when it is enabled, the jev-gates scripts and hooks send material for judgment (for the Stop hook, the text of the turn) to `api.typesafe.ai`. When it is disabled, nothing is sent, the scripts return exit 3, and the hooks output nothing. Each skill has a procedure that does not use Jev, so the procedure runs to the end even when Jev is disabled.

## Migrating from the earlier procedure

If your environment follows the earlier procedure, you have copied `pstack-models.md` directly under `~/.claude/` and added an `@` line to `~/.claude/CLAUDE.md` that makes it read that file. In that case, delete the `@` line and the `pstack-models.md` directly under `~/.claude/`. If you leave them, the old table (`strongest judgment`, values without effort) is read together with the table in `rules/`.

## Using it in Cursor

Cursor (checked on 3.23.12) reads the Claude Code plugins enabled in `~/.claude/settings.json`. After `claude plugin install bigdaddy@bigdaddy`, there is nothing to do on the Cursor side.

- Skills and hooks are read from the Claude Code install location. Update them with the Claude Code procedure (`claude plugin marketplace update bigdaddy` and `claude plugin update bigdaddy@bigdaddy`).
- The SessionStart context also reaches Cursor, because the hook outputs JSON. Cursor discards stdout that is not JSON.
- `CLAUDE_PLUGIN_ROOT` is not set in the shell of the Cursor agent. Call the scripts in the skill procedures from the `installPath` of `bigdaddy@bigdaddy` in `~/.claude/plugins/installed_plugins.json`.

The two known gaps are as follows.

- The Stop hook (`decision-audit-stop.sh`) reads `transcript_path`, but Cursor passes null, so it ends without output.
- `review-push-guard.sh` and `decision-audit-nudge.sh` also run in Cursor, but their behavior there has not been checked.

## Cloud sessions

A cloud session does not read the `~/.claude` on your machine. Paste the contents of `cloud/setup.sh` into the Setup script of the claude.ai environment settings. The Setup script adds bigdaddy with `claude plugin marketplace add iamyosei/bigdaddy`.

- Setup does not run in every session. The state after it ran is reused in later sessions. Even if you update bigdaddy, it does not reach the cloud until Setup runs next.
- Only when you use Jev, set `BIGDADDY_JEV=1` and `TYPESAFE_API_KEY` as environment variables. If it stays disabled, the typesafe plugin is not installed either.
- The Setup script copies the model table from the installed bigdaddy to `~/.claude/rules/pstack-models.md`.
- The Setup script also puts `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` in `env` of `~/.claude/settings.json` (on the local machine, the Install section of the README does this).
- For an item that failed to install, the `bigdaddy-health` hook puts a warning into the context at session start.
