# 55 — 2.5 GbE homelab network with a 10G SFP+ core: switch, NIC and host selection

**Source**: [Gemini chat — "Homelab 2.5G net setup"](https://gemini.google.com/share/a9aa0c4028f3)
(thread created 2026‑11‑09, published 2026‑11‑11; conversation in Polish; 24 questions) · supplementary  
thread [share.gemini.google/F7UoGx8P36nX](https://share.gemini.google/F7UoGx8P36nX)  
(same conversation mirrored; the NAS aggregation-link and disk-matrix analysis below is folded in from it).

**Scope**: budget 2.5 GbE upgrade of the homelab LAN — unmanaged vs web-managed 2.5G switches, SFP+ vs
10GBASE-T uplinks, DAC vs fiber costs, used 10G SFP+ NIC evaluation, PCIe-bus fit in the Futro S930/S940,
2.5G M.2 NICs for the nodes, deployment cost calculation, and the NAS-side analysis: link aggregation to
the NAS and an SSD-vs-HDD disk-matrix performance comparison. Feeds [idea 18](../ideas/18-2-5g-homelab-network.md).

**Status**: 📝 Analysis — the operator selected the setup (Futro S940 + D2755-A11 + YuLinca + 2× EX.2268 DAC +
3× branded 10Gtek M.2 A+E for `pve1`/`pve2`/`lab` + a 10G SFP+ PCIe card for `nas`, ~990 PLN; corrected  
2026‑11‑11 to branded node NICs and a PCIe card for the NAS); nothing purchased or configured yet. No ADR.

> ⚠️ **Verification status**: hardware claims (prices, slot speeds, temperatures) are transcribed from the
> thread and marketplace listings; the PCIe negotiation numbers (S940 riser = PCIe 3.0 ×4, X520 negotiates
> PCIe 2.0 ×4 ≈ 16 Gbps) are thread calculations, to be confirmed with `lspci -vv` after install.

---

## §1 — Managed vs unmanaged 2.5G switches

Price gap is real: budget **unmanaged** 2.5G switches (GiGaPlus GP-S25-0802T, SODOLA, Hasivo, NICGIGA — all  
Realtek RTL8373 + RTL8224 OEM boards) cost ~129–250 PLN; **managed** 2.5G with 802.1Q costs 700–1200+ PLN  
from Ubiquiti/MikroTik/TP-Link Omada. The middle path is the Chinese **"Easy Web Managed"** class:

| Switch | Ports | Management | Price (2026‑11) | Verdict |
|---|---|---|---|---|
| GiGaPlus GP-S25-0802T / SODOLA 8×2.5G+2×10G SFP+ | 8× 2.5G + 2× 10G SFP+ | none (plug & play, jumbo frames 10 KB) | 129 PLN (outlet; new ~400 PLN) | best price/port, but **no VLANs** |
| SODOLA 8×2.5G + **1×** 10G SFP+ (outlet variant) | 8× 2.5G + 1× SFP+ | none | 129 PLN | single 10G port becomes the topology bottleneck |
| XikeStor SKS1200-8GPY2XF / Hasivo / MokerLink managed | 8× 2.5G + 2× 10G SFP+ | Web GUI: 802.1Q, LACP, IGMP | 350–450 PLN (AliExpress) | true VLANs, 2× 10G |
| MikroTik CRS310-8G+2S+IN | 8× 2.5G + 2× 10G SFP+ | RouterOS/SwitchOS, HW offload | 850–950 PLN | enterprise, overkill here |
| **YuLinca 8× 2.5G + 1× 10G SFP+ Easy Web Managed** | 8× 2.5G + 1× SFP+ | Web GUI (default `192.168.2.1`, admin/admin): **802.1Q VLAN, LACP, QoS, IGMP snooping, STP**; backplane 60 Gbps; fanless metal ~160×90×35 mm; 12 V 1 A PSU | **199 PLN** | **selected** — real VLANs under 200 PLN |

Hybrid architecture that works with an unmanaged 2.5G switch anyway: keep a cheap 1G managed switch  
(TL‑SG108E, already owned — [research 24](24-network-topology-design.md)) for IoT/mgmt VLANs and hang the  
unmanaged 2.5G switch off a router **access port** of one dedicated storage VLAN; unmanaged Realtek switches  
pass 802.1Q tags transparently, so host-side tagging on Proxmox/OPNsense also works. The YuLinca makes this  
moot by doing the tagging itself.

## §2 — SFP+ 10G vs RJ45 10GBASE-T uplink

| Criterion | SFP+ 10G | RJ45 10GBASE-T |
|---|---|---|
| Power per port | ~0.5–1.5 W | 2.5–5 W+ |
| Heat | negligible | modules/NICs reach 60–80 °C — can overheat a fanless switch |
| Latency | ~0.1 µs | ~1.5–2.5 µs (DSP/FEC) |
| Used NIC market | cheap enterprise SFP+ cards (Mellanox, Intel) ~90–150 PLN | expensive, poor second-hand selection |
| Media | DAC (1–5 m), AOC, fiber LC (up to km) | Cat6 ≤30 m / Cat6A ≤100 m only |

**Verdict**: always SFP+ in a homelab when there is a choice. In the same 10″ rack use a **passive DAC**;
between rooms use SFP+ LR/SR modules + fiber. Only use an SFP+→RJ45 transceiver when a device truly has just  
a 10G RJ45 port, and minimize their number (heat).

## §3 — DAC vs fiber costs (router ↔ switch)

| Medium | BOM | Total |
|---|---|---|
| **DAC 10G, 1–1.5 m (same rack)** — e.g. **Extralink EX.2268 1 m, 30 PLN** | one cable | **~30–60 PLN** |
| DAC 3–5 m | one cable | ~70–100 PLN |
| Multi-mode fiber (OM3/OM4, ≤300 m) | 2× SFP+ SR modules (~90–120 PLN new, 30–40 used) + LC-LC OM3 patchcord 2–5 m (~20–35 PLN) | ~110–155 PLN |
| Single-mode (OS2, ≤10 km) | 2× SFP+ LR modules (~110–160 PLN) + LC-LC OS2 patchcord (~20–40 PLN) | ~130–200 PLN |

DAC wins for a 10″ rack: passive (0 W, no heat), plug & play, cheapest. Watch the bend radius at the SFP+  
plugs — DACs are stiff. Outlet PSU caveat on cheap switches: the bundled 12 V 1–1.5 A adapter can cause  
random reboots under load; replace with a branded 12 V ≥2 A if that happens.

## §4 — 10G SFP+ NIC evaluation (used market)

| Card | Chip / bus | Power | OPNsense (FreeBSD) | Verdict |
|---|---|---|---|---|
| **Fujitsu D2755-A11 (= Intel X520-DA2)** | Intel 82599ES, PCIe 2.0 ×8, 2× SFP+, 167 mm LP/FH | ~5–7 W with DAC | `ixgbe` in-kernel, plug & play | **selected, 125 PLN** — industry standard, DAC-compatible, normal bracket |
| Huawei CN21ITGAA13 | same Intel 82599, PCIe 2.0 ×8 | ~5 W | `ixgbe` | equal alternative under ~100–120 PLN |
| Mellanox ConnectX-3 MCX311A/MCX312A | PCIe 3.0 ×8 | ~3–4 W | `mlx4_en` | best cold/cheap alternative ~90–130 PLN |
| Intel X710-DA2 | PCIe 3.0 ×8 | ~3.6 W | `ixl` | ideal but 200–300 PLN |
| Emulex/Dell LPE12002 | **8 Gb Fibre Channel HBA** | — | n/a | **reject** — not Ethernet, no IP, FC SFP+ modules, DAC won't work |
| Silicom PE210G2SPI9A-XR | Intel 82599 but **bypass NIC**, proprietary bracket, full-length | ~5 W | `ixgbe` | **reject** — bracket/fit problems in a 10″ rack |
| Dell Chelsio T540-BT | Chelsio T5, PCIe 3.0 ×8, **4× 10GBASE-T RJ45** | **19–25 W+** | `cxgbe` | **reject** for a fanless Futro — furnace, kills the 40/65 W PSU, DAC useless |
| Brocade 1020 (80-1003249) | CNA, PCIe 2.0 ×8 | ~10–12 W | **no driver** (`bfa`/`bna` dropped from FreeBSD) | **reject** — invisible to OPNsense |

PCIe Gen3 NICs exist (X710, ConnectX-4 Lx, BCM57412/57414, Aquantia AQC107) and would negotiate native  
PCIe 3.0 ×4 in the S940 (~3.9 GB/s — both 10G ports full-duplex), but cost 2–3× more; the X520 at PCIe 2.0 ×4  
(~2.0 GB/s ≈ 16 Gbps) already saturates one 10G port with headroom for the second in real traffic.

## §5 — Host fit: Futro S930 vs Futro S940

| | Futro S930 (current router) | Futro S940 (selected replacement) |
|---|---|---|
| PCIe slot | **Gen1 ×1 ≈ 250 MB/s (~2 Gbps)** — a 10G card here would be *slower than 2.5 GbE* | riser exposes **PCIe 3.0 ×4** (~3.94 GB/s); X520 negotiates PCIe 2.0 ×4 ≈ 16 Gbps |
| CPU | GX-424CC — weak for 10G stateful filtering | J4105/N4200 class — handles 10G routing + IDS/IPS much better |
| Fit | card physically needs open-ended riser | D2755 (167 mm) fits on the riser after removing the rear mounting basket; **needs the Fujitsu riser included** (~20–40 PLN if not) |

Using **both** 10G ports on the S940: theoretical full-duplex on both = 40 Gbps > 16 Gbps bus cap, so a  
synthetic iperf on both ports simultaneously caps at ~16 Gbps; real router traffic (one port = 10G trunk to  
the switch) never hits that. A small 40 mm fan (Noctua NF-A4x10/20 or cheap 12 V) over the X520 heatsink is
**mandatory** in the passively cooled S940 (80–90 °C without airflow).

## §6 — 2.5G NICs for the four nodes

| Chipset | Bus | Power | Linux/Proxmox | FreeBSD/OPNsense |
|---|---|---|---|---|
| **Realtek RTL8125B** (M.2 A+E or M key, PCIe x1; also 2-port PCIe cards ~90–140 PLN) | PCIe 2.0/3.0 x1–x2 | ~1.5–2.5 W, cold | `r8169` in-kernel ≥5.4; `realtek-r8125-dkms` for heavy loads (`apt install pve-headers realtek-r8125-dkms`) | needs `os-realtek-re` plugin (in-kernel driver unstable under load) |
| Intel i225-V rev3 / i226-V (2-port RJ45 ~130–180 PLN) | PCIe 3.0 x1/x2 | ~2–3 W | `igc` native | `igc` native — zero fuss |

M.2 keying: **A+E** goes into the Wi-Fi slot (M.2 2230) and keeps the NVMe M-key slot free for the boot SSD;
**M key** goes into a free NVMe slot. Cards are a small M.2 module + RJ45 jack on a 15–20 cm flex ribbon with
LP/FH brackets. **Selected (operator correction, 2026‑11‑11): 3× branded  
[10Gtek M.2 A+E Key 2.5G RJ45](https://store.10gtek.com/m-2-a-e-key-2-5g-rj-45-nic-realtek-rtl8125-controller/p-22194)  
(RTL8125, $18.00 list / $16.20 at qty 50 on store.10gtek.com) for `pve1`, `pve2`, `lab` — the 27 PLN no-name  
modules from the thread are rejected in favour of the branded card (PCB/signal integrity at 2.5G); `nas`  
gets a regular PCIe card (§7.1), not an M.2 adapter.

Per-node notes (from `docs/hardware.md`):

- `lab` (M910q): free **2.5″ SATA bay**, M.2 occupied by NVMe boot → needs a free M.2 Wi-Fi slot or a PCIe
  2-port card; verify.
- `pve2` (OptiPlex 7050 MFF): M.2 SATA occupied, free 2.5″ bay; WiFi M.2 slot present (8265) — check if
  replaceable with A+E NIC or use a PCIe slot (MFF riser).
- `pve1` (Wyse 5070): M.2 SATA boot occupied, CNVi WiFi on M.2 — the A+E NIC may replace the WiFi module;
  otherwise its PCIe slot.
- `nas` (Beetle M-III): 1× I219-V GbE + **free PCIe 3.0 ×16** — gets a **regular 10G SFP+ PCIe card**
  (D2755-A11 or ConnectX-3 class, ~90–130 PLN), not an M.2 adapter: it puts the NAS directly on the 10G
  core via the router's second SFP+ port, no switch port needed.

## §7 — NAS: link aggregation and the disk matrix (SSD vs HDD)

### §7.1 Aggregating the link to the NAS

The YuLinca's single SFP+ port goes to the router as the VLAN trunk, and the router's **second** SFP+ port  
(D2755 is dual-port) goes straight to the NAS with a second DAC — so the selected design is:

1. **Direct 10G SFP+ PCIe NIC in the Beetle's PCIe 3.0 ×16 slot** (D2755-A11 or ConnectX-3 class,
   ~90–130 PLN) — **chosen**: frees a switch port, no bonding needed, full 10G to the router.
2. Fallback: **LACP on the switch** — 2× 2.5G RJ45 ports to the NAS aggregate to **5 Gbps**, but the
   Beetle has only one onboard GbE (I219-V), so this needs a second 2.5G NIC plus bonding (802.3ad) in OMV;
   the YuLinca's Easy Web UI does support LACP.

Either way the NAS link is no longer the 1 GbE bottleneck; what remains is the disk matrix.

### §7.2 Disk matrix: what actually delivers the bandwidth

The Beetle today: SanDisk X600 128 GB SSD (OS/cache) + **2× Seagate ST1000VT001 1 TB 2.5″ HDD in mdadm  
RAID1** over XFS, 5× SATA AHCI ports (3 occupied, mSATA + M.2 SATA free), PCIe 3.0 ×16 + 2× 2.0 ×1 free  
([research 32](32-wincor-beetle-m3-hardware-diagnostic.md)). Sequential numbers that decide what a 2.5G  
(≈280–300 MB/s) or 5G/10G link can actually carry:

| Matrix | Seq. read | Seq. write | 2.5G link (300 MB/s) | 5G LACP | 10G |
|---|---|---|---|---|---|
| 1× HDD 3.5″/2.5″ | 150–220 MB/s | ~150–200 MB/s | **bottleneck — link underused** | bottleneck | bottleneck |
| RAID1 2× HDD (mdadm, current) | ~2× single disk ≈ 300–440 MB/s | ~150–200 MB/s (mirror write) | write-capped ~200 MB/s; read can saturate | read OK, write capped | write-capped |
| RAID10 4× HDD | ~2× single ≈ 300–440 MB/s | ~2× single ≈ 300–400 MB/s | near-saturated | OK | capped by disks |
| RAIDZ2 5–6× HDD | (n−2)× single | lower | OK-ish | OK | capped |
| 1× SATA SSD | ~550 MB/s | ~500 MB/s | **saturates 2.5G** | bottleneck | bottleneck |
| NVMe (if slot were NVMe — it is SATA-only) | 2–3.5 GB/s | 1.5–3 GB/s | saturates | saturates | ~saturates at 10G |
| SSD tier/cache + HDD bulk (e.g. SSD as L2ARC/read cache or bcache) | reads ~SSD speed for hot data | HDD-bound for cold | hot data saturates 2.5G | — | — |

Conclusions:

- **The current RAID1 of 2× 1 TB HDDs already saturates or nearly saturates a 2.5G link on reads**; on writes
  it caps at ~200 MB/s. So 2.5G alone is *not* wasted — but **10G to the NAS is pointless until the matrix
  changes**.
- **SSD vs HDD matrix**: an all-SSD matrix (SATA SSDs on the 2 free mSATA/M.2 ports + spares) lifts the NAS
  to ~500–550 MB/s per link — full 2.5G, and with LACP 2×2.5G ≈ 5 Gbps aggregate ≈ one SSD-class stream;
  10G needs NVMe-class storage, which this board cannot host (M.2 is SATA-only per research 32).
- Practical sweet spot for this box: **keep RAID1 HDDs for bulk/cold data, add the free mSATA + M.2 SATA
  SSDs as a fast tier** (bcache/L2ARC-style or a separate SSD mirror for hot data: VM disks, Longhorn
  snapshots) — hot reads then saturate 2.5G, cold bulk stays HDD-bound but that is the right trade for a
  backup target.
- Jumbo frames (MTU 9000) end-to-end (PVE, NAS, switch) shave a few % of CPU and can push 2.5G transfers from
  ~285 to ~300–305 MB/s; MTU 1500 is fine by default. NFS/iSCSI give the most stable 285–295 MB/s; SMB is
  ~260–280 MB/s unless `smb multichannel` is enabled (which is also where LACP/bonding pays off).

## §8 — Expected transfers in this fleet (2× PVE + K3s `lab` + NAS over 2.5G)

- 2.5GBASE-T line rate 2.5 Gbps = 312.5 MB/s; **real TCP ~280–300 MB/s** (vs 110–115 MB/s on 1 GbE — a
  2.5× jump). 10G is disk-bound at ~1150 MB/s ceiling.
- PBS/restic backups of a 50 GB VM: ~2.5–3 min on 2.5G vs ~8 min on 1 GbE.
- Live migration `pve1` ↔ `pve2` (16 GB RAM VM): seconds, no freeze — versus minutes/throttled on 1 GbE.
- NFS/iSCSI VM disks and K3s PVCs from the NAS: ~280–300 MB/s — smooth for databases/containers, provided
  the disk matrix (§7) keeps up.
- Bottlenecks to watch: single HDD (~150–220 MB/s), SMB without multichannel (~260–280 MB/s), CPU on the
  router for 10G stateful filtering + IDS/IPS.

## §9 — Deployment cost (2026‑11‑11 prices, from the thread)

| Element | Qty | Unit | Total |
|---|---|---|---|
| Fujitsu Futro S940 (J5005, 4 GB DDR4, 32 GB M.2 SATA SSD, PSU) — replaces the S930 router | 1 | 219 PLN | 219 PLN |
| YuLinca 8× 2.5G + 1× 10G SFP+ Easy Web Managed switch | 1 | 199 PLN | 199 PLN |
| Fujitsu D2755-A11 (2× 10G SFP+) for the S940 router | 1 | 125 PLN | 125 PLN |
| Extralink EX.2268 DAC SFP+ 1 m (router ↔ switch trunk, router ↔ NAS) | 2 | 30 PLN | 60 PLN |
| [10Gtek M.2 A+E Key 2.5G RJ45](https://store.10gtek.com/m-2-a-e-key-2-5g-rj-45-nic-realtek-rtl8125-controller/p-22194) (`pve1`, `pve2`, `lab`) | 3 | ~$18 ≈ 75 PLN | ~225 PLN |
| 10G SFP+ PCIe card for `nas` (D2755-A11 or ConnectX-3 class) | 1 | ~110 PLN | ~110 PLN |
| 10Gtek store shipping | 1 | ~40 PLN (est.) | ~40 PLN |
| **Total** | | | **~960 PLN** |

Thread variants for the record: 651 PLN (YuLinca at 243 PLN + 4× 54 PLN no-name M.2 cards); 537 PLN with the  
129 PLN outlet SODOLA unmanaged switch; 873–913 PLN with 10Gtek cards + 4th no-name card. **Operator  
correction 2026‑11‑11**: branded 10Gtek NICs only (no no-name 27 PLN modules), 3× M.2 for the PVE/lab nodes,  
NAS on a regular PCIe 10G card, second DAC router ↔ NAS. Side costs: 40 mm fan for the X520 in the S940  
(~10–40 PLN), Fujitsu PCIe riser if the S940 listing lacks it (~20–40 PLN), possibly a 12 V ≥2 A PSU for the  
switch.

## §10 — Open questions

- Per-node M.2 A+E keying check (§6) before ordering the 3× 10Gtek cards — A+E for Wi-Fi slots, M for free
  NVMe slots.
- NAS NIC choice: second D2755-A11 (~125 PLN) vs ConnectX-3 (~90–130 PLN) in the Beetle's PCIe ×16; LACP
  2× 2.5G is the fallback (needs a second NIC + bonding in OMV).
- OPNsense migration S930 → S940: export `config.xml`, restore on the new box, re-map interfaces (`ix0`/`ix1`).
- RTL8125B on OPNsense needs the `os-realtek-re` plugin; on Proxmox install `realtek-r8125-dkms` for heavy
  sustained loads.
- Whether to keep the S930 as a cold spare router (like the ML110 NAS standby) — its Gen1 ×1 slot limits it
  to 1G-class routing only.
