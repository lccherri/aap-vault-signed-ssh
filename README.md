# POC: SSH assinado via HashiCorp Vault + AAP

Substitui chave SSH estática de longa duração por certificados de curta duração
(30 min), assinados sob demanda pelo Vault a cada execução de job no AAP.

## Como funciona

```mermaid
sequenceDiagram
    participant Op as Operador
    participant AAP as AAP (Job Template)
    participant Vault as HashiCorp Vault
    participant Host as Host gerenciado (sshd)

    Op->>AAP: Launch Job Template
    AAP->>Vault: POST auth/approle/login (role_id + secret_id)
    Vault-->>AAP: token de acesso (AppRole)
    AAP->>Vault: POST ssh/sign/aap-role (chave publica estatica + valid_principals)
    Vault-->>AAP: certificado assinado (TTL 30 min)
    Note over AAP: identidade da sessao = chave privada estatica + certificado novo
    AAP->>Host: conexao SSH com chave + certificado
    Host->>Host: valida certificado contra TrustedUserCAKeys (offline, sem chamar o Vault)
    Host-->>AAP: sessao autenticada (principal = usuario)
    AAP->>Host: executa o playbook
    Note over Vault,Host: certificado expira em 30 min - nenhuma chave de longa duracao envolvida
```

A chave privada usada pelo AAP é estática (gerada uma vez), mas sozinha não abre
sessão em lugar nenhum — o host só confia em conexões acompanhadas de um
certificado válido assinado pela CA do Vault. Como o certificado expira em 30
minutos, uma credencial vazada perde valor rapidamente sem precisar de revogação
manual.

## Estrutura

| Caminho | Conteúdo |
|---|---|
| [`docs/guia-configuracao.md`](docs/guia-configuracao.md) | Passo a passo de configuração — Vault, AAP, host gerenciado |
| [`playbooks/demo.yml`](playbooks/demo.yml) | Playbook de demonstração usado no Job Template do AAP |
| [`scripts/vault/`](scripts/vault/) | Scripts que automatizam a configuração do Vault (CA, role, policy, AppRole) |
| `lab/` | Notas do ambiente de laboratório usado para validar esta POC (não faz parte da solução) |

## Referência

https://www.hashicorp.com/en/blog/managing-ansible-automation-platform-aap-credentials-at-scale-with-vault
