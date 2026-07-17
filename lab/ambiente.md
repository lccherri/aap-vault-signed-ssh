# Ambiente de laboratorio

Cluster de workshop usado para validar a POC. Levantamento de 2026-07-17.

## Cluster OpenShift

- API: `https://api.cluster-gxt8z.dyn.redhatworkshops.io:6443`
- Certificado autoassinado: usar `--insecure-skip-tls-verify` (oc) ou `-k` (curl).
- Token de login e pessoal/temporario do workshop — nao versionar.

## AAP (namespace `aap`)

- Operator `aap-operator.v2.7.0`, CR `AnsibleAutomationPlatform/example`.
- Gateway/UI: `https://example-aap.apps.cluster-gxt8z.dyn.redhatworkshops.io`.
- Login: usuario `admin`, senha em `oc extract secret/example-admin-password -n aap --to=-`.
- Automation Hub (`example-hub-*`) fica em `Pending` por falta de PVC disponivel na
  storage class default. Nao afeta Controller/Gateway, unicos componentes usados
  nesta POC.

## Vault (namespace `vault`)

- Instalado via Helm chart oficial HashiCorp (`vault-0.34.0`), modo standalone,
  storage `file`, TLS terminado no listener interno (`tls_disable=1`).
- Chart nao cria Route por padrao. Criada manualmente:
  ```bash
  oc create route edge vault --service=vault --port=8200 -n vault
  ```
  Resultado: `https://vault-vault.apps.cluster-gxt8z.dyn.redhatworkshops.io`.
- Inicializacao (unica vez):
  ```bash
  oc exec vault-0 -n vault -- vault operator init -key-shares=5 -key-threshold=3
  oc exec vault-0 -n vault -- vault operator unseal <key1>
  oc exec vault-0 -n vault -- vault operator unseal <key2>
  oc exec vault-0 -n vault -- vault operator unseal <key3>
  ```
  Unseal keys e root token em `out/vault-init.json` (nao versionado).
- Sem HA/auto-unseal: se o pod `vault-0` reiniciar, o Vault volta `Sealed` e precisa
  ser destravado de novo com as chaves em `out/vault-init.json`. Reproduz o risco de
  SPOF descrito em `docs/POC-vault-ssh-aap-contexto.md`.
- SSH Secrets Engine, role, policy e AppRole configurados conforme
  `docs/guia-configuracao.md`, executado via `oc exec vault-0 -- vault ...` (sem
  `vault` CLI instalado localmente neste lab).
- Artefatos gerados: `out/trusted-user-ca-keys.pem` (chave publica da CA),
  `out/approle-creds.env` (ROLE_ID/SECRET_ID do AppRole `aap-controller`).

## Storage

- StorageClass default: `ocs-external-storagecluster-ceph-rbd` (`WaitForFirstConsumer`).
- Alternativa com binding imediato: `ocs-external-storagecluster-ceph-rbd-immediate`.
