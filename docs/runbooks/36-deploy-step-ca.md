# Private CA — Deploy `step-ca` on `pve` (LXC `ca`, TPM-Bound Intermediate, ACME)

> Stand up the fleet's issuing CA: an unprivileged Debian 13 LXC (`ca`, LXC **215**, `192.168.2.215`)
> on the `pve` node with the host's **TPM 2.0** passed through, running **`step-ca` as a native
> systemd service** (no Docker), holding the intermediate from
> [runbook 35](35-private-ca-init.md) and serving an **ACME provisioner**. Decision:
> [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md); mechanics:
> [research 36 §5](../research/36-step-ca-machine-identity.md) and the measured gate in
> [#141](https://github.com/jaroslaw-bagnicki/Homelab/issues/141).
>
> ⚠ **This runbook is unexecuted.** It is written from ADR 38, research 36–37, and the
> [#141](https://github.com/jaroslaw-bagnicki/Homelab/issues/141) gate — which measured the TPM and LXC
> mechanics on `pve` — but **no step below has been run as written**. Every command is a *plan*; treat
> each as unverified until the first execution records its result. Gate-measured facts are marked
> **(measured #141)**.
>
> ⚠ **Scope / split.** This is the **one-off on-host deployment**; the offline root/intermediate
> ceremony is [runbook 35](35-private-ca-init.md). The two interleave once: **§1–§2 below run
> before [runbook 35 §3](35-private-ca-init.md)**, because the intermediate key is created in the TPM
> bound to this LXC; **§3–§6 run after [runbook 35 §5](35-private-ca-init.md)**.
> Root distribution ([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)), proxy wiring
> ([#142](https://github.com/jaroslaw-bagnicki/Homelab/issues/142)), and the first migrated service
> ([#143](https://github.com/jaroslaw-bagnicki/Homelab/issues/143)) are out of scope.
>
> ⚠ **Execution note.** Author on `docs/private-ca-runbooks`; **run only after CR**. §1–§2 are
> manual/console on the `pve` host, reached as `ssh fleetadm@192.168.2.201`; the Ansible steps (§4–§6)
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

- **LXC 215 `ca`** — unprivileged, **Debian 13**, static `192.168.2.215`, `onboot 1`, 1 vCPU /
  512 MiB / 8 GiB rootfs, with `/dev/tpm0` + `/dev/tpmrm0` passed through. Next free guest in the
  `21x` block ([ADR 31](../decisions/31-static-address-scheme.md) — VMID = last octet).
- **Reboot-durable TPM device ownership on `pve`** — a udev rule, because an unprivileged container's
  root maps to host subuid `100000` and cannot open a `root:root 0600` device (measured #141).
- **Base roles** — `common` (hostname, UTC, NTP, **Avahi**), `security` (UFW default-deny; SSH + CA
  `9000` from `192.168.2.0/24`), `fluentbit` (ships the CA's journald to VictoriaLogs on `vtstack`).
- **`ansible/workloads/step-ca/`** — a self-contained recipe installing `step-ca` + `step` CLI +
  `step-kms-plugin` (checksum-verified) and `libpcsclite1`, deploying `ca.json` with the pinned
  `tpmkms` storage directory, and running it as a native systemd unit.
- **An ACME provisioner** — so the reverse proxy ([#142](https://github.com/jaroslaw-bagnicki/Homelab/issues/142))
  and services renew short-lived leaves automatically.
- **Not backed up as a node** — the CA state is the offline root (IronKey) plus the TPM sealed key
  ([runbook 35 §7](35-private-ca-init.md)); standard node backup is out of [ADR 02](../decisions/02-backup-strategy-restic-blob.md)'s scope.

## Prerequisites

- [ ] `pve` base-provisioned — Proxmox VE + `fleetadm` ([runbook 28](28-pve-proxmox-node.md)).
- [ ] TPM available and cleared on second-hand hardware (`Clear PTT` in BIOS;
      [research 37 §5](../research/37-tpm2-hardware-and-fleet.md)).
- [ ] A Debian 13 LXC template available on the `pve` node (`pveam`).
- [ ] Runbook 35 §1–§2 done — the offline root exists on the IronKey.
- [ ] Ansible collections installed (`ansible-galaxy collection install -r ansible/requirements.yml`).
- [ ] Fleet key in `ssh-agent` (`ssh-add -l` shows `fleetadm@homelab`).
- [ ] Azure Key Vault `homelab-bysxdb-kv` reachable from the controller for the CA provisioner password
      (and the Fluent Bit store password, like every other node).

---

## 1. Reboot-durable TPM device access on `pve`

An unprivileged container's root maps to host subuid **`100000`**, so a bind-mounted `/dev/tpmrm0`
that is `root:root 0600` on the host appears inside the container as `nobody` and every open fails with
`permission denied` (measured #141). The device allow + bind mount go in the LXC config (§2); the
**ownership** fix is host-side and must survive reboots.

```sh
# on pve
ls -l /dev/tpm*        # read the majors/minors off the host — do not assume

cat >/etc/udev/rules.d/60-tpm-lxc.rules <<'EOF'
SUBSYSTEM=="tpm", KERNEL=="tpm*", RUN+="/bin/chown 100000:100000 /dev/%k"
EOF

udevadm control --reload-rules
udevadm trigger --subsystem-match=tpm
ls -l /dev/tpm0 /dev/tpmrm0        # owner must now be 100000:100000
```

- The udev rule is the **persistent** form of the one-shot `chown 100000:100000 /dev/tpmrm0` the gate
  used; without it the ownership is lost on reboot.
- The gate read `/dev/tpm0` as `10:224` and `/dev/tpmrm0` as `252:65536`; always `ls -l` on the host
  (the `252` major is dynamic). Those numbers are used in the LXC config (§2).
- A **privileged** container avoids the ownership change, at the cost of the isolation the unprivileged
  shape exists for — not used here.

> **Acceptance.** `ls -l /dev/tpm0 /dev/tpmrm0` shows `100000:100000`; after `reboot` they still do.

> **Backout.** `rm /etc/udev/rules.d/60-tpm-lxc.rules`, reload rules, `chown root:root /dev/tpm*`.

## 2. Create LXC 215 `ca`

On the `pve` host (`ssh fleetadm@192.168.2.201`, then `sudo -i`):

```sh
pveam update
pveam available --section system | grep debian-13
pveam download local <debian-13-template-from-the-line-above>
pveam list local

pct create 215 local:vztmpl/<template> \
  --hostname ca --unprivileged 1 \
  --cores 1 --memory 512 --swap 512 \
  --rootfs local-lvm:8 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.2.215/24,gw=192.168.2.1 \
  --onboot 1
```

- **No `nesting`/`fuse`** — `step-ca` is native, not Docker.
- **`--onboot 1`** — the CA must return on its own after a host reboot.
- `--rootfs local-lvm:8` is a starting estimate; `step-ca` and its state are small, re-check after
  deployment.
- DNS is deliberately **not** pinned — the guest inherits the host resolvers.

Append the TPM passthrough to `/etc/pve/lxc/215.conf`:

```ini
lxc.cgroup2.devices.allow: c 10:224 rwm       # /dev/tpm0
lxc.cgroup2.devices.allow: c 252:65536 rwm    # /dev/tpmrm0
lxc.mount.entry: /dev/tpm0   dev/tpm0   none bind,optional,create=file
lxc.mount.entry: /dev/tpmrm0 dev/tpmrm0 none bind,optional,create=file
```

```sh
pct start 215
pct exec 215 -- ls -l /dev/tpmrm0     # present and owned by container root
```

- The device numbers must match §1's host reading; update the config if the host differs.
- Keep the Proxmox network **Firewall** flag at `0` — the boundary is the in-container UFW (§4).

> **Acceptance.** `pct status 215` → `running`; `/dev/tpmrm0` visible inside; `systemctl --failed`
> inside is empty.

> **Backout.** `pct stop 215 && pct destroy 215`; remove the udev rule (§1 backout).

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

> **Acceptance.** `ssh fleetadm@192.168.2.215 'sudo -n whoami'` → `root`, key-only.

> **Backout.** `pct destroy 215` (§2) removes the account with the container.

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

> **Acceptance.** Clean `PLAY RECAP`; UFW active with `22` + `9000` allowed from `192.168.2.0/24`;
> `avahi-daemon` and `fluent-bit` running; `systemctl --failed` empty.

> **Backout.** Re-run with the previous inventory/host_vars.

## 5. Provision the `step-ca` workload

The workload is `ansible/workloads/step-ca/` ([workload convention](../workloads.md)). **Writing the
role is out of scope here** — this section specifies what it must contain. From the repo root:

```powershell
ansible-playbook ansible/workloads/step-ca/step-ca-playbook.yml --diff
```

**`step-ca-playbook.yml`** — an entrypoint targeting host `ca` and applying the role below.

**Role `step_ca` must contain:**

- **Packages** — install the current `step-cli`, `step-ca`, and `step-kms-plugin` releases,
  **checksum-verified** against `checksums.txt` (measured #141: a truncated tarball segfaulted and
  produced a false "step-ca is broken" result), plus **`libpcsclite1`** — `step-kms-plugin` is a CGO
  build linked against `libpcsclite.so.1` and fails for TPM-only work without it; `step-ca` itself
  needs no PCSC (measured #141).
- **Layout** — a `step` service user; `/etc/step-ca/{certs,config,secrets}` and
  `/var/lib/step-ca/tpm`.
- **Certificates** — deploy `root_ca.crt` and `intermediate_ca.crt` from
  [runbook 35 §4–§5](35-private-ca-init.md); the intermediate's private key is **never** a file (it is
  the TPM sealed blob at `/var/lib/step-ca/tpm/key-homelab-intermediate-ca.tpmobj`).
- **`ca.json`** — templated with the TPM key and the **pinned** storage directory (measured #141):

  ```json
  {
    "root": "/etc/step-ca/certs/root_ca.crt",
    "crt":  "/etc/step-ca/certs/intermediate_ca.crt",
    "key":  "tpmkms:name=homelab-intermediate-ca",
    "kms":  { "type": "tpmkms", "uri": "tpmkms:storage-directory=/var/lib/step-ca/tpm" }
  }
  ```

- **Provisioner password** — fetch the CA provisioner password from Azure Key Vault
  (`homelab-bysxdb-kv`) and write it to a **root-only** file (`/etc/step-ca/secrets/password`, mode
  `0600`); the service reads it with `--password-file`, so it never appears in the unit's
  `Environment=` or on a command line.
- **systemd** — `step-ca.service`, enabled and `restart=on-failure`, with
  `ExecStart=/usr/bin/step-ca /etc/step-ca/config/ca.json --password-file /etc/step-ca/secrets/password`;
  a handler restarts the service on config change.
- **ACME provisioner** — `step ca provisioner add acme --type ACME` against the local CA, idempotent.
- **Root export** — make `root_ca.crt` available for distribution
  ([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)); distribution itself is out of scope.
- **Ansible-side README** describing the role, its variables, and the AKV secret.

> **Acceptance.** `systemctl is-active step-ca` → `active`; `systemctl is-enabled step-ca` → `enabled`;
> `ca.json` carries the `kms` block; no `intermediate_ca_key` file exists anywhere.

> **Backout.** `systemctl disable --now step-ca`; restore the previous `ca.json`/`certs/`.

## 6. Validate

```sh
CA=https://192.168.2.215:9000
ROOT=/etc/step-ca/certs/root_ca.crt

# health + the ACME directory the reverse proxy (#142) will point at
step ca health --ca-url "$CA" --root "$ROOT"
curl -sk "$CA/acme/acme/directory"

# issue a leaf over ACME and chain-verify it (use the IP — nothing resolves ca.internal yet)
step ca certificate test.internal test.crt test.key --ca-url "$CA" --root "$ROOT"
step certificate verify test.crt --roots "$ROOT"

# plaintext is refused (ADR 34)
curl -s --connect-timeout 5 -o /dev/null -w '%{http_code}\n' http://192.168.2.215:9000/acme/acme/directory

# UFW is the LAN boundary
pct exec 215 -- ufw status verbose     # 22 + 9000 ALLOW IN 192.168.2.0/24

# installed versions / no pin — record what shipped
pct exec 215 -- step-ca version
```

**Reboot survival** — `onboot 1`, the udev rule, and `restart=on-failure` together:

```sh
pct reboot 215
ssh fleetadm@192.168.2.215 'systemctl is-active step-ca && ls -l /dev/tpmrm0'
# then re-issue a leaf — this proves the sealed blob + TPM still resolve after a reboot
```

**Idempotency** — a second `ansible-playbook ansible/workloads/step-ca/step-ca-playbook.yml --diff`
must report no changes.

> **Acceptance.**

> | Check | Result |
> |---|---|
> | `step ca health` | `{"status":"ok"}` |
> | ACME directory | JSON with `newNonce`/`newAccount`/… |
> | Leaf issued + verified | chain `leaf ← Homelab Intermediate CA ← Homelab Internal CA` |
> | Plaintext request | refused (no cleartext service) |
> | In-LXC UFW | `22` + `9000` ALLOW IN `192.168.2.0/24` |
> | Reboot | service active, `/dev/tpmrm0` owned by container root, leaf re-issues |
> | Idempotency | re-run reports no changes |

> **Backout.** `systemctl disable --now step-ca`; the offline root and client trust are untouched.

## 7. Operations

- **Leaves auto-renew** — 24 h default, 7 d maximum; the reverse proxy renews against the ACME
  directory ([#142](https://github.com/jaroslaw-bagnicki/Homelab/issues/142)). No CRL/OCSP: revocation
  is by short lifetime (ADR 38's accepted residual).
- **Annual intermediate re-sign** — [runbook 35 §8](35-private-ca-init.md); set a reminder.
- **PTT key-loss hazard** — a BIOS update, `Clear PTT`, or NVRAM reset destroys the sealed key;
  recover with [runbook 35 §9](35-private-ca-init.md). The root is unaffected.
- **Name resolution** — nothing resolves `ca.internal` yet (resolver is
  [idea 10](../ideas/10-internal-ca-dns-stack.md)); until then use the IP or a hosts entry.
- **Out of scope** — proxy wiring [#142](https://github.com/jaroslaw-bagnicki/Homelab/issues/142),
  first service [#143](https://github.com/jaroslaw-bagnicki/Homelab/issues/143), root distribution
  [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144).

---

## Verification Checklist

Executed on: **never** — this runbook is unexecuted. Record the date, the `ansible-playbook --diff`
summary, and each result when it is first run.

- [ ] §1 udev rule makes `/dev/tpm*` owned by `100000:100000`; survives reboot
- [ ] §2 LXC 215 `ca` created unprivileged, `.215`, TPM passed through
- [ ] §3 `fleetadm` key-only SSH works; `sudo -n whoami` → root
- [ ] §4 `playbook-ca.yml` applied cleanly; UFW `22` + `9000`; Avahi + Fluent Bit running
- [ ] §5 step-ca workload applied; service `active` + `enabled`; `ca.json` has the `kms` block
- [ ] §6 `step ca health` ok; ACME directory responds; leaf chain-verified; plaintext refused
- [ ] §6 survives `pct reboot 215`; leaf re-issues; idempotent re-run reports no changes
- [ ] §7 annual re-sign reminder set; PTT recovery understood

## Follow-ups

- **Workload role** — `ansible/workloads/step-ca/` is specified in §5 but not written here (non-goal).
- **Proxy wiring** — [#142](https://github.com/jaroslaw-bagnicki/Homelab/issues/142).
- **First service** — [#143](https://github.com/jaroslaw-bagnicki/Homelab/issues/143) (`https://netdata.internal`).
- **Root distribution** — [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144).
- **Name resolution** — [idea 10](../ideas/10-internal-ca-dns-stack.md); `ca.internal` is unresolved until then.

## References

- [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — the CA hierarchy, custody, and `pve` host
- [Research 36 §5](../research/36-step-ca-machine-identity.md) — the measured LXC TPM passthrough recipe
- [Research 37 §5–§6](../research/37-tpm2-hardware-and-fleet.md) — the `pve` Intel PTT fTPM; Proxmox TPM shapes
- [Issue #141](https://github.com/jaroslaw-bagnicki/Homelab/issues/141) — the measured TPM custody gate
- [Runbook 35](35-private-ca-init.md) — the offline root/intermediate ceremony this deployment consumes
- [Runbook 33](33-deploy-victorialogs.md) (LXC/Ansible pattern) · [Runbook 28](28-pve-proxmox-node.md) (Proxmox base)
- [ADR 31](../decisions/31-static-address-scheme.md) (guest numbering) · [ADR 34](../decisions/34-lan-tls-only.md) (TLS-only) ·
  [ADR 36](../decisions/36-log-collector-fluentbit.md) (Fluent Bit) · [ADR 37](../decisions/37-lan-name-space-internal.md) (`.internal`)
