# 03 — Signing the intermediate CSR with the token

Signs `intermediate_ca.csr` with the root on the uTrust token. This is the operation that **repeats** —
run it at every signing, including the annual re-sign before the intermediate expires.

## Before you start

- The kit is on the workstation, `step` and `step-kms-plugin` run, `libpcsclite1` is installed —
  [01](01-building-step.md), [README](README.md) steps 1–2.
- The token is attached and `check-utrust.sh` passes (gates 4 + 6).
- The root already exists on the token — provisioned by [02](02-issuing-root-cert.md) — and
  `root_ca.crt` (the public cert) is in the kit.

## Run it

```sh
SIGN_PIV_ALLOW_NETWORK=1 ./sign-piv.sh "<token label>"
```

(`<token label>` is the `token label` line from `pkcs11-tool --list-slots`; omit it and the script probes.
`SIGN_PIV_ALLOW_NETWORK=1` is the explicit acceptance that the workstation is networked — the root key
is non-exportable, so the residual risk is one rogue intermediate while the token is plugged in, not key
theft. On an air-gapped machine the variable is not needed.)

The script runs exactly this, prompting the **PIV PIN via PC/SC immediately before the signature**
(never `pin-value=`):

```sh
./step certificate sign --template intermediate-ca.tpl --not-after 8760h \
  intermediate_ca.csr root_ca.crt \
  "pkcs11:module-path=/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so;token=<token label>;object=Homelab Root CA;type=private" \
  > intermediate_ca.crt.new      # printed and machine-checked first, renamed once it passes
```

Before signing it prints the full CSR (`step certificate inspect intermediate_ca.csr`) — **verify the
subject and public key on screen**; that is the TOCTOU guard against a swapped request.

**`--template`, never `--profile intermediate-ca`.** A profile rebuilds the certificate from its own
defaults and silently drops the SANs — the intermediate's declared identity shape. Measured 2026-10-11:
the certificate that serves TLS is a **separate self-issued leaf** the CA builds from `ca.json`'s
provisioner, so the intermediate itself carries no TLS role — but its SANs (`ca.internal`,
`192.168.2.215`) are what the deployment records and audits expect, and `sign-piv.sh` machine-checks
them.

## Machine checks (all must read OK before the cert is promoted)

- chains to `root_ca.crt` in the kit (`step certificate verify`)
- `is_ca`, `pathlen:0`, key usage certSign + crlSign
- SANs present, carrying `ca.internal` and `192.168.2.215`
- validity 1 year (8760h)

A `FAIL` line means: stop, carry nothing away. The token is untouched and re-signing the same CSR is
safe; a previously signed `intermediate_ca.crt` on disk is left untouched.

## FreeIPA CA

When M1 needs it, bring `ipa.csr` (from the IPA guest) into the kit and run
`SIGN_PIV_ALLOW_NETWORK=1 ./sign-ipa-ca.sh "<token label>"` — same token root, `ipa-ca.tpl`, 5 years,
subject `CN=Certificate Authority,O=IPA.INTERNAL` checked.
