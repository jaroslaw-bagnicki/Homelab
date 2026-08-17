# Edge Appliance (Wyse 3040) — Runbook

> Deploy the homelab's **dedicated edge appliance** — bare-metal `cloudflared` + Caddy +
> dnsmasq + Netdata on a Dell Wyse 3040 thin client — as the single public ingress and
> local DNS server for the LAN.
> Device acquired **2026-08-13**; hardware audit complete **2026-08-17**; implementation in progress.
> See [ADR 24 — Edge ingress on a dedicated thin-client appliance](../decisions/24-edge-ingress-appliance.md),
> [ADR 27 — Monitoring strategy](../decisions/27-monitoring-strategy.md) (Netdata child node),
> [research 28 — Hardware diagnostic](../research/28-wyse3040-hardware-diagnostic.md),
> [research 25 — PL-market hardware](../research/25-edge-ingress-sbc.md),
> [idea 04](../ideas/04-edge-device-tunnel-caddy.md). Tracked in
> [issue #65](https://github.com/jaroslaw-bagnicki/Homelab/issues/65).

## Install Progress (2026-08-17)

Debian 13.6.0 install **completed** on the eMMC. Decisions locked during install:

| Item | Decision |
|---|---|
| Installer | Debian 13.6.0 **Expert install** (text mode) |
| Installer components | None added (all defaults auto-loaded) |
| Network | Manual static IP — **`192.168.2.240`/24**, gw `192.168.2.1`, DNS `1.1.1.1, 8.8.8.8` (new `24x` edge block, research 24) |
| IPv6 | Disabled (homelab is IPv4-only, research 24) |
| Root login | **Allowed** — breaking-glass console credential (Keeper), mirroring runbook 25 §2 |
| Timezone | **UTC** (fleet-wide `Etc/UTC`, the `common` Ansible role) |
| Partitioning | **Guided — use entire disk** on `mmcblk0` (eMMC; Kingston USB `sda` untouched): ESP 656 MB FAT32 `/boot/efi` + ext4 `/` 6.4 GB + **swap 790.6 MB** |
| Kernel / initramfs | `linux-image-amd64` (standard) + **targeted** initramfs (this system's drivers only) |
| Mirror | `deb.debian.org` — https failed, http failed (network wrinkle); apt mirror state TBD post-boot |
| Updates | Only **security updates**; **automatic security install** selected |
| Tasksel | **SSH server** + **standard system utilities** only (no desktop, no web server) |
| GRUB | Installed via the **EFI removable-media path** (`/EFI/BOOT/BOOTX64.EFI`) — Wyse EFI-bug workaround; **NVRAM not updated**; os-prober not run (single-OS) |

> ⚠ **Deviations from the plan above (§1):**
> 1. **Swap partition created** (790.6 MB) — guided partitioning's default; §1 planned
>    "no swap" for eMMC endurance. Pending decision: keep as a 2 GB RAM safety valve vs
>    remove post-install.
> 2. **NVRAM left untouched** — boots via the EFI fallback entry, not a registered UEFI
>    boot entry. Verify F12 shows the eMMC, then re-add it to the F2 Setup Boot Sequence.

**Handoff to next thread:** reboot → confirm eMMC boot via F12 (research 28 open Q1) →
settle swap keep/remove → verify apt mirror works → continue with §2 base setup.

## Goals

- Run `cloudflared` (single outbound QUIC connection to Cloudflare's edge, UDP 7844),
  Caddy, dnsmasq, and Netdata as **systemd services** on a minimal distro — bare-metal,
  no Docker.
- **External routing:** `*.example.com` → Caddy → backends over the LAN
  (M910q k3s, ML110 OMV, future gear).
- **Internal routing + DNS:** `*.home` DNS via dnsmasq and `.home` Caddy routing both
  served by the edge box (ADR 24 architecture split — M910q is compute-only).
- **Monitoring:** Netdata **child node** with RAM-only buffering (no eMMC DB; ADR 27).
- Stay lean: 2 GB RAM / 8 GB eMMC, ~2–3 W idle, fanless.

## Hardware (purchased)

| Item | Detail |
|---|---|
| Dell Wyse 3040 | Atom x5-Z8350 · 2 GB DDR3L · **8 GB eMMC `mmcblk0` (7.8 GB, H8G4a)** · 1× GbE · fanless |
| Purchase date | 2026-08-13 |
| Device price | 89,00 PLN (~20,70 EUR) — won at auction; the 69,00 PLN offer was closed |
| Charger | 35,94 PLN (~8,36 EUR) — 24,99 PLN + 10,95 PLN shipping |
| **Total** | **124,94 PLN (~29,06 EUR)** |
| Exchange rate | ≈4,30 PLN/EUR (Aug 2026) |

> ⚠ **Charger compatibility**: the device shipped without a charger — verify the
> purchased one matches the Wyse 3040's power spec (barrel connector size + voltage)
> before first boot. Verified working 2026-08-17 (AC `ADP1` attached during the audit).

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
> parallel lean-OS trial; it is deferred — the eMMC install path is being validated with
> Debian first. Lock the OS in ADR 24 once cloudflared + Caddy + dnsmasq + Netdata all
> validate on Debian.

---

## 2. Base Setup

> **Static IP chosen — `192.168.2.240`** (research 24's new `24x` edge/appliance block,
> set during install, see Install Progress above).

1. **Static IP** — configure `enp1s0` in `/etc/network/interfaces` (or netplan if
   installed) with the chosen `192.168.2.X`, gateway `192.168.2.1`, DNS `1.1.1.1, 8.8.8.8`
   — mirror [runbook 01](01-init.md) §1.2.
2. **Hostname** — `edge` (or `edge.home`-friendly short name), set in `/etc/hostname`.
3. **SSH** — install `openssh-server`, add the control node's public key to root/`labadmin`,
   disable password auth — mirror [runbook 01](01-init.md) §2/§5 and runbook 25 §2
   (`labadmin` agent account pattern).
4. **Hardening** — UFW (allow SSH from `192.168.2.0/24`, deny inbound otherwise),
   fail2ban, `unattended-upgrades` — mirror [runbook 01](01-init.md) §6 and the Ansible
   `security` role pattern.
5. **eMMC longevity** — aggressive log rotation (`logrotate`) and no heavy disk writes;
   Netdata is RAM-only (see §6) per ADR 24/27.
6. **Ansible provisioning (future)** — ADR 24 specifies a new `edge_host`-style role
   (systemd units) distinct from `docker_services`. This runbook's manual steps map 1:1
   to that role; the role is written once the OS + services validate (§7).

---

## 3. Local DNS — dnsmasq

> ADR 24 moved local DNS to the edge: `*.home` resolution must survive M910q/k3s churn.
> The edge box is now the DNS server that runbook 03's dnsmasq used to run on the M910q.

1. Install: `apt install dnsmasq` (bare-metal package, not Docker — mirrors ADR 24's
   bare-metal exception; runbook 03's Docker variant was the M910q-era pattern).
2. `/etc/dnsmasq.conf`:
   ```conf
   # Wildcard: all .home domains resolve to the edge box (Caddy handles routing)
   address=/.home/192.168.2.X

   # Upstream forwarders
   server=192.168.2.1    # router
   server=1.1.1.1
   server=8.8.8.8

   domain-needed
   bogus-priv
   cache-size=2000
   ```
3. Start/enable: `systemctl enable --now dnsmasq` (will occupy port 53 — no
   `systemd-resolved` on a minimal Debian install).
4. Point the router's DHCP DNS (or client devices) at the edge's `192.168.2.X`
   (mirror runbook 03 §4).

---

## 4. cloudflared — Tunnel

1. Install via the official apt repo:
   ```sh
   curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | gpg --dearmor -o /usr/share/keyrings/cloudflare.gpg
   echo 'deb [signed-by=/usr/share/keyrings/cloudflare.gpg] https://pkg.cloudflare.com/cloudflared any main' > /etc/apt/sources.list.d/cloudflared.list
   apt update && apt install cloudflared
   ```
2. **Tunnel token** — from the Zero Trust dashboard; deploy as a **systemd unit**
   (`cloudflared tunnel run --token …`) with the token stored in a root-only file —
   **never in git** (security rule; KV/Ansible secret pattern from ADR 10/16/19).
3. **systemd unit** — `Enabled` + `Restart=on-failure`; outbound-only path (UDP 7844
   QUIC to CF edge; UFW keeps all inbound closed).
4. **Route** the tunnel to Caddy over **HTTP** (the ADR 19/24 pattern): dashboard ingress
   rules point hostnames (`*.example.com`) at `http://<edge-ip>:80` — TLS terminates at
   the CF edge; cloudflared ↔ Caddy is plain LAN HTTP.

---

## 5. Caddy — Reverse Proxy

1. Install via the Caddy apt repo (`caddyserver.com` — match the cloudlab flow,
   runbook 16).
2. **Single Caddyfile for both planes** (ADR 20 — one Caddyfile is the source of truth):
   - **External** `*.example.com` sites → backends over the LAN (M910q k3s, ML110 OMV,
     future gear). Served on :80, TLS handled at the CF edge (ADR 19).
   - **Internal** `*.home` sites (from §3 dnsmasq) → routed by the same Caddy on :80/:443
     with Caddy's local auto-TLS or plain HTTP per service.
3. Config is **templated by Ansible** (`edge_host` role) — the Caddyfile lives in the repo,
   rendered to `/etc/caddy/Caddyfile`, `Caddyfile reload` on change (ADR 10).
4. No Cloudflare Origin CA needed on the edge: per ADR 19's revised pattern, cloudflared →
   Caddy is **plain HTTP** on the LAN (the earlier HTTPS-origin attempt failed on SNI
   mismatch and config-file override limits).

> **Terminology note — TLS split (plain language):** Cloudflare's edge terminates TLS for
> public clients (`https://*.example.com` → CF). The hop from cloudflared to Caddy is a
> private LAN connection and can be plain HTTP — no cert needed on the edge. This is the
> same pattern cloudlab already uses (ADR 19 revised).

---

## 6. Monitoring — Netdata Child Node

1. Install via the kickstart script (research 26 §9 pattern):
   ```sh
   wget -O /tmp/netdata-kickstart.sh https://my-netdata.io/netdata-kickstart.sh && sh /tmp/netdata-kickstart.sh
   ```
2. **RAM-only buffering** — `/etc/netdata/netdata.conf`:
   ```ini
   [db]
       mode = ram
   ```
   No `dbengine` disk store — per ADR 24 (eMMC endurance) and ADR 27 (lightweight Edge
   child node).
3. **Standalone-first, parent-later (ADR 27):** run as a standalone child with local
   alarms now; re-point to the M910q Netdata Parent (k3s workload) when it lands.
4. Resource check: expect ~60–100 MB RSS with the minimal profile — fits the 2 GB budget
   alongside cloudflared + Caddy + dnsmasq.

---

## 7. Validation

> *To be completed.* End-to-end checks:

- **Boot:** power-cycle → eMMC boots without F12 (Boot Sequence entry present).
- **Services:** `systemctl status cloudflared caddy dnsmasq netdata` all active.
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
- Static IP `192.168.2.X` from the reserved block (decision deferred — see §2).
- Update the topology diagrams in [overview](../overview.md) and [research 24](../research/24-network-topology-design.md)
  once the IP is assigned.
- Repoint internal `.home` DNS consumers (router DHCP DNS, device configs) at the edge,
  and note the M910q dnsmasq is retired (runbook 25 §What changes — DNS/Caddy/tunnel leave
  the M910q).

---

## Verification Checklist

- [ ] §1 Debian minimal installed on `mmcblk0`; eMMC boots without F12
- [ ] §2 Static IP `192.168.2.X` reachable; SSH key-only login
- [ ] §2 UFW active (SSH from LAN only); fail2ban on
- [ ] §3 dnsmasq resolves `service.home` → edge IP; router serves it as DNS
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