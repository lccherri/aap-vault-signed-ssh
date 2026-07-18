# VM RHEL de teste

Disponibilizada em 2026-07-17.

## Acesso

- Hostname: `rhel.gw8gc.sandbox2991.opentlc.com` (interno: `rhel.example.com`,
  IP `192.168.0.153`).
- Usuário inicial: `lab-user`, senha em `out/rhel-vm-creds.env` (não versionado),
  sudo passwordless.
- SO: RHEL 10.0, kernel `6.12.0-55.9.1.el10_0.x86_64`.
- OpenSSH: `OpenSSH_9.9p1` (pacote `openssh-server-9.9p1-7.el10_0.x86_64`).
- SELinux: `Enforcing`.

Suficiente para validar o fluxo funcional. Suporte a `TrustedUserCAKeys` depende da
versão do OpenSSH do host gerenciado — ver pré-requisitos em
`docs/guia-configuracao.md`.

## Configuração aplicada

1. Copiada a chave pública da CA (`out/trusted-user-ca-keys.pem`) para
   `/etc/ssh/trusted-user-ca-keys.pem` (`root:root`, modo `644`, contexto SELinux
   `etc_t` via `restorecon`).
2. Criado `/etc/ssh/sshd_config.d/60-vault-ssh-ca.conf`:
   ```
   TrustedUserCAKeys /etc/ssh/trusted-user-ca-keys.pem
   ```
3. Criado usuário local `ansible` (`useradd -m -s /bin/bash ansible`), sudo
   passwordless via `/etc/sudoers.d/ansible`. Mesmo username usado em
   `allowed_users`/`default_user` na role do Vault e no campo Username da
   credencial Machine do AAP.
4. `sshd -t` e `systemctl restart sshd`.

`/etc/sudoers.d/lab-user` pré-existente acusa permissão incorreta em
`visudo -c` — não relacionado a esta configuração, não alterado.

## Validação manual (Vault + host, sem passar pelo AAP)

1. Par de chaves de teste gerado localmente e descartado após o teste.
2. Login no Vault via AppRole `aap-controller`.
3. `vault write ssh/sign/aap-role public_key=@... valid_principals=ansible` — emite
   certificado `ssh-rsa-cert-v01@openssh.com`, validade 30 min, principal `ansible`.
4. `ssh -i <chave> -o CertificateFile=<cert> ansible@rhel.gw8gc.sandbox2991.opentlc.com`
   — login bem-sucedido.

Confirma o fluxo antes de configurar a credencial no AAP: Vault assina sob demanda,
host confia na CA via `TrustedUserCAKeys`, sem chave estática distribuída.
