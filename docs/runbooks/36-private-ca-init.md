# Private CA — Offline Root and Intermediate Signing (Init + Annual Re-Sign)

> The offline half of the CA: a 10-year **root** generated on an air-gapped signing machine and kept on
> the **Kingston IronKey Locker+ 50** in a safe, plus the **root-signing of the intermediate CSR** the
> deploy host produced ([runbook 35 §6](35-deploy-step-ca.md)). Run §2 **once** to create the root,
> then **§4 annually** to re-sign the intermediate before it expires — ADR 38 sets the intermediate at
> **1 year**, so the **same TPM key** gets a fresh certificate from the **same root** each year.
> Decision: [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md); mechanics:
> [research 36 §4–§5](../research/36-step-ca-machine-identity.md); measured gate:
> [#141](https://github.com/jaroslaw-bagnicki/Homelab/issues/141).
>
> **"Air-gapped"** means no network of any kind — no cable, no Wi-Fi, no route out. The steps below run
> on a live-USB Linux boot (SystemRescue 13 or Ubuntu Live) used only for this ceremony, and powered
> off afterwards.
>
> ⚠ **The §1–§3 mechanics are rehearsed; no ceremony has been run against the real IronKey.** On
> 2026-10-11 root creation and signing were both exercised against a **throwaway software root** and a
> fake IronKey directory (nothing real touched, no trust distributed) — which is how the
> `--profile`-drops-SANs defect was found and the `--template` fix proven. **§1–§3 are now encapsulated
> in the offline signing kit**
> (`docs/private-ca-offline-signing/`), which is what the signing machine runs; the sections below keep
> the reasoning rather than repeat the commands. §4 and §5 remain *plans*.
>
> ⚠ **Order — one-way, purely offline.** Run **after** [runbook 35 §6](35-deploy-step-ca.md), which
> produces `intermediate_ca.csr`; this runbook signs it and hands back `intermediate_ca.crt`, which
> [runbook 35 §7](35-deploy-step-ca.md) installs. **No step here touches the LAN.**
>
> ⚠ **Scope.** Root distribution to the fleet and workstations is
> [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144) (out of scope); this runbook only
> produces the root certificate and the signed intermediate.

## Why

[ADR 34](../decisions/34-lan-tls-only.md) made every LAN service TLS-only and admitted the gap:
per-service self-signed certificates are *encrypted* but *unauthenticated*, so a LAN MITM still wins.
[ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) settles the fix as a **three-tier PKI**:
a **10-year root** that is never online, a **1-year intermediate** whose key is sealed in the `pve`
TPM so signing happens in hardware and the key never exists in the clear, and **short-lived leaves**
(24 h default, 7 d max) issued over ACME.

The root is the one irreplaceable secret. Compromising `pve` cannot forge a new intermediate, and if
`pve` or its TPM dies the root is untouched — the recovery is to **re-sign the intermediate**, not to
re-trust a new root. That model only holds if the root-key ceremony is done offline, so the root key
never touches an online host.

The `pve` TPM is an **Intel PTT firmware TPM**, not a discrete chip (measured 2026-10-04,
[research 37 §5](../research/37-tpm2-hardware-and-fleet.md)). A BIOS update, a `Clear PTT` or an NVRAM
reset can **destroy the sealed key** — so the annual re-sign in §4 and the recovery in §5 are expected
events, not emergencies.

## What changes

- **Offline root** — `Homelab Internal CA` root key generated on an air-gapped signing machine and
  stored **only** on the IronKey (Locker+ 50, an encrypted USB carrier kept in a safe). The root cert
  is public and is exported later for distribution ([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)).
- **Signed intermediate** — the CSR from [runbook 35 §6](35-deploy-step-ca.md) is signed here; the
  intermediate's private key never leaves the TPM, so only a public CSR and a public certificate cross
  the air gap.
- **A repeatable annual signing** — §3–§4 re-run each year against the same root and the same TPM key.

## Prerequisites

- [ ] [Runbook 35 §1–§6](35-deploy-step-ca.md) done — LXC 215 `ca` exists and
      `intermediate_ca.csr` has been generated from the TPM key.
- [ ] The `pve` TPM is present and **not owned by a previous deployment**. On second-hand hardware,
      run `Clear TPM` / `Clear PTT` in the BIOS first
      ([research 37 §5](../research/37-tpm2-hardware-and-fleet.md)).
- [ ] An air-gapped signing machine — booted from the **YUMI multiboot stick**, which carries the live
      ISO *and* the signing kit, so the IronKey is the only thing crossing the air gap besides it.
- [ ] The **offline signing kit** (`docs/private-ca-offline-signing/`) on that stick, with `step` in
      place ([01-building-step.md](../private-ca-offline-signing/01-building-step.md)).
- [ ] A place to record the **root fingerprint** (safe copy / password manager, not the repo).

---

## 1. Prepare the offline signing machine

The signing machine has no network, so `step` goes in place beforehand and travels on the boot stick
with the kit. [01-building-step.md](../private-ca-offline-signing/01-building-step.md) covers both
routes, and the [kit README](../private-ca-offline-signing/README.md) covers the machine end — boot
offline, copy the kit to `/tmp`, mount the IronKey.

## 2. Generate the 10-year root CA onto the IronKey

**The kit runs this** — [02-issuing-root-cert.md](../private-ca-offline-signing/02-issuing-root-cert.md):

```sh
./root.sh /mnt/ironkey
```

Run **only on the signing machine**, with the IronKey mounted. `root.sh` wraps
`step certificate create "Homelab Internal CA" <ironkey>/root_ca.crt <ironkey>/root_ca_key --profile
root-ca --not-after 87600h` and adds the guards a first-run step needs:

- **It refuses to run when a root already exists** — replacing a root is a **root rotation** with a full
  client re-trust, not a re-run. It also catches a half-written root pair left behind by a crashed run,
  which matters because `step` will not overwrite an existing output without a TTY, so simply re-running
  the raw command is not a way out.
- **It asserts the shape** before you leave the signing machine: `CA:TRUE` with `pathlen` ≥ 1, key
  usage `certSign` + `crlSign`, 10-year validity, and that the key file is actually `ENCRYPTED`.
- **It prints the fingerprint** to record, and stops rather than let you carry on if a check fails.

The reasoning it encodes:

- `87600h` = 10 years. **`--profile root-ca` is correct here and does not contradict §3's rule** — a
  profile rebuilds a certificate from its own defaults, so signing a *CSR* with one discards whatever
  the requester asked for. A root has nothing to discard: it needs no SANs (it is never a TLS server)
  and inherits nothing from a CSR (it is the trust anchor). The profile yields `CA:TRUE`, `pathlen:1`,
  `certSign` + `crlSign`.
- The root key is **passphrase-protected**, and that passphrase is written into the safe. Lose it and
  the root key is unusable — the only recovery is a new root plus a full re-trust of every client.
- Both files live **only** on the IronKey. The certificate is public and is exported later for
  distribution ([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)); the **key must never
  leave the IronKey**.
- The CA instance name / CN is `Homelab Internal CA`. The service's DNS name is `ca.internal`
  ([runbook 35 §6](35-deploy-step-ca.md)); they are separate.

> **Acceptance.** Every `root.sh` check reports OK and the fingerprint is recorded in the safe. Note
> that `"valid": false` in `step`'s JSON is normal for a self-signed root — there is no higher authority
> to validate it against, so `self_signed: true` is the check.

> **Backout (init only).** No trust has been distributed yet, so a wrong root is simply deleted and §2
> repeated. Once the root has been distributed ([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)),
> replacing it is a **root rotation** with a full client re-trust window — do not treat it as routine.

## 3. Offline-sign the intermediate CSR from runbook 35 §6

**The kit runs this** — [03-signing-csr.md](../private-ca-offline-signing/03-signing-csr.md). The CSR
and its template travel in the kit, so the IronKey is the only secret that crosses the air gap.

```sh
./sign.sh /mnt/ironkey
```

Insert the IronKey, sign the CSR, return it to the safe. `sign.sh` wraps
`step certificate sign --template intermediate-ca.tpl --not-after 8760h intermediate_ca.csr
<ironkey>/root_ca.crt <ironkey>/root_ca_key`, then **machine-checks** the result rather than leaving it
to an eye: `step certificate verify` against the root, plus `is_ca`, `pathlen:0`, key usage and the
SANs. It writes to a temporary file and only moves it into place on success, so a failed run cannot
leave a half-written certificate to carry home.

- **`--template`, never `--profile intermediate-ca`.** A profile rebuilds the certificate from its own
  defaults and **silently drops the CSR's SANs** (measured 2026-10-11). The intermediate doubles as
  step-ca's TLS server certificate, so a certificate without SANs passes an issuer/validity check and
  then fails *every* trusted request with a hostname-verification error — including
  [runbook 35 §7](35-deploy-step-ca.md)'s health check. The template makes the **signer** assert the
  shape (`CA:TRUE, pathlen:0`; key usage `certSign, crlSign`; SANs `ca.internal`, `192.168.2.215`)
  rather than inheriting it from the requester.
- `8760h` = 1 year (ADR 38). The root is used for exactly this operation and nothing else.
- **Lock/unmount the IronKey and return it to the safe** before the signing machine is powered off.
- Carry `intermediate_ca.crt` and a copy of `root_ca.crt` back to the `ca` guest — both are public;
  [runbook 35 §7](35-deploy-step-ca.md) installs them and starts the service. The kit copies them back
  onto the boot stick.

> **Acceptance.** `step certificate inspect intermediate_ca.crt` shows: issuer = the root's CN,
> ~1-year validity, **`CA:TRUE, pathlen:0`**, and the **Subject Alternative Name**
> `DNS:ca.internal` + `IP Address:192.168.2.215`. The IronKey is locked and back in the safe.

> **Backout.** Discard the signed certificate and repeat §3. The root key is unaffected.

> **Rehearsal record — 2026-10-11 (`ca` guest, throwaway root in `/tmp`).** Runbook 35 §6's real CSR
> was signed with a temporary root, then the root and the signed certificate were deleted. Results:
> `--profile intermediate-ca` → `CA:TRUE, pathlen:0` + correct key usage, **no SAN extension**;
> `--profile csr` → SANs preserved, but **no** `CA:TRUE` and no key usage; `--template
> intermediate-ca.tpl` → all three together (`Digital Signature, Certificate Sign, CRL Sign` /
> `CA:TRUE, pathlen:0` / `DNS:ca.internal` + `IP Address:192.168.2.215`). Two template drafts were
> rejected first and are worth knowing: a `sans` list of plain strings fails with
> `cannot unmarshal string into Certificate.sans.0 of type x509util.SubjectAlternativeName`, and a
> nested `{"dnsNames":…}` object is **silently ignored**, yielding a certificate with no SAN at all —
> the working form uses the top-level `dnsNames` / `ipAddresses` fields.

## 4. Annual re-sign

ADR 38 sets the intermediate at **1 year**, so roughly **annually** (before it expires) the same root
re-signs a fresh certificate for the **same TPM key**:

1. On the `ca` guest, **re-run [runbook 35 §6](35-deploy-step-ca.md)'s CSR task** — a fresh
   `intermediate_ca.csr` from the existing TPM key. Do **not** recreate the key.
2. Sign it with the kit — `./sign.sh /mnt/ironkey`
   ([03-signing-csr.md](../private-ca-offline-signing/03-signing-csr.md)).
3. Install it and restart the service ([runbook 35 §7](35-deploy-step-ca.md)).

- **No new key, no root re-issue, no client re-trust** — the fleet and workstations keep trusting the
  same root, so there is no propagation window. This is the payoff of the offline root.
- Set a calendar reminder ~30 days before expiry. The intermediate's actual expiry is in
  `step certificate inspect intermediate_ca.crt`.

> **Acceptance.** The new intermediate chain verifies ([runbook 35 §7](35-deploy-step-ca.md)); the old
> certificate is retired only after the new one passes; the new expiry is recorded.

> **Backout.** Revert to the previous `intermediate_ca.crt` before it expires; re-run §3 and
> [runbook 35 §7](35-deploy-step-ca.md).

## 5. PTT key-loss recovery

The `pve` TPM is an **Intel PTT firmware TPM** (measured 2026-10-04,
[research 37 §5](../research/37-tpm2-hardware-and-fleet.md)). Any of these **destroys the sealed key**:

- a BIOS/firmware update,
- `Clear PTT` in BIOS setup (**Security → PTT security → Clear PTT**),
- an NVRAM reset.

Recovery is the same flow on demand:

1. On the controller, run the workload with `-e step_ca_reset=true`
   ([runbook 35 §6](35-deploy-step-ca.md)) — this clears the stale TPM blob, CSR, public key and
   intermediate certificate (which the create guards would otherwise keep), then creates a **fresh**
   intermediate key in the (possibly cleared) TPM and emits a new CSR.
2. Sign it with the **same** offline root — the kit's `./sign.sh /mnt/ironkey`
   ([03-signing-csr.md](../private-ca-offline-signing/03-signing-csr.md)).
3. Install the returned certificate(s) and re-run the workload ([runbook 35 §7](35-deploy-step-ca.md));
   the role restarts `step-ca` on the changed intermediate.

- The **root is unaffected**, so there is **no client re-trust**. A PTT wipe costs a re-signing
  ceremony, not a re-trust.
- Adjust the annual reminder after an unexpected wipe.

> **Acceptance.** The CA again issues chain-verified leaves.

> **Backout.** None needed — the root is untouched; repeat the steps if the first attempt fails.

---

## Verification Checklist

Executed on: **never** — no ceremony has been run against the real IronKey. §1–§3's mechanics are
rehearsed and encapsulated in the kit (`docs/private-ca-offline-signing/`), which is what the signing
machine runs; record the date and each result here when the real ceremony is first performed.

- [ ] §1 signing machine air-gapped; kit on the stick with `step` in place; `./step version` runs
- [ ] §2 root created with `CA:TRUE`, `pathlen:1`, ~10y; stored only on the IronKey; fingerprint and passphrase in the safe
- [ ] §3 intermediate CSR from runbook 35 §6 signed by the offline root; the kit's checks all pass; IronKey returned to the safe
- [ ] §4 annual re-sign scheduled
- [ ] §5 PTT-loss recovery documented and understood

## Follow-ups

- **Deploy runbook** — [runbook 35](35-deploy-step-ca.md) installs the signed certificate and runs the CA.
- **Root distribution** — [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144) (out of scope).
- **YubiKey PIV upgrade** — ADR 38's planned custody move: make the root non-exportable and **destroy
  every exportable copy**; a ceremony, not a file move (out of scope).

## References

- [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — the three-tier hierarchy, custody, and 1-year intermediate
- [Research 36 §4–§5](../research/36-step-ca-machine-identity.md) — TPM/KMS mechanics, the LXC recipe
- [Research 37 §5](../research/37-tpm2-hardware-and-fleet.md) — the `pve` Intel PTT fTPM and key-loss risk
- [Issue #141](https://github.com/jaroslaw-bagnicki/Homelab/issues/141) — the measured TPM custody gate
- [Runbook 35](35-deploy-step-ca.md) — the on-host deployment this ceremony feeds
- [Offline signing kit](../private-ca-offline-signing/README.md) — the scripts and the instructions
  for the signing machine that §1–§3 now point at
- [Runbook 28](28-pve-proxmox-node.md) (Proxmox base) · [ADR 34](../decisions/34-lan-tls-only.md) (TLS-only) ·
  [ADR 37](../decisions/37-lan-name-space-internal.md) (`.internal`)
