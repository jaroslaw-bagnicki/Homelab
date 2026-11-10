# 02 — Provision the root on the uTrust token (first run only)

Generates the CA's 10-year **root key on the token itself** — PIV slot 9C — so the key never exists in
software. **First run only**, once in the life of this CA. This is phase 2 of
[runbook 46](../runbooks/46-adopt-utrust-piv-root-custody.md); the diagnostic background is
[research 54](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md).

## Before you start

- The kit is on the workstation and both binaries run — [01](01-building-step.md), [README](README.md)
  step 1–2.
- The token is attached and healthy: `bash check-utrust.sh` passes, including PIV AID select `9000`
  and `pkcs11-tool --module …/opensc-pkcs11.so --list-slots` listing the token (gates 4 + 6).
- `pcscd` runs and `opensc`, `pcsc-tools`, `libpcsclite1` are installed on the workstation.
- **Skip this document completely** if the token already holds the root — that is the steady state;
  the repeat job is [03](03-signing-csr.md). Replacing a root is a trust rotation (issue #144: every
  client must re-trust), not a re-run.

## Run it

```sh
MOD=/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so
TOKEN="$(pkcs11-tool --module "$MOD" --list-slots | sed -n 's/^  token label *: //p' | head -1)"

# 1. change the factory defaults first (manual defaults: PIN 123456, PUK 12345678, 3DES mgmt key)
piv-tool --admin-mode -k            # set management key, then PIN and PUK via pkcs11-tool --change-pin
#    write the new PIN/PUK down and put them in the safe — lose them and the token is dead

# 2. generate the P-256 key pair IN slot 9C — PIN policy "always" is fixed at generation;
#    --login prompts for the PIV PIN, never pin-value
pkcs11-tool --module "$MOD" --keypairgen --key-type EC:prime256v1 \
  --slot-id 0x9C --label "Homelab Root CA" --login

# 3. self-signed 10-year root cert over that on-token key (verified shapes — see research 54 §5:
#    every pkcs11: URI needs token=; step create cannot generate the key itself, hence step 2)
./step certificate create "Homelab Internal CA" root_ca.crt --profile root-ca --not-after 87600h \
  --kms "pkcs11:module-path=$MOD;token=$TOKEN" \
  --key "pkcs11:module-path=$MOD;token=$TOKEN;object=Homelab Root CA;type=private"

# 4. verify the shape, record the fingerprint OUTSIDE the repo (safe / password manager)
./step certificate inspect root_ca.crt        # CN=Homelab Internal CA, P-256, CA:TRUE pathlen:1, certSign+crlSign, 10y
./step certificate fingerprint root_ca.crt

# 5. test-sign a throwaway CSR, then discard it — the PIN is prompted again, per signature
./step certificate sign --not-after 24h probe.csr root_ca.crt \
  "pkcs11:module-path=$MOD;token=$TOKEN;object=Homelab Root CA;type=private" > probe.crt
./step certificate verify probe.crt --roots root_ca.crt
rm -f probe.csr probe.key probe.crt
```

`root_ca.crt` is public — it is the trust anchor distributed by
[runbook 39](../runbooks/39-trust-private-ca.md). The private key has no file anywhere; the only copy
is inside the token. To keep a backup token, generate the key in software once here, import it into a
second uTrust, and destroy the software file immediately (runbook 46's backup note) — otherwise token
loss means another reissue.
