# AI session logs

Raw Claude Code session transcripts (JSONL), one file per session, exported by `scripts/export-logs.sh` (R11.2).

They are unedited except for redaction under D5: credentials and personal or cloud identifiers are replaced by visible placeholders such as `[REDACTED-EMAIL]`, `[REDACTED-HOME]`, `[REDACTED-USER]`, `[REDACTED-GCP-PROJECT]`, `[REDACTED-EXTERNAL-IP]` and `[REDACTED:garage-s3-access-key-id]`. Counts per rule and file are in [`redactions.tsv`](redactions.tsv); the redaction log is [`../docs/process/redaction-log.md`](../docs/process/redaction-log.md). The export fails if any value from `./secrets` appears in the output (secret scan, R11.7).

Planning and prompt review were done in a separate Claude chat acting as consultant; those chats are not Claude Code sessions and are not in this folder. See [`../docs/ai-process/README.md`](../docs/ai-process/README.md).

| Session file | First entry (UTC) | Last entry (UTC) | Phase |
|---|---|---|---|
| [`b2ebea08-4f5e-4379-8f0b-730ca89018db.jsonl`](raw/b2ebea08-4f5e-4379-8f0b-730ca89018db.jsonl) | 2026-11-22 18:34:23 | 2026-11-23 10:27:32 | P0 requirements and D1-D9, P1 design options, ADRs, version pins, lean plan |
| [`38dd8981-353b-45be-9a43-7bc7dc3140b6.jsonl`](raw/38dd8981-353b-45be-9a43-7bc7dc3140b6.jsonl) | 2026-11-23 10:40:58 | 2026-11-23 11:16:24 | L0 bootstrap and spikes (S1 Garage debugging; redactions R-001) |
| [`e73dfe31-c4f5-4462-88b4-bec9dcc42812.jsonl`](raw/e73dfe31-c4f5-4462-88b4-bec9dcc42812.jsonl) | 2026-11-23 14:17:20 | 2026-11-25 16:05:00 | L0 review, L1 replication, L2 failover, L3 backup, L4 restore and PITR (redactions R-002) |
| [`d597e1ae-c6c0-481d-b109-4bd17abe23ea.jsonl`](raw/d597e1ae-c6c0-481d-b109-4bd17abe23ea.jsonl) | 2026-11-25 16:13:33 | 2026-11-25 16:58:33 | L5 monitoring and alerting |
| [`ef576bb9-39b0-44b0-8766-fdd633c93e79.jsonl`](raw/ef576bb9-39b0-44b0-8766-fdd633c93e79.jsonl) | 2026-11-25 17:06:36 | 2026-11-26 14:22:12 | L5 completion and L6 security baseline, backup connectivity race |
| [`cf5397ce-e4bd-408e-bf16-e7bd63878dde.jsonl`](raw/cf5397ce-e4bd-408e-bf16-e7bd63878dde.jsonl) | 2026-11-26 14:42:41 | 2026-11-26 16:48:38 | L7 clean run and L8 documentation (README, runbooks, AI-process docs, this export script) |
