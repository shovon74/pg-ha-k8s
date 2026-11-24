# Redaction log

This log records every redaction made to material submitted with this repository (D5, R11.2). Only credentials and personal or cloud identifiers are redacted, always with a visible placeholder. Redacted values are never written here.

## Status

The raw session logs are not in the repository yet. They are redacted and committed in L8, so entries below marked **Pending** identify what must be replaced at that point.

## Entries

| ID | Date (UTC) | Source | Value type | Placeholder | Occurrences | How to find it | Status |
|---|---|---|---|---|---:|---|---|
| R-001 | 2026-11-23 | Session `38dd8981-353b-45be-9a43-7bc7dc3140b6` (L0), Garage log printed while debugging S1 | Garage S3 access key ID, since rotated | `[REDACTED:garage-s3-access-key-id]` | 24 | Regex `GK[0-9a-f]{24}` | **Pending** (L8) |
| R-002 | 2026-11-23 | Session `e73dfe31-c4f5-4462-88b4-bec9dcc42812` (L0 review), the same log re-read from the transcript while investigating the 136 s hang | Garage S3 access key ID, since rotated | `[REDACTED:garage-s3-access-key-id]` | 20 at last count | Regex `GK[0-9a-f]{24}` | **Pending** (L8) |

Occurrence counts were taken on 2026-11-23 at about 15:10 UTC. Session `e73dfe31` was still running, so recount both logs when applying the redaction.

## Exposure and response

- **What was exposed:** the S3 access key **ID** only. A search of all three session logs for the matching secret key found no occurrences.
- **Response:** the ID and secret key were rotated on 2026-11-23 at about 15:07 UTC, and `make spike-s1` passed on the new pair. See `docs/evidence/L0-spike-S1-history.md`.
- **Repository:** the old ID does not appear in the working tree or in git history.

## Automatic redaction

The spike harness (`scripts/spikes/lib.sh`) replaces any value from `./secrets/credentials` with `[REDACTED:<credential-name>]` before writing evidence files. These replacements are made at generation time, so no unredacted original exists in the repository to log individually.
