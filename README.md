# infra — GitOps del cluster de SpainSMP (oxa)

Bootstrap declarativo del cluster Kubernetes con **ArgoCD** + **patrón App-of-Apps**.
Argo se instala una vez y a partir de ahí despliega y mantiene todo lo demás desde Git.

```
ArgoCD (bootstrap, Helm)
└── root-app  (App-of-Apps → este repo, carpeta apps/)
    ├── traefik       → ingress interno (chart traefik/traefik 41.0.0, v3.7.5)
    ├── external-dns  → DNS Cloudflare (chart 1.21.1, v0.21.0) zonas oxa.gg + spainsmp.com
    └── spainsmp      → web + API (chart github.com/spainSMP/helm-spainsmp)
```

Versiones (latest a 2026-06-27): ArgoCD chart **10.0.0** (app v3.4.4), Traefik **41.0.0**
(v3.7.5), external-dns **1.21.1** (v0.21.0).

## Prerrequisitos

1. `kubectl` + `helm` apuntando al cluster:
   ```bash
   export KUBECONFIG=/ruta/a/oxa-kubeconfig.yaml
   kubectl get nodes      # debe responder (el API del cluster está en la red interna oxa)
   ```
2. **Subir este repo** a `github.com/spainSMP/infra` (rama `main`) — Argo lo lee desde ahí.
3. **Subir el chart** a `github.com/spainSMP/helm-spainsmp` (rama `main`) — lo consume `apps/spainsmp.yaml`.
4. Token de **Cloudflare** (Zone:Read + DNS:Edit en oxa.gg y spainsmp.com).

## Bootstrap (una sola vez)

```bash
export KUBECONFIG=/ruta/a/oxa-kubeconfig.yaml

# 1) Secrets (NO van en git) — copia los .example, rellénalos y aplícalos
kubectl create namespace external-dns
kubectl apply -f secrets/cloudflare-api-token.yaml
kubectl create namespace spainsmp
kubectl apply -f secrets/spainsmp-secrets.yaml
# (+ imagePullSecret ghcr, ver secrets/spainsmp-secrets.example.yaml)

# 2) Instalar ArgoCD (latest)
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --version 10.0.0 \
  -f bootstrap/argocd-values.yaml

# 3) Arrancar el App-of-Apps → Argo despliega traefik, external-dns y spainsmp
kubectl apply -f bootstrap/root-app.yaml
```

## Comprobar

```bash
kubectl -n argocd get applications        # root, traefik, external-dns, spainsmp → Synced/Healthy
kubectl -n traefik get svc                # IP del LoadBalancer
kubectl -n external-dns logs deploy/external-dns | grep -i cloudflare
kubectl -n spainsmp get pods,ingress

# Password inicial de la UI de Argo (usuario admin):
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
# UI: https://argo.int.oxa.gg  (una vez external-dns cree el registro), o port-forward:
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

## Estructura

| Ruta | Qué es |
|------|--------|
| `bootstrap/argocd-values.yaml` | Valores Helm de ArgoCD (Ingress Traefik, modo insecure tras TLS) |
| `bootstrap/root-app.yaml`      | Application raíz (App-of-Apps) → `apps/` |
| `apps/traefik.yaml`            | Application de Traefik |
| `apps/external-dns.yaml`       | Application de external-dns (Cloudflare) |
| `apps/spainsmp.yaml`           | Application de spainsmp (helm-spainsmp) |
| `secrets/*.example.yaml`       | Plantillas de secrets (los reales NO se versionan) |

## Notas

- **`policy: upsert-only`** en external-dns: nunca borra registros que no creó. Cámbialo a
  `sync` si quieres limpieza automática.
- **Traefik Service `LoadBalancer`**: si el cluster gestionado no provee LB, cambia a
  `ClusterIP`/`NodePort` en `apps/traefik.yaml`.
- Para versionar secretos de forma segura (GitOps puro), migrar a **Sealed Secrets** o **SOPS**.
