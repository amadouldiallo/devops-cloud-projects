# Landing Zone GCP — Projet 01 (partie 1 : réseau)

Ce projet pose les fondations **Infrastructure as Code (Terraform)** d'un
environnement GCP : remote state, structure modulaire, et premier module
fonctionnel (réseau).

> 🎯 **Objectif pédagogique :** comprendre *pourquoi* on structure un projet
> Terraform de cette façon avant même de se soucier de ce qu'on déploie.

---

## 1. Pourquoi un *remote state* (et pourquoi GCS) ?

Le **state Terraform** (`terraform.tfstate`) est le fichier qui fait correspondre
ton code à la réalité du cloud (quelles ressources existent, avec quel ID...).

- En local, ce fichier traîne sur ta machine : pas de partage en équipe, risque de
  conflits, risque de perte (et donc de "désynchronisation" entre le code et la
  réalité — un cauchemar à corriger).
- En **remote state** (ici sur un bucket **GCS** : `gs://devops-498817-tfstate`),
  le fichier est centralisé, partageable, et — point clé — **versionné** (on a
  activé le *versioning* du bucket). Si le state se corrompt ou qu'une mauvaise
  manip écrase une bonne version, on peut revenir en arrière.

> 📌 **Pourquoi GCS et pas un autre backend ?** Parce qu'on est sur GCP : c'est le
> backend natif, géré, peu coûteux (quelques centimes/mois pour un fichier de
> quelques Ko), et il gère nativement le **locking** (deux `apply` simultanés ne
> peuvent pas se marcher dessus).

Configuration dans [`backend.tf`](backend.tf) :
```hcl
backend "gcs" {
  bucket = "devops-498817-tfstate"
  prefix = "landing-zone/state"   # un "dossier" logique dans le bucket
}
```
> Le `prefix` permet de stocker plusieurs states (un par projet/environnement)
> dans **un seul bucket**, proprement séparés.

---

## 2. Pourquoi découper en modules (`network`, `iam`, `budget`) ?

Un **module Terraform** est un sous-dossier réutilisable et testable
indépendamment, avec ses propres `variables.tf` (entrées) et `outputs.tf`
(sorties) — un peu comme une fonction dans un langage de programmation.

```
landing-zone/
├── backend.tf       # configuration du remote state
├── provider.tf      # quel cloud, quel projet, quelle région
├── variables.tf     # variables globales du projet
├── main.tf          # assemble les modules
└── modules/
    ├── network/     # VPC, sous-réseaux, routage, NAT
    ├── iam/         # rôles et permissions (J2)
    └── budget/      # alertes de facturation as code (J2)
```

> 📌 **Pourquoi cette découpe et pas un seul gros fichier ?**
> - **Lisibilité** : chaque module a une responsabilité claire (principe de
>   responsabilité unique, comme en dev logiciel)
> - **Réutilisabilité** : le module `network` pourra être réutilisé tel quel pour
>   un futur projet, ou dupliqué pour un environnement de staging
> - **Test isolé** : on peut faire un `plan`/`apply` ciblé sur un seul module
>   (`terraform plan -target=module.network`) pendant qu'on le développe
> - **Travail en équipe** : deux personnes peuvent travailler sur deux modules
>   différents sans se gêner

---

## 3. Le module `network` — vue d'ensemble puis décortiqué

### Schéma — ce qu'on construit

```
                              Internet
                                 ▲
                                 │ trafic SORTANT uniquement
                                 │ (aucune connexion entrante possible)
                        ┌────────┴──────────┐
                        │     Cloud NAT       │
                        │  main-vpc-nat-...   │
                        └────────▲────────────┘
                                 │ s'appuie sur
                        ┌────────┴──────────┐
                        │   Cloud Router      │
                        │ main-vpc-router-... │
                        └────────▲────────────┘
                                 │
  ┌──────────────────────────────────────────────────────────┐
  │  VPC : main-vpc   (auto_create_subnetworks = false)        │
  │                                                              │
  │  ┌────────────────────────────────────────────────────┐  │
  │  │ Subnet : main-vpc-subnet-europe-west1                  │  │
  │  │   CIDR   : 10.10.0.0/20   (~4096 adresses IP)          │  │
  │  │   Région : europe-west1                                │  │
  │  │   ✅ VPC Flow Logs (50 % sampling)                     │  │
  │  │   ✅ Private Google Access                             │  │
  │  │                                                          │  │
  │  │      [futures VM, sans IP publique]                    │  │
  │  └────────────────────────────────────────────────────┘  │
  └──────────────────────────────────────────────────────────┘
```

> 🔑 **Analogie :** le VPC est comme un **immeuble privé** dont tu choisis
> l'adresse (`10.10.0.0/20`). Le sous-réseau est un **étage** de cet immeuble.
> Cloud Router + Cloud NAT forment le **local courrier** au rez-de-chaussée :
> les habitants (VM) peuvent envoyer du courrier (requêtes sortantes) sans que
> personne à l'extérieur ne connaisse leur adresse personnelle (IP publique).

Fichier [`modules/network/main.tf`](modules/network/main.tf), 4 ressources :

### a. Le VPC (`google_compute_network`)
```hcl
resource "google_compute_network" "main" {
  name                    = "main-vpc"
  auto_create_subnetworks = false
}
```
> `auto_create_subnetworks = false` est un choix **volontaire** : par défaut, GCP
> crée un sous-réseau dans *chaque* région du monde — bruyant, peu lisible, et
> contraire au principe "on ne déploie que ce dont on a besoin". On préfère
> déclarer **explicitement** chaque sous-réseau.

### b. Le sous-réseau (`google_compute_subnetwork`)
```hcl
resource "google_compute_subnetwork" "main" {
  ip_cidr_range = "10.10.0.0/20"   # ~4096 adresses IP
  region        = "europe-west1"
  log_config { ... }                # VPC Flow Logs
}
```
> Le `log_config` active les **VPC Flow Logs** : GCP enregistre des métadonnées
> sur le trafic réseau (qui parle à qui, sur quel port...). Très utile pour le
> debug réseau et la sécurité (détection d'anomalies). `flow_sampling = 0.5`
> échantillonne 50 % du trafic — un compromis coût/visibilité raisonnable pour
> un environnement d'apprentissage.

### c. Le Cloud Router (`google_compute_router`)
```hcl
resource "google_compute_router" "main" { ... }
```
> Le Cloud Router est un **prérequis technique** pour Cloud NAT — il ne fait rien
> de visible par lui-même ici, mais NAT s'appuie dessus pour gérer le routage BGP
> sous le capot. On ne peut pas créer de NAT sans lui.

### d. Le Cloud NAT (`google_compute_router_nat`)
```hcl
resource "google_compute_router_nat" "main" {
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
```
> Cloud NAT permet à des machines **sans IP publique** (donc non exposées
> directement à Internet — bonne pratique de sécurité) d'initier des connexions
> sortantes (ex. télécharger des paquets, appeler une API externe). C'est la
> pièce qui permettra à de futures VM internes d'avoir un accès Internet sortant
> sans être exposées en entrée.
>
> ⚠️ **Cloud NAT est facturé à l'heure dès qu'il existe** (que tu l'utilises ou
> non) — c'est pour ça que la consigne du jour précise : si tu fais `apply`,
> pense à `destroy` avant de dormir.

---

## 4. La séquence de validation Terraform — et pourquoi cet ordre précis

```bash
terraform init      # 1. télécharge providers + modules, configure le backend
terraform fmt       # 2. formate le code selon les conventions HCL officielles
terraform validate  # 3. vérifie la cohérence syntaxique et de types
terraform plan      # 4. calcule le diff entre le code et l'état réel du cloud
```

> 📌 **Pourquoi dans cet ordre ?** Chaque étape est un *filtre* de moins en moins
> rapide et de plus en plus coûteux :
> - `fmt` et `validate` sont **instantanés** et **locaux** (pas d'appel API) →
>   on les fait tourner à chaque sauvegarde, presque par réflexe
> - `plan` interroge l'**API GCP** pour comparer le réel et le déclaré → plus
>   lent, mais toujours **sans danger** (lecture seule, aucune ressource modifiée)
> - `apply` (qu'on ne fait *pas* ce soir) est la seule étape qui **modifie**
>   réellement le cloud — et donc la seule qui coûte de l'argent ou peut casser
>   quelque chose

Résultat obtenu :
```
Plan: 4 to add, 0 to change, 0 to destroy
```
Cela signifie : "si tu lances `apply` maintenant, Terraform créera ces 4
ressources, n'en modifiera aucune, n'en détruira aucune." C'est exactement ce
qu'on veut voir avant un premier déploiement — un plan propre et prévisible.

---

## 5. Et maintenant ?

On s'arrête volontairement à `plan` : **aucune ressource n'est créée**, donc
**aucun coût**. La suite (J2) ajoutera :
- le module `iam` (qui peut faire quoi sur le projet)
- le module `budget` (alertes de facturation *as code*, plutôt que cliquées dans
  la console — pour les rendre reproductibles et versionnées)
- une analyse de sécurité statique avec **checkov** (détecte les
  mauvaises pratiques dans le code Terraform avant même de déployer)

---

# J2 — Module IAM

## 6. Le module `iam` — principe du moindre privilège

Fichier [`modules/iam/main.tf`](modules/iam/main.tf).

### Pourquoi un compte de service dédié ?

En J1, tu as peut-être lancé `terraform` avec ton compte Google personnel (qui a
potentiellement les droits `owner` sur le projet). C'est pratique pour débuter,
mais dangereux en production :
- Si le token est compromis → accès total au projet
- Aucune séparation entre "moi qui navigue" et "Terraform qui provisionne"
- Impossible d'auditer précisément ce que Terraform a fait

Le SA `terraform-runner` résout ça : identité dédiée, rôles précis, traces claires.

> 🔑 **Analogie :** ton compte Google personnel, c'est **toi**, avec toutes
> tes clés (perso + travail). Le **service account** `terraform-runner`, c'est
> un **badge d'employé temporaire** que tu fabriques toi-même : il n'ouvre que
> les portes nécessaires (rôles ci-dessous), et si tu le perds, tu le désactives
> sans toucher à tes propres clés.

### Les ressources

```hcl
# 1. Le compte de service lui-même
resource "google_service_account" "terraform" {
  account_id   = "terraform-runner"
  display_name = "Terraform Runner"
}

# 2. Attribution de rôles via for_each — un resource par rôle
resource "google_project_iam_member" "terraform_sa_roles" {
  for_each = toset(var.terraform_sa_roles)
  role     = each.value
  member   = "serviceAccount:${google_service_account.terraform.email}"
}
```

> 📌 **`for_each = toset(list)` plutôt qu'une boucle `count`** : le `for_each`
> utilise la valeur du rôle comme clé dans le state Terraform. Si tu supprimes
> un rôle de la liste, Terraform sait exactement lequel désappliquer. Avec
> `count`, il utilise l'index — supprimer l'élément 0 décalerait tous les
> suivants et déclencherait des destroy/create inutiles.

### Rôles choisis — pourquoi pas `roles/editor` ?

Les rôles primitifs (`owner`, `editor`, `viewer`) donnent accès à **toutes** les
APIs GCP sans distinction. Checkov les signale systématiquement (CKV_GCP_49).
On utilise des rôles granulaires : `compute.networkAdmin` pour le réseau,
`storage.admin` pour le state, etc.

---

## 7. Le module `budget` — FinOps as Code

Fichier [`modules/budget/main.tf`](modules/budget/main.tf).

### Pourquoi coder le budget plutôt que le cliquer ?

Le budget créé manuellement en J1 dans la console est invisible dans le code :
un nouveau membre du projet ne saurait pas qu'il existe, et il serait perdu si
le projet était recréé. En le déclarant en Terraform, il est versionné, auditable,
et recréé automatiquement si quelqu'un le supprime.

```hcl
resource "google_billing_budget" "main" {
  billing_account = var.billing_account_id

  budget_filter {
    projects = ["projects/${data.google_project.current.number}"]
  }

  amount {
    specified_amount {
      currency_code = "EUR"
      units         = tostring(floor(var.budget_amount_eur))
    }
  }

  dynamic "threshold_rules" {
    for_each = var.alert_thresholds   # [0.5, 0.9, 1.0]
    content {
      threshold_percent = threshold_rules.value
    }
  }
}
```

> 📌 **`dynamic` block** : génère autant de blocs `threshold_rules` qu'il y a
> d'éléments dans `var.alert_thresholds`. C'est l'équivalent Terraform d'une
> boucle `for` — utile quand le nombre de blocs est variable.

### Pré-requis : `billing_account_id`

```bash
gcloud billing accounts list
```

Ce paramètre ne doit **pas** avoir de valeur par défaut dans le code (il est
spécifique à chaque utilisateur). On le passe via `terraform.tfvars` (non
commité) :

```hcl
billing_account_id = "XXXXXX-XXXXXX-XXXXXX"
```

### Schéma — vue d'ensemble IAM + Budget

```
┌──────────────────────────────────┐    ┌────────────────────────────┐
│ Service Account                    │    │ Billing Account              │
│ terraform-runner@PROJECT.iam...    │    │ 0170F9-AAEDBC-FFA533          │
│                                     │    │                              │
│ Rôles attribués :                   │    │  └─ Budget : 20 EUR / mois    │
│  • compute.networkAdmin             │    │       Seuils : 50 / 90 / 100 %│
│  • iam.serviceAccountAdmin          │    │       → email aux admins de   │
│  • iam.serviceAccountUser           │    │         facturation           │
│  • storage.admin                    │    └────────────────────────────┘
│  • resourcemanager.projectIamAdmin  │
└─────────────────┬──────────────────┘
                   │ identité utilisée pour
                   ▼
            terraform apply
                   │
                   ▼
   Ressources du projet devops-498817
   (VPC, subnet, router, NAT...)
```

> 📌 **Lecture du schéma :** le SA (à gauche) est l'**identité** qui exécute
> les actions. Le budget (à droite) est un **garde-fou indépendant**, attaché
> au compte de facturation — il surveille la dépense globale du projet, peu
> importe quelle identité a créé quoi.

---

## 8. Le module `compute` — VM de lab à la demande

### 🧠 Concept : une VM joignable, sans jamais l'exposer sur Internet

Jusqu'ici, aucune ressource créée n'a de "porte d'entrée" exploitable depuis
l'extérieur (VPC, IAM, budget sont des ressources de configuration, pas des
machines). La VM de lab change la donne : c'est une machine sur laquelle on va
se connecter en SSH, installer des outils, lancer des conteneurs.

Le réflexe classique — IP publique + règle firewall `0.0.0.0/0:22` — est une
mauvaise pratique : ça expose un port SSH au scan permanent d'Internet. Le
module `compute` combine trois mécanismes pour éviter ça :

| Mécanisme | Rôle |
|---|---|
| **Pas d'IP publique** | La VM n'a tout simplement aucune adresse joignable depuis Internet |
| **IAP TCP forwarding** | `gcloud` ouvre un tunnel chiffré vers le port 22, authentifié par IAM (`roles/iap.tunnelResourceAccessor`) — jamais de port exposé publiquement |
| **OS Login** | L'accès SSH est lié à ton identité Google (`roles/compute.osAdminLogin`), pas à une clé statique stockée dans les metadata |

> 🔑 **Analogie :** pense à un immeuble de bureaux sans porte donnant sur la
> rue. Pour entrer, tu passes par l'accueil, qui vérifie ton badge
> d'entreprise (IAP + IAM) et t'ouvre un accès temporaire vers ton bureau
> (tunnel SSH). Une fois à l'intérieur, ton badge personnel (OS Login)
> détermine si tu peux entrer dans la salle serveur (sudo) ou non.

### Schéma — comment on accède à `lab-vm`

```
   Toi (gcloud CLI, identité Google)
        │
        │ gcloud compute ssh lab-vm --tunnel-through-iap
        ▼
┌────────────────────────────────┐
│  IAP (Identity-Aware Proxy)        │  ← vérifie roles/iap.tunnelResourceAccessor
│  tunnel chiffré vers le port 22     │
└────────────────┬───────────────────┘
                 │ source = 35.235.240.0/20 (plage réservée Google)
                 ▼
┌────────────────────────────────────────────────────────┐
│  VPC main-vpc — subnet 10.10.0.0/20                        │
│                                                            │
│   ┌────────────────────────────────────┐                 │
│   │  lab-vm (10.10.x.x)                    │                 │
│   │  e2-standard-4 — PAS d'IP publique       │                 │
│   │  Shielded VM + OS Login                   │                 │
│   └─────────────────┬────────────────────┘                 │
│                     │ trafic sortant (apt, docker pull...)   │
│                     ▼                                        │
│              Cloud NAT → Internet                              │
└────────────────────────────────────────────────────────┘
```

### Les ressources

| Ressource | Rôle |
|---|---|
| `google_service_account.lab_vm` | SA dédié à la VM — droits minimaux (`logging.logWriter`, `monitoring.metricWriter`), jamais le SA par défaut du projet |
| `google_compute_firewall.allow_iap_ssh` | Autorise le port 22 **uniquement** depuis `35.235.240.0/20` (plage IAP) sur les instances taguées `iap-ssh` |
| `google_compute_instance.lab_vm` | VM `e2-standard-4`, Ubuntu 22.04, disque `pd-balanced` 50 Go, sans `access_config` (= pas d'IP publique), Shielded VM (secure boot, vTPM, integrity monitoring) |

### Pourquoi `desired_status = "TERMINATED"` + `lifecycle.ignore_changes` ?

GCP facture le **calcul** (vCPU/RAM) uniquement quand la VM tourne — le disque
est facturé en continu mais coûte quelques euros par mois. Comme cette VM est
"à la demande" (`que je lance à chaque fois de besoin`), `terraform apply` la
crée **à l'arrêt** :

```hcl
desired_status = "TERMINATED"

lifecycle {
  ignore_changes = [desired_status]
}
```

Sans le bloc `lifecycle`, chaque `terraform plan` après un `gcloud compute
instances start` proposerait de **rallumer→éteindre** la VM pour revenir à
l'état "désiré" du code — un faux problème que `ignore_changes` neutralise
une fois pour toutes : Terraform gère *l'existence* de la VM, `gcloud` gère
*si elle tourne*.

### Démarrer / se connecter / arrêter

```bash
# Démarrer la VM (quelques dizaines de secondes)
gcloud compute instances start lab-vm --zone=europe-west1-b

# Se connecter en SSH via IAP (aucune IP publique nécessaire)
gcloud compute ssh lab-vm --zone=europe-west1-b --tunnel-through-iap

# Arrêter la VM quand on a fini (stoppe la facturation calcul)
gcloud compute instances stop lab-vm --zone=europe-west1-b
```

### Coût

| État | Coût approximatif |
|---|---|
| VM `RUNNING` (e2-standard-4, europe-west1) | ~0,13-0,17 €/h |
| VM `TERMINATED` (disque `pd-balanced` 50 Go uniquement) | ~2-4 €/mois |

> 💡 Le réflexe FinOps du jour : démarrer la VM seulement le temps de
> travailler dessus, puis `gcloud compute instances stop`. Le budget créé en
> §7 continue de surveiller la dépense globale du projet, VM incluse.

### Et ensuite ?

Au démarrage, la VM exécute automatiquement
[`modules/compute/files/setup.sh`](modules/compute/files/setup.sh) : il
installe `git`, Docker (durci : `no-new-privileges`, rotation des logs) et un
cluster `k3s` (configuration par défaut), puis active `ufw` (SSH via IAP
uniquement) et `unattended-upgrades`.

Le script est **idempotent et auto-réparateur** : Terraform recrée/éteint la
VM dès les premières secondes du tout premier démarrage (cf.
`desired_status = "TERMINATED"` ci-dessus), ce qui peut interrompre k3s en
pleine génération de ses certificats. Au démarrage suivant, le script détecte
ce cas (`k3s kubectl get nodes` ne répond pas après 60s), nettoie l'état
partiel (`/var/lib/rancher/k3s/{server,agent}`, `/etc/rancher/node`) et
relance k3s proprement — sans intervention manuelle.

---

## 9. Checkov — audit de sécurité statique

Checkov analyse le code Terraform et remonte les mauvaises pratiques **avant**
tout déploiement. C'est un outil clé pour les pipelines CI/CD.

```bash
pip3 install checkov
checkov -d . --framework terraform --compact
```

### Finding corrigé en J2

**CKV_GCP_74** — *Ensure that Private Google Access is enabled for all subnetworks*

Le check détecte l'absence de `private_ip_google_access = true` dans le sous-réseau.

Sans cet attribut, les VM sans IP publique ne peuvent pas atteindre les APIs
Google (Cloud Storage, Secret Manager, Artifact Registry...) — elles n'ont
aucun chemin réseau vers ces services. Avec `private_ip_google_access = true`,
GCP route ce trafic via son réseau interne, sans passer par Internet.

**Correction appliquée** dans [`modules/network/main.tf`](modules/network/main.tf) :
```hcl
private_ip_google_access = true
```

### Résultat attendu après corrections

```
Passed checks: X, Failed checks: 0, Skipped checks: 0
```

Aucun finding HIGH ou CRITICAL.

---

## 10. Le module `cloudrun` — CI/CD Cloud Run sans clé statique (Projet 04)

### 🧠 Concept : séparer l'infra "permanente" de l'infra "applicative"

Les modules précédents (`network`, `iam`, `budget`, `compute`) posent les
fondations du projet — elles changent rarement. Le module `cloudrun` est
différent : il provisionne ce dont **une application** (le backend FastAPI du
[Projet 04](../projet-04-cloudrun/README.md)) a besoin pour exister et se
déployer en continu — un registre d'images, un service serverless, et une
identité dédiée pour le pipeline CI/CD.

> 🔑 **Analogie :** si `network`/`iam`/`compute` sont les fondations et les
> murs d'un immeuble, `cloudrun` est **un local commercial** prêt à accueillir
> un commerçant (l'app) — avec sa propre clé d'accès (le SA `cloudrun-deployer`)
> qui n'ouvre QUE ce local, pas tout l'immeuble.

### Schéma — du `git push` au service en ligne

```
GitHub Actions (push sur main)
        │  jeton OIDC (court terme, signé par GitHub)
        ▼
Workload Identity Federation ──► cloudrun-deployer@...iam.gserviceaccount.com
        │  credentials GCP temporaires (pas de clé JSON)
        ▼
┌────────────────────────────┐      ┌──────────────────────────┐
│ Artifact Registry              │ ───▶ │ Cloud Run : backend          │
│ backend-repo (europe-west9)    │      │ scale-to-zero, public        │
└────────────────────────────┘      └──────────────────────────┘
```

### Les ressources

| Ressource | Rôle |
|---|---|
| `google_project_service` | Active `run`, `artifactregistry`, `iamcredentials` sur le projet |
| `google_artifact_registry_repository.backend` | Registre Docker privé `backend-repo` (europe-west9) |
| `google_cloud_run_v2_service.backend` | Service serverless `backend` — créé avec une image placeholder, `lifecycle.ignore_changes` sur le conteneur (le pipeline CI/CD fait évoluer l'image ensuite) |
| `google_cloud_run_v2_service_iam_member.public` | `roles/run.invoker` à `allUsers` (équivalent `--allow-unauthenticated`) |
| `google_iam_workload_identity_pool.github` + `..._provider.github` | Pool/provider OIDC, restreint à `var.github_repo` via `attribute_condition` |
| `google_service_account.cloudrun_deployer` | SA dédié au pipeline — `run.admin`, `artifactregistry.writer`, `iam.serviceAccountUser` (pas `terraform-runner`, pas `lab-vm`) |
| `google_service_account_iam_member.github_wif_binding` | Autorise **ce repo GitHub précis** à emprunter l'identité du SA ci-dessus |

### Pourquoi pas une clé de service account JSON ?

Une clé JSON est une **chaîne d'accès statique** : si elle fuite (logs, repo
public par erreur...), elle reste valide jusqu'à révocation manuelle. La
**Workload Identity Federation** échange un jeton **OIDC** signé par GitHub
(valable quelques minutes, prouvant "je suis le run #123 du repo X") contre
des credentials GCP **temporaires** — aucun secret long terme à stocker.

### Récupérer les valeurs pour les secrets GitHub

```bash
terraform output cloudrun_workload_identity_provider     # → secret WIF_PROVIDER
terraform output cloudrun_deployer_service_account_email # → secret WIF_SERVICE_ACCOUNT
```

### Coût

Cloud Run **scale à zéro** : aucune instance (donc aucun coût de calcul) tant
qu'il n'y a aucun trafic. Seuls l'image stockée dans Artifact Registry
(quelques Mo) et le service Cloud Run lui-même (gratuit à l'arrêt) persistent.

> 📄 La suite — code de l'application, déploiement et tests — est documentée
> dans [`../projet-04-cloudrun/README.md`](../projet-04-cloudrun/README.md).

---

## 📖 Glossaire — termes du projet

### Terraform

| Terme | Définition |
|---|---|
| **State** | Fichier (`terraform.tfstate`) qui fait correspondre le code à la réalité du cloud — la "carte" de ce que Terraform a créé |
| **Backend** | Endroit où est stocké le state (ici : un bucket GCS) |
| **Provider** | Plugin qui sait parler à l'API d'un cloud donné (ici : `hashicorp/google`) |
| **Module** | Sous-dossier Terraform réutilisable, avec ses propres variables d'entrée et sorties — l'équivalent d'une fonction |
| **Resource** | Bloc qui décrit UN objet à créer dans le cloud (ex. `google_compute_network`) |
| **HCL** | *HashiCorp Configuration Language* — le langage déclaratif utilisé par Terraform (`.tf`) |
| **`init` / `fmt` / `validate` / `plan` / `apply`** | Les 5 commandes du cycle de vie Terraform, de la moins risquée (`init`) à la seule qui modifie le cloud (`apply`) |
| **Idempotence** | Propriété selon laquelle appliquer plusieurs fois le même code produit toujours le même résultat — un second `apply` ne change rien si rien n'a changé dans le code |
| **`for_each`** | Crée une ressource par élément d'une liste/map, en utilisant la valeur comme clé (contrairement à `count` qui utilise un index) |
| **`dynamic` block** | Génère un bloc répété (ex. `threshold_rules`) dynamiquement à partir d'une liste — l'équivalent d'une boucle `for` à l'intérieur d'une resource |
| **Data source** | Lecture seule d'une information existante dans le cloud (ex. `data "google_project"` pour récupérer le numéro d'un projet déjà créé) |

### GCP / Réseau

| Terme | Définition |
|---|---|
| **VPC** *(Virtual Private Cloud)* | Réseau privé virtuel isolé, à l'échelle du projet GCP |
| **Subnet** | Sous-découpage régional du VPC, avec sa propre plage d'adresses IP (CIDR) |
| **CIDR** | Notation `a.b.c.d/n` décrivant une plage d'adresses IP (ex. `10.10.0.0/20` = ~4096 adresses) |
| **VPC Flow Logs** | Journalisation des métadonnées de trafic réseau (qui parle à qui, sur quel port) — utile pour le debug et la sécurité |
| **Cloud Router** | Composant gérant le routage dynamique (BGP) — prérequis technique pour Cloud NAT |
| **Cloud NAT** | Service donnant un accès Internet **sortant** aux ressources sans IP publique, sans les exposer en entrée |
| **Private Google Access** | Permet aux ressources sans IP publique d'atteindre les APIs Google (Storage, Secret Manager...) via le réseau interne de Google |

### IAM / Facturation

| Terme | Définition |
|---|---|
| **Service Account (SA)** | Identité non-humaine utilisée par des applications/outils pour s'authentifier auprès des APIs GCP |
| **Rôle IAM** | Ensemble de permissions nommé (ex. `roles/storage.admin`) attribuable à un SA, utilisateur ou groupe |
| **Rôle primitif** | Rôle large hérité de l'historique GCP (`owner`, `editor`, `viewer`) — donne accès à toutes les APIs, déconseillé en production |
| **Principe du moindre privilège** | N'accorder que les permissions strictement nécessaires à une identité pour faire son travail |
| **Billing Account** | Compte de facturation auquel sont rattachés un ou plusieurs projets GCP |
| **Budget (GCP)** | Règle déclarative qui surveille la dépense d'un périmètre (projet) et déclenche des alertes à des seuils définis |

### Sécurité / Outils

| Terme | Définition |
|---|---|
| **IaC** *(Infrastructure as Code)* | Décrire son infrastructure cloud sous forme de code versionné, plutôt que de la créer manuellement dans une console |
| **Checkov** | Outil d'analyse statique qui scanne le code IaC (Terraform, CloudFormation...) à la recherche de mauvaises pratiques de sécurité, **avant** tout déploiement |
| **Finding** | Un résultat de scan (ex. checkov) signalant une non-conformité à une règle |
| **FinOps** | Pratique de gestion des coûts cloud intégrée dès la conception (budgets, alertes, tagging...) |

### Compute / k3s (module §8)

| Terme | Définition |
|---|---|
| **Compute Engine** | Service GCP de machines virtuelles (VM) à la demande |
| **IAP** *(Identity-Aware Proxy)* | Service GCP qui ouvre un tunnel chiffré et authentifié par IAM vers une ressource privée (ex. SSH sur une VM sans IP publique) |
| **OS Login** | Mécanisme liant les comptes Linux d'une VM aux identités IAM Google — remplace la gestion manuelle de clés SSH |
| **Shielded VM** | Option Compute Engine activant *secure boot*, *vTPM* et *integrity monitoring* pour détecter toute altération du démarrage/firmware |
| **`metadata_startup_script`** | Script exécuté automatiquement à chaque démarrage de la VM — utilisé ici pour installer/durcir Docker, k3s, etc. de façon idempotente |
| **k3s** | Distribution Kubernetes légère (binaire unique) de Rancher, adaptée aux VM de lab et environnements à ressources limitées |
| **`ufw`** *(Uncomplicated Firewall)* | Pare-feu local Linux (frontend à `iptables`) — ici en défense en profondeur, redondant avec le firewall GCP |
| **`fail2ban`** | Service qui bannit temporairement les IP après des tentatives de connexion répétées échouées |
| **`unattended-upgrades`** | Service Debian/Ubuntu qui applique automatiquement les correctifs de sécurité du système |
| **`--protect-kernel-defaults`** | Flag k3s/kubelet qui exige certains réglages `sysctl` du noyau — empêche un nœud mal configuré de démarrer silencieusement avec des défauts non sûrs |

### Cloud Run / CI-CD (module §10)

| Terme | Définition |
|---|---|
| **Artifact Registry** | Registre d'images Docker managé par GCP, intégré à l'IAM du projet |
| **Cloud Run** | Service serverless qui exécute un conteneur à la demande, **scale-to-zero** (0 instance = 0 coût hors trafic) |
| **OIDC** *(OpenID Connect)* | Protocole de jeton d'identité signé, à courte durée de vie |
| **Workload Identity Federation (WIF)** | Échange un jeton OIDC externe (ex. GitHub Actions) contre des credentials GCP temporaires — sans clé JSON statique |
| **`attribute_condition`** | Expression CEL qui restreint le WIF provider à une identité précise (ex. un seul repo GitHub) |
| **`principalSet://...`** | Syntaxe IAM désignant *l'ensemble des identités* satisfaisant une condition WIF (ex. "tous les workflows de ce repo"), plutôt qu'une identité unique |
