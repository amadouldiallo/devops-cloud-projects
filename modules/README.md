# `modules/` — modules Terraform partagés

Ce dossier est **externe à tous les projets** : il ne contient aucun state,
aucun `backend.tf`, aucun `provider.tf` — uniquement des modules réutilisables
(`variables.tf` / `main.tf` / `outputs.tf`), consommés par les states qui en
ont besoin via un chemin relatif.

| Module | Rôle | Consommé par |
|---|---|---|
| [`network/`](network/) | VPC, sous-réseaux, routage, Cloud NAT | `landing-zone` |
| [`iam/`](iam/) | Bindings IAM (principe du moindre privilège) | `landing-zone` |
| [`budget/`](budget/) | Alerte de facturation (FinOps as Code) | `landing-zone` |
| [`compute/`](compute/) | VM de lab à la demande (lab-vm) | `landing-zone` |
| [`wif-pool/`](wif-pool/) | Pool/provider Workload Identity Federation GitHub — un par projet (`pool_id` distinct) | `projet-04-cloudrun/terraform` |
| [`cloudrun-service/`](cloudrun-service/) | Artifact Registry + Cloud Run + SA déployeur, pour une app donnée | `projet-04-cloudrun/terraform` |

## Convention d'usage

- Depuis `landing-zone/` : `source = "../modules/<nom>"`
- Depuis `projet-XX/terraform/` : `source = "../../modules/<nom>"`

## Pourquoi ce dossier existe

Avant cette restructuration, tous les modules vivaient sous
`landing-zone/modules/` et partageaient le **même state** que la fondation.
Un `apply` sur un module applicatif (ex. Cloud Run pour le Projet 04)
réappliquait alors tout le root module de `landing-zone`, avec le risque de
recréer/modifier des ressources partagées (réseau, NAT...) sans rapport avec
le changement voulu.

En sortant les modules de `landing-zone/` :

- chaque **projet** a son propre dossier Terraform + son propre state + son
  propre pool WIF, et ne référence que les modules dont il a besoin ;
- la **fondation** (`landing-zone/`) garde son state séparé pour les
  ressources partagées (réseau, IAM, budget, lab-vm) ;
- un module modifié ici (ex. `cloudrun-service/`) n'affecte que les states qui
  l'utilisent — pas les autres projets ; détruire le state d'un projet
  n'affecte ni la fondation ni les autres projets.

Voir [`../landing-zone/README.md` § 2](../landing-zone/README.md#2-pourquoi-découper-en-modules-network-iam-budget-)
et [§ 10](../landing-zone/README.md#10-fondation-vs-projets-un-state-et-un-pool-wif-indépendant-par-projet)
pour le détail de cette architecture.
