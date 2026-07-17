# POC: SSH assinado via HashiCorp Vault + AAP

## Objetivo
Substituir chave SSH estática única (usada hoje para todo o inventário) por
certificados SSH de curta duração assinados dinamicamente pelo Vault SSH
Secrets Engine, via credential plugin nativo do AAP.

## Contexto do ambiente
- AAP rodando em OpenShift, com Container Groups e Execution Environments (EEs).
- Inventário heterogêneo: hosts modernos + hosts legados RHEL 5/6 (Python 2.6).
- Migração em andamento AWX → AAP.
- Cliente já possui HashiCorp Vault disponível (precisa confirmar se é
  instância única ou cluster HA — ponto em aberto, ver seção "Riscos").
- Uso de Constructed Inventories para segmentação lógica do inventário
  (não Smart Inventories, que são deprecated).

## Decisão de arquitetura
Usar o tipo de credencial nativo **"HashiCorp Vault Signed SSH"** do AAP,
que implementa o fluxo de CA (host confia na CA do Vault via
`TrustedUserCAKeys`, não em uma chave estática compartilhada).

Ponto-chave de escala: a requisição de assinatura ao Vault ocorre
**uma vez por execução de job** (não uma vez por host). O AAP gera um
par de chaves local para a sessão e pede a assinatura de uma vez;
o certificado resultante autentica contra todos os hosts do job.

## Passo a passo — lado Vault

```bash
# 1. Habilitar o SSH secrets engine como CA
vault secrets enable -path=ssh ssh
vault write ssh/config/ca generate_signing_key=true

# 2. Extrair a chave pública da CA (vai para os hosts gerenciados)
vault read -field=public_key ssh/config/ca > trusted-user-ca-keys.pem

# 3. Criar a role de assinatura (ajustar allowed_users ao usuário real
#    de automação, evitar "*" em produção)
vault write ssh/roles/aap-role -<<EOH
{
  "algorithm_signer": "rsa-sha2-256",
  "allow_user_certificates": true,
  "allowed_users": "ansible",
  "default_user": "ansible",
  "key_type": "ca",
  "ttl": "30m0s"
}
EOH

# 4. Policy de acesso mínimo para o AAP
vault policy write aap-ssh-signer - <<EOH
path "ssh/sign/aap-role" { capabilities = ["create","update"] }
path "ssh/config/ca"     { capabilities = ["read"] }
EOH

# 5. AppRole para autenticação do AAP no Vault
vault auth enable approle
vault write auth/approle/role/aap-controller \
  token_policies="aap-ssh-signer" \
  token_ttl=1h token_max_ttl=4h

vault read auth/approle/role/aap-controller/role-id
vault write -f auth/approle/role/aap-controller/secret-id
```

Nos hosts gerenciados (via playbook/golden image):
```
# /etc/ssh/sshd_config
TrustedUserCAKeys /etc/ssh/trusted-user-ca-keys.pem
```
seguido de restart do `sshd`.

## Passo a passo — lado AAP

1. **Credentials → Add** → tipo **HashiCorp Vault Signed SSH**
   - Server URL, Approle Role_ID, Approle Secret_ID, Path to Approle Auth,
     CA Certificate (se TLS com CA própria).
2. **Credentials → Add** → tipo **Machine**
   - Username = usuário SSH alvo (ex: `ansible`)
   - No campo SSH Private Key, usar o ícone de link para linkar como
     "Input Source" apontando para a credencial Vault criada no passo 1
   - Preencher Path to Secret (`ssh`), Role Name (`aap-role`),
     Valid Principals
   - Clicar **Test** antes de salvar
3. Associar a Machine Credential ao Job Template normalmente.

## Riscos e mitigação (SPOF do Vault)

- Jobs **em execução** não são afetados por queda do Vault (cert já emitido,
  host valida offline contra a CA).
- Jobs **novos** falham no pre-start check se o Vault estiver indisponível
  no momento do lookup (erro de credential lookup, não chega a tentar SSH).
- Mitigação lado Vault: cluster HA (Raft, 3 ou 5 nós), auto-unseal via KMS,
  monitoramento de `sys/health`.
- Mitigação lado operação: credencial estática de emergência ("break-glass"),
  escopo restrito, uso audit·ado, não usada em operação normal.
- **Em aberto**: confirmar com o cliente se o Vault atual já é HA ou
  instância única — decide a urgência de endereçar esse ponto antes do
  rollout amplo.

## Escopo sugerido para a POC
1. Validar o fluxo completo em Vault dev/lab + 1-2 hosts de teste
   (não legados ainda).
2. Medir latência de assinatura e confirmar comportamento de erro quando
   o Vault está indisponível (para validar a análise de impacto acima).
3. Validar se o fluxo funciona sem alteração nos hosts Python 2.6/RHEL 5-6
   legados (o `sshd` neles pode não suportar certificados CA — **checar
   versão mínima do OpenSSH que suporta `TrustedUserCAKeys`**, pode ser
   um bloqueador para a parte legada do inventário).
4. Testar segmentação por Organization/tenant no Vault, alinhado ao
   padrão de tenancy validado pela HashiCorp (mapear Organization do AAP
   para role/policy dedicada no Vault).

## Perguntas em aberto para a próxima sessão
- Topologia atual do Vault do cliente (single node vs HA)?
- Versão do OpenSSH nos hosts RHEL 5/6 legados — suporta certificados CA?
- Qual o volume esperado de jobs concorrentes usando essa credencial
  (para dimensionar throughput do Vault)?
