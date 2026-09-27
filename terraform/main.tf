# ============================================================================
#  Activation des APIs GCP
#  Un projet GCP neuf n'a presque aucune API active : sans ces lignes, la
#  création du cluster échoue avec une erreur « API not enabled ».
# ============================================================================
locals {
  required_services = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
  ]
}

resource "google_project_service" "enabled" {
  for_each = toset(local.required_services)

  project = var.project_id
  service = each.value

  # On laisse les APIs actives au destroy : les désactiver allonge
  # considérablement l'opération sans rien économiser.
  disable_on_destroy = false
}

# ============================================================================
#  Réseau
#  Un VPC dédié plutôt que le réseau « default », pour que la destruction
#  n'emporte rien d'autre et que les plages d'adresses soient explicites.
# ============================================================================
resource "google_compute_network" "vpc" {
  name                    = "${var.prefix}-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.enabled]
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.prefix}-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.10.0.0/20"

  # Cluster VPC-native : les pods et les services prennent leurs adresses
  # dans des plages secondaires du sous-réseau, pas dans un overlay.
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.30.0.0/20"
  }

  private_ip_google_access = true
}

# ============================================================================
#  Artifact Registry — remplace l'ancien Container Registry (gcr.io)
# ============================================================================
resource "google_artifact_registry_repository" "images" {
  location      = var.region
  repository_id = "${var.prefix}-images"
  description   = "Images Docker de l'essai GameGauge sur GKE"
  format        = "DOCKER"

  depends_on = [google_project_service.enabled]
}

# ============================================================================
#  Cluster GKE Standard, zonal
# ============================================================================
resource "google_container_cluster" "primary" {
  name = "${var.prefix}-cluster"

  # Une ZONE (et non une région) : cluster zonal, un seul plan de contrôle,
  # éligible au crédit gratuit de 74,40 $/mois.
  location = var.zone

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  # GKE impose de créer un pool par défaut ; on le supprime aussitôt pour
  # gérer le nôtre explicitement dans google_container_node_pool.
  remove_default_node_pool = true
  initial_node_count       = 1

  # ---------------------------------------------------------------------
  #  LE RÉGLAGE À NE PAS OUBLIER POUR UN ESSAI TEMPORAIRE
  #  Depuis le provider v5, ce champ vaut true par défaut et « terraform
  #  destroy » REFUSE de supprimer le cluster tant qu'il n'est pas passé à
  #  false ET appliqué. Le mettre après coup oblige à un apply avant de
  #  pouvoir détruire.
  # ---------------------------------------------------------------------
  deletion_protection = false

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  release_channel {
    channel = "REGULAR"
  }

  # On n'envoie que les journaux des composants système vers Cloud Logging.
  # Les journaux applicatifs restent lisibles avec « kubectl logs », et on
  # évite de facturer l'ingestion de tout le bruit de l'application.
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }

  depends_on = [google_project_service.enabled]
}

# ============================================================================
#  Pool de nœuds
# ============================================================================
resource "google_container_node_pool" "primary" {
  name     = "${var.prefix}-pool"
  location = var.zone
  cluster  = google_container_cluster.primary.name

  node_count = var.node_count

  node_config {
    machine_type = var.node_machine_type
    disk_size_gb = var.node_disk_size_gb
    disk_type    = "pd-balanced"
    spot         = var.use_spot_vms

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels = {
      env = "essai"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
