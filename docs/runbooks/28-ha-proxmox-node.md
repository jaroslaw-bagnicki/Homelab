# Home Assistant Node — Proxmox VE Install

> Install **Proxmox VE** on the Dell Wyse 5070 Home Assistant node (`ha`, `192.168.2.201`)
> — the dedicated smart-home hypervisor ([ADR 25](../decisions/25-home-assistant-thin-client.md)).
> Tracked in [issue #103](https://github.com/jaroslaw-bagnicki/Homelab/issues/103) (child of
> [#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68)). The hardware diagnostic is
> already done ([research 29](../research/29-wyse5070-hardware-diagnostic.md), issue #82).
>
> ⚠ **Netdata is out of scope here.** The Netdata **Parent** (which will also run on this host) is
> tracked under [#104](https://github.com/jaroslaw-bagnicki/Homelab/issues/104).

## Why

ADR 25 needs Home Assistant on a **dedicated thin-client node** (good Zigbee mesh location, and
MQTT/Zigbee2MQTT as LXCs so HA restarts don't drop the mesh). Proxmox VE is that hypervisor. It is
also the future home of the **Netdata Parent** (ADR 27 / #104) — a central Tier B monitoring plane
independent of the M910q.

## What changes

- **Proxmox VE** installed on the Wyse 5070; static IP **`192.168.2.201`** — the `20x` **server**
  block of [research 24](../research/24-network-topology-design.md) (this is a compute/virtualisation
  host, not an edge/ingress device).
- **`ha`** added to the Ansible inventory; base provisioned via `ansible/playbooks/playbook-ha.yml`
  (`common` → `security`).
- **Agent account — `fleetadm`** — key-only SSH (ADR 28), installed at bootstrap (full pattern in the
  [ansible README](../../ansible/README.md)).
- **Breaking-glass account — `root`** — the Proxmox admin (web UI `:8006` + console), password stored
  in **Keeper**; SSH password login allowed from the LAN (§3).
- **Firewall** — the fleet `security` role (**UFW**), default-deny with LAN allow: SSH `22` + Proxmox
  web UI `8006`. UFW is host-management-plane only; bridged VM traffic is unaffected (LAN-trusted).

> **Execution note.** Run this runbook **interactively from the repo's dev container** (any
> interactive session — e.g. VSCode with the GitHub Copilot extension), like runbooks 24/25. This is a
> **physical/console install** — it cannot be delegated to a headless agent. The `ha` node is LAN-only;
> run its playbook from a machine on `192.168.2.0/24` per the `fleet-connect` skill.

## Prerequisites

- Wyse 5070 (Celeron J4105, 8 GB, M.2 SATA 128 GB — **no NVMe**, research 26/29) · monitor + keyboard · power
- **Proxmox VE ISO** on a bootable USB (F12 one-time boot)
- Console or SSH reachability during setup
- Refs: [research 29](../research/29-wyse5070-hardware-diagnostic.md) (diagnostic) · [research 26](../research/26-home-assistant-thin-client.md) · [ADR 25](../decisions/25-home-assistant-thin-client.md) · [ADR 28](../decisions/28-fleet-admin-account-and-key.md) · [research 24](../research/24-network-topology-design.md) (IP scheme)

---

## 0. Hardware — Diagnostic (already done)

The Phase 0 pre-boot audit is **complete** — see research 29 / issue #82: Celeron J4105, **2× 4 GB** Micron
DDR4 (both slots full — 16 GB means replacing both), M.2 **SATA** 128 GB (SK hynix SC311, used/SMART-verified
— **B+M key only, no NVMe**), eMMC 14.7 GiB present/unused, Realtek GbE + Intel WiFi + Sonoff ZBDongle-P
(Zigbee coordinator).

## 1. Install Proxmox VE

1. Boot the Wyse 5070 from the **Proxmox VE ISO** USB (F12 → USB).
2. Select **Install Proxmox VE**; accept defaults, **manual partitioning** to the M.2 SATA SSD (the
   128 GB SK hynix) — single ext4 root; Proxmox defaults are fine here.
3. **Network config:**

   | Field | Value |
   |---|---|
   | Management interface | `enp1s0` (Realtek GbE) |
   | IP | `192.168.2.201/24` |
   | Gateway | `192.168.2.1` |
   | DNS | `1.1.1.1, 8.8.8.8` |
   | Hostname | `ha` (the `common` role sets it) |
   | Timezone | `Etc/UTC` (the `common` role enforces it) |
4. Set a **strong root password** → **Keeper**. This is the breaking-glass account (Proxmox web UI
   admin + console).
5. Finish the install, reboot (remove the USB).
6. **Verify:**
   ```sh
   ip addr show enp1s0 | grep 'inet '
   # Expected: 192.168.2.201/24
   ping -c1 192.168.2.1
   ```
7. Proxmox web UI: **https://192.168.2.201:8006** → log in as `root` (Keeper).

> **Proxmox reality vs runbook 25:** Proxmox VE has **no "create user" step** — `root` is the only
> built-in admin (console + web UI). There is no separate personal account like the Ubuntu installer's.
> `root` is the breaking-glass identity; `fleetadm` is created in §2 for Ansible.

## 2. `fleetadm` Bootstrap (ADR 28) — unblock Ansible

Mirrors [runbook 25 §2](25-m910q-os-refresh.md) / ADR 28. On the box (console or SSH as `root`):

1. Create the agent account + NOPASSWD sudo + install the fleet key — copy the exact snippet
   (`useradd`/`usermod`/`chmod 440` `sudoers.d`, `.ssh` perms, `authorized_keys` with the fleet key
   + restrictive `key_options`, `passwd -l fleetadm`) from [runbook 25 §2](25-m910q-os-refresh.md),
   using the public key at `ansible/roles/common/files/ssh/fleetadm.pub`.
2. **Verify from the control node** (LAN workstation with the fleet key in the agent):
   ```sh
   ssh fleetadm@192.168.2.201
   sudo -n whoami      # → root
   ```

## 3. Ansible Base Provision

From the **LAN workstation** (per `fleet-connect`), with the fleet key loaded:

```powershell
chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible   # world-writable fix
ansible-playbook ansible/playbooks/playbook-ha.yml --diff
```

`playbook-ha.yml` runs `common → security`:
- **`common`** — hostname `ha`, `Etc/UTC`, systemd-timesyncd, Avahi (`ha.local`, `common_enable_avahi: true`),
  and re-arms the fleet key on `fleetadm` (ADR 28).
- **`security`** — UFW default-deny + allow from `192.168.2.0/24`: SSH `22` and Proxmox UI **`8006`**
  (`security_ufw_allow_tcp_ports`), fail2ban, sshd key-only hardening with LAN password auth for the
  breakglass `root`.

> **Netdata** is not part of this runbook/playbook — it is **#104**.

## Verification Checklist

- [ ] §1 Proxmox VE installed; static IP `192.168.2.201`; web UI reachable at `:8006`
- [ ] §2 `fleetadm` key-only SSH works; `sudo -n whoami` → root
- [ ] §3 `common` + `security` applied cleanly (idempotent — second run = 0 changed)
- [ ] UFW active; SSH + 8006 allowed from LAN; `ha.local` resolves

## References

- [ADR 25](../decisions/25-home-assistant-thin-client.md) · [research 26](../research/26-home-assistant-thin-client.md) · [idea 05](../ideas/05-home-assistant-thin-client.md)
- [research 29](../research/29-wyse5070-hardware-diagnostic.md) (diagnostic) · issue #82 (diagnostic, closed)
- [ADR 28](../decisions/28-fleet-admin-account-and-key.md) (fleetadm) · [research 24 §Option A](../research/24-network-topology-design.md) (IP scheme)
- [Runbook 25 §2](25-m910q-os-refresh.md) (fleetadm bootstrap pattern)
- [Issue #103](https://github.com/jaroslaw-bagnicki/Homelab/issues/103) · parent [#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68) · Netdata [#104](https://github.com/jaroslaw-bagnicki/Homelab/issues/104)
