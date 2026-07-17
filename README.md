# POC: SSH assinado via HashiCorp Vault + AAP

Substitui chave SSH estatica de longa duracao por certificados de curta duracao
(30 min), assinados sob demanda pelo Vault a cada execucao de job no AAP.

## Estrutura

| Caminho | Conteudo |
|---|---|
| [`docs/guia-configuracao.md`](docs/guia-configuracao.md) | Passo a passo de configuracao — Vault, AAP, host gerenciado |
| [`docs/POC-vault-ssh-aap-contexto.md`](docs/POC-vault-ssh-aap-contexto.md) | Escopo e decisao de arquitetura originais |
| [`playbooks/demo.yml`](playbooks/demo.yml) | Playbook de demonstracao usado no Job Template do AAP |
| [`scripts/vault/`](scripts/vault/) | Scripts que automatizam a configuracao do Vault (CA, role, policy, AppRole) |
| `lab/` | Notas do ambiente de laboratorio usado para validar esta POC (nao faz parte da solucao) |

## Referencia

https://www.hashicorp.com/en/blog/managing-ansible-automation-platform-aap-credentials-at-scale-with-vault

## `out/`

Segredos gerados durante a configuracao do ambiente de lab (chaves, tokens,
credenciais). Nao versionado.
