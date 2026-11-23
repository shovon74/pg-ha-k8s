# ADR-012: Security baseline

**Status:** Accepted

## Context

Security is scored, but the brief's FAQ places hardening after replication, backup and monitoring.

## Options considered

- **Minimal:** generated secrets and SCRAM only.
- **Layered baseline:** secrets, TLS, SCRAM, NetworkPolicy, RBAC, hardened pods and separate roles.
- **Full hardening:** adds client certificates, rotation and image scanning.

## Decision

Adopt the **layered baseline, built last**.

- **Bootstrap exceptions:** `make certs` and generated Secrets run first, because pgBackRest depends on them (ADR-009).
- **Auth:** SCRAM, with `hostssl` rules in `pg_hba`.
- **TLS:** one deployment CA for Postgres and pgBackRest. Replication uses `verify-full`.
- **Network:** default-deny NetworkPolicies with explicit allows. k3s includes a policy controller, and enforcement must be proven by test.
- **Kubernetes:** namespaced least-privilege RBAC and Pod Security `restricted` on the database namespace.
- **Database:** separate roles for admin, replication, rewind, monitoring, backup, application and read-only access.

cert-manager is excluded because it is an operator (D1).

## Consequences

- Hardening may be cut in priority order if earlier phases overrun, and any cut is documented.
- Default-deny egress may interfere with API access, which spike S2 tests.
- Object-storage traffic is not TLS-protected (ADR-014).

## R-IDs covered

R8.1, R8.2, R8.3, R8.4, R8.5, R8.6, R8.7, R8.8, R11.7
