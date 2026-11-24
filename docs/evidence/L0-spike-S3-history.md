# L0 spike S3: history

This file is maintained by hand. `make spike-s3` writes only the generated results in [`L0-spike-S3.md`](L0-spike-S3.md) and never touches this file.

## Run history

The first run on 2026-11-23 failed because this test script used a bash-only construct under `sh` before initdb. PGDATA had already been created as 0700 by UID 999 in that run. The script was fixed and the complete re-run passed.
