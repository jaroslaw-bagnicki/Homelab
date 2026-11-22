# 04 — Signing the FreeIPA CA

Signs `ipa.csr` with the offline root, making the FreeIPA CA a sibling under the fleet root
([ADR 42](../../decisions/42-pki-topology-sibling-cas.md)). This is [runbook 41](../../runbooks/41-deploy-freeipa-server.md) §7.

Run once per IPA CA — at the M1 build, and again whenever `ipa-server-install --external-ca` produces a
new CSR.

## Before you start

Run this on the **Windows workstation** that holds the stick — it is the path this document is
written for, and the one that is proven. `step.exe` and the templates sit in the bundle; the root sits
at the stick's root.

| Need | Where it comes from |
|---|---|
| `ipa.csr` | the IPA guest, from `ipa-server-install --external-ca` (runbook 41 §6) |
| `step.exe` | this bundle — [01](01-building-step.md) |
| `root_ca.crt` + `root_ca_key` | the stick, created once ever — [02](02-issuing-root-cert.md) |
| the root key passphrase | **Keeper Vault** |

> **The root key passphrase is in Keeper Vault — not on the stick, not in this repo.** Open the entry
> *before* you start: the signing command prompts for it and will not continue without it, and
> `root_ca_key` is unreadable if the passphrase is lost.

Get the CSR off the guest (it is public — no key material):

```sh
ssh fleetadm@192.168.2.250 'sudo cat /root/ipa.csr' > ipa.csr
openssl req -in ipa.csr -noout -subject
# expected: subject=O = LAB.INTERNAL, CN = Certificate Authority
```

Put it in the bundle directory — `H:\RootCA\ca-signing-kit` on the signing workstation.

> **`O=` must be `LAB.INTERNAL`.** The realm was renamed from `IPA.INTERNAL` on 2026-11-15
> ([ADR 43](../../decisions/43-freeipa-domain-realm.md) third amendment). A CSR generated before that
> carries the old name — regenerate it from the guest.

## Sign

With the stick at `H:\RootCA` and the bundle at `H:\RootCA\ca-signing-kit`:

```powershell
cd H:\RootCA\ca-signing-kit
.\step.exe certificate sign --template .\ipa-ca.tpl --not-after 8760h .\ipa.csr ..\root_ca.crt ..\root_ca_key > .\ipa-ca.crt
```

`..` is the stick. Paste the root key passphrase from Keeper Vault when prompted.

## Check

```powershell
.\step.exe certificate verify .\ipa-ca.crt --roots ..\root_ca.crt
.\step.exe certificate inspect .\ipa-ca.crt
```

`verify` reads only the public root certificate — it never asks for the passphrase.

Expected:

| Field | Value |
|---|---|
| Issuer | `CN=Homelab Internal CA` — the root |
| Subject | `CN=Certificate Authority, O=LAB.INTERNAL` |
| Validity | ~1 year |
| Basic Constraints | critical `CA:TRUE, pathlen:0` |
| Key Usage | critical Digital Signature, Certificate Sign, CRL Sign |

## Carry back

Two files, both **public**:

```powershell
scp .\ipa-ca.crt ..\root_ca.crt fleetadm@192.168.2.250:/tmp/
ssh fleetadm@192.168.2.250 'sudo install -m 0644 /tmp/ipa-ca.crt /root/ipa-ca.crt; sudo install -m 0644 /tmp/root_ca.crt /root/root_ca.crt'
```

`root_ca.crt` is a **copy** from the stick. The root key never leaves it.

Then continue with [runbook 41](../../runbooks/41-deploy-freeipa-server.md) §8.

## If it refuses

| Symptom | What to do |
|---|---|
| `ipa.csr` missing | Copy the CSR into the bundle directory. |
| `root_ca.crt not found` / `root_ca_key not found` | The stick is not mounted, or the path is wrong. |
| `exec: "step-kms-plugin": executable file not found in %PATH%` | **Not a plugin problem.** `step` prints this whenever the key argument is not a readable file — it then falls back to reading it as a `kms:` URI. Check the path to `root_ca_key`. The `step-kms-plugin` shipped in the bundle is a Linux ELF and can never run on Windows anyway. |
| `error decrypting … password incorrect` | Wrong passphrase. Nothing was written; re-run with the right one. |
| Certificate does not chain | The stick holds a **different** root than the fleet trusts. Stop. |
