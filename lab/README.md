# Ambiente de laboratório

Registro do ambiente usado para validar esta POC. Não faz parte da solução em si
— ver `docs/guia-configuracao.md` para o passo a passo genérico.

| Arquivo | Conteúdo |
|---|---|
| `ambiente.md` | Acesso ao cluster, AAP e Vault usados no lab |
| `vm-rhel.md` | VM RHEL de teste: acesso e configuração aplicada |
| `aap-configuracao.md` | Credenciais e objetos criados no AAP deste lab, com IDs |
| `plano-execucao.md` | Status de cada item do escopo da POC |
| `deploy-vault-dev.sh` | Script de referência para subir um Vault em modo dev (não usado neste lab) |
| `unseal.sh` | Destrava o Vault deste lab usando o CLI local e as chaves em `out/vault-init.json` |
