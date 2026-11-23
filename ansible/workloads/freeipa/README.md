# FreeIPA workload

## Purpose

A self-contained Ansible recipe that installs the **FreeIPA server** on the `ipa` VM (VMID 250,
`192.168.2.250`) on the `pve2` node, realm **`LAB.INTERNAL`**, DNS domain **`lab.internal`**,
integrated DNS **off**. Decision: [ADR 43](../../../docs/decisions/43-freeipa-domain-realm.md);
CA relation: [ADR 42](../../../docs/decisions/42-pki-topology-sibling-cas.md); implementation:
[issue #164](https://github.com/jaroslaw-bagnicki/Homelab/issues/164) and
[runbook 41](../../../docs/runbooks/41-deploy-freeipa-server.md).

## Two-phase external CA

The role targets `freeipa_ca_mode: external`:

1. **Phase 1** runs `ipa-server-install --external-ca` and emits `/root/ipa.csr`.
2. The operator signs that CSR with the offline fleet root
   ([`04-signing-ipa-ca.md`](../../../docs/ca-signing-kit/v1-ironkey/04-signing-ipa-ca.md), the active IronKey
   flow — [runbook 41](../../../docs/runbooks/41-deploy-freeipa-server.md) §7) and copies
   `ipa-ca.crt` + `root_ca.crt` back to `/root`.
3. **Phase 2** reruns the installer with both `--external-cert-file` arguments and completes the
   server.

`freeipa_ca_mode: selfsigned` is the documented interim fallback; it must be re-parented before M3.
The role refuses to complete Phase 2 until both signed files exist.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `freeipa_ca_mode` | `external` | `external` or `selfsigned` |
| `freeipa_server_package` | `ipa-server` | RHEL/AlmaLinux/Rocky package name; override to `freeipa-server` on Fedora |
| `freeipa_ds_password_secret` | `freeipa-directory-manager-password` | AKV secret for Directory Manager |
| `freeipa_admin_password_secret` | `freeipa-admin-password` | AKV secret for `admin` |
| `freeipa_ds_password` / `freeipa_admin_password` | `""` | Override to skip the AKV lookup (tests) |
| `freeipa_test_user` | `m1test` | M1 test user; its password is set interactively in the runbook |

The realm, domain, FQDN and address are fixed in `defaults/main.yml` and must match
`host_vars/ipa.yml` and Technitium. The hostname (`ipa.internal`) deliberately differs from the
IPA domain (`lab.internal`) — `ipa-server-install` refuses a hostname equal to the domain, and
requires the hostname to be fully qualified.

## Base guest

The role assumes `playbook-ipa.yml` has already applied `ipa_host`: AlmaLinux 9, FQDN
`ipa.internal`, `/etc/hosts`, the Technitium resolver pin, chrony, firewalld LAN rules and the
`fleetadm` key. It is **not** a Debian guest and does not use `common`/`security`.

RHEL/AlmaLinux/Rocky ship the server as `ipa-server`; Fedora calls it `freeipa-server`. The role
uses `freeipa_server_package` so either name works without changing the tasks.

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

M1: server, external CA, test user, verification — **done**. M2: the domain's own artefact and a
rehearsed restore ([runbook 47](../../../docs/runbooks/47-freeipa-backup-restore.md)). Clients,
HBAC/sudo and LDAPS are later milestones.

## Backup recipe — `freeipa_backup`

`freeipa-backup-playbook.yml` is a **second entrypoint**, separately runnable, because the server
playbook is a two-phase install:

```powershell
ansible-playbook ansible/workloads/freeipa/freeipa-backup-playbook.yml --diff
```

It installs a nightly timer in the guest (`ipa-backup`, full by default so the artefact carries the CA,
with staging retention) and publishes the newest artefact — `relay` to a storage host today, `path`
into a mounted share once the NAS exists. **The destination is a transport, not a rewrite**: adding the
NAS changes `freeipa_backup_transport`/`freeipa_backup_publish_path`, not the role. The guest holds no
credential for the storage host by design — the `relay` transport reuses the controller's identities
([ADR 41](../../../docs/decisions/41-ssh-certificates-step-ca.md)). Full procedure:
[runbook 47](../../../docs/runbooks/47-freeipa-backup-restore.md).
