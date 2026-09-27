#!/usr/bin/env bash
# ============================================================================
#  Vérification préalable au déploiement.
#
#  Ce script existe parce que l'essai comporte des modifications réparties
#  dans trois dépôts, dont plusieurs sont silencieuses si on les oublie : un
#  Actuator absent ne casse rien, il laisse simplement des graphiques vides.
#  Lancez-le jusqu'à obtenir du tout vert AVANT de construire les images.
#
#  Usage, depuis le dossier gamegauge-gcp :
#    ./scripts/preflight.sh
# ============================================================================
set -uo pipefail

# Chemins des deux copies applicatives, voisines du dépôt d'infrastructure.
UI_DIR="${UI_DIR:-../gamegauge-ui-gcp}"
API_DIR="${API_DIR:-../gamegauge-api-gcp}"
SECCFG="src/main/java/fr/gamegauge/gamegauge_api/config/SecurityConfig.java"

FAIL=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; printf '      → %s\n' "$2"; FAIL=$((FAIL + 1)); }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# --- Le script doit tourner depuis la racine du dépôt d'infrastructure ------
head_ "Emplacement"
if [ -d terraform ] && [ -d k8s ] && [ -d monitoring ]; then
  pass "lancé depuis la racine de gamegauge-gcp"
else
  fail "ce script doit être lancé depuis la racine de gamegauge-gcp" \
       "cd ~/essai-gcp/gamegauge-gcp && ./scripts/preflight.sh"
  exit 1
fi

# --- Outils ----------------------------------------------------------------
head_ "Outils"
for bin in gcloud kubectl terraform; do
  if command -v "$bin" >/dev/null 2>&1; then
    pass "$bin présent"
  else
    fail "$bin introuvable" "installez-le avant de continuer"
  fi
done
if gcloud components list --only-local-state --format='value(id)' 2>/dev/null \
     | grep -q gke-gcloud-auth-plugin; then
  pass "gke-gcloud-auth-plugin installé"
else
  warn "gke-gcloud-auth-plugin non détecté — sans lui kubectl ne pourra pas s'authentifier"
  printf '      → gcloud components install gke-gcloud-auth-plugin\n'
fi
if [ -f "${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}/application_default_credentials.json" ]; then
  pass "identifiants applicatifs par défaut présents (pour Terraform)"
else
  fail "identifiants applicatifs par défaut absents" \
       "gcloud auth application-default login"
fi

# --- Copie du frontend -----------------------------------------------------
head_ "Copie UI : $UI_DIR"
if [ ! -d "$UI_DIR" ]; then
  fail "dossier introuvable" "dupliquez gamegauge-ui (phase 1 du runbook)"
else
  if [ -d "$UI_DIR/.github/workflows" ]; then
    fail "le pipeline de production est encore présent" \
         "rm -rf $UI_DIR/.github/workflows — sinon un push republierait l'image de production"
  else
    pass "aucun workflow GitHub Actions"
  fi
  # On cherche les directives réelles, pas le mot : nginx.gke.conf mentionne
  # Let's Encrypt dans ses commentaires pour expliquer ce qui a été retiré.
  if grep -qE '^[[:space:]]*(ssl_certificate|listen[[:space:]]+443)' "$UI_DIR/nginx.conf" 2>/dev/null; then
    fail "nginx.conf est encore celui de production (écoute en 443 avec certificats)" \
         "cp nginx.gke.conf $UI_DIR/nginx.conf — nginx refuserait de démarrer dans le cluster"
  else
    pass "nginx.conf sans bloc TLS"
  fi
  if grep -q "proxy_pass http://backend:8080" "$UI_DIR/nginx.conf" 2>/dev/null; then
    pass "nginx relaie /api/ vers le service backend"
  else
    fail "nginx.conf ne relaie pas vers backend:8080" \
         "cp nginx.gke.conf $UI_DIR/nginx.conf"
  fi
fi

# --- Copie du backend ------------------------------------------------------
head_ "Copie API : $API_DIR"
if [ ! -d "$API_DIR" ]; then
  fail "dossier introuvable" "dupliquez gamegauge-api (phase 1 du runbook)"
else
  if [ -d "$API_DIR/.github/workflows" ]; then
    fail "le pipeline de production est encore présent" \
         "rm -rf $API_DIR/.github/workflows"
  else
    pass "aucun workflow GitHub Actions"
  fi
  if grep -q "spring-boot-starter-actuator" "$API_DIR/pom.xml" 2>/dev/null; then
    pass "spring-boot-starter-actuator déclaré"
  else
    fail "spring-boot-starter-actuator absent du pom.xml" \
         "voir api-instrumentation/README.md, section 1"
  fi
  if grep -q "micrometer-registry-prometheus" "$API_DIR/pom.xml" 2>/dev/null; then
    pass "micrometer-registry-prometheus déclaré"
  else
    fail "micrometer-registry-prometheus absent du pom.xml" \
         "sans lui, l'endpoint /actuator/prometheus n'existe pas"
  fi
  if grep -q '"/actuator/\*\*"' "$API_DIR/$SECCFG" 2>/dev/null; then
    pass "/actuator/** ouvert dans SecurityConfig"
  else
    fail "/actuator/** absent de PUBLIC_URLS dans SecurityConfig" \
         "Spring Security répondrait 403 à chaque collecte, sans aucun message d'erreur"
  fi
  if [ -n "$(git -C "$API_DIR" status --porcelain 2>/dev/null)" ]; then
    warn "modifications non commitées dans la copie API — Cloud Build lit le dossier local, donc ce n'est pas bloquant"
  fi
fi

# --- Dépôt d'infrastructure ------------------------------------------------
head_ "Infrastructure"
if [ -f terraform/terraform.tfvars ]; then
  if grep -qE '^\s*project_id\s*=\s*"[^"]+"' terraform/terraform.tfvars; then
    pass "terraform.tfvars renseigné"
  else
    fail "project_id absent de terraform.tfvars" "renseignez votre identifiant de projet"
  fi
else
  fail "terraform/terraform.tfvars manquant" "cp terraform/terraform.tfvars.example terraform/terraform.tfvars"
fi

if [ -f k8s/01-secret.yaml ]; then
  if grep -q "REMPLACEZ_MOI" k8s/01-secret.yaml; then
    fail "k8s/01-secret.yaml contient encore des valeurs d'exemple" \
         "remplacez-les ; la clé JWT vient de : openssl rand -base64 32"
  else
    pass "k8s/01-secret.yaml rempli"
  fi
  JWT=$(grep -E '^\s*JWT_SECRET:' k8s/01-secret.yaml | sed 's/.*JWT_SECRET:[[:space:]]*//' | tr -d '"'"'"' \r')
  LEN=$(printf %s "$JWT" | base64 -d 2>/dev/null | wc -c | tr -d ' ')
  if [ "${LEN:-0}" -ge 32 ]; then
    pass "clé JWT de $LEN octets une fois décodée"
  else
    fail "clé JWT trop courte (${LEN:-0} octets décodés, 32 minimum)" \
         "jjwt refuse toute clé de moins de 256 bits : openssl rand -base64 32"
  fi
else
  fail "k8s/01-secret.yaml manquant" "cp secret.example.yaml k8s/01-secret.yaml puis remplissez-le"
fi

if grep -q "IMAGE_BACKEND" k8s/20-backend.yaml 2>/dev/null; then
  warn "les marqueurs IMAGE_* sont encore en place — normal avant le terraform apply, à traiter à l'étape d'injection"
else
  pass "noms d'images injectés dans les manifests"
fi

for f in k8s/20-backend.yaml k8s/30-frontend.yaml; do
  if grep -q "imagePullPolicy: Always" "$f"; then
    pass "$(basename "$f") : imagePullPolicy Always"
  else
    fail "$(basename "$f") sans imagePullPolicy Always" \
         "le tag essai étant mutable, le nœud réutiliserait son image en cache"
  fi
done

if grep -q "prometheus.io/scrape" k8s/20-backend.yaml 2>/dev/null; then
  pass "annotations de collecte Prometheus sur le backend"
else
  fail "annotations prometheus.io absentes du backend" "Prometheus ne découvrirait jamais ce pod"
fi

if grep -q "MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE" k8s/20-backend.yaml 2>/dev/null; then
  pass "variables MANAGEMENT_* sur le backend"
else
  fail "variables MANAGEMENT_* absentes" "seul l'endpoint health serait publié"
fi

# --- Verdict ---------------------------------------------------------------
printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32m%s\033[0m\n' "Tout est en place. Vous pouvez construire les images."
else
  printf '\033[31m%s\033[0m\n' "$FAIL point(s) à corriger avant de continuer."
  exit 1
fi
