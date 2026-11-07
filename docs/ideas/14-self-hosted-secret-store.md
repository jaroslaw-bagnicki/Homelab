# Idea 14 — Self-Hosted Secret Store (replacing Azure Key Vault)

> Every playbook, script and runbook in the lab reads its credentials from **Azure Key Vault
> `homelab-bysxdb-kv`**. It works — and it makes the lab's automation depend on a cloud subscription, a
> service principal and a network path out of the LAN. This idea replaces it with a **secret store that
> runs on the fleet**.

**Status**: 🧠 Idea — no decision taken, nothing deployed
**Date**: 2026-10-25
**Sources**: [research 46 §1.4](../research/46-identity-and-access-stack.md) (the Vault/Infisical/Bitwarden comparison from the identity threads) · [research 22](../research/22-infisical-for-homelab-secret-management.md) (the earlier Infisical evaluation)
**Related**: [idea 13](13-freeipa-domain-controller.md) (the domain beside it — and where a TPM-bound unseal would live) · [ADR 28](../decisions/28-fleet-admin-account-and-key.md) (fleet key held in Key Vault) · [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) (CA custody — TPM-bound intermediate) · [ADR 39](../decisions/39-nut-host-native.md) (NUT passwords) · [ADR 35](../decisions/35-log-store-victorialogs.md) / [ADR 36](../decisions/36-log-collector-fluentbit.md) (passwords fetched at playbook time) · [idea 10](10-internal-ca-dns-stack.md) (the `.internal` stack the store would sit in) · [idea 11](11-authentik-idp.md) (a possible human login in front of the UI)

---

## Context

Key Vault is not an experiment in this repo — it is load-bearing. What actually reads it today:

| Consumer | Secret |
|---|---|
| `ansible/workloads/step-ca` | CA provisioner password |
| `ansible/workloads/victorialogs` | HTTP basic-auth password for ingest |
| `ansible/workloads/zot` | registry `htpasswd` credential |
| `ansible/workloads/opencode` | per-instance passwords |
| `ansible/roles/netdata` | parent/child stream key |
| `ansible/roles/fluentbit`, `ansible/roles/technitium` | service passwords |
| `runbooks/39` + the `ca_trust` role | the CA **root certificate** |
| `scripts/New-*` / `Set-*` PowerShell | create/rotate all of the above |
| [ADR 28](../decisions/28-fleet-admin-account-and-key.md) | fleet SSH key; Arc client secret |
| `bicep/` | provisions the vault itself |

Two mechanics tie it together: the `azure.azcollection.azure_keyvault_secret` lookup with
`AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` / `AZURE_TENANT_ID` on the Ansible controller, and the
`New-Homelab*` scripts that create the secrets with `Az` PowerShell. Both would have to change.

Why replace it at all: the lab would stop needing an Azure tenant and a service principal for its own
automation; secrets would be readable on the LAN alone (no WAN dependency for a playbook run); and the
store would sit beside the CA and the domain instead of in a subscription. The honest counter-argument:
Key Vault is *already* hardened, backed up and off-site by Microsoft — a self-hosted store trades that
for control, and inherits unseal, backup and availability as problems.

## What has to be replaced

| Capability | Needed? | Note |
|---|---|---|
| Versioned K/V with history | ✅ | `kv-v2`-class behaviour; the CA root and passwords change over time |
| Machine auth for Ansible (no human in the loop) | ✅ | today: service principal + three env vars |
| Human-readable UI / CLI | ✅ | today: the Azure portal and `Az.KeyVault` |
| Certificate storage (CA root, provisioner password) | ✅ | the CA bootstrap depends on it |
| Audit of who read what | ✅ | today: Azure activity logs |
| Dynamic DB credentials (TTL-bound) | ❔ | not used today; the reason to pick a "platform" over a "K/V" |
| Encryption-as-a-service / *Transit* | ❔ | only if anything calls Key Vault *Keys* rather than *Secrets* — **to check** |
| TPM-bound unseal | ❔ | removes the "master password in a file" problem on `pve` |
| HA / replica | ❔ | a lab can accept a single node + a rehearsed restore |

## Candidates

| Option | Verdict | Reason |
|---|---|---|
| **OpenBao** | **Leading candidate for the platform route** | Community fork of Vault (MPL-2.0, Linux Foundation — *verify governance*) keeping the Vault API, so `community.hashi_vault` and existing knowledge carry over, minus the BUSL licence |
| **HashiCorp Vault** | The reference implementation | Complete (PKI, Transit, dynamic secrets, AppRole, audit), best-documented; **BUSL-1.1 since 2023** for the server — licence terms need reading before adoption |
| **Infisical** | **Leading candidate for the K/V route** | Good UI, project/environment model, Machine Identities (Client ID + Secret), Ansible collection and CLI wrapper, low footprint — already assessed in [research 22](../research/22-infisical-for-homelab-secret-management.md) |
| Bitwarden Secrets Manager | Fallback | K/V only, very light, familiar UX; no dynamic secrets, no Transit |
| SOPS + age in Git | Rejected for this purpose | No server, no audit, no per-consumer auth — but fine for *some* static config |
| `ansible-vault` + password file | Rejected | A single shared password is worse than what exists today |
| Stay on Key Vault | **Always on the table** | Zero migration, off-site durability, already working |

**Leaning**: if the lab wants only what Key Vault actually does (K/V + machine auth + UI), **Infisical**
is the smaller change; if it wants a reusable platform (dynamic credentials, Transit, PKI, audit) and the
learning that comes with it, **Vault or OpenBao**. Not both.

## Migration shape

1. **Inventory the consumers** (the table above) and classify each secret: static password, certificate,
   key, or derived. Find out whether anything uses Key Vault *Keys* (would force Transit or a rewrite).
2. **Run the store beside Key Vault** — dual-read: `community.hashi_vault` / `infisical` lookups added
   next to the Azure ones, one workload at a time.
3. **Move the bootstrap secrets first** — CA provisioner password and CA root: they are needed *before*
   the store can be trusted to hold them, so the order is: store up → secrets imported → playbooks
   switched → Key Vault frozen read-only.
4. **Rotate everything that moved** — a secret that existed in two stores should be considered exposed.
5. **Decommission** — remove the service principal, the Bicep resource, the `AZURE_*` gates in the roles,
   and the `New-Homelab*` scripts' Key Vault paths.

## Risks worth naming

- **The store becomes a hard dependency of every playbook.** If it is down, configuration cannot be
  applied. A read-only cached copy (or a documented offline path) is not optional.
- **Unseal is the new single point of failure.** Auto-unseal bound to `pve`'s TPM
  ([research 37](../research/37-tpm2-hardware-and-fleet.md)) is elegant — and ties the store to one
  machine's boot state. A sealed copy of the unseal material, stored offline, is mandatory.
- **Backing up the store** is the same problem as backing up the CA and the domain: state that must be
  restored *together* (storage snapshot + unseal/key material) — the kind of backup that only proves
  itself when rehearsed.
- **Placement is contested.** `pve` is 8 GB and is also getting FreeIPA ([idea 13](13-freeipa-domain-controller.md));
  `lab` (16 GB) has room but carries workloads; `nas` has storage but the wrong role. This decision
  blocks the whole idea.
- **Two stores, one truth.** Running Infisical *and* Vault, or keeping Key Vault "just in case", recreates
  the split-brain this idea is meant to remove.

## Open questions

- **What is the actual driver** — removing the Azure dependency, cost, control, or learning? Each points at
  a different product.
- **Does anything use Key Vault *Keys*** (encryption) rather than *Secrets*? If yes, only a
  Transit-capable store replaces it.
- **Vault vs OpenBao** — is licence cleanliness worth a smaller community, or is BUSL acceptable for a
  personal lab?
- **Where does it run**, given `pve` is already committed to FreeIPA?
- **Do humans log in to it** — Authentik in front, or the store's own UI with local accounts?
- **What is the DR story** — snapshot + offline unseal material + a rehearsed restore on a spare LXC?
- **Does the CA stay in Key Vault** even after everything else moves (it is the one secret whose loss is
  unrecoverable)?

## References

- [Research 46 — identity and access stack](../research/46-identity-and-access-stack.md) — the Vault/Infisical/Bitwarden comparison and TPM notes
- [Research 22 — Infisical for homelab secret management](../research/22-infisical-for-homelab-secret-management.md)
- [Research 37 — TPM 2.0 and the fleet](../research/37-tpm2-hardware-and-fleet.md)
- Upstream: [Vault](https://developer.hashicorp.com/vault/docs) · [OpenBao](https://openbao.org/) · [Infisical](https://infisical.com/docs) · [Bitwarden Secrets Manager](https://bitwarden.com/products/secrets-manager/) · [SOPS](https://getsops.io/)
- [Idea 13 — FreeIPA domain controller](13-freeipa-domain-controller.md) · [idea 10 — internal CA + DNS + proxy stack](10-internal-ca-dns-stack.md) · [ADR 28 — fleet admin account](../decisions/28-fleet-admin-account-and-key.md)
