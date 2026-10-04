---
title: "Stage 8 — Command Module (planned clean rebuild)"
description: "Status and learner-first implementation boundary for the future cluster security and policy stage."
---

# Stage 8: Command Module

> **Status: not implemented. Planned clean rebuild.**

The approved target and migration boundary are defined in [`ROADMAP.md`](../../ROADMAP.md) and [`AGENTS.md`](../../AGENTS.md).

Stage 8 starts from the trusted **Stage 7 baseline** (the hardened 10-component Apollo Airlines stack with Envoy Gateway, StatefulSets, monitoring, and scaling). It receives no trust inheritance from legacy security manifests and will be authored cleanly under the learner-first contract (**Build → Inspect → Break → Recover → Explain**).

## Planned curriculum & sequence

1. **RBAC & Least Privilege**:
   - Least-privilege Roles and RoleBindings per component (deprecating cluster-admin assumptions).
   - Dedicated ServiceAccounts with token projection and disabled default automounts.
2. **Pod Security Standards & Runtime Hardening**:
   - `restricted` Pod Security Admission (PSA) enforcement across application namespaces.
   - Read-only root filesystems, dropping all capabilities, non-root execution (`runAsNonRoot: true`, `runAsUser: 10001`), seccomp profile (`RuntimeDefault`).
3. **Calico NetworkPolicy Lab**:
   - Calico CNI integration on kind to enable observable network policy enforcement.
   - Reversible break/recover isolation experiments: default-deny ingress/egress, explicit pod-to-pod and pod-to-db allowlists.
4. **Secret Management with External Secrets Operator (ESO)**:
   - Moving sensitive database credentials and JWT signing keys out of plain Kubernetes Secrets into HashiCorp Vault / External Secrets.
5. **Admission Control & Supply Chain Security**:
   - Kyverno policy enforcement for image signatures and required labels.
   - Trivy vulnerability scanning and Cosign signature verification in CI.
