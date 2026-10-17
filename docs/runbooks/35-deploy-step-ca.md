# Private CA — Deploy `step-ca` on `pve` (LXC `ca`, TPM-Bound Intermediate, ACME)

> Stand up the fleet's issuing CA: an unprivileged Debian 13 LXC (`ca`, LXC **215**, `192.168.2.215`)
> on the `pve` node with the host's **TPM 2.0** passed through, running **`step-ca` as a native
> systemd service** (no Docker), serving an **ACME provisioner** for LAN services. The intermediate key
> is created **inside the TPM** and only a **CSR** leaves the host; the root signs that CSR **offline**
> ([runbook 36](36-private-ca-init.md)). Decision:
> [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md); mechanics:
> [research 36 §5](../research/36-step-ca-machine-identity.md); measured gate:
> [#141](https://github.com/jaroslaw-bagnicki/Homelab/issues/141).
>
> ⚠ **Executed — §1–§7 run 2026-10-11**, together with the offline ceremony
> ([runbook 36](36-private-ca-init.md)) the same day. Each section carries an **Execution record** with
> the output observed on the run. §8 is operations: the only outstanding item is the annual re-sign
> reminder. The runbook was written from ADR 38, research 36–37, and the
> [#141](https://github.com/jaroslaw-bagnicki/Homelab/issues/141) gate, which measured the TPM and LXC
> mechanics on `pve` — gate-measured facts are marked **(measured #141)**.
>
> ⚠ **Order — one-way.** Run **§1–§6 first**, then the offline ceremony
> ([runbook 36](36-private-ca-init.md)), then **resume at §7**. §1–§6 need no root key and end by
> handing out `intermediate_ca.csr`; §7 installs the root-signed certificate and starts the service.
>
> ⚠ **Scope.** This is the **on-host deployment**; the offline root/intermediate signing is
> [runbook 36](36-private-ca-init.md). Root distribution to the fleet is
> [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144), proxy wiring is
> [#142](https://github.com/jaroslaw-bagnicki/Homelab/issues/142), and the first migrated service is
> [#143](https://github.com/jaroslaw-bagnicki/Homelab/issues/143) — all out of scope.
>
> ⚠ **Execution note.** Author on `docs/private-ca-runbooks`; **run only after CR**. §1–§2 are
> manual/console on the `pve` host, reached as `ssh fleetadm@192.168.2.201`; the Ansible steps (§4–§7)
> run with the fleet key loaded ([`fleet-connect` skill](../../.opencode/skills/fleet-connect/SKILL.md)).

## Why

The CA is the answer to [ADR 34](../decisions/34-lan-tls-only.md)'s unauthenticated-TLS gap: it is the
fleet trust anchor that lets a client verify a LAN service instead of clicking past a warning.

It must run on **`pve`** — the TPM makes that a hard requirement, because a TPM-bound intermediate key
cannot move to another machine ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)). The
`pve` TPM is an **Intel PTT firmware TPM** (measured 2026-10-04,
[research 37 §5](../research/37-tpm2-hardware-and-fleet.md)); it is a genuine TPM 2.0 implementation, so
the key stays non-exportable, but it is platform firmware rather than a discrete chip.

`step-ca` runs as a **native systemd service**, not a container: the TPM KMS is pure Go on the stock
binary, so there is nothing to build or ship, and a CA operating on a hardware key should have the
smallest possible attack surface ([research 36 §5](../research/36-step-ca-machine-identity.md)). A
dedicated unprivileged LXC keeps it off the Proxmox host and away from the edge services.

## What changes

- **LXC 215 `ca`** — unprivileged, **Debian 13**, `nesting=1`, static `192.168.2.215`, `onboot 1`,
  1 vCPU / 512 MiB / 8 GiB rootfs, with `/dev/tpmrm0` passed through. Next free guest in the `21x`
  block ([ADR 31](../decisions/31-static-address-scheme.md) — VMID = last octet).
- **Reboot-durable TPM device ownership on `pve`** — a udev rule, because an unprivileged container's
  root maps to host subuid `100000` and cannot open a `root:root 0600` device (measured #141).
- **Base roles** — `common` (hostname, UTC, NTP, **Avahi**), `security` (UFW default-deny; SSH + CA
  `9000` from `192.168.2.0/24`), `fluentbit` (ships the CA's journald to VictoriaLogs on `vtstack`).
- **`ansible/workloads/step-ca/`** — a self-contained recipe installing `step-ca` + `step` CLI +
  `step-kms-plugin` (checksum-verified) and `libpcsclite1`, creating the intermediate key in the TPM,
  and emitting `intermediate_ca.csr`.
- **An ACME provisioner** — so the reverse proxy ([#142](https://github.com/jaroslaw-bagnicki/Homelab/issues/142))
  and services renew short-lived leaves automatically.
- **No node backup** — the CA's recovery is **re-issue, not restore** ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)):
  the offline root stays untouched and the intermediate is re-signed, with no client re-trust.

## Prerequisites

- [ ] `pve` base-provisioned — Proxmox VE + `fleetadm` ([runbook 28](28-pve-proxmox-node.md)).
- [ ] TPM available and cleared on second-hand hardware (`Clear PTT` in BIOS;
      [research 37 §5](../research/37-tpm2-hardware-and-fleet.md)).
- [ ] A Debian 13 LXC template available on the `pve` node (`pveam`).
- [ ] Ansible collections installed (`ansible-galaxy collection install -r ansible/requirements.yml`).
- [ ] Azure Key Vault `homelab-bysxdb-kv` reachable from the controller (CA provisioner password —
      provisioned in §5 — and the Fluent Bit store password like every other node).
- [ ] Controller Python packages for the Key Vault lookup — `azure-identity` and
      `azure-keyvault-secrets` (`pip3 install --break-system-packages azure-identity azure-keyvault-secrets`).
- [ ] `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` and `AZURE_TENANT_ID` exported on the controller — the
      role reads the Key Vault secret through them.
- [ ] Fleet key in `ssh-agent` (`ssh-add -l` shows `fleetadm@homelab`).
- [ ] The secure USB stick and the air-gapped signing machine are needed for the **later** offline step
      ([runbook 36](36-private-ca-init.md)), not for §1–§6.

---

## 1. Reboot-durable TPM device access on `pve`

An unprivileged container's root maps to host subuid **`100000`**, so a bind-mounted `/dev/tpmrm0`
that is `root:root 0600` on the host appears inside the container as `nobody` and every open fails with
`permission denied` (measured #141). The device allow + bind mount go in the LXC config (§2); the
**ownership** fix is host-side and must survive reboots.

```sh
# on pve
ls -l /dev/tpmrm0        # read the major/minor off the host — do not assume

# Only the resource-manager node is used: the CA's tpmkms opens /dev/tpmrm0, and /dev/tpm0 is
# never touched by anything, so it gets no rule. Note /dev/tpmrm0 is its own SUBSYSTEM ("tpmrm",
# not "tpm") — a rule written as SUBSYSTEM=="tpm" matches only tpm0 and leaves the node the CA
# uses at root:root (measured 2026-10-11).
cat >/etc/udev/rules.d/60-tpm-lxc.rules <<'EOF'
SUBSYSTEM=="tpmrm", KERNEL=="tpm*", RUN+="/bin/chown 100000:100000 /dev/%k"
EOF

udevadm control --reload-rules
# `udevadm trigger` defaults to the "change" action, which does NOT run RUN keys — ownership only
# lands with --action=add (measured 2026-10-11).
udevadm trigger --action=add --subsystem-match=tpmrm
ls -l /dev/tpmrm0        # owner must now be 100000:100000
```

- **Only `tpmrm` is owned.** `/dev/tpmrm0` is a *separate subsystem* (`tpmrm`, not `tpm`) **and** the
  only node the CA opens; `/dev/tpm0` is passed to no process and gets no rule. A rule written as
  `SUBSYSTEM=="tpm"` therefore matches `tpm0` only and leaves the node the CA actually uses at
  `root:root` (measured 2026-10-11).
- **`--action=add` is required.** A bare `udevadm trigger` (action `change`) does not execute `RUN`
  keys, so the rule is installed but nothing is chowned until the next boot (measured 2026-10-11).
- The udev rule is the **persistent** form of the one-shot `chown 100000:100000 /dev/tpmrm0` the gate
  used; without it the ownership is lost on reboot.
- The gate read `/dev/tpmrm0` as `252:65536`; always `ls -l` on the host (the `252` major is dynamic).
  That pair is used in the LXC config (§2).
- A **privileged** container avoids the ownership change, at the cost of the isolation the unprivileged
  shape exists for — not used here.

> **Execution record — 2026-10-11 (`pve`).** Rule written, then `udevadm control --reload-rules` and
> `udevadm trigger --action=add --subsystem-match=tpmrm`:
> `/dev/tpmrm0` → `crw------- 100000 100000 252, 65536` ✅ (`/dev/tpm0` left `root:root`, unused).
> Two corrections were needed and are folded into the block above: the rule must match the `tpmrm`
> subsystem (the node the CA opens), and `udevadm trigger` must use `--action=add` — the default
> `change` action does not run `RUN` at all. **Reboot persistence proven same day** — after a `pve`
> reboot the rule fired on its own: `/dev/tpmrm0` → `100000:100000`, `/dev/tpm0` → `root:root` (no
> rule covers it, as intended).

## 2. Create LXC 215 `ca`

On the `pve` host (`ssh fleetadm@192.168.2.201`, then `sudo -i`):

```sh
pveam update
pveam available --section system | grep debian-13
pveam download local <debian-13-template-from-the-line-above>
pveam list local

pct create 215 local:vztmpl/<template> \
  --hostname ca --unprivileged 1 \
  --features nesting=1 \
  --cores 1 --memory 512 --swap 512 \
  --rootfs local-lvm:8 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.2.215/24,gw=192.168.2.1 \
  --onboot 1
```

- **`nesting=1` is required** (measured 2026-10-11). Debian 13's systemd (257) mounts its own `/tmp`,
  `/run/lock` and `/dev/mqueue`; in an unprivileged container **without** nesting those three units
  fail — `mount: /run/lock: tmpfs already mounted on /dev/shm`, because LXC already holds a tmpfs
  there. The cost is not cosmetic: without `tmp.mount`, `/tmp` is a plain directory on the rootfs, so
  it is **not `nosuid`/`nodev`**, not RAM-backed and not wiped on reboot — and because `/dev/tpmrm0`
  is owned by container root, a setuid binary dropped in `/tmp` is a route to the CA's key. With
  nesting the three mounts are restored with their intended options (`nosuid,nodev`; `noexec` + a
  5 MiB cap on `/run/lock`) and `systemctl --failed` is genuinely empty. Measured against `vtstack`,
  which runs `nesting=1`.
- **No `fuse=1`** — `step-ca` is native, not Docker.
- **`--onboot 1`** — the CA must return on its own after a host reboot.
- `--rootfs local-lvm:8` is a starting estimate; `step-ca` and its state are small, re-check after
  deployment.
- DNS is **not** pinned at build time — the guest inherits the host resolvers for now. [ADR 40](../decisions/40-internal-dns-proxy-edge.md)
  makes the resolver a prerequisite for ACME: once the `.internal` stack runs on `edge`, point this
  guest at `192.168.2.240` so `step-ca` can resolve service names during challenge validation.

Append the TPM passthrough to `/etc/pve/lxc/215.conf`:

```ini
lxc.cgroup2.devices.allow: c 252:65536 rwm    # /dev/tpmrm0
lxc.mount.entry: /dev/tpmrm0 dev/tpmrm0 none bind,optional,create=file
```

```sh
pct start 215
pct exec 215 -- ls -l /dev/tpmrm0     # present and owned by container root
```

- The device numbers must match §1's host reading; update the config if the host differs.
- Keep the Proxmox network **Firewall** flag at `0` — the boundary is the in-container UFW (§4).

> **Execution record — 2026-10-11 (`pve`).** Guest created, passthrough appended, started. `pct
> status` → `running`; `systemctl --failed` → **0 units** (`0 loaded units listed`); `findmnt` →
> `/tmp` `rw,nosuid,nodev,nr_inodes=1048576`, `/run/lock` `rw,nosuid,nodev,noexec,size=5120k`,
> `/dev/mqueue` `rw,nosuid,nodev,noexec`; `/dev/tpmrm0` inside → `crw------- root root 252, 65536` ✅.
> **Two defects the first run exposed:** (1) with no `nesting=1` all three mount units fail and `/tmp`
> stays a rootfs directory without `nosuid`/`nodev` — see the bullet above; (2) the `tpm0` passthrough
> this runbook originally carried was dead weight (nothing opens it) and has been removed.
>
> **Post-reboot (same day, after a `pve` reboot).** `onboot 1` brought the guest up (`pct list` →
> `running`; note PVE starts guests a little *after* the host is reachable, so an immediate check can
> briefly see `stopped`). Inside: `/dev/tpmrm0` → `crw------- root root 252, 65536`,
> `systemctl --failed` → 0 units, and `/tmp`, `/run/lock`, `/dev/mqueue` still mounted with
> `nosuid,nodev`; eth0 `.215`; `ssh fleetadm@192.168.2.215 'sudo -n whoami'` → `root`.

## 3. `fleetadm` bootstrap (unblock Ansible)

Mirrors [runbook 33 §2](33-deploy-victorialogs.md). From the `pve` host (the fleet public key lives at
`ansible/roles/common/files/ssh/fleetadm.pub`, [ADR 28](../decisions/28-fleet-admin-account-and-key.md)):

```sh
pct exec 215 -- bash -lc '
apt-get update && apt-get install -y sudo
id -u fleetadm >/dev/null 2>&1 || useradd -m -s /bin/bash fleetadm
usermod -aG sudo fleetadm
echo "fleetadm ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/fleetadm
chmod 440 /etc/sudoers.d/fleetadm
mkdir -p /home/fleetadm/.ssh && chmod 700 /home/fleetadm/.ssh
printf "no-port-forwarding,no-agent-forwarding,no-X11-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKAucOXvwvHvSn11uzG49QFvJPxodbOjPEWkvdS9vCVG fleetadm@homelab\n" > /home/fleetadm/.ssh/authorized_keys
chmod 600 /home/fleetadm/.ssh/authorized_keys
chown -R fleetadm:fleetadm /home/fleetadm/.ssh
passwd -l fleetadm
'
```

**Verify from the control node** (LAN workstation with the fleet key loaded):

```sh
ssh fleetadm@192.168.2.215 'sudo -n whoami'   # → root
```

> **Execution record — 2026-10-11.** Account verified: `authorized_keys` matches
> `ansible/roles/common/files/ssh/fleetadm.pub` (compared *before* installing — it is current),
> `passwd -S fleetadm` → `L`, `/etc/sudoers.d/fleetadm` `0440 root:root`, `~/.ssh` `0700`,
> `authorized_keys` `0600`. `ssh fleetadm@192.168.2.215 'sudo -n whoami'` → `root`, key-only ✅.
> Note for §4: `sshd -T` still reports `passwordauthentication yes` — the `security` role is expected
> to turn that off and must be verified there.

## 4. Ansible base provision + enrollment

Add the guest to `ansible/inventory.ini` (`[proxmox_guests]`):

```ini
ca ansible_host=192.168.2.215 ansible_user=fleetadm
```

Add `ansible/host_vars/ca.yml`:

```yaml
common_enable_avahi: true

security_ufw_deny_inbound_tcp_80: true
security_ufw_allow_ssh_from: "192.168.2.0/24"
security_ufw_allow_tcp_from: "192.168.2.0/24"
security_ufw_allow_tcp_ports:
  - 9000
```

Add `ansible/playbooks/playbook-ca.yml`:

```yaml
---
- name: Configure ca (private CA guest on pve) base
  hosts: ca
  become: true
  roles:
    - common
    - security
    - fluentbit
```

From the repo root on the LAN workstation:

```powershell
# Dev container only — world-writable /workspaces breaks ansible.cfg; skip on a LAN workstation:
chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible
ansible-playbook ansible/playbooks/playbook-ca.yml --diff
```

- **`common`** — hostname `ca`, `Etc/UTC`, NTP, Avahi (`ca.local` mDNS), fleet key on `fleetadm`.
- **`security`** — UFW default-deny with a LAN allow for SSH `22` and CA `9000`
  (`security_ufw_allow_tcp_ports`); fail2ban and sshd hardening. This is the in-container LAN boundary
  — not the Proxmox host firewall, which never sees container traffic.
- **`fluentbit`** — ships the CA's journald to VictoriaLogs on `vtstack` (`192.168.2.214`), like every
  other LAN node ([ADR 36](../decisions/36-log-collector-fluentbit.md)); the store password comes from
  AKV at playbook runtime.

> **Execution record — 2026-10-11.** `ansible-playbook ansible/playbooks/playbook-ca.yml --diff` →
> `ca : ok=39 changed=25 unreachable=0 failed=0 skipped=2 rescued=0 ignored=0`, no warnings (the two
> skips are the eMMC-only Fluent Bit tmpfs tasks). Verified on the guest: hostname `ca`; `ufw status`
> **active**, default *deny incoming*, `22/tcp` + `9000/tcp` ALLOW IN `192.168.2.0/24`, `80/tcp` DENY;
> `avahi-daemon`, `fluent-bit` and `fail2ban` active; `systemctl --failed` → 0 units; `sshd -T` →
> `passwordauthentication no`, `kbdinteractiveauthentication no`. **One nuance:** `systemctl is-active
> ufw` reads `inactive` while `ufw status` reads `active` — the role enables UFW through the CLI
> rather than `systemctl start`, so the oneshot unit stays `dead` until the next boot even though the
> rules are live. **Verified by a guest reboot the same day:** after `pct reboot 215` the unit reads
> `active (exited)` with the same four rules, so the LAN boundary survives a reboot. Probed from the
> LAN: `:22` returns the OpenSSH banner (allowed), `:80` times out (DROP), and `:9000` is refused —
> allowed by UFW with nothing listening yet, which is correct before §6.

## 5. Provision the CA provisioner password

`step-ca` runs its **JWK admin provisioner** under a password — the password decrypts the provisioner
at startup and authorises admin operations. It is **not** the CA key (which lives in the TPM). The
password lives in Azure Key Vault and is fetched at deploy time:

```powershell
.\scripts\New-HomelabStepCaPassword.ps1
```

The role writes `homelab-bysxdb-kv/step-ca-provisioner-password` to a **root-only file**
(`/etc/step-ca/secrets/password`, mode `0600`) and starts `step-ca` with `--password-file …`, so the
secret never appears in the unit's environment or on a command line
([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)). **Rotation is not a password swap** —
the JWK provisioner's `encryptedKey` is encrypted with this password when `step ca init` runs, so
replacing the Key Vault secret alone would leave the new password unable to issue while the old one kept
working. The script therefore refuses to overwrite an existing secret; rotate the provisioner itself
(§8).

> **Execution record — 2026-10-11.** The secret was **absent** before this run. `./scripts/New-HomelabStepCaPassword.ps1`
> → `Secret 'step-ca-provisioner-password' provisioned in 'homelab-bysxdb-kv'`. Read back:
> `present=True enabled=True created=13:42:02Z expires=(none)`. Only `Enabled` and the timestamps were
> queried — **the value was never printed**. §6's `Assert Azure controller credentials are set` and
> Key Vault lookup (measured in the §4 run) confirm the role can read it at deploy time.

## 6. Provision the `step-ca` workload — tooling, TPM key, CSR

The workload is implemented at `ansible/workloads/step-ca/` —
[workload convention](../workloads.md), [workload README](../../ansible/workloads/step-ca/README.md).
The role does the work below; this section records what it enforces. From the repo root:

```powershell
ansible-playbook ansible/workloads/step-ca/step-ca-playbook.yml --diff
```

**`step-ca-playbook.yml`** — an entrypoint targeting host `ca` and applying the `step_ca` role.

**Role `step_ca` enforces:**

- **Packages** — install the current `step-cli`, `step-ca`, and `step-kms-plugin` releases,
  **checksum-verified** against each release's `checksums.txt` (measured #141: a truncated tarball
  segfaulted and produced a false "step-ca is broken" result). The archive + checksums are resolved
  from the GitHub **release API** at run time — the `step-kms-plugin` asset is versioned
  (`step-kms-plugin_<ver>_linux_amd64.tar.gz`), so a constructed `latest/download/<fixed-name>` URL
  404s — and the binary is located after extraction (the CLI archive nests it under `bin/`). Plus
  **`libpcsclite1`** — `step-kms-plugin` is a CGO build linked against `libpcsclite.so.1` and fails for
  TPM-only work without it; `step-ca` itself needs no PCSC (measured #141).
- **Layout** — root-owned `/etc/step-ca/{certs,config,secrets,db}` and `/var/lib/step-ca/tpm`. The
  service runs as **root**: the TPM device is owned by container root (§1), so a non-root service could
  not open it.
- **Intermediate key in the TPM** — create it with the **pinned storage directory** (measured #141):

  ```sh
  step kms create --json 'tpmkms:name=homelab-intermediate-ca;storage-directory=/var/lib/step-ca/tpm'
  ```

  The key material lands in `/var/lib/step-ca/tpm/key-homelab-intermediate-ca.tpmobj` as a JSON blob.
  **This is not a private-key file** — it is the sealed blob, useless off this TPM, and required on
  disk for the service to start.
- **CSR** — emit `intermediate_ca.csr`, signed by the TPM key, for the offline root to sign, requesting
  the service SANs (`ca.internal` and `192.168.2.215`). The signing step is what decides the finished
  certificate's shape (runbook 36 §3). **The intermediate is not what serves TLS** (measured §7):
  `step-ca` self-issues a short-lived server leaf for the `dnsNames` in `ca.json`, so the identity a
  client verifies is `ca.internal` — the SANs are kept on the request so a re-signed intermediate is
  shaped exactly like its predecessor.

  ```sh
  step certificate create --csr \
    --san ca.internal --san 192.168.2.215 \
    --kms 'tpmkms:storage-directory=/var/lib/step-ca/tpm' \
    --key 'tpmkms:name=homelab-intermediate-ca' \
    "Homelab Intermediate CA" \
    /etc/step-ca/intermediate_ca.csr
  ```

  Three things this invocation must **not** carry — each measured on the first execution, 2026-10-11:

  - **no `--profile`** — a profile describes a certificate being *issued*; with `--csr` the CLI rejects
    it outright (`flag '--profile' is incompatible with '--csr'`).
  - **no second output file** — with `--kms`/`--key` the private key already lives in the TPM, so a
    third positional is read as *“the private-key file to write”*: `step` prompts for a password
    (which hangs when there is no TTY) and, handed `--no-password`, dies with
    `cannot serialize type '*cryptoutil.kmsSigner'`. The documented KMS form takes two positionals:
    subject + CSR.
  - **no `--no-password`** — unnecessary once no key file is written.

  **This task must be re-runnable without recreating the key** — the annual re-sign
  ([runbook 36 §3](36-private-ca-init.md)) re-runs it to produce a fresh CSR from the *same* TPM key,
  so the role removes the existing CSR first when a renewal is forced (the CLI will not overwrite an
  existing output without a TTY).
- **`ca.json`** — templated with the TPM key and the **pinned** storage directory (measured #141),
  with the certificate paths the offline ceremony will fill:

  ```json
  {
    "root": "/etc/step-ca/certs/root_ca.crt",
    "crt":  "/etc/step-ca/certs/intermediate_ca.crt",
    "key":  "tpmkms:name=homelab-intermediate-ca",
    "kms":  { "type": "tpmkms", "uri": "tpmkms:storage-directory=/var/lib/step-ca/tpm" }
  }
  ```

  **`step ca init` cannot bootstrap a TPM-backed CA** (measured #141) — its `--kms` accepts only
  `azurekms`, and `--kms-intermediate 'tpmkms:…'` is silently ignored. The role runs `step ca init`
  **once into a throwaway `STEPPATH`** to mint the provisioner skeleton and password, writes the live
  `ca.json` with the TPM key above, and then deletes the throwaway directory — so no software
  intermediate key persists. It also adds the **ACME provisioner** to `ca.json`.
- **Provisioner password** — fetch the CA provisioner password from Azure Key Vault
  (`homelab-bysxdb-kv`) and write it to a **root-only** file (`/etc/step-ca/secrets/password`, mode
  `0600`); the service reads it with `--password-file`, so it never appears in the unit's
  `Environment=` or on a command line.
- **systemd** — stage `step-ca.service` (enabled, `restart=on-failure`,
  `ExecStart=/usr/local/bin/step-ca /etc/step-ca/config/ca.json --password-file /etc/step-ca/secrets/password`),
  but **do not start it yet** — there is no signed intermediate certificate until §7.
- **Root export** — `/etc/step-ca/certs/root_ca.crt` is the anchor for distribution
  ([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)); distribution itself is out of scope.
- **Re-runnable** — the TPM key is create-once (never recreated); the CSR is create-only unless
  `step_ca_csr_force=true`; the service starts only once both certificates exist. A routine run cannot
  destroy the key or clobber a CSR awaiting signing.

> **Execution record — 2026-10-11.** Took three runs. The TPM key was created on the first attempt
> (`Create the intermediate CA key in the TPM` → `changed`), then the CSR task failed twice more:
> `flag '--profile' is incompatible with '--csr'`, and then — after `--no-password --insecure` was
> tried — a **hang**: `step` blocked on a password prompt with `fd 4 -> /dev/tty`, because the third
> positional made it treat `/etc/step-ca/intermediate_ca_key.pub` as *the private key to write*. The
> root cause is that positional, not any flag; with the documented two-positional KMS form the CSR
> was produced immediately. Final state: `step` 0.31.0 / `step-ca` 0.30.2 (+`step-kms-plugin`),
> checksum-verified install; `/etc/step-ca/{certs,config,db,secrets}` + `secrets/password` 0600;
> `ca.json` pinning `tpmkms:storage-directory=/var/lib/step-ca/tpm` with the JWK admin + ACME
> provisioners; `intermediate_ca.csr` (0600, `CN=Homelab Intermediate CA`, ECDSA P-256, SANs
> `ca.internal` + `192.168.2.215`); the TPM blob; **no** `intermediate_ca_key` file anywhere; unit
> staged **disabled/inactive**. `pct reboot 215` did not recreate the key (`ok`, not `changed`).
>
> The CSR's SANs are only *requested* — the rehearsal in runbook 36 settled that the signing step must
> be given a template, since `--profile intermediate-ca` silently drops them.

## 7. Resume — install the signed intermediate and start the CA

This section runs **after** the offline ceremony ([runbook 36 §2](36-private-ca-init.md)) returns
`root_ca.crt` and `intermediate_ca.crt`. The role already put the ACME provisioner in `ca.json`.

```sh
# on the ca guest — install the two public certificates the ceremony returned
install -m 0600 root_ca.crt         /etc/step-ca/certs/root_ca.crt
install -m 0600 intermediate_ca.crt /etc/step-ca/certs/intermediate_ca.crt
```

```powershell
# from the controller — the role sees both certificates and enables + starts step-ca
ansible-playbook ansible/workloads/step-ca/step-ca-playbook.yml --diff
```

The role **restarts** `step-ca` whenever the installed intermediate certificate's checksum changed —
a renewed intermediate would otherwise stay unused until the next restart.

**Validate** (on the `ca` guest, as root — `ssh fleetadm@192.168.2.215`, then `sudo -i`: the certificates
and the provisioner-password file are `0600 root:root`, so a plain `fleetadm` shell cannot read them):

```sh
# `ca.internal` must resolve on the client — add a hosts entry until idea 10 provides the resolver. The
# CA serves a self-issued leaf for that name and no IP SAN, so the IP fails hostname verification.
CA=https://ca.internal:9000
ROOT=/etc/step-ca/certs/root_ca.crt

# health + the ACME directory the reverse proxy (#142) will point at
step ca health --ca-url "$CA" --root "$ROOT"    # → {"status":"ok"}
curl -s --cacert "$ROOT" "$CA/acme/acme/directory"

# the served TLS identity: a short-lived leaf the CA issues for itself, named from ca.json's dnsNames
echo | openssl s_client -connect 192.168.2.215:9000 2>/dev/null | openssl x509 -noout -subject -issuer -dates -ext subjectAltName

# the certificate the ceremony signed kept CA:TRUE, pathlen:0 and both SANs — the CA's declared identity
# shape, not what serves TLS (§6)
step certificate inspect /etc/step-ca/certs/intermediate_ca.crt --format json \
  | grep -E '"is_ca"|"max_path_len"|"dns_names"|"ip_addresses"'

# JWK-provisioner smoke test — issues a leaf and chain-verifies it. Naming the provisioner is required:
# without --provisioner, `step` opens an interactive menu and dies with "error allocating terminal" in a
# script, and it also asks for a private-key passphrase — hence the empty --password-file. This is NOT an
# ACME check: real ACME enrolment is exercised by the reverse proxy in #142.
step ca certificate test.internal test.crt test.key --ca-url "$CA" --root "$ROOT" \
  --provisioner admin@internal \
  --provisioner-password-file /etc/step-ca/secrets/password \
  --password-file /tmp/empty
step certificate verify test.crt --roots "$ROOT"

# plaintext is refused (ADR 34)
curl -s --connect-timeout 5 -o /dev/null -w '%{http_code}\n' http://192.168.2.215:9000/acme/acme/directory

# UFW is the LAN boundary (run inside the guest — pct exists only on the pve host)
ufw status verbose     # 22 + 9000 ALLOW IN 192.168.2.0/24
```

**Reboot survival** — `onboot 1`, the udev rule, and `restart=on-failure` together. `pct` lives on the
`pve` host, the service check on the guest:

```sh
# on the pve host (ssh fleetadm@192.168.2.201, then sudo -i)
pct reboot 215

# on the ca guest (ssh fleetadm@192.168.2.215, then sudo -i)
systemctl is-active step-ca && ls -l /dev/tpmrm0
# then re-issue a leaf — this proves the sealed blob + TPM still resolve after a reboot
```

**Idempotency** — a second `ansible-playbook ansible/workloads/step-ca/step-ca-playbook.yml --diff`
must report no changes.

> **Execution record — 2026-10-11.** Certificates installed `0600 root:root`, SHA-256 matching the files
> carried back from the ceremony (`5a19b660…` root, `ddbcb513…` intermediate). First run: `changed=4` —
> enable, start, restart on the changed intermediate checksum, and record the activated checksum
> (`22b1869a…`); second run: `changed=0`. `step-ca` is `active` + `enabled`, and the log confirms
> `X.509 Root Fingerprint: 0283b26b…` plus `The primary server URL is https://ca.internal:9000`. Health
> `{"status":"ok"}` and the ACME directory both answer over a **verifying** TLS connection; plaintext on
> `:9000` is refused (`400`, *client sent an HTTP request to an HTTPS server*). A leaf issued through
> `admin@internal` chain-verified against the root — before, and again after `pct reboot 215`, which
> proves the sealed TPM blob and the udev rule survive (new boot id, service back up, `/dev/tpmrm0`
> present, 0 failed units).
>
> **Two corrections this run forced, both folded into the blocks above.** (1) `step ca certificate` needs
> `--provisioner admin@internal` — without it, `step` opens an interactive menu and dies with *"error
> allocating terminal"* in a non-interactive session, and it prompts for a key passphrase unless an empty
> `--password-file` is given. (2) **The CA does not serve the intermediate**: it self-issues a 24 h leaf
> (`CN=Step Online CA`, issued by the intermediate) carrying `DNS:ca.internal` and **no IP SAN**, so a
> verifying client must use the name — `https://192.168.2.215:9000` fails hostname verification.

## 8. Operations

- **Leaves auto-renew** — 24 h default, 7 d maximum; the reverse proxy renews against the ACME
  directory ([#142](https://github.com/jaroslaw-bagnicki/Homelab/issues/142)). No CRL/OCSP: revocation
  is by short lifetime (ADR 38's accepted residual).
- **Annual intermediate re-sign** — [runbook 36 §3](36-private-ca-init.md): re-run §6's CSR task for a
  fresh CSR from the same TPM key, sign offline, then re-run §7. No new key, no new client trust.
- **JWK provisioner password** — the value in Key Vault is the one the `admin@internal` provisioner was
  encrypted with at init, so it cannot be rotated by writing a new secret (§5). To rotate: re-issue the
  provisioner on the guest as root — `step ca provisioner remove admin@internal` then
  `step ca provisioner add admin@internal --type JWK --create --password-file <new>` (both with
  `--ca-url https://ca.internal:9000`, `--root /etc/step-ca/certs/root_ca.crt`, and
  `--admin-provisioner admin@internal --admin-password-file /etc/step-ca/secrets/password` for the
  still-valid old password) — install the new password as `/etc/step-ca/secrets/password`, restart
  `step-ca`, and write the same value into the Key Vault secret. ACME issuance
  ([#142](https://github.com/jaroslaw-bagnicki/Homelab/issues/142)) is untouched either way.
- **PTT key-loss hazard** — a BIOS update, `Clear PTT`, or NVRAM reset destroys the sealed key. Run the
  workload with `-e step_ca_reset=true` to clear the stale blob/CSR/certificate, sign the fresh CSR
  offline ([runbook 36 §2](36-private-ca-init.md)), then re-run §7. The root is unaffected.
- **Name resolution** — nothing resolves `ca.internal` yet (resolver is
  [idea 10](../ideas/10-internal-ca-dns-stack.md)); add a hosts entry on each client until it does. The
  IP is not a substitute: the CA's server certificate carries `ca.internal` and no IP SAN, so a verifying
  client rejects `https://192.168.2.215:9000`.
- **Out of scope** — proxy wiring [#142](https://github.com/jaroslaw-bagnicki/Homelab/issues/142),
  first service [#143](https://github.com/jaroslaw-bagnicki/Homelab/issues/143), root distribution
  [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144).

---

## Verification Checklist

Executed on: **2026-10-11** — §1–§7 done. Each section carries its own **Execution record** with the
observed output.

- [x] §1 udev rule makes `/dev/tpmrm0` owned by `100000:100000`; survived a `pve` reboot
- [x] §2 LXC 215 `ca` created unprivileged + `nesting=1`, `.215`, `/dev/tpmrm0` passed through; `--failed` empty
- [x] §3 `fleetadm` key-only SSH works; `sudo -n whoami` → root
- [x] §4 `playbook-ca.yml` applied cleanly; UFW `22` + `9000`; Avahi + Fluent Bit running
- [x] §5 CA provisioner password provisioned in `homelab-bysxdb-kv`
- [x] §6 step-ca workload applied; TPM key created; CSR emitted; service **not** started
- [x] §7 signed intermediate installed; service `active` + `enabled`; ACME directory responds
- [x] §7 leaf chain-verified; plaintext refused; survives `pct reboot 215`; idempotent re-run
- [ ] §8 annual re-sign reminder set (intermediate expires 2027-10-11); PTT recovery understood

## Follow-ups

- **Offline ceremony** — [runbook 36](36-private-ca-init.md), between §6 and §7.
- **Proxy wiring** — [#142](https://github.com/jaroslaw-bagnicki/Homelab/issues/142).
- **First service** — [#143](https://github.com/jaroslaw-bagnicki/Homelab/issues/143) (`https://netdata.internal`).
- **Root distribution** — [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144).
- **Name resolution** — [idea 10](../ideas/10-internal-ca-dns-stack.md); `ca.internal` is unresolved until then.

## References

- [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — the CA hierarchy, custody, and `pve` host
- [Research 36 §5](../research/36-step-ca-machine-identity.md) — the measured LXC TPM passthrough recipe
- [Research 37 §5–§6](../research/37-tpm2-hardware-and-fleet.md) — the `pve` Intel PTT fTPM; Proxmox TPM shapes
- [Issue #141](https://github.com/jaroslaw-bagnicki/Homelab/issues/141) — the measured TPM custody gate
- [Runbook 36](36-private-ca-init.md) — the offline root/intermediate ceremony this deployment consumes
- [Runbook 33](33-deploy-victorialogs.md) (LXC/Ansible pattern) · [Runbook 28](28-pve-proxmox-node.md) (Proxmox base)
- [ADR 31](../decisions/31-static-address-scheme.md) (guest numbering) · [ADR 34](../decisions/34-lan-tls-only.md) (TLS-only) ·
  [ADR 36](../decisions/36-log-collector-fluentbit.md) (Fluent Bit) · [ADR 37](../decisions/37-lan-name-space-internal.md) (`.internal`)
