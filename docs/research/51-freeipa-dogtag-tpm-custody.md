# 51 — FreeIPA Dogtag CA Key Custody — Is the Host TPM a Fit?

**Status**: 📝 Research — parked, not pursued for M1/M2
**Date**: 2026-11-01
**Question**: Can FreeIPA's Dogtag CA private key live in the `pve` host TPM through `tpm2-pkcs11`, and does that improve M1/M2 enough to justify the change?
**Related**: [ADR 42](../decisions/42-pki-topology-sibling-cas.md) · [ADR 43](../decisions/43-freeipa-domain-realm.md) · [issue #164](https://github.com/jaroslaw-bagnicki/Homelab/issues/164) · [research 46 §6](46-identity-and-access-stack.md) · [research 37](37-tpm2-hardware-and-fleet.md) · [runbook 35](../runbooks/35-deploy-step-ca.md)

> **Parked 2026-11-01.** TPM-backed PKCS#11 keys in Dogtag are **not pursued** for M1/M2. Standard
> FreeIPA uses the Dogtag CA key on disk with `ipa-backup`; revisit only if hardware-backed CA-key
> custody becomes a requirement.

> **This is a research record, not a proof of concept.** The output is a support-and-risk assessment,
> not a deployment recipe. An earlier draft turned it into an implementation runbook; that was the wrong
> artefact and has been withdrawn. No live changes were made.

## Executive summary

**The host TPM is not a supported or sensible place for FreeIPA's Dogtag CA key in this lab.**

1. **FreeIPA's HSM support is real but narrow.** It is an all-or-nothing CA/KRA mode for a
   PKCS#11 token, designed around network-accessible hardware HSMs so replicas can share the key.
   It supports RSA only, and only Thales nFast and Gemalto Luna have FreeIPA SELinux policy.
2. **Dogtag's supported-HSM list does not include `tpm2-pkcs11`.** The documented HSM options are
   Thales nFast Connect, Gemalto Luna SA, Nitrokey HSM and SoftHSM. `tpm2-pkcs11` is not listed.
3. **`tpm2-pkcs11` is a local software token over a TPM, not a shareable HSM.** Its store is a
   SQLite database on disk; objects live under a persistent primary key in the TPM owner hierarchy.
   There is no network-sharing model for replicas, and the store plus the TPM objects are one unit.
4. **A TPM-resident CA key is non-exportable.** FreeIPA's HSM design leaves HSM backup/restore to the
   operator. `ipa-backup` captures IPA files and data, not a portable HSM key. Off-host restore cannot
   recover the key; recovery becomes re-issue the IPA CA and re-trust it.
5. **On this hardware the TPM belongs to `step-ca`.** The Wyse 5070 has Intel PTT, a firmware TPM.
   Proxmox VMs get an emulated vTPM (`swtpm`), not the host TPM; physical TPM access is an LXC-only
   pattern. `step-ca` already seals its intermediate and SSH CA keys there, so a second CA on the same
   TPM creates a shared failure domain and a coexistence risk with no upstream support statement.

**Recommendation:** keep the Dogtag CA key on disk and rely on `ipa-backup` for M2. If
hardware-backed CA-key custody is a hard requirement, evaluate a **Dogtag-supported HSM** — the
Nitrokey HSM is the low-cost candidate — as a separate research question. Do not treat a vTPM as a
substitute for the physical TPM.

## What Dogtag actually does in this lab

[ADR 42](../decisions/42-pki-topology-sibling-cas.md) makes Dogtag a **sibling** of `step-ca` under
the offline root; [ADR 43](../decisions/43-freeipa-domain-realm.md) narrows its scope.

| Dogtag/IPA CA issues | `step-ca` issues |
|---|---|
| `HTTP/ipa.internal` — IPA WebUI | LAN TLS for Caddy / `*.internal` |
| `ldap/ipa.internal` — Directory Server / LDAPS for Authentik | SSH host and user certificates |
| `krb5/ipa.internal` — PKINIT | Fleet host certificates |
| IPA client host/service certificates via `certmonger` | Anything consumed by non-IPA services |
| The IPA CA itself (sibling under the fleet root, or self-signed interim) | — |

Dogtag is the **domain CA**, not the fleet CA. That lowers the blast radius of a Dogtag compromise
compared with `step-ca`, but it does not make the key disposable: under the same root and without
name constraints, a compromised Dogtag CA can still mint certificates for names the root covers.

## Evidence

### 1. FreeIPA HSM support is all-or-nothing and network-HSM-shaped

The FreeIPA HSM design document states:

- the Dogtag CA and KRA can use an HSM for **private key generation and storage** via a
  PKCS#11 shared library;
- installing with an HSM is **all or nothing** — CA and KRA are both on the HSM, with no mixing;
- **only RSA keys are supported**;
- **replica key sharing is HSM-specific and generally assumes a network-accessible device**;
- FreeIPA ships SELinux policy only for **Thales nFast** and **Gemalto Luna**;
- HSM backup is explicitly **left to the operator** — “an HSM install creates no additional files;
  management of the HSM is left as an exercise for the user.” For the SoftHSM development case, the
  operator must manually restore the token directory.

Source: FreeIPA `doc/designs/hsm.md` (upstream `freeipa/freeipa`, read 2026-11-01).

### 2. Dogtag's supported-HSM list excludes `tpm2-pkcs11`

The Dogtag PKI documentation lists four supported HSM paths:

| HSM | Listed by Dogtag |
|---|---|
| Thales nFast Connect 6000 | ✅ |
| Gemalto Luna SA | ✅ |
| Nitrokey HSM | ✅ |
| SoftHSM | ✅ (development) |
| TPM 2.0 via `tpm2-pkcs11` | ❌ |

Source: Dogtag PKI “Supported HSMs” documentation (read 2026-11-01). `tpm2-pkcs11` is a PKCS#11
provider, but “provides a PKCS#11 interface” is not the same as “a Dogtag-supported token”. Dogtag
tests and SELinux policy are written around the listed devices.

### 3. `tpm2-pkcs11` is a local token with an on-disk store

The upstream architecture document describes:

- a **store** — a SQLite database on disk holding the metadata required for the PKCS#11 interface;
- a **persistent primary key in the TPM owner hierarchy** under which all objects are stored;
- the primary-key auth value stored **on disk**, protected only by filesystem access controls;
- token users' PINs unsealing an AES wrapping key that encrypts object auth values.

The private key material is non-exportable, but the token is **not** a network HSM and has no
replica-sharing model. The store and the TPM objects are a single unit: copying the SQLite store to
another host does not carry the TPM objects with it.

Source: `tpm2-software/tpm2-pkcs11`, `docs/ARCHITECTURE.md` and `README.md` (read 2026-11-01).

### 4. Proxmox: vTPM is emulated; physical TPM means LXC

Proxmox VE 9.2's QEMU documentation says a VM TPM is a `tpmstate` volume (swtpm) and that, compared
with a physical TPM, an emulated one **does not provide any real security benefits** because its state
is a regular volume that can be edited by anyone with access. Physical TPM passthrough to a VM is not
a Proxmox feature; the supported path for giving a guest the host PTT is the LXC `/dev/tpmrm0`
bind-mount pattern already used by the `ca` guest.

The host TPM is an **Intel PTT firmware TPM**, not a discrete chip that can be assigned to a VM.
Passing `/dev/tpmrm0` to a VM through unsupported custom QEMU arguments would still share the same
global TPM state — PCRs, NV indices and hierarchy auth — with the host and `ca`.

Sources: Proxmox VE 9.2 QEMU documentation (TPM section, read 2026-11-01); [research 37](37-tpm2-hardware-and-fleet.md); [runbook 35](../runbooks/35-deploy-step-ca.md).

### 5. `step-ca` already owns the host TPM's failure domain

`step-ca` seals its intermediate and SSH CA keys to the `pve` TPM. A second CA on the same TPM would:

- share the **same owner hierarchy** and TPM state;
- make a TPM clear or ownership change take out **both** the fleet CA and the IPA CA;
- add a local `tpm2-pkcs11` store to the backup problem;
- have no upstream support statement for coexistence with `step-ca`'s `tpmkms` signer.

The TPM resource manager permits concurrent host processes, but it does not isolate PCRs, NV storage
or hierarchy policy between them. “Shared access is possible” is not the same as “independent
failure domains”.

## Option analysis

| Option | Fit | Constraints | Verdict |
|---|---|---|---|
| **Disk key + `ipa-backup`** | Standard FreeIPA; restorable; no extra hardware | Key exists on the VM disk; at-rest protection depends on the disk/VM encryption | **Recommended for M1/M2** |
| **Dogtag-supported HSM** (Nitrokey HSM; Luna/nFast) | Hardware-backed CA key; Dogtag-listed | Cost/hardware; FreeIPA SELinux policy documented only for nFast/Luna; HSM backup/replica model still operator-owned | Separate research if hardware custody is mandatory |
| **Host TPM via `tpm2-pkcs11`** | Uses the existing `pve` TPM | Not a Dogtag-supported HSM; local-only; non-exportable; shares the `step-ca` failure domain; off-host restore impossible | **Reject as a default** |
| **VM + vTPM** | Guest sees a TPM 2.0 device | Emulated, not hardware-backed; Proxmox says no real security benefit | Only if a TPM *device* is a checkbox, not for key custody |
| **TPM-backed LUKS on the VM disk** | Protects the disk at rest; keeps `ipa-backup` working | Not a CA key in the TPM; vTPM state sits with the VM disk | Useful for disk-theft protection, not CA-key custody |

## What this means for #164 M1/M2

| Item | Effect |
|---|---|
| M1 guest shape | A normal VM (or LXC) without host-TPM access; the TPM is not a prerequisite |
| Dogtag CA key | On disk, protected by the guest disk/VM encryption; captured by `ipa-backup` |
| M2 restore | Off-host restore remains possible; no non-exportable key to lose |
| Hardware custody | A separate spike for a Dogtag-supported HSM, not the host TPM |

## Recommendation

1. **M1/M2:** install standard FreeIPA with the Dogtag CA key on disk, protected by the VM disk and
   captured by `ipa-backup`. This keeps the M2 restore model intact and does not touch `step-ca`.
2. **If hardware-backed CA-key custody is mandatory:** scope a separate spike for a **Dogtag-supported
   HSM** (Nitrokey HSM is the low-cost candidate). Do not use the host TPM for Dogtag.
3. **If the physical TPM remains non-negotiable:** accept that this is an unsupported configuration
   and that the IPA CA key becomes non-exportable. M2 then changes to “same-host restore only;
   off-host/TPM-loss means re-issue the IPA CA and re-trust”, which needs an ADR amendment before
   implementation. A prototype would not remove the support-matrix or backup problems — those are the
   findings.

## Why not a proof of concept

A POC could show that `ipa-server-install --token-name` accepts a `tpm2-pkcs11` token on one
AlmaLinux build. It would not change the facts that:

- the token is not on Dogtag's supported list;
- the CA key cannot be backed up in portable form;
- replica sharing has no TPM equivalent;
- the host TPM is already the `step-ca` trust anchor.

Those are architectural and support-lifecycle constraints, not integration bugs.

## If a lab experiment is later approved

A **new, explicit research task** may test the integration in a throwaway guest with a software TPM
first. It should answer only what desk research cannot:

- which FreeIPA/Dogtag version accepts `--token-name` / `--token-library-path` on AlmaLinux 9;
- whether Dogtag uses the token or silently falls back to NSS;
- whether `tpm2_ptool init` on the host TPM disturbs `step-ca`;
- what `ipa-backup` actually captures when the CA key is in a token.

That experiment is out of scope here and must not be run on the production TPM without a maintenance
window and an accepted DR change. This document deliberately contains no implementation steps.

## References

- FreeIPA HSM design — `freeipa/freeipa`, `doc/designs/hsm.md` (read 2026-11-01)
- Dogtag PKI — [Supported HSMs](https://www.dogtagpki.org/wiki/HSM) (read 2026-11-01)
- `tpm2-pkcs11` — `docs/ARCHITECTURE.md`, `docs/README.md`, `docs/INTEROPERABILITY.md` (read 2026-11-01)
- Proxmox VE 9.2 QEMU documentation — TPM section (read 2026-11-01)
- [Research 37 — TPM 2.0 hardware and fleet](37-tpm2-hardware-and-fleet.md)
- [Research 46 §6 — claims to verify](46-identity-and-access-stack.md)
- [ADR 42 — PKI topology](../decisions/42-pki-topology-sibling-cas.md) · [ADR 43 — FreeIPA domain](../decisions/43-freeipa-domain-realm.md)
- [Runbook 35 — `step-ca` on the `ca` guest](../runbooks/35-deploy-step-ca.md)
