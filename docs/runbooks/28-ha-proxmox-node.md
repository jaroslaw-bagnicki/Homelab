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
  in **Keeper**; it is reached via the **console / Proxmox web UI** (SSH for `root` is key-only — the
  shared sshd uses `PermitRootLogin prohibit-password`).
- **Firewall** — the fleet `security` role (**UFW**), default-deny with LAN allow: SSH `22` + Proxmox
  web UI `8006`. UFW is host-management-plane only; bridged VM traffic is unaffected (LAN-trusted).

> **Execution note.** Run this runbook **interactively from the repo's dev container** (any
> interactive session — e.g. VSCode with the GitHub Copilot extension), like runbooks 24/25. This is a
> **physical/console install** — it cannot be delegated to a headless agent. The `ha` node is LAN-only;
> run its playbook from a machine on `192.168.2.0/24` per the `fleet-connect` skill.

## Prerequisites

- Wyse 5070 (Celeron J4105, 8 GB, M.2 SATA 128 GB — **no NVMe**, research 26/29) · monitor + keyboard · power
- **Proxmox VE ISO (x86_64/amd64)** added to the YUMI multiboot USB stick (runbook 01 §0 / research 12) — F12 one-time boot · ⚠ do **not** add the **ARM64** (`*-arm64`) build — the Wyse 5070 is an Intel J4105 (x86_64)
- Console or SSH reachability during setup
- Refs: [research 29](../research/29-wyse5070-hardware-diagnostic.md) (diagnostic) · [research 26](../research/26-home-assistant-thin-client.md) · [ADR 25](../decisions/25-home-assistant-thin-client.md) · [ADR 28](../decisions/28-fleet-admin-account-and-key.md) · [research 24](../research/24-network-topology-design.md) (IP scheme)

---

## 0. Hardware — Diagnostic (already done)

The Phase 0 pre-boot audit is **complete** — see research 29 / issue #82: Celeron J4105, **2× 4 GB** Micron
DDR4 (both slots full — 16 GB means replacing both), M.2 **SATA** 128 GB (SK hynix SC311, used/SMART-verified
— **B+M key only, no NVMe**), eMMC 14.7 GiB present/unused, Realtek GbE + Intel WiFi + Sonoff ZBDongle-P
(Zigbee coordinator).

## 1. Install Proxmox VE

1. Boot the Wyse 5070 from the **YUMI** USB stick → select the **Proxmox VE** entry (F12 → USB).
2. Select **Install Proxmox VE**; accept defaults, **manual partitioning** to the M.2 SATA SSD (the
   128 GB SK hynix) — single ext4 root; Proxmox defaults are fine here.
3. **Network config:**

   | Field | Value |
   |---|---|
   | Management interface | `enp1s0` (Realtek GbE) |
   | IP | `192.168.2.201/24` |
   | Gateway | `192.168.2.1` |
   | DNS | `1.1.1.1` — the Proxmox installer exposes a **single** DNS Server field (not two); the secondary `8.8.8.8` is added later via the node's **System → DNS** (or by the `common` role) |
   | Hostname (FQDN) | `ha.local` — Proxmox sets OS `hostname` to `ha` (FQDN recorded in `/etc/hosts`); the `common` role keeps `ha` |
   | Timezone | `Etc/UTC` (the `common` role enforces it) |

   > **Single DNS field.** The installer's network screen accepts **one** DNS server only — don't try to enter `1.1.1.1, 8.8.8.8` (it will reject the value as invalid). Enter just `1.1.1.1`; add `8.8.8.8` as a secondary via **Node `ha` → System → DNS**. A single resolver is fine for this host.

   > `ha.local` resolves via Avahi mDNS; `ha.home` is the planned OPNsense domain (ADR 24) — revisit when OPNsense lands.

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

> **Future (optional):** once OPNsense `.home` DNS lands (#65/#81 · #96), the Edge Caddy can alias
> `http://ha.home` → `https://ha:8006` for a portless URL. Not needed here — direct `:8006` access is used.

> **Proxmox reality vs runbook 25:** Proxmox VE has **no "create user" step** — `root` is the only
> built-in admin (console + web UI). There is no separate personal account like the Ubuntu installer's.
> `root` is the breaking-glass identity, reached via the **console / Proxmox web UI**; `fleetadm` is
> created in §3 for Ansible.

## 2. Repositories & OS updates (no subscription)

Proxmox VE is free and fully functional **without a licence** — a subscription only unlocks the
`pve-enterprise` APT repo and commercial support. A fresh install enables the **enterprise** repos by
default, which error on `apt update` without a key, so switch to the free **no-subscription** repo:

1. Node `ha` → **Updates → Repositories**.
2. **Disable** `pve-enterprise` — and `ceph-squid` too (the enterprise Ceph repo; unused on this
   single-node host, and it will otherwise throw the same subscription error on `apt update`).
3. **Add → No-Subscription** — it auto-selects the correct Debian codename (Proxmox VE 9 = Debian 13 *trixie*).
4. **Refresh** the package lists.

Then bring the OS + Proxmox packages up to date — either from the web UI (**Updates → Refresh**, then
**Upgrade**) or at the console (a reboot may be needed if a kernel updates):

```sh
apt update && apt dist-upgrade
```

> The **"No valid subscription"** popup is **cosmetic** — you can dismiss it; it has no effect on
> functionality. You do **not** need a licence for a homelab.

## 3. `fleetadm` Bootstrap (ADR 28) — unblock Ansible

Mirrors [runbook 25 §2](25-m910q-os-refresh.md) / ADR 28. On the box (console or SSH as `root`), create
the key-only `fleetadm` agent account + NOPASSWD sudo + install the fleet key. **Proxmox VE does not
ship `sudo` by default** — install it first, otherwise Ansible's `become` (which uses `sudo`) will
fail. Paste the following at the **root console / Proxmox Shell** (the fleet key is inlined; it lives
at `ansible/roles/common/files/ssh/fleetadm.pub`, ADR 28):

```bash
# Proxmox VE does not ship sudo by default — install it first (Ansible become needs it)
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

> `sudo` is a no-op if you're already `root` (console/Shell). The `common` role re-arms the same
> `key_options` line on every run, so bootstrap and rotation stay on one identical line.

**Verify from the control node** (LAN workstation with the fleet key in the agent):

```sh
ssh fleetadm@192.168.2.201
sudo -n whoami      # → root
```

## 4. Ansible Base Provision

From the **LAN workstation** (per `fleet-connect`), with the fleet key loaded:

```powershell
chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible   # world-writable fix
ansible-playbook ansible/playbooks/playbook-ha.yml --diff
```

`playbook-ha.yml` runs `common → security`:
- **`common`** — hostname `ha`, `Etc/UTC`, Avahi (`ha.local`, `common_enable_avahi: true`), and re-arms
  the fleet key on `fleetadm` (ADR 28). Time sync is left to Proxmox's **`chrony`**.
- **`security`** — UFW default-deny + allow from `192.168.2.0/24`: SSH `22` and Proxmox UI **`8006`**
  (`security_ufw_allow_tcp_ports`), fail2ban, sshd key-only hardening (LAN password auth applies to
  **non-root** accounts only — `root` SSH stays key-only via `PermitRootLogin prohibit-password`).

> **Time sync.** The `common` role asks `systemctl is-active chrony`; if `chrony` is the running NTP
> daemon it manages `chrony`, otherwise it manages the standard `systemd-timesyncd`. This reads the
> **actual runtime state**, not what's installed — so a host running `chrony` (e.g. Proxmox VE) is handled
> correctly, while Debian/Ubuntu hosts stay on `systemd-timesyncd`.

> **Netdata** is not part of this runbook/playbook — it is **#104**.

## Verification Checklist

- [ ] §1 Proxmox VE installed; static IP `192.168.2.201`; web UI reachable at `:8006`
- [ ] §2 `no-subscription` repo enabled; `apt update && apt dist-upgrade` succeeds
- [ ] §3 `fleetadm` key-only SSH works; `sudo -n whoami` → root
- [ ] §4 `common` + `security` applied cleanly (idempotent — second run = 0 changed)
- [ ] UFW active; SSH + 8006 allowed from LAN; `ha.local` resolves

## References

- [ADR 25](../decisions/25-home-assistant-thin-client.md) · [research 26](../research/26-home-assistant-thin-client.md) · [idea 05](../ideas/05-home-assistant-thin-client.md)
- [research 29](../research/29-wyse5070-hardware-diagnostic.md) (diagnostic) · issue #82 (diagnostic, closed)
- [ADR 28](../decisions/28-fleet-admin-account-and-key.md) (fleetadm) · [research 24 §Option A](../research/24-network-topology-design.md) (IP scheme)
- [Runbook 25 §2](25-m910q-os-refresh.md) (fleetadm bootstrap pattern)
- [runbook 01 §0](01-init.md) / [research 12](../research/12-first-boot-setup.md) (YUMI multiboot stick)
- [Issue #103](https://github.com/jaroslaw-bagnicki/Homelab/issues/103) · parent [#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68) · Netdata [#104](https://github.com/jaroslaw-bagnicki/Homelab/issues/104)
