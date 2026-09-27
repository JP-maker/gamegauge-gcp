# gamegauge-gcp — essai de déploiement sur GKE

Infrastructure et manifests pour déployer temporairement GameGauge sur Google
Kubernetes Engine, dans le cadre d'un exercice. **Cet environnement est fait
pour être détruit** : voir la phase 6 de la procédure.

Le déploiement de production sur VPS n'est pas concerné. Les dépôts applicatifs
utilisés ici sont des copies (`gamegauge-ui-gcp`, `gamegauge-api-gcp`) dont les
workflows GitHub Actions ont été supprimés, précisément pour qu'aucun essai ne
puisse republier une image de production.

## Contenu

    terraform/            VPC, sous-réseau VPC-native, cluster GKE Standard
                          zonal, pool de nœuds, dépôt Artifact Registry
    k8s/                  Namespace, MySQL (StatefulSet + PVC), backend
                          (Deployment + Service), frontend (Deployment +
                          Service LoadBalancer)
    monitoring/           Prometheus, kube-state-metrics et Grafana avec sa
                          source de données et son tableau de bord
                          provisionnés. Volontairement hors de k8s/ pour
                          rester optionnel.
    api-instrumentation/  Les trois modifications à porter dans la copie de
                          l'API pour obtenir des métriques applicatives
    secret.example.yaml   Modèle du Secret, à copier en k8s/01-secret.yaml.
                          Délibérément hors de k8s/ : « kubectl apply -f k8s/ »
                          l'appliquerait sinon avec ses mots de passe d'exemple.
    nginx.gke.conf        Configuration nginx sans TLS, à copier dans le
                          dépôt UI dupliqué en remplacement de nginx.conf
    scripts/              preflight.sh (contrôle des préconditions avant de
                          construire), build-and-push.sh et cleanup-check.sh

## Architecture

    Internet
       │
       ▼
    Service LoadBalancer (IP publique GCP)
       │
       ▼
    frontend  ── nginx sert Angular, et relaie /api/ ──▶ backend (Spring Boot)
                                                             │
                                                             ▼
                                                       mysql (StatefulSet)
                                                             │
                                                             ▼
                                                    PersistentVolume 10 Gio

Tout le trafic entre les pods reste interne au cluster : le backend n'est
jamais exposé publiquement, et comme Angular appelle `/api` en relatif, il n'y
a aucune question de CORS à traiter.

## Ordre d'application

Les fichiers de `k8s/` sont numérotés parce que l'ordre compte : nginx résout
le nom `backend` au démarrage, et le pod frontend redémarre en boucle tant que
ce Service n'existe pas. `kubectl apply -f k8s/` les traite dans l'ordre
alphabétique et ignore les sous-dossiers, ce qui convient.

Le dossier `monitoring/` s'applique séparément, après que l'application
fonctionne.

## Avant de construire les images

    ./scripts/preflight.sh

L'essai répartit ses modifications sur trois dépôts, et plusieurs d'entre elles
échouent en silence si on les oublie : un Actuator absent ne casse rien, il
laisse simplement des graphiques vides. Ce script vérifie les onze conditions
concernées et affiche la commande de correction pour chacune. Il doit être vert
avant toute construction d'image.

## Coût indicatif

Environ **2,50 $ par jour** si l'ensemble tourne en continu avec des nœuds
`e2-medium`, et plutôt **4,30 $** avec des `e2-standard-2`, souvent nécessaires
pour que le backend trouve sa place. Soit une trentaine de centimes à moins d'un
euro pour une séance de trois heures. Le forfait de gestion du cluster
(0,10 $/h) est couvert par le crédit gratuit de 74,40 $/mois, à condition que le
cluster soit zonal — d'où le choix d'une zone et non d'une région dans
`variables.tf`.

La pile de supervision n'ajoute rien à la facture : ni équilibreur de charge
(l'accès à Grafana passe par `kubectl port-forward`), ni disque persistant
(Prometheus et Grafana utilisent des volumes éphémères). Elle consomme en
revanche de la mémoire sur les nœuds, environ 900 Mio réservés au total.

## Procédure complète

Voir le runbook pas à pas fourni séparément.
