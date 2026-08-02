# Idea 01 — Homelab NAS

**Status**: 🧠 Idea
**Date**: 2026-08-02
**Sources**:
- [Gemini thread 1](https://share.gemini.google/IT4sMLWoypH6) — hardware selection, Unraid vs OMV, disk/RAM config
- [Gemini thread 2](https://share.gemini.google/9EUcOTYIaaDo) — USFF/SFF form factor exploration, port counts, alternatives

## Topic

Build a small, quiet, energy-efficient NAS for Homelab backups (~256 GB target), using repurposed enterprise mini-PC hardware and free/open-source software.

## Final Hardware Shape

| Component | Selection |
|---|---|
| **PC** | Fujitsu Esprimo Q956 (USFF, ~1.9L, Intel Core i5-6500T, 4C/4T) |
| **RAM** | 2× 4 GB DDR3L PC3L-12800S 1600MHz SODIMM (8 GB total, dual-channel) |
| **Disks** | 2× WD Black WD5000LPLX 500 GB 2.5" HDD (7200 RPM, CMR, 7mm slim) |
| **Cache (deferred)** | SK Hynix BC501 256GB M.2 NVMe (2230) — optional, add later |

## Cost Estimation

Prices sourced from Allegro.pl (August 2026). Conversion: **1 EUR ≈ 4.25 PLN**.

### Primary Build (Fujitsu Q956)

| # | Component | Auction | Unit Price (PLN) | Qty | Total (PLN) | Total (EUR) |
|---|---|---|---|---|---|---|
| 1 | Fujitsu Esprimo Q956 (i5-6500T, no RAM, no disk) | [link](https://allegro.pl/oferta/mini-komputer-fujitsu-q956-tiny-i5-6500t-ddr4-slot-m2-do-rozbudowy-18256791271) | 194.99 | 1 | 194.99 | 45.88 € |
| 2 | WD Black 500GB 2.5" 7200RPM (WD5000LPLX) | [link](https://allegro.pl/oferta/dysk-twardy-wd-black-500gb-2-5-sata-iii-7200rpm-9351169249) | 79.99 | 2 | 159.98 | 37.64 € |
| 3 | RAM 2×4GB DDR3L PC3L-12800S 1600MHz SODIMM | [link](https://allegro.pl/oferta/pamiec-laptopowa-8gb-2x4gb-ddr3-pc3l-12800s-1600mhz-1-35v-sodimm-17388366528) | 29.00 | 1 | 29.00 | 6.82 € |
| 4 | Slimline SATA Caddy 9.5mm (2.5" → ODD bay) | [link](https://allegro.pl/oferta/kieszen-sata-2-5-9-5mm-do-dvd-ssd-hdd-adapter-caddy-ramka-laptop-18799185748) | 17.28 | 1 | 17.28 | 4.07 € |
| | **Base Total** | | | | **401.25** | **94.41 €** |
| 5 | SK Hynix BC501 256GB M.2 NVMe (optional cache) | [link](https://allegro.pl/oferta/sk-hynix-dysk-ssd-2230-m-2-pcie-nvme-256gb-bc501-18558606058) | 89.99 | 1 | 89.99 | 21.17 € |
| | **Total with M.2 cache** | | | | **491.24** | **115.59 €** |

### Alternative Platform (Lenovo M710s SFF)

| # | Component | Auction | Price (PLN) | Price (EUR) |
|---|---|---|---|---|
| 1 | Lenovo ThinkCentre M710s SFF (i3-6100, 8GB RAM, 256GB NVMe, Win 10 Pro) | [link](https://allegro.pl/oferta/lenovo-thinkcentre-m710s-sff-i3-6100-8gb-256gb-nvme-ssd-licencja-win-10-pro-18729986162) | 199.00 | 46.82 € |

**Why Q956 over M710s?** The M710s is cheaper and includes RAM + NVMe, but:
- SFF form factor (~8.4L) vs Q956's ~1.9L — 4× larger
- i3-6100 (2C/4T) vs i5-6500T (4C/4T) in the Q956 — half the cores
- Q956's USFF form factor is quieter, lower power, and fits anywhere

> ⚠️ **RAM compatibility note**: The Allegro Q956 listing states "DDR4". The user-sourced RAM is DDR3L. Skylake supports both DDR3L and DDR4 depending on the motherboard variant — verify the Q956's actual RAM type before purchasing the DDR3L kit.

## Software Choice

**Primary: OpenMediaVault (OMV)** — free, Debian-based, lightweight (~300–500 MB RAM), web UI, Docker support. Fits the 8 GB RAM budget perfectly.

**Migration path: Unraid** — if license cost becomes acceptable later; Unraid offers simpler mixed-disk arrays and a richer Docker ecosystem. OMV was chosen as the starting point because it's free and the setup (2× 500 GB, daily backups, no virtualization) doesn't need Unraid's unique features.

## Key Findings from Research

### Hardware Platform

- **Fujitsu Esprimo Q956** is a rare USFF with 2× native SATA 3.0 ports + 1× M.2 NVMe — most 1L PCs only have 1× SATA + 1× M.2.
- The second SATA port normally serves a slim DVD drive; can be repurposed via a Slimline SATA Caddy 9.5 mm (slot-in adapter for a 2.5" drive).
- The WD5000LPLX is 7mm slim — fits in any 9.5mm Caddy without issue.
- Power supply (external brick, likely 65–90W) is more than sufficient for 2× HDD + potential M.2 NVMe.

### Drive Selection Rationale

- **WD Black WD5000LPLX** chosen over alternatives:
  - Samsung HM321HI (320 GB): too old (~2009), too small, SATA II only
  - Toshiba MQ01ACF050 (500 GB): decent 7200 RPM CMR but older (~2013)
  - WD Black: 7200 RPM, CMR (not SMR!), 32 MB cache, SATA 6 Gbps, ~130–140 MB/s sustained — enough to saturate 1 GbE
- **CMR is critical** for any RAID/parity array — SMR drives (most modern 2.5" HDDs like WD Blue, Seagate BarraCuda) suffer catastrophic write slowdowns during parity calculations.
- **500 GB per disk** with 1× Parity + 1× Data = 500 GB usable (mirrors or single-parity). Exceeds the 256 GB target with room for versioning.

### RAM

- 8 GB (2× 4 GB) is the sweet spot — dual-channel helps I/O, leaves headroom for Linux page cache and light Docker containers.
- DDR3L (1.35V) is required for Skylake; standard 1.5V DDR3 may cause instability.
- Single 4 GB stick would work (Unraid/OMV minimum) but 8 GB is strongly recommended.

### Software: OMV vs Alternatives

| | OMV | Unraid | TrueNAS SCALE | Proxmox |
|---|---|---|---|---|
| **Cost** | Free | Paid license | Free | Free |
| **Base** | Debian | Slackware | Debian | Debian |
| **Min RAM** | 1–2 GB | 4 GB | 8 GB+ | 4 GB |
| **Mixed disks** | Yes (MergerFS+SnapRAID) | Native | No (ZFS requires matched sizes) | Possible (passthrough) |
| **Best for** | Simple NAS + Docker | NAS + Docker + VMs | ZFS purists | Virtualization-focused homelab |

**Why OMV over Unraid for now:**
- Free — no license cost for a simple backup target
- Lower RAM overhead (~500 MB vs ~2 GB for Unraid OS in RAM)
- Native NFS export for Longhorn/K8s backup targets
- Can migrate to Unraid later by importing disks

**Why not TrueNAS:** ZFS needs 8 GB+ RAM minimum, matched disk sizes, and is overkill for 2× 500 GB.

### Installation Strategy (2-Disk Constraint)

OMV is a full OS (unlike Unraid which runs from USB+RAM). With only 2 disks, options are:

1. **Install OMV on a USB stick** (16–32 GB) with `openmediavault-flashmemory` plugin to reduce wear — both WD Black disks remain 100% for data. ✅ Recommended.
2. **Partition disk 1**: small system partition (~20 GB) + data partition — disk 2 is pure data/backup.

Adding an M.2 NVMe later provides the ideal setup: system on NVMe, both HDDs for data.

### Backup Target for Longhorn/K8s

OMV works as a native NFS backup target for Longhorn — just enable NFS, export a share, and point Longhorn's Backup Target to `nfs://<OMV_IP>:/export/backup`. All K8s nodes need `nfs-common` installed.

### Performance Expectations

- **Without cache M.2**: Direct writes to WD Black array at ~60–80 MB/s (parity calculated in-flight). Daily snapshots of a few GB complete in 1–2 minutes. Use "Turbo Write" (Reconstruct Write) in settings to hit ~110–120 MB/s.
- **With cache M.2**: Writes land on NVMe at full 1 GbE speed (~115 MB/s), then `Mover` flushes to HDDs overnight. Disks can spin down 23h/day.
- **Bottlenecks only appear with**: thousands of small files (HDD seek latency), simultaneous multi-client access, or network >1 GbE.

### Disk Mounting

- Disk 1: in the main 2.5" bay (native SATA port).
- Disk 2: via Slimline SATA Caddy 9.5 mm in the DVD bay — the WD5000LPLX (7mm) fits perfectly.
- No extra cables needed for the Caddy approach — the Caddy adapts the Slimline SATA connector on the motherboard to standard SATA data+power.

## Alternatives Considered

### Hardware Platform

| Option | Verdict | Reason |
|---|---|---|
| Dell OptiPlex 3040 SFF (G4400) | ❌ Rejected | Only 2 SATA, no M.2, weakest CPU (2C/2T, no AVX2) |
| Lenovo M900 SFF (i5-6400) | ❌ Rejected | Best SATA count (4 + M.2) but SFF size, overkill for 2-disk NAS |
| Lenovo M710s SFF (i3-6100, 8GB+256GB NVMe incl.) | ⏸️ Alternative | Cheaper (199 zł all-in), more expansion room (3 SATA + M.2 + PCIe slots, ~8.4L), but larger and 2C/4T vs Q956's 4C/4T |
| Lenovo M900 Tiny | ❌ Rejected | Only 1× SATA + 1× M.2, can't fit 2 HDDs |
| USFF with M.2→SATA adapter | ❌ Rejected | Adds cost/complexity; Q956 has native 2× SATA |

### Software

| Option | Verdict | Reason |
|---|---|---|
| Unraid (paid) | ⏸️ Deferred | Great but costs money; OMV first, migrate later if needed |
| TrueNAS SCALE | ❌ Rejected | ZFS needs 8 GB+ RAM minimum, matched disks; overkill |

## Open Questions

- Exact Fujitsu Q956 power supply wattage and connector type (verify before purchase)
- Availability and pricing of Q956 units on the Polish second-hand market (Allegro/OLX)
- Whether the Q956 unit comes with the SATA cable for the second port or if it needs to be sourced separately
- Specific M.2 NVMe model and capacity to add as cache later

## Component Specifications

### Fujitsu Esprimo Q956

| Spec | Value |
|---|---|
| Model | Fujitsu Esprimo Q956 |
| Form factor | USFF / Tiny (~1.9L), internal PSU |
| CPU | Intel Core i5-6500T — 4 cores / 4 threads, 2.5 GHz base, Skylake 6th gen, 35W TDP |
| GPU | Intel HD Graphics 530 (integrated) |
| RAM support | 2× SO-DIMM slots (DDR4 per listing; verify DDR3L compatibility) |
| Storage slots | 1× M.2 NVMe (2280) + 1× SATA 2.5" bay + 1× Slim ODD (SATA via Caddy) |
| Rear I/O | 2× DisplayPort, DVI, COM (serial), RJ-45 LAN, USB 3.0 |
| Included | Green SSD caddy + metal bracket + internal SATA adapter |
| Not included | RAM, storage disk, power cable (C5 "ósemka"), OS |
| Condition | Used, no OS |

### WD Black WD5000LPLX

| Spec | Value |
|---|---|
| Model / P/N | WD5000LPLX / 0CXKCK (Dell OEM variant) |
| Format | 2.5", 7mm slim |
| Capacity | 500 GB |
| RPM | 7200 |
| Interface | SATA III (6 Gbps) |
| Cache | 32 MB |
| Recording | CMR (Conventional Magnetic Recording) |
| Condition | **New** (seller: "Nowy") |

### RAM

| Spec | Value |
|---|---|
| Type | DDR3L SODIMM |
| Speed | PC3L-12800S, 1600 MHz |
| Voltage | 1.35V |
| Kit | 2× 4 GB (8 GB total) |
| Condition | Used |

### Slimline SATA Caddy

| Spec | Value |
|---|---|
| Brand / Model | Gembird MF-95-01 |
| Type | Slimline SATA 9.5mm |
| For | 2.5" SATA SSD/HDD → Slim ODD bay |
| Condition | New |

### SK Hynix BC501 (Optional M.2 Cache)

| Spec | Value |
|---|---|
| Model | SK Hynix BC501 |
| Format | M.2 2230 |
| Capacity | 256 GB |
| Interface | PCIe NVMe |
| Condition | Used |

### Alternative: Lenovo ThinkCentre M710s SFF

| Spec | Value |
|---|---|
| Model | Lenovo ThinkCentre M710s SFF |
| Form factor | SFF (~8.4L) |
| CPU | Intel Core i3-6100 — 2 cores / 4 threads (Hyper-Threading), 3.7 GHz, 51W TDP |
| RAM | 8 GB DDR4 (included) |
| Storage | 256 GB M.2 NVMe SSD (included) |
| OS | Windows 10 Pro license (included) |
| Dimensions | 9.3 cm height |
| Condition | Used |

