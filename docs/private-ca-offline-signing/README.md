# Private CA — uTrust token signing kit

Everything needed to sign with the fleet **root key held on the uTrust FIDO2 NFC USB-A** (PIV applet,
slot 9C) — **except the token itself**. The root private key never leaves the token: it is generated
on-card once ([02](02-issuing-root-cert.md), [runbook 46](../runbooks/46-adopt-utrust-piv-root-custody.md)),
and every signature prompts the PIV PIN on the token.

## What this is, and is not

The fleet CA's **offline root** lives in the token's PIV slot 9C, the **`step-ca` intermediate** is
signed by it, and (for M1) the **FreeIPA CA** CSR is signed by the same root. All of it happens on the
**workstation** — WSL with the token attached via `usbipd`, or Windows native. No air-gap is needed
because the key is **non-exportable**: the worst case on a networked machine is one rogue intermediate
signed while the token is plugged in, bounded by the per-signature PIN prompt and the on-screen CSR
check (ADR 38 amendment; [research 54 §6](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md)).
The token is plugged in **only during signing** and goes back to the safe afterwards — and it is
**never** plugged into `pve1` / the `ca` guest.

The kit carries the tools, the requests and the recipes, so the workstation needs the smartcard
packages (`pcscd`, `opensc`, `pcsc-tools`, `libpcsclite1`) and nothing downloaded at ceremony time.
Nothing in the kit is private — the CSRs, templates and certificates are public. The one secret is the
root key, and it exists only inside the token.

## Contents

| File | What it is | Read it |
|---|---|---|
| [`01-building-step.md`](01-building-step.md) | puts the `step` CLI **and** `step-kms-plugin` into this kit | on the connected machine, before the ceremony |
| [`02-issuing-root-cert.md`](02-issuing-root-cert.md) | provisions the 10-year root **on the token**, slot 9C | **once ever** |
| [`03-signing-csr.md`](03-signing-csr.md) | signs the intermediate CSR with the token | every signing, incl. the annual re-sign |
| `step` | the `step` CLI, linux/amd64 — **not stored in git** (42 MB upstream binary), added by 01 | — |
| `step-kms-plugin` | the CGO KMS plugin — **not stored in git**, added by 01; the stock static `step` execs it for every `pkcs11:` URI | — |
| [`check-utrust.sh`](check-utrust.sh) | read-only token health check (USB, reader, PIV AID `9000`, CPLC, PKCS#11 slot, AAGUID) | first, on the workstation with the token attached |
| [`sign-piv.sh`](sign-piv.sh) | signs `intermediate_ca.csr` with the root on the token, then machine-checks the result | every signing |
| [`sign-ipa-ca.sh`](sign-ipa-ca.sh) | signs FreeIPA's `ipa.csr` with the same token root | the FreeIPA CA ceremony |
| `intermediate_ca.csr` | the certificate request, created on the CA host by the key in `pve1`'s TPM — **not stored in git**, bring the file the CA host produced | — |
| `intermediate-ca.tpl` | the signing template — the extensions the finished certificate must carry | — |
| `ipa-ca.tpl` | the FreeIPA CA signing template — `CN=Certificate Authority,O=IPA.INTERNAL`, CA:TRUE, pathlen:0 | — |
| `root_ca.crt` | the current root certificate (public); replaced by the new root after the reissue | — |
| `intermediate_ca.crt` | the last signed intermediate (public) | — |

`intermediate-ca.tpl` is a **copy** of `ansible/workloads/step-ca/files/intermediate-ca.tpl`, which is
the versioned source. If you change one, change both — otherwise the signing run uses the old shape.

## What you must bring (deliberately not in this kit)

- **The uTrust token**, unplugged except during signing. Empty PIV slot 9C on the first run — that is
  where [02](02-issuing-root-cert.md) generates the root.
- `ipa.csr` when the M1 FreeIPA CA ceremony runs — produced on the IPA guest, public, not stored in git.
- A safe place for the token and the written-down PIV PIN / PUK.

## Rules

1. **The root key never exists outside the token** — there is no key file to copy, back up or destroy.
   Backing the root up means a second token (import during the ceremony — runbook 46's backup note).
2. **The token is plugged in only during signing** and back in the safe afterwards; never on `pve1` /
   the `ca` guest. The live CA's `ca.json` does not change — the intermediate stays in the `pve1` TPM.
3. **No PIN, PUK, management key or `pin-value=` in scripts, Ansible, logs or the repo** — PC/SC prompts
   the PIN immediately before each signature.
4. Never sign with `--profile intermediate-ca`. It silently drops the SANs, which are the CA's declared
   identity shape — [03](03-signing-csr.md) explains.
5. **[02](02-issuing-root-cert.md) runs once, ever.** Replacing a root is a trust rotation (issue #144:
   every client must re-trust), not a re-run. The repeat job is [03](03-signing-csr.md).
6. **Write the PIV PIN/PUK down before the first ceremony.** Lose them and the token's contents are dead.
7. A networked workstation is accepted risk (the key is non-exportable): the scripts warn and proceed
   only with `SIGN_PIV_ALLOW_NETWORK=1`, and print the CSR for on-screen verification before signing.

## The flow, end to end

1. **On the connected machine.** Assemble the kit — [01-building-step.md](01-building-step.md) adds
   `step` and `step-kms-plugin` (both checksum-verified).

2. **On the workstation.** Attach the token — in WSL from Windows PowerShell:
   `usbipd bind --busid <busid>` + `usbipd attach --wsl --busid <busid>`, then `wsl -d <distro>`;
   install `pcscd opensc pcsc-tools libpcsclite1 fido2-tools usbutils` and start `pcscd`. Copy the kit
   to a real filesystem (`/tmp`) — FAT/exFAT sticks have no executable bit — and run the health check:

   ```sh
   bash check-utrust.sh        # all checks pass: reader, PIV AID 9000, CPLC 40 90, PKCS#11 slot, AAGUID
   ```

   Gates 4 (PIV AID `9000`) and 6 (OpenSC PKCS#11 lists the token) are the ceremony go/no-go
   ([research 54 §4](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md)).

3. **Provision the root — once ever.** [02-issuing-root-cert.md](02-issuing-root-cert.md): change the
   factory PIV defaults, generate the P-256 key pair in slot 9C, create the 10-year self-signed root
   over it, test-sign a throwaway CSR. Record the root fingerprint **outside the repo**.

4. **Sign the intermediate — every time, incl. the annual re-sign.**
   [03-signing-csr.md](03-signing-csr.md):

   ```sh
   SIGN_PIV_ALLOW_NETWORK=1 ./sign-piv.sh "<token label>"
   ```

   The PIN is prompted by PC/SC per signature; the CSR is printed first — verify subject and public
   key; the result is machine-checked before it replaces `intermediate_ca.crt`.

5. **Sign the FreeIPA CA when M1 needs it.** Bring `ipa.csr` from the IPA guest into the kit and run
   `SIGN_PIV_ALLOW_NETWORK=1 ./sign-ipa-ca.sh "<token label>"` — same token root, `ipa-ca.tpl`, 5 years.

6. **Finish.** Unplug the token back to the safe; carry back only the public certificates
   (`intermediate_ca.crt`, `ipa-ca.crt`, `root_ca.crt`).

## Bring back

- `intermediate_ca.crt` — the signed `step-ca` intermediate (installed by [runbook 35 §7](../runbooks/35-deploy-step-ca.md))
- `ipa-ca.crt` — the signed FreeIPA CA (when M1 runs its ceremony; [runbook 41](../runbooks/41-deploy-freeipa-server.md))
- `root_ca.crt` — the current root certificate

## If something goes wrong

| Symptom | What to do |
|---|---|
| `./step version` fails with `Permission denied` | Running from a FAT/exFAT stick — copy the kit to `/tmp` first and `chmod +x` there. |
| `exec: "step-kms-plugin": not found in $PATH` | The plugin is missing — [01](01-building-step.md) adds it; the stock `step` delegates every `pkcs11:` URI to it. `libpcsclite1` must be installed too. |
| `check-utrust.sh` check 4 ≠ `9000` or check 6 lists no token | OpenSC cannot drive the PIV applet on Linux — fall back to Windows (uTrust Key Manager / `certreq`) or an NFC+ SKU; see research 54 §4 decision rule. |
| `kms uri 'token', 'serial' or 'slot-id' are required` | The `pkcs11:` URI needs `token=` (or `serial=`/`slot-id`) besides `module-path` and `object=`. |
| `getPublicKey failed: key … not found` on `certificate create` | `create` cannot generate the key — run the slot-9C keygen first ([02](02-issuing-root-cert.md)). |
| A `FAIL` line in the checks | Stop and do not carry the certificate away. The token is untouched and re-signing the same CSR is safe. |

## Reference

- [Runbook 46](../runbooks/46-adopt-utrust-piv-root-custody.md) — the adoption runbook (reissue + trust rotation)
- [Runbook 35 §6](../runbooks/35-deploy-step-ca.md) — produced `intermediate_ca.csr` (the CA host)
- [Research 54](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md) — the token diagnostic, gates and verified command shapes
- [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — the hierarchy: 10-year root on the uTrust token, 1-year TPM-bound intermediate
