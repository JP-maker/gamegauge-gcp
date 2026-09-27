variable "project_id" {
  type        = string
  description = "Identifiant du projet GCP dédié à l'essai (surtout pas un projet de production)."
}

variable "region" {
  type        = string
  description = "Région GCP. europe-west1 (Belgique) limite la latence depuis la France."
  default     = "europe-west1"
}

variable "zone" {
  type        = string
  description = "Zone du cluster. Un cluster ZONAL est nécessaire pour entrer dans le crédit gratuit GKE ; un cluster régional n'y a pas droit."
  default     = "europe-west1-b"
}

variable "prefix" {
  type        = string
  description = "Préfixe appliqué au nom de toutes les ressources, pour les retrouver et les nettoyer facilement."
  default     = "gamegauge"
}

variable "node_machine_type" {
  type        = string
  description = "Type de machine des nœuds. e2-standard-2 (2 vCPU, 8 Gio) par défaut car GKE réserve environ 1 Gio par nœud et ses composants système quelques centaines de Mio : sur e2-medium le backend Spring Boot reste en Pending faute de mémoire, et e2-small ne suffit pas du tout."
  default     = "e2-standard-2"
}

variable "node_count" {
  type        = number
  description = "Nombre de nœuds du pool."
  default     = 2
}

variable "node_disk_size_gb" {
  type        = number
  description = "Taille du disque de chaque nœud. Le défaut GKE est 100 Gio, inutilement coûteux pour un essai."
  default     = 30
}

variable "use_spot_vms" {
  type        = bool
  description = "Nœuds Spot : environ 70 % moins chers, mais Google peut les récupérer à tout moment. Pratique pour un essai, risqué pendant une démonstration notée."
  default     = false
}
