# Apollo11

![logo](./images/apollo11-project-logo.png)

11 stage plan to enable you to become very good with the whole k8s based cloud native ecosystem and comfortable with all the components involved for almost every requirement that may come up to build a robust architecture.

![tools](./images/apollo11-flavor2-project.drawio.png)

## Stages

- Litfoff - Start with docker
    - Run the whole cluster over docker-compose

- Stage 1 - Bare Bones on k8s 
    - Run all the services on kind cluster with basic deployment and service in custom namespace

- Stage 2 - Add best practices

    - Kubens/kubectx for permenant ns in terminal
    - Config maps/secrets
    - Labels and Annotations
    - Init containers
    - Probes
    - Resource quotas
    - Limits/requests 
    - Restart policy
    - Taints and Tolerations
    - Pod Affinity/ Anti-Affinity

- Stage 3 - Enter Persistance
    - Persistent volume
    - Persistent volume claim
    - Storage class
    - Access Modes
    - Reclaim Policy    
    - Statefulset

- Stage 4 - Enter Better Networking

    - Network Policies
    - Ingress
    - Gateway 
    - Service Mesh

- Stage 5 - Lets Package it

    - Helm 
    - Kustomize
    - CR/ CRDs

- Stage 6 - Monitoring and Troubleshooting

    - Ephemeral Containers/Debug
    - Headlamp
    - K9s
    - Merics server 
    - Prometheus 
    - Loki
    - Open Telemetry
    - Grafana

- Stage 7 - Bring in Automation

    - Tilt for local testing
    - Argo Workflows/Tekton
        - multi env deploys
    - Argo CD

- Stage 8 - Security

    - Tls
    - Sealed secrets
    - RBAC
    --- optional
    - Keycloak
    - Vault
    - OPA
    - Kubescape

- Stage 9 - Autoscaling
    
    - HPA
    - VPA
    - Cluster Autoscaling
    - Karpenter 
    - Load Testing
    - Qos

- Stage 10 - Backup,upgrades and Chaos
    
    - Backup and restore
        - Velero/Rook
    - Cluster upgrades
    - Chaos Engineering
    
- Stage 11 - Move on from Local k8s cluster
    - github actions to push image to gcr/private repo
    - use image pull secrets to pull image

- To Mars
    - Argo Rollouts [progressive delivery]
    - Harbor - Self hosted container registry



## Prerequisites

- This course assumes that you come with bare basic knowledge about k8s concepts. 
- I highly recommend this playlist, will cover everything you ever need to know [varjosh k8s course](https://youtube.com/playlist?list=PLmPit9IIdzwRjqD-l_sZBDdPlcSfKqpAt&si=TN-MJ8-1pKj1_V4J)
    - Its long so you can choose what you need, if you are a complete beginner i would encourage to go through all of it from start to end


## Tools

| Category | Tools |
|---|---|
| Backend API |  Golang,Python |
| Sql Database| Postgres,Mysql |
| Nosql Database | MongoDB | 
| Local Development | Tilt |
| Dashboard | Headlamp,k9s |
| Container Management | Docker, Podman |
| CI | Github Actions |
| GitOps | ArgoCD |
| Progressive Deployment | Argo Events, Argo Rollouts |
| Secret Store | Vault |
| Ingress Controller | Apisix |
| Packaging | Helm |
| Patching | Kustomize |
| Logging | Fluentd (agent), Loki (backend) |
| Service Mesh | Istio |
| Monitoring | Prometheus, Grafana |    
| Compliance Monitoring | kubebench |
| Policy Engine | OPA/Kyverno |
| Policy Checker | Kubescape |
| Backup and Restore | Velero |
| Load Testing | hey,Kube-monkey |
| Cluster Provisioning | Kubespray (optional) |
| Serverless | OpenFaas |
| Container Builds | Buildah |

Extra:

- https://github.com/groundcover-com/caretta
- Dapr
- Dagger