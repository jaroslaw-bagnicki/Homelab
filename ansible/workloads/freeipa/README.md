# FreeIPA workload

## Purpose

A self-contained Ansible recipe that installs the **FreeIPA server** on the `ipa` VM (VMID 216,
`192.168.2.216`) on the `pve` node, realm **`IPA.INTERNAL`**, DNS domain **`ipa.internal`**,
integrated DNS **off**. Decision: [ADR 43](../../../docs/decisions/43-freeipa-domain-realm.md);
CA relation: [ADR 42](../../../docs/decisions/42-pki-topology-sibling-cas.md); implementation:
[issue #164](https://github.com/jaroslaw-bagnicki/Homelab/issues/164) and
[runbook 41](../../../docs/runbooks/41-deploy-freeipa-server.md).

## Two-phase external CA

The role targets `freeipa_ca_mode: external`:

1. **Phase 1** runs `ipa-server-install --external-ca` and emits `/root/ipa.csr`.
2. The operator signs that CSR with the offline fleet root
   ([`sign-ipa-ca.sh`](../../../docs/private-ca-offline-signing/sign-ipa-ca.sh)) and copies
   `ipa-ca.crt` + `root_ca.crt` back to `/root`.
3. **Phase 2** reruns the installer with both `--external-cert-file` arguments and completes the
   server.

`freeipa_ca_mode: selfsigned` is the documented interim fallback; it must be re-parented before M3.
The role refuses to complete Phase 2 until both signed files exist.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `freeipa_ca_mode` | `external` | `external` or `selfsigned` |
| `freeipa_server_package` | `freeipa-server` | Fedora package name; override to `ipa-server` on RHEL/AlmaLinux |
| `freeipa_ds_password_secret` | `freeipa-directory-manager-password` | AKV secret for Directory Manager |
| `freeipa_admin_password_secret` | `freeipa-admin-password` | AKV secret for `admin` |
| `freeipa_ds_password` / `freeipa_admin_password` | `""` | Override to skip the AKV lookup (tests) |
| `freeipa_test_user` | `m1test` | M1 test user; its password is set interactively in the runbook |

The realm, domain, FQDN and address are fixed in `defaults/main.yml` and must match
`host_vars/ipa.yml` and Technitium.

## Base guest

The role assumes `playbook-ipa.yml` has already applied `ipa_host`: Fedora 45, FQDN
`ipa.internal`, `/etc/hosts`, the Technitium resolver pin, chrony, firewalld LAN rules and the
`fleetadm` key. It is **not** a Debian guest and does not use `common`/`security`.

Fedora ships the server as `freeipa-server`; the role uses `freeipa_server_package` so an
AlmaLinux/Rocky host can override it to `ipa-server` without changing the tasks.

## Deploy

```powershell
# phase 1 — emits /root/ipa.csr on the ipa VM
ansible-playbook ansible/workloads/freeipa/freeipa-playbook.yml --diff

# sign /root/ipa.csr with the offline root, copy ipa-ca.crt + root_ca.crt back to /root

# phase 2 — completes the install
ansible-playbook ansible/workloads/freeipa/freeipa-playbook.yml --diff
```

Run only after CR ([Ansible Verification](../../../AGENTS.md#ansible-verification)).

## Scope

M1 only: server, external CA, test user, verification. Backup/restore is M2; clients, HBAC/sudo and
LDAPS are later milestones.
