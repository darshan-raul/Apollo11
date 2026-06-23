# ebs-gp3 StorageClass for the EBS CSI driver.
#
# WHY THIS RESOURCE EXISTS:
# A fresh EKS cluster has NO StorageClass objects at all. None. Verify with
# `kubectl get storageclass` — the output is empty.
#
# This surprises people coming from kind or minikube, both of which ship a
# default StorageClass (kind installs `local-path`, minikube installs
# `standard`). EKS does not, because AWS deliberately separates the two
# things that get conflated:
#
#   1. The CSI driver (DaemonSet/Deployment that talks to AWS APIs to create
#      EBS volumes). EKS installs this as a managed addon
#      (`aws-ebs-csi-driver`). When installed, it exposes the
#      `ebs.csi.aws.com` provisioner name to the cluster.
#
#   2. The StorageClass object (a cluster-scoped resource that tells
#      kube-controller-manager: "use THIS provisioner with THESE parameters
#      when a PVC asks for storage and doesn't specify a class").
#
# The addon creates (1) but never creates (2). It's a separate resource,
# and someone has to write it.
#
# FAILURE MODE WITHOUT THIS:
# Stage 3's StatefulSets (and any other PVC that omits storageClassName)
# would stay `Pending` indefinitely. The kubelet has no StorageClass to
# fall back to, so it cannot pick a provisioner.
#
# DESIGN CHOICES:
# - `is-default-class: "true"` so Stage 3's PVCs (which don't set
#   storageClassName) bind automatically.
# - `volumeBindingMode: WaitForFirstConsumer` so the EBS volume is created
#   in the same AZ the pod schedules into. EBS volumes are AZ-bound; if
#   we created them up-front, half the StatefulSet pods would land in
#   the wrong AZ.
# - `type: gp3` because gp3 is the AWS-recommended default for new
#   workloads (cheaper per GB, baseline 3000 IOPS / 125 MB/s without
#   provisioned IOPS).
# - `encrypted: "true"` because cluster secrets and DB data should not
#   be sitting on unencrypted disks.

resource "kubernetes_manifest" "ebs_gp3_storageclass" {
  manifest = {
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = "ebs-gp3"
      annotations = {
        "storageclass.kubernetes.io/is-default-class" = "true"
      }
    }
    provisioner       = "ebs.csi.aws.com"
    reclaimPolicy     = "Delete"
    allowVolumeExpansion = true
    volumeBindingMode    = "WaitForFirstConsumer"
    parameters = {
      type      = "gp3"
      encrypted = "true"
    }
    mountOptions = [
      "debug",
    ]
  }
}
