# Credenciais criadas neste lab

Criadas via API do Controller (`/api/controller/v2/...`), autenticando como `admin`
atraves da rota do Gateway. Mesmos campos e valores da UI — ver
`docs/guia-configuracao.md` para o procedimento generico.

## Credenciais

| Nome | Tipo | ID | Inputs |
|---|---|---|---|
| `Vault SSH CA - POC` | HashiCorp Vault Signed SSH (credential_type 30) | 3 | `url`, `role_id`, `secret_id` (AppRole `aap-controller`), `default_auth_path=approle` |
| `Ansible Machine - Vault Signed SSH - POC` | Machine (credential_type 7) | 4 | `username=ansible`, `ssh_key_data=<chave privada estatica>` |

Par de chaves gerado uma unica vez com `ssh-keygen -t rsa -b 2048`, nao persistido
apos a criacao da credencial (a API do AAP criptografa o valor internamente).

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

## Inventario e teste funcional

- Inventario `POC Vault SSH - Inventory` (id 2), variavel
  `ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"`.
- Host `rhel.gw8gc.sandbox2991.opentlc.com` (id 2).
- Ad Hoc Command (`whoami`, credencial id 4) executado com sucesso contra o host.
  stdout confirma emissao de certificado pelo Vault a cada execucao:
  ```
  Identity added: /runner/artifacts/1/ssh_key_data (aap-vault-signed-ssh-poc)
  Certificate added: /runner/artifacts/1/ssh_key_data-cert.pub (vault-approle-...)
  rhel.gw8gc.sandbox2991.opentlc.com | CHANGED | rc=0 >>
  ansible
  ```

Proximo passo: substituir o Ad Hoc Command por um Project + Job Template apontando
para `playbooks/demo.yml` (passo 8 de `docs/guia-configuracao.md`), assim que o
repositorio estiver disponivel em um remoto Git.
