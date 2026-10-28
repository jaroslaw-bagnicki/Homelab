# SSH Certificates — Fleet SSH CA, Host Certificates, `automation` and `agent-ai`

> Move LAN SSH access from the shared fleet key to **short-lived `step-ca` certificates**:
> host certificates on every LAN node, an `automation` certificate for non-agent playbooks, and one
> shared `agent-ai` credential for all AI agents with a per-agent key ID. The fleet key stays installed
> as the break-glass path. Decisions: [ADR 41](../decisions/41-ssh-certificates-step-ca.md) (amended
> 2026-10-27) and [ADR 45](../decisions/45-workload-identity.md) (SSH exception); issue
> [#161](https://github.com/jaroslaw-bagnicki/Homelab/issues/161).

**Status:** 📋 Prepared — not yet executed. Every section carries a verification gate; record the
observed output under **Execution record** when it runs.

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
step ca provisioner list --ca-config /etc/step-ca/config/ca.json
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

> **Execution record:** _(not yet run)_

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

> **Execution record:** _(not yet run)_

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

> **Execution record:** _(not yet run)_

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
# restore the fleet key from Key Vault for break-glass
Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name fleetadm-key-priv -AsPlainText | ssh-add -
```

**Break-glass drill.** Stop the CA, prove the fleet key still logs in, then restore:

```sh
ssh fleetadm@192.168.2.215 'sudo systemctl stop step-ca'
ssh fleetadm@192.168.2.200 'hostname && sudo -n whoami'   # fleet key, no certificate
ssh fleetadm@192.168.2.215 'sudo systemctl start step-ca'
```

Record the drill. The fleet key is the only path that survives a CA outage.

> **Execution record:** _(not yet run)_

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

> **Execution record:** _(not yet run)_

## 7. Operations

- **Revoke the AI class:** remove `agent-ai@internal`; existing certificates remain valid until they
  expire (≤ 8 h). Re-add it with a new password and update Key Vault.
- **Revoke one agent:** not possible at the CA with a shared principal. Disable the agent's future
  issuance at the broker when it lands; until then use the `RevokedKeys` KRL escalation for a single
  certificate, or rotate the class.
- **Rotate a JWK password:** remove and re-add the provisioner with a new password, update Key Vault,
  then re-issue the affected certificates. Removing the provisioner does not revoke existing certs.
- **TPM loss:** run the step-ca workload with `-e step_ca_reset=true`, repeat the offline ceremony
  ([runbook 36](36-private-ca-init.md)), publish the new SSH CA public keys, re-run `ca_trust` and the
  `security` role, then re-issue host certificates. The X.509 root is unaffected.
- **`cloudlab`:** stays on the fleet key and the pinned host key. A LAN↔VPS path (tunnel/VPN) is a
  prerequisite for including it; do not add its IP to `@cert-authority` until then.

## Verification checklist

- [ ] SSH CA keys created in the TPM; `step-ca` serves both; public keys published to Key Vault
- [ ] `sshpop`, `hosts@internal`, `automation@internal` and `agent-ai@internal` present
- [ ] `ca_trust` installs the SSH CA keys on the LAN nodes; `cloudlab` untouched
- [ ] A client accepts a host certificate via `@cert-authority` without per-host `known_hosts`
- [ ] Host certificates carry short name, `.internal` and inventory IP on every LAN node
- [ ] `sshd -T` shows `HostCertificate`, `TrustedUserCAKeys`, `AuthorizedPrincipalsFile`
- [ ] Renewal timer runs; a near-expiry certificate renews and reloads `sshd`
- [ ] `automation` certificate runs a playbook with the fleet key removed from the agent
- [ ] Break-glass drill: CA stopped, fleet key still logs in
- [ ] `agent-ai` certificate carries principal `agent-ai` and key ID `agent-<name>`
- [ ] Deleting `agent-ai@internal` stops new AI-agent issuance; existing certs expire

## References

- [ADR 41](../decisions/41-ssh-certificates-step-ca.md) — SSH certificates, amended for `agent-ai` and `cloudlab`
- [ADR 45](../decisions/45-workload-identity.md) — SSH exception for the shared AI-agent identity
- [Runbook 35](35-deploy-step-ca.md) · [runbook 36](36-private-ca-init.md) · [runbook 39](39-trust-private-ca.md)
- [Research 43](../research/43-ssh-certificates-step-ca.md) — SSH certificate mechanics and the policy gap
