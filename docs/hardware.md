# Hardware Inventory

Per-node hardware detail for the homelab. For the high-level node/workload view see
[Overview](overview.md); for network design see [research 24](research/24-network-topology-design.md).

**Status legend**: ✅ running · 🔨 in progress · 📋 planned · 🧠 idea

## Summary

| Node | Role | Device | CPU | RAM | Storage | Network | Status |
|---|---|---|---|---|---|---|---|
| **Lab** | main workload host | Lenovo ThinkCentre M910q Tiny | i5-7500T (4C/4T, 35 W) | 16 GB DDR4 | 256 GB NVMe (+ free 2.5" bay) | 1× GbE `enp0s31f6` | ✅ |
| **OMV NAS** | OpenMediaVault server, backup target | HP ProLiant ML110 G5 | Pentium E2160 (2C/2T, 65 W) | 4 GB DDR2 | Goodram 120 GB SSD + RAID1 arrays | 1× GbE BCM5722 | ✅ |
| **Beetle NAS** | OMV NAS backup target (successor to ML110) | Wincor Beetle M-III | Pentium G4400 (2C/2T, 3.3 GHz) | 8 GB DDR4 (1×, 1 free slot) | SanDisk 128 GB SSD + 2× Seagate 1 TB 2.5" | 1× GbE Intel I219-V | 🔨 |
| **Edge Ingress** | public ingress | Dell Wyse 3040 | Atom x5-Z8350 (2 W TDP) | 2 GB DDR3L | 8 GB eMMC | 1× GbE | 🔨 |
| **Proxmox VE** | virtualisation host — smart-home + always-on services | Dell Wyse 5070 | Celeron J4105 (10 W) | 8 GB DDR4 (2× 4 GB) | M.2 SATA SK hynix 128 GB | 1× GbE + WiFi | 🔨 |
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

### Beetle NAS — Wincor Beetle M-III

| Item | Spec |
|---|---|
| CPU | Intel Pentium G4400 (2C/2T, 3.3 GHz) · AES-NI, VT-x, VT-d, QuickSync |
| RAM | 8 GB DDR4 (1× 8 GiB SODIMM @ 2133 MT/s; 1 slot free, 32 GB max) |
| Storage | SanDisk X600 128 GB SSD (OS) + 2× Seagate 1 TB 2.5" → `md0` RAID1, 1 TB usable, XFS; one disk has 1,056 reallocated sectors but passed a long self-test |
| Firmware | AMI BIOS `R1.8.0` (2021-11-22) · board `D3460-D22` · legacy boot, no Secure Boot |
| Network | 1× GbE Intel I219-V (`enp0s31f6`) · hostname `nas` · static `192.168.2.202` ([ADR 31](decisions/31-static-address-scheme.md)) · LAN-only SSH/web UI |
| OS | OMV 8.5.9-1 (Debian 13) · kernel `6.12.107+deb13-amd64` · HTTPS-only web UI ([ADR 34](decisions/34-lan-tls-only.md)) |
| Cooling | 3 fans · 43.7 dB(A) · no software fan control · internal UPS battery not OS-exposed |
| Power | 14–16 W idle · AcBel 250 W 80 Plus Gold UPS-integrated PSU |
| Role | OMV NAS backup-target successor to the ML110 — [issue #98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98) |
| Docs | [idea 01c](ideas/01c-nas-backup-target-wincor-beetle.md) · [research 32](research/32-wincor-beetle-m3-hardware-diagnostic.md) · [runbook 32](runbooks/32-beetle-m3-omv-setup.md) · [issue #98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98) |

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

### Proxmox VE — Dell Wyse 5070

| Item | Spec |
|---|---|
| CPU | Intel Celeron J4105 (4C/4T, 2.5 GHz, 10 W TDP) · fanless, ~35 °C idle |
| RAM | 8 GB DDR4 (2× 4 GiB; both slots populated, 16 GB max with replacement) |
| Storage | M.2 SATA 2280 SK hynix SC311 128 GB SSD (SMART PASSED, ~97% life remaining) · unused 14.7 GiB eMMC |
| Firmware | BIOS 1.34.0 (2024-11-08) · board `060J9C` |
| Network | Realtek GbE (`enp1s0`) · Intel CNVi WiFi/BT (`wlp0s12f0`) |
| Zigbee | Sonoff ZBDongle-P (CC2652P) · USB coordinator for LXC 212 |
| OS | Proxmox VE 9.2.2 installed at `192.168.2.201` · base provisioned ([runbook 28](runbooks/28-pve-proxmox-node.md)) |
| Guests | VM 210 HA OS · LXC 211 Mosquitto · LXC 212 Zigbee2MQTT · LXC 213 NUT ([ADR 31](decisions/31-static-address-scheme.md)) |
| Role | Fleet virtualisation host with Netdata Parent; NUT delivered, HA OS/Mosquitto/Zigbee2MQTT pending (ADR 25, ADR 27, ADR 30) |
| Docs | [idea 05](ideas/05-home-assistant-thin-client.md) · [ADR 25](decisions/25-home-assistant-thin-client.md) · [ADR 33](decisions/33-fleet-node-hostnames.md) · [research 26](research/26-home-assistant-thin-client.md) · [research 29](research/29-wyse5070-hardware-diagnostic.md) · [runbook 28](runbooks/28-pve-proxmox-node.md) · [runbook 31](runbooks/31-deploy-netdata.md) |

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

## Power

### Shared-rail UPS — Green Cell UPSLM600

| Item | Spec |
|---|---|
| Model | Green Cell **UPSLM600** — line-interactive, AVR, **modified sine**, 1000 VA / 600 W |
| Battery | 2× 12 V 7 Ah (24 V, ~168 Wh) · no runtime estimate — end of discharge is the hardware `LB` flag |
| Outlets | 4 (2× Schuko + 2× IEC) over two strips — servers (`pve`, `lab`, `edge`, `nas`) and network appliances; monitors, dock and laptop charger stay on the wall |
| USB | `0665:5161` · HID page `0xFF00`, **no serial number** — driven by NUT `nutdrv_qx`, not `usbhid-ups` |
| Measured | **17 W** self-consumption at the socket · **55 min** to `LB` at the ~80 W fleet (drill 2026-09-19) |
| NUT | USB on the `pve` node; server in **LXC 213** (`.213`); `upsmon` on `pve` (primary) and `lab`/`edge`/`nas` (secondaries) |
| Docs | [ADR 30](decisions/30-ups-nut-graceful-shutdown.md) · [runbook 29](runbooks/29-nut-ups-shutdown.md) · [runbook 30](runbooks/30-deploy-nut-clients.md) · [drill report](reports/260919-nut-shutdown-drill.md) |

## Smart Home

One Zigbee mesh serves two consumers — the Home Assistant OS VM (VM 210) and the
HA-independent Zigbee2MQTT → Prometheus monitoring path — with the coordinator USB on the `pve`
node ([ADR 25](decisions/25-home-assistant-thin-client.md) · [ADR 26](decisions/26-zigbee-energy-monitoring.md)).

### Zigbee coordinator — Sonoff ZBDongle-P

| Item | Spec |
|---|---|
| Type | Zigbee 3.0 USB coordinator — Sonoff **ZBDongle-P**, Silicon Labs **CC2652P** (Z-Stack) |
| USB | Silicon Labs CP210x bridge `10c4:ea60` · by-id `usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_c8f3975dd19aef1197dbb89061ce3355-if00-port0` |
| Placement | USB on the `pve` node — the smart-home node sits centrally for Zigbee coverage; passthrough to **LXC 212** (Zigbee2MQTT) still to be wired ([#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85)) |
| Docs | [ADR 26](decisions/26-zigbee-energy-monitoring.md) · [research 27](research/27-zigbee-energy-monitoring.md) · [research 29](research/29-wyse5070-hardware-diagnostic.md) |

### Smart plugs — 4× Nous A1Z

| Item | Spec |
|---|---|
| Type | Zigbee 3.0 smart plug, 16 A / 3680 W — metering **W / A / V / kWh** |
| Mesh | mains-powered, act as **Zigbee routers** — extend coverage for battery sensors |
| Role | per-node energy monitoring ([#73](https://github.com/jaroslaw-bagnicki/Homelab/issues/73)) and Home Assistant sockets |
| Docs | [ADR 26](decisions/26-zigbee-energy-monitoring.md) · [research 27](research/27-zigbee-energy-monitoring.md) |

## Test & Measurement

Bench instruments behind the figures quoted in the node audits and in
[runbook 29](runbooks/29-nut-ups-shutdown.md).

| Instrument | Device | Used for |
|---|---|---|
| Power meter | **VIRONE EM-1/B** | inline plug meter — per-node idle/load draws and the UPS rail measurements ([runbook 29](runbooks/29-nut-ups-shutdown.md) · [research 32](research/32-wincor-beetle-m3-hardware-diagnostic.md)) |
| Sound level meter | **UNI-T UT353** | cooling noise in dB(A) — Beetle M-III 43.7 dB(A) ([research 32](research/32-wincor-beetle-m3-hardware-diagnostic.md)) |
| Multimeter | **Xtreme DT9205L** | bench voltage/continuity checks — PSU, cabling and board headers during node bring-up |
