# Troubleshooting & Lab Evidence Template

Copy this template into `learner-work/stageN/work/<lab-or-drill>.md` (ignored by Git) when recording a Break/Recover experiment or Blind Troubleshooting fault drill. Follow the **Ignition 5-Rung Evidence Ladder** (`Status -> Events -> Detail -> Logs -> Behavior`) and stop once you have proven the root cause—then prove recovery with real behavioral output, not just `Running`.

---

## Metadata

- **Stage / Lab / Drill ID:** `<e.g. Stage 4 / Fault Drill 01>`
- **Date (UTC):** `<YYYY-MM-DDTHH:MM:SSZ>`
- **Cluster Context:** `<kubectl config current-context>`
- **Namespace(s):** `<e.g. apollo-airlines-apps, apollo-airlines-ui>`

---

## 1. Symptom

What failed, timed out, returned an unexpected HTTP status, or fired an alert/metric?

```text
<paste observed symptom or failing curl/UI/alert output>
```

---

## 2. Command Output (Ignition 5-Rung Evidence Ladder)

Record each rung you inspected until the root cause was isolated:

### Rung 1 — Status
> *Is the workload Pending, Running, CrashLoopBackOff, or unready? Where is it placed?*

```bash
kubectl get pods,deploy,svc,httproute -n <namespace> -o wide
```

```text
<paste output>
```

### Rung 2 — Events
> *What scheduling, probe, pull, or controller decisions occurred over time?*

```bash
kubectl get events -n <namespace> --sort-by=.metadata.creationTimestamp | tail -20
```

```text
<paste output>
```

### Rung 3 — Detail
> *Which image, selector, Secret, probe path, condition, or event explains the status?*

```bash
kubectl describe <resource>/<name> -n <namespace>
```

```text
<paste output>
```

### Rung 4 — Logs
> *What did the application or controller process report?*

```bash
kubectl logs <pod> -n <namespace> [--previous]
```

```text
<paste output>
```

### Rung 5 — Behavior
> *Can a user or downstream caller obtain the expected HTTP response, metric, or trace?*

```bash
# Examples:
# kubectl port-forward -n <ns> svc/<svc> 8082:8082 && curl -i http://127.0.0.1:8082/readyz
# curl --cacert /tmp/apollo-ca.crt --resolve "booking.apollo.local:443:${gateway_ip}" https://booking.apollo.local/healthz
# PromQL / Grafana query output
```

```text
<paste output>
```

---

## 3. Root Cause

- **Broken field / mismatch:** `<exact manifest field, selector label, Secret name, probe path, or env var>`
- **Reporting controller / component:** `<kubelet, scheduler, EndpointSlice controller, Envoy Gateway, Prometheus, etc.>`
- **Causal explanation:** `<1–3 sentences connecting the evidence above to the symptom>`

---

## 4. Fix & Recovery Proof

- **Change applied:**

```diff
<exact manifest diff or command run to restore>
```

- **Behavioral recovery proof** *(must show working HTTP response / metric / trace recovery, not merely `Pod Running`)*:

```text
<paste post-fix curl / PromQL / booking workflow / verify output>
```

---

## 5. Takeaway

- **Mental model / invariant:** `<one-sentence takeaway you can defend without notes>`
- **Cleanup / residue check (if applicable):** `<e.g. deleted /tmp files, restored taints/replicas>`
