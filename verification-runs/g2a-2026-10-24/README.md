---
title: "G2a — hosted CI validation failure: root cause and fix (2026-10-24)"
description: "Why every hosted CI run failed at the validation step, the reproduction, and the fix."
---

# G2a — hosted CI validation failure (2026-10-24)

## Symptom

Every run of `.github/workflows/main.yml` since 2026-06-17 failed in job
"Helm + Kustomize validate", step "Validate all maintained charts, overlays,
scripts, and tests". Build and publish never ran. GitHub's step timings
(public API) show the step failing in **0 s** on runs 39985772897 (`97232fb`)
and 39684523245 (`f6211e6`), which means the very first command in
`test/ci.sh` failed: `python3 test/generated.py --check`. The job log itself
needs GitHub authentication, so the failing line was reproduced locally
instead.

## Root cause (reproduced)

CI pinned Helm **v3.16.2**. The committed `stages/stage{6,7}/overlays/base/generated.yaml`
and `argocd/platform/observability/generated.yaml` files were rendered with
Helm **v4.3.1**. `test/generated.py --check` compares `helm template` output
byte for byte, and Helm 4 emits one extra blank line between documents (114
lines for Stage 6; there are no other differences).

With the checksum-verified Helm v3.16.2 binary in the scratchpad (not
installed), the check fails exactly as on GitHub, in 0.8 s:

```text
stages/stage6/overlays/base/generated.yaml is stale; run python3 test/generated.py
```

(`generated-check-helm3.16.2.log`)

## Fix

- `.github/workflows/main.yml`: Helm v3.16.2 → **v4.3.1**, kubectl v1.30.0 →
  **v1.37.1**, Trivy v0.70.0 → **v0.75.0**: the versions the local lifecycle
  and image-gate evidence used.
- `test/ci.sh`: prints Helm, kubectl, Go and shellcheck versions first, and
  exits with "test/ci.sh needs Helm 4 …" under Helm 3, instead of reporting a
  misleading "stale" file. Checked by running it with Helm 3.16.2 on `PATH`.
- `stages/stage5/README.md`: documents the pinned CI versions.

## Local result after the fix

`bash test/ci.sh` with Helm v4.3.1 and kubectl v1.37.1: **rc 0** in 45 s,
including the generated-file check, 23 review tests, Helm lint and render for
every environment, Kustomize renders, Argo CD validation, Go tests, and
shellcheck (`ci-local-helm4.log`). This includes the uncommitted G17 changes.

## Still open

A green hosted run is G15. It needs a push to `main`, which needs the user's
approval. Until then this fix is verified locally only.
