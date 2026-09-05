# Hardware Inventory

Per-node hardware detail for the homelab. For the high-level node/workload view see
[Overview](overview.md); for network design see [research 24](research/24-network-topology-design.md).

**Status legend**: ✅ running · 🔨 in progress · 📋 planned · 🧠 idea

## Summary

| Node | Role | Device | CPU | RAM | Storage | Network | Status |
|---|---|---|---|---|---|---|---|
| **Lab** | main workload host | Lenovo ThinkCentre M910q Tiny | i5-7500T (4C/4T, 35 W) | 16 GB DDR4 | 256 GB NVMe (+ free 2.5" bay) | 1× GbE `enp0s31f6` | ✅ |
| **OMV NAS** | OpenMediaVault server, backup target | HP ProLiant ML110 G5 | Pentium E2160 (2C/2T, 65 W) | 4 GB DDR2 | Goodram 120 GB SSD + RAID1 arrays | 1× GbE BCM5722 | ✅ |
| **Beetle NAS** | Unraid NAS backup target (successor to ML110) | Wincor Beetle M-III | Pentium G3420 (2C/2T, 53 W) | 4 GB DDR3 (1×, 1 free slot) | SanDisk 128 GB SSD + 2× Seagate 1 TB 2.5" | 1× GbE Intel I217-V | 🔨 |
| **Edge Ingress** | public ingress | Dell Wyse 3040 | Atom x5-Z8350 (2 W TDP) | 2 GB DDR3L | 8 GB eMMC | 1× GbE | 🔨 |
| **Home Assistant** | smart home node | Dell Wyse 5070 | Celeron J4105 (10 W) | 8 GB DDR4 (2× 4 GB) | M.2 SATA SK hynix 128 GB | 1× GbE + WiFi | 🔨 |
| **OPNsense Router** | LAN edge router / firewall | Fujitsu Futro S930 | GX-424CC (4C/4T, 25 W TDP) | 4 GB DDR3 (1×, 1 free slot) | Innodisk 7.99 GB mSATA | 3× GbE (BCM5720 2× + Realtek 1×) | 📋 |
| **LLM server** | local LLM inference | Minisforum AI X1 | Ryzen 7 255 (Hawk Point, 45 W cTDP) | 64–96 GB DDR5 | NVMe | 1× GbE | 🧠 (Phase 2) |
| **Cloudlab VPS** | staging / playground | Contabo Cloud VPS 10 | 4 vCPU (cloud — no TDP) | 8 GB | 75 GB NVMe | public IP | ✅ |

## Compute & Storage Nodes

### Lab — Lenovo ThinkCentre M910q Tiny

| Item | Spec |
|---|---|
| CPU | Intel Core i5-7500T (4C/4T, 35 W TDP, QuickSync) |
| RAM | 16 GB DDR4 (1× 16 GiB SODIMM in ChannelB-DIMM0 @ 2400 MT/s; ChannelA-DIMM0 empty — 2 slots, upgradeable to 32 GB) |
| Storage | 256 GB NVMe — SK hynix BC501 HFM256GDJTNG-8310A · serial `FS85N582310805D30` · FW `80000C00` · SMART **PASSED** (1% used, 16,355 POH — §0 audit 2026-08-16); free 2.5" SATA bay for a secondary/backup disk |
| Firmware | BIOS LENOVO M1AKT2CA (2017-11-22) · board 310B |
| Network | 1× Gigabit Ethernet Intel I219-LM (`enp0s31f6`, MAC `6c:4b:90:40:c5:e2`) |
| Role | Main workload host — OS refresh to Ubuntu 24.04 LTS + Arc enrolment in progress (runbook 25), then k3s (ADR 22) |
| Docs | [ADR 01](decisions/01-hardware-selection-m910q.md) · [runbook 25](runbooks/25-m910q-os-refresh.md) · [overview](overview.md) |

### OMV NAS — HP ProLiant ML110 G5

| Item | Spec |
|---|---|
| CPU | Intel Pentium E2160 @ 1.8 GHz (2C/2T, 65 W TDP) |
| RAM | 4 GB (2× 2 GiB DDR2-800) |
| Boot | Goodram C40 120 GB SSD (ICH9 SATA #5, OMV 8.3) |
| Data | `md0` = 2× 500 GB Hitachi HDS721050CLA660 (RAID1 → XFS) · `md1` = 2× 250 GB (RAID1 → ext4) |
| Spare | 1 TB WD10EZEX — **offline** (role: offline, decided 2026-08-15) |
| Controllers | ICH9R 4-port + ICH9 2-port SATA; Dell SAS 6/iR **removed** (no hardware RAID) |
| Network | 1× GbE Broadcom BCM5722 (`enp14s0`), MAC `78:e7:d1:53:fb:87` |
| Management | None — no LO100/IPMI, direct console only; fan control not software-addressable |
| Docs | [runbook 22](runbooks/22-ml110-nas-inventory.md) · [runbook 23](runbooks/23-ml110-omv-setup.md) · [research 23](research/23-ml110-nas-omv.md) · [ADR 23](decisions/23-nas-on-ml110.md) |

### Beetle NAS — Wincor Beetle M-III (planned)

| Item | Spec |
|---|---|
| CPU | Intel **Pentium G3420** (Haswell, 2C/2T, 3.2 GHz, 3 MB L3, 53 W) — AES-NI, QuickSync (H.264 only) |
| RAM | **4 GB DDR3-1600** (1× 4 GiB SODIMM — 2 slots, **DIMM 1 free** → 8 GB is a one-stick upgrade) |
| Storage | **SanDisk X600 128 GB SSD** (cache, SMART PASSED) + **2× Seagate ST1000VT001-1RE172 1 TB 2.5"** (Seagate **Video 2.5** surveillance; **CMR (Perpendicular)** — `sdb` 138 MB/s, `sdc` 132 MB/s rewrite; SMART PASSED, **~65.5k POH**; array 1 parity + 1 data = 1 TB usable). ⚠️ Extended self-test pending — final Seagate-vs-WD decision held |
| Acquire notes | Offer described these as *"removed from high-budget laptops"* — **contradicted** by the always-on SMART history (65,536 POH / 4 power-cycles); drive provenance misdescription (seller-complaint point, issue #98) |
| SATA | H81 **4-port AHCI** (2× SATA III 6 Gb/s + 2× SATA II 3 Gb/s) — no mSATA/NVMe installed; **mini-PCIe (mSATA) slot + PCIe 3.0 x16** available (future NVMe/HBA/NIC/cache) |
| PSU | **AcBel 250 W, 80 Plus Gold** (Wincor `01750279900`) — +5V 10.5A rail ample for the drives |
| Cooling | **3 fans** (front → CPU+PSU, rear PSU-end, UPS-unit); **42.5 dB @ 30 cm**; Gelid Fan Speed Controller planned (~32–35 dB) |
| Network | 1× GbE Intel I217-V (`enp0s25`, MAC `00:01:2e:86:11:0c`) · DHCP `192.168.2.241` |
| Board | `K2.1-H81-uATX` (WINCOR NIXDORF) · BIOS AMI `WN STD 07/16` (2018-12-19) · SN `000000001750261682 53R0455744` |
| Role | Unraid NAS backup-target successor to the ML110 — [issue #98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98) |
| Acquisition | 2026-09-05 — hardware diagnostic complete ([research 32](research/32-wincor-beetle-m3-hardware-diagnostic.md)); Unraid install pending |
| Docs | [idea 01c](ideas/01c-nas-backup-target-wincor-beetle.md) · [research 32](research/32-wincor-beetle-m3-hardware-diagnostic.md) · [issue #98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98) |

### Edge Ingress — Dell Wyse 3040

| Item | Spec |
|---|---|
| CPU | Intel Atom x5-Z8350 (2 W TDP) |
| RAM | 2 GB DDR3L |
| Storage | 8 GB eMMC |
| Firmware | BIOS Dell 1.2.3 (2017-11-07) · SKU 07C1 · serial `8YW28L2` |
| Network | 1× GbE Realtek RTL8111/8168 (`enp1s0`, MAC `8c:ec:4b:6d:6f:4f`) · static `192.168.2.240/24` |
| OS | Debian 13 minimal (netinst on eMMC, no desktop) |
| Cooling | Fanless · ~2–3 W idle |
| Role | Dedicated public ingress — bare-metal `cloudflared` + Caddy (ADR 24) |
| Docs | [runbook 24](runbooks/24-edge-appliance.md) · [ADR 24](decisions/24-edge-ingress-appliance.md) · [research 25](research/25-edge-ingress-sbc.md) · [idea 04](ideas/04-edge-device-tunnel-caddy.md) |

### Home Assistant — Dell Wyse 5070

| Item | Spec |
|---|---|
| CPU | Intel Celeron J4105 (Gemini Lake, 4C/4T, 2.5 GHz, 10 W TDP) — fanless, idle ~35 °C |
| RAM | **8 GB DDR4 (2× 4 GiB Micron `4ATF51264HZ-3G2J1`)** — both SODIMM slots populated (DDR4-3200 rated, 2400 MT/s); 16 GB = replace both with 2× 8 GB |
| Storage | M.2 **SATA** 2280 — **SK hynix SC311 SATA 128 GB** (used, SMART PASSED, ~97% NAND life left, SN `MS8BN03201230BC10`); eMMC 14.7 GiB present, unused |
| Network | Realtek RTL8111/8168 GbE (`enp1s0`, MAC `c0:25:a5:65:02:67`) · Intel CNVi WiFi + BT (`wlp0s12f0`, MAC `d0:3c:1f:cb:76:9a`) |
| Zigbee | Sonoff Zigbee 3.0 USB Dongle Plus (ZBDongle-P / CC2652P) — USB coordinator for LXC 102 passthrough (by-id pattern, research 26 §4) |
| Firmware | BIOS 1.34.0 (2024-11-08) · board 060J9C · SKU `080C` · SN `16474B3` |
| Role | Home Assistant OS VM on Proxmox VE + Mosquitto/Zigbee2MQTT LXCs (ADR 25) |
| Acquisition | 2026-08-19 — hardware diagnostic done ([research 29](research/29-wyse5070-hardware-diagnostic.md)); SK hynix SSD + Sonoff ZBDongle-P acquired; Proxmox install pending |
| Docs | [idea 05](ideas/05-home-assistant-thin-client.md) · [ADR 25](decisions/25-home-assistant-thin-client.md) · [research 26](research/26-home-assistant-thin-client.md) · [research 29](research/29-wyse5070-hardware-diagnostic.md) |

### OPNsense Router — Fujitsu Futro S930 (planned)

| Item | Spec |
|---|---|
| CPU | AMD **GX-424CC** (Jaguar-family, 4C/4T, 2.4 GHz, 2 MB L2, 25 W TDP) — AES-NI present, no SHA-NI |
| RAM | **4 GB DDR3-1600** (1× 4 GiB SK hynix `HMT451S6BFR8A-PB` @ 1600 MT/s) — 2 SODIMM slots, **DIMM 2 free** → 8 GB is a one-stick upgrade |
| Storage | **Innodisk DEMSR-08GB mSATA 3ME3 — 7.99 GB** (`sda`, SN `20171003AAAA159004FC`) · SMART **PASSED** (5,066 POH, 0 errors); **tight** for OPNsense — 32–128 GB mSATA swap recommended |
| Network | **Broadcom NetXtreme BCM5720 2× 1 GbE** (FreeBSD `bge`) in the PCIe slot = WAN + LAN · onboard **Realtek RTL8111/8168** (`re`) = MGMT/OPT · **slot trains Gen1 ×1** (no BIOS option — platform limit) |
| Firmware | BIOS AMI **R1.14.0** (2017-09-21) · board `D3313-E1` · SN `YMFH014511` |
| Cooling | Fanless · ~59 °C idle · ~8–15 W idle (Jaguar 25 W) |
| Role | LAN edge router — **OPNsense** (DHCP + NAT + firewall), routing-first, VLANs later — [issue #96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96) |
| Acquisition | 2026-09-02 — hardware diagnostic complete ([research 31](research/31-futro-s930-hardware-diagnostic.md)); OPNsense install pending |
| Docs | [idea 07](ideas/07-opnsense-futro-s930.md) · [research 31](research/31-futro-s930-hardware-diagnostic.md) · [issue #96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96) |

### LLM server — Minisforum AI X1 (Phase 2, 🧠 idea)

| Item | Spec |
|---|---|
| CPU | Ryzen 7 255 (Hawk Point / Zen 4, Radeon 780M 12 CU, 45 W cTDP) |
| RAM | 64–96 GB DDR5 (planned) |
| Role | Local LLM inference (Bielik, Llama-3 8B etc.) via UMA frame buffer; OCuLink future eGPU |
| Docs | [research 08](research/08-llm-server-hardware.md) |

### Cloudlab VPS — Contabo Cloud VPS 10

| Item | Spec |
|---|---|
| Compute | 4 vCPU, 8 GB RAM |
| Storage | 75 GB NVMe |
| OS | Ubuntu 24.04 LTS (pre-installed by Contabo) |
| Role | Ansible staging/playground + hosted workloads (Portainer, Caddy, cloudflared, OpenCode, Zot) |
| Docs | [runbook 10](runbooks/10-vps-playground.md) · [ADR 13](decisions/13-cloudlab-staging.md) |

## Network Appliances

### TP-Link TL-SG108E switch

| Item | Spec |
|---|---|
| Ports | 8× Gigabit Ethernet (L2, utility-managed) |
| Hardware | Rev V1 — web UI non-functional (HTTP 501), managed via **Easy Smart Configuration Utility** (Windows) |
| IP | `192.168.2.230` (static) |
| Role | Access switch — turns the single office drop into wired ports for Lab, OMV NAS, Edge Ingress, work dock |
| Docs | [runbook 21](runbooks/21-tl-sg108e-switch.md) · [research 24](research/24-network-topology-design.md) |

### Tenda Nova mesh

| Item | Spec |
|---|---|
| Units | 3× Mesh3 (AC1200) + 1× Mesh5s (AC1200) in use — 4 units on the mesh (1 lost) |
| Topology | Single broadcast domain, no VLAN trunking; gateway `192.168.2.1` |
| Role | House Wi-Fi + the single office Ethernet drop that feeds the TL-SG108E |
| Docs | [research 24](research/24-network-topology-design.md) |

### ISP fiber router

| Item | Spec |
|---|---|
| Network | `192.168.1.0/24` (WAN side of the mesh) |
| Role | ISP edge; home connection is **CGNAT** — no public inbound, remote access via Cloudflare Tunnel (ADR 08) |

### Huawei B593u-12 LTE modem — Speedport LTE II (backup WAN)

| Item | Spec |
|---|---|
| Model | Huawei B593u-12 (Telekom Speedport LTE II) · LTE **Cat. 3** · material `40264880` |
| Serial | `N4Y5TD9331405207` |
| Network | 4× 100 Mbps Ethernet (Fast Ethernet) + Wi-Fi; **Orange APN** added manually (legacy T-Mobile APN was the default) |
| Speed | ~3–8 Mbps down / ~4–7 Mbps up, ping ~25–36 ms (measured 2026-08-26) |
| Stability | ⚠️ Unstable — frequently fails to attach to the BTS; power cycle recovers |
| Data plan | Orange Flex additional SIM (free) — internet-only, shares the plan data pool |
| Role | Backup WAN (LTE failover) for the homelab edge — fallback until the ZTE WF830 ODU is found (idea 08) |
| Docs | [idea 08](ideas/08-lte-wan-failover.md) · [research 30](research/30-mobile-internet-failover-offers.md) |
