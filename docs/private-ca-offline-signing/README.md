# Private CA — uTrust token signing kit

Sign with the fleet root key held **on the uTrust FIDO2 NFC USB-A** (PIV slot 9C). The key is generated
on-card once and never leaves the token; every signature prompts the PIV PIN. Nothing in the kit is
secret. Full procedure: [runbook 46](../runbooks/46-adopt-utrust-piv-root-custody.md).

## Use it

1. **Connected machine** — [01](01-building-step.md): add `step` + `step-kms-plugin` (checksum-verified).
2. **Workstation, token attached** (WSL via `usbipd`, or Windows): install `pcscd opensc pcsc-tools
   libpcsclite1 fido2-tools usbutils`, start `pcscd`, copy the kit to `/tmp`, then
   `bash check-utrust.sh` — gates 4 (PIV AID `9000`) and 6 (PKCS#11 slot) must pass ([research 54 §4](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md)).
3. **Once ever** — [02](02-issuing-root-cert.md): provision the 10-year root in slot 9C.
4. **Every signing** (incl. annual re-sign) — [03](03-signing-csr.md):

   ```sh
   SIGN_PIV_ALLOW_NETWORK=1 ./sign-piv.sh "<token label>"      # intermediate_ca.csr -> intermediate_ca.crt
   SIGN_PIV_ALLOW_NETWORK=1 ./sign-ipa-ca.sh "<token label>"   # FreeIPA M1: ipa.csr -> ipa-ca.crt
   ```

   The PIN is prompted per signature; the CSR is printed first — check subject + public key; the result
   is machine-checked before it replaces the old cert. Then unplug the token and carry back only the
   public certs (`root_ca.crt`, `intermediate_ca.crt`, `ipa-ca.crt`).

## Files

- **Guides:** `01-building-step.md`, `02-issuing-root-cert.md`, `03-signing-csr.md`
- **Scripts:** `check-utrust.sh` (health check), `sign-piv.sh`, `sign-ipa-ca.sh`
- **Binaries (not in git, added by 01):** `step`, `step-kms-plugin`
- **Inputs (not in git):** `intermediate_ca.csr` (from [runbook 35 §6](../runbooks/35-deploy-step-ca.md)), `ipa.csr` (from the IPA guest)
- **Templates:** `intermediate-ca.tpl` (mirrors `ansible/workloads/step-ca/files/intermediate-ca.tpl` — change both), `ipa-ca.tpl`
- **Public outputs:** `root_ca.crt`, `intermediate_ca.crt`, `ipa-ca.crt`

## Rules

- Token plugged in **only during signing**, then back to the safe; **never** on `pve1` / the `ca` guest.
- No PIN, PUK, management key or `pin-value=` in scripts, Ansible, logs or the repo — PC/SC prompts per signature.
- Never `--profile intermediate-ca` (drops the SANs). Guide 02 runs **once ever** — replacing a root is a trust rotation.
- Networked workstation is accepted (the key is non-exportable): scripts require `SIGN_PIV_ALLOW_NETWORK=1`.
- Bring the token, `ipa.csr` when M1 needs it, and a safe for the written-down PIV PIN/PUK.

## If something fails

| Symptom | Fix |
|---|---|
| `Permission denied` running `./step` | kit on a FAT/exFAT stick — copy to `/tmp`, `chmod +x` |
| `step-kms-plugin: not found in $PATH` | 01 adds the plugin; install `libpcsclite1` |
| health-check gate 4 ≠ `9000` / gate 6 empty | OpenSC can't drive PIV on Linux — Windows (Key Manager/`certreq`) or NFC+ SKU, research 54 §4 |
| `kms uri 'token'… required` | `pkcs11:` URI needs `token=`/`serial=`/`slot-id` besides `module-path`+`object=` |
| `getPublicKey failed: key … not found` | `create` can't generate keys — run the slot-9C keygen in 02 first |
| a `FAIL` line in the checks | stop; carry nothing away — the token is untouched, re-signing the same CSR is safe |

## Reference

[Runbook 46](../runbooks/46-adopt-utrust-piv-root-custody.md) · [research 54](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md) · [runbook 35 §6–§7](../runbooks/35-deploy-step-ca.md) · [runbook 41](../runbooks/41-deploy-freeipa-server.md) · [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)
