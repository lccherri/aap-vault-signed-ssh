#!/usr/bin/env bash
# Cria o AppRole que o AAP usara para autenticar no Vault.
# Pre-requisito: 02-role-policy.sh ja executado (policy referenciada precisa existir).
set -euo pipefail

: "${VAULT_ADDR:?defina VAULT_ADDR}"

APPROLE_NAME="${APPROLE_NAME:-aap-controller}"
POLICY_NAME="${POLICY_NAME:-aap-ssh-signer}"

vault auth enable approle || true

vault write "auth/approle/role/${APPROLE_NAME}" \
  token_policies="${POLICY_NAME}" \
  token_ttl=1h token_max_ttl=4h

ROLE_ID=$(vault read -field=role_id "auth/approle/role/${APPROLE_NAME}/role-id")
SECRET_ID=$(vault write -f -field=secret_id "auth/approle/role/${APPROLE_NAME}/secret-id")

OUT_FILE="${OUT_FILE:-$(dirname "$0")/../../out/approle-creds.env}"
mkdir -p "$(dirname "$OUT_FILE")"
cat > "$OUT_FILE" <<EOF
# Usar em Role_ID / Secret_ID na credencial "HashiCorp Vault Signed SSH" do AAP.
ROLE_ID=${ROLE_ID}
SECRET_ID=${SECRET_ID}
EOF

echo "AppRole '${APPROLE_NAME}' criado. Role ID e Secret ID salvos em: $OUT_FILE"
