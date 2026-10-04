# step-ca workload

## Purpose

A self-contained Ansible recipe that deploys the fleet **private CA** — **`step-ca`** — as a native
systemd service on the `ca` guest (LXC 215, `192.168.2.215`) on the `pve` node, with the intermediate
CA private key held in the host's **TPM 2.0**. Decision:
[ADR 38](../../../docs/decisions/38-private-ca-hierarchy-and-custody.md); measured gate:
[#141](https://github.com/jaroslaw-bagnicki/Homelab/issues/141); operational steps:
[runbook 35](../../../docs/runbooks/35-deploy-step-ca.md) and
[runbook 36](../../../docs/runbooks/36-private-ca-init.md).

`step-ca` is a **native service, not a container** — the TPM KMS is pure Go on the stock binary, so
there is no image to build and the CA keeps the smallest possible attack surface
([research 36 §5](../../../docs/research/36-step-ca-machine-identity.md)).

## Two-phase recipe (one idempotent run)

| Phase | When | What |
|---|---|---|
| **prepare** | every run | install `step`/`step-ca`/`step-kms-plugin` (checksum-verified) + `libpcsclite1`; create the intermediate key **in the TPM**; emit `intermediate_ca.csr`; write the TPM-backed `ca.json`; stage the systemd unit **disabled** |
| **start** | only once the root-signed `intermediate_ca.crt` and `root_ca.crt` are present in `/etc/step-ca/certs/` | enable and start `step-ca` |

The root signs the CSR **offline** on an air-gapped island ([runbook 36](../../../docs/runbooks/36-private-ca-init.md)),
so between the two phases the operator copies the two public certificates onto the guest. The start
step is gated on their presence, so a run before the offline signing simply prepares and stops.

**Safety.** The TPM key is create-once — never recreated, with no force path. The CSR is create-only
unless `step_ca_csr_force=true` (the annual re-sign). A routine run therefore cannot destroy the
sealed key or clobber a CSR awaiting signing.

## Capabilities

- **Hardware key custody** — the intermediate private key is generated inside `/dev/tpmrm0` and never
  exists in the clear; `ca.json` pins the `tpmkms` **storage directory** (gate #141).
- **Native systemd service** — enabled, `restart=on-failure`; no Docker.
- **ACME provisioner** — added to `ca.json` so the reverse proxy ([#142](https://github.com/jaroslaw-bagnicki/Homelab/issues/142))
  and LAN services renew short-lived leaves automatically.
- **Checksum-verified tooling** — the current upstream release, verified against the release
  `checksums.txt` (gate #141: a truncated download produced a false "step-ca is broken" result).
- **Provisioner password from AKV** — written to a root-only `file://` path, never in the unit's
  environment or a command line.
- **Not backed up as a node** — recovery is **re-issue, not restore**: the offline root is untouched
  and the intermediate is re-signed, with no client re-trust (ADR 38).

## Services

| Service | Port | Owned by |
|---|---|---|
| `step-ca` (`/usr/local/bin/step-ca`) | `:9000` (LAN-only via UFW, runbook 35 §4) | `step_ca` role |

## Host on-disk layout

```
/etc/step-ca/
├── config/ca.json          # root/crt/key/kms/db; mode 0600
├── certs/
│   ├── root_ca.crt         # offline root (public) — installed after runbook 36
│   └── intermediate_ca.crt # root-signed intermediate (public)
├── secrets/password        # provisioner password from AKV (mode 0600)
├── intermediate_ca.csr     # public CSR for the offline root (create-only)
└── db/                     # badgerv2 database
/var/lib/step-ca/tpm/key-homelab-intermediate-ca.tpmobj   # TPM sealed blob — NOT a key file
/usr/local/bin/{step,step-ca,step-kms-plugin}
```

The `.tpmobj` is the **sealed blob** the TPM key lives in — it is useless off this TPM and required on
disk for the service to start.

## Variables

The role is single-host and single-purpose, so paths (`/etc/step-ca`,
`/var/lib/step-ca/tpm`), the CA identity (`Homelab Internal CA`, `ca.internal`, `:9000`), the key
name and the ACME provisioner name are **hardcoded in the tasks/templates**. Only these are knobs:

| Variable | Default | Purpose |
|---|---|---|
| `step_ca_keyvault_name` | `homelab-bysxdb-kv` | Key Vault holding the password |
| `step_ca_password_secret_name` | `step-ca-provisioner-password` | secret name |
| `step_ca_password` | `""` | override to skip the Key Vault lookup (tests) |
| `step_ca_csr_force` | `false` | regenerate the CSR from the existing TPM key (annual re-sign) |

The binary assets live in the role's `vars/main.yml` (`step_ca_releases`). Upgrades follow normal
package practice — clear `/var/tmp/step-ca-install` and re-run.

## Secrets

- `step-ca-provisioner-password` — the CA provisioner password (`step_ca_password_secret_name`) in
  `homelab-bysxdb-kv`. Written to `/etc/step-ca/secrets/password` (mode `0600`); the service
  reads it with `--password-file`.

## Deploy

```powershell
# from a LAN workstation, with the fleet key loaded, after CR
chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible
ansible-playbook ansible/workloads/step-ca/step-ca-playbook.yml --diff
```

Run order across the two workstreams: base guest ([`playbook-ca.yml`](../../playbooks/playbook-ca.yml))
→ this workload (`prepare`) → offline ceremony ([runbook 36](../../../docs/runbooks/36-private-ca-init.md))
→ this workload again (`start`).

## References

- [ADR 38](../../../docs/decisions/38-private-ca-hierarchy-and-custody.md) — hierarchy, custody, `pve` host
- [Runbook 35](../../../docs/runbooks/35-deploy-step-ca.md) — deploy + validate · [Runbook 36](../../../docs/runbooks/36-private-ca-init.md) — offline root/signing
- [Research 36 §5](../../../docs/research/36-step-ca-machine-identity.md) · [Research 37 §5](../../../docs/research/37-tpm2-hardware-and-fleet.md) · [#141](https://github.com/jaroslaw-bagnicki/Homelab/issues/141)
