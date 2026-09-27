#!/usr/bin/env bash
# ============================================================================
#  Vérification post-destruction : liste tout ce qui pourrait encore être
#  facturé dans le projet. À lancer APRÈS « terraform destroy ».
#
#  Les ressources créées par Kubernetes lui-même — l'équilibreur de charge du
#  Service LoadBalancer, le disque persistant du StatefulSet — n'appartiennent
#  pas à l'état Terraform. Si le cluster est détruit avant elles, elles
#  survivent et continuent d'être facturées silencieusement.
#
#  Usage :
#    PROJECT_ID=mon-projet ./cleanup-check.sh
# ============================================================================
set -uo pipefail

PROJECT_ID="${PROJECT_ID:?Définissez PROJECT_ID}"

echo "=== Clusters GKE ==="
gcloud container clusters list --project "$PROJECT_ID" 2>/dev/null || true

echo
echo "=== Règles de transfert (équilibreurs de charge) ==="
gcloud compute forwarding-rules list --project "$PROJECT_ID" 2>/dev/null || true

echo
echo "=== Adresses IP réservées ==="
gcloud compute addresses list --project "$PROJECT_ID" 2>/dev/null || true

echo
echo "=== Disques persistants ==="
gcloud compute disks list --project "$PROJECT_ID" 2>/dev/null || true

echo
echo "=== Instances de calcul ==="
gcloud compute instances list --project "$PROJECT_ID" 2>/dev/null || true

echo
echo "=== Dépôts Artifact Registry (facturés au stockage) ==="
gcloud artifacts repositories list --project "$PROJECT_ID" 2>/dev/null || true

echo
echo "Tout doit être vide. Si une ligne subsiste, supprimez-la à la main,"
echo "ou supprimez le projet entier : gcloud projects delete $PROJECT_ID"
