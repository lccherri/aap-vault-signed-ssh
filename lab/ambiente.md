# Ambiente de laboratório

Cluster de workshop usado para validar a POC. Levantamento de 2026-07-17.

## Cluster OpenShift

- API: `https://api.cluster-gxt8z.dyn.redhatworkshops.io:6443`
- Certificado autoassinado: usar `--insecure-skip-tls-verify` (oc) ou `-k` (curl).
- Token de login é pessoal/temporário do workshop — não versionar.

## AAP (namespace `aap`)

- Operator `aap-operator.v2.7.0`, CR `AnsibleAutomationPlatform/example`.
- Gateway/UI: `https://example-aap.apps.cluster-gxt8z.dyn.redhatworkshops.io`.
- Login: usuário `admin`, senha em `oc extract secret/example-admin-password -n aap --to=-`.
- Automation Hub (`example-hub-*`) fica em `Pending` por falta de PVC disponível na
  storage class default. Não afeta Controller/Gateway, únicos componentes usados
  nesta POC.

## Vault (namespace `vault`)

- Instalado via Helm chart oficial HashiCorp (`vault-0.34.0`), modo standalone,
  storage `file`, TLS terminado no listener interno (`tls_disable=1`).
- Chart não cria Route por padrão. Criada manualmente:
  ```bash
  oc create route edge vault --service=vault --port=8200 -n vault
  ```
  Resultado: `https://vault-vault.apps.cluster-gxt8z.dyn.redhatworkshops.io`.
- Inicialização (única vez, bootstrap de plataforma):
  ```bash
  oc exec vault-0 -n vault -- vault operator init -key-shares=5 -key-threshold=3
  ```
  Unseal keys e root token em `out/vault-init.json` (não versionado).
- Sem HA/auto-unseal: se o pod `vault-0` reiniciar, o Vault volta `Sealed` e precisa
  ser destravado de novo. Reproduz o risco de SPOF do Vault em produção (ver
  `lab/aap-configuracao.md` § Incidente). Já ocorreu mais de uma vez neste lab —
  destravar com `out/unseal.sh` (usa o CLI local + as chaves em
  `out/vault-init.json`).
- Vault CLI instalado localmente (fora do OpenShift). SSH Secrets Engine, role,
  policy e AppRole configurados a partir dele, conforme `docs/guia-configuracao.md`
  — não pelo `oc exec` no pod. A inicialização (`vault operator init`), por ser
  bootstrap de plataforma, foi feita uma única vez via `oc exec`.
- Artefatos gerados: `out/trusted-user-ca-keys.pem` (chave pública da CA),
  `out/approle-creds.env` (ROLE_ID/SECRET_ID do AppRole `aap-controller`).

## Storage

- StorageClass default: `ocs-external-storagecluster-ceph-rbd` (`WaitForFirstConsumer`).
- Alternativa com binding imediato: `ocs-external-storagecluster-ceph-rbd-immediate`.
