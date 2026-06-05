resource "google_container_cluster" "main" {
  name     = var.cluster_name
  location = "us-central1"
  project  = "apollo11-project"

  network    = var.vpc_id
  subnetwork = var.subnet_id

  remove_default_node_pool = true
  initial_node_count       = 1

  master_auth {
    username = ""
    password = ""

    client_certificate_config {
      issue_client_certificate = false
    }
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint  = false
    master_ipv4_cidr_block   = "172.16.0.0/28"
  }

  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "10.4.0.0/16"
    services_ipv4_cidr_block = "10.0.0.0/20"
  }

  workload_identity_config {
    workload_pool = "apollo11-project.svc.id.goog"
  }

  tags = {
    environment = var.environment
  }
}

resource "google_container_node_pool" "main" {
  name       = "${var.cluster_name}-node-pool"
  location   = "us-central1"
  project    = "apollo11-project"
  cluster    = google_container_cluster.main.name
  node_count = 3

  node_config {
    preemptible  = false
    machine_type = "e2-medium"

    labels = {
      "node.kubernetes.io/role" = "app"
    }

    service_account = google_service_account.main.email
  }

  autoscaling {
    min_node_count = 1
    max_node_count = 10
  }
}

resource "google_service_account" "main" {
  project = "apollo11-project"
  name    = "${var.cluster_name}-sa"

  description = "Service account for GKE nodes"
}

resource "google_project_iam_member" "node_pool" {
  project = "apollo11-project"
  role    = "roles/container.nodeTaintsExecutor"
  member  = "serviceAccount:${google_service_account.main.email}"
}

output "cluster_id" {
  value = google_container_cluster.main.id
}

output "cluster_endpoint" {
  value = google_container_cluster.main.endpoint
}

output "cluster_name" {
  value = google_container_cluster.main.name
}
