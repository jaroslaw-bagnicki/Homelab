# 01 — Assembling the kit: `step` + `step-kms-plugin`

Two upstream binaries are not stored in git, so they are put in place when the kit is assembled, on the
connected machine. Everything else here is text and comes down with the repository.

## `step` — the CLI

Two routes. Both produce the identical file.

### From the CA host — fastest

The `ca` guest already has it at `/usr/local/bin/step`, installed and checksum-verified by runbook 35 §6:

```sh
scp fleetadm@192.168.2.215:/usr/local/bin/step docs/private-ca-offline-signing/step
chmod +x docs/private-ca-offline-signing/step
```

### From the upstream release

```sh
curl -fsSLO https://github.com/smallstep/cli/releases/download/v0.31.0/step_linux_amd64.tar.gz
curl -fsSLO https://github.com/smallstep/cli/releases/download/v0.31.0/checksums.txt
grep -E ' +step_linux_amd64[.]tar[.]gz$' checksums.txt | sha256sum -c -
tar -xzf step_linux_amd64.tar.gz                # unpacks to step_0.31.0/
install -m 755 step_0.31.0/bin/step docs/private-ca-offline-signing/step
```

The archive is not flat — the binary sits under `bin/` inside a `step_0.31.0/` directory. This route was
run end to end and produced a byte-identical file to the CA host's copy (the unmodified upstream
release binary, statically linked — it does not load PKCS#11 itself, see below).

## `step-kms-plugin` — required for `pkcs11:` URIs

The stock `step` is static/non-CGO and **execs `step-kms-plugin` for every `pkcs11:` URI** — without it
any ceremony command fails with `exec: "step-kms-plugin": executable file not found in $PATH`
(verified 2026-11-10). The plugin is the CGO build from the separate `smallstep/step-kms-plugin` repo and
links `libpcsclite.so.1`, so the workstation also needs the `libpcsclite1` package:

```sh
curl -fsSLO https://github.com/smallstep/step-kms-plugin/releases/download/v0.17.0/step-kms-plugin_0.17.0_linux_amd64.tar.gz
curl -fsSLO https://github.com/smallstep/step-kms-plugin/releases/download/v0.17.0/checksums.txt
grep -E ' +step-kms-plugin_0.17.0_linux_amd64[.]tar[.]gz$' checksums.txt | sha256sum -c -
tar -xzf step-kms-plugin_0.17.0_linux_amd64.tar.gz   # unpacks to step-kms-plugin_0.17.0/
install -m 755 step-kms-plugin_0.17.0/step-kms-plugin docs/private-ca-offline-signing/step-kms-plugin
```

Put the kit directory on `PATH` (or copy the plugin next to wherever you run from) so `step` finds it.
The PKCS#11 sign path with this exact pair was proven end-to-end on 2026-11-10 against SoftHSM 2.6
(root created with the key in the module, CSR signed via a `pkcs11:` URI, result verified) —
[research 54 §3](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md).

## Confirm before you carry anything

```sh
./docs/private-ca-offline-signing/step version              # Smallstep CLI/0.31.0 (linux/amd64)
./docs/private-ca-offline-signing/step-kms-plugin --help     # usage text = CGO build runs
```

The kit was assembled with **step v0.31.0 + step-kms-plugin v0.17.0**. A newer CLI is fine — the
ceremonies only use `certificate create`, `sign`, `inspect`, `verify` and `fingerprint` — so read the
version strings as a sanity check, not a pin. Bump the version strings above if you deliberately move
forward.

Then carry the folder to the workstation and pick up the [flow in the README](README.md).
