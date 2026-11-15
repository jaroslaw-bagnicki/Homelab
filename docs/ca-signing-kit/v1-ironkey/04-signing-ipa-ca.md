# 04 — Signing the FreeIPA CA

Signs `ipa.csr` with the offline root, making the FreeIPA CA a sibling under the fleet root
([ADR 42](../../decisions/42-pki-topology-sibling-cas.md)). This is [runbook 41](../../runbooks/41-deploy-freeipa-server.md) §7.

Run once per IPA CA — at the M1 build, and again whenever `ipa-server-install --external-ca` produces a
new CSR.

## Before you start

| Need | Where it comes from |
|---|---|
| `ipa.csr` | the IPA guest, from `ipa-server-install --external-ca` (runbook 41 §6) |
| `step` | this bundle, one level up — [01](01-building-step.md) |
| `root_ca.crt` + `root_ca_key` | the stick, created once ever — [02](02-issuing-root-cert.md) |
| the root key passphrase | Keeper Vault |

Get the CSR off the guest (it is public — no key material):

```sh
ssh fleetadm@192.168.2.250 'sudo cat /root/ipa.csr' > ipa.csr
openssl req -in ipa.csr -noout -subject
# expected: subject=O = LAB.INTERNAL, CN = Certificate Authority
```

Put it in `docs/ca-signing-kit/` or beside the script — it looks in both.

> **`O=` must be `LAB.INTERNAL`.** The realm was renamed from `IPA.INTERNAL` on 2026-11-15
> ([ADR 43](../../decisions/43-freeipa-domain-realm.md) third amendment). A CSR generated before that
> carries the old name — regenerate it from the guest.

## Run it

```sh
./sign-ipa-ca.sh <stick-mount>
# e.g. ./sign-ipa-ca.sh /mnt/sdX1
```

It asks for the root key passphrase. Non-interactively, pass a file as the second argument, then delete
it:

```sh
./sign-ipa-ca.sh <stick-mount> /tmp/rootpass.txt
```

It runs:

```sh
./step certificate sign --template ../ipa-ca.tpl --not-after 8760h \
  ipa.csr <stick-mount>/root_ca.crt <stick-mount>/root_ca_key > ipa-ca.crt.new
```

**`--template`, never `--profile`.** A profile rebuilds the certificate from its own defaults and
silently drops what the requester asked for. `ipa-ca.tpl` fixes the shape: `CN=Certificate Authority,
O=LAB.INTERNAL`, `CA:TRUE`, `pathlen:0`.

## Acceptance

The script verifies the chain against the stick root and checks `is_ca: true`, then renames
`ipa-ca.crt.new` to `ipa-ca.crt` and prints the certificate. **Read the dump — it must show:**

| Field | Expected |
|---|---|
| Issuer | `CN=Homelab Internal CA` — the root |
| Subject | `CN=Certificate Authority, O=LAB.INTERNAL` |
| Validity | ~1 year |
| Basic Constraints | critical `CA:TRUE, pathlen:0` |
| Key Usage | critical Digital Signature, Certificate Sign, CRL Sign |

If the chain or the CA check fails the script exits non-zero and nothing is renamed. The root is
untouched — signing the same CSR again is safe.

## Carry back

Two files, both **public**:

```sh
scp ipa-ca.crt root_ca.crt fleetadm@192.168.2.250:/tmp/
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
| `ipa.csr is missing` | Copy the CSR into this folder or the kit root. |
| `root_ca.crt not found` | The stick is not mounted, or the path is wrong. |
| `step is missing` | Build it — [01](01-building-step.md). |
| `error decrypting … password incorrect` | Wrong passphrase. Nothing was written; re-run with the right one. |
| `FAIL: not a CA` | The template was edited. Restore `ipa-ca.tpl`. |
| Certificate does not chain | The stick holds a **different** root than the fleet trusts. Stop. |
