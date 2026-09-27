output "cluster_name" {
  description = "Nom du cluster GKE créé."
  value       = google_container_cluster.primary.name
}

output "cluster_zone" {
  description = "Zone du cluster."
  value       = var.zone
}

output "image_prefix" {
  description = "Préfixe à utiliser pour taguer et pousser les images."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

output "commande_kubectl" {
  description = "Commande à lancer pour connecter kubectl au cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --zone ${var.zone} --project ${var.project_id}"
}

output "commande_docker_auth" {
  description = "Commande à lancer pour autoriser Docker à pousser vers Artifact Registry."
  value       = "gcloud auth configure-docker ${var.region}-docker.pkg.dev"
}
