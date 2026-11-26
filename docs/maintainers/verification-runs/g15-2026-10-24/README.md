---
title: "G15 — first green hosted CI run and GHCR publication (2026-10-24)"
description: "Hosted GitHub Actions run 40009537140 on 6bc371b: lint, 18 builds with Trivy, 18 publishes; anonymous GHCR pulls."
---

# G15 — first green hosted CI run and GHCR publication (2026-10-24)

Commit `6bc371b` (the G2a CI pin and the G17 non-root images), pushed to `main`
with the user's approval.

- Run: <https://github.com/darshan-raul/Apollo11/actions/runs/40009537140>.
  **37 of 37 jobs succeeded**: "Helm + Kustomize validate", 18 builds (each with
  the Trivy gate) and 18 publishes (`jobs.json`). It is the first successful run
  of `.github/workflows/main.yml` since at least 2026-06-17.
- GHCR: anonymous manifest fetches for all 18
  `ghcr.io/darshan-raul/apollo11/stage{5,6,7}/<service>` packages under tags
  `sha-6bc371b` and `latest` returned HTTP 200 (36/36), so the packages are public.
- An anonymous `docker pull ghcr.io/darshan-raul/apollo11/stage7/booking:sha-6bc371b`
  succeeded; the image runs as UID 10001 (`pull.txt`).

The tags are `sha-<short sha>` and `latest`, from `docker/metadata-action`.
Release tag `v1.0.0`, which `values-prod.yaml` pins, still does not exist.
Creating it is a separate decision (see the G15 entry in the tracker).
