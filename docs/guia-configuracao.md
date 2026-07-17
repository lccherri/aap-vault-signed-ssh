# Guia de configuracao: SSH assinado via HashiCorp Vault no AAP

Passo a passo para reproduzir o modelo de credencial em qualquer ambiente com Vault
e AAP. Baseado em:
https://www.hashicorp.com/en/blog/managing-ansible-automation-platform-aap-credentials-at-scale-with-vault

Substitua os valores de exemplo (URLs, nomes de role/policy, usuario) pelos do
ambiente de destino.

## Pre-requisitos

- Vault acessivel via HTTPS a partir do AAP, com permissao para habilitar um
  secrets engine e um auth method.
- AAP 2.x (o credential type "HashiCorp Vault Signed SSH" ja vem incluido).
- Host gerenciado com OpenSSH com suporte a `TrustedUserCAKeys` (OpenSSH >= 6.9,
  disponivel desde RHEL 7.x).

## 1. Vault — habilitar o SSH Secrets Engine e gerar a CA

```bash
vault secrets enable -path=ssh ssh
vault write ssh/config/ca generate_signing_key=true
vault read -field=public_key ssh/config/ca > trusted-user-ca-keys.pem
```

Distribuir `trusted-user-ca-keys.pem` para `/etc/ssh/trusted-user-ca-keys.pem` em
cada host gerenciado (via playbook ou golden image).

## 2. Vault — role de assinatura

```bash
vault write ssh/roles/aap-role - <<EOF
{
  "algorithm_signer": "rsa-sha2-256",
  "allow_user_certificates": true,
  "allowed_users": "ansible",
  "default_user": "ansible",
  "key_type": "ca",
  "ttl": "30m0s"
}
EOF
```

`allowed_users` define quais usernames podem receber certificado assinado. Deve
corresponder ao usuario configurado na credencial Machine do AAP (passo 7).

## 3. Vault — policy de acesso minimo

```bash
vault policy write aap-ssh-signer - <<EOF
path "ssh/sign/aap-role" { capabilities = ["create","update"] }
path "ssh/config/ca"     { capabilities = ["read"] }
EOF
```

## 4. Vault — AppRole para o AAP autenticar

```bash
vault auth enable approle

vault write auth/approle/role/aap-controller \
  token_policies="aap-ssh-signer" \
  token_ttl=1h token_max_ttl=4h

vault read -field=role_id auth/approle/role/aap-controller/role-id
vault write -f -field=secret_id auth/approle/role/aap-controller/secret-id
```

Guardar `role_id` e `secret_id` — vao para a credencial do AAP no passo 6.

Scripts equivalentes aos passos 1-4: [`scripts/vault/`](../scripts/vault/).

## 5. Host gerenciado — confiar na CA

```bash
# copiar trusted-user-ca-keys.pem para /etc/ssh/trusted-user-ca-keys.pem
echo 'TrustedUserCAKeys /etc/ssh/trusted-user-ca-keys.pem' \
  > /etc/ssh/sshd_config.d/60-vault-ssh-ca.conf
systemctl restart sshd
```

Criar/garantir que o usuario definido em `allowed_users` (passo 2) existe no host.

## 6. AAP — credencial "HashiCorp Vault Signed SSH"

**Credentials → Add**, tipo **HashiCorp Vault Signed SSH**.

| Campo | Valor |
|---|---|
| Server URL | URL do Vault |
| AppRole role_id | `role_id` do passo 4 |
| AppRole secret_id | `secret_id` do passo 4 |
| Path to Auth | `approle` |

## 7. AAP — credencial "Machine"

Gerar um par de chaves estatico (uma vez, fora do AAP):

```bash
ssh-keygen -t rsa -b 2048 -f aap-machine-key -N ""
```

**Credentials → Add**, tipo **Machine**:

| Campo | Valor |
|---|---|
| Username | `ansible` (mesmo valor de `allowed_users` no passo 2) |
| SSH Private Key | conteudo de `aap-machine-key` |

No campo **Signed SSH Certificate**, clicar no icone de link e selecionar a
credencial criada no passo 6 como Input Source. Preencher:

| Campo (metadata) | Valor |
|---|---|
| Unsigned Public Key | conteudo de `aap-machine-key.pub` |
| Path to Secret | `ssh` |
| Role Name | `aap-role` |
| Valid Principals | `ansible` |

Clicar **Test** — deve retornar sucesso antes de salvar.

Nao linkar o campo "SSH Private Key" ao Vault: ele permanece com o valor estatico
colado acima. O campo linkado e o "Signed SSH Certificate" — e o que muda a cada
execucao de job, com um certificado novo emitido pelo Vault e validade de 30
minutos (TTL definido no passo 2).

## 8. AAP — Project e Job Template de demonstracao

1. **Projects → Add**: SCM Type = Git, URL do repositorio deste projeto.
2. **Templates → Add Job Template**:
   - Inventory: inventario com o(s) host(s) de teste.
   - Project: o project criado acima.
   - Playbook: `playbooks/demo.yml`.
   - Credentials: a credencial Machine criada no passo 7.
3. **Launch**. O job busca um certificado novo no Vault, conecta ao host via
   certificado e grava `/tmp/aap-vault-demo.txt` no destino.

## Verificacao

No host de destino, o login autenticado por certificado aparece no log do sshd:

```bash
journalctl -u sshd | grep RSA-CERT
```

A linha mostra `RSA-CERT`, o `Key ID` gerado pelo Vault e a impressao digital da
CA — confirma que a autenticacao usou o certificado, nao uma chave estatica.
