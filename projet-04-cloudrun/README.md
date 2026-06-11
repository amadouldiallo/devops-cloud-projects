# Projet 04 — Backend FastAPI sur Cloud Run

Petit backend FastAPI (`/health` + `/chat` avec rate limiting), conteneurisé
et déployé en serverless sur **Cloud Run**, via un pipeline CI/CD GitHub
Actions sans clé statique.

> 🏗️ L'infrastructure GCP (Artifact Registry, service Cloud Run, identité de
> déploiement) est provisionnée par Terraform — voir
> [`../landing-zone/README.md` § 10](../landing-zone/README.md#10-le-module-cloudrun--cicd-cloud-run-sans-clé-statique-projet-04).
> Ce document couvre uniquement le **code applicatif**.

---

## 🗺️ Structure

```
projet-04-cloudrun/
├── app/
│   └── main.py        # API FastAPI : /health + /chat
├── requirements.txt
└── Dockerfile          # build multi-stage, utilisateur non-root
```

---

## 🧠 Concept : `/health` et rate limiting

`/health` est l'endpoint que Cloud Run (et tout orchestrateur) appelle pour
savoir si l'instance est vivante. `/chat` est protégé par un **rate limit**
(10 requêtes/minute/IP via `slowapi`) — la première brique de protection
contre l'abus d'un service "IA".

> 🔑 **Analogie :** `/health` est le videur qui vérifie que le bâtiment est
> ouvert. Le rate limiting est le tourniquet du métro : au-delà d'un certain
> nombre de passages par minute, il bloque — pour protéger ce qu'il y a
> derrière.

---

## Lancer en local

```bash
cd projet-04-cloudrun
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

uvicorn app.main:app --reload
```

Ouvre `http://localhost:8000/` dans un navigateur : un petit formulaire envoie
le message à `/chat` et affiche la réponse du serveur.

```bash
curl http://localhost:8000/health
curl -X POST http://localhost:8000/chat -d "message=bonjour"
```

---

## Construire et lancer l'image Docker

Le `Dockerfile` est en **multi-stage** : un stage `builder` installe les
dépendances Python, le stage final ne copie que le résultat et tourne avec un
utilisateur non-root (`appuser`). L'app écoute sur `$PORT` (`8080` par
défaut), comme l'exige Cloud Run.

```bash
docker build -t backend:local .
docker run --rm -p 8080:8080 backend:local

curl http://localhost:8080/health
```

---

## Déployer sur Cloud Run

### Option 1 — déploiement manuel (vol d'essai)

Cloud Build construit l'image à partir du `Dockerfile` et la déploie :

```bash
gcloud run deploy backend \
  --source . \
  --region europe-west9 \
  --allow-unauthenticated
```

### Option 2 — pipeline CI/CD (automatique)

[`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml) build +
push l'image vers Artifact Registry et redéploie Cloud Run à chaque
`git push` sur `main` (uniquement si `projet-04-cloudrun/**` a changé).
L'authentification GCP se fait via **Workload Identity Federation** — pas de
clé JSON stockée dans GitHub.

Prérequis (une seule fois, après `terraform apply` du module `cloudrun`) :
secrets de repo `WIF_PROVIDER` et `WIF_SERVICE_ACCOUNT` — voir
[`../landing-zone/README.md` § 10](../landing-zone/README.md#10-le-module-cloudrun--cicd-cloud-run-sans-clé-statique-projet-04).

---

## Tester le déploiement

```bash
URL=$(gcloud run services describe backend --region europe-west9 --format="value(status.url)")

curl ${URL}/health
curl -X POST ${URL}/chat -d "message=bonjour"
```

Vérifier le rate limiting (la 11ᵉ requête en moins d'une minute doit renvoyer
`429`) :

```bash
for i in $(seq 1 11); do
  curl -s -o /dev/null -w "requête $i → %{http_code}\n" \
    -X POST ${URL}/chat -d "message=test${i}"
done
```

---

## 📖 Glossaire express

| Terme | Définition courte |
|---|---|
| **FastAPI** | Framework Python pour APIs, basé sur les *type hints* |
| **Rate limiting** | Limite le nombre de requêtes par client sur une fenêtre de temps |
| **Multi-stage build** | Dockerfile en plusieurs `FROM` : un stage prépare, un autre n'embarque que le résultat |
| **Cloud Run** | Service serverless qui exécute un conteneur à la demande, scale-to-zero |
| **Workload Identity Federation** | Authentification GitHub Actions → GCP sans clé JSON statique |
