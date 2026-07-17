# Status da POC

Rastreamento do escopo definido em `docs/POC-vault-ssh-aap-contexto.md` § "Escopo
sugerido para a POC".

| # | Item | Status |
|---|---|---|
| 1 | Vault dev/lab configurado (CA, role, policy, AppRole) | Feito — `lab/ambiente.md` |
| 2 | Credenciais criadas no AAP e linkadas | Feito — `lab/aap-configuracao.md` |
| 3 | Fluxo validado ponta a ponta (manual + via AAP) | Feito — `lab/vm-rhel.md`, `lab/aap-configuracao.md` |
| 4 | Medir latencia de assinatura sob carga | Pendente |
| 5 | Comportamento com Vault indisponivel | Pendente — simular escalando `vault-0` para 0 replicas |
| 6 | Versao minima de OpenSSH para hosts legados RHEL 5/6 | Pendente — pesquisa documental |
| 7 | Segmentacao por Organization/tenant no Vault | Pendente |

## Perguntas em aberto para o cliente

- Topologia atual do Vault em producao (single node vs HA).
- Versao do OpenSSH nos hosts RHEL 5/6 legados.
- Volume esperado de jobs concorrentes usando a credencial Vault, para dimensionar
  throughput.
