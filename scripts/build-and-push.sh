#!/usr/bin/env bash
# ============================================================================
#  Construit les deux images avec Cloud Build et les pousse vers Artifact
#  Registry. Cloud Build évite d'avoir Docker installé localement et compile
#  côté Google, ce qui est nettement plus rapide pour l'image Maven.
#
#  Usage :
#    PROJECT_ID=mon-projet ./build-and-push.sh
# ============================================================================
set -euo pipefail

PROJECT_ID="${PROJECT_ID:?Définissez PROJECT_ID}"
REGION="${REGION:-europe-west1}"
REPO="${REPO:-gamegauge-images}"
TAG="${TAG:-essai}"

# Chemins vers les deux dépôts dupliqués, relatifs à ce script par défaut.
UI_DIR="${UI_DIR:-../../gamegauge-ui-gcp}"
API_DIR="${API_DIR:-../../gamegauge-api-gcp}"

PREFIX="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}"

echo "==> Backend : ${PREFIX}/gamegauge-api:${TAG}"
gcloud builds submit "${API_DIR}" \
  --tag "${PREFIX}/gamegauge-api:${TAG}" \
  --project "${PROJECT_ID}"

echo "==> Frontend : ${PREFIX}/gamegauge-ui:${TAG}"
gcloud builds submit "${UI_DIR}" \
  --tag "${PREFIX}/gamegauge-ui:${TAG}" \
  --project "${PROJECT_ID}"

echo
echo "Images publiées. Injectez-les dans les manifests :"
echo "  sed -i \"s|IMAGE_BACKEND|${PREFIX}/gamegauge-api:${TAG}|\" k8s/20-backend.yaml"
echo "  sed -i \"s|IMAGE_FRONTEND|${PREFIX}/gamegauge-ui:${TAG}|\" k8s/30-frontend.yaml"
