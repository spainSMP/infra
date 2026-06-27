#!/usr/bin/env bash
# Bootstrap del cluster oxa (ArgoCD + Traefik + external-dns + cert-manager + spainsmp).
# Ejecútalo desde una máquina CON acceso al API del cluster.
#
#   export KUBECONFIG=/ruta/a/oxa-kubeconfig.yaml
#   export CF_API_TOKEN=cfat_...           # token Cloudflare (o usa secrets/cloudflare-api-token.yaml)
#   bash bootstrap.sh
#
set -euo pipefail
cd "$(dirname "$0")"

echo "==> 1/5  Comprobando acceso al cluster..."
kubectl get nodes >/dev/null || { echo "!! kubectl no alcanza el cluster (¿KUBECONFIG?)"; exit 1; }

echo "==> 2/5  Namespaces..."
for ns in argocd external-dns cert-manager spainsmp; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

echo "==> 3/5  Secret de Cloudflare (external-dns + cert-manager)..."
if [[ -n "${CF_API_TOKEN:-}" ]]; then
  for ns in external-dns cert-manager; do
    kubectl -n "$ns" create secret generic cloudflare-api-token \
      --from-literal=apiKey="$CF_API_TOKEN" --dry-run=client -o yaml | kubectl apply -f -
  done
elif [[ -f secrets/cloudflare-api-token.yaml ]]; then
  kubectl apply -f secrets/cloudflare-api-token.yaml
else
  echo "!! Falta el token: exporta CF_API_TOKEN o crea secrets/cloudflare-api-token.yaml"; exit 1
fi

echo "==> 4/5  Instalando ArgoCD (10.0.0)..."
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd -n argocd \
  --version 10.0.0 -f bootstrap/argocd-values.yaml --wait

echo "==> 5/5  App-of-Apps (Traefik, external-dns, cert-manager, spainsmp)..."
kubectl apply -f bootstrap/root-app.yaml

cat <<'EOF'

✅ Bootstrap lanzado. external-dns ya está desplegándose.

Sigue el progreso:
  kubectl -n argocd get applications
  kubectl -n traefik get svc                         # IP del LoadBalancer (destino del DNS)
  kubectl -n external-dns logs deploy/external-dns -f # verás cómo crea argo.int.oxa.gg en Cloudflare

Cuando Traefik tenga IP, external-dns crea 'argo.int.oxa.gg' solo y cert-manager le saca el cert.

(Nota: la app 'spainsmp' quedará en error hasta que crees sus secrets
 spainsmp-api-db / spainsmp-app-secrets / ghcr. No afecta al DNS de Argo.)
EOF
