# Credenciais criadas neste lab

Criadas via API do Controller (`/api/controller/v2/...`), autenticando como `admin`
através da rota do Gateway. Mesmos campos e valores da UI — ver
`docs/guia-configuracao.md` para o procedimento genérico.

## Credenciais

| Nome | Tipo | ID | Inputs |
|---|---|---|---|
| `Vault SSH CA - POC` | HashiCorp Vault Signed SSH (credential_type 30) | 3 | `url`, `role_id`, `secret_id` (AppRole `aap-controller`), `default_auth_path=approle` |
| `Ansible Machine - Vault Signed SSH - POC` | Machine (credential_type 7) | 4 | `username=ansible`, `ssh_key_data=<chave privada estática>` |

Par de chaves gerado uma única vez com `ssh-keygen -t rsa -b 2048`, não persistido
após a criação da credencial (a API do AAP criptografa o valor internamente).

## Input Source

`POST /api/controller/v2/credential_input_sources/`:

```json
{
  "input_field_name": "ssh_public_key_data",
  "target_credential": 4,
  "source_credential": 3,
  "metadata": {
    "public_key": "<conteudo do .pub>",
    "secret_path": "ssh",
    "role": "aap-role",
    "valid_principals": "ansible"
  }
}
```

Validado com `POST /api/controller/v2/credentials/3/test/` — resposta `202`.

## Inventário

- Inventário `POC Vault SSH - Inventory` (id 2), variável
  `ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"`.
- Host `rhel.gw8gc.sandbox2991.opentlc.com` (id 2).

## Project e Job Template

- Project `AAP Vault Signed SSH - Demo` (id 7): SCM Git,
  `https://github.com/lccherri/aap-vault-signed-ssh.git`, branch `main`,
  `scm_update_on_launch=true`.
- Job Template `Demo - Vault Signed SSH` (id 8): inventory id 2, project id 7,
  playbook `playbooks/demo.yml`, credencial Machine id 4.
- Execução de referência (job id 8) — sucesso, stdout confirma certificado novo a
  cada run:
  ```
  Identity added: /runner/artifacts/8/ssh_key_data (aap-vault-signed-ssh-poc)
  Certificate added: /runner/artifacts/8/ssh_key_data-cert.pub (vault-approle-...)
  ...
  TASK [Exibir evidencia] ***
  ok: [rhel.gw8gc.sandbox2991.opentlc.com] => {
      "msg": [
          "Conexao autenticada via certificado SSH assinado pelo HashiCorp Vault.",
          ...
      ]
  }
  ```

## Incidente: Vault selado após restart do pod

Entre a criação das credenciais e o teste do Job Template, o pod `vault-0` reiniciou
(2 restarts) e voltou `Sealed=true` — Shamir de nó único, sem auto-unseal. O primeiro
lançamento do Job Template falhou com `503 Service Unavailable` no login AppRole
(`auth/approle/login`). Resolvido destravando novamente com as 3 unseal keys em
`out/vault-init.json`. Reproduz na prática o risco de SPOF do Vault em produção:
jobs novos falham no lookup da credencial quando o Vault está selado/indisponível;
é o comportamento esperado, não um bug.
