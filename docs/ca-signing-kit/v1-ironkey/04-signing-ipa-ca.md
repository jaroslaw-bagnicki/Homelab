# 04 — Signing the FreeIPA CA

Signs `ipa.csr` with the offline root. This is the step [runbook 41](../../runbooks/41-deploy-freeipa-server.md)
§7 calls, and it is what turns FreeIPA's CA into a **sibling under the fleet root** instead of a
self-signed island ([ADR 42](../../decisions/42-pki-topology-sibling-cas.md)).

Run it **once per IPA CA** — at the M1 build, and again whenever `ipa-server-install --external-ca`
produces a new CSR.

## Before you start

Three things must be true, and the script aborts with a specific message if any is not:

| Need | Where it comes from | If missing |
|---|---|---|
| `ipa.csr` | the IPA guest, from `ipa-server-install --external-ca` (runbook 41 §6) | `ABORT: ipa.csr is missing` |
| `step` | this bundle, one level up — [01](01-building-step.md) | `ABORT: …/step is missing or not executable` |
| `root_ca.crt` + `root_ca_key` on the stick | [02](02-issuing-root-cert.md), once ever | `ABORT: …/root_ca.crt not found (is the stick mounted?)` |

### Get the CSR off the guest first

The CSR is public — it carries no key material — so it travels in the clear:

```sh
ssh fleetadm@192.168.2.250 'sudo cat /root/ipa.csr' > ipa.csr
openssl req -in ipa.csr -noout -subject
# expected: subject=O = LAB.INTERNAL, CN = Certificate Authority
```

Put it in the bundle directory (`docs/ca-signing-kit/`) **or** beside this script
(`docs/ca-signing-kit/v1-ironkey/`) — the script looks in both.

> **Check the subject before you sign.** `O=` must be the **current realm**. The realm was renamed from
> `IPA.INTERNAL` to `LAB.INTERNAL` on 2026-11-15 ([ADR 43](../../decisions/43-freeipa-domain-realm.md)
> third amendment); a CSR generated before that carries the old name, and the script's own subject check
> will reject it. If it reads `O = IPA.INTERNAL`, the CSR is stale — regenerate it from the guest.

## Run it

On the signing machine, with the stick mounted:

```sh
./sign-ipa-ca.sh <stick-mount>
# e.g. ./sign-ipa-ca.sh /mnt/sdX1
```

It asks for the root key's passphrase. To drive it non-interactively, put the passphrase in a file and
pass the path as the second argument — then **delete that file before powering off**:

```sh
./sign-ipa-ca.sh <stick-mount> /tmp/rootpass.txt
```

It runs exactly this:

```sh
./step certificate sign --template ../ipa-ca.tpl --not-after 43800h \
  ipa.csr <stick-mount>/root_ca.crt <stick-mount>/root_ca_key \
  > ipa-ca.crt.new          # checked first, renamed to ipa-ca.crt once it passes
```

**`--template`, never `--profile`.** A profile rebuilds the certificate from its own defaults and
silently drops what the requester asked for. `ipa-ca.tpl` fixes the shape the signer must assert:
`CN=Certificate Authority, O=LAB.INTERNAL`, `CA:TRUE`, `pathlen:0`.

The script signs into `ipa-ca.crt.new`, checks that file, and only then renames it. A failed run cannot
leave a half-written certificate to carry home, and cannot overwrite a previous good one.

## Acceptance

The script machine-checks the result. **Every line must read OK:**

| Check | Expected |
|---|---|
| chain | `certificate verify` succeeds against the root on the stick |
| is a CA | `is_ca: true` |
| path length | `max_path_len: 0` — it issues leaves, nothing deeper |
| key usage | `certificate_sign` and `crl_sign` |
| subject | `CN=Certificate Authority` and `O=LAB.INTERNAL` |
| validity | **5 years** — `"length": 157680000` |

If any check fails it prints `STOP: this certificate is not fit to install` and exits non-zero.
**Nothing has been trusted at that point** — the root is untouched and signing the same CSR again is
safe. Fix the cause and re-run; there is no cleanup to do.

## What you carry back

Two files, both **public**:

| File | From | To |
|---|---|---|
| `ipa-ca.crt` | the bundle directory, written by this script | `/root/ipa-ca.crt` on the guest |
| `root_ca.crt` | **a copy from the stick** — not the stick itself | `/root/root_ca.crt` on the guest |

```sh
scp ipa-ca.crt root_ca.crt fleetadm@192.168.2.250:/tmp/
ssh fleetadm@192.168.2.250 '
  sudo install -m 0644 /tmp/ipa-ca.crt /root/ipa-ca.crt
  sudo install -m 0644 /tmp/root_ca.crt /root/root_ca.crt
'
```

Then continue with [runbook 41](../../runbooks/41-deploy-freeipa-server.md) §8, which reruns the
workload and completes the install.

**The root key never leaves the stick.** Only `root_ca.crt` — the public certificate — is copied.

## If it refuses

| Symptom | What to do |
|---|---|
| `ABORT: ipa.csr is missing (looked in …)` | The CSR is not in either directory. Copy it there — see above. |
| `ABORT: …/root_ca.crt not found` | The stick is not mounted, or the path is wrong. Check `mount` / `lsblk`. |
| `ABORT: …/step is missing or not executable` | Build it first — [01](01-building-step.md). |
| `FAIL subject: O=LAB.INTERNAL` | The CSR predates the realm rename. Regenerate it on the guest. |
| `FAIL does NOT chain to the root` | The stick holds a **different** root than the one the fleet trusts. Stop — do not install this certificate. |
| `FAIL validity is 5 years` | `--not-after` was edited. Restore `43800h`; do not hand-wave the check. |

## Why 5 years, when the intermediate is annual

The `step-ca` intermediate is re-signed every year ([03](03-signing-csr.md)) because it is the CA that
issues fleet TLS and SSH — rotating it is routine. The IPA CA is different: it signs only FreeIPA's own
service certificates through `certmonger`, and it is baked into the directory at install time. Re-signing
it means reinstalling the server, so it is deliberately long-lived. Re-parenting it later is a real
operation, not an annual chore.
