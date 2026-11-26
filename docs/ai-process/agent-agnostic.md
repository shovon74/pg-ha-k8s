# Agent-agnostic method

The method does not depend on Claude (R11.4). Generic instructions and vendor-specific setup are kept in separate files.

## Where things live

| File | Vendor-specific? | Content |
|---|---|---|
| [`docs/process/working-rules.md`](../process/working-rules.md) | No | Roles, method, safety and traceability rules for any engineer or agent |
| [`docs/00-requirements.md`](../00-requirements.md) | No | R-IDs, acceptance tests, D1-D9, hard constraints |
| [`docs/01-design-options.md`](../01-design-options.md), ADRs | No | Options, decisions and the lean plan |
| [`docs/process/prompts/`](../process/prompts/) | No | Prompts written to be portable (the Phase 1 prompt was written to be rerun by Gemini) |
| `Makefile`, `scripts/`, `tests/` | No | The work itself. Any agent or person runs the same targets |
| [`CLAUDE.md`](../../CLAUDE.md) | **Yes** | The only Claude-specific file: project context loaded by Claude Code, pointing at the generic files above |
| `ai-logs/` | Yes (format) | Claude Code session transcripts, as evidence of process only |

## What would change with another agent

- **Context file.** Replace `CLAUDE.md` with that agent's equivalent (for example `AGENTS.md` or `GEMINI.md`) with the same short content: goal, key constraints, and "read the working rules, requirements and environment first".
- **Permissions.** Claude Code's permission prompts enforced "ask before destructive actions" and blocked one hand-typed `kubectl exec` (L6 history). Another agent needs its own approval settings for the same rules.
- **Log export.** `scripts/export-logs.sh` reads Claude Code's JSONL files from `~/.claude/projects/`. Another agent stores transcripts elsewhere and in another format, so the copy step changes. The redaction rules and secret scan stay the same.
- **Nothing else.** Requirements, ADRs, prompts, rules, scripts, tests and evidence are agent-independent. The acceptance tests decide whether the work is done, not the agent.
- **Expect different wording and different first proposals.** The gates and the lead's decisions bring the result back to the same place.
