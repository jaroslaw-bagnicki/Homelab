# Private CA — signing kit

Two kits, one job: hold the 10-year root key, and use it to sign the CAs that sit under it. Pick the
one that matches the custody device you actually have.

| | Kit | Custody | Status |
|---|---|---|---|
| **v1** | [`v1-ironkey/`](v1-ironkey/README.md) | IronKey — encrypted key file on a stick, air-gapped ceremony | ✅ **Active** |
| **v2** | [`v2-utrust-token/`](v2-utrust-token/README.md) | PIV token, key generated on-device, PIN per signature | ⏸ **Dormant** — needs an NFC+ token |

## Which one

**Use v1.** The root key lives on the IronKey, and that is the custody
[ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) currently accepts.

**v2 is dormant, not retired.** It is the better design — the key is non-exportable and never exists in
software — but the token it needs does not work. The plain-NFC uTrust 905601 was trialled and rejected
on 2026-11-14: its PIV applet answers AID select but cannot generate a key
([research 54 §9](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md)). v2 stays here, complete and
correct, until a **uTrust FIDO2 NFC+** (or a YubiKey 5) arrives. Then it becomes the active kit and
v1 is retired.

## The mental model

```
root key  ── lives offline, never leaves its custody device
   │
   ├── signs ── step-ca intermediate   (1 year, key in pve1's TPM)   ← re-signed annually
   └── signs ── FreeIPA CA             (5 years, key on the IPA guest)
```

Two things follow from that picture, and they explain both kits:

- **Creating the root happens once, ever.** Replacing a root is a trust rotation — every client
  re-trusts, both CAs are re-signed, the old root is removed by hand. There is no "re-run".
- **Signing the CAs is the repeating job.** That is the annual ceremony, and it is what the scripts
  are mostly for.

The two kits differ only in **where the root key lives** and therefore **how the ceremony is isolated**:

| | v1 — IronKey | v2 — token |
|---|---|---|
| Root key | encrypted file on the stick | generated on the PIV chip, non-exportable |
| Ceremony machine | air-gapped live-USB boot, network physically off | the workstation, network on |
| Per-signature auth | the stick's passphrase | the PIV PIN |
| Worst case if the machine is compromised | the key file can be copied | one rogue certificate; the key cannot leave |
| Scripts | POSIX `sh` | PowerShell 7 |

## Shared files

| File | Used by | What it is |
|---|---|---|
| [`intermediate-ca.tpl`](intermediate-ca.tpl) | both | the extensions the `step-ca` intermediate must carry |
| [`ipa-ca.tpl`](ipa-ca.tpl) | both | the FreeIPA CA shape — `CN=Certificate Authority,O=IPA.INTERNAL`, CA:TRUE, pathlen:0 |

Both kits sign the **same** CSRs with the **same** root — only the custody device changes. A certificate
signed by v1 and one signed by v2 chain to the same root, so switching kits is a custody change, never a
trust change (unless the root itself is reissued, which is the trust rotation above).

## Where it runs

- **v1** — an air-gapped live-USB Linux boot. Nothing installed, nothing downloaded; the bundled static
  `step` is all it needs. See [`v1-ironkey/README.md`](v1-ironkey/README.md).
- **v2** — WSL (Ubuntu) on the Windows 11 workstation, with the token handed to WSL by `usbipd`. See
  [`v2-utrust-token/README.md`](v2-utrust-token/README.md).

## Related

- [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — the PKI design and root custody
- [runbook 36](../runbooks/36-private-ca-init.md) — the **active** IronKey ceremony
- [runbook 46](../runbooks/46-adopt-utrust-piv-root-custody.md) — the token adoption, blocked pending hardware
- [research 54](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md) — the token diagnostic and why the 905601 failed
- [runbook 39](../runbooks/39-trust-private-ca.md) — distributing the root to the fleet and workstations
