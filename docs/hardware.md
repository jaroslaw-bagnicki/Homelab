# Hardware Inventory

Per-node hardware detail for the homelab. For the high-level node/workload view see
[Overview](overview.md); for network design see [research 24](research/24-network-topology-design.md).

## Summary

| Node | Role | Device | CPU | RAM | Storage | Network |
|---|---|---|---|---|---|---|
| **Lab** | main workload host | Lenovo ThinkCentre M910q Tiny | i5-7500T (4C/4T, 35 W) | 16 GB DDR4 | 256 GB NVMe (+ free 2.5" bay) | 1× GbE `enp0s31f6` |
| **OMV NAS** | OpenMediaVault **emergency NAS** — powered off, retained as the fallback | HP ProLiant ML110 G5 | Pentium E2160 (2C/2T, 65 W) | 4 GB DDR2 | Goodram 120 GB SSD + RAID1 arrays | 1× GbE BCM5722 |
| **Beetle NAS** | OMV NAS backup target (successor to ML110) | Wincor Beetle M-III | Pentium G4400 (2C/2T, 3.3 GHz) | 8 GB DDR4 (1×, 1 free slot) | SanDisk 128 GB SSD + 2× Seagate 1 TB 2.5" | 1× GbE Intel I219-V |
| **Edge Ingress** | LAN DNS + reverse proxy (public ingress held) | Dell Wyse 3040 | Atom x5-Z8350 (2 W TDP) | 2 GB DDR3L | 8 GB eMMC | 1× GbE |
| **Proxmox VE** | virtualisation host — smart-home + always-on services | Dell Wyse 5070 | Celeron J4105 (Gemini Lake, 10 W) | 8 GB DDR4-2400 (2× 4 GB) | M.2 SATA SK hynix 128 GB | 1× GbE + WiFi |
| **Proxmox VE (second node)** | second virtualisation host — `homelab` cluster member | Dell OptiPlex 7050 MFF | i5-7500 (4C/4T, 65 W) | 8 GB DDR4-2400 (1× 8 GiB, 1 slot free) | M.2 SATA SK hynix 128 GB (+ free 2.5″ bay) | 1× GbE Intel I219-LM |
| **OPNsense Router** | LAN edge router / firewall | Fujitsu Futro S930 | GX-424CC (4C/4T, 25 W TDP) | 4 GB DDR3 (1×, 1 free slot) | Innodisk 7.99 GB mSATA | 3× GbE (BCM5720 2× + Realtek 1×) |
| **Cloudlab VPS** | staging / playground | Contabo Cloud VPS 10 | 4 vCPU (cloud — no TDP) | 8 GB | 75 GB NVMe | public IP |

## Compute & Storage Nodes

### Lab — Lenovo ThinkCentre M910q Tiny

| Item | Spec |
|---|---|
| CPU | Intel Core i5-7500T (4C/4T, 35 W TDP, QuickSync) |
| RAM | 16 GB DDR4 (1× 16 GiB SODIMM in ChannelB-DIMM0 @ 2400 MT/s; ChannelA-DIMM0 empty — 2 slots, upgradeable to 32 GB) |
| Storage | 256 GB NVMe — SK hynix BC501 HFM256GDJTNG-8310A · serial `FS85N582310805D30` · FW `80000C00` · SMART **PASSED** (1% used, 16,355 POH — §0 audit 2026-08-16); free 2.5" SATA bay for a secondary/backup disk |
| Firmware | BIOS LENOVO M1AKT2CA (2017-11-22) · board 310B |
| Network | 1× Gigabit Ethernet Intel I219-LM (`enp0s31f6`, MAC `6c:4b:90:40:c5:e2`) |
| Noise | **36.1 dB @ 0.3 m · 36.4 dB @ 0.2 m** (sound-level meter, idle, 2026-11-06) |
| Role | Main workload host |
| Docs | [ADR 01](decisions/01-hardware-selection-m910q.md) · [runbook 25](runbooks/25-m910q-os-refresh.md) |

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
| Storage | SanDisk X600 128 GB SSD (OS) + 2× Seagate 1 TB 2.5" → `md0` RAID1, 1 TB usable, XFS · members `WDES3KB7` + `WL10C3NG` (`WDEPBVR3` 🪦 failed 2026-10-11) |
| Firmware | AMI BIOS `R1.8.0` (2021-11-22) · board `D3460-D22` · legacy boot, no Secure Boot |
| Network | 1× GbE Intel I219-V (`enp0s31f6`) · hostname `nas` · static `192.168.2.209` ([ADR 31](decisions/31-static-address-scheme.md)) · LAN-only SSH/web UI |
| OS | OMV 8.5.9-1 (Debian 13) · kernel `6.12.107+deb13-amd64` · HTTPS-only web UI ([ADR 34](decisions/34-lan-tls-only.md)) |
| Cooling | 3 fans · 43.7 dB(A) · no software fan control · internal UPS battery not OS-exposed |
| Power | 14–16 W idle · AcBel 250 W 80 Plus Gold UPS-integrated PSU |
| Role | NAS — backup target |
| Docs | [idea 01c](ideas/01c-nas-backup-target-wincor-beetle.md) · [research 32](research/32-wincor-beetle-m3-hardware-diagnostic.md) · [runbook 32](runbooks/32-beetle-m3-omv-setup.md) |

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
| Role | LAN DNS + reverse proxy (Technitium DNS + Caddy); **Corosync QDevice arbitrator** (`corosync-qnetd`, TCP 5403) for the `homelab` cluster; public ingress held |
| Docs | [runbook 24](runbooks/24-edge-appliance.md) · [runbook 37](runbooks/37-deploy-internal-access-stack.md) · [runbook 43](runbooks/43-proxmox-cluster-qdevice.md) · [ADR 24](decisions/24-edge-ingress-appliance.md) · [ADR 40](decisions/40-internal-dns-proxy-edge.md) · [ADR 47](decisions/47-second-proxmox-node-cluster-qdevice.md) · [research 25](research/25-edge-ingress-sbc.md) |

### pve1 — Dell Wyse 5070

| Item | Spec |
|---|---|
| CPU | Intel **Celeron J4105** (**Gemini Lake** / Goldmont Plus, 4C/4T, **1.5 GHz base / 2.5 GHz burst**, 4 MB cache, 10 W TDP, **x86-64-v2**) · AES-NI ✅ · fanless, ~35 °C idle (800 MHz, downclocked) · iGPU UHD Graphics 600 |
| RAM | 8 GB DDR4 — 2× 4 GiB Micron `4ATF51264HZ-3G2J1` rated **DDR4-3200 (PC4-25600)** but **running at 2400 MT/s**, the Gemini Lake IMC ceiling · both slots populated, so 16 GB means a full 2× 8 GiB swap |
| Storage | M.2 SATA 2280 SK hynix **SC311 128 GB** (SN `MS8BN03201230BC10`, FW `70000P10`) · SMART **PASSED**, ~97 % endurance remaining · **no NVMe controller** on Gemini Lake — M.2 **SATA / B+M key only** · unused 14.7 GiB eMMC |
| Firmware | BIOS **1.34.0** (2024-11-08) · board `060J9C` · serial `16474B3` · SKU `080C` |
| Network | Realtek RTL8111/8168 GbE (`enp1s0`, MAC `c0:25:a5:65:02:67`) · Intel CNVi WiFi + BT (`wlp0s12f0`, MAC `d0:3c:1f:cb:76:9a`) |
| Virtualisation | VT-x ✅ **in use** (VM 210 + LXCs 211/212/214/215, `kvm_intel` loaded) · **VT-d supported** by the J4105 ([Intel ARK](https://www.intel.com/content/www/us/en/products/sku/128989/intel-celeron-j4105-processor-4m-cache-up-to-2-50-ghz/specifications.html)) — but **IOMMU/DMAR not yet confirmed on this board**, so PCIe passthrough is unproven; neither the TPM nor the Zigbee USB passthrough needs it |
| TPM | **Intel PTT** firmware TPM 2.0 — `/dev/tpm0`, `/dev/tpmrm0` (measured 2026-10-04, [research 37 §5](research/37-tpm2-hardware-and-fleet.md)) · passed into LXC 215, which seals the CA's intermediate key to it |
| Zigbee | Sonoff ZBDongle-P (CC2652P) · USB coordinator for LXC 212 |
| OS | Proxmox VE **9.2.26** installed at `192.168.2.201` · base provisioned ([runbook 28](runbooks/28-pve1-proxmox-node.md)) |
| Role | Fleet virtualisation host (Proxmox VE) · hosts LXC 214 `vtstack` (VictoriaLogs) and LXC 215 `ca`, the fleet trust anchor ([ADR 38](decisions/38-private-ca-hierarchy-and-custody.md)) |
| Docs | [idea 05](ideas/05-home-assistant-thin-client.md) · [ADR 25](decisions/25-home-assistant-thin-client.md) · [research 26](research/26-home-assistant-thin-client.md) · [research 29](research/29-wyse5070-hardware-diagnostic.md) · [runbook 28](runbooks/28-pve1-proxmox-node.md) |

### pve2 — Dell OptiPlex 7050 MFF

| Item | Spec |
|---|---|
| OS | **Proxmox VE 9.2.26** (Debian 13 trixie, kernel `7.0.14-28-pve`) — matches `pve1` |
| CPU | Intel **Core i5-7500** (Kaby Lake, 4C/4T, 3.4/3.8 GHz, **65 W TDP**) — not a factory Micro SKU (Dell's Micro list is 35 W T-series only); an i7-7700T swap is the fallback |
| RAM | 8 GB DDR4-2400 (1× 8 GiB SO-DIMM, **DIMM 2 free**) — 16 GB is one stick, 32 GB with 2× 16 GiB |
| Storage | **M.2 2280 SATA** module — SK hynix **SC311 SATA 128 GB**, SATA III via AHCI · 11 134 POH, **~97 % endurance remaining** (worst block only 86 erase cycles) — healthy but small; a larger NVMe is optional ([research 52](research/52-optiplex7050-hardware-diagnostic.md)) · 2.5″ bay empty · `local` 40 GB + `local-lvm` 57 GB thin pool on VG `pve` |
| Firmware | BIOS Dell 1.27.0 — Dell's current release (published 2023-11-15), not on DSA-2025-153, so nothing to flash · board `055H3G` · serial `3CLD6Q2` · asset tag `80006161` |
| Network | Intel **I219-LM** GbE (`enp0s31f6`, MAC `d8:9e:f3:97:3e:d1`) · Intel 8265 WiFi/BT · **`.202`** ([ADR 31](decisions/31-static-address-scheme.md)) |
| TPM | **TPM 2.0, enabled** (TPM On, SHA-256, attestation + key storage) — PTT vs discrete pending |
| Power | **130 W** adapter (documented options: 65 W ↔ 35 W CPU, 130 W ↔ 65 W CPU) · BIOS logged `Unknown AC power adapter` before the purchase, none on the current boot · **23.2 W in BIOS Setup, 19.7 W at PXE** — pre-OS, OS idle still to measure |
| Cooling | Fan **2278 RPM idle / 2908 RPM high** (ePSA) · CPU thermistor 36 °C, HDD 37 °C · audible at idle, **loud under sustained load** |
| Noise | **37.3 dB @ 0.3 m · 38.2 dB @ 0.2 m** idle, **~59 dB at full fan speed** (ePSA fan test) — 1–2 dB above the M910q at idle; the ceiling is what matters |
| Management | ⚠️ **AMT/vPro unreachable — treat as absent**: the platform qualifies (i5-7500 + Q270 + I219-LM, `USB Provision` present) and every BIOS gate for MEBx is satisfied (`OROM Keyboard Access` on, `MEBx Hotkey` on, admin password set), yet CTRL+P and F12 show nothing; CSME **11.8.94.4494** is alive, so the open question is whether that image is an AMT build (`mei-amt-version` still to run). Remote power therefore rests on **AC Recovery `Power On` + Wake-on-LAN `LAN Only`** — no remote console |
| Virtualisation | VT-x ✅ · **VT-d ✅** · TXT off — firmware ready for Proxmox |
| Wireless | Intel 8265 WLAN + Bluetooth, **both disabled in BIOS** — unused on a hypervisor |
| Role | Second virtualisation host — `homelab` cluster member with `pve1`, QDevice on `edge`; guest block `25x` (`.250`–`.254`); ZFS replication/HA later ([ADR 47](decisions/47-second-proxmox-node-cluster-qdevice.md)) |
| Docs | [idea 15](ideas/15-second-proxmox-node.md) · [research 47](research/47-second-proxmox-node.md) · [research 52](research/52-optiplex7050-hardware-diagnostic.md) · [runbook 42](runbooks/42-pve2-proxmox-node.md) · [runbook 43](runbooks/43-proxmox-cluster-qdevice.md) · [ADR 47](decisions/47-second-proxmox-node-cluster-qdevice.md) · [#177](https://github.com/jaroslaw-bagnicki/Homelab/issues/177) |

### OPNsense Router — Fujitsu Futro S930 (planned)

| Item | Spec |
|---|---|
| CPU | AMD **GX-424CC** (Jaguar-family, 4C/4T, 2.4 GHz, 2 MB L2, 25 W TDP) — AES-NI present, no SHA-NI |
| RAM | **4 GB DDR3-1600** (1× 4 GiB SK hynix `HMT451S6BFR8A-PB` @ 1600 MT/s) — 2 SODIMM slots, **DIMM 2 free** → 8 GB is a one-stick upgrade |
| Storage | **Innodisk DEMSR-08GB mSATA 3ME3 — 7.99 GB** (`sda`, SN `20171003AAAA159004FC`) · SMART **PASSED** (5,066 POH, 0 errors); **tight** for OPNsense — 32–128 GB mSATA swap recommended |
| Network | **Broadcom NetXtreme BCM5720 2× 1 GbE** (FreeBSD `bge`) in the PCIe slot = WAN + LAN · onboard **Realtek RTL8111/8168** (`re`) = MGMT/OPT · **slot trains Gen1 ×1** (no BIOS option — platform limit) |
| Firmware | BIOS AMI **R1.14.0** (2017-09-21) · board `D3313-E1` · SN `YMFH014511` |
| Cooling | Fanless · ~59 °C idle · ~8–15 W idle (Jaguar 25 W) |
| Role | LAN edge router (OPNsense) |
| Acquisition | 2026-09-02 — hardware diagnostic complete ([research 31](research/31-futro-s930-hardware-diagnostic.md)); OPNsense install pending |
| Docs | [idea 07](ideas/07-opnsense-futro-s930.md) · [research 31](research/31-futro-s930-hardware-diagnostic.md) |

### Cloudlab VPS — Contabo Cloud VPS 10

| Item | Spec |
|---|---|
| Compute | 4 vCPU, 8 GB RAM |
| Storage | 75 GB NVMe |
| OS | Ubuntu 24.04 LTS (pre-installed by Contabo) |
| Role | Staging / playground VPS |
| Docs | [runbook 10](runbooks/10-vps-playground.md) · [ADR 13](decisions/13-cloudlab-staging.md) |

## Network Appliances

### TP-Link TL-SG108E switch

| Item | Spec |
|---|---|
| Ports | 8× Gigabit Ethernet (L2, utility-managed) |
| Hardware | Rev V1 — web UI non-functional (HTTP 501), managed via **Easy Smart Configuration Utility** (Windows) |
| IP | `192.168.2.230` (static) |
| Role | Access switch — turns the single office drop into wired ports for Lab, `pve1`, `pve2`, Beetle NAS, Edge Ingress and the work dock |
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
| Outlets | 4 (2× Schuko + 2× IEC) over two strips — servers (`pve1`, `pve2`, `lab`, `edge`, `nas`) and network appliances; monitors, dock and laptop charger stay on the wall |
| USB | `0665:5161` · HID page `0xFF00`, **no serial number** — driven by NUT `nutdrv_qx`, not `usbhid-ups` |
| Measured | **17 W** self-consumption · **~55 min** to `LB` at the ~80 W fleet (inline meter, drill 2026-09-19); NUT reports no power — `ups.load` % only |
| NUT | USB on the `pve1` node, which runs the server **host-native** (`.201`); `upsmon` on `pve1` (primary) and `pve2`/`lab`/`edge`/`nas` (secondaries) |
| Docs | [ADR 39](decisions/39-nut-host-native.md) · [runbook 29](runbooks/29-nut-ups-shutdown.md) · [runbook 30](runbooks/30-deploy-nut-clients.md) · [drill report](reports/260919-nut-shutdown-drill.md) |

## Smart Home

One Zigbee mesh serves two consumers — the Home Assistant OS VM (VM 210) and the
HA-independent Zigbee2MQTT → Prometheus monitoring path — with the coordinator USB on the `pve1`
node ([ADR 25](decisions/25-home-assistant-thin-client.md) · [ADR 26](decisions/26-zigbee-energy-monitoring.md)).

### Zigbee coordinator — Sonoff ZBDongle-P

| Item | Spec |
|---|---|
| Type | Zigbee 3.0 USB coordinator — Sonoff **ZBDongle-P**, Silicon Labs **CC2652P** (Z-Stack) |
| USB | Silicon Labs CP210x bridge `10c4:ea60` · by-id `usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_c8f3975dd19aef1197dbb89061ce3355-if00-port0` |
| Placement | USB on the `pve1` node — the smart-home node sits centrally for Zigbee coverage; passthrough to **LXC 212** (Zigbee2MQTT) still to be wired ([#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85)) |
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
