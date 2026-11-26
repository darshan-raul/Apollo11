---
title: "CI Pipeline, Published GHCR Images & Local Image Contract"
description: "Shared reference for GitHub Actions CI pins, GHCR image tags, local build-images.sh + kind load, and non-root UID rules."
---

# CI Pipeline, Published GHCR Images & Local Image Contract

Apollo11 stages either build images locally and load them into `kind` (`apollo11/<service>:<tag>`), or pull CI-built, Trivy-scanned images from GitHub Container Registry (GHCR) for Stages 5–7.

---

## 1. GHCR Published Image Contract (Stages 5–7)

- **Image naming:** `ghcr.io/darshan-raul/apollo11/stage{5,6,7}/<service>:<tag>`
  - `<service>` is one of: `identity`, `flight`, `booking`, `search`, `notification`, `frontend`.
- **Stage isolation:** Never mix images across stages. Stage 6 adds OpenTelemetry instrumentation and real Prometheus `/metrics` exposition; Stage 7 adds Redis cache-aside behavior on `search`.
- **Tags published by CI (`docker/metadata-action@v5`):**
  - `sha-<commit>` — immutable tag built on every push.
  - `latest` — updated on pushes to `main`.
  - `v*` — created on Git tag pushes (e.g., `v1.0.0`).
  - **Production tag note:** `values-prod.yaml` and `overlays/prod/` pin `:v1.0.0`, which exists on GHCR only after a `v1.0.0` Git tag is pushed and published by CI; until then, `sha-<commit>` and `latest` are the published GHCR tags.

---

## 2. GitHub Actions CI Pipeline (`.github/workflows/main.yml`)

The workflow runs on `push` to `main` or `tags: ['v*']`, `pull_request` to `main`, and `workflow_dispatch`:

1. **`lint` job (`ubuntu-latest`)** runs `bash test/ci.sh` with pinned tools:
   - **Helm `v4.3.1`** (`azure/setup-helm@v4`) — mandatory because `test/generated.py --check` byte-compares Helm-4-rendered `overlays/base/generated.yaml` (Helm 3 formatting differs).
   - **kubectl `v1.37.1`** (`azure/setup-kubectl@v4`).
   - **Go `1.27.3`** (`actions/setup-go@v5`).
   - `shellcheck` and `PyYAML`.
2. **`build` job (`needs: lint`)** builds all 18 images (`stage: [5, 6, 7]` × 6 services):
   - Parses `viteUrls` from `stages/stageN/helm/apollo11/values.yaml` as build args for `frontend`.
   - Builds with `docker/build-push-action@v6` (`load: true`, tagged `:sha-${{ github.sha }}`).
   - **Trivy scan gate:** Runs `aquasecurity/trivy-action` (commit-pinned `v0.36.0`) with **Trivy `v0.75.0`**, `severity: CRITICAL,HIGH`, `vuln-type: os,library`, `ignore-unfixed: true`, `exit-code: 1`.
   - Saves each scanned image tarball via `docker save` as a workflow artifact (`image-stageN-<service>`).
3. **`publish` job (`needs: build`, on `push` to `main` or `tags: ['v*']`)**:
   - Downloads the exact scanned tarball, loads it (`docker load`), and pushes to GHCR without rebuilding—ensuring the published bytes are identical to the scanned bytes.

---

## 3. Local Build & `kind load docker-image` (`build-images.sh`)

Each stage provides `scripts/build-images.sh` to build local images and load them into the `kind` cluster:

- **Stages 1–4:**
  ```bash
  bash scripts/build-images.sh [--cluster NAME] [--skip-kind-load]
  # Stage 2 also accepts: --scheme http|https
  ```
  Builds `apollo11/<service>:latest` and runs `kind load docker-image "apollo11/<service>:latest" --name "$CLUSTER"` (default `apollo11`).
- **Stages 5–7:**
  ```bash
  bash scripts/build-images.sh [--tag TAG] [--cluster NAME] [--skip-load]
  ```
  Parses `viteUrls` from `helm/apollo11/values.yaml`, builds `apollo11/<service>:<tag>` (default `latest`), and runs `kind load docker-image "apollo11/<service>:${TAG}" --name "$CLUSTER"`.

> **Stage-switch rebuild warning:** Because Stages 1–7 reuse the local tag `apollo11/<service>:latest`, always rebuild when moving between stages (do **not** pass `--skip-build` on your first run in a new stage). Reusing cached images from an earlier stage leaves stale `VITE_*` URLs or missing Stage 6 OTEL / Stage 7 Redis features.

---

## 4. Non-Root UID & Reproducibility Contract (`test/review/test_images.py`)

All Stages 5–7 Dockerfiles enforce:

- **Backends (`identity`, `flight`, `booking`, `search`, `notification`):** numeric `USER 10001:10001`.
- **Frontend (`frontend`):** numeric `USER 101:101` (NGINX non-root with pid/temp paths in `/tmp`).
- **Reproducibility & context hygiene:** every service directory includes `.dockerignore`, and `frontend` commits `package-lock.json` and installs with `npm ci`.
- **Base images (Stages 5–7):** `golang:1.27.3-alpine3.24` (builder) / `alpine:3.24.2` (Go runtime), `python:3.12.15-slim-trixie` (`identity`), `node:22.23.4-alpine3.24` (builder) / `nginx:1.30.6-alpine3.24` (`frontend`).
