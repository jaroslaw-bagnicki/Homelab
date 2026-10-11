# 01 — Building the bundle: getting `step`

`step` is a 42 MB upstream binary, so it is not stored in git: it is put in place when the bundle is
assembled, on the connected machine. Everything else here is text and comes down with the repository.

Two routes. Both produce the identical file.

## From the CA host — fastest

The `ca` guest already has it at `/usr/local/bin/step`, installed and checksum-verified by runbook 35 §6:

```sh
scp fleetadm@192.168.2.215:/usr/local/bin/step docs/private-ca-offline-signing/step
chmod +x docs/private-ca-offline-signing/step
```

## From the upstream release

The same source that put it on the CA host — the `smallstep/cli` release for linux/amd64, checked
against that release's own `checksums.txt`:

```sh
curl -fsSLO https://github.com/smallstep/cli/releases/download/v0.31.0/step_linux_amd64.tar.gz
curl -fsSLO https://github.com/smallstep/cli/releases/download/v0.31.0/checksums.txt
grep -E ' +step_linux_amd64[.]tar[.]gz$' checksums.txt | sha256sum -c -
tar -xzf step_linux_amd64.tar.gz                # unpacks to step_linux_amd64/
install -m 755 step_linux_amd64/bin/step docs/private-ca-offline-signing/step
```

The archive is not flat — the binary sits under `bin/` inside a `step_linux_amd64/` directory. This
route was run end to end and produced a byte-identical file to the CA host's copy, which is the
unmodified upstream release binary.

## Confirm it before you carry anything

```sh
./docs/private-ca-offline-signing/step version      # Smallstep CLI/0.31.0 (linux/amd64)
```

The bundle was assembled with **v0.31.0**. A newer CLI is fine — the ceremonies only use
`certificate create`, `sign`, `inspect`, `verify` and `fingerprint` — so read the version string as a
sanity check, not a pin. Bump the two version strings above if you deliberately move forward.

Then carry the folder to the signing machine and pick up the [flow in the README](README.md).
