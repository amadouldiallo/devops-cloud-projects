# Projet 02 — Plateforme GitOps sur GKE avec ArgoCD

Un cluster **GKE** (provisionné par Terraform) piloté en continu par
**ArgoCD** : tout ce qui tourne dans le cluster est défini dans **ce repo
Git**, et ArgoCD le synchronise en permanence — c'est le modèle **GitOps**.

> 🎯 **Objectif pédagogique :** comprendre le modèle **pull** (le cluster
> *tire* son état désiré depuis Git) par opposition au modèle **push**
> (un pipeline CI *pousse* vers le cluster), et démontrer les **3 propriétés**
> qui distinguent vraiment GitOps d'un simple `kubectl apply` : **sync
> automatique**, **selfHeal** (anti-drift) et **rollback** via `git revert`.

> 🏗️ L'infrastructure GKE (cluster zonal, VPC dédié) est provisionnée par
> Terraform dans [`terraform/`](terraform/) — un **state indépendant** de la
> fondation, même logique que pour le Projet 04 (voir
> [`../landing-zone/README.md` § 10](../landing-zone/README.md#10-fondation-vs-projets-un-state-et-un-pool-wif-indépendant-par-projet)).
> Ce document couvre l'infra **et** la couche GitOps (`gitops-repo/`).

> ⚠️ **Coût :** un cluster GKE est facturé **à l'heure** (les nœuds Compute
> Engine — le control plane zonal est couvert par le free tier, 1 cluster
> zonal gratuit par compte de facturation). Le cluster de ce lab **n'est pas
> laissé en place** : voir [§ 9](#9-coût-et-cycle-de-vie-créer--détruire).

---

## 🗺️ Structure

```
projet-02-gitops/
├── terraform/                    # infra GKE — state indépendant
│   ├── backend.tf                # state: gs://devops-498817-tfstate/projet-02-gitops/state
│   ├── provider.tf
│   ├── variables.tf              # project_id, region, zone, cluster_name
│   ├── main.tf                   # module "network" (VPC dédié) + module "gke_cluster"
│   └── outputs.tf                # cluster_name, cluster_zone, vpc_name
│
└── gitops-repo/                  # CE QU'ARGOCD SYNCHRONISE DANS LE CLUSTER
    ├── apps/                      # définitions des `Application` ArgoCD
    │   ├── dev/demo-app.yaml      # Application -> environments/dev
    │   ├── staging/                # vide (.gitkeep) — Application à créer, voir § 10
    │   └── prod/                   # vide (.gitkeep) — Application à créer, voir § 10
    ├── base/                      # manifests Kubernetes communs
    │   ├── deployment.yaml         # Deployment "demo-app" (1 replica par défaut)
    │   ├── service.yaml             # Service ClusterIP "demo-app"
    │   └── kustomization.yaml
    └── environments/              # overlays Kustomize, un par environnement
        ├── dev/kustomization.yaml      # hérite de base/ (1 replica)
        ├── staging/kustomization.yaml  # patch: 2 replicas
        └── prod/kustomization.yaml     # patch: 3 replicas
```

---

## 1. Vue d'ensemble — le modèle **pull**

```
┌─────────────────────────────────────────────────────────────────────┐
│  GKE cluster "gitops-lab" (europe-west9-a, VPC-native, autoscalé)      │
│                                                                         │
│  ┌─────────────────────────┐                                          │
│  │  namespace argocd          │◀────┐                                  │
│  │  - argocd-server (UI/API)  │     │ reconciliation loop              │
│  │  - argocd-repo-server       │     │ ("est-ce que le cluster          │
│  │  - argocd-application-      │     │  ressemble à Git ?")             │
│  │    controller               │     │                                  │
│  │  - redis / dex               │─────┘                                  │
│  └─────────────────────────┘                                          │
│         │ crée/gère                                                     │
│         ▼                                                               │
│  ┌─────────────────────────┐                                          │
│  │  namespace dev               │  Deployment demo-app, Service demo-app │
│  └─────────────────────────┘                                          │
└──────────────────────────────────────┬────────────────────────────────┘
                                          │ git pull (lecture seule, repo public)
                                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Ce repo — gitops-repo/                                                │
│  ├── apps/        → définitions des `Application` ArgoCD              │
│  ├── base/        → manifests communs (Deployment, Service...)        │
│  └── environments/                                                     │
│      ├── dev/      → overlay Kustomize (1 replica)                    │
│      ├── staging/   → overlay (2 replicas)                             │
│      └── prod/      → overlay (3 replicas)                             │
└─────────────────────────────────────────────────────────────────────┘
```

### Pull vs push — la différence qui définit GitOps

| | **Push** (CI/CD classique) | **Pull** (GitOps / ArgoCD) |
|---|---|---|
| Qui initie le déploiement ? | Le pipeline CI (GitHub Actions...) | **L'agent dans le cluster** (ArgoCD) |
| Credentials cluster | Doivent **sortir** vers le pipeline CI | **Ne sortent jamais** du cluster |
| Comment savoir ce qui est déployé ? | Regarder les logs du pipeline | Lire **Git** — c'est la source de vérité |
| Que se passe-t-il si quelqu'un fait `kubectl edit` à la main ? | Rien ne le détecte | ArgoCD le détecte (**drift**) et peut le corriger (**selfHeal**) |

> 🔑 **Analogie :** *push* = un livreur a la clé de ton appartement et dépose
> les colis quand on le lui demande. *pull* = un colocataire qui vit dans
> l'appartement, consulte en permanence la liste de courses (Git) et range
> lui-même ce qu'il manque — et **range aussi** ce que quelqu'un d'autre
> aurait déplacé sans le noter sur la liste.

Le Projet 04 (Cloud Run) illustre le modèle *push* (GitHub Actions déploie via
Workload Identity Federation). Ce projet illustre le modèle *pull*.

---

## 2. Le cluster GKE — `modules/gke-cluster` (Terraform)

### 🧠 Concept : cluster zonal, VPC-native, node pool dédié

```hcl
module "network" {
  source = "../../modules/network"

  project_id  = var.project_id
  region      = var.region
  vpc_name    = "gitops-vpc"
  subnet_cidr = "10.20.0.0/20"

  secondary_ip_ranges = [
    { range_name = "pods", ip_cidr_range = "10.21.0.0/16" },
    { range_name = "services", ip_cidr_range = "10.22.0.0/20" },
  ]
}

module "gke_cluster" {
  source = "../../modules/gke-cluster"

  project_id           = var.project_id
  zone                 = var.zone
  cluster_name         = var.cluster_name
  network_self_link    = module.network.vpc_self_link
  subnetwork_self_link = module.network.subnet_self_link
  pods_range_name      = "pods"
  services_range_name  = "services"
}
```

| Choix | Pourquoi |
|---|---|
| **Cluster zonal** (`europe-west9-a`), pas régional | Le control plane d'**1 cluster zonal par compte de facturation** est gratuit. Un cluster régional (control plane répliqué sur 3 zones) est plus résilient mais facturé — inutile pour un lab. |
| **VPC-native** (`networking_mode = "VPC_NATIVE"`) | Les pods et services reçoivent des IP issues de **ranges secondaires** du sous-réseau (`pods` = `10.21.0.0/16`, `services` = `10.22.0.0/20`) plutôt qu'un réseau superposé (overlay). C'est le mode **recommandé par Google** : meilleure intégration au VPC, support du peering, des règles de pare-feu natives, etc. |
| **`remove_default_node_pool = true`** + node pool dédié | Le node pool "default" créé automatiquement par GKE n'est pas configurable finement. On le supprime et on définit notre propre `google_container_node_pool` (autoscaling, SA dédié, type de machine). |
| **SA dédié aux nœuds** (`gitops-lab-nodes@...`) avec rôles minimaux (`logging.logWriter`, `monitoring.metricWriter/viewer`, `stackdriver.resourceMetadata.writer`) | Par défaut, GKE utilise le **compte de service Compute Engine par défaut**, qui a souvent le rôle `Editor` sur le projet — beaucoup trop large. Principe du moindre privilège (même logique que CKS J3-J4 : RBAC, scan d'images). |
| **Autoscaling** (`min_node_count=1`, `max_node_count=3`) | Le lab tourne avec 2 nœuds `e2-small` ; l'autoscaler peut réduire à 1 (coût) ou monter à 3 si la charge augmente. |
| **`deletion_protection = false`** | Permet `terraform destroy` sans étape manuelle de déprotection — acceptable pour un lab, **pas** pour de la prod. |

### State et VPC indépendants

Ce projet a son **propre state** (`gs://devops-498817-tfstate/projet-02-gitops/state`)
et son **propre VPC** (`gitops-vpc`, distinct du VPC de la fondation). Aucune
lecture cross-state : `terraform destroy` ici n'affecte ni `landing-zone/` ni
`projet-04-cloudrun/`, et inversement — même principe que documenté dans
[`../landing-zone/README.md` § 10](../landing-zone/README.md#10-fondation-vs-projets-un-state-et-un-pool-wif-indépendant-par-projet).

### Provisionner / détruire

```bash
cd terraform
terraform init
terraform apply        # ~5-7 min (création du cluster + node pool)

gcloud container clusters get-credentials "$(terraform output -raw cluster_name)" \
  --zone "$(terraform output -raw cluster_zone)"
kubectl get nodes       # → 2 nœuds Ready
```

```bash
terraform destroy       # ~4-5 min — voir § 9
```

> 🔑 **Pourquoi Terraform plutôt que `gcloud container clusters create` ?**
> La définition complète du cluster (réseau, ranges, node pool, SA, rôles
> IAM) est **versionnée dans Git**. `terraform apply` est **idempotent** :
> il recrée exactement le même cluster, sans avoir à se souvenir d'une
> longue commande `gcloud`. C'est le même principe d'Infrastructure as Code
> que pour `landing-zone/` et `projet-04-cloudrun/`.

---

## 3. Installer ArgoCD — l'agent GitOps qui tourne *dans* le cluster

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

ArgoCD installe plusieurs composants dans le namespace `argocd` :

| Composant | Rôle |
|---|---|
| `argocd-server` | API + UI web |
| `argocd-repo-server` | Clone les repos Git et génère le YAML final (via Kustomize/Helm) |
| `argocd-application-controller` | Boucle de réconciliation : compare l'état du cluster à Git, applique les changements |
| `redis` | Cache (état des dépôts, etc.) |
| `dex` | Authentification (SSO) — non utilisé ici (login admin local) |

> ⚠️ **Piège rencontré : `last-applied-configuration` > 256 Ko.**
> Un `kubectl apply -f install.yaml` "normal" échoue sur le CRD
> `applicationsets.argoproj.io` :
> ```
> metadata.annotations: Too long: may not be more than 262144 bytes
> ```
> Ce CRD est trop volumineux pour l'annotation
> `kubectl.kubernetes.io/last-applied-configuration` (utilisée par le mode
> *client-side apply* pour calculer les diffs). La solution :
> **`--server-side --force-conflicts`** — l'API server calcule le diff
> lui-même (*Server-Side Apply*, sans cette annotation), et
> `--force-conflicts` autorise ArgoCD à reprendre la main sur des champs
> qu'il gère déjà s'il y a un conflit de propriété.

### Accéder à l'UI

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

kubectl port-forward svc/argocd-server -n argocd 8080:443
# → https://localhost:8080, login "admin" + mot de passe ci-dessus
```

---

## 4. Le repo Git comme source de vérité — `base/` + `environments/` (Kustomize)

### 🧠 Concept : DRY entre environnements

- **`base/`** : manifests **communs**, valides par eux-mêmes (un Deployment
  "raisonnable" par défaut — 1 replica, limites de ressources définies).
- **`environments/<env>/`** : un `kustomization.yaml` qui **référence**
  `base/` et applique des **patches** spécifiques (nombre de replicas...).

```yaml
# environments/staging/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: staging
resources:
  - ../../base
patches:
  - target:
      kind: Deployment
      name: demo-app
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 2
```

| | `base/` | `environments/dev/` | `environments/staging/` | `environments/prod/` |
|---|---|---|---|---|
| Replicas | 1 (défini dans `base/`) | 1 (hérité, pas de patch) | 2 (patch) | 3 (patch) |
| Namespace | — | `dev` | `staging` | `prod` |

```bash
kubectl kustomize environments/dev      # → replicas: 1
kubectl kustomize environments/staging  # → replicas: 2
kubectl kustomize environments/prod     # → replicas: 3
```

Même `base/`, trois résultats différents — toute modification commune (ex.
changer l'image, ajouter une variable d'environnement) se fait **une seule
fois** dans `base/deployment.yaml`.

> 🔑 **Analogie :** `base/` est la **recette de base** d'un plat. Chaque
> `environments/<env>/` est une **fiche d'ajustements** ("pour 1 personne",
> "pour 2", "pour 3") — on ne réécrit jamais toute la recette, on note juste
> les écarts.

---

## 5. L'objet `Application` ArgoCD — le lien entre Git et le cluster

[`gitops-repo/apps/dev/demo-app.yaml`](gitops-repo/apps/dev/demo-app.yaml) :

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-app-dev
  namespace: argocd          # les Application vivent dans le namespace argocd
spec:
  project: default
  source:
    repoURL: https://github.com/amadouldiallo/devops-cloud-projects.git
    targetRevision: main
    path: projet-02-gitops/gitops-repo/environments/dev
  destination:
    server: https://kubernetes.default.svc   # = "ce cluster" (in-cluster)
    namespace: dev
  syncPolicy:
    automated:
      prune: true      # supprime du cluster ce qui a disparu de Git
      selfHeal: true   # corrige automatiquement le drift (§ 6)
    syncOptions:
      - CreateNamespace=true   # crée le namespace `dev` s'il n'existe pas
```

| Champ | Rôle |
|---|---|
| `source.repoURL` / `path` / `targetRevision` | **Quoi** synchroniser : ce repo (public, donc pas de credentials Git à configurer), ce dossier (`environments/dev`), cette branche |
| `destination.server` / `namespace` | **Où** déployer : `https://kubernetes.default.svc` = le cluster sur lequel ArgoCD tourne, namespace `dev` |
| `syncPolicy.automated` | Sans ce bloc, ArgoCD détecte les écarts mais attend un clic "Sync" manuel dans l'UI |
| `prune: true` | Une ressource supprimée de `environments/dev/` est aussi supprimée du cluster |
| `selfHeal: true` | Une modification **directe** du cluster (drift) est **annulée** — le cluster revient à l'état de Git |

```bash
kubectl apply -f gitops-repo/apps/dev/demo-app.yaml

kubectl get application -n argocd
# NAME           SYNC STATUS   HEALTH STATUS
# demo-app-dev   Synced        Healthy

kubectl get all -n dev
# Deployment demo-app, Service demo-app, Pod demo-app-xxxxx Running
```

---

## 6. Les 3 piliers du GitOps — preuve par la pratique

N'importe qui peut faire un `kubectl apply` une fois. GitOps se prouve par
**trois propriétés** :

| Propriété | Question | Test |
|---|---|---|
| **Sync automatique** | Un changement dans Git se propage-t-il **sans action manuelle sur le cluster** ? | Modifier `environments/dev`, commit, push → ArgoCD applique seul |
| **SelfHeal (anti-drift)** | Une modification manuelle du cluster est-elle **annulée** automatiquement ? | `kubectl scale` → ArgoCD revient à l'état de Git |
| **Rollback** | L'historique Git permet-il de **revenir en arrière** sur l'infra comme sur du code ? | `git revert` → ArgoCD redéploie l'état précédent |

> 🔑 **Le fil commun :** dans les 3 cas, **Git reste la seule source de
> vérité**. Que l'écart vienne d'un commit voulu, d'une action manuelle non
> voulue, ou d'un besoin de revenir en arrière — ArgoCD réconcilie toujours
> le cluster vers ce que dit Git *en ce moment*.

### Test 1 — Sync automatique

```bash
# Éditer environments/dev/kustomization.yaml : ajouter un patch replicas: 2
git add gitops-repo/environments/dev/kustomization.yaml
git commit -m "dev passe à 2 replicas"
git push

# Forcer un refresh (ArgoCD interroge Git toutes les 3 min par défaut)
kubectl patch application demo-app-dev -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

kubectl get deployment demo-app -n dev   # READY: 2/2 — sans `kubectl apply`
```

### Test 2 — SelfHeal

```bash
kubectl scale deployment demo-app -n dev --replicas=5
kubectl get application -n argocd   # → OutOfSync (drift détecté)

# Quelques secondes plus tard, sans intervention :
kubectl get deployment demo-app -n dev   # revient à READY: 2/2
```

> ⚠️ **Pourquoi pas "supprimer un pod" ?** Supprimer un pod est récupéré par
> le **ReplicaSet** (mécanisme natif Kubernetes, indépendant d'ArgoCD). Le
> test pertinent change l'**état désiré dans le cluster** (`scale`) : c'est
> ArgoCD — pas le ReplicaSet — qui annule ce changement pour revenir à Git.

### Test 3 — Rollback

```bash
git revert HEAD --no-edit
git push
# (même refresh que Test 1)

kubectl get deployment demo-app -n dev   # READY revient à 1/1
```

> 🔑 Revenir en arrière sur un déploiement = `git revert` + push, **exactement
> comme pour du code**. Pas de commande `kubectl rollback` spécifique — Git
> **est** l'historique des déploiements.

---

## 7. Aller plus loin : le pattern **App-of-Apps**

### Le problème

`apps/dev/demo-app.yaml` est appliqué **manuellement** (`kubectl apply`). Pour
`apps/staging/` et `apps/prod/` (§ 10), il faudrait répéter ce `kubectl apply`
pour chaque environnement — une brèche dans le principe GitOps : la
*déclaration* de l'`Application` elle-même n'est pas pilotée par Git.

### Le pattern

Un `Application` **racine** ("root-app") dont `source.path` pointe vers le
dossier `apps/` lui-même. ArgoCD synchronise ce dossier... et y trouve
d'autres `Application` (dev, staging, prod), qu'il **crée et gère**.

```
┌─────────────────────────────────────────────────────────────────┐
│  Application "root-app"  (créée une seule fois, à la main)         │
│  source.path = gitops-repo/apps  +  directory.recurse: true        │
└──────────────────────────────┬────────────────────────────────────┘
                                  │ ArgoCD sync → crée les Application trouvées
                ┌─────────────────┼─────────────────┐
                ▼                 ▼                 ▼
   ┌────────────────┐ ┌────────────────┐ ┌────────────────┐
   │ demo-app-dev      │ │ demo-app-staging  │ │ demo-app-prod     │
   │ path: .../dev     │ │ path: .../staging │ │ path: .../prod    │
   └────────┬─────────┘ └────────┬─────────┘ └────────┬─────────┘
            ▼                    ▼                    ▼
      namespace dev        namespace staging      namespace prod
```

```yaml
# gitops-repo/apps/root-app.yaml (exemple)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/amadouldiallo/devops-cloud-projects.git
    targetRevision: main
    path: projet-02-gitops/gitops-repo/apps
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

> 📌 **Seule étape manuelle restante : le "bootstrap".** On crée `root-app`
> **une fois**. Après ça, ajouter un environnement = un commit dans
> `apps/<env>/`, plus aucun `kubectl apply`.

App-of-Apps devient intéressant **à partir de 2 `Application`** — voir § 10
(staging/prod, prochaine étape de ce projet).

---

## 8. Reproduire ce lab de bout en bout

```bash
# 1. Infra
cd terraform && terraform apply
gcloud container clusters get-credentials "$(terraform output -raw cluster_name)" \
  --zone "$(terraform output -raw cluster_zone)"

# 2. ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

# 3. Application
kubectl apply -f gitops-repo/apps/dev/demo-app.yaml
kubectl get application -n argocd   # Synced / Healthy
kubectl get all -n dev

# 4. UI (optionnel)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# → https://localhost:8080

# 5. Les 3 tests (§ 6)

# 6. Nettoyage
cd terraform && terraform destroy
```

---

## 9. Coût et cycle de vie : créer / détruire

- **Control plane zonal** : gratuit (1 par compte de facturation).
- **2 nœuds `e2-small`** : quelques centimes/heure — facturés tant que le
  cluster existe.
- `terraform destroy` supprime cluster, node pool, VPC et SA dédié — **tout**
  l'état désiré (`gitops-repo/`) reste dans Git, à coût nul.
- Relancer `terraform apply` recrée un cluster **identique**. Une fois
  ArgoCD réinstallé et l'`Application` réappliquée, `demo-app-dev`
  resynchronise automatiquement depuis Git — aucune action Git nécessaire.

---

## 10. Et maintenant ? Prochaines étapes

- **`apps/staging/`** et **`apps/prod/`** : dupliquer `demo-app.yaml` en
  changeant `path` (→ `environments/staging` / `environments/prod`) et
  `destination.namespace`.
- **App-of-Apps** (§ 7) : remplacer les `kubectl apply` successifs par un
  `root-app` unique qui gère les trois `Application`.
- **Repo privé** : si `devops-cloud-projects` devenait privé, ajouter un
  `Secret` de type `repository` (token/clé SSH) dans le namespace `argocd`
  pour qu'ArgoCD continue à cloner le repo.
- **Helm** : `source` d'une `Application` peut pointer vers un chart Helm au
  lieu d'un dossier Kustomize — utile si l'app grandit (valeurs
  paramétrables par environnement).

---

## 📖 Glossaire

| Terme | Définition |
|---|---|
| **GKE** *(Google Kubernetes Engine)* | Service Kubernetes managé de GCP — Google opère le control plane, on gère les nœuds (workers) |
| **Cluster zonal** | Cluster GKE dont le control plane vit dans une seule zone — éligible au tier gratuit (1 par compte de facturation) |
| **VPC-native / alias IP** | Mode réseau GKE où pods et services reçoivent des IP issues de **ranges secondaires** du sous-réseau, plutôt qu'un réseau overlay |
| **Node pool** | Groupe de nœuds (VM Compute Engine) avec une configuration commune (type de machine, disque, autoscaling) |
| **GitOps** | Pratique où Git est la **source de vérité unique** de l'état désiré, et un agent dans le cluster (ArgoCD) la synchronise en continu |
| **Modèle push vs pull** | *Push* = le pipeline CI envoie le déploiement vers le cluster ; *pull* = le cluster récupère lui-même l'état désiré (aucune credential cluster ne sort) |
| **ArgoCD** | Outil GitOps pour Kubernetes — surveille un repo Git et synchronise son contenu (manifests/Kustomize/Helm) vers un ou plusieurs clusters |
| **Reconciliation loop** | Boucle continue qui compare l'état réel du cluster à l'état désiré (Git) et corrige les écarts |
| **Server-Side Apply** | Mode `kubectl apply` où l'API server calcule le diff lui-même (pas d'annotation `last-applied-configuration`) — nécessaire pour les CRD volumineux comme `applicationsets.argoproj.io` |
| **Kustomize** | Outil (intégré à `kubectl`) de personnalisation de manifests YAML sans templating, via le pattern `base` + `overlays`/`patches` |
| **`base/`** | Manifests Kubernetes communs/génériques, réutilisés par tous les environnements |
| **Overlay (`environments/<env>/`)** | Dossier qui référence `base/` et applique des patches spécifiques (replicas, namespace, ressources) |
| **`Application` (ArgoCD)** | CRD ArgoCD (namespace `argocd`) qui décrit *quoi* synchroniser (`source`) et *où* (`destination`) |
| **`syncPolicy.automated`** | Rend la synchronisation automatique (`prune`, `selfHeal`), sans clic "Sync" manuel |
| **Drift** | Écart entre l'état réel du cluster et l'état désiré déclaré dans Git — déclenche `OutOfSync`, corrigé par `selfHeal` |
| **`OutOfSync` / `Synced` / `Healthy`** | Statuts d'une `Application` : `Synced`/`OutOfSync` = le cluster correspond (ou pas) à Git ; `Healthy` = les ressources fonctionnent |
| **Rollback GitOps** | `git revert` (+ push) d'un commit de manifests → ArgoCD redéploie automatiquement l'état précédent |
| **App-of-Apps** | Pattern où une `Application` "racine" pointe vers un dossier d'`Application` — ArgoCD les crée/gère comme n'importe quelle ressource |
