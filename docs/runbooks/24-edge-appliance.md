# Edge Appliance (Wyse 3040) — Runbook

> Deploy the homelab's **dedicated edge appliance** — bare-metal `cloudflared` + Caddy +
> Netdata on a Dell Wyse 3040 thin client — as the single public ingress for the LAN.
> Device acquired **2026-08-13**; hardware audit complete **2026-08-17**; implementation in progress.
> See [ADR 24 — Edge ingress on a dedicated thin-client appliance](../decisions/24-edge-ingress-appliance.md),
> [ADR 27 — Monitoring strategy](../decisions/27-monitoring-strategy.md) (Netdata child node),
> [research 28 — Hardware diagnostic](../research/28-wyse3040-hardware-diagnostic.md),
> [research 25 — PL-market hardware](../research/25-edge-ingress-sbc.md),
> [idea 04](../ideas/04-edge-device-tunnel-caddy.md). Tracked in
> [issue #65](https://github.com/jaroslaw-bagnicki/Homelab/issues/65).

> 🛟 **Snapshot before risky changes** — this box has no reinstall shortcut (the Debian Expert
> install took ~2 h). Take a full eMMC system snapshot before any change that could break it —
> see [runbook 27 — Backup & Restore](27-edge-backup-restore.md).

## Goals

- Run `cloudflared` (single outbound QUIC connection to Cloudflare's edge, UDP 7844),
  Caddy, and Netdata as **systemd services** on a minimal distro — bare-metal,
  no Docker.
- **External routing:** `*.example.com` → Caddy → backends over the LAN
  (M910q k3s, ML110 OMV, future gear).
- **Internal routing:** `.home` Caddy routing served by the edge box; `*.home` DNS
  handled by the OPNsense router (idea 07) — ADR 24 architecture split, M910q is compute-only.
- **Monitoring:** Netdata **child node** with RAM-only buffering (no eMMC DB; ADR 27).
- Stay lean: 2 GB RAM / 8 GB eMMC, ~2–3 W idle, fanless.

## Hardware

| Item | Detail |
|---|---|
| Dell Wyse 3040 | Atom x5-Z8350 · 2 GB DDR3L · **8 GB eMMC `mmcblk0` (7.8 GB, H8G4a)** · 1× GbE · fanless |

## Hardware audit — complete (research 28)

Pre-boot diagnostic via SystemRescue + Dell ePSA + Debian installer is finished.
Key facts for the setup (full detail in [research 28](../research/28-wyse3040-hardware-diagnostic.md)):

- **Serial** `8YW28L2`, SKU `07C1`, BIOS Dell **1.2.3** (2017-11-07)
- **CPU** Atom x5-Z8350 (4C/4T, 480–1920 MHz); **RAM** 2 GB DDR3-1600 soldered
- **eMMC** `mmcblk0` = 7.8 GB — present, ePSA Pass, enumerated by the Debian installer.
  ⚠ **SystemRescue 13.02 does NOT show it** (live-media kernel artifact) — don't trust a
  bare `lsblk` from SystemRescue to prove it absent.
- **NIC** Realtek RTL8111/8168, interface `enp1s0`, MAC `8c:ec:4b:6d:6f:4f`
- **BIOS boot** — Setup's Boot Sequence lists **only PXE** (IP4/IP6 Realtek); no storage
  menu exists. Booting the installer/OS from USB/eMMC works via the **F12 One-Time Boot
  Menu**. After install, verify/re-add the eMMC EFI entry to the Boot Sequence.
- Idle temps 51–55 °C; fanless; display DP-1 (active only during console work).

## Prerequisites

- Wyse 3040 + verified charger (see Hardware above)
- USB flash drive + flasher (balenaEtcher / `dd` / Ventoy)
- **Debian minimal (netinst)** ISO — baseline install on the eMMC
- Console (keyboard + monitor) or SSH reachability during setup
- Refs: [research 28](../research/28-wyse3040-hardware-diagnostic.md) (audit), [research 25](../research/25-edge-ingress-sbc.md) (hardware/OS eval), [ADR 24](../decisions/24-edge-ingress-appliance.md) (decision), [runbook 21](21-tl-sg108e-switch.md) (switch placement)

---

## 1. OS Install — Debian Minimal on the eMMC

> **Use the minimal/custom manual install, not the default.** The default Debian desktop
> profile pulls GNOME + apps, far over what a 2 GB/8 GB appliance needs and wastes eMMC
> write endurance. If the default install was already started, abort and restart.

1. Boot the Debian netinst USB via **F12** → USB.
2. Choose **Advanced options → Expert install** (or plain **Install** with tasks deselected)
   so the desktop tasksel profile is skipped.
3. **Partitioning** — choose **Manual** and target `mmcblk0` (the eMMC; the Kingston USB
   `sda` is your installer media — do not touch it):
   - **No swap partition** — 2 GB RAM is tight but the workload is write-light and swap
     on eMMC shortens its life; rely on `systemd-oomd`-free default behavior and the
     2 GB ceiling (ADR 24's constrained-resources design).
   - Single **ext4 `/` partition** for the whole 7.8 GB (or a small ESP + root if the
     installer insists on UEFI/EFI partition — it will, on this firmware: **create the
     EFI System Partition (~100–512 MB, FAT32)** + ext4 root, with `/boot/efi` mount).
   - Flags: bootable on the root/ESP.
4. **Base system** — accept the defaults (standard system utilities only; **no desktop,
   no laptop tasks, no print server**).
5. **GRUB** — install it to **`/dev/mmcblk0`** (NOT `/dev/sda`). Let it register the
   UEFI boot entry for the eMMC.
6. After reboot prompt: remove the USB, press power on, hit **F12** and confirm the eMMC
   now appears as a boot device (it will have a `\EFI\BOOT\BOOTX64.EFI` / GRUB shim entry).
   If it does **not** appear, the firmware is PXE-locked for local media → fall to the
   USB-as-OS-medium decision (research 28 open question 1) and amend ADR 24.
7. If needed afterwards, re-enter **F2 Setup → Boot Sequence** and add the eMMC entry so
   the box boots without F12.

> **OS trial note (ADR 24):** Debian minimal is the baseline. Alpine Linux was the
> parallel lean-OS trial — **dropped 2026-08-18** (staying with Debian 13 minimal). Lock
> the OS in ADR 24 once cloudflared + Caddy + Netdata all validate on Debian.

## Install Progress (2026-08-17)

Debian 13.6.0 install **completed** on the eMMC. Decisions locked during install:

| Item | Decision |
|---|---|
| Installer | Debian 13.6.0 **Expert install** (text mode) |
| Installer components | None added (all defaults auto-loaded) |
| Network | Manual static IP — **`192.168.2.240`/24**, gw `192.168.2.1`, DNS `1.1.1.1, 8.8.8.8` (new `24x` edge block, research 24) |
| IPv6 | Disabled (homelab is IPv4-only, research 24) |
| Root login | **Allowed** — breaking-glass console credential (Keeper), mirroring runbook 25 §2; root SSH locked by default (`prohibit-password`) |
| Timezone | **UTC** (fleet-wide `Etc/UTC`, the `common` Ansible role) |
| Partitioning | **Guided — use entire disk** on `mmcblk0` (eMMC; Kingston USB `sda` untouched): ESP 656 MB FAT32 `/boot/efi` + ext4 `/` 6.4 GB + **swap 790.6 MB** |
| Kernel / initramfs | `linux-image-amd64` (standard) + **targeted** initramfs (this system's drivers only) |
| Mirror | `deb.debian.org` — https failed, http failed (network wrinkle); apt source added post-boot — `deb http://deb.debian.org/debian trixie main` in `sources.list`; `apt-get update`/`upgrade` verified |
| Updates | Only **security updates**; **automatic security install** selected |
| Tasksel | **SSH server** + **standard system utilities** only (no desktop, no web server) |
| GRUB | Installed via the **EFI removable-media path** (`/EFI/BOOT/BOOTX64.EFI`) — Wyse EFI-bug workaround; **NVRAM not updated**; os-prober not run (single-OS) |

> ⚠ **Deviations from the plan above (§1):**
> 1. **Swap partition created** (790.6 MB) — guided partitioning's default; §1 planned
>    "no swap" for eMMC endurance. **Resolved 2026-08-18: swap fully removed and `/`
>    grown.** `mmcblk0p3` deleted with `parted`, `/` resized **5.9G → 6.7G** (ext4 grown
>    with `resize2fs`), swap line dropped from fstab. Confirmed post-reboot: `free -h`
>    shows 0B swap and `dmesg` adds no swap at boot.
> 2. **NVRAM left untouched** — boots via the EFI fallback entry, not a registered UEFI
>    boot entry. **Resolved 2026-08-18:** eMMC entry (`UEFI: Hard Drive, Partition 1`)
>    re-added to the F2 Setup Boot Sequence — the box now boots from the eMMC without F12.

> ✅ **2026-08-22 — System disk snapshot taken.** Full eMMC baseline image (`dd` + gzip) to the
> NAS SMB share (`//192.168.2.210/shared/edge/`), taken before the Netdata (#80) /
> service-migration (#81) work — see [runbook 27 — Backup & Restore](27-edge-backup-restore.md).

---

## 2. Base Setup — bootstrap only (unblock Ansible)

> **Static IP chosen — `192.168.2.240`** (research 24's `24x` edge/appliance block, set during
> install — see Install Progress above).
>
> §2 exists **only to unblock Ansible**; everything beyond the bootstrap is provisioned by the
> `edge_host` role (§3, **planned — #65, role not yet in the repo**), idempotently. Don't
> hand-configure what the role owns (accounts, hardening, services) — that's how drift happens.

### 2.1 Static IP

Configured **during install** (Expert install → manual network) on `enp1s0`:
`192.168.2.240`/24, gw `192.168.2.1`, DNS `1.1.1.1, 8.8.8.8` (research 24 `24x` block).
Verify:

```sh
ip -4 addr show enp1s0        # 192.168.2.240/24
ip route show default         # via 192.168.2.1
ping -c1 192.168.2.1          # gateway reachable
```

### 2.2 SSH for Ansible — fleetadm + fleet key (2026-08-30)

Mirroring [runbook 25](25-m910q-os-refresh.md) §2 / ADR 28: the `fleetadm` agent account
(sudo, agent-account pattern) is the key-only SSH identity Ansible uses.

**Update (2026-08-30):** the 2026-08-23 bootstrap (control-node `lenovo-slim` key) is
obsolete — the box's `fleetadm` account had since been removed, so it was **re-created
fresh** per ADR 28 (new-account pattern, runbook 25 §2):

- Created **`fleetadm`** (uid 1002, `/bin/bash`), added to the **`sudo`** group, with
  `/etc/sudoers.d/fleetadm` NOPASSWD (440); password **locked** (`passwd -l`).
- Installed the **fleet public key** (`fleetadm@homelab`, from
  `ansible/roles/common/files/ssh/fleetadm.pub`) as the **sole** entry in
  `/home/fleetadm/.ssh/authorized_keys` (600, owner `fleetadm`), with restrictive
  `key_options` — the `lenovo-slim` control key is retired (ADR 28).
- **Verified** from the control node: `ssh fleetadm@192.168.2.240` → hostname `edge`,
  `sudo -n whoami` → root.

> Ansible provisioning of edge is implemented by the `edge_host` role via
> `ansible/playbooks/playbook-edge.yml` (edge added to the inventory on this branch).

---

## 3. Ansible provisioning — `edge_host` role

ADR 24 specifies a new `edge_host`-style role (systemd units) distinct from `docker_services`.
The role provisions everything beyond the §2 bootstrap, idempotently, via
`ansible/playbooks/playbook-edge.yml` (`common → security → edge_host`):

- **hostname `edge`** + **name broadcast** — Avahi (`edge.local`, via `common`) — nmbd dropped 2026-08-26 (mDNS suffices; the bare `edge` NetBIOS name is not needed)
- **SSH hardening** — password auth off, key-only login (**added to the shared `security` role**,
  fleet-wide drop-in `/etc/ssh/sshd_config.d/99-homelab-hardening.conf`)
- **UFW** (SSH from `192.168.2.0/24`, deny inbound otherwise) + **fail2ban** +
  `unattended-upgrades`
- **eMMC longevity** — journald `Storage=volatile`, logrotate; Netdata is RAM-only (see §6)
- **services §4–§6** — cloudflared, Caddy, Netdata (install + config + systemd units)

**Base provisioning is written and committed 2026-08-26** (the `edge_host` role + `common`/`security`
reuse — see §3a). Services §4–§6 are a follow-up once the base is verified live on the box.

### 3a. Role layout (base phase)

- `ansible/roles/common` (reused) — hostname `edge`, `Etc/UTC`, `systemd-timesyncd`, Avahi
  (`common_enable_avahi: true` → `edge.local`)
- `ansible/roles/security` (reused, tuned via `host_vars/edge.yml`) — UFW default-deny +
  SSH allow from `192.168.2.0/24` (`security_ufw_allow_ssh_from`), fail2ban, sshd key-only
  hardening; `security_ufw_deny_inbound_tcp_80: false` (the edge owns :80)
- `ansible/roles/edge_host` (new) — `unattended-upgrades`, `logrotate`, journald
  `Storage=volatile`, the DNS search domain (`edge_dns_search`, default empty — removes the
  installer's `cloud5.ovh` search leftover); UFW stays deny-inbound — cloudflared → Caddy
  runs over loopback, no :80 opened (nmbd dropped 2026-08-26 — Avahi suffices)
- `ansible/host_vars/edge.yml` + `inventory.ini` (`edge` → `192.168.2.240`)

---

## 4. cloudflared — Tunnel

**Target state (services follow-up, §4–§6)** — to be deployed by the `edge_host` role; this documents the resulting state:

- **systemd unit** — `cloudflared tunnel run --token …`, `Enabled` + `Restart=on-failure`;
  outbound-only path (UDP 7844 QUIC to CF edge; UFW keeps all inbound closed).
- **Tunnel token** — from the Zero Trust dashboard, stored in a root-only file (secret via
  the KV/Ansible secret pattern, ADR 10/16/19) — **never in git**.
- **Route** the tunnel to Caddy over **HTTP** (the ADR 19/24 pattern): dashboard ingress
  rules point hostnames (`*.example.com`) at `http://127.0.0.1:80` — TLS terminates at the
  CF edge; cloudflared ↔ Caddy is plain HTTP over **loopback** (both on the edge box), so no
  inbound :80 is opened on UFW.

---

## 5. Caddy — Reverse Proxy

**Target state (services follow-up, §4–§6)** — to be installed/configured by the `edge_host` role; the Caddyfile lives in the
repo, rendered to `/etc/caddy/Caddyfile`, `Caddyfile reload` on change (ADR 10).

- **Single Caddyfile for both planes** (ADR 20 — one Caddyfile is the source of truth):
  - **External** `*.example.com` sites → backends over the LAN (M910q k3s, ML110 OMV,
    future gear). Served on :80, TLS handled at the CF edge (ADR 19).
  - **Internal** `*.home` sites (DNS via OPNsense, idea 07) → routed by the same Caddy on
    :80/:443 with Caddy's local auto-TLS or plain HTTP per service.
- No Cloudflare Origin CA needed on the edge: per ADR 19's revised pattern, cloudflared →
  Caddy is **plain HTTP over loopback** (`127.0.0.1:80`, both on the edge box) — the earlier
  HTTPS-origin attempt failed on SNI mismatch and config-file override limits.

> **Terminology note — TLS split (plain language):** Cloudflare's edge terminates TLS for
> public clients (`https://*.example.com` → CF). The hop from cloudflared to Caddy is a
> private loopback connection on the edge box and can be plain HTTP — no cert needed on the edge. This is the
> same pattern cloudlab already uses (ADR 19 revised).

---

## 6. Monitoring — Netdata Child Node

**Target state (services follow-up, §4–§6)** — to be installed/configured by the `edge_host` role; this documents the
resulting state:

- **RAM-only buffering** — `/etc/netdata/netdata.conf`:
  ```ini
  [db]
      mode = ram
  ```
  No `dbengine` disk store — per ADR 24 (eMMC endurance) and ADR 27 (lightweight Edge
  child node).
- **Standalone-first, parent-later (ADR 27):** run as a standalone child with local
  alarms now; re-point to the M910q Netdata Parent (k3s workload) when it lands.
- Resource check: expect ~60–100 MB RSS with the minimal profile — fits the 2 GB budget
  alongside cloudflared + Caddy.

---

## 7. Validation

> *To be completed.* End-to-end checks:

- **Boot:** power-cycle → eMMC boots without F12 (Boot Sequence entry present).
- **Services:** `systemctl status cloudflared caddy netdata` all active.
- **External:** `curl https://app.example.com` resolves + serves from the backend edge box
  path; `*.example.com` wildcard → Caddy → backend.
- **Internal DNS:** `nslookup service.home <edge-ip>` → edge IP; client on DHCP → router
  hands out edge DNS → `service.home` resolves.
- **Monitoring:** Netdata dashboard reachable; child streams to parent once it lands.
- **Failover:** behaviour with the M910q tunnel (replace vs parallel, idea 04) — decide
  during cutover.
- **eMMC wear sanity:** `dmesg | grep -i mmc` clean; `df -h /` shows expected usage
  (<50% of 7.8 GB after services + logs with rotation).

---

## 8. Switch Placement

- Port on the TL-SG108E (runbook 21) — a spare port (6–8 is fine; the switch plan has
  ports 2/3/5 in use).
- Static IP `192.168.2.240` from the reserved `24x` block — assigned during install (see §2).
- Update the topology diagrams in [overview](../overview.md) and [research 24](../research/24-network-topology-design.md)
  once the IP is assigned.
- Repoint internal `.home` DNS consumers (router DHCP DNS, device configs) at the edge,
  and note the M910q dnsmasq is retired (runbook 25 §What changes — DNS/Caddy/tunnel leave
  the M910q).

---

## Verification Checklist

- [x] §1 Debian minimal installed on `mmcblk0`; eMMC boots without F12 (entry re-added 2026-08-18)
- [x] §2 Static IP `192.168.2.240` reachable; SSH key-only login (fleet key, 2026-08-30)
- [ ] §3 `edge.local` + bare `edge` resolve on the LAN; SSH by name (live run 2026-08-30 — manual verify from LAN)
- [x] §3 UFW active (SSH from LAN only); fail2ban on (live run 2026-08-30 — ok=24)
- [ ] §4 cloudflared tunnel up (`cloudflared tunnel list`)
- [ ] §5 Caddy serves `*.example.com` and `*.home`
- [ ] §6 Netdata child running (RAM-only); dashboard reachable
- [ ] §7 all validation checks pass
- [ ] §8 switch port wired; `docs/overview.md` / `docs/hardware.md` reflect the edge node

## References

- [Diagnostic — research 28](../research/28-wyse3040-hardware-diagnostic.md) — hardware audit + eMMC investigation
- [ADR 24](../decisions/24-edge-ingress-appliance.md) — edge appliance decision (OS, DNS, bare-metal)
- [ADR 27](../decisions/27-monitoring-strategy.md) — Netdata child node on the edge (RAM-only)
- [ADR 20](../decisions/20-caddy-single-routing-layer.md) — single Caddyfile routing layer
- [ADR 19](../decisions/19-cloudflare-tunnel-https-origin.md) — CF HTTPS origin pattern (HTTP to origin)
- [Research 25](../research/25-edge-ingress-sbc.md) — PL-market hardware + OS evaluation
- [Idea 04](../ideas/04-edge-device-tunnel-caddy.md) — original edge idea
- [Runbook 01](01-init.md) — base setup / hardening pattern · [Runbook 03](03-dns.md) — dnsmasq pattern
- [Runbook 21](21-tl-sg108e-switch.md) — switch placement · [Runbook 25](25-m910q-os-refresh.md) — DNS/Caddy/tunnel migration context
- [Issue #65](https://github.com/jaroslaw-bagnicki/Homelab/issues/65) — this work
