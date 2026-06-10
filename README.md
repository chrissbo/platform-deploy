# platform-deploy

GitOps deploy repo for an end-to-end CI/CD pipeline simulation. Argo CD in a
local kind cluster watches this repo; promotions to staging/prod are PRs here.

This repo is the **deploy repo** in a three-repo simulation:

- [`ledger-service`](https://github.com/chrissbo/ledger-service) — the Go service.
- [`platform-golden-paths`](https://github.com/chrissbo/platform-golden-paths) — reusable workflows + policies.
- `platform-deploy` (this repo) — Helm/Kustomize manifests, Argo CD `Application` definitions, environment overlays.

## What lives here

```
apps/
  ledger-service/
    base/                  # Common manifests
    overlays/
      staging/             # Image digest pinned per release
      prod/                # Image digest pinned per release
argocd/
  applicationsets/         # ApplicationSet for ephemeral PR namespaces
  applications/            # Per-environment Application definitions
```

The two-repo separation (code repo + deploy repo) mirrors the MaRisk AT 7.2
separation-of-duties pattern described in the parent research.

Plan and feasibility analysis:
[`research/cicd-toolchain/local-simulation-feasibility.md`](https://github.com/chrissbo/upvest-platform/blob/main/research/cicd-toolchain/local-simulation-feasibility.md).

## Status

Phase 0 — bootstrap. Manifests and Argo CD applications still to come.
