-- L4 data fingerprint (ADR-010). Recorded by backup-job.sh as pgBackRest annotations right before each
-- backup, and recomputed by restore-test.sh on the restored copy. Uses the seeded pgbench tables, which
-- only make seed writes, so a backup taken while the probe writes elsewhere still matches. On a cluster
-- that was never seeded it records seeded=no, which the restore test also compares. Output: key=value lines.
select to_regclass('public.pgbench_accounts') is not null as seeded \gset
\if :seeded
select 'seeded=yes'
union all select format('rows.pgbench_accounts=%s', count(*)) from pgbench_accounts
union all select format('sum.pgbench_accounts=%s', sum(hashtext(a::text)::bigint)) from pgbench_accounts a
union all select format('rows.pgbench_branches=%s', count(*)) from pgbench_branches
union all select format('sum.pgbench_branches=%s', sum(hashtext(b::text)::bigint)) from pgbench_branches b
union all select format('rows.pgbench_tellers=%s', count(*)) from pgbench_tellers
union all select format('sum.pgbench_tellers=%s', sum(hashtext(t::text)::bigint)) from pgbench_tellers t;
\else
select 'seeded=no';
\endif
