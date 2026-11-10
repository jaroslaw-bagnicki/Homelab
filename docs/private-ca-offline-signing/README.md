# Private CA — uTrust token signing kit

Signs the fleet CA's requests with the **root key held on the uTrust FIDO2 NFC USB-A** (PIV applet,
slot 9C) — the token itself is not in this kit. The key is generated on-card once and never leaves the
token; every signature prompts the PIV PIN. Runs on the **workstation** (WSL with the token attached
via `usbipd`, or Windows) — no air-gap needed, because the key is non-exportable (ADR 38 amendment,
[research 54 §6](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md)). Full procedure:
[runbook 46](../runbooks/46-adopt-utrust-piv-root-custody.md).

Nothing in the kit is private — CSRs, templates and certificates are public. The one secret is the root
key, and it exists only inside the token.

## Contents

| Kind | File | What it is |
|---|---|---|
| guide | [`01-building-step.md`](01-building-step.md) | assembles the kit: adds `step` + `step-kms-plugin` (checksum-verified) — connected machine, before the ceremony |
| guide | [`02-issuing-root-cert.md`](02-issuing-root-cert.md) | provisions the 10-year root **on the token** (slot 9C) — **once ever** |
| guide | [`03-signing-csr.md`](03-signing-csr.md) | signs the intermediate CSR with the token — every signing, incl. the annual re-sign |
| script | [`check-utrust.sh`](check-utrust.sh) | read-only token health check: USB, reader, PIV AID `9000`, CPLC, PKCS#11 slot, AAGUID |
| script | [`sign-piv.sh`](sign-piv.sh) | signs `intermediate_ca.csr` with the token root, machine-checks the result |
| script | [`sign-ipa-ca.sh`](sign-ipa-ca.sh) | signs FreeIPA's `ipa.csr` with the same token root |
| binary | `step` | `step` CLI linux/amd64 — not in git (42 MB), added by 01 |
| binary | `step-kms-plugin` | CGO KMS plugin — not in git, added by 01; the static `step` execs it for every `pkcs11:` URI |
| input | `intermediate_ca.csr` | CSR from the CA host (`pve1` TPM key) — not in git, bring the file [runbook 35 §6](../runbooks/35-deploy-step-ca.md) produced |
| input | `ipa.csr` | FreeIPA CA CSR — not in git, bring it from the IPA guest for the M1 ceremony |
| template | `intermediate-ca.tpl` | signing template for the intermediate (a **copy** of `ansible/workloads/step-ca/files/intermediate-ca.tpl` — change both or neither) |
| template | `ipa-ca.tpl` | IPA CA template — `CN=Certificate Authority,O=IPA.INTERNAL`, CA:TRUE, pathlen:0 |
| output | `root_ca.crt` | current root cert (public); replaced by the new root after the reissue |
| output | `intermediate_ca.crt` | last signed intermediate (public) |
| output | `ipa-ca.crt` | last signed FreeIPA CA (public), when produced |

## Bring

- **The uTrust token** — unplugged except during signing; back in the safe afterwards. Never plugged
  into `pve1` / the `ca` guest. Empty slot 9C on the first run.
- `ipa.csr` from the IPA guest, for the FreeIPA CA ceremony.
- A safe place for the token and the written-down PIV PIN/PUK (lose them and the token is dead).

## Rules

1. The root key never exists outside the token — nothing to copy, back up or destroy. A backup means a
   second token (runbook 46's backup note).
2. No PIN, PUK, management key or `pin-value=` in scripts, Ansible, logs or the repo — PC/SC prompts the
   PIN immediately before each signature.
3. Never sign with `--profile intermediate-ca` — it silently drops the SANs ([03](03-signing-csr.md)).
4. [02](02-issuing-root-cert.md) runs **once ever**; replacing a root is a trust rotation (#144), not a
   re-run. The repeat job is [03](03-signing-csr.md).
5. A networked workstation is accepted risk (non-exportable key): the scripts warn and proceed only
   with `SIGN_PIV_ALLOW_NETWORK=1`, and print the CSR for on-screen verification before signing.

## Flow

1. **Connected machine:** assemble the kit — [01](01-building-step.md).
2. **Workstation:** attach the token (WSL: `usbipd bind --busid <busid>` + `usbipd attach --wsl --busid
   <busid>` from Windows PowerShell, then `wsl -d <distro>`), install
   `pcscd opensc pcsc-tools libpcsclite1 fido2-tools usbutils`, start `pcscd`, copy the kit to `/tmp`
   (FAT/exFAT has no executable bit), then:

   ```sh
   bash check-utrust.sh    # gates 4 (PIV AID 9000) + 6 (PKCS#11 slot) are the go/no-go — research 54 §4
   ```

3. **Once ever:** provision the root on the token — [02](02-issuing-root-cert.md).
4. **Every signing (incl. annual re-sign):**

   ```sh
   SIGN_PIV_ALLOW_NETWORK=1 ./sign-piv.sh "<token label>"      # intermediate_ca.csr -> intermediate_ca.crt
   SIGN_PIV_ALLOW_NETWORK=1 ./sign-ipa-ca.sh "<token label>"   # when M1 needs it: ipa.csr -> ipa-ca.crt
   ```

   PIN prompted per signature; CSR printed first — verify subject + public key; result machine-checked
   before it replaces the old cert. Carry back only the public certs (`root_ca.crt`,
   `intermediate_ca.crt`, `ipa-ca.crt`); unplug the token.

## If something goes wrong

| Symptom | Fix |
|---|---|
| `Permission denied` running `./step` | Kit is on a FAT/exFAT stick — copy to `/tmp`, `chmod +x` there |
| `exec: "step-kms-plugin": not found in $PATH` | Plugin missing — 01 adds it; also install `libpcsclite1` |
| `check-utrust.sh` gate 4 ≠ `9000` or 6 empty | OpenSC can't drive the PIV applet — use Windows (Key Manager / `certreq`) or an NFC+ SKU (research 54 §4) |
| `kms uri 'token', 'serial' or 'slot-id' are required` | `pkcs11:` URI needs `token=`/`serial=`/`slot-id` besides `module-path` + `object=` |
| `getPublicKey failed: key … not found` on `create` | `create` can't generate keys — run the slot-9C keygen first ([02](02-issuing-root-cert.md)) |
| A `FAIL` line in the checks | Stop; carry nothing away. The token is untouched and re-signing the same CSR is safe |

## Reference

- [Runbook 46](../runbooks/46-adopt-utrust-piv-root-custody.md) — adoption: reissue + trust rotation
- [Research 54](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md) — token diagnostic, gates, verified command shapes
- [Runbook 35 §6–§7](../runbooks/35-deploy-step-ca.md) — produces `intermediate_ca.csr`, installs the signed intermediate
- [Runbook 41](../runbooks/41-deploy-freeipa-server.md) — FreeIPA external-CA flow
- [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — 10-year root on the token, 1-year TPM-bound intermediate
