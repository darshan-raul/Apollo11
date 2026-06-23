---
title: "Stage EKS — Apollo11 on Amazon EKS (NLB + EBS CSI)"
description: "Provision a single-region EKS cluster that runs the Stage 2 set-5 Envoy Gateway stack and the Stage 3 StatefulSets (EBS-backed). Replaces kind+MetalLB+local-path with EKS+NLB+EBS CSI. One-command spin up, one-command tear down."
---

# Stage EKS — Apollo11 on Amazon EKS

This stage takes everything you built in [Stage 2 set 5](../stage2/set5-envoy-gateway/README.md) (Envoy Gateway + the 6-service Apollo Airlines app) and [Stage 3](../stage3/README.md) (StatefulSets with persistent storage) and runs it on a real managed Kubernetes cluster — **Amazon EKS** — with the AWS equivalents of the local-stack pieces:

| Local (kind) | AWS |
|---|---|
| `kind` cluster | EKS managed control plane |
| `kindnet` CNI | AWS VPC CNI (Pod IPs in the VPC) |
| `kind get nodes` | Managed node group (2 × t3.small spot) |
| `kind load docker-image` | ECR (one repo per service) + `docker push` |
| MetalLB | AWS Network Load Balancer, provisioned by the AWS Load Balancer Controller |
| `local-path` StorageClass | `ebs-gp3` StorageClass, gp3 EBS volumes, `WaitForFirstConsumer` |
| `envoy-gateway-install.yaml` (vendored) | The same `envoy-gateway-install.yaml` (vendored) — no change |
| `EnvoyProxy` (no annotations) | `EnvoyProxy` + 5 LBC annotations so the LBC materialises the NLB |

**The only changes to the Stage 2 set 5 / Stage 3 k8s manifests:**

1. The `EnvoyProxy` (`stages/eks/terraform/gateway/envoyproxy.yaml.tftpl`) gains 5 LBC annotations. Everything else — GatewayClass, Gateway, 6 HTTPRoutes, ReferenceGrant — is byte-for-byte identical to Stage 2 set 5.
2. A new `ebs-gp3` `StorageClass` is installed. EKS ships with **no `StorageClass` at all** on a fresh cluster (unlike kind, which installs `local-path` as default). The `aws-ebs-csi-driver` addon exposes the `ebs.csi.aws.com` provisioner but does not create a `StorageClass` object — that's a separate resource, written in `terraform/storage/storageclass.tf`. Without it, Stage 3's StatefulSets would stay `Pending` forever.

Nothing else. The 10 workloads, the 4 StatefulSets, the 3 seed Jobs, the schema, the seed data — all run unmodified from `stages/stage3/`.

---

## When to use this stage

Use `stages/eks/` when you want to:

- **Validate the manifests in a production-like environment** (managed k8s, real cloud networking, real LB, real persistent disks).
- **Demonstrate Envoy Gateway + AWS NLB** in an interview or a talk — the `EnvoyProxy` annotation block is the only piece that changes between the local stack and AWS.
- **Test pod-eviction + PVC persistence under real AWS load balancer conditions** (cross-AZ ENIs, security groups, idle-fee billing).
- **Bring up a multi-AZ cluster in ~10 minutes and tear it down in ~6**, repeatably, with the same `up.sh` / `down.sh` commands every time.

Don't use this stage for:

- **Cost-sensitive always-on dev.** Even on spot + single NAT, the EKS control plane is $73/mo. Use kind (Stages 1–6) for day-to-day dev.
- **Learning the basics of k8s.** Stages 1–4 are the right place. This stage assumes you understand StatefulSets, PVCs, HTTPRoutes, and what a LoadBalancer Service is.
- **Production HA.** Single NAT, 2 nodes, no cluster autoscaler, no multi-region. The TF is shaped to be cheap to spin up, not to be prod-ready.

---

## Cost (us-east-1, May 2026)

| Item | Always-on / month | Per 2-hour session |
|---|---|---|
| EKS control plane | $73.00 | $0.20 |
| 2 × t3.small spot worker nodes | $18.25 | $0.05 |
| 1 × NAT Gateway | $32.85 | $0.09 |
| 1 × EIP for NAT | $3.65 | $0.01 |
| Internet-facing NLB | $16.43 | $0.05 |
| 2 × public IPv4 for NLB | $7.20 | $0.02 |
| 2 × gp3 root volumes (20 GB) | $3.20 | $0.01 |
| KMS key for cluster | $1.00 | — |
| 4 × 1 GB gp3 StatefulSet volumes | $0.32 | <$0.01 |
| 6 × ECR repos (within free tier) | $0.00 | $0.00 |
| CloudWatch Logs (cluster audit, 1d retention) | $0.50 | $0.01 |
| **Total** | **~$156/mo** | **~$0.44 per 2-hour dev session** |

Numbers come from the AWS pricing pages (`eks/pricing`, `vpc/pricing`, `ec2/pricing/on-demand`). The spot price fluctuates — `t3.small` is one of the cheapest EC2 instance types and rarely has spot capacity issues.

If you want to go even cheaper:

- `nlb_scheme = "internal"` — saves the $7.20/mo in public IPv4 fees, but you'll need a bastion or VPN to reach the cluster.
- `node_capacity_type = "ON_DEMAND"` with `node_instance_type = "t3.small"` — more stable, +$50/mo.
- `node_group_desired_size = 1` — not recommended (NLB needs targets in both AZs), but possible.

If you want to go richer:

- `node_capacity_type = "ON_DEMAND"` + `node_instance_type = "t3.medium"` — comfortable headroom, ~$60/mo compute instead of $18.
- `single_nat_gateway = false` — one NAT per AZ, HA-grade, +$33/mo.

---

## Quickstart

```bash
cd stages/eks

# 0. Prereqs (one-time, via devbox)
devbox add awscli terraform@latest kubectl helm

# 1. AWS creds
aws configure

# 2. Spin up the cluster (~10 min)
./scripts/up.sh

# 3. Apply Apollo11 workloads (~5 min)
./scripts/apply-workloads.sh

# 4. Verify (~40 checks)
./scripts/verify.sh

# 5. Tear down (~6 min)
./scripts/down.sh
```

After step 2, `up.sh` prints the NLB DNS name and one-liner `curl` examples.
After step 3, `apply-workloads.sh` prints the same NLB hostname (the LBC
provisions it after the Envoy Gateway Service is created, which happens
during the `up.sh` apply, so it's usually already up by step 3).

---

## Detailed walkthrough

### Step 0 — Prereqs

| Tool | Why | Install |
|---|---|---|
| `aws` (CLI v2) | All cluster + ECR + NLB operations | `devbox add awscli` (or `pip install awscli` / `brew install awscli`) |
| `terraform >= 1.5.7` | Cluster + addon lifecycle | `devbox add terraform@latest` |
| `kubectl >= 1.28` | Workload management | `devbox add kubectl` |
| `helm >= 3.13` | LBC install (Terraform also uses it) | `devbox add helm` |
| `docker` | Build + push images to ECR | Already required for stages 1–6 |

Configure your AWS credentials:

```bash
aws configure
# AWS Access Key ID:     AKIA...
# AWS Secret Access Key: ...
# Default region:        us-east-1
# Default output:        json
```

The principal you configure must have permission to create:

- VPC + subnets + NAT + EIPs
- EKS cluster + node group + addons + access entries
- IAM roles + OIDC provider + Pod Identity associations
- ECR repositories
- KMS key for cluster secrets encryption
- KMS key (optional) for ECR encryption (we use AES256, no extra key needed)
- Security groups + ENIs

The `AdministratorAccess` managed policy is the easiest way to grant this. For a tighter setup, see the IAM section at the bottom of this README.

### Step 1 — Spin up the cluster (`./scripts/up.sh`)

This script:

1. Runs `terraform init` (downloads the EKS module + AWS provider).
2. Runs `terraform apply` — the apply creates, in this order:
   - VPC + subnets + 1 NAT Gateway + 1 EIP
   - KMS key for EKS secrets
   - EKS control plane (~5–8 min)
   - Managed node group (2 × t3.small spot across 2 AZs)
   - 6 EKS addons: `vpc-cni`, `coredns`, `kube-proxy`, `eks-pod-identity-agent`, `aws-ebs-csi-driver`, `aws-load-balancer-controller`
   - 4 IAM roles + Pod Identity associations (for the addons that need them)
   - 6 ECR repositories (one per service)
   - 1 `ebs-gp3` StorageClass (default — EKS has no StorageClass on its own; the CSI driver addon only exposes the `ebs.csi.aws.com` provisioner, it doesn't create the `StorageClass` object)
   - AWS Load Balancer Controller Helm release
   - Envoy Gateway stack (install.yaml + GatewayClass + EnvoyProxy with LBC annotations + Gateway + ReferenceGrant + 6 HTTPRoutes)
3. Writes `~/.kube/config` so `kubectl` points at the new cluster.
4. Polls `aws elbv2 describe-load-balancers` until the NLB is `active` (typically 1–2 min after the Envoy data plane Service is created).

The script prints the NLB DNS name when it's ready. Example:

```
NLB hostname: apollo11-dev-envoy-nlb-1234567890.us-east-1.elb.amazonaws.com
```

### Step 2 — Apply Apollo11 workloads (`./scripts/apply-workloads.sh`)

This is a port of `stages/stage3/scripts/apply.sh` for EKS. Differences from the kind version:

| Stage 3 (kind) | EKS |
|---|---|
| `kind load docker-image` | `docker push` to ECR |
| `kubectl apply -f k8s/metallb/` | (skipped — TF handled it) |
| `kubectl apply -f k8s/gateway/` | (skipped — TF handled it) |
| Frontend VITE_* → `http://*.apollo.local` (MetalLB IP) | Frontend VITE_* → `http://*.nip.io` (NLB FQDN, no /etc/hosts needed) |

The 10-step ordering from Stage 3 is preserved:

1. Build + push 6 service images to ECR
2. Apply namespaces + configmap + secret
3. Apply 13 ServiceAccounts
4. Apply apps + infra (10 components, image tag rewritten to ECR)
5. Wait for StatefulSets to be Ready
6. Apply 3 seed Jobs
7. Wait for seed Jobs to Complete
8. Wait for `apollo-gateway` to be Programmed (no-op — TF already applied the manifests)
9. Wait for the NLB hostname to be set on the Envoy data plane Service
10. Print the URLs

### Step 3 — Verify (`./scripts/verify.sh`)

~40 checks in 5 groups:

1. **Cluster + addon health (5)** — k8s version, all 6 EKS addons `ACTIVE`.
2. **StatefulSets + PVCs + EBS PVs (10)** — 4 StatefulSets Ready, 4 pods Ready, 4 PVCs Bound, ≥4 PVs in Bound state, StorageClass uses `ebs.csi.aws.com` provisioner with `WaitForFirstConsumer` binding.
3. **App Deployments + frontend (7)** — 5 backend Deployments ≥2/2, frontend ≥2/2, image source is ECR (not local cache).
4. **NLB + Envoy Gateway (7)** — NLB is `active`, ≥1 healthy target in the target group, GatewayClass uses the right controller, Gateway is Programmed, Envoy data plane Service exists, 6 HTTPRoutes have parents, EnvoyProxy has LBC annotations.
5. **End-to-end (8)** — 3 smoke tests through `Host:` header to identity/flight/frontend, full login round-trip, 3 DB row counts (users ≥2, airports ≥6, flights ≥180), and a **PVC persistence demo** (insert row, delete pod, confirm row survives).

### Step 4 — Tear down (`./scripts/down.sh`)

Order matters here, because 90% of "ghost resource" pain comes from the LBC holding an NLB ENI in the cluster SG, which then blocks the SG's `terraform destroy`.

1. `kubectl delete ns apollo-airlines-apps apollo-airlines-ui` (async). This drops the HTTPRoute parent status on the Gateway, so the Gateway can be deleted cleanly.
2. `terraform apply -destroy` on the Envoy Gateway stack (the `kubectl_manifest` resources). The HTTPRoutes, ReferenceGrant, Gateway, EnvoyProxy, GatewayClass, and install.yaml go away in that order.
3. `terraform apply -destroy` on the LBC Helm release. This is what tells the LBC to release the NLB.
4. Wait for the NLB to actually disappear (up to 60s).
5. `terraform destroy` on the rest (cluster, addons, node groups, VPC, ECR, IAM).
6. `ebs-sweep.sh` — delete any EBS volumes in `available` state (the StatefulSet PVs should be released by step 5, but orphaned volumes are common if a teardown step is interrupted).
7. Sweep orphaned cluster ENIs.

Set `PURGE_ECR=1` to also delete the ECR repos + their images. By default we keep them (they're cheap if you have 6 repos with no images, and the lifecycle policy keeps image count under 10).

### Customising the cluster

All knobs are in `terraform/variables.tf`. Common edits:

| Want | Edit |
|---|---|
| Different region | `region` (default `us-east-1`) |
| Internal NLB (cheaper, but private) | `nlb_scheme = "internal"` |
| 3 nodes instead of 2 | `node_group_desired_size = 3`, `node_group_min_size = 2`, `node_group_max_size = 4` |
| On-Demand instead of spot | `node_capacity_type = "ON_DEMAND"` |
| Bigger nodes | `node_instance_type = "t3.medium"` |
| Different k8s version | `kubernetes_version = "1.30"` (must be in the EKS-supported list) |
| Lock down kubectl CIDR | `cluster_endpoint_public_access_cidrs = ["203.0.113.0/32"]` |
| Disable encryption at rest | Drop the `encryption_config` block in `cluster/eks.tf` |
| Use Calico for NetworkPolicy | Add a `terraform-helm-calico` release + CNI hook (out of scope here) |

---

## How the AWS pieces fit together

```
┌─────────────────────────────────────────────────────────────────────┐
│ Region: us-east-1                                                    │
│                                                                       │
│  ┌─ VPC 10.0.0.0/16 ─────────────────────────────────────────────┐  │
│  │                                                                 │  │
│  │  ┌─ Public subnets (NAT + NLB ENIs live here) ──────────────┐  │  │
│  │  │  10.0.0.0/22 (1a)  10.0.4.0/22 (1b)                    │  │  │
│  │  │  ┌──────────────┐  ┌──────────────┐                     │  │  │
│  │  │  │ NAT GW + EIP │  │   (empty)    │                     │  │  │
│  │  │  └──────┬───────┘  └──────────────┘                     │  │  │
│  │  │         │ (egress for private subnets)                   │  │  │
│  │  └─────────┼──────────────────────────────────────────────┘  │  │
│  │            │                                                    │  │
│  │  ┌─ Private subnets (worker nodes + EBS volumes) ──────────┐  │  │
│  │  │  10.0.16.0/22 (1a) 10.0.20.0/22 (1b)                    │  │  │
│  │  │  ┌────────────────┐ ┌────────────────┐                  │  │  │
│  │  │  │  node 1a       │ │  node 1b       │                  │  │  │
│  │  │  │  t3.small spot │ │  t3.small spot │                  │  │  │
│  │  │  │  ┌──────────┐  │ │  ┌──────────┐  │                  │  │  │
│  │  │  │  │ identity │  │ │  │ identity │  │  (StatefulSet    │  │  │
│  │  │  │  │ flight   │  │ │  │ flight   │  │   pods)         │  │  │
│  │  │  │  │ booking  │  │ │  │ booking  │  │                  │  │  │
│  │  │  │  │ ...      │  │ │  │ ...      │  │                  │  │  │
│  │  │  │  │  Envoy   │  │ │  │  Envoy   │  │                  │  │  │
│  │  │  │  │  proxy   │  │ │  │  proxy   │  │                  │  │  │
│  │  │  │  └────┬─────┘  │ │  └────┬─────┘  │                  │  │  │
│  │  │  └───────┼────────┘ └───────┼────────┘                  │  │  │
│  │  │          │                  │                           │  │  │
│  │  │  ┌───────┴────── EBS volumes (gp3)                     │  │  │
│  │  │  │  1Gi PVC × 4 (3 PG + 1 redis)                       │  │  │
│  │  │  └─────────────────────────────────────────────────────┘  │  │
│  │  └─────────────────────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌─ EKS control plane (managed, $0.10/hr) ───────────────────────┐  │
│  │  k8s API:  https://<cluster>.eks.us-east-1.amazonaws.com       │  │
│  │  Addons: vpc-cni, coredns, kube-proxy, pod-identity-agent,     │  │
│  │          aws-ebs-csi-driver, aws-load-balancer-controller      │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌─ NLB (internet-facing, $0.0225/hr + 2 × public IPv4) ─────────┐   │
│  │  apollo11-dev-envoy-nlb-<hash>.us-east-1.elb.amazonaws.com     │   │
│  │  └─ target group: envoy data plane pods (1a + 1b)              │   │
│  └────────────────────────────────────────────────────────────────┘   │
│                                                                       │
│  ┌─ ECR (1 repo per service, free tier covers dev) ──────────────┐  │
│  │  apollo11-dev/identity, /flight, /booking, /search,            │  │
│  │  /notification, /frontend                                       │  │
│  └────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

A request to `http://identity.apollo.local/api/users/login` (after `/etc/hosts` maps the name to the NLB's public DNS) flows:

1. **DNS** → NLB's public IP (the *.us-east-1.elb.amazonaws.com A record).
2. **NLB** → Layer-4 forwards to an Envoy data plane pod in the target group. The NLB's target type is `ip` (configured via the `aws-load-balancer-nlb-target-type: ip` annotation), so the NLB connects directly to the pod IP, not the node IP.
3. **Envoy data plane** (in `apollo-airlines-apps` namespace) → Host header routing via the Gateway → `identity.apollo.local` HTTPRoute → `identity:8080` ClusterIP Service.
4. **identity Service** → `identity-db:5432` (a headless Service in the same namespace) → Postgres pod.
5. Postgres writes to its `pgdata` PVC (1Gi gp3 EBS volume). The pod restarts and the data is still there.

---

## What's different from the stage 2/3 kind flow

| Concern | kind | EKS |
|---|---|---|
| Cluster bring-up | `kind create cluster` (~30s) | `terraform apply` (~10 min, mostly EKS control plane) |
| Pod networking | kindnet (CNI), pod CIDR `10.244.0.0/16` | VPC CNI, pod IPs from the VPC (`10.0.16.0/22` etc.) |
| Service of type LoadBalancer | MetalLB (L2) assigns a local IP | AWS Load Balancer Controller provisions an NLB |
| DNS for the NLB | `*.apollo.local` via /etc/hosts | `*.apollo.local` via /etc/hosts (same), or `*.nip.io` |
| Persistent storage | `local-path` StorageClass (default on kind) | `ebs-gp3` StorageClass (we install as default; EKS ships with none — see gotcha below) |
| Image delivery | `kind load docker-image` (writes to the node's local Docker cache) | `docker push` to ECR (kubelet pulls from ECR via the node IAM role) |
| Cross-AZ concerns | None (single-node kind) | NLB requires 2 AZs, EBS volumes are AZ-bound (WaitForFirstConsumer handles this) |
| Time to clean up | `kind delete cluster` (~5s) | `terraform destroy` (~6 min, ordered to avoid NLB→SG dependency hang) |

> **A subtle gotcha** — EKS ships with **no `StorageClass` at all** on a
> fresh cluster, which surprises people coming from kind/minikube (both
> install a default). The EKS `aws-ebs-csi-driver` addon installs the
> *driver* (which exposes the `ebs.csi.aws.com` provisioner), but it
> does not create the `StorageClass` object itself. That's a separate
> resource someone has to write — which is what
> `terraform/storage/storageclass.tf` does. Without it, Stage 3's
> StatefulSets would stay `Pending` indefinitely. Verify on a fresh
> cluster with `kubectl get storageclass` — empty output is normal.

---

## Troubleshooting

### "NLB is in `provisioning` state for >5 minutes"

The LBC creates the NLB asynchronously after the Envoy data plane Service is reconciled. Check:

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50
kubectl get events -n envoy-gateway-system --sort-by='.lastTimestamp' | tail -20
```

Common causes:

- The EnvoyProxy annotations are missing or wrong → re-apply with `terraform apply`.
- The cluster's public subnets aren't tagged for the LBC → check the `kubernetes.io/role/elb = 1` tag on the public subnets.
- The LBC's IAM role is missing the `elasticloadbalancing:CreateLoadBalancer` permission → check the policy in `terraform/cluster/policies/lbc-policy.json`.

### "PVCs stuck in `Pending`"

```bash
kubectl describe pvc pg-data-identity-db-0 -n apollo-airlines-apps
```

Common causes:

- No `ebs-gp3` StorageClass exists → re-apply `terraform apply` (the StorageClass is in `terraform/storage/storageclass.tf`).
- The `ebs-csi-controller-sa` ServiceAccount isn't getting the right IAM role → check `aws eks describe-pod-identity-association --cluster-name apollo11-dev --region us-east-1`.
- The `aws-ebs-csi-driver` addon is `DEGRADED` → `aws eks describe-addon --cluster-name apollo11-dev --addon-name aws-ebs-csi-driver --region us-east-1`.

### "StatefulSet pod stuck in `ContainerCreating`"

```bash
kubectl describe pod identity-db-0 -n apollo-airlines-apps
```

Common causes:

- EBS volume is in a different AZ than the pod → confirm the StorageClass is `WaitForFirstConsumer` (it should be by default in our TF).
- The `ec2:CreateVolume` IAM permission is missing → the EBS CSI driver logs will show this.

### "Login round-trip returns 502"

The NLB has 0 healthy targets. Check:

```bash
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups --load-balancer-arn <NLB_ARN> --query 'TargetGroups[0].TargetGroupArn' --output text) \
  --region us-east-1
```

If the targets are `unhealthy`:

- The Envoy proxy pod may be in a different subnet than the NLB's health check security group → confirm the Envoy data plane Service is `type: LoadBalancer` and the SG rules allow 100.64.0.0/10 (VPC CNI range) on port 80.
- The Envoy proxy pod's readiness probe is failing → `kubectl describe pod -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=apollo-gateway`.

### "Frontend shows 'Network Error' on every API call"

The frontend's VITE_* URLs are baked at build time. If you see `*.apollo.local` in the browser dev tools, you either:

- Built the frontend before the NLB DNS was known (re-run `apply-workloads.sh`).
- The browser doesn't have `/etc/hosts` mapping for `*.apollo.local` (use the NLB's `nip.io` trick: `http://frontend.<NLB_DNS>.nip.io/`).

The `apply-workloads.sh` script uses nip.io by default to avoid this. If you want to use `*.apollo.local` with /etc/hosts, set `FRONTEND_HOST_SUFFIX=.apollo.local` and the script will still build with those URLs.

### "I deleted the cluster but I'm still being billed"

Run:

```bash
./scripts/ebs-sweep.sh us-east-1
aws ec2 describe-nat-gateways --region us-east-1 --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId' --output text
aws elbv2 describe-load-balancers --region us-east-1 --query 'LoadBalancers[?contains(LoadBalancerName, `apollo11-dev`)].LoadBalancerArn' --output text
aws ec2 describe-addresses --region us-east-1 --query 'Addresses[?contains(PublicIp, `YOUR_NAT_EIP`)].AllocationId' --output text
```

Anything that comes back is what you're being billed for. Delete it manually if needed.

---

## IAM policy (least-privilege alternative)

The `AdministratorAccess` managed policy is what `up.sh` assumes. For a tighter setup, the principal you `aws configure` with needs:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "eks:*",
        "iam:*",
        "kms:*",
        "ecr:*",
        "elasticloadbalancing:*",
        "cloudwatch:*",
        "logs:*"
      ],
      "Resource": "*"
    }
  ]
}
```

For a truly least-privilege setup, you'd break this into 5+ roles and a permission boundary. Out of scope for a dev environment.

---

## What's next

After `verify.sh` returns all green, you have a production-shaped EKS cluster running the Apollo11 lab. To take it further:

- **Add the [Stage 4 probes + resource limits](../stage4/README.md)** — copy the probe paths from `stages/stage4/k8s/apps/*/deployment.yaml` into the EKS-applied manifests.
- **Add a Cluster Autoscaler** — `kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml` after enabling the addon.
- **Add the [Stage 6 observability stack](../stage6/README.md)** — Prometheus + Grafana + OTEL, using the same Helm chart shape.
- **Add ALB ingress in front of the NLB** — for TLS termination, set `nlb_scheme = "internal"` and add an `aws_lb` (ALB) with an ACM cert.

But for the demo path, `up.sh → apply-workloads.sh → verify.sh → down.sh` is the complete loop.
