# SSH Certificates — Fleet SSH CA, Host Certificates, `automation` and `agent-ai`

> Move LAN SSH access from the shared fleet key to **short-lived `step-ca` certificates**:
> host certificates on every LAN node, an `automation` certificate for non-agent playbooks, and one
> shared `agent-ai` credential for all AI agents with a per-agent key ID. The fleet key stays installed
> as the break-glass path. Decisions: [ADR 41](../decisions/41-ssh-certificates-step-ca.md) (amended
> 2026-10-27) and [ADR 45](../decisions/45-workload-identity.md) (SSH exception); issue
> [#161](https://github.com/jaroslaw-bagnicki/Homelab/issues/161).

**Status:** ✅ Delivered 2026-10-31 — §1–§6 executed against the fleet; each carries the observed output
under **Execution record**. The operations section at the end is reference material for later changes,
not part of the delivery sequence.

The **delivery steps are §1–§6**; each carries a verification gate. §7 is not a delivery step and has no
gate — it documents revocation, rotation and recovery for when the stack is already live.

**Scope.** `pve`, `lab`, `edge`, `nas`, `vtstack` and `ca`. **`cloudlab` is deliberately excluded** — it
has no LAN route to `ca.internal`, so it keeps the pinned host key and the fleet key. The AI-agent broker
is **not** part of this runbook; until it lands, agents self-issue with the shared `agent-ai` JWK
(§6), and per-agent revocation is a class-level operation.

---

## Prerequisites

- [ ] `step-ca` workload deployed and healthy ([runbook 35](35-deploy-step-ca.md)).
- [ ] `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID` exported on the controller.
- [ ] Fleet key in `ssh-agent` (`ssh-add -l` shows `fleetadm@homelab`) and the LAN workstation/control
      node can reach `ca.internal:9000`.
- [ ] `step` CLI and OpenSSH (`ssh-keygen`, `ssh-add`) on the controller. The dev container installs
      `step` in `.devcontainer/scripts/setup-step.ps1`; on a LAN workstation install smallstep/cli.
- [ ] From the dev container only: `chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible`.
- [ ] The LAN workstation resolves `ca.internal` (Technitium or a hosts-file entry). The deploy adds
      `ca.internal` to `/etc/hosts` on every managed host.

## 1. Provision the SSH provisioner passwords

The three SSH JWK provisioners are bound to their passwords when they are created. Seed the Key Vault
secrets first; do not overwrite an existing secret:

```powershell
./scripts/New-HomelabSshProvisionerPasswords.ps1
```

Creates:

| Secret | Provisioner |
|---|---|
| `step-ca-ssh-hosts-password` | `hosts@internal` — initial host issuance |
| `step-ca-ssh-automation-password` | `automation@internal` — non-agent Ansible |
| `step-ca-ssh-agent-ai-password` | `agent-ai@internal` — all AI agents |

## 2. M1 — SSH CA on the `ca` guest

Apply the step-ca workload. It creates both SSH CA keys **in the TPM**, adds the `ssh` block, the
authority SSH policy (`@internal` email, `automation`/`agent-ai` principals, LAN host names/IPs), the
`sshpop` provisioner, and the three JWK provisioners. It also writes the SSH CA public keys on the CA.

```powershell
# LAN workstation, with the fleet key loaded
ansible-playbook ansible/workloads/step-ca/step-ca-playbook.yml --diff
```

**Validate on `ca` (root):**

```sh
ssh fleetadm@192.168.2.215 'sudo -i'
step ca provisioner list --ca-url https://ca.internal:9000 --root /etc/step-ca/certs/root_ca.crt
journalctl -u step-ca --no-pager -o cat | grep -E '^SSH (Host|User) CA Key:'
ls -l /etc/step-ca/certs/ssh_*_key.pub /etc/ssh/ssh_*_key.pub
```

Expected: `admin@internal` has `enableSSHCA: true`; `sshpop`, `hosts@internal`, `automation@internal`
and `agent-ai@internal` are present; both SSH CA keys are printed and the files exist.

**TPM gate.** If `step-ca` cannot start with the `tpmkms:` SSH signers, stop here. Switch
`step_ca_ssh_key_custody: file`, amend ADR 41, and re-run. Do not put host certificates on the fleet
until this gate passes.

**Publish the SSH CA public keys** (from the control node; copy the two files from `ca` first):

```powershell
ssh fleetadm@192.168.2.215 'sudo cat /etc/step-ca/certs/ssh_host_ca_key.pub' > ssh_host_ca_key.pub
ssh fleetadm@192.168.2.215 'sudo cat /etc/step-ca/certs/ssh_user_ca_key.pub' > ssh_user_ca_key.pub
./scripts/Set-HomelabSshCaKeys.ps1 -HostKeyPath ./ssh_host_ca_key.pub -UserKeyPath ./ssh_user_ca_key.pub
Remove-Item ./ssh_host_ca_key.pub, ./ssh_user_ca_key.pub
```

> **Execution record:** 2026-10-31 — **TPM gate passed.** `ca.json` carries
> `ssh.hostKey: tpmkms:name=homelab-ssh-host-ca` and `ssh.userKey: tpmkms:name=homelab-ssh-user-ca`;
> `step-ca` is `active` and logged both `SSH Host CA Key:` / `SSH User CA Key:` (ECDSA P-256) after the
> restart. Provisioners: `acme` (ACME), `admin@internal` (JWK, `enableSSHCA: true`), `sshpop` (SSHPOP,
> `enableSSHCA: true`), `hosts@internal`, `automation@internal`, `agent-ai@internal` (JWK, SSH enabled).
> Published: host CA `256 SHA256:j6/pAzp9vAKjm7njR1Khkyq0ZWCtv2p6KJgi0v7Zg9c`, user CA
> `256 SHA256:cTbpT2fsQgyZ3Db8EvJs2VxdiJV9HcfjQ+bw6pZRItU`.
>
> Four defects surfaced on the live run and were fixed in the same change:
>
> 1. **Provisioner creation is an online admin call.** step CLI 0.31 dropped the offline `--ca-config`
>    write: `provisioner add` requires `--ca-url`, `--root`, `--admin-provisioner` and
>    `--admin-password-file`. The role now writes the merged config, restarts `step-ca`, and only then
>    creates/updates the provisioners against `https://ca.internal:9000`.
> 2. **Activated-config checksum.** `ca.json` is rewritten by the CA itself on every admin-API change, so
>    the "did the config change?" checksum is now recorded last, after the provisioner calls.
> 3. **SSH templates must start with `{`.** `CustomSSHTemplateOptions` treats any template that does not
>    begin with `{` as base64 JSON — the `{{ if … }}` guard at position 0 failed every signature with
>    `error parsing template`. Templates now open with a literal brace; the type guard follows as an
>    action. A template change also needs a `step-ca` restart: the running authority keeps the template
>    it loaded at start.
> 4. **No `sshd` reload.** `ssh.socket` holds port 22 on `ca`, so a SIGHUP re-exec fails with
>    `fatal: Cannot bind any address`. The CA-key publication only writes public-key files, so the
>    handler was dropped; `security` restarts sshd where a config change needs it.

## 3. M2 — Distribute the SSH CA public keys

The `ca_trust` role now fetches `ssh-host-ca-pub` / `ssh-user-ca-pub` from Key Vault and installs them as
`/etc/ssh/ssh_host_ca_key.pub` and `/etc/ssh/ssh_user_ca_key.pub`. `cloudlab` opts out in `host_vars`.

```powershell
ansible-playbook ansible/playbooks/playbook-ca-trust.yml --diff --limit 'physical:proxmox_guests'
# cloudlab is intentionally untouched; running it there only re-verifies the X.509 root.
```

On the **workstation** add the host-CA trust line to `known_hosts`:

```powershell
./scripts/Set-HomelabSshKnownHosts.ps1
```

The dev-container profile does this automatically after it has an Azure context. The line is
`@cert-authority *.internal,192.168.2.* <host-CA-public-key>`; `cloudlab`'s public IP is not included.

Verify a client accepts a test host certificate without a per-host `known_hosts` entry, then remove stale
pinned LAN entries:

```sh
ssh-keygen -R pve.internal; ssh-keygen -R 192.168.2.201
```

> **Execution record:** 2026-10-31 — `ca_trust` applied to `pve`, `lab`, `nas`, `edge`, `vtstack`
> (5/5 `ok=14 changed=2 failed=0`): `/etc/ssh/ssh_host_ca_key.pub` and `/etc/ssh/ssh_user_ca_key.pub`
> installed from Key Vault on every node, root still verified against the pinned fingerprint.
> `./scripts/Set-HomelabSshKnownHosts.ps1` wrote
> `@cert-authority *.internal,192.168.2.* <host-CA-public-key>` to the workstation `known_hosts`.
> `cloudlab` untouched, as intended.
>
> Controller prerequisite worth recording: the dev container had **no** `ca.internal` mapping (the
> issuance step silently skipped, printing an advisory). It needs
> `192.168.2.215 ca.internal` in `/etc/hosts` before M3.

## 4. M3 — Host certificates on every LAN node

The `security` role now:

- installs the `step` CLI on non-CA nodes;
- issues the initial host certificate through `hosts@internal` **on the controller** — the password is
  fetched from Key Vault there, the host's public key is signed, and only the certificate is copied back;
- on every run checks the remaining lifetime and reissues through `hosts@internal` when the certificate
  is missing or within 49 h of expiry, so an expired certificate is not stuck;
- deploys an SSHPOP renewal timer (`homelab-ssh-host-cert-renew.timer`) that renews when less than 49 h
  remain and reloads `sshd`;
- writes `AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u` with `automation` and `agent-ai`;
- adds `TrustedUserCAKeys`, `HostCertificate` and an ed25519-only `HostKeyAlgorithms` to the hardening
  drop-in.

`ca_trust` runs **before** `security` in the LAN playbooks so the root and SSH CA keys exist first. On
`ca`, `security` uses `/etc/step-ca/certs/root_ca.crt` after the CA is running.

```powershell
# LAN workstation, one at a time
ansible-playbook ansible/playbooks/playbook-pve.yml --diff
ansible-playbook ansible/playbooks/playbook-lab.yml --diff
ansible-playbook ansible/playbooks/playbook-edge.yml --diff
ansible-playbook ansible/playbooks/playbook-nas.yml --diff
ansible-playbook ansible/playbooks/playbook-logs.yml --diff

# ca guest: the CA must be healthy for the host certificate
ansible-playbook ansible/playbooks/playbook-ca.yml --diff
```

**Validate on each node:**

```sh
sudo ssh-keygen -L -f /etc/ssh/ssh_host_ed25519_key-cert.pub
sudo sshd -T | grep -E 'hostcertificate|trustedusercakeys|authorizedprincipalsfile|hostkeyalgorithms'
sudo systemctl list-timers homelab-ssh-host-cert-renew.timer
sudo /usr/local/sbin/homelab-ssh-host-cert-renew   # exits 0 when >49 h remain
```

The certificate must list the short hostname, `<node>.internal` and the node's inventory address.
A renewal failure leaves `homelab-ssh-host-cert-renew.service` in the failed state: the stock Netdata
`systemd_service_unit_failed_state` alarm raises, and the alert unit writes a `crit` journal line that
Fluent Bit ships to VictoriaLogs. Alarm delivery remains deferred per ADR 27.

**Renewal proof.** On a canary node, temporarily raise the renewal threshold so the 7-day certificate is
treated as near expiry, run the role once, then restore the normal threshold:

```powershell
ansible-playbook ansible/playbooks/playbook-lab.yml --diff --limit lab -e security_ssh_renew_before_seconds=999999
ansible-playbook ansible/playbooks/playbook-lab.yml --diff --limit lab
```

```sh
sudo ssh-keygen -L -f /etc/ssh/ssh_host_ed25519_key-cert.pub   # fresh 7-day window
sudo journalctl -u homelab-ssh-host-cert-renew -n 20
```

> **Execution record:** 2026-10-31 — **complete across all six nodes.**
>
> | Node | Playbook | First run | Re-run |
> |---|---|---|---|
> | `lab` (canary) | `playbook-lab.yml` | `ok=114 changed=10 failed=0` | — |
> | `pve` | `playbook-pve.yml` | `ok=126 changed=19 failed=0` | — |
> | `edge` | `playbook-edge.yml` | `ok=150 changed=19 failed=0` | `changed=0` |
> | `nas` | `playbook-nas.yml` | `ok=67 changed=17 failed=0` (1 transient unreachable) | `ok=83 changed=0` |
> | `vtstack` | `playbook-logs.yml` | `ok=97 changed=20 failed=0` | `changed=1` |
> | `ca` | `playbook-ca.yml` | `ok=64 changed=15 failed=0` | `changed=1` |
>
> Every node: `ssh-ed25519-cert-v01@openssh.com host certificate`, signing CA
> `ECDSA SHA256:j6/pAzp9…` (the published host CA), the node's inventory address among the principals, and
> `homelab-ssh-host-cert-renew.timer` **active**. Canary detail as recorded above; `sshd -T` on `lab`
> reports `hostcertificate`, `trustedusercakeys /etc/ssh/ssh_user_ca_key.pub`,
> `authorizedprincipalsfile /etc/ssh/auth_principals/%u`,
> `hostkeyalgorithms ssh-ed25519-cert-v01@openssh.com`; a manual renewal run exits 0.
>
> Two operational notes:
>
> - **`ca` and `vtstack` run no time daemon** (`systemd-timesyncd`, `chrony`, `ntpsec` all inactive) and
>   inherit the host clock through the container. The CA was ~6 h behind during the first issuances, so
>   the `pve`/`lab`/`edge`/`nas` certificates carry a `notBefore` 6 h in the past and a slightly short
>   7-day window. Harmless — the clocks are consistent again — but the CA guest should get time sync
>   before certificates become load-bearing, and §5's break-glass drill is the natural place to confirm.
> - **Losing `ssh-agent` mid-run** costs a playbook: every task fails `Permission denied (publickey)`.
>   Start the agent on a fixed socket (`ssh-agent -a /tmp/fleet-ssh-agent.sock`) so it survives terminal
>   churn, and export `SSH_AUTH_SOCK` in each new shell.

## 5. M4 — `automation` principal

`automation@internal` is the non-agent control path. It is **not** the identity for agent-run playbooks;
an agent session uses its own `agent-ai` certificate.

```powershell
# LAN workstation, with ssh-agent running
./scripts/Get-HomelabSshAutomationCert.ps1
ssh-add -L | Select-String 'automation'
```

Prove the path without the fleet key: start a fresh agent, load only the automation certificate, run a
playbook, then restore the fleet key:

```powershell
# example on the workstation; do not log the certificate or password
ssh-add -D
./scripts/Get-HomelabSshAutomationCert.ps1
ansible-playbook ansible/playbooks/playbook-lab.yml --diff
# break-glass only: import the fleet key explicitly
./scripts/Import-HomelabFleetKey.ps1
```

**Break-glass drill.** Stop the CA, prove the fleet key still logs in, then restore:

```sh
ssh fleetadm@192.168.2.215 'sudo systemctl stop step-ca'
ssh fleetadm@192.168.2.200 'hostname && sudo -n whoami'   # fleet key, no certificate
ssh fleetadm@192.168.2.215 'sudo systemctl start step-ca'
```

Record the drill. The fleet key is the only path that survives a CA outage.

> **Execution record:** 2026-10-31 — **drill passed.** `step-ca` stopped on `ca` (`inactive`), the fleet
> key logged into `lab` (`hostname` → `lab`, `sudo -n whoami` → `root`) with no certificate involved, and
> the CA came back `active` with `step ca health … → ok`.
>
> **2026-10-31 (follow-up) — the `automation` path ran a playbook.** A fresh agent on
> `/tmp/automation-gate.sock` held the `automation` certificate and no fleet key
> (`ssh-add -l` → one `ED25519-CERT`), and `ansible-playbook ansible/playbooks/playbook-ca.yml
> --check` connected as that principal: `ok=35 changed=4 failed=1`. The single failure is a check-mode
> artifact, not a defect — `security : Fetch the issued host certificate` reads
> `/tmp/homelab-ssh-issue-ca/ssh_host_ed25519_key-cert.pub`, which check mode never creates because
> the issuance task is skipped.

## 6. M5 — Shared `agent-ai` identity

All AI agents use one principal `agent-ai` and one JWK `agent-ai@internal`; the SSH template fixes the
principal and preserves the requested **key ID**. The shared credential is a deliberate tradeoff:
per-agent audit by key ID, class-level revocation.

```powershell
# Copilot session
./scripts/Get-HomelabSshAgentCert.ps1 -Agent copilot
ssh-add -L | Select-String 'agent-ai'
# OpenCode session
./scripts/Get-HomelabSshAgentCert.ps1 -Agent opencode
```

Run an Ansible playbook from the agent session; the host log shows principal `agent-ai` and the key ID
`agent-copilot` (or `agent-opencode`). `automation` remains a separate identity for non-agent runs. The
key ID is an **audit hint**, not an authorization boundary: the script self-asserts it, and the shared
principal is what `auth_principals` checks.

**Broker (deferred).** The target custody is a broker that holds the JWK password and issues per-agent
key IDs; until it lands, the agent script fetches the shared secret. The broker will restore per-agent
revocation and should be the only holder of `step-ca-ssh-agent-ai-password`.

> **Execution record:** 2026-10-31 — **`agent-ai` works.** `Get-HomelabSshAgentCert.ps1 -Agent copilot`
> issued a certificate into a dedicated agent socket (the script refuses while the fleet key is loaded —
> that is the intended guard). `ssh-add -L` shows the certificate with key ID `agent-copilot`; the `lab`
> sshd log records
> `Accepted publickey … ED25519-CERT … ID agent-copilot … CA ECDSA SHA256:cTbpT2fs…` — the **user** CA,
> with the requested key ID preserved. Ansible ran over that identity alone:
> `playbook-lab.yml` `ok=102 changed=1 failed=0`, with 4 certificate logins logged.

## Operations (reference — not part of this runbook's delivery)

> **Not actionable for delivery.** Nothing in this section is executed to deliver §1–§6, and none of it
> has a verification gate. It is kept here because it is the only place these procedures are written
> down — reach for it when a credential must be revoked, rotated, or the CA rebuilt, not when rolling the
> change out.

- **Revoke the AI class:** remove `agent-ai@internal`; existing certificates remain valid until they
  expire (≤ 8 h). Re-add it with a new password and update Key Vault. The `step_ca` role recreates any
  missing provisioner from its Key Vault password, so a removal that is meant to stick must also delete
  `step-ca-ssh-agent-ai-password` — otherwise the next playbook run re-adds it.
- **Revoke one agent:** not possible at the CA with a shared principal. The `RevokedKeys` KRL path is
  **not wired**: the hardening drop-in sets `TrustedUserCAKeys` and `HostCertificate` but not
  `RevokedKeys`, so a KRL is never consulted (confirmed: `sshd -T` reports `revokedkeys none`). Until
  that is added and the broker lands, revoking one agent means rotating the whole class above.
- **Rotate a JWK password:** remove and re-add the provisioner with a new password, update Key Vault,
  then re-issue the affected certificates. Removing the provisioner does not revoke existing certs.
- **TPM loss:** run the step-ca workload with `-e step_ca_reset=true`, repeat the offline ceremony
  ([runbook 36](36-private-ca-init.md)), publish the new SSH CA public keys, re-run `ca_trust` and the
  `security` role, then re-issue host certificates. The X.509 root is unaffected. The reset clears
  `.active-intermediate.sha256` but not `.active-ca-config.sha256` — remove that file too, so the
  rebuilt CA is treated as a configuration change. `ca_trust` writes the new `TrustedUserCAKeys`
  content but does **not** reload `sshd` (a `ssh.socket` re-exec fails with `Cannot bind any address`),
  so finish with `systemctl restart ssh` on every host — otherwise hosts keep trusting the old CA key
  until their next restart.
- **`cloudlab`:** stays on the fleet key and the pinned host key. A LAN↔VPS path (tunnel/VPN) is a
  prerequisite for including it; do not add its IP to `@cert-authority` until then.

## Verification checklist

- [x] SSH CA keys created in the TPM; `step-ca` serves both; public keys published to Key Vault
- [x] `sshpop`, `hosts@internal`, `automation@internal` and `agent-ai@internal` present
- [x] `ca_trust` installs the SSH CA keys on the LAN nodes; `cloudlab` untouched
- [x] A client accepts a host certificate via `@cert-authority` without per-host `known_hosts`
- [x] Host certificates carry short name, `.internal` and inventory IP on every LAN node
- [x] `sshd -T` shows `HostCertificate`, `TrustedUserCAKeys`, `AuthorizedPrincipalsFile`
- [x] Renewal timer runs; a near-expiry certificate renews and restarts `sshd`
- [x] `automation` certificate runs a playbook with the fleet key removed from the agent
- [x] Break-glass drill: CA stopped, fleet key still logs in
- [x] `agent-ai` certificate carries principal `agent-ai` and key ID `agent-<name>`
- [ ] Deleting `agent-ai@internal` stops new AI-agent issuance; existing certs expire

## References

- [ADR 41](../decisions/41-ssh-certificates-step-ca.md) — SSH certificates, amended for `agent-ai` and `cloudlab`
- [ADR 45](../decisions/45-workload-identity.md) — SSH exception for the shared AI-agent identity
- [Runbook 35](35-deploy-step-ca.md) · [runbook 36](36-private-ca-init.md) · [runbook 39](39-trust-private-ca.md)
- [Research 43](../research/43-ssh-certificates-step-ca.md) — SSH certificate mechanics and the policy gap
