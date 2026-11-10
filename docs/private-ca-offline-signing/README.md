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

Stop. Keep the exact error output and record it in [research 54 §3](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md)
— including what was verified where, so a probe result is never mistaken for a hardware result. A failed
run changes nothing on the token (a signed-but-rejected certificate is discarded, never installed), and
re-signing the same CSR is safe. Do not improvise around a refusal — the network warning, the health-check
gates (research 54 §4 decision rule) and the `FAIL` checks are deliberate.

## Reference

[Runbook 46](../runbooks/46-adopt-utrust-piv-root-custody.md) · [research 54](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md) · [runbook 35 §6–§7](../runbooks/35-deploy-step-ca.md) · [runbook 41](../runbooks/41-deploy-freeipa-server.md) · [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)
