# Instrumenter la copie de l'API pour Prometheus

Trois modifications à faire dans le dépôt `gamegauge-api-gcp`, puis une
reconstruction de l'image. Sans elles, Prometheus collecte bien les métriques
d'infrastructure (nœuds, pods, objets Kubernetes) mais aucune métrique
applicative, et les quatre premiers panneaux du tableau de bord restent vides.

Rien de tout cela ne touche le dépôt de production.

---

## 1. Deux dépendances dans `pom.xml`

À ajouter dans le bloc `<dependencies>`. Aucune version à préciser : le parent
`spring-boot-starter-parent` 3.5.5 les gère.

```xml
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>
        <dependency>
            <groupId>io.micrometer</groupId>
            <artifactId>micrometer-registry-prometheus</artifactId>
            <scope>runtime</scope>
        </dependency>
```

`actuator` ajoute les endpoints de supervision ; `micrometer-registry-prometheus`
leur donne le format que Prometheus sait lire, exposé sur
`/actuator/prometheus`.

Profitez-en pour retirer la déclaration en double de
`spring-boot-starter-mail`, présente deux fois dans ce `pom.xml` : Maven émet un
avertissement à chaque compilation.

---

## 2. Ouvrir `/actuator/**` dans `SecurityConfig.java`

C'est l'étape qu'on oublie, et elle est invisible : sans elle Prometheus reçoit
un 401 sur chaque collecte, et le tableau de bord reste désespérément vide sans
qu'aucun pod ne soit en erreur.

La configuration actuelle termine par `anyRequest().authenticated()`, donc tout
ce qui n'est pas listé dans `PUBLIC_URLS` exige un jeton. Ajoutez-y les endpoints
de supervision :

```java
    private static final String[] PUBLIC_URLS = {
            "/api/auth/**",
            // -- Supervision (Prometheus, sondes Kubernetes) --
            "/actuator/**",
            // -- Swagger UI v3 (OpenAPI) --
            "/v3/api-docs/**",
            "/swagger-ui/**",
            "/swagger-ui.html"
    };
```

L'entrée `/api/auth/**` y figure deux fois dans le fichier d'origine : l'occasion
de nettoyer.

**Cela n'expose rien sur Internet.** Le Service `backend` est de type ClusterIP,
et nginx ne relaie que `location /api/`. Une requête vers
`http://IP_PUBLIQUE/actuator/prometheus` tombe donc sur la règle `try_files` du
frontend et reçoit `index.html`, jamais les métriques. Seuls les pods du cluster
atteignent `/actuator`.

---

## 3. Reconstruire et redéployer

```bash
cd ../gamegauge-gcp/scripts
PROJECT_ID="votre-project-id" ./build-and-push.sh
```

Le tag ne changeant pas (`essai`), Kubernetes ne voit aucune différence dans le
manifeste et ne redéploie pas de lui-même. Forcez le remplacement des pods :

```bash
kubectl -n gamegauge rollout restart deployment/backend
kubectl -n gamegauge rollout status deployment/backend
```

Puis vérifiez que les métriques sortent bien, depuis l'intérieur du cluster :

```bash
kubectl -n gamegauge exec deploy/backend -- \
  sh -c 'wget -qO- http://localhost:8080/actuator/prometheus | head -20'
```

Vous devez voir des lignes `jvm_memory_used_bytes`, `http_server_requests_...`,
`process_cpu_usage`.

**Un 403 — et non un 401 — est la réponse de Spring Security à une requête non
authentifiée ici**, faute de `httpBasic()` ou de `formLogin()` dans la
configuration : c'est `Http403ForbiddenEntryPoint` qui répond. Deux causes
possibles, que cette commande distingue :

```bash
kubectl -n gamegauge logs -l app=backend | grep -i "beneath base path"
```

Une ligne `Exposing 3 endpoint(s) beneath base path '/actuator'` signifie
qu'Actuator est bien présent : le blocage vient donc de l'étape 2, `/actuator/**`
manque dans `PUBLIC_URLS`. Aucune ligne signifie que l'image qui tourne ne
contient pas Actuator, et le problème est ailleurs : voir ci-dessous.

### Le piège du tag mutable

Le tag `essai` est réécrit à chaque build. Or Kubernetes n'applique
`imagePullPolicy: Always` par défaut qu'au tag `latest` : pour tout autre tag il
retombe sur `IfNotPresent` et **réutilise l'image déjà en cache sur le nœud**,
même après un `rollout restart`. Votre nouvelle image ne tourne alors jamais.

Les manifests fournis portent désormais `imagePullPolicy: Always`. Pour vérifier
sur un déploiement existant, comparez les empreintes :

```bash
kubectl -n gamegauge get pod -l app=backend \
  -o custom-columns='POD:.metadata.name,DIGEST:.status.containerStatuses[0].imageID'

PREFIX=$(terraform -chdir=terraform output -raw image_prefix)
gcloud artifacts docker images list "$PREFIX/gamegauge-api" --include-tags \
  --format='table(version,tags,createTime)'
```

Si le `sha256` du pod ne correspond pas à la version la plus récente du registre :

```bash
kubectl -n gamegauge patch deployment backend --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"Always"}]'
kubectl -n gamegauge rollout restart deployment/backend
```

La solution de fond, celle qu'on retient pour un vrai projet, consiste à taguer
chaque build avec le sha du commit plutôt qu'avec un nom fixe : le manifeste
change alors à chaque déploiement, Kubernetes le voit, et la question du cache ne
se pose plus. C'est exactement ce que fait votre pipeline de production sur le
VPS avec ses tags `sha-…`.

---

## 4. Optionnel : de vraies sondes de santé

Avec Actuator en place, les sondes TCP du manifeste peuvent céder la place à des
sondes qui interrogent réellement l'application — y compris l'état de sa
connexion à la base. Remplacez les deux blocs `tcpSocket` de
`k8s/20-backend.yaml` par :

```yaml
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 12
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            initialDelaySeconds: 120
            periodSeconds: 20
```

Ne faites ce changement qu'**après** avoir confirmé à l'étape 3 que les endpoints
répondent, sinon les pods seront redémarrés en boucle.
