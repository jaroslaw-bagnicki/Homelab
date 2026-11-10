# Private CA — offline signing bundle

Everything the air-gapped signing machine needs — **except the secure USB stick**.

## What this is, and is not

The fleet CA's **offline root** is created here, the **`step-ca` intermediate** is signed by it, and
(for M1) the **FreeIPA CA** CSR is signed by the same root. All of it happens on a machine with no
network of any kind, because the root's private key lives on the stick and must never touch a
networked machine. This bundle carries the tool, the requests and the recipes, so the signing machine
needs **nothing installed and nothing downloaded**.

**Any live Linux will do.** SystemRescue 13 is the default; an Ubuntu Live desktop works just as well.
Nothing has to be installed: the bundled `step` is statically linked, so it does not care what the host
distribution is. Only two things matter — **no network**, and a shell to run the steps below.

If you use Ubuntu Live rather than SystemRescue, three differences:

| | SystemRescue 13 | Ubuntu Live |
|---|---|---|
| Who you are | `root` | user `ubuntu` with passwordless `sudo` — prefix `sudo` where needed (`mkdir`, `mount`) |
| Removable media | **not** auto-mounted — run `mountall`, or mount it yourself (step 4) | **auto-mounted** under `/media/ubuntu/<label>` — use that path |
| Network | nothing brings it up | NetworkManager may connect by itself — **disable Wi-Fi / unplug the cable** before touching the stick. Both scripts abort if they find **any non-loopback address** (or a default route). |

It does **not** start the CA and does **not** distribute trust. Nothing in the bundle is private — the
CSR and the template are public. The one secret it produces is the **root key**, and that must leave
the signing machine only on the stick, back into the safe.

## Contents

| File | What it is | Read it |
|---|---|---|
| [`01-building-step.md`](01-building-step.md) | puts the `step` CLI **and** `step-kms-plugin` into this bundle | on the connected machine, before you leave |
| [`02-issuing-root-cert.md`](02-issuing-root-cert.md) | provisions the 10-year root **on the token**, slot 9C | **once ever** |
| [`03-signing-csr.md`](03-signing-csr.md) | signs the intermediate CSR with the token root | every signing |
| `step` | the `step` CLI, linux/amd64 — **not stored in git** (42 MB upstream binary), added by 01 | — |
| `step-kms-plugin` | the CGO KMS plugin — **not stored in git**, added by 01; the static `step` execs it for every `pkcs11:` URI | — |
| [`check-utrust.sh`](check-utrust.sh) | read-only token health check (USB, reader, PIV AID `9000`, CPLC, PKCS#11 slot, AAGUID) | first, on the workstation |
| [`sign-piv.sh`](sign-piv.sh) | signs the `step-ca` intermediate CSR with the token root, then machine-checks the result | every signing |
| [`sign-ipa-ca.sh`](sign-ipa-ca.sh) | signs FreeIPA's `ipa.csr` (from `ipa-server-install --external-ca`) with the same token root | the FreeIPA ceremony |
| `intermediate_ca.csr` | the certificate request, created on the CA host by the key that lives in `pve1`'s TPM — **not stored in git**, bring the file the CA host produced | — |
| `intermediate-ca.tpl` | the signing template — the extensions the finished certificate must carry | — |
| `ipa-ca.tpl` | the FreeIPA CA signing template — `CN=Certificate Authority,O=IPA.INTERNAL`, CA:TRUE, pathlen:0 | — |
| `root_ca.crt` | the current root certificate (public) | — |
| `intermediate_ca.crt` | the last signed intermediate (public) | — |

`intermediate-ca.tpl` is a **copy** of `ansible/workloads/step-ca/files/intermediate-ca.tpl`, which is the
versioned source. If you change one, change both — otherwise the signing machine uses the old shape.

## What you must bring (deliberately not in this bundle)

- **The secure USB stick**, unlocked. **Empty** on the first run — that is where `root.sh` writes
  the root. On any later run it already holds `root_ca.crt` and `root_ca_key`.
- The **YUMI multiboot stick**, with this bundle on it. One stick does both jobs: it boots the signing
  machine (SystemRescue 13, or an Ubuntu Live desktop) *and* carries the bundle, so there is no second
  USB to keep track of.
- `ipa.csr` when the M1 FreeIPA CA ceremony runs — produced on the IPA guest, public, not stored in git.
- A safe place to keep the stick and the written-down key passphrase.

## Rules

1. **The root key never exists outside the token** — there is no key file to put on a disk, copy or
   destroy. The token is plugged in **only during signing** and goes back to the safe afterwards;
   **never** plug it into `pve1` / the `ca` guest.
2. **No PIN, PUK, management key or `pin-value=`** in scripts, Ansible, logs or the repo — PC/SC prompts
   the PIN immediately before each signature.
3. **A networked workstation is accepted risk** (the key is non-exportable): the scripts warn if they
   find a non-loopback address or default route, and proceed only with `SIGN_PIV_ALLOW_NETWORK=1`.
4. Never sign with `--profile intermediate-ca`. It silently drops the SANs, which are the CA's declared
   identity shape — the CA is not left unserved (the serving certificate is a separate self-issued leaf,
   runbook 35 §7), but the certificate no longer matches the shape the deployment records.
5. **[02](02-issuing-root-cert.md) runs once, ever.** Replacing a root is a trust rotation — every client
   would have to re-trust — not a re-run. The repeat job is [03](03-signing-csr.md) / `sign-piv.sh`.
6. **Write the PIV PIN/PUK down before the first ceremony.** They are the only way back into the token;
   lose them and the root key is dead.

## The flow, end to end

1. **On the connected machine.** Put this whole folder onto the YUMI stick, alongside the live ISO, and
   add `step` to it — [01-building-step.md](01-building-step.md).

2. **On the signing machine.** Boot it (SystemRescue 13 or Ubuntu Live) and confirm it is offline:

   ```sh
   ip -brief addr show   # only `lo` may carry an address — any other one means the machine is networked
   ip route              # must print nothing — no default route is what "air-gapped" means
   ```

3. **Copy the bundle off the stick before running anything.** A boot stick is FAT32, exFAT or NTFS —
   none of which has an executable bit, so `chmod +x` silently does nothing there and `./step` fails
   with `Permission denied`. `/tmp` is a real filesystem and works:

   ```sh
   cp -r <usb>/private-ca-offline-signing /tmp/bundle
   cd /tmp/bundle
   chmod +x step root.sh sign.sh sign-ipa-ca.sh
   ./step version
   ```

   It must print a `Smallstep CLI/... (linux/amd64)` line. If it prints nothing, the copy is broken —
   re-copy the bundle from the stick. This is the only integrity check the bundle needs.

4. Plug in the **secure USB stick** and make sure it is mounted, noting the path:

   ```sh
   lsblk -o NAME,SIZE,LABEL,FSTYPE      # find the stick's partition
   ```

   - **Ubuntu Live** auto-mounts it — look under `/media/ubuntu/<label>`.
   - **SystemRescue** — `mountall` mounts every filesystem it finds, bringing up both sticks together:

     ```sh
     mountall
     df -h                                # the stick lands at /mnt/sdXN — note that path
     ```

     Use it read-write, never `mountall --readonly`: the root is written to the stick.

     To bring up the secure stick alone instead:

     ```sh
     mkdir -p /mnt/stick
     mount /dev/sdX1 /mnt/stick       # replace sdX1 with the real device from lsblk
     ```

   **Nothing assumes a location.** Wherever the stick lands — `/mnt/sdX1`, `/media/ubuntu/<label>`, or
   a directory you made — that path is the first argument both scripts take. There is no default, so
   the commands in 02 and 03 read `<destination-path>`.

5. **Create the root — once ever.** Only if the stick does not already hold one. The full ceremony,
   its acceptance checks and its refusals: [02-issuing-root-cert.md](02-issuing-root-cert.md).

6. **Sign the intermediate.** This is the operation that repeats — including the annual re-sign:
   [03-signing-csr.md](03-signing-csr.md).

6b. **Sign the FreeIPA CA when M1 needs it.** Bring `ipa.csr` from the IPA guest to this bundle and run
   `./sign-ipa-ca.sh <destination-path>`; copy `ipa-ca.crt` back with `root_ca.crt`. The script checks
   the chain, `CA:TRUE, pathlen:0`, key usage and the `CN=Certificate Authority,O=IPA.INTERNAL`
   subject. This is a separate ceremony from the `step-ca` intermediate.

7. **Finish.** Unmount and remove the stick and return it to the safe, copy `intermediate_ca.crt`
   (and, when used, `ipa-ca.crt`) **and** a copy of `root_ca.crt` back onto the YUMI stick (all are
   public certificates), and power the machine off.

## Bring back

- `intermediate_ca.crt` — the signed `step-ca` intermediate
- `ipa-ca.crt` — the signed FreeIPA CA (when M1 runs its ceremony)
- `root_ca.crt` — a copy taken from the stick

`intermediate_ca.crt` is installed and the CA started by **runbook 35 §7**; `ipa-ca.crt` is installed
by the FreeIPA workload ([runbook 41](../runbooks/41-deploy-freeipa-server.md)).

## If something goes wrong

| Symptom | What to do |
|---|---|
| `./step version` fails with `Permission denied` | You are running it from a FAT/exFAT/NTFS stick — no executable bit. Copy the bundle to `/tmp` first (step 3). |
| `./step version` fails otherwise | The copy is truncated or corrupt. Re-copy it from the stick. |
| `exec: "step-kms-plugin": not found in $PATH` | The plugin binary is missing or the kit dir is not on `PATH` — see step 3 and [01](01-building-step.md); `libpcsclite1` must be installed too. |
| A script warns about a non-loopback address / default route | Accepted risk on the workstation (key is non-exportable) — re-run with `SIGN_PIV_ALLOW_NETWORK=1`. |
| Health-check gate 4 ≠ `9000` or gate 6 lists no token | OpenSC cannot drive the PIV applet on Linux — fall back to Windows (uTrust Key Manager / `certreq`) or an NFC+ SKU; decision rule in research 54 §4. |
| A `FAIL` line appears in the checks | Stop and do not carry the certificate away. No trust has been distributed, nothing on the token changed and re-signing the same CSR is safe. |

Anything specific to one ceremony — a root that already exists on the token, a missing SAN, a wrong PIN —
is in the refusals of [02](02-issuing-root-cert.md) or [03](03-signing-csr.md). On any unexpected error:
stop, keep the exact output, and record it in [research 54 §3](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md)
with what was verified where — a probe result is not a hardware result.

## Reference

- [Runbook 46](../runbooks/46-adopt-utrust-piv-root-custody.md) — the adoption runbook: reissue the root on the token + trust rotation
- [Research 54](../research/54-utrust-fido2-nfc-piv-root-diagnostic.md) — the token diagnostic, hardware gates, verified command shapes
- Runbook 35 §6–§7 — produced `intermediate_ca.csr` (the CA host); installs the signed intermediate
- Runbook 41 — the FreeIPA external-CA flow
- ADR 38 — the hierarchy: 10-year root on the uTrust token, 1-year TPM-bound intermediate
