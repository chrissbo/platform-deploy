# platform-deploy

GitOps deploy repo for an end-to-end CI/CD pipeline simulation. Argo CD in a
local kind cluster watches this repo; promotions are PRs here.

This repo is the **deploy repo** in a three-repo simulation:

- [`ledger-service`](https://github.com/chrissbo/ledger-service) — the Go service.
- [`platform-golden-paths`](https://github.com/chrissbo/platform-golden-paths) — reusable workflows + policies.
- `platform-deploy` (this repo) — Kubernetes manifests, Kyverno policies, Argo CD Application definitions.

## Structure

```
base/
  kyverno-policies/        # Admission policies (image signature verification)
services/
  ledger-service/          # Namespace + Deployment + Service for the ledger
argocd/
  apps/                    # Argo CD Application CRs (one per workload/policy set)
```

## Trust boundary (MaRisk AT 7.2)

The two-repo separation (code repo + deploy repo) enforces separation of duties:

1. **Bot proposes** — post-merge CI in `ledger-service` opens a PR here bumping the image digest.
2. **Human approves** — a reviewer verifies the digest matches a signed, attested build.
3. **Argo CD syncs** — only after merge to `main`. It cannot deploy unmerged code.

## Admission enforcement (Kyverno)

The `verify-ghcr-signatures` ClusterPolicy requires any image from `ghcr.io/chrissbo/*`
to carry a Cosign keyless signature from `platform-golden-paths/.github/workflows/ci-post-merge.yml@refs/heads/main`.
Pods with unsigned or wrongly-signed images are rejected at admission.

## Status

Phase 3b — Argo CD + Kyverno + ledger-service deployed and syncing.
