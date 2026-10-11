# Private CA — Offline Root and Intermediate Signing (Init + Annual Re-Sign)

> The offline half of the CA: a 10-year **root** generated on an air-gapped signing machine (a live-USB
> Linux boot with no network at all) and kept on the **Kingston IronKey Locker+ 50** in a safe, plus the
> **root-signing of the intermediate CSR** the deploy host produced. §2 runs **once**; §4 re-runs
> annually, before the 1-year intermediate expires. Decision:
> [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md); mechanics:
> [research 36 §4–§5](../research/36-step-ca-machine-identity.md).
>
> ⚠ **Offline throughout.** It runs between [runbook 35 §6](35-deploy-step-ca.md) (makes the CSR) and
> [§7](35-deploy-step-ca.md) (installs the signed certificate). §1–§3 run the
> [kit](../private-ca-offline-signing/README.md) and are rehearsed on throwaway material only; §4 and
> §5 have never been run. Root distribution is [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144).

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

Run **only on the signing machine**, with the IronKey mounted:

```sh
./root.sh /mnt/ironkey
```

It wraps `step certificate create` with `--profile root-ca --not-after 87600h`, refuses to run if a root
already exists (replacing one is a full client re-trust, not a re-run), then checks its own output —
`CA:TRUE`, `pathlen:1`, `certSign` + `crlSign`, 10 years, key `ENCRYPTED` — and prints the fingerprint
to record. `"valid": false` in that JSON is normal for a root; `self_signed: true` is the check.

The root key never leaves the IronKey. The certificate is public and is exported later for distribution
([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)). Passphrase handling, the refusals,
and why `--profile root-ca` is right here but wrong in §3:
[02-issuing-root-cert.md](../private-ca-offline-signing/02-issuing-root-cert.md).

## 3. Offline-sign the intermediate CSR from runbook 35 §6

```sh
./sign.sh /mnt/ironkey
```

It signs `intermediate_ca.csr` with the template and a 1-year lifetime, then machine-checks the result —
`certificate verify` against the root, plus `is_ca`, `pathlen:0`, key usage and the SANs — instead of
leaving it to an eye. A failed run cannot leave a half-written certificate to carry home.

**Use `--template`, never `--profile intermediate-ca`**: a profile drops the CSR's SANs, and the
intermediate doubles as step-ca's TLS certificate, so the result would pass an issuer check and then
fail every request. Then unmount the IronKey, return it to the safe, and carry `intermediate_ca.crt`
and `root_ca.crt` back for [runbook 35 §7](35-deploy-step-ca.md).

Details, the required certificate shape and the refusals:
[03-signing-csr.md](../private-ca-offline-signing/03-signing-csr.md).

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
