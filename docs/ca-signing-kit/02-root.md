# 02 — Create the root CA (once, ever)

Generates the CA's 10-year **root key inside the token** — PIV slot 9C — so the key never exists in
software, then writes a self-signed certificate over it.

> **This runs once in the life of the CA.** Replacing a root is a trust rotation: every client
> re-trusts, both sibling CAs are re-signed, and the old root is removed from every trust store by
> hand. There is no "re-run" — the repeating job is [03](03-sign.md).
>
> Skip this document entirely if the token already holds the root. That is the steady state.

## Before you start

- [01-setup.md](01-setup.md) is done: `step` and `step-kms-plugin` are in the kit, `pcscd` runs, the
  token is attached to WSL.
- `./Test-uTrustKey.ps1` passes every check.
- **The PIV PIN and PUK are not written down anywhere yet.** Do that first — see step 1.

## Run it

```sh
cd ~/ca-signing-kit
./New-Root.ps1
```

The script walks through six steps and stops if any of them fails. It finds the key itself — there is
nothing to pass in.

### Step 1 — replace the factory credentials

The token ships with PIN `123456`, PUK `12345678` and a published 3DES management key. All three must
be replaced before the root exists, or anyone holding the token can use it.

`piv-tool` prompts interactively. **Write the new PIN and PUK down and put them in the safe before you
start** — they are the only way back into the token, and losing them kills the root. The script asks
you to confirm before it continues.

### Step 2 — generate the key inside slot 9C

```sh
pkcs11-tool --keypairgen --key-type EC:prime256v1 --slot-id 0x9C --label "Homelab Root CA" --login
```

The key is generated **on the card** and is non-exportable: there is no file to copy, back up or
destroy. The PIN policy ("always") is fixed at generation, so every signature prompts.

`step` cannot generate a key on the uTrust Security Key itself — it only uses a key that already exists
on the card — which is why this step exists separately.

### Step 3 — write the self-signed root certificate

```sh
step certificate create "Homelab Internal CA" root_ca.crt --profile root-ca --not-after 87600h \
  --kms "pkcs11:module-path=<module>;token=<label>" \
  --key "pkcs11:module-path=<module>;token=<label>;object=Homelab Root CA;type=private"
```

PC/SC prompts for the PIN. The script builds both URIs for you, percent-encoding the token label.

### Step 4 — verify the shape

The script checks the certificate it just wrote:

- subject `CN=Homelab Internal CA`
- key is P-256
- `CA:TRUE`, `pathlen:1`
- key usage `certSign` + `crlSign`
- validity 10 years

A failure here means do not distribute the certificate. Nothing has been trusted yet.

### Step 5 — prove the token signs

A root that cannot sign is worthless, and this is the cheapest moment to find out. The script signs a
throwaway CSR, verifies it chains to the new root, and deletes it. This is also the first real test of
the PIN prompt.

### Step 6 — record the fingerprint

The script prints it:

```sh
step certificate fingerprint root_ca.crt
```

**Record it in the safe or a password manager — never in the repository.** It is how you recognise
this root later when checking trust stores.

## What you end up with

`root_ca.crt` — public, and the trust anchor distributed to the fleet and workstations by
[runbook 39](../runbooks/39-trust-private-ca.md).

The private key has **no file anywhere**. The only copy is inside the uTrust Security Key. That is the
point of the whole design: there is nothing to leak and nothing to destroy.

## Backup uTrust Security Key

An on-card-generated root has no exportable copy, so a single uTrust Security Key means losing it =
another reissue. If you want a backup, generate the root key in software **once**, import it into
**two** uTrust Security Keys, and destroy the software file immediately. Decide that before running
this script — it changes the ceremony — and record the choice in
[research 54](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md).

## When it refuses

| Symptom | Meaning |
|---|---|
| `A root certificate already exists in the kit` | Correct — this is a once-ever operation. Use `New-Intermediate.ps1` for the repeating job. Re-run with `-Force` only if you are deliberately reissuing the root. |
| `Stopped before creating the root` | You did not confirm the credential change. Do step 1 properly first. |
| `The root certificate does not have the shape…` | Do not distribute it. The key on the token is reusable; investigate before going further. |
| `does not chain to the root it just created` | The token cannot sign correctly. Do not distribute anything. |

Next: [sign the intermediate](03-sign.md).
