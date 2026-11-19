# pstack model configuration. One line per role. Delete a line to fall back to the skill default.
# `inherit-parent` or `auto` as a value: the role runs on the parent chat model (omit Agent `model`). Alias entries in a panel list still count toward its fan-out.
# A value is `<model> <effort>`, passed to the Agent call as `model` and `effort`. The values in this sheet use only three pairs, `opus medium`, `sonnet high` and `haiku high`. The role lines are set by hand, so do not rerun `/setup-pstack` over it.
# budget: medium (high)
feature, refactoring: sonnet high
bug-fix: opus medium
perf-issue: opus medium
hillclimb: opus medium
judgment and prose: opus medium
hardest tasks: opus medium
how explorer: sonnet high
how explainer: opus medium
why investigators: sonnet high
why synthesizer: opus medium
reflect tooling: sonnet high
reflect judgment, divergent, synthesizer: opus medium
arena runners: opus medium, sonnet high
arena cross-judge pool: opus medium, sonnet high
swarm workers: sonnet high
architect runners: opus medium, sonnet high
interrogate reviewers: opus medium, sonnet high
