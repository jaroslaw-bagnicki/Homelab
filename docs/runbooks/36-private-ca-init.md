# Private CA — Offline Root and Intermediate Signing (Init + Annual Re-Sign)

> The offline half of the CA: a 10-year **root** generated on an air-gapped signing island and kept on
> the **Kingston IronKey Locker+ 50** in a safe, plus the **root-signing of the intermediate CSR** the
> deploy host produced ([runbook 35 §5](35-deploy-step-ca.md)). Run §2 **once** to create the root,
> then **§4 annually** to re-sign the intermediate before it expires — ADR 38 sets the intermediate at
> **1 year**, so the **same TPM key** gets a fresh certificate from the **same root** each year.
> Decision: [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md); mechanics:
> [research 36 §4–§5](../research/36-step-ca-machine-identity.md); measured gate:
> [#141](https://github.com/jaroslaw-bagnicki/Homelab/issues/141).
>
> ⚠ **This runbook is unexecuted.** It is written from ADR 38, research 36–37, and the
> [#141](https://github.com/jaroslaw-bagnicki/Homelab/issues/141) gate, but **no step below has been run
> as written**. Every command is a *plan*; treat each as unverified until the first execution records
> its result. Gate-measured facts are marked **(measured #141)**.
>
> ⚠ **Order — one-way, purely offline.** Run **after** [runbook 35 §5](35-deploy-step-ca.md), which
> produces `intermediate_ca.csr`; this runbook signs it and hands back `intermediate_ca.crt`, which
> [runbook 35 §6](35-deploy-step-ca.md) installs. **No step here touches the LAN.**
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

- **Offline root** — `Homelab Internal CA` root key generated on an air-gapped signing island and
  stored **only** on the IronKey (Locker+ 50, an encrypted USB carrier kept in a safe). The root cert
  is public and is exported later for distribution ([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)).
- **Signed intermediate** — the CSR from [runbook 35 §5](35-deploy-step-ca.md) is signed here; the
  intermediate's private key never leaves the TPM, so only a public CSR and a public certificate cross
  the air gap.
- **A repeatable annual signing** — §3–§4 re-run each year against the same root and the same TPM key.

## Prerequisites

- [ ] [Runbook 35 §1–§5](35-deploy-step-ca.md) done — LXC 215 `ca` exists and
      `intermediate_ca.csr` has been generated from the TPM key.
- [ ] The `pve` TPM is present and **not owned by a previous deployment**. On second-hand hardware,
      run `Clear TPM` / `Clear PTT` in the BIOS first
      ([research 37 §5](../research/37-tpm2-hardware-and-fleet.md)).
- [ ] An air-gapped signing island (a live USB that will never hold the root key on its internal disk),
      with the IronKey available.
- [ ] A second, ordinary USB stick to carry the CSR/certificate across the air gap — **never the
      IronKey**, which does not leave safe custody.
- [ ] A place to record the **root fingerprint** (safe copy / password manager, not the repo).

## Tooling and measurements

| Fact | Source |
|---|---|
| Stock `step-ca` contains `tpmkms` — `CGO_ENABLED=0`, statically linked, zero PCSC; no custom build needed | measured #141 |
| The intermediate key is a **file** (`$STEPPATH/tpm/key-<name>.tpmobj`, JSON), not TPM NV — useless off the `pve` TPM and required on disk for the service | measured #141 |
| `step ca init` cannot bootstrap a TPM-backed CA; the deploy runbook stages the TPM key + `ca.json` instead | measured #141 |
| `step certificate create` prompts before overwriting an existing output — fails without a TTY; write to a fresh path and move into place | measured #141 |
| The `step-ca` release tarball arrived **truncated** on one download; the truncated binary segfaulted and gave a false "broken" result — **verify `checksums.txt`** | measured #141 |

Tooling is installed from the current upstream release and **checksum-verified**; no version is pinned.

---

## 1. Prepare the offline signing island

The island has **no network**, so the CLI must be fetched on a **connected staging machine first**,
verified there, and carried over on ordinary removable media — never the IronKey. Only then boot the
island with no LAN or internet route and install from the carried archive.

```sh
# 1. On the connected staging machine — download and verify before carrying (measured #141:
#    a truncated download produced a false "step-ca is broken" result)
wget https://dl.smallstep.com/gh-release/cli/gh-release-<current>/step_linux_amd64.tar.gz
wget https://dl.smallstep.com/gh-release/cli/gh-release-<current>/checksums.txt
sha256sum -c <(grep step_linux_amd64.tar.gz checksums.txt)

# 2. carry the archive on ordinary media, then on the air-gapped island:
tar -xzf step_linux_amd64.tar.gz
./step version
```

- Install nothing else on the island. The `step-kms-plugin`/`libpcsclite1` requirement is on the
  **CA host** ([runbook 35 §5](35-deploy-step-ca.md)) — the root is an ordinary file on the IronKey.
- Carry the archive on ordinary media; **never the IronKey**, which holds only the root.
- Unlock the IronKey and mount it. **Never** leave the root key on the island's disk.

> **Acceptance.** `step version` runs on the island; the island has no route to `192.168.2.0/24` or
> the internet; the IronKey mounts read/write.

> **Backout.** Reboot the island from its own disk; wipe the live USB. Nothing was written yet.

## 2. Generate the 10-year root CA onto the IronKey

Run **only on the island**, with the IronKey mounted. This is a first-run step — **do not overwrite an
existing root**; if one already exists, skip to §3.

```sh
step certificate create "Homelab Internal CA" \
  /mnt/ironkey/root_ca.crt /mnt/ironkey/root_ca_key \
  --profile root-ca --not-after 87600h
# the key is passphrase-protected at the prompt; record the passphrase in the safe

# record the root fingerprint somewhere durable OUTSIDE the repo
step certificate fingerprint /mnt/ironkey/root_ca.crt
```

- `87600h` = 10 years. `--profile root-ca` sets `CA:TRUE` and path-length constraints.
- Both files live **only** on the IronKey. The certificate is public once distributed
  ([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)); the **key must never leave the
  IronKey**.
- The CA instance name / CN is `Homelab Internal CA`. The service's DNS name is `ca.internal`
  ([runbook 35 §5](35-deploy-step-ca.md)); they are separate.

> **Acceptance.** `step certificate inspect /mnt/ironkey/root_ca.crt` shows `CA:TRUE`, a path-length
> constraint, and a ~10-year validity; the fingerprint is recorded in the safe.

> **Backout (init only).** No trust has been distributed yet, so a wrong root is simply deleted and §2
> repeated. Once the root has been distributed ([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)),
> replacing it is a **root rotation** with a full client re-trust window — do not treat it as routine.

## 3. Offline-sign the intermediate CSR from runbook 35 §5

Carry `intermediate_ca.csr` from the `ca` guest to the island on the ordinary USB stick. Insert the
IronKey, sign the CSR, and return it to the safe.

```sh
step certificate sign --profile intermediate-ca --not-after 8760h \
  intermediate_ca.csr \
  /mnt/ironkey/root_ca.crt /mnt/ironkey/root_ca_key \
  > intermediate_ca.crt

step certificate inspect intermediate_ca.crt   # issuer = root CN, ~1 year, CA:TRUE
```

- `8760h` = 1 year (ADR 38). The root is used for exactly this operation and nothing else.
- **Lock/unmount the IronKey and return it to the safe** before the island is powered off.
- Carry `intermediate_ca.crt` and a copy of `root_ca.crt` back to the `ca` guest — both are public;
  [runbook 35 §6](35-deploy-step-ca.md) installs them and starts the service.

> **Acceptance.** `step certificate inspect intermediate_ca.crt` shows the root as issuer and a
> ~1-year validity; the IronKey is locked and back in the safe.

> **Backout.** Discard the signed certificate and repeat §3. The root key is unaffected.

## 4. Annual re-sign

ADR 38 sets the intermediate at **1 year**, so roughly **annually** (before it expires) the same root
re-signs a fresh certificate for the **same TPM key**:

1. On the `ca` guest, **re-run [runbook 35 §5](35-deploy-step-ca.md)'s CSR task** — a fresh
   `intermediate_ca.csr` from the existing TPM key. Do **not** recreate the key.
2. Sign it here (§3).
3. Install it and restart the service ([runbook 35 §6](35-deploy-step-ca.md)).

- **No new key, no root re-issue, no client re-trust** — the fleet and workstations keep trusting the
  same root, so there is no propagation window. This is the payoff of the offline root.
- Set a calendar reminder ~30 days before expiry. The intermediate's actual expiry is in
  `step certificate inspect intermediate_ca.crt`.

> **Acceptance.** The new intermediate chain verifies ([runbook 35 §6](35-deploy-step-ca.md)); the old
> certificate is retired only after the new one passes; the new expiry is recorded.

> **Backout.** Revert to the previous `intermediate_ca.crt` before it expires; re-run §3 and
> [runbook 35 §6](35-deploy-step-ca.md).

## 5. PTT key-loss recovery

The `pve` TPM is an **Intel PTT firmware TPM** (measured 2026-10-04,
[research 37 §5](../research/37-tpm2-hardware-and-fleet.md)). Any of these **destroys the sealed key**:

- a BIOS/firmware update,
- `Clear PTT` in BIOS setup (**Security → PTT security → Clear PTT**),
- an NVRAM reset.

Recovery is the same flow on demand:

1. On the controller, run the workload with `-e step_ca_reset=true`
   ([runbook 35 §5](35-deploy-step-ca.md)) — this clears the stale TPM blob, CSR, public key and
   intermediate certificate (which the create guards would otherwise keep), then creates a **fresh**
   intermediate key in the (possibly cleared) TPM and emits a new CSR.
2. Sign it here (§3) with the **same** offline root.
3. Install the returned certificate(s) and re-run the workload ([runbook 35 §6](35-deploy-step-ca.md));
   the role restarts `step-ca` on the changed intermediate.

- The **root is unaffected**, so there is **no client re-trust**. A PTT wipe costs a re-signing
  ceremony, not a re-trust.
- Adjust the annual reminder after an unexpected wipe.

> **Acceptance.** The CA again issues chain-verified leaves.

> **Backout.** None needed — the root is untouched; repeat the steps if the first attempt fails.

---

## Verification Checklist

Executed on: **never** — this runbook is unexecuted. Record the date and each result when it is first
run; update the measured/planned labels above as facts are confirmed.

- [ ] §1 island air-gapped; `step` installed; checksums verified
- [ ] §2 root created with `CA:TRUE`, ~10y; stored only on the IronKey; fingerprint recorded
- [ ] §3 intermediate CSR from runbook 35 §5 signed by the offline root; IronKey returned to the safe
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
- [Runbook 28](28-pve-proxmox-node.md) (Proxmox base) · [ADR 34](../decisions/34-lan-tls-only.md) (TLS-only) ·
  [ADR 37](../decisions/37-lan-name-space-internal.md) (`.internal`)
