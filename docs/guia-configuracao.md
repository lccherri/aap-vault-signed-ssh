# Guia de configuração: SSH assinado via HashiCorp Vault no AAP

Passo a passo para reproduzir o modelo de credencial em qualquer ambiente com Vault
e AAP. Baseado em:
https://www.hashicorp.com/en/blog/managing-ansible-automation-platform-aap-credentials-at-scale-with-vault

Substitua os valores de exemplo (URLs, nomes de role/policy, usuário) pelos do
ambiente de destino.

## Pré-requisitos

- Vault acessível via HTTPS a partir do AAP, com permissão para habilitar um
  secrets engine e um auth method.
- AAP 2.x (o credential type "HashiCorp Vault Signed SSH" já vem incluído).
- Host gerenciado com OpenSSH com suporte a `TrustedUserCAKeys` (OpenSSH >= 6.9,
  disponível desde RHEL 7.x).
- Vault CLI instalado na estação de onde a configuração será feita:
  https://developer.hashicorp.com/vault/install

## Onde executar os comandos

Os comandos `vault` dos passos 1-4 rodam a partir de uma estação de trabalho com o
Vault CLI instalado — não dentro do AAP, nem dentro da plataforma (Kubernetes/
OpenShift/VM) que hospeda o servidor Vault. Essa estação só precisa de rede até o
Vault e de um token com permissão administrativa:

```bash
export VAULT_ADDR=https://vault.exemplo.com
export VAULT_TOKEN=<token com permissao de admin>
vault status
```

Isso mantém a responsabilidade de cada componente separada: quem administra o
Vault configura a CA, a role, a policy e o AppRole a partir do próprio Vault CLI;
o AAP só consome essas credenciais através do credential plugin, sem acesso
administrativo ao Vault; a plataforma que hospeda o Vault (OpenShift, neste
laboratório) é responsável apenas por manter o serviço no ar.

## 1. Vault — habilitar o SSH Secrets Engine e gerar a CA

Transforma o Vault em uma autoridade certificadora (CA) de SSH. A chave gerada aqui
é o que os hosts gerenciados vão passar a confiar, no lugar de uma chave estática —
por isso a chave pública precisa ser distribuída a cada host (passo 5).

```bash
vault secrets enable -path=ssh ssh
vault write ssh/config/ca generate_signing_key=true
vault read -field=public_key ssh/config/ca > trusted-user-ca-keys.pem
```

Distribuir `trusted-user-ca-keys.pem` para `/etc/ssh/trusted-user-ca-keys.pem` em
cada host gerenciado (via playbook ou golden image).

## 2. Vault — role de assinatura

Define as regras que a CA aplica sempre que assina um certificado por essa role:
para quais usuários, por quanto tempo (`ttl`) e com qual algoritmo. Qualquer
certificado emitido fora desses limites é rejeitado pelo Vault.

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
corresponder ao usuário configurado na credencial Machine do AAP (passo 7).

## 3. Vault — policy de acesso mínimo

Controla o que a identidade do AAP pode fazer dentro do Vault — não se confunde com
a role do passo 2, que controla o que um certificado pode conter. Aqui restringimos
o AAP a apenas pedir assinaturas pela role `aap-role` e ler a CA, nada além disso.

```bash
vault policy write aap-ssh-signer - <<EOF
path "ssh/sign/aap-role" { capabilities = ["create","update"] }
path "ssh/config/ca"     { capabilities = ["read"] }
EOF
```

## 4. Vault — AppRole para o AAP autenticar

Cria a identidade de máquina que o AAP vai usar para se autenticar no Vault e
receber um token com a policy do passo 3 — sem depender de um usuário humano nem de
uma senha fixa. `role_id` funciona como identificador, `secret_id` como segredo.

```bash
vault auth enable approle

vault write auth/approle/role/aap-controller \
  token_policies="aap-ssh-signer" \
  token_ttl=1h token_max_ttl=4h

vault read -field=role_id auth/approle/role/aap-controller/role-id
vault write -f -field=secret_id auth/approle/role/aap-controller/secret-id
```

`role_id` é um identificador fixo do AppRole — `read` só consulta o valor já
existente, sem alterar nada. `secret_id` é gerado sob demanda a cada chamada —
`write` dispara a criação de um novo, com seu próprio TTL/número de usos; o `-f`
indica que a chamada não precisa de dados de entrada. Rodar o `write` de novo gera
um `secret_id` diferente a cada vez.

Guardar `role_id` e `secret_id` — vão para a credencial do AAP no passo 6.

Scripts equivalentes aos passos 1-4: [`scripts/vault/`](../scripts/vault/).

## 5. Host gerenciado — confiar na CA

Copiar o arquivo gerado no passo 1 para o host e aplicar a configuração:

```bash
scp trusted-user-ca-keys.pem <usuario>@<host>:/tmp/trusted-user-ca-keys.pem

ssh <usuario>@<host> <<'EOF'
sudo mv /tmp/trusted-user-ca-keys.pem /etc/ssh/trusted-user-ca-keys.pem
sudo chown root:root /etc/ssh/trusted-user-ca-keys.pem
sudo chmod 644 /etc/ssh/trusted-user-ca-keys.pem
# Em hosts com SELinux (RHEL e derivados): sem isso o arquivo fica com o
# contexto herdado de /tmp e o sshd, confinado, nao consegue le-lo — a
# autenticacao por certificado falha silenciosamente. Nao se aplica a
# distros sem SELinux.
sudo restorecon -v /etc/ssh/trusted-user-ca-keys.pem
sudo useradd -m -s /bin/bash ansible || true
echo 'TrustedUserCAKeys /etc/ssh/trusted-user-ca-keys.pem' \
  | sudo tee /etc/ssh/sshd_config.d/60-vault-ssh-ca.conf
sudo systemctl restart sshd
EOF
```

`ansible` no `useradd` deve ser o mesmo valor de `allowed_users`/`default_user`
definido no passo 2.

Em escala, substituir esses dois comandos por um playbook/golden image, já que todo
host gerenciado precisa da mesma CA.

## 6. AAP — credencial "HashiCorp Vault Signed SSH"

Guarda apenas como o AAP se autentica no Vault (URL + AppRole). Sozinha, não loga em
nenhum host — é uma credencial do tipo "external"/lookup, usada por referência no
passo 7.

**Credentials → Add**, tipo **HashiCorp Vault Signed SSH**.

| Campo | Valor |
|---|---|
| Server URL | URL do Vault |
| AppRole role_id | `role_id` do passo 4 |
| AppRole secret_id | `secret_id` do passo 4 |
| Path to Auth | `approle` |

## 7. AAP — credencial "Machine"

Esta é a credencial que efetivamente faz SSH (username + chave privada). O campo
"Signed SSH Certificate" é linkado à credencial do passo 6 em vez de receber um valor
fixo: a cada execução de job, o AAP autentica no Vault via AppRole e pede um
certificado novo, assinando a chave pública estática gerada abaixo. O certificado
retornado (TTL de 30 min) vale só para aquela execução e nunca fica salvo.

Gerar um par de chaves estático (uma vez, fora do AAP):

```bash
ssh-keygen -t rsa -b 2048 -f aap-machine-key -N ""
```

**Credentials → Add**, tipo **Machine**:

| Campo | Valor |
|---|---|
| Username | `ansible` (mesmo valor de `allowed_users` no passo 2) |
| SSH Private Key | conteúdo de `aap-machine-key` |

No campo **Signed SSH Certificate**, clicar no ícone de link e selecionar a
credencial criada no passo 6 como Input Source. Preencher:

| Campo (metadata) | Valor |
|---|---|
| Unsigned Public Key | conteúdo de `aap-machine-key.pub` |
| Path to Secret | `ssh` |
| Role Name | `aap-role` |
| Valid Principals | `ansible` |

Clicar **Test** — deve retornar sucesso antes de salvar.

Não linkar o campo "SSH Private Key" ao Vault: ele permanece com o valor estático
colado acima. O campo linkado é o "Signed SSH Certificate" — é o que muda a cada
execução de job, com um certificado novo emitido pelo Vault e validade de 30
minutos (TTL definido no passo 2).

## 8. AAP — Project e Job Template de demonstração

1. **Projects → Add**: SCM Type = Git, URL do repositório deste projeto.
2. **Templates → Add Job Template**:
   - Inventory: inventário com o(s) host(s) de teste.
   - Project: o project criado acima.
   - Playbook: `playbooks/demo.yml`.
   - Credentials: a credencial Machine criada no passo 7.
3. **Launch**. O job busca um certificado novo no Vault, conecta ao host via
   certificado e grava `/tmp/aap-vault-demo.txt` no destino.

## Verificação

No host de destino, o login autenticado por certificado aparece no log do sshd:

```bash
journalctl -u sshd | grep RSA-CERT
```

A linha mostra `RSA-CERT`, o `Key ID` gerado pelo Vault e a impressão digital da
CA — confirma que a autenticação usou o certificado, não uma chave estática.
