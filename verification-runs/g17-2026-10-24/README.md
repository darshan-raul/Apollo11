---
title: "G17 — Stage 5–7 images restored to the Stage 4 hardening (2026-10-24)"
description: "Static and image-level evidence for the Stage 5–7 non-root, build-context and metrics fixes."
---

# G17 — Stage 5–7 hardening restored (2026-10-24)

## Changes (Stages 5, 6 and 7)

- All six Dockerfiles run as a numeric non-root user: UID 10001 for the five
  backends, the image's `nginx` UID 101 for the frontend. Numeric so Kubernetes
  `runAsNonRoot` can verify it in Stage 8.
- `.dockerignore` added for every service (copied from Stage 4).
- The frontend uses a lockfile and `npm ci`. `package-lock.json` was generated
  inside `node:22.23.4-alpine3.24` (`npm install --package-lock-only`) for the
  existing Stage 5–7 `package.json`, which is unchanged. The full non-root
  `nginx.conf` (pid and temp paths under `/tmp`) is installed as
  `/etc/nginx/nginx.conf`.
- Identity uses `bcrypt` directly, as in Stage 4; `passlib` is removed from
  `requirements.txt`.
- Stage 5's four Go services and identity serve Prometheus text on `/metrics`
  again (Stage 4's handler; that region was the only difference in `main.go`).
- New static test `test/review/test_images.py`: every Stage 5–7 Dockerfile has a
  numeric non-zero `USER`, a `.dockerignore`, and the frontend a lockfile plus
  `npm ci`.

The 2026-10-22 base images and dependency upgrades, and the Stage 6/7 telemetry
and cache code, are unchanged.

## Evidence

| Check | Result | File |
|---|---|---|
| Build all 18 images (scratch tags `g17-check/stage<N>-<svc>:local`) | 18/18 built | `images.txt` |
| Runtime UID (`docker run --entrypoint id -u`) | 10001 for 15 backend images, 101 for 3 frontends | `images.txt` |
| Trivy gate (`--ignore-unfixed --severity CRITICAL,HIGH --exit-code 1`, Trivy 0.75.0) | 18/18 pass | `trivy/` |
| Frontend smoke (Stage 7 image, non-root) | UID 101; `/healthz/live`, `/healthz/ready`, `/` → 200 | `frontend-smoke.txt` |
| Stage 5 `/metrics` (search image) | UID 10001; Prometheus `# HELP`/`# TYPE` text | `stage5-metrics.txt` |
| Seeded password hashes with direct `bcrypt.checkpw` (inside the Stage 7 identity image) | admin `True`, passenger `True` | `stage5-metrics.txt` (appended) |
| `bash test/ci.sh` (Helm 4.3.1, kubectl 1.37.1) | rc 0; 23 review tests | `../g2a-2026-10-24/ci-local-helm4.log` |

A first scan pass reported 18 failures that came from a zsh `:l` modifier
mangling the image tags in the scan loop, not from Trivy findings. The scans
were rerun under bash; the files in `trivy/` are the rerun.

## Not covered here

The live Stage 5–7 lifecycles on these images, including live login through
the identity service, are G1f.
