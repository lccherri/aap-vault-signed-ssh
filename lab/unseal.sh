#!/usr/bin/env bash
# Destrava o Vault deste lab usando o CLI local, via rota externa.
# Le as unseal keys de out/vault-init.json (gerado no vault operator init).
set -euo pipefail

export VAULT_ADDR="${VAULT_ADDR:-https://vault-vault.apps.cluster-gxt8z.dyn.redhatworkshops.io}"
export VAULT_SKIP_VERIFY=true

INIT_FILE="$(dirname "$0")/../out/vault-init.json"

for i in 0 1 2; do
  KEY=$(python3 -c "import json;print(json.load(open('$INIT_FILE'))['unseal_keys_b64'][$i])")
  vault operator unseal "$KEY" >/dev/null
done

vault status
