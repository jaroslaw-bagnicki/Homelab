# Private CA — Offline Root and TPM-Bound Intermediate (Init + Annual Re-Sign)

> Create the fleet private CA's **trust anchor**: a 10-year **root** generated offline and kept on the
> **Kingston IronKey Locker+ 50** in a safe, and a 1-year **intermediate** whose private key is generated
> **inside the TPM 2.0 on `pve`** (an Intel PTT firmware TPM) and signed by that offline root. Run once
> to create the CA, then **re-run annually** to re-sign the intermediate before it expires. Decision:
> [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md); mechanics:
> [research 36 §4–§5](../research/36-step-ca-machine-identity.md) and the measured gate in
> [#141](https://github.com/jaroslaw-bagnicki/Homelab/issues/141).
>
> ⚠ **This runbook is unexecuted.** It is written from the decision (ADR 38), research 36–37, and the
> [#141](https://github.com/jaroslaw-bagnicki/Homelab/issues/141) gate — which measured the TPM mechanics
> on `pve` — but **no step below has been run as written**. Every command is a *plan*; treat each as
> unverified until the first execution records its result. Facts the gate measured are marked
> **(measured #141)**.
>
> ⚠ **Scope / split.** This is the **offline ceremony** — the root and the intermediate key only. The
> one-off on-host deployment (LXC, native systemd service, ACME) is
> [runbook 36](36-deploy-step-ca.md). The two interleave once: **create the LXC
> ([runbook 36 §1–§2](36-deploy-step-ca.md)) before §3 below**, because the intermediate key lives in
> the TPM bound to that container; deploy the service ([runbook 36 §3–§6](36-deploy-step-ca.md))
> **after** §5 below. Root distribution to the fleet is
> [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144), proxy wiring is
> [#142](https://github.com/jaroslaw-bagnicki/Homelab/issues/142), and the first migrated service is
> [#143](https://github.com/jaroslaw-bagnicki/Homelab/issues/143) — all out of scope here.

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
reset can **destroy the sealed key** — so the annual re-sign in §8 and the recovery in §9 are expected
events, not emergencies.

## What changes

- **Offline root** — `Homelab Internal CA` root key generated on an air-gapped signing island and
  stored **only** on the IronKey (Locker+ 50, an encrypted USB carrier kept in a safe). The root cert
  is public and is exported later for distribution ([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)).
- **TPM-bound intermediate** — a 1-year intermediate key created inside `/dev/tpmrm0` on the `pve`
  host and passed into LXC 215 `ca` ([runbook 36](36-deploy-step-ca.md)); its certificate is signed by
  the offline root.
- **A sealed key blob** — `tpmkms` keeps the key material as a JSON blob on disk
  (`key-<name>.tpmobj`), **not** in TPM NV storage and **not** as a private-key file. It is unusable
  without the TPM and unrecoverable without the file, so it is backed up with the deployment (§7).
- **A repeatable annual ceremony** — §3–§6 re-run each year against the same root.

## Prerequisites

- [ ] `pve` base-provisioned — Proxmox VE + `fleetadm` ([runbook 28](28-pve-proxmox-node.md)).
- [ ] LXC 215 `ca` created with the TPM passed through ([runbook 36 §1–§2](36-deploy-step-ca.md)) —
      required before §3.
- [ ] The `pve` TPM is present and **not owned by a previous deployment**. On second-hand hardware,
      run `Clear TPM` / `Clear PTT` in the BIOS first
      ([research 37 §5](../research/37-tpm2-hardware-and-fleet.md)).
- [ ] An air-gapped signing island (a live USB that will never hold the root key on its internal disk),
      with the IronKey available.
- [ ] A second, ordinary USB stick to carry the intermediate CSR/cert between the island and the CA
      host — **never the IronKey**, which does not leave safe custody.
- [ ] A place to record the **root fingerprint** (safe copy / password manager, not the repo).

## Tooling and measurements

| Fact | Source |
|---|---|
| Stock `step-ca` contains `tpmkms` — `CGO_ENABLED=0`, statically linked, zero PCSC; no custom build needed | measured #141 |
| `step-kms-plugin` is a CGO build linked against `libpcsclite.so.1`, so **`libpcsclite1`** is required for `step kms …` (TPM-only work) when it is absent; `step-ca` itself has no PCSC dependency | measured #141 |
| `tpmkms` stores the sealed key as a **file** (`$STEPPATH/tpm/key-<name>.tpmobj`, JSON), not TPM NV; `ca.json` must **pin the storage directory** or `step-ca` reports `failed getting key "…": not found` | measured #141 |
| `step ca init --kms` accepts only `azurekms`; `--kms-intermediate 'tpmkms:…'` is accepted but **silently ignored** (falls back to software keys) | measured #141 |
| `step certificate create` prompts before overwriting an existing output — fails without a TTY; write to a fresh path and move into place | measured #141 |
| The `step-ca` release tarball arrived **truncated** on one download; the truncated binary segfaulted and gave a false "broken" result — **verify `checksums.txt`** | measured #141 |
| Gate environment: Debian 13, Proxmox VE 9.2.18, kernel `7.0.14-16-pve`, Intel PTT; `/dev/tpm0` `10:224`, `/dev/tpmrm0` `252:65536` | measured #141 |

Tooling is installed from the current upstream release and **checksum-verified**; no version is pinned.

---

## 1. Prepare the offline signing island

Use a machine that will never hold the root key on its internal disk. Boot a live Linux USB with **no
network route** to the LAN or internet, and install the `step` CLI there.

```sh
# On the island — verify the download against checksums.txt before running anything (measured #141)
wget https://dl.smallstep.com/gh-release/cli/gh-release-<current>/step_linux_amd64.tar.gz
wget https://dl.smallstep.com/gh-release/cli/gh-release-<current>/checksums.txt
sha256sum -c <(grep step_linux_amd64.tar.gz checksums.txt)
tar -xzf step_linux_amd64.tar.gz
./step version
```

- Install nothing else on the island. The `step-kms-plugin`/`libpcsclite1` requirement applies to the
  **CA host** (§3), not here — the root is an ordinary file on the IronKey.
- Unlock the IronKey and mount it. **Never** leave the root key on the island's disk.

> **Acceptance.** `step version` runs; the island has no route to `192.168.2.0/24` or the internet;
> the IronKey mounts read/write.

> **Backout.** Reboot the island from its own disk; wipe the live USB. Nothing was written yet.

## 2. Generate the 10-year root CA onto the IronKey

Run **only on the island**, with the IronKey mounted. This is a first-run step — **do not overwrite an
existing root**; if one already exists, skip to §3.

```sh
# subject is the CA instance name / CN
step certificate create "Homelab Internal CA" \
  /mnt/ironkey/root_ca.crt /mnt/ironkey/root_ca_key \
  --profile root-ca --not-after 87600h
# the key is passphrase-protected at the prompt; record the passphrase in the safe

# record the root fingerprint somewhere durable OUTSIDE the repo
step certificate fingerprint /mnt/ironkey/root_ca.crt
```

- `87600h` = 10 years. `--profile root-ca` sets `CA:TRUE` and path length constraints.
- Both files live **only** on the IronKey. The certificate is public once distributed
  ([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)); the **key must never leave the
  IronKey**.
- The CA instance name / CN is `Homelab Internal CA`. The service's DNS name is `ca.internal`
  (§5); they are separate.

> **Acceptance.** `step certificate inspect /mnt/ironkey/root_ca.crt` shows `CA:TRUE`, a path-length
> constraint, and a ~10-year validity; the fingerprint is recorded in the safe.

> **Backout (init only).** No trust has been distributed yet, so a wrong root is simply deleted and §2
> repeated. Once the root has been distributed ([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)),
> replacing it is a **root rotation** with a full client re-trust window — do not treat it as routine.

## 3. Generate the intermediate key inside the `pve` TPM

Run **inside LXC 215 `ca`** ([runbook 36 §1–§2](36-deploy-step-ca.md) must be done first). The TPM is
bound to this container, and the sealed-key storage directory must be pinned to match the eventual
`ca.json`.

```sh
# in LXC 215
apt-get update && apt-get install -y libpcsclite1
# install the current `step` CLI, `step-ca`, and `step-kms-plugin`, each checksum-verified

ls -l /dev/tpm*                       # /dev/tpmrm0 must be present and owned by container root

# create the intermediate key INSIDE the TPM, pinning the storage directory (measured #141)
step kms create --json 'tpmkms:name=homelab-intermediate-ca;storage-directory=/var/lib/step-ca/tpm'
```

- The key material lands in `/var/lib/step-ca/tpm/key-homelab-intermediate-ca.tpmobj` as a JSON blob.
  **This is not a private-key file** — it is the sealed blob. It cannot be used without this TPM, and
  it is **unrecoverable without the file** (§7).
- Both the create command's storage-directory argument form and the resulting path are **unverified**;
  confirm on first run that `ca.json` later resolves the same directory.

Next, emit a CSR signed by the TPM key so the offline root can sign it:

```sh
step certificate create "Homelab Intermediate CA" \
  intermediate_ca.csr intermediate_ca_key.pub \
  --csr --profile intermediate-ca \
  --kms 'tpmkms:storage-directory=/var/lib/step-ca/tpm' \
  --key 'tpmkms:name=homelab-intermediate-ca'
```

- The exact `--csr` argument/flag combination is **unverified**; the point is a CSR whose public key is
  the TPM key and whose signature is produced by the TPM. Confirm with
  `step certificate inspect intermediate_ca.csr`.

> **Acceptance.** `step kms` lists the key; the `.tpmobj` exists; a CSR exists and inspects correctly.

> **Backout.** `step kms delete` the key, remove the `.tpmobj`, and delete the CSR. Nothing has been
> signed by the root yet, so this is fully reversible.

## 4. Root signs the intermediate certificate (offline)

Carry `intermediate_ca.csr` to the island on the ordinary USB stick. Insert the IronKey, sign, and
return it to the safe.

```sh
step certificate sign --profile intermediate-ca --not-after 8760h \
  intermediate_ca.csr \
  /mnt/ironkey/root_ca.crt /mnt/ironkey/root_ca_key \
  > intermediate_ca.crt

step certificate inspect intermediate_ca.crt   # issuer = root CN, ~1 year, CA:TRUE
```

- `8760h` = 1 year. The root is used for exactly this operation and nothing else.
- **Lock/unmount the IronKey and return it to the safe** before the island is powered off.
- Carry `intermediate_ca.crt` and a copy of `root_ca.crt` back to the CA host — both are public.

> **Acceptance.** `step certificate inspect intermediate_ca.crt` shows the root as issuer and a
> ~1-year validity; the IronKey is locked and back in the safe.

> **Backout.** Discard the signed certificate and repeat §4. The root key is unaffected.

## 5. Install the intermediate and build `ca.json`

Back in LXC 215 ([runbook 36 §5](36-deploy-step-ca.md) does this from Ansible). `step ca init` **cannot
bootstrap a TPM-backed CA** (measured #141), so the working route is to let it create the skeleton and
then **replace** the intermediate and patch the config.

```sh
# 1. create the skeleton (config + provisioners). Keep the passphrase-file for the service.
step ca init --name "Homelab Internal CA" --dns ca.internal --address :9000 \
  --provisioner admin@internal --password-file /etc/step-ca/secrets/password

# 2. install the offline-signed material
install -m 0644 root_ca.crt        /etc/step-ca/certs/root_ca.crt
install -m 0644 intermediate_ca.crt /etc/step-ca/certs/intermediate_ca.crt

# 3. remove the software intermediate key init just wrote (the TPM holds ours)
rm -f /etc/step-ca/secrets/intermediate_ca_key
```

Patch `/etc/step-ca/config/ca.json` so the CA loads the TPM key and the offline-signed certificates:

```json
{
  "root": "/etc/step-ca/certs/root_ca.crt",
  "crt":  "/etc/step-ca/certs/intermediate_ca.crt",
  "key":  "tpmkms:name=homelab-intermediate-ca",
  "kms":  { "type": "tpmkms", "uri": "tpmkms:storage-directory=/var/lib/step-ca/tpm" }
}
```

- **Pin the `storage-directory`** — a bare `tpmkms:` URI makes `step-ca` report
  `failed getting key "…": not found` for a key the CLI just created and used (measured #141).
- `step ca init` generated a throwaway root key/cert; replace them with the offline root and delete the
  generated copies.
- The ACME provisioner is added by the workload role ([runbook 36 §5](36-deploy-step-ca.md)).
- **Non-TTY overwrite nit (measured #141):** `step certificate create` hangs on an overwrite prompt
  without a TTY — write to a fresh path and `install`/`mv` into place.

> **Acceptance.** `step ca health` reports `ok`; `ca.json` carries the `kms` block; no
> `secrets/intermediate_ca_key` remains; the enabled service starts clean.

> **Backout.** Restore the previous `ca.json` and `certs/` from backup and restart the service. Because
> the root is unchanged, any previously issued leaves remain valid.

## 6. Verify the chain before any distribution

```sh
# from the CA host (or anywhere with the root cert)
step certificate create test.internal test.crt test.key \
  --ca-url https://ca.internal:9000 --root /etc/step-ca/certs/root_ca.crt
step certificate verify test.crt --roots /etc/step-ca/certs/root_ca.crt
```

- Nothing resolves `ca.internal` yet — name resolution is a separate workstream
  ([idea 10](../ideas/10-internal-ca-dns-stack.md)); use `--ca-url https://192.168.2.215:9000` or a
  temporary hosts entry.
- The expected chain is `leaf ← Homelab Intermediate CA ← Homelab Internal CA` (root).

> **Acceptance.** The leaf verifies against the offline root; the intermediate is in the chain; the
> CA serves no cleartext.

> **Backout.** Stop the service; the root and client trust are untouched.

## 7. Back up the sealed key blob with the deployment

```sh
install -D -m 0600 /var/lib/step-ca/tpm/key-homelab-intermediate-ca.tpmobj \
  /root/step-ca-backup/tpm/key-homelab-intermediate-ca.tpmobj
cp /etc/step-ca/config/ca.json       /root/step-ca-backup/ca.json
cp /etc/step-ca/certs/*.crt          /root/step-ca-backup/certs/
```

- The blob is **not** a key file: it cannot sign off this machine, but the CA is unrecoverable on this
  machine without it.
- This backup covers **filesystem** loss. It does **not** survive a TPM wipe — that is §9.

> **Acceptance.** The backup contains the `.tpmobj`, `ca.json`, and both certificates.

> **Backout.** None — this step only copies.

## 8. Annual re-sign ceremony

Roughly **annually** (before the 1-year intermediate expires), re-run **§3–§6** against the **same
root**:

1. Create a fresh intermediate key in the TPM (§3) — or reuse the existing key and re-sign a new cert.
2. Sign the CSR with the offline root (§4).
3. Install it and restart the service (§5).
4. Verify the chain (§6).

- **No root re-issue and no client re-trust** — the fleet and workstations keep trusting the same root,
  so there is no propagation window. This is the payoff of the offline root.
- Set a calendar reminder ~30 days before expiry. The intermediate's actual expiry is in
  `step certificate inspect intermediate_ca.crt`.

> **Acceptance.** The new intermediate chain verifies; the old one is retired only after the new one
> passes; the new expiry is recorded.

> **Backout.** Revert to the previous `intermediate_ca.crt` (and key, if not overwritten) before it
> expires; re-run §4–§6.

## 9. PTT key-loss recovery

The `pve` TPM is an **Intel PTT firmware TPM** (measured 2026-10-04,
[research 37 §5](../research/37-tpm2-hardware-and-fleet.md)). Any of these **destroys the sealed key**:

- a BIOS/firmware update,
- `Clear PTT` in BIOS setup (**Security → PTT security → Clear PTT**),
- an NVRAM reset.

Recovery is the annual ceremony, run on demand:

1. Re-run §3 to create a fresh intermediate key in the (possibly cleared) TPM.
2. Re-run §4–§6 with the **same** offline root.

- The **root is unaffected**, so there is **no client re-trust**. A PTT wipe costs a re-signing
  ceremony, not a re-trust.
- Adjust the annual reminder after an unexpected wipe.

> **Acceptance.** The CA again issues chain-verified leaves.

> **Backout.** None needed — the root is untouched; repeat §3–§6 if the first attempt fails.

---

## Verification Checklist

Executed on: **never** — this runbook is unexecuted. Record the date and each result when it is first
run; update the measured/planned labels above as facts are confirmed.

- [ ] §1 island air-gapped; `step` installed; checksums verified
- [ ] §2 root created with `CA:TRUE`, ~10y; stored only on the IronKey; fingerprint recorded
- [ ] §3 intermediate key created in `/dev/tpmrm0`; sealed blob + CSR present
- [ ] §4 intermediate signed by the offline root; IronKey returned to the safe
- [ ] §5 `ca.json` patched with the `tpmkms` block; software intermediate key removed; `step ca health` ok
- [ ] §6 leaf issued and chain-verified against the root
- [ ] §7 `.tpmobj` + `ca.json` + certs backed up
- [ ] §8 annual re-sign scheduled
- [ ] §9 PTT-loss recovery documented and understood

## Follow-ups

- **Root distribution** — [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144) (out of scope).
- **Proxy wiring** — [#142](https://github.com/jaroslaw-bagnicki/Homelab/issues/142); **first service** —
  [#143](https://github.com/jaroslaw-bagnicki/Homelab/issues/143).
- **YubiKey PIV upgrade** — ADR 38's planned custody move: make the root non-exportable and **destroy
  every exportable copy**; a ceremony, not a file move (out of scope).
- **Exact genesis CLI flags** — §3/§4 are marked unverified; confirm on the first execution and update
  this runbook.

## References

- [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — the three-tier hierarchy and custody
- [Research 36 §4–§5](../research/36-step-ca-machine-identity.md) — TPM/KMS mechanics, the LXC recipe
- [Research 37 §5](../research/37-tpm2-hardware-and-fleet.md) — the `pve` Intel PTT fTPM and key-loss risk
- [Issue #141](https://github.com/jaroslaw-bagnicki/Homelab/issues/141) — the measured TPM custody gate
- [Runbook 36](36-deploy-step-ca.md) — the on-host deployment this ceremony feeds
- [Runbook 28](28-pve-proxmox-node.md) (Proxmox base) · [ADR 34](../decisions/34-lan-tls-only.md) (TLS-only) ·
  [ADR 37](../decisions/37-lan-name-space-internal.md) (`.internal`)
