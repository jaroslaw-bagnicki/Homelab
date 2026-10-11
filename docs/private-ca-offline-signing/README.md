# Private CA — offline signing bundle

Everything the air-gapped signing machine needs — **except the secure USB stick**.

## What this is, and is not

The fleet CA's **offline root** is created here, and the **intermediate certificate** is signed by it.
Both happen on a machine with no network of any kind, because the root's private key lives on the
stick and must never touch a networked machine. This bundle carries the tool, the request and the
recipes, so the signing machine needs **nothing installed and nothing downloaded**.

**Any live Linux will do.** SystemRescue 13 is the default; an Ubuntu Live desktop works just as well.
Nothing has to be installed: the bundled `step` is statically linked, so it does not care what the host
distribution is. Only two things matter — **no network**, and a shell to run the steps below.

If you use Ubuntu Live rather than SystemRescue, three differences:

| | SystemRescue 13 | Ubuntu Live |
|---|---|---|
| Who you are | `root` | user `ubuntu` with passwordless `sudo` — prefix `sudo` where needed (`mkdir`, `mount`) |
| Removable media | **not** auto-mounted — run `mountall`, or mount it yourself (step 4) | **auto-mounted** under `/media/ubuntu/<label>` — use that path |
| Network | nothing brings it up | NetworkManager may connect by itself — **disable Wi-Fi / unplug the cable** before touching the stick. Both scripts abort if they find a default route. |

It does **not** start the CA and does **not** distribute trust. Nothing in the bundle is private — the
CSR and the template are public. The one secret it produces is the **root key**, and that must leave
the signing machine only on the stick, back into the safe.

## Contents

| File | What it is | Read it |
|---|---|---|
| [`01-building-step.md`](01-building-step.md) | puts the `step` CLI into this bundle | on the connected machine, before you leave |
| [`02-issuing-root-cert.md`](02-issuing-root-cert.md) | creates the 10-year root on the stick | **once ever** |
| [`03-signing-csr.md`](03-signing-csr.md) | signs the intermediate CSR with that root | every signing |
| `step` | the `step` CLI, linux/amd64 — **not stored in git** (42 MB upstream binary), added by 01 | — |
| `intermediate_ca.csr` | the certificate request, created on the CA host by the key that lives in `pve`'s TPM — **not stored in git**, bring the file the CA host produced | — |
| `intermediate-ca.tpl` | the signing template — the extensions the finished certificate must carry | — |
| `root.sh` | creates the root CA on the stick — first run only | — |
| `sign.sh` | signs the CSR with that root, then machine-checks the result | — |

`intermediate-ca.tpl` is a **copy** of `ansible/workloads/step-ca/files/intermediate-ca.tpl`, which is the
versioned source. If you change one, change both — otherwise the signing machine uses the old shape.

## What you must bring (deliberately not in this bundle)

- **The secure USB stick**, unlocked. **Empty** on the first run — that is where `root.sh` writes
  the root. On any later run it already holds `root_ca.crt` and `root_ca_key`.
- The **YUMI multiboot stick**, with this bundle on it. One stick does both jobs: it boots the signing
  machine (SystemRescue 13, or an Ubuntu Live desktop) *and* carries the bundle, so there is no second
  USB to keep track of.
- A safe place to record the root fingerprint and the result.

## Rules

1. **Never put the root on the machine's disk.** It exists only on the mounted stick; unmount and
   remove the stick before powering the machine off.
2. **Never copy `root_ca_key` off the stick** — not into this bundle, not onto the YUMI stick, not
   anywhere on the machine's disk.
3. **The signing machine must have no network** — no LAN cable, no Wi-Fi, and no default route. Both
   scripts refuse to run if they find one.
4. Never sign with `--profile intermediate-ca`. It silently drops the SANs, producing a certificate
   that passes an issuer check and then fails every TLS request (measured 2026-10-11).
5. **`root.sh` runs once, ever.** It refuses to touch an existing root, because replacing a root is a
   trust rotation — every client would have to re-trust — not a re-run. The repeat job is `sign.sh`.
6. **Write the root key passphrase down before you leave the machine.** It is the only way to use the
   root again; lose it and the root key is dead.

## The flow, end to end

1. **On the connected machine.** Put this whole folder onto the YUMI stick, alongside the live ISO, and
   add `step` to it — [01-building-step.md](01-building-step.md).

2. **On the signing machine.** Boot it (SystemRescue 13 or Ubuntu Live) and confirm it is offline:

   ```sh
   ip route          # must print nothing — no default route is what "air-gapped" means
   ```

3. **Copy the bundle off the stick before running anything.** A boot stick is FAT32, exFAT or NTFS —
   none of which has an executable bit, so `chmod +x` silently does nothing there and `./step` fails
   with `Permission denied`. `/tmp` is a real filesystem and works:

   ```sh
   cp -r <usb>/private-ca-offline-signing /tmp/bundle
   cd /tmp/bundle
   chmod +x step root.sh sign.sh
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
   the commands in 02 and 03 read `<mount-path>`.

5. **Create the root — once ever.** Only if the stick does not already hold one. The full ceremony,
   its acceptance checks and its refusals: [02-issuing-root-cert.md](02-issuing-root-cert.md).

6. **Sign the intermediate.** This is the operation that repeats — including the annual re-sign:
   [03-signing-csr.md](03-signing-csr.md).

7. **Finish.** Record the root's fingerprint **while the stick is still mounted** — the next step
   removes it:

   ```sh
   ./step certificate fingerprint <mount-path>/root_ca.crt
   ```

   Then unmount and remove the stick and return it to the safe, copy `intermediate_ca.crt` **and** a
   copy of `root_ca.crt` back onto the YUMI stick (both are public certificates), and power the machine
   off.

## Bring back

- `intermediate_ca.crt` — the signed intermediate
- `root_ca.crt` — a copy taken from the stick
- the root **fingerprint**, recorded in the safe / password manager (**never** in the repo)

These are installed and the CA started by **runbook 35 §7**.

## If something goes wrong

| Symptom | What to do |
|---|---|
| `./step version` fails with `Permission denied` | You are running it from the stick — FAT32, exFAT and NTFS have no executable bit. Copy the bundle to `/tmp` first (step 3). |
| `./step version` fails otherwise | The copy is truncated or corrupt. Re-copy it from the stick. |
| Either script refuses: "has a default route" | The signing machine is not air-gapped. Disconnect it before using the stick. |
| A `FAIL` line appears in the checks | Stop and do not carry the certificate home. No trust has been distributed, the root is untouched and re-signing the same CSR is safe. |

Anything specific to one ceremony — a root that already exists, a missing SAN, a wrong passphrase — is
in the refusals table of [02](02-issuing-root-cert.md) or [03](03-signing-csr.md).

## Reference

- Runbook 35 §6 — produced `intermediate_ca.csr` (the CA host)
- Runbook 36 §2 — creating the 10-year root, in the repo
- Runbook 36 §3 — signing the intermediate, in the repo
- ADR 38 — the hierarchy: 10-year offline root, 1-year TPM-bound intermediate
