# L2 failure mode: api-outage

**Result: PASS**

- **Fault:** `docker stop` on the k3d server container for 60 s, then `docker start`. With `failsafe_mode` off (ADR-002), every member should demote, so writes stop and reads continue. Observed by a Job on an agent node that queried each member by pod IP every second. Its log was read after the API returned, so nothing depends on `make status` or the API during the outage.
- **Run:** 2026-11-25T07:53:30Z (UTC), 213 s
- **Reproduce:** `make test-api-outage`
- **Versions:** k3s `rancher/k3s:v1.35.10-k3s1`, image `pg-ha-postgres:17.12-patroni4.1.5-pgbackrest2.60.1`

## Summary

| Outage (s) | Last write during outage (s) | Rounds with no primary | Reads served | Max primaries in a round | API back (s) | Healthy again (s) | First write after (s) | Result |
|---:|---:|---:|---|---:|---:|---:|---:|---|
| 60 | +9.14 | 55 of 65 | 65 of 65 rounds | 1 | +74.11 | +114.52 | +86.13 | PASS |

Times are seconds after the server was stopped. Write unavailability lasts the whole outage plus recovery, by design.

## Checks

| Check | Result |
|---|---|
| Every member demoted during the outage (writes stopped) | PASS |
| Demotion within 20 s of the outage starting (ttl) | PASS |
| Reads continued on replicas in every outage round | PASS |
| Never more than 1 primary in any round | PASS |
| Never more than 1 member accepted a write in any round | PASS |
| A leader was elected and replication healthy after the API returned | PASS |

## API server outage

Leader before: `pg-1`. Server container `k3d-pg-ha-server-0` stopped at 07:53:37.595 UTC for 60 s. Members by IP: `pg-0=10.42.1.42 pg-1=10.42.3.14 pg-2=10.42.2.19`.

During the outage: last sample with a primary +9.14 s, last successful write +9.14 s. 65 of 65 rounds had a replica answering reads, and 55 rounds had no primary at all. API back at +74.11 s, healthy with leader `pg-0` at +114.52 s, first write after restart +86.13 s.

```console
$ awk -v a=1795593217.595614761 '$3>a-3' /tmp/tmp.mSPQSZoQ7W/r.txt | awk '{printf "%s round=%s %s in_recovery=%s write=%s\n", strftime("%H:%M:%S", $3, 1), $2, $4, $5, $6}' | awk 'NR%3==1 || /write=yes/' | head -40
07:53:34 round=3 pg-0 in_recovery=t write=no
07:53:34 round=3 pg-1 in_recovery=f write=yes
07:53:35 round=4 pg-0 in_recovery=t write=no
07:53:35 round=4 pg-1 in_recovery=f write=yes
07:53:36 round=5 pg-0 in_recovery=t write=no
07:53:36 round=5 pg-1 in_recovery=f write=yes
07:53:37 round=6 pg-0 in_recovery=t write=no
07:53:37 round=6 pg-1 in_recovery=f write=yes
07:53:39 round=7 pg-0 in_recovery=t write=no
07:53:39 round=7 pg-1 in_recovery=f write=yes
07:53:39 round=8 pg-0 in_recovery=t write=no
07:53:39 round=8 pg-1 in_recovery=f write=yes
07:53:40 round=9 pg-0 in_recovery=t write=no
07:53:40 round=9 pg-1 in_recovery=f write=yes
07:53:41 round=10 pg-0 in_recovery=t write=no
07:53:41 round=10 pg-1 in_recovery=f write=yes
07:53:42 round=11 pg-0 in_recovery=t write=no
07:53:42 round=11 pg-1 in_recovery=f write=yes
07:53:43 round=12 pg-0 in_recovery=t write=no
07:53:43 round=12 pg-1 in_recovery=f write=yes
07:53:44 round=13 pg-0 in_recovery=t write=no
07:53:44 round=13 pg-1 in_recovery=f write=yes
07:53:45 round=14 pg-0 in_recovery=t write=no
07:53:45 round=14 pg-1 in_recovery=f write=yes
07:53:46 round=15 pg-0 in_recovery=t write=no
07:53:46 round=15 pg-1 in_recovery=f write=yes
07:53:47 round=16 pg-0 in_recovery=t write=no
07:53:48 round=17 pg-0 in_recovery=t write=no
07:53:49 round=18 pg-0 in_recovery=t write=no
07:53:50 round=19 pg-0 in_recovery=t write=no
07:53:51 round=20 pg-0 in_recovery=t write=no
07:53:52 round=21 pg-0 in_recovery=t write=no
07:53:53 round=22 pg-0 in_recovery=t write=no
07:53:54 round=23 pg-0 in_recovery=t write=no
07:53:55 round=24 pg-0 in_recovery=t write=no
07:53:56 round=25 pg-0 in_recovery=t write=no
07:53:57 round=26 pg-0 in_recovery=t write=no
07:53:58 round=27 pg-0 in_recovery=t write=no
07:53:59 round=28 pg-0 in_recovery=t write=no
07:54:00 round=29 pg-0 in_recovery=t write=no
[exit code 141]
```
