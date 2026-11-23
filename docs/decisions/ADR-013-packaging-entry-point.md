# ADR-013: Packaging and entry point

**Status:** Accepted

## Context

The system needs one documented entry point, clean teardown and reproducible versions, without anything resembling a turnkey chart.

## Options considered

- **Raw manifests + Kustomize:** readable and built into kubectl.
- **Our own Helm chart:** strong parameterisation, but more templating to defend.
- **Plain YAML + `envsubst`:** fewest tools, but fragile.

## Decision

Use **raw manifests with Kustomize overlays** and a **Makefile**. `versions.env` is the single version source. `make tools` installs checksum-verified `kubectl` and `k3d` into a git-ignored `./bin`, leaving system tools unchanged.

Target groups: `preflight`, `tools`, `certs`, `image`, `up`, `down`, `status`, `test-*`, `failover-*`, `backup`, `restore`, `switchover` and `upgrade-minor`.

## Consequences

- A reviewer can read exactly what is deployed.
- Kustomize offers limited parameterisation, so restore differences live in an overlay.
- `make down` must delete only this project's named cluster.

## R-IDs covered

R6.1, R6.2, R6.5, R7.1, R7.2, R7.3, R8.2, R9.2, R12.2
