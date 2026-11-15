# 04 — Signing the FreeIPA CA

Signs `ipa.csr` with the offline root, making the FreeIPA CA a sibling under the fleet root
([ADR 42](../../decisions/42-pki-topology-sibling-cas.md)). This is [runbook 41](../../runbooks/41-deploy-freeipa-server.md) §7.

Run once per IPA CA — at the M1 build, and again whenever `ipa-server-install --external-ca` produces a
new CSR.

## Before you start

| Need | Where it comes from |
|---|---|
| `ipa.csr` | the IPA guest, from `ipa-server-install --external-ca` (runbook 41 §6) |
| `step` + `step-kms-plugin` | this bundle, one level up — [01](01-building-step.md) |
| `root_ca.crt` + `root_ca_key` | the stick, created once ever — [02](02-issuing-root-cert.md) |
| the root key passphrase | Keeper Vault |

Get the CSR off the guest (it is public — no key material):

```sh
ssh fleetadm@192.168.2.250 'sudo cat /root/ipa.csr' > ipa.csr
openssl req -in ipa.csr -noout -subject
# expected: subject=O = LAB.INTERNAL, CN = Certificate Authority
```

Put it in `docs/ca-signing-kit/`.

> **`O=` must be `LAB.INTERNAL`.** The realm was renamed from `IPA.INTERNAL` on 2026-11-15
> ([ADR 43](../../decisions/43-freeipa-domain-realm.md) third amendment). A CSR generated before that
> carries the old name — regenerate it from the guest.

## Sign

From `docs/ca-signing-kit`, with the stick mounted at `<stick>`:

```sh
PATH="$PWD:$PATH" ./step certificate sign --template ./ipa-ca.tpl --not-after 8760h ./ipa.csr <stick>/root_ca.crt <stick>/root_ca_key > ./ipa-ca.crt
```

`PATH="$PWD:$PATH"` is required — `step` shells out to `step-kms-plugin` and will not find it otherwise.

It asks for the root key passphrase.

## Check

```sh
./step certificate verify ./ipa-ca.crt --roots <stick>/root_ca.crt
./step certificate inspect ./ipa-ca.crt
```

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

```sh
scp ipa-ca.crt <stick>/root_ca.crt fleetadm@192.168.2.250:/tmp/
ssh fleetadm@192.168.2.250 '
  sudo install -m 0644 /tmp/ipa-ca.crt /root/ipa-ca.crt
  sudo install -m 0644 /tmp/root_ca.crt /root/root_ca.crt
'
```

`root_ca.crt` is a **copy** from the stick. The root key never leaves it.

Then continue with [runbook 41](../../runbooks/41-deploy-freeipa-server.md) §8.

## If it refuses

| Symptom | What to do |
|---|---|
| `step-kms-plugin: executable file not found` | Prefix the command with `PATH="$PWD:$PATH"` — see Sign. |
| `ipa.csr` missing | Copy the CSR into `docs/ca-signing-kit/`. |
| `root_ca.crt not found` | The stick is not mounted, or the path is wrong. |
| `error decrypting … password incorrect` | Wrong passphrase. Nothing was written; re-run with the right one. |
| Certificate does not chain | The stick holds a **different** root than the fleet trusts. Stop. |
