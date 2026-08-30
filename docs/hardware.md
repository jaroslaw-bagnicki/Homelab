# Hardware Inventory

Per-node hardware detail for the homelab. For the high-level node/workload view see
[Overview](overview.md); for network design see [research 24](research/24-network-topology-design.md).

**Status legend**: ✅ running · 🔨 in progress · 📋 planned · 🧠 idea

## Summary

| Node | Base | Role | CPU | RAM | Storage | Network | Status |
|---|---|---|---|---|---|---|---|
| **Lab** | Lenovo ThinkCentre M910q Tiny | main workload host | i5-7500T (4C/4T) | 16 GB DDR4 | 256 GB NVMe (+ free 2.5" bay) | 1× GbE `enp0s31f6` | ✅ |
| **OMV NAS** | HP ProLiant ML110 G5 | backup target / NFS | Pentium E2160 (2C/2T) | 4 GB DDR2 | Goodram 120 GB SSD + RAID1 arrays | 1× GbE BCM5722 | ✅ |
| **Edge Ingress** | Dell Wyse 3040 | public ingress | Atom x5-Z8350 | 2 GB DDR3L | 8 GB eMMC | 1× GbE | 🔨 |
| **Home Assistant** | Dell Wyse 5070 | smart home node | J4105 (planned) | 8 GB DDR4 | M.2 SATA SSD 64–256 GB | 1× GbE | 📋 |
| **LLM server** | Minisforum AI X1 | local LLM inference | Ryzen 7 255 (Hawk Point) | 64–96 GB DDR5 | NVMe | 1× GbE | 🧠 (Phase 2) |
| **Cloudlab VPS** | Contabo Cloud VPS 10 | staging / playground | 4 vCPU | 8 GB | 75 GB NVMe | public IP | ✅ |

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
| CPU | Intel Pentium E2160 @ 1.8 GHz (2C/2T) |
| RAM | 4 GB (2× 2 GiB DDR2-800) |
| Boot | Goodram C40 120 GB SSD (ICH9 SATA #5, OMV 8.3) |
| Data | `md0` = 2× 500 GB Hitachi HDS721050CLA660 (RAID1 → XFS) · `md1` = 2× 250 GB (RAID1 → ext4) |
| Spare | 1 TB WD10EZEX — **offline** (role: offline, decided 2026-08-15) |
| Controllers | ICH9R 4-port + ICH9 2-port SATA; Dell SAS 6/iR **removed** (no hardware RAID) |
| Network | 1× GbE Broadcom BCM5722 (`enp14s0`), MAC `78:e7:d1:53:fb:87` |
| Management | None — no LO100/IPMI, direct console only; fan control not software-addressable |
| Docs | [runbook 22](runbooks/22-ml110-nas-inventory.md) · [runbook 23](runbooks/23-ml110-omv-setup.md) · [research 23](research/23-ml110-nas-omv.md) · [ADR 23](decisions/23-nas-on-ml110.md) |

### Edge Ingress — Dell Wyse 3040

| Item | Spec |
|---|---|
| CPU | Intel Atom x5-Z8350 |
| RAM | 2 GB DDR3L |
| Storage | 8 GB eMMC |
| Firmware | BIOS Dell 1.2.3 (2017-11-07) · SKU 07C1 · serial `8YW28L2` |
| Network | 1× GbE Realtek RTL8111/8168 (`enp1s0`, MAC `8c:ec:4b:6d:6f:4f`) |
| Cooling | Fanless · ~2–3 W idle |
| Role | Dedicated public ingress — bare-metal `cloudflared` + Caddy (ADR 24) |
| Docs | [runbook 24](runbooks/24-edge-appliance.md) · [ADR 24](decisions/24-edge-ingress-appliance.md) · [research 25](research/25-edge-ingress-sbc.md) · [idea 04](ideas/04-edge-device-tunnel-caddy.md) |

### Home Assistant — Dell Wyse 5070 (planned)

| Item | Spec |
|---|---|
| CPU | Intel Celeron J4105 (4C, fanless) |
| RAM | 8 GB DDR4 SO-DIMM (dual slot, 16 GB future) — Home Assistant VM gets 4 GB |
| Storage | M.2 **SATA** 2280 SSD 64–256 GB (128 GB practical pick; no NVMe) |
| Role | Home Assistant OS VM on Proxmox VE + Mosquitto/Zigbee2MQTT LXCs |
| Fallback | Fujitsu Futro S740 (same J4105, often cheaper, no PCIe/mPCIe) |
| Docs | [idea 05](ideas/05-home-assistant-thin-client.md) · [ADR 25](decisions/25-home-assistant-thin-client.md) · [research 26](research/26-home-assistant-thin-client.md) |

### LLM server — Minisforum AI X1 (Phase 2, 🧠 idea)

| Item | Spec |
|---|---|
| CPU | Ryzen 7 255 (Hawk Point / Zen 4, Radeon 780M 12 CU) |
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
