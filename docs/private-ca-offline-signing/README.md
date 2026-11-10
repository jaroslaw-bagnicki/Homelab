# Private CA — uTrust token signing kit

> Signs the fleet CA's requests with the **root key held on the uTrust FIDO2 NFC USB-A** (PIV applet,
> slot 9C) — the token itself is not in this kit. The key is generated on-card once and never leaves the
> token; every signature prompts the PIV PIN via PC/SC. Runs on the **workstation** (WSL with the token
> attached via `usbipd`, or Windows native) — no air-gap needed because the key is non-exportable.
>
> ⚠ **Invariants:** the token is plugged in **only during signing** and goes back to the safe afterwards;
> it is **never** plugged into `pve1` / the `ca` guest. No PIN, PUK, management key or `pin-value=` in
> scripts, Ansible, logs or the repo. Nothing in the kit is secret — CSRs, templates and certificates are
> public; the one secret is the root key, and it exists only inside the token.
>
> Full procedure and trust rotation: [runbook 46](../runbooks/46-adopt-utrust-piv-root-custody.md).
> Diagnostic background and verified command shapes: [research 54](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md).

## Prerequisites

- [ ] The uTrust FIDO2 NFC USB-A (P/N 905601), empty PIV slot 9C on the first run; a safe for it and for
      the written-down PIV PIN/PUK
- [ ] The workstation: WSL distro (token attached from Windows PowerShell: `usbipd bind --busid <busid>`
      + `usbipd attach --wsl --busid <busid>`, then `wsl -d <distro>`) or Windows native; packages
      `pcscd opensc pcsc-tools libpcsclite1 fido2-tools usbutils`, `pcscd` running
- [ ] This kit assembled on the connected machine — [01](01-building-step.md) added `step` and
      `step-kms-plugin` (both checksum-verified, not in git)
- [ ] `intermediate_ca.csr` from the CA host — [runbook 35 §6](../runbooks/35-deploy-step-ca.md)
      (not in git); `ipa.csr` from the IPA guest for the FreeIPA CA ceremony (not in git)

## Kit contents

| | |
|---|---|
| Guides | `01-building-step.md` (assemble), `02-issuing-root-cert.md` (root on token, once ever), `03-signing-csr.md` (every signing) |
| Scripts | `check-utrust.sh` (read-only health check) · `sign-piv.sh` (intermediate) · `sign-ipa-ca.sh` (FreeIPA CA) |
| Binaries, added by 01, not in git | `step` · `step-kms-plugin` (the static `step` execs it for every `pkcs11:` URI) |
| Inputs, not in git | `intermediate_ca.csr` · `ipa.csr` |
| Templates | `intermediate-ca.tpl` (mirrors `ansible/workloads/step-ca/files/intermediate-ca.tpl` — change both) · `ipa-ca.tpl` |
| Public outputs | `root_ca.crt` · `intermediate_ca.crt` · `ipa-ca.crt` |

## 1. Assemble the kit (connected machine)

[01-building-step.md](01-building-step.md) — adds `step` v0.31.0 and `step-kms-plugin` v0.17.0, each
verified against the upstream release's `checksums.txt`. Confirm both run (`step version`,
`step-kms-plugin --help`).

## 2. Attach the token and health-check it (workstation)

Copy the kit to a real filesystem (`/tmp` — FAT/exFAT has no executable bit), then:

```sh
bash check-utrust.sh
```

All checks pass → proceed. The go/no-go gates are **4** (PIV AID select `9000`) and **6**
(`pkcs11-tool --module …/opensc-pkcs11.so --list-slots` lists the token) — decision rule in
[research 54 §4](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md). Gate 4 fails → Windows
(Key Manager / `certreq`) or an NFC+ SKU instead.

## 3. Provision the root on the token — once ever

[02-issuing-root-cert.md](02-issuing-root-cert.md): change the factory PIV defaults, keygen in slot 9C
(`pkcs11-tool --keypairgen --key-type EC:prime256v1 --slot-id 0x9C --label "Homelab Root CA" --login`),
create the 10-year self-signed root over it (`step certificate create --kms … --key …`, verified URI
shapes in research 54 §5), record the fingerprint outside the repo, test-sign a throwaway CSR.
Replacing a root is a trust rotation (#144), not a re-run — this step never repeats.

## 4. Sign — every time, incl. the annual re-sign

[03-signing-csr.md](03-signing-csr.md):

```sh
SIGN_PIV_ALLOW_NETWORK=1 ./sign-piv.sh "<token label>"      # intermediate_ca.csr -> intermediate_ca.crt
SIGN_PIV_ALLOW_NETWORK=1 ./sign-ipa-ca.sh "<token label>"   # FreeIPA M1: ipa.csr -> ipa-ca.crt
```

`<token label>` is the `token label` from `pkcs11-tool --list-slots`. `SIGN_PIV_ALLOW_NETWORK=1` is the
explicit acceptance of a networked workstation (the key is non-exportable; residual risk is one rogue
intermediate while plugged in). The script prints the CSR first — verify subject and public key — prompts
the PIN per signature, and machine-checks the result (chains to root, `is_ca`, `pathlen:0`, SANs
`ca.internal` + `192.168.2.215`, 1 year) before it replaces the old cert. Never `--profile
intermediate-ca` — it drops the SANs.

Bring back only the public certs (`root_ca.crt`, `intermediate_ca.crt`, `ipa-ca.crt`); unplug the token
back to the safe.

## Abort criteria

- Any health-check gate fails → stop before step 3; nothing has been written to the token.
- A script aborts or prints `FAIL` → stop, keep the exact output, record it in
  [research 54 §3](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md) with what was verified where
  (a probe result is not a hardware result). A failed run changes nothing on the token — a
  signed-but-rejected certificate is discarded, never installed — and re-signing the same CSR is safe.
- Do not improvise around a refusal: the network warning, the gates and the `FAIL` checks are deliberate.

## Reference

- [Runbook 46](../runbooks/46-adopt-utrust-piv-root-custody.md) — adoption: reissue + trust rotation
- [Research 54](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md) — diagnostic, gates, verified command shapes
- [Runbook 35 §6–§7](../runbooks/35-deploy-step-ca.md) — produces the CSR, installs the signed intermediate
- [Runbook 41](../runbooks/41-deploy-freeipa-server.md) — FreeIPA external-CA flow
- [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — 10-year root on the token, 1-year TPM-bound intermediate
