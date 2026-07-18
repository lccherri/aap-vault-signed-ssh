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
- Vault CLI instalado na estacao de onde a configuracao sera feita:
  https://developer.hashicorp.com/vault/install

## Onde executar os comandos

Os comandos `vault` dos passos 1-4 rodam a partir de uma estacao de trabalho com o
Vault CLI instalado — nao dentro do AAP, nem dentro da plataforma (Kubernetes/
OpenShift/VM) que hospeda o servidor Vault. Essa estacao so precisa de rede ate o
Vault e de um token com permissao administrativa:

```bash
export VAULT_ADDR=https://vault.exemplo.com
export VAULT_TOKEN=<token com permissao de admin>
vault status
```

Isso mantem a responsabilidade de cada componente separada: quem administra o
Vault configura a CA, a role, a policy e o AppRole a partir do proprio Vault CLI;
o AAP so consome essas credenciais atraves do credential plugin, sem acesso
administrativo ao Vault; a plataforma que hospeda o Vault (OpenShift, neste
laboratorio) e responsavel apenas por manter o servico no ar.

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

`role_id` e um identificador fixo do AppRole — `read` so consulta o valor ja
existente, sem alterar nada. `secret_id` e gerado sob demanda a cada chamada —
`write` dispara a criacao de um novo, com seu proprio TTL/numero de usos; o `-f`
indica que a chamada nao precisa de dados de entrada. Rodar o `write` de novo gera
um `secret_id` diferente a cada vez.

Guardar `role_id` e `secret_id` — vao para a credencial do AAP no passo 6.

Scripts equivalentes aos passos 1-4: [`scripts/vault/`](../scripts/vault/).

## 5. Host gerenciado — confiar na CA

Copiar o arquivo gerado no passo 1 para o host e aplicar a configuracao:

```bash
scp trusted-user-ca-keys.pem <usuario>@<host>:/tmp/trusted-user-ca-keys.pem

ssh <usuario>@<host> <<'EOF'
sudo mv /tmp/trusted-user-ca-keys.pem /etc/ssh/trusted-user-ca-keys.pem
sudo chown root:root /etc/ssh/trusted-user-ca-keys.pem
sudo chmod 644 /etc/ssh/trusted-user-ca-keys.pem
echo 'TrustedUserCAKeys /etc/ssh/trusted-user-ca-keys.pem' \
  | sudo tee /etc/ssh/sshd_config.d/60-vault-ssh-ca.conf
sudo systemctl restart sshd
EOF
```

Em escala, substituir esses dois comandos por um playbook/golden image, ja que todo
host gerenciado precisa da mesma CA.

Criar/garantir que o usuario definido em `allowed_users` (passo 2) existe no host.

## 6. AAP — credencial "HashiCorp Vault Signed SSH"

Guarda apenas como o AAP se autentica no Vault (URL + AppRole). Sozinha, nao loga em
nenhum host — e uma credencial do tipo "external"/lookup, usada por referencia no
passo 7.

**Credentials → Add**, tipo **HashiCorp Vault Signed SSH**.

| Campo | Valor |
|---|---|
| Server URL | URL do Vault |
| AppRole role_id | `role_id` do passo 4 |
| AppRole secret_id | `secret_id` do passo 4 |
| Path to Auth | `approle` |

## 7. AAP — credencial "Machine"

Esta e a credencial que efetivamente faz SSH (username + chave privada). O campo
"Signed SSH Certificate" e linkado a credencial do passo 6 em vez de receber um valor
fixo: a cada execucao de job, o AAP autentica no Vault via AppRole e pede um
certificado novo, assinando a chave publica estatica gerada abaixo. O certificado
retornado (TTL de 30 min) vale so para aquela execucao e nunca fica salvo.

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
