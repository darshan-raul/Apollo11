---
title: "Stage 10 — Mission Extensions (planned optional missions)"
description: "Status and intended modular shape for advanced Apollo Airlines operational extensions."
---

# Stage 10: Mission Extensions

> **Status: two new optional missions added; live validation status is recorded in the gap tracker. Legacy code/k8s files remain untrusted and must not be applied.**

The approved mission catalog is defined in [`ROADMAP.md`](../../ROADMAP.md).

The existing files contain unverified legacy scaffolding from a different
application. Stage 10 will be rebuilt from the last trusted Apollo Airlines
snapshot.

This stage is not one linear prerequisite chain. It will be a set of optional,
independently runnable missions:

- service mesh and mTLS with Linkerd;
- progressive delivery with Argo Rollouts;
- live debugging with ephemeral containers and Kubeshark traffic inspection;
- advanced disaster recovery building on the required Stage 9 Velero lab; and
- controlled failure experiments with Chaos Mesh.

Lifecycle hooks move to Stage 4, and the baseline DevSecOps pipeline moves to
Stage 8. They are not introduced here as new concepts.

Each mission must begin with a working baseline, introduce one mechanism, run
an observable experiment, and return the cluster to the baseline. A learner
should not need to install every extension to complete the core curriculum.

## New independent missions

- [CloudNativePG](missions/cloudnativepg/README.md): replicated booking-evidence
  data, primary failure, row survival, and separate logical restore.
- [Falco](missions/falco/README.md): harmless runtime event, detection, rule
  mismatch, recovery and cleanup.

Each owns a disposable kind cluster and private kubeconfig. These additions do
not mark the remaining Stage 10 catalog or the Stage 8 baseline complete.
