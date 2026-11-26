# Stage 5 Author Before Bootstrap — Helm Values, Helpers, Schema & Kustomize Patch

Before bootstrapping the full Stage 5 fleet with `stages/stage5/scripts/apply.sh`, practice authoring a scoped packaging change in both Helm and Kustomize completely offline.

## Workspace Layout

- `starter/` — baseline scoped workspace (`chart/` + `kustomize/`) for the `booking` service.
- `work/` — your working copy (git-ignored; automatically initialized from `starter/` on first run of `check.sh`).
- `solution/` — reference implementation for comparison after you finish.
- `check.sh` — offline validator (`helm lint`, `helm template`, `values.schema.json` negative test, and `kubectl kustomize`).

## Tasks

Initialize `work/` (or let `check.sh` create it):

```bash
cp -R learner-work/stage5/starter learner-work/stage5/work
```

Edit files inside `learner-work/stage5/work/`:

1. **Add a new Helm chart value (`chart/values.yaml`):**
   Under `apps.booking`, add `releaseChannel: stable`.

2. **Add a template helper and wire it into `booking` (`chart/templates/_helpers.tpl` and `chart/templates/booking.yaml`):**
   - In `chart/templates/_helpers.tpl`, define `apollo11.releaseAnnotations`:
     ```gotemplate
     {{- define "apollo11.releaseAnnotations" -}}
     apollo.airlines/release-channel: {{ .channel | quote }}
     {{- end -}}
     ```
   - In `chart/templates/booking.yaml`, under `spec.template.metadata`, add:
     ```yaml
           annotations:
             {{- include "apollo11.releaseAnnotations" (dict "channel" $appCfg.releaseChannel) | nindent 8 }}
     ```

3. **Constrain the value in JSON Schema (`chart/values.schema.json`):**
   In `definitions.app`:
   - Add `"releaseChannel"` to `"required"`.
   - Add `"releaseChannel"` under `"properties"` with `"type": "string"` and `"enum": ["canary", "stable", "lts"]`.

4. **Author a Kustomize production patch (`kustomize/overlays/prod/`):**
   - In `kustomize/overlays/prod/booking-patch.yaml`, change `apollo.airlines/release-channel` from `stable` to `lts`.
   - In `kustomize/overlays/prod/kustomization.yaml`, wire the patch:
     ```yaml
     patches:
       - path: booking-patch.yaml
     ```

## Verify

```bash
# Fails on starter/ (expected: 1 passed, 9 failed)
bash learner-work/stage5/check.sh starter

# Check your work/ directory (auto-copies starter/ -> work/ if absent)
bash learner-work/stage5/check.sh

# Inspect diff against starter and verify the reference solution
diff -ru learner-work/stage5/starter learner-work/stage5/work || true
bash learner-work/stage5/check.sh --solution
```

Once `bash learner-work/stage5/check.sh` exits `0`, continue with `stages/stage5/README.md` (`apply.sh`).
