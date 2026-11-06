# pve2 Node — Proxmox VE Install (OptiPlex 7050)

> Stand up the Dell OptiPlex 7050 MFF as **`pve2`** — the fleet's second virtualisation host at
> **`192.168.2.202`**, ready to join the two-node cluster in [runbook 43](43-proxmox-cluster-qdevice.md).
> Tracked in [issue #177](https://github.com/jaroslaw-bagnicki/Homelab/issues/177); hardware audit in
> [research 52](../research/52-optiplex7050-hardware-diagnostic.md); decision in
> [ADR 47](../decisions/47-second-proxmox-node-cluster-qdevice.md).
>
> ⚠ **Do not join the cluster until the smoke-test guest is deleted.** A joining node cannot hold
> guests and `/etc/pve` is overwritten on join.

## Why

`pve1` is the only hypervisor. `pve2` adds capacity now and makes the two-node cluster/QDevice design
possible ([ADR 47](../decisions/47-second-proxmox-node-cluster-qdevice.md)). HA rules and ZFS
replication stay out of scope.

## What changes

- Proxmox VE **9.x, the same point release as `pve1`** (currently 9.2.2).
- Hostname `pve2`, static `192.168.2.202/24`, gateway `192.168.2.1`, DNS `1.1.1.1`, timezone `Etc/UTC`.
- `ext4` + LVM-thin on the 128 GB M.2 SATA module; no ZFS. The 2.5″ bay stays free for a later pool.
- Fleet enrollment via `ansible/playbooks/playbook-pve2.yml`:
  `common → ca_trust → security → proxmox_cluster → nut_client → netdata → fluentbit`.
- Netdata **child** streams to `pve1:19996` (TLS); Fluent Bit ships to VictoriaLogs `.214`; NUT is a
  **secondary** of the server on `pve1`. The NUT server is **not** installed here.

## Prerequisites

- OptiPlex 7050 (i5-7500, 8 GB, 128 GB M.2 SATA) · monitor + keyboard · 130 W adapter · power
- Proxmox VE 9.x ISO on the YUMI/Ventoy stick (x86_64)
- LAN workstation with the `automation` certificate or the break-glass fleet key
- `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` / `AZURE_TENANT_ID` on the controller, `step` CLI, and
  `ca.internal` resolution

---

## 0. Pre-boot checks

1. **BIOS (F2), final settings** — AHCI; UEFI with Secure Boot **off**; VT-x + VT-d on; TPM 2.0 on;
   wireless disabled; TurboBoost **off**; **AC Recovery `Power On`**; **Wake on LAN `LAN Only`**;
   **Deep Sleep `Disabled`**; Fastboot `Thorough` with a non-zero POST delay.
2. **Record the NIC MAC** — `enp0s31f6` on the Intel I219-LM; it is needed for WoL and the DHCP
   reservation. Run `mei-amt-version` and the TPM vendor check from a live session; if AMT is absent,
   remote power is AC Recovery + WoL only.
3. **Confirm the disk is the 128 GB SK hynix SC311** and that the 2.5″ bay is empty. No disk
   replacement is required (research 52).

## 1. Install Proxmox VE

1. Boot the USB → **Install Proxmox VE**.
2. **Filesystem:** `ext4` (the installer's default — do **not** select ZFS). Target the internal
   128 GB module; use the whole disk.
3. **Network:**

   | Field | Value |
   |---|---|
   | Management interface | `enp0s31f6` |
   | IP | `192.168.2.202/24` |
   | Gateway | `192.168.2.1` |
   | DNS | `1.1.1.1` |
   | Hostname (FQDN) | `pve2.local` (OS hostname `pve2`) |
   | Timezone | `Etc/UTC` |

4. Set a strong `root` password → **Keeper**. Reboot, remove the USB.
5. Verify:

   ```sh
   ip addr show enp0s31f6 | grep 'inet '
   ping -c1 192.168.2.1
   ```

   Web UI: **https://192.168.2.202:8006** → `root`.

## 2. Repositories and OS updates

1. Node `pve2` → **Updates → Repositories**: disable `pve-enterprise` and `ceph-squid`; add the
   **No-Subscription** repo; refresh.
2. Bring the node to the same point release as `pve1`:

   ```sh
   apt update && apt dist-upgrade
   pveversion -v        # must match pve1
   ```

## 3. `fleetadm` bootstrap

Proxmox does not ship `sudo`. At the root console / Proxmox Shell, mirror
[runbook 28 §3](28-pve1-proxmox-node.md):

```bash
apt update && apt install -y sudo
id -u fleetadm >/dev/null 2>&1 || useradd -m -s /bin/bash fleetadm
usermod -aG sudo fleetadm
echo 'fleetadm ALL=(ALL) NOPASSWD: ALL' | tee /etc/sudoers.d/fleetadm
chmod 440 /etc/sudoers.d/fleetadm
mkdir -p /home/fleetadm/.ssh && chmod 700 /home/fleetadm/.ssh
printf 'no-port-forwarding,no-agent-forwarding,no-X11-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKAucOXvwvHvSn11uzG49QFvJPxodbOjPEWkvdS9vCVG fleetadm@homelab\n' | tee /home/fleetadm/.ssh/authorized_keys
chmod 600 /home/fleetadm/.ssh/authorized_keys
chown -R fleetadm:fleetadm /home/fleetadm/.ssh
passwd -l fleetadm
```

Verify from the LAN workstation: `ssh fleetadm@192.168.2.202` → `sudo -n whoami` → `root`.

## 4. Ansible base provision

From the LAN workstation (repo root, automation certificate loaded):

```powershell
chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible   # dev container only
ansible-playbook ansible/playbooks/playbook-pve2.yml --check
ansible-playbook ansible/playbooks/playbook-pve2.yml --diff
ansible-playbook ansible/playbooks/playbook-pve2.yml --diff   # idempotence: changed=0
```

The controller needs the Azure Key Vault credentials for `nut_client`, `netdata` and `fluentbit`, and
the `step` CLI for the SSH host certificate. The `security` role issues a certificate with principals
`pve2`, `pve2.internal` and `192.168.2.202`.

## 5. Smoke test (standalone, before the cluster)

Create a throwaway LXC with an ID from the `25x` guest block, start it, check storage and network, then
destroy it:

```sh
pct create 250 local:vztmpl/debian-13-standard_*.tar.zst \
  --hostname smoke --rootfs local-lvm:1 --net0 name=eth0,bridge=vmbr0,ip=dhcp
pct start 250
pct exec 250 -- ip -4 addr show eth0
pct exec 250 -- ping -c1 192.168.2.1
pct stop 250 && pct destroy 250
pct list        # empty
```

The node is now ready to join the cluster. Do not create guests before the join.

## 6. State docs

Update `docs/overview.md` (node row + topology), `docs/hardware.md` (per-node specs) and the Technitium
`pve2.internal` record in the same change.

## Verification Checklist

- [ ] Proxmox VE 9.x installed; `pve2` at `192.168.2.202`; UI `:8006` returns `200`
- [ ] `pveversion -v` matches `pve1`
- [ ] `fleetadm` key-only SSH works; `sudo -n whoami` → root
- [ ] `playbook-pve2.yml` applies cleanly; second run `changed=0`
- [ ] UFW active; SSH + `8006` allowed from LAN; `pve2.local` / `pve2.internal` resolve
- [ ] Netdata child visible on the `pve1` Parent; Fluent Bit logs in VictoriaLogs
- [ ] `upsc ups@192.168.2.201` works; `nut-monitor` active
- [ ] Smoke-test LXC 250 created, verified and destroyed
- [ ] `docs/overview.md` and `docs/hardware.md` updated

## References

- [ADR 47](../decisions/47-second-proxmox-node-cluster-qdevice.md) · [idea 15](../ideas/15-second-proxmox-node.md) · [research 47](../research/47-second-proxmox-node.md) · [research 52](../research/52-optiplex7050-hardware-diagnostic.md)
- [Runbook 28](28-pve1-proxmox-node.md) — the incumbent node's install and `fleetadm` pattern
- [Runbook 43](43-proxmox-cluster-qdevice.md) — the cluster and QDevice step
- [Runbook 31](31-deploy-netdata.md) · [runbook 34](34-deploy-fluentbit.md) · [runbook 30](30-deploy-nut-clients.md)
