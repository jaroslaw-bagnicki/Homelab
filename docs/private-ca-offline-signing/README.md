# Private CA — uTrust token signing kit

Everything the signing workstation needs — **except the uTrust FIDO2 NFC USB-A token itself**.

## What this is, and is not

The fleet CA's **offline root** lives in the token's PIV applet (slot 9C), the **`step-ca`
intermediate** is signed by it, and (for M1) the **FreeIPA CA** CSR is signed by the same root. All of
it happens on the **workstation** — a WSL distro with the token attached via `usbipd`, or Windows
native. No air-gap is needed: the root key is **non-exportable** on the token, so the worst case on a
networked machine is one rogue intermediate signed while the token is plugged in — bounded by the
per-signature PIN prompt and the on-screen CSR check (ADR 38 amendment, research 54 §6). This bundle
carries the tools, the requests and the recipes, so the workstation needs only the smartcard packages
(`pcscd`, `opensc`, `pcsc-tools`, `libpcsclite1`) — nothing is downloaded at signing time.

It does **not** start the CA and does **not** distribute trust. Nothing in the bundle is private — the
CSRs, templates and certificates are public. The one secret is the **root key**, and it exists only
inside the token, back in the safe outside ceremonies.

## Contents

| File | What it is | Read it |
|---|---|---|
| [`01-building-step.md`](01-building-step.md) | puts the `step` CLI **and** `step-kms-plugin` into this bundle | on the connected machine, before you leave |
| [`02-issuing-root-cert.md`](02-issuing-root-cert.md) | provisions the 10-year root **on the token**, slot 9C | **once ever** |
| [`03-signing-csr.md`](03-signing-csr.md) | signs the intermediate CSR with the token root | every signing |
| `step` | the `step` CLI, linux/amd64 — **not stored in git** (42 MB upstream binary), added by 01 | — |
| `step-kms-plugin` | the CGO KMS plugin — **not stored in git**, added by 01; the static `step` execs it for every `pkcs11:` URI | — |
| [`check-utrust.sh`](check-utrust.sh) | read-only token health check (USB, reader, PIV AID `9000`, CPLC, PKCS#11 slot, AAGUID) | first, on the workstation |
| [`sign-piv.sh`](sign-piv.sh) | signs the `step-ca` intermediate CSR with the token root, then machine-checks the result | every signing |
| [`sign-ipa-ca.sh`](sign-ipa-ca.sh) | signs FreeIPA's `ipa.csr` (from `ipa-server-install --external-ca`) with the same token root | the FreeIPA ceremony |
| `intermediate_ca.csr` | the certificate request, created on the CA host by the key that lives in `pve1`'s TPM — **not stored in git**, bring the file the CA host produced | — |
| `intermediate-ca.tpl` | the signing template — the extensions the finished certificate must carry | — |
| `ipa-ca.tpl` | the FreeIPA CA signing template — `CN=Certificate Authority,O=IPA.INTERNAL`, CA:TRUE, pathlen:0 | — |
| `root_ca.crt` | the current root certificate (public) | — |
| `intermediate_ca.crt` | the last signed intermediate (public) | — |

`intermediate-ca.tpl` is a **copy** of `ansible/workloads/step-ca/files/intermediate-ca.tpl`, which is the
versioned source. If you change one, change both — otherwise the signing run uses the old shape.

## What you must bring (deliberately not in this bundle)

- **The uTrust token**. Empty PIV slot 9C on the first run — that is where [02](02-issuing-root-cert.md)
  generates the root. Unplugged except during signing.
- `ipa.csr` when the M1 FreeIPA CA ceremony runs — produced on the IPA guest, public, not stored in git.
- A safe place to keep the token and the written-down PIV PIN / PUK.

## Rules

1. **The root key never exists outside the token** — there is no key file to put on a disk, copy or
   destroy. The token is plugged in **only during signing** and goes back to the safe afterwards;
   **never** plug it into `pve1` / the `ca` guest.
2. **No PIN, PUK, management key or `pin-value=`** in scripts, Ansible, logs or the repo — PC/SC prompts
   the PIN immediately before each signature.
3. **A networked workstation is accepted risk** (the key is non-exportable): the scripts warn if they
   find a non-loopback address or a default route, and proceed only with `SIGN_PIV_ALLOW_NETWORK=1`.
4. Never sign with `--profile intermediate-ca`. It silently drops the SANs, which are the CA's declared
   identity shape — the CA is not left unserved (the serving certificate is a separate self-issued leaf,
   runbook 35 §7), but the certificate no longer matches the shape the deployment records.
5. **[02](02-issuing-root-cert.md) runs once, ever.** Replacing a root is a trust rotation — every client
   would have to re-trust — not a re-run. The repeat job is [03](03-signing-csr.md) / `sign-piv.sh`.
6. **Write the PIV PIN/PUK down before the first ceremony.** They are the only way back into the token;
   lose them and the root key is dead.

## The flow, end to end

1. **On the connected machine.** Assemble the bundle and add the two binaries to it —
   [01-building-step.md](01-building-step.md) (`step` + `step-kms-plugin`, checksum-verified).

2. **On the workstation.** Attach the token — in WSL, from Windows PowerShell:
   `usbipd bind --busid <busid>` + `usbipd attach --wsl --busid <busid>`, then `wsl -d <distro>`
   (on Windows native, the token is simply plugged in). Install the smartcard packages and start the
   daemon:

   ```sh
   sudo apt install pcscd opensc pcsc-tools libpcsclite1 fido2-tools usbutils
   sudo systemctl start pcscd    # or: sudo service pcscd start
   ```

3. **Copy the bundle to a real filesystem before running anything.** A USB stick is FAT32, exFAT or
   NTFS — none of which has an executable bit, so `chmod +x` silently does nothing there and `./step`
   fails with `Permission denied`. `/tmp` is a real filesystem and works:

   ```sh
   cp -r <usb>/private-ca-offline-signing /tmp/bundle
   cd /tmp/bundle
   chmod +x step step-kms-plugin check-utrust.sh sign-piv.sh sign-ipa-ca.sh
   export PATH="$PWD:$PATH"      # step execs step-kms-plugin for pkcs11: URIs
   ./step version
   ```

   It must print a `Smallstep CLI/... (linux/amd64)` line. If it prints nothing, the copy is broken —
   re-copy the bundle. This is the only integrity check the bundle needs.

4. **Health-check the token** (read-only — no PIN login, writes nothing):

   ```sh
   bash check-utrust.sh
   ```

   All checks pass → proceed. The go/no-go gates are **4** (PIV AID select `9000`) and **6** (`pkcs11-tool
   --module …/opensc-pkcs11.so --list-slots` lists the token) — decision rule in
   [research 54 §4](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md).

5. **Provision the root on the token — once ever.** The full ceremony, its acceptance checks and its
   refusals: [02-issuing-root-cert.md](02-issuing-root-cert.md).

6. **Sign the intermediate.** This is the operation that repeats — including the annual re-sign:
   [03-signing-csr.md](03-signing-csr.md).

   ```sh
   SIGN_PIV_ALLOW_NETWORK=1 ./sign-piv.sh "<token label>"
   ```

6b. **Sign the FreeIPA CA when M1 needs it.** Bring `ipa.csr` from the IPA guest into the bundle and
   run `SIGN_PIV_ALLOW_NETWORK=1 ./sign-ipa-ca.sh "<token label>"`; copy `ipa-ca.crt` back with
   `root_ca.crt`. The script checks the chain, `CA:TRUE, pathlen:0`, key usage and the
   `CN=Certificate Authority,O=IPA.INTERNAL` subject. This is a separate ceremony from the `step-ca`
   intermediate.

7. **Finish.** Unplug the token and return it to the safe, and carry back the public certificates
   (`intermediate_ca.crt`, and when used `ipa-ca.crt`, plus `root_ca.crt`).

## Bring back

- `intermediate_ca.crt` — the signed `step-ca` intermediate
- `ipa-ca.crt` — the signed FreeIPA CA (when M1 runs its ceremony)
- `root_ca.crt` — the current root certificate

`intermediate_ca.crt` is installed and the CA started by **runbook 35 §7**; `ipa-ca.crt` is installed
by the FreeIPA workload ([runbook 41](../runbooks/41-deploy-freeipa-server.md)).

## If something goes wrong

| Symptom | What to do |
|---|---|
| `./step version` fails with `Permission denied` | You are running it from a FAT/exFAT/NTFS stick — no executable bit. Copy the bundle to `/tmp` first (step 3). |
| `./step version` fails otherwise | The copy is truncated or corrupt. Re-copy it. |
| `exec: "step-kms-plugin": not found in $PATH` | The plugin binary is missing or the kit dir is not on `PATH` — see step 3 and [01](01-building-step.md); `libpcsclite1` must be installed too. |
| A script warns about a non-loopback address / default route | Accepted risk on the workstation (key is non-exportable) — re-run with `SIGN_PIV_ALLOW_NETWORK=1`. |
| Health-check gate 4 ≠ `9000` or gate 6 lists no token | OpenSC cannot drive the PIV applet on Linux — fall back to Windows (uTrust Key Manager / `certreq`) or an NFC+ SKU; decision rule in research 54 §4. |
| A `FAIL` line appears in the checks | Stop and do not carry the certificate away. No trust has been distributed, nothing on the token changed and re-signing the same CSR is safe. |

Anything specific to one ceremony — a root that already exists on the token, a missing SAN, a wrong PIN —
is in the refusals of [02](02-issuing-root-cert.md) or [03](03-signing-csr.md). On any unexpected error:
stop, keep the exact output, and record it in
[research 54 §3](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md) with what was verified where —
a probe result is not a hardware result.

## Reference

- [Runbook 46](../runbooks/46-adopt-utrust-piv-root-custody.md) — the adoption runbook: reissue the root on the token + trust rotation
- [Research 54](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md) — the token diagnostic, hardware gates, verified command shapes
- Runbook 35 §6–§7 — produced `intermediate_ca.csr` (the CA host); installs the signed intermediate
- Runbook 41 — the FreeIPA external-CA flow
- ADR 38 — the hierarchy: 10-year root on the uTrust token, 1-year TPM-bound intermediate
