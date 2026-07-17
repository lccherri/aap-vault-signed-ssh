#!/usr/bin/env bash
# Cria a role de assinatura SSH e a policy de acesso minimo para o AAP.
# Pre-requisito: 01-enable-ssh-ca.sh ja executado.
set -euo pipefail

: "${VAULT_ADDR:?defina VAULT_ADDR}"

SSH_ROLE="${SSH_ROLE:-aap-role}"
ALLOWED_USERS="${ALLOWED_USERS:-ansible}"
TTL="${TTL:-30m0s}"
POLICY_NAME="${POLICY_NAME:-aap-ssh-signer}"

vault write "ssh/roles/${SSH_ROLE}" - <<EOH
{
  "algorithm_signer": "rsa-sha2-256",
  "allow_user_certificates": true,
  "allowed_users": "${ALLOWED_USERS}",
  "default_user": "${ALLOWED_USERS}",
  "key_type": "ca",
  "ttl": "${TTL}"
}
EOH

vault policy write "${POLICY_NAME}" - <<EOH
path "ssh/sign/${SSH_ROLE}" { capabilities = ["create","update"] }
path "ssh/config/ca"        { capabilities = ["read"] }
EOH

echo "Role '${SSH_ROLE}' (allowed_users=${ALLOWED_USERS}, ttl=${TTL}) e policy '${POLICY_NAME}' criadas."
