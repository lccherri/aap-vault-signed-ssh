#!/usr/bin/env bash
# Deploy de referencia de um Vault em modo dev (in-memory, auto-unsealed, token
# root fixo). Nao usar em producao. Nao utilizado neste ambiente de lab, que ja
# tem Vault instalado em modo standalone com storage em disco.
set -euo pipefail

NAMESPACE="${NAMESPACE:-vault}"
RELEASE="${RELEASE:-vault}"

helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null 2>&1 || true
helm repo update hashicorp

helm upgrade --install "$RELEASE" hashicorp/vault \
  --namespace "$NAMESPACE" \
  --set server.dev.enabled=true \
  --set injector.enabled=false \
  --set server.route.enabled=true \
  --set server.route.host="vault-${NAMESPACE}.$(oc whoami --show-server 2>/dev/null | sed -E 's#https://api\.##; s#:6443##; s#^#apps.#')"

echo "Aguardando pod do Vault ficar pronto..."
oc rollout status statefulset/"$RELEASE" -n "$NAMESPACE" --timeout=180s

echo "Pod:"
oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=vault

echo
echo "Para expor a rota (se server.route.enabled não criar automaticamente):"
echo "  oc expose svc/${RELEASE} --port=8200 -n ${NAMESPACE}"
echo
echo "Root token do modo dev: 'root' (fixo, apenas para lab)."
