#!/usr/bin/env bash
# Script de provisioning de la VM de lab — exécuté à chaque démarrage (metadata_startup_script).
# Idempotent : chaque section vérifie l'état avant d'agir, donc rejouable sans effet de bord.
set -euo pipefail

# --- 1. Mise à jour système + outils de base ---------------------------------
apt-get update -y
apt-get upgrade -y
apt-get install -y git curl ca-certificates gnupg ufw fail2ban unattended-upgrades

# --- 2. Docker (dépôt officiel) ------------------------------------------------
if ! command -v docker &>/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    >/etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

# Durcissement du daemon Docker : interdit l'élévation de privilèges, limite les logs
cat >/etc/docker/daemon.json <<'EOF'
{
  "no-new-privileges": true,
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
systemctl restart docker

# --- 3. Limite la durée de démarrage de k3s --------------------------------------
# L'unit générée par l'installeur k3s a TimeoutStartSec=0 (illimité). Si k3s
# reste bloqué (ex. serving-kubelet.key corrompu par un arrêt brutal précédent),
# son job de démarrage ne se termine jamais et bloque multi-user.target — donc
# ce script (google-startup-scripts.service, qui dépend de multi-user.target)
# ne tourne plus jamais, et la section 4b d'auto-réparation ci-dessous ne peut
# pas s'exécuter. On force une limite : passé ce délai, le job échoue (k3s.service
# est en `Wants=`, pas `Requires=`, donc ça ne bloque pas le boot) et le reste du
# provisioning peut continuer.
mkdir -p /etc/systemd/system/k3s.service.d
cat >/etc/systemd/system/k3s.service.d/override.conf <<'EOF'
[Service]
TimeoutStartSec=120
EOF
systemctl daemon-reload

# --- 4. k3s ------------------------------------------------------------------------
# Note : install par défaut, sans flags de durcissement (--secrets-encryption,
# --protect-kernel-defaults, --kube-apiserver-arg=..., --disable=traefik). Avec
# ces flags, l'agent embarqué ne devenait jamais prêt ("node password not set"
# / 400 sur /v1-k3s/serving-kubelet.crt en boucle), même sur un datastore neuf
# et un boot non interrompu — donc sans rapport avec les arrêts forcés par
# Terraform. Un cluster qui démarre est plus utile pour les projets suivants
# qu'un cluster durci qui ne démarre jamais ; le durcissement pourra être
# réintroduit flag par flag plus tard si besoin.
if ! command -v k3s &>/dev/null; then
  curl -sfL https://get.k3s.io | sh -
fi

# --- 4b. Auto-réparation k3s ------------------------------------------------------
# La VM est arrêtée par Terraform juste après sa création (desired_status =
# TERMINATED), en pleine génération des certificats/secrets par k3s. Ça laisse
# des fichiers vides (0 octet) que k3s ne régénère JAMAIS tout seul car ils
# existent déjà — ex. /etc/rancher/node/password (le mot de passe que l'agent
# embarqué envoie au serveur pour s'enregistrer). Un mot de passe vide fait
# échouer l'enregistrement ("node password not set", 400 en boucle), même sur
# un datastore /var/lib/rancher/k3s tout neuf. On attend jusqu'à 60s ; si k3s
# n'est toujours pas prêt, on repart d'un état propre — sans risque sur un
# cluster qui n'a encore rien déployé.
k3s_ready() {
  systemctl is-active --quiet k3s && k3s kubectl get nodes &>/dev/null
}
ready=false
for _ in $(seq 1 12); do
  if k3s_ready; then
    ready=true
    break
  fi
  sleep 5
done
if [ "$ready" = false ]; then
  systemctl stop k3s || true
  /usr/local/bin/k3s-killall.sh || true
  rm -rf /var/lib/rancher/k3s/server /var/lib/rancher/k3s/agent /etc/rancher/node
  # `|| true` : si k3s reste bloqué malgré la réinitialisation (timeout
  # systemd, cf. override section 3), on ne doit pas faire échouer tout setup.sh
  # (sections 5-6 ci-dessous) — k3s continuera de réessayer en arrière-plan
  # via Restart=on-failure.
  systemctl start k3s || true
fi

# --- 5. Pare-feu local (défense en profondeur, redondant avec le firewall GCP) --
ufw default deny incoming
ufw default allow outgoing
ufw allow from 35.235.240.0/20 to any port 22 proto tcp comment 'SSH via IAP uniquement'
ufw --force enable

# --- 6. Mises à jour de sécurité automatiques -----------------------------------
systemctl enable --now unattended-upgrades

# --- Pense-bête (à faire manuellement après la première connexion) -------------
# sudo usermod -aG docker $(whoami)   # pour utiliser docker sans sudo
# sudo k3s kubectl get nodes          # vérifier que le cluster est prêt
