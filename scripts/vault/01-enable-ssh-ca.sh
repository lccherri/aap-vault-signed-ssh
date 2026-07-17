#!/usr/bin/env bash
# Habilita o SSH Secrets Engine e gera a CA de assinatura.
# Requer VAULT_ADDR e VAULT_TOKEN exportados com permissao de admin no Vault.
set -euo pipefail

: "${VAULT_ADDR:?defina VAULT_ADDR, ex: export VAULT_ADDR=https://vault.exemplo.com}"

OUT_FILE="${OUT_FILE:-$(dirname "$0")/../../out/trusted-user-ca-keys.pem}"
mkdir -p "$(dirname "$OUT_FILE")"

vault secrets enable -path=ssh ssh || true
vault write ssh/config/ca generate_signing_key=true

vault read -field=public_key ssh/config/ca > "$OUT_FILE"
echo "Chave publica da CA: $OUT_FILE"
echo "Copiar para /etc/ssh/trusted-user-ca-keys.pem em cada host gerenciado."
