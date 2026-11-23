# Working rules

These rules apply to any engineer or AI agent working in this repository. They are tool-independent. Vendor-specific setup belongs in that tool's own context file.

## Roles

- The **lead** makes the decisions and owns every submitted line.
- The **agent** researches, proposes and implements within the current phase, then stops for review.

## Method

1. **Plan before code.** State the plan and get it reviewed before implementing.
2. **Work in small steps.** Each step has a verification command and its expected output.
3. **Stay in scope.** Do only the current phase. Propose anything extra instead of doing it.
4. **State assumptions.** Record anything the lead did not explicitly give.
5. **Prove claims.** A requirement is met only when its acceptance check passes and the evidence is saved.
6. **Report honestly.** Record failures, skipped checks and known gaps as they are.

## Safety

7. **Pin all versions.** Never use `:latest`, floating tags or unpinned tools.
8. **Keep secrets out.** Never put real secrets in files, logs, prompts or chat.
9. **Ask before destructive actions.** Get explicit approval for each one, after looking at the target.
10. **Ask before changing the host.** Keep project tools local to the repository.
11. **Commit only when the lead asks.**

## Traceability

12. **Requirements are the contract.** Reference requirement IDs from `docs/00-requirements.md` in plans, tests and evidence.
13. **Preserve raw session logs.** Redact only credentials and personal or cloud identifiers, use visible placeholders, and record every redaction.
14. **State timezones.** Every evidence timestamp names its timezone.
