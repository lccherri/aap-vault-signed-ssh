# Status da POC

Rastreamento do escopo original definido para esta POC.

| # | Item | Status |
|---|---|---|
| 1 | Vault dev/lab configurado (CA, role, policy, AppRole) | Feito — `lab/ambiente.md` |
| 2 | Credenciais criadas no AAP e linkadas | Feito — `lab/aap-configuracao.md` |
| 3 | Fluxo validado ponta a ponta (manual + via AAP) | Feito — `lab/vm-rhel.md`, `lab/aap-configuracao.md` |
| 4 | Medir latencia de assinatura sob carga | Pendente |
| 5 | Comportamento com Vault indisponivel | Observado organicamente — pod `vault-0` reiniciou e ficou `Sealed`, job novo falhou com `503` no login AppRole antes de tentar SSH. Ver `lab/aap-configuracao.md` § Incidente |
| 6 | Segmentacao por Organization/tenant no Vault | Pendente |

## Observacao — pre-requisito de versao do OpenSSH

Fora do escopo desta POC, mas relevante para qualquer rollout: `TrustedUserCAKeys`
exige OpenSSH >= 6.9 (ver `docs/guia-configuracao.md` § Pre-requisitos). Hosts com
versoes anteriores nao suportam autenticacao via certificado e precisariam de
avaliacao/mitigacao separada antes da adocao deste modelo de credencial.

## Perguntas em aberto

- Topologia do Vault em producao (single node vs HA).
- Volume esperado de jobs concorrentes usando a credencial Vault, para dimensionar
  throughput.
