# Idea 01b — Homelab NAS: HP EliteDesk 800 G1 SFF (Unraid)

**Status**: 🧠 Idea
**Date**: 2026-08-17
**Sources**:
- [Gemini thread 3](https://share.gemini.google/U5zpt2ypVual) — HP EliteDesk 800 G1 SFF (Variant B): platform limits, CPU/RAM, power, fan control, SATA/NVMe controllers, link aggregation
- Allegro offers: [HP EliteDesk 800 G1 SFF](https://allegro.pl/oferta/hp-elitedesk-800-g1-sff-lga-1150-0-0-gb-baza-do-rozbudowy-18569899026) · [UGREEN PCIe→M.2 adapter](https://allegro.pl/oferta/kontroler-ugreen-adapter-pcie-4-0-x16-do-m-2-nvme-17379581052) · [RAM DDR3 8GB](https://allegro.pl/produkt/pamiec-ram-ddr3-8-gb-1600-11-f86e6e7f-da74-4da4-b456-ba14b4fe434d?offerId=13774167898) · [Micron M.2 2230 NVMe 256GB](https://allegro.pl/produkt/dysk-ssd-m-2-micron-2230-pcie-x4-gen4-nvme-256-gb-mtfdkbk256tfk-2450-9893eda0-82e5-4b34-b2e7-57ad2a56ec31?offerId=18798899129) · [WD 1TB 2.5" WD10JUCX ×3](https://allegro.pl/produkt/wd-1tb-5-4k-16mb-sata-iii-2-5-wd10jucx-5a7413ab-7a36-48ac-896a-000b9486c737?offerId=18802168828)

Companion to [idea 01](01-nas-backup-target.md) (Fujitsu Esprimo Q956 / OMV variant) — the **extensible** alternative.

## Topic

A used **HP EliteDesk 800 G1 SFF** (LGA1150 / Q87 / Haswell) barebones, upgraded to a **Unraid** NAS with 2× 1 TB 2.5" HDDs + 1× M.2 NVMe cache. Chosen over the Fujitsu Q956 because the platform leaves room to grow:

| Capability | Q956 (idea 01) | EliteDesk 800 G1 SFF (this idea) |
|---|---|---|
| SATA ports | 2 | 4 (2× SATA III + 2× SATA II) |
| RAM slots | 2× SO-DIMM (DDR3L) | 4× DIMM DDR3/DDR3L, up to 32 GB |
| Expansion | 1× M.2 NVMe (no PCIe) | 1× PCIe 3.0 x16 + 1× PCIe 2.0 x16 (x4) + 2× PCIe x1 |
| Form factor | USFF ~1.9L | SFF ~8.4L |
| PSU | Internal brick | 240 W proprietary (not ATX) |
| Drive bays | 1× 2.5" + ODD bay | 2× 3.5" (→ 2.5" sleds) + 1× 2.5" |

## Final Hardware Shape

| Component | Selection |
|---|---|
| **PC** | HP EliteDesk 800 G1 SFF barebones (no CPU/RAM/disk, 240 W PSU) |
| **OS** | **Unraid** (paid license, USB-boot → runs from RAM; no BIOS NVMe boot needed) |
| **CPU** (not included — buy separately) | Intel Core i5-4570T (2C/4T, 35 W) — 19 PLN budget pick; or i5-4570 / i5-4590 (4C/4T) for more headroom |
| **RAM** | 8 GB DDR3 PC3-12800 1600 MHz (2× 4 GB kit); upgrade path to 16 GB (Unraid sweet spot) |
| **Disks** | 2× WD Blue 1 TB 2.5" HDD (WD10JUCX, 5400 RPM, 16 MB cache, SATA III) — 1× parity + 1× data |
| **Cache** | 1× Micron M.2 2230 PCIe Gen4 NVMe 256 GB (MTFDKBK256TFK) via UGREEN PCIe x16→M.2 adapter |

## Cost Estimation

Prices from the Allegro cart (August 2026, screenshots). Conversion: **1 EUR ≈ 4.25 PLN**.

| # | Component | Unit (PLN) | Qty | Total (PLN) | Total (EUR) | Link |
|---|---|---|---|---|---|---|
| 1 | HP EliteDesk 800 G1 SFF barebones (used) | 125 | 1 | 125 | 30 € | [offer](https://allegro.pl/oferta/hp-elitedesk-800-g1-sff-lga-1150-0-0-gb-baza-do-rozbudowy-18569899026) |
| 2 | Intel Core i5-4570T (2C/4T, 35 W, used) | 19 | 1 | 19 | 4 € | [offer](https://allegro.pl/produkt/intel-core-i5-4570t-2-90ghz-sr1ca-s1150-tdp-35w-edbe2065-6f26-424d-b54c-a50c8c9789ac?offerId=18408407677) |
| 3 | DDR3 8 GB (2×4 GB) 1600 MHz (used) | 30 | 1 | 30 | 7 € | [offer](https://allegro.pl/produkt/pamiec-ram-ddr3-8-gb-1600-11-f86e6e7f-da74-4da4-b456-ba14b4fe434d?offerId=13774167898) |
| 4 | WD 1 TB 2.5" 5400 RPM (WD10JUCX) | 185 | 2 | 370 | 87 € | [offer](https://allegro.pl/produkt/wd-1tb-5-4k-16mb-sata-iii-2-5-wd10jucx-5a7413ab-7a36-48ac-896a-000b9486c737?offerId=18802168828) |
| 5 | Micron M.2 2230 NVMe 256 GB | 135 | 1 | 135 | 32 € | [offer](https://allegro.pl/produkt/dysk-ssd-m-2-micron-2230-pcie-x4-gen4-nvme-256-gb-mtfdkbk256tfk-2450-9893eda0-82e5-4b34-b2e7-57ad2a56ec31?offerId=18798899129) |
| 6 | UGREEN PCIe x16 → M.2 NVMe adapter | 30 | 1 | 30 | 7 € | [offer](https://allegro.pl/oferta/kontroler-ugreen-adapter-pcie-4-0-x16-do-m-2-nvme-17379581052) |
| | **Total** | | | **709** | **167 €** | |

> ⚠️ **The barebones listing ships WITHOUT a CPU, RAM, and disk** — a Haswell LGA1150 CPU must be sourced separately (i5-4570T at 19 PLN is the budget pick; note it's 2C/4T). Unlike the Beetle 01c, no SSD is included, so the NVMe cache + adapter are a **required** part of the build. Shipping differs per seller; some items qualify for free "SMART!" delivery.

## Key Findings

### Platform limits & workarounds
- **No NVMe boot in BIOS** — Q87 has no native NVMe; irrelevant for Unraid (USB boot → Linux kernel `nvme.ko` → NVMe shows up as a fully usable cache disk)
- **SATA**: 4 on-board ports (2× SATA III 6Gbps + 2× SATA II 3Gbps) — enough for the 2 HDDs; an HBA unlocks expansion
- **PCIe** (all Low Profile): 1× PCIe 3.0 x16, 1× PCIe 2.0 x16 (electrically x4), 2× PCIe x1
- **PSU**: 240 W, proprietary HP 6-pin + 6-pin Aux connector (not ATX); only ~3–4 factory SATA power plugs → quality Y-splitters needed for 5-disk builds; mind disk spin-up current on 5V/12V
- **Cooling**: single front fan; 4–5 packed 2.5" disks run hot without airflow; keep the factory dual-ball-bearing fans, set BIOS `Fan Idle Mode = 1` (~700–900 RPM idle, disks ~38–42°C)
- **Fan control limits**: HP proprietary Super I/O + BIOS-enforced PWM lock → Unraid's Dynamix Fan Control usually reads temps but can't set PWM; HP 4-pin pinout is non-standard → replacement fans risk POST errors `511-CPU Fan Not Detected` / `512-Rear Fan Not Detected`

### CPU & RAM (Unraid)
- SFF supports up to **84 W TDP**; avoid unlocked "K" chips (throttling). "T" variants (e.g. i5-4570T, 2C/4T) are acceptable as a **budget pick** for a backup-only NAS without transcoding
- **Economy**: i5-4570 / i5-4590 (4C/4T, ~30–50 PLN); **budget**: i5-4570T (2C/4T, 35 W) at 19 PLN
- **Recommended (transcoding)**: i7-4770 / i7-4790 (4C/8T, ~100–140 PLN); HD 4600 decodes H.264 but **not** H.265/HEVC 10-bit or AV1
- **RAM**: 4× DIMM DDR3/DDR3L 1600, non-ECC, max 32 GB; **16 GB (2×8 GB or 4×4 GB) is the sweet spot**; run MemTest86 (in Unraid's boot menu) first — Unraid lives in RAM
- **Power**: whole unit ~12–15 W idle; CPU TDP doesn't affect idle draw (identical C-States, "race to sleep"); real savings from disk spin-down (1.5–2.5 W working vs ~0.2 W asleep per 2.5" disk) and enabling C6/C7 + Intel SpeedStep in BIOS

### SATA controller (only if adding more disks)
- **Avoid** cheap PCIe x1 Marvell/ASMedia "4× SATA RAID" cards — dropped drives / CRC errors under load, x1 lane bottleneck during parity checks, hardware RAID breaks Unraid's JBOD/SMART
- **Recommended**: LSI 9211-8i / 9207-8i (or Dell PERC H310 flashed to IT mode), ~100–140 PLN, up to 8 disks via SFF-8087→4×SATA
- **Budget/eco**: ASMedia ASM1064 card (no RAID, <2 W) — note a full LSI HBA draws 7–10 W constantly

### NVMe adapter (UGREEN, offer 17379581052)
- **Works** — passive M.2→PCIe adapter; ships with a **Low Profile** bracket that must be swapped in to close the SFF case
- Full speed (~3200–3500 MB/s) in the **PCIe 3.0 x16** slot; ~1600–2000 MB/s in the PCIe 2.0 x4 slot (still plenty for cache)
- Unraid detects it after kernel load — no BIOS boot required

### Networking / link aggregation
- Slot plan: PCIe x16 → SATA HBA; PCIe x16/x4 → NVMe adapter; PCIe x1 → 2nd NIC (**Intel i350-T2 / i210-T2**, Low Profile) → 3× 1 GbE total with the onboard I217-LM
- Unraid bonding: Mode 1 Active-Backup (any switch), Mode 4 802.3ad LACP (managed switch, multi-client), Mode 6 ALB (any switch, load balance)
- **LACP ≠ 2 Gb/s per client** — a single session stays on one cable (~1 Gb/s); 2 clients can each hit 1 Gb/s
- For single-client speed: 2.5 GbE card (Realtek RTL8125B, Low Profile, ~80–120 PLN) if the switch supports 2.5G

### ✅ Recording — the 2× WD 1 TB drives
- WD10JUCX is a **WD AV-25** (2.5" surveillance/AV line) drive using **CMR** — parity-safe, no SMR write-degradation in the array

## Alternatives Considered

| Option | Verdict | Reason |
|---|---|---|
| Cheap PCIe x1 "4× SATA RAID" controller | ❌ Rejected | Unstable under Unraid (dropped drives / CRC), x1 bottleneck, RAID breaks SMART |
| LSI HBA IT mode (9211-8i / 9207-8i) | ✅ Recommended | Native Unraid support, up to 8 disks, ~100–140 PLN |
| ASMedia ASM1064 controller | ⏸️ Budget option | Works, <2 W, no RAID — enough for the 2-disk build |
| Link aggregation 2× 1 GbE | ⏸️ Depends | Multi-client throughput only; not for single-client speed |

## Open Questions

- CPU settled on the budget i5-4570T (2C/4T) — revisit i7-4770/4790 if transcoding is later needed
- Extra SATA HBA needed? Only 2 HDDs → on-board SATA is sufficient for now
- Confirm WD10JUCX SMR behaviour under Unraid parity in practice
- Thermals/fan noise with 2 HDDs in the SFF case

## Component Specifications

### HP EliteDesk 800 G1 SFF

| Spec | Value |
|---|---|
| Model | HP EliteDesk 800 G1 SFF |
| Form factor | SFF (~8.4L), Low Profile cards only |
| Chipset | Intel Q87, LGA1150 (4th gen Haswell) |
| CPU support | Up to 84 W TDP |
| RAM | 4× DIMM DDR3/DDR3L 1600 MHz, non-ECC, max 32 GB |
| Storage | 4× SATA (2× SATA III 6Gbps + 2× SATA II 3Gbps) |
| Expansion | 1× PCIe 3.0 x16 · 1× PCIe 2.0 x16 (x4) · 2× PCIe 2.0 x1 |
| LAN | Intel I217-LM 1 GbE (onboard) |
| PSU | 240 W, proprietary HP 6-pin + 6-pin Aux |
| Bays | 2× 3.5" (→ 2.5" sleds) + 1× 2.5" |
| Included | None — barebones (no CPU/RAM/disk/OS) |
| Condition | Used, 100% functional |