# Idea 01c — Homelab NAS: Wincor Beetle M-III (Unraid)

> ⚠️ **2026-09-05 correction — acquired unit does NOT match this analysis.** The hardware
> diagnostic ([research 32](../research/32-wincor-beetle-m3-hardware-diagnostic.md), issue #98)
> found the acquired Beetle M-III is a board `K2.1-H81-uATX` — **Intel H81 / Haswell / LGA1150 /
> DDR3**, not the **H110 / Skylake / LGA1151 / DDR4** assumed below. The CPU is a **Pentium G3420**
> (Haswell, QuickSync H.264 only, no HEVC), RAM is **1×4 GB DDR3** (2 slots, ≤16 GB), there is
> **no mSATA/NVMe/M.2**, and the array is **2× Seagate 1 TB** (1 parity + 1 data = 1 TB usable),
> not 4×. The box is a workable small Unraid NAS but **the same generation as the EliteDesk 01b**
> it was meant to beat — the "modern platform" premise no longer holds. Directions tested in
> [open questions](#open-questions) below; decision status on [issue #98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98).
>
> **Drives (2026-09-05)** — the array is **2× Seagate ST1000VT001-1RE172** (the pre-analysis's
> "2× WD 1 TB" never applied — the unit shipped with these). Both are **CMR-like** (verified:
> `sdb` 138 MB/s, `sdc` 132 MB/s on rewrite-in-place), SMART **PASSED** and **extended self-test
> clean (both `Completed without error`)**, but **~65.5k POH (~7.5 yr)** and **Seagate Video 2.5
> (surveillance)** drives — the offer's *"removed from high-budget laptops"* description
> **contradicts** the always-on SMART history (65,536 POH / only 4 power-cycles). **Decision
> resolved 2026-09-05: keep the 2× Seagates** (CMR + healthy + deep-test clean) → array = 1 parity +
> 1 data = 1 TB, SanDisk X600 cache. The WD10JUCX pair is a fallback only.
>
> The analysis below remains as the pre-acquisition research that fed the decision; it is **not**
> the authority for the platform. Where it conflicts with research 32, research 32 wins.

**Status**: 🧠 Idea (platform premise superseded)  
**Date**: 2026-08-22  
**Sources**:
- [Gemini thread 4 — Wincor Beetle M-III vs EliteDesk 800 G1 SFF](https://share.gemini.google/H4KW01K8tTUZ) — dimensions, CPU support, cooling, fan control/noise, Zigbee fan control, disk capacity/mounting, NAS-platform analysis
- [Gemini thread 5 — Cache SSD mSATA for Unraid HDD](https://share.gemini.google/lyviXlDkXm7Y) — cache choice (mSATA vs NVMe vs SATA SSD), link aggregation vs 2.5 GbE, Unraid build plan
- [Allegro offer 18851315845 — Wincor Beetle M-III G4400 8GB 128GB SSD](https://allegro.pl/oferta/wincor-beetle-m-iii-g4400-8gb-128gb-ssd-terminal-pos-komputer-18851315845) (scraped 2026-08-22)

Companion to [idea 01b](01b-nas-backup-target-elitedesk.md) (EliteDesk 800 G1 SFF) and
**successor candidate to [idea 03](03-nas-backup-target-ml110.md)** (ML110 — too noisy and
power-hungry, to be retired next month) — the **most extensible** NAS variant.

## Topic

A used **Wincor Beetle M-III** POS terminal (LGA1151 / H110 / DDR4) upgraded to a
**Unraid** NAS: 2.5" HDD array + SSD/NVMe cache. Chosen over the EliteDesk (01b) because
the industrial POS platform leaves the most room to grow:

| Capability | EliteDesk 800 G1 SFF (01b) | Wincor Beetle M-III (this idea) |
|---|---|---|
| Chipset / CPU | Q87, LGA1150 (4th gen Haswell) | **H110, LGA1151 (6th gen; some revisions 7./8./9.)** |
| RAM | 4× DIMM DDR3, max 32 GB | **4× DIMM DDR4, 32 GB+** |
| SATA | 4 (2× SATA III + 2× SATA II) | 3× SATA III + 1× mSATA |
| Expansion | 1× x16<br>1× x16(x4)<br>2× x1 | 1× x16<br>1× x1<br>1× PCI/PCIe (optional) |
| PSU | 240 W proprietary HP (not ATX) | **Industrial 220–300 W (FSP/Fortron, 80 Plus Gold/Platinum)** |
| Form factor — dimensions | 33.8 × 37.9 × 10.0 cm (W×D×H) | 31.2 × 30.3 × 10.3 cm (W×D×H) |
| Form factor — weight | ~7.6 kg | ~5.0 kg |
| Form factor — capacity | ~12.8 L (from dims) | ~9.7 L (from dims) |

## Final Hardware Shape

| Component | Selection |
|---|---|
| **PC** | Wincor Beetle M-III (G4400, 8 GB DDR4, 128 GB SSD, industrial PSU) |
| **OS** | **Unraid** (paid license, USB-boot → runs from RAM; no BIOS NVMe boot needed) |
| **Storage** | up to **4× 2.5" HDD** — 2× factory bracket + 3.5" bay → 2× 2.5" sled (1× parity + 3× data) |
| **Cache** | reuse the **included 128 GB SSD** for now; future upgrade: **M.2 NVMe via low-profile PCIe adapter** |
| **Network** | on-board 1 GbE (keep); 2.5 GbE only if the switch is upgraded |
| **Cooling** | **3 fans** (front → CPU+PSU, rear PSU-end, UPS-unit) + **Gelid Fan Speed Controller** (TACH kept on board); optional quiet 80 mm front intake fan over the disk bracket — see [research 32](../research/32-wincor-beetle-m3-hardware-diagnostic.md) |

## Cost Estimation

Prices scraped / quoted (August 2026). Conversion: **1 EUR ≈ 4.25 PLN**.

| # | Component | Unit (PLN) | Qty | Total (PLN) | Total (EUR) | Link |
|---|---|---|---|---|---|---|
| 1 | Wincor Beetle M-III G4400 8GB 128GB (used, BIOS unlocked) | 299 | 1 | 299 | 70 € | [offer](https://allegro.pl/oferta/wincor-beetle-m-iii-g4400-8gb-128gb-ssd-terminal-pos-komputer-18851315845) |
| 2 | WD 1TB 2.5" 5400 RPM SATA III (WD10JUCX) — unused 2017 AV-recorder drives | 185 | 2 | 370 | 87 € | [offer](https://allegro.pl/oferta/dysk-twardy-wd-1tb-5-4k-16mb-sata-iii-2-5-wd10jucx-18802168828) |
| | **Total** | | | **669** | **157 €** | |

> ⚠️ Base unit **includes** CPU + 8 GB RAM + 128 GB SSD — no extra CPU/RAM purchase needed
> (unlike the EliteDesk 01b barebones). The 2× WD 1 TB HDDs are new 2017 AV-recorder drives
> drives bought from warehouse stock (185 PLN each). The included 128 GB SSD is reused as the
> Unraid cache for now.

**Nice-to-have (future):**
- **M.2 NVMe cache via low-profile PCIe→M.2 adapter** (e.g. Kioxia/SSSTC CL4 128 GB, ~60 PLN + ~15–20 PLN adapter) — upgrade path once the reused 128 GB SSD is outgrown
- **Gelid Fan Speed Controller** (~15–20 PLN) — use it to reduce the factory turbine noise by ~50–60 % (down to ~32–35 dB) while keeping TACH on the board

## Key Findings

### Platform & extensibility
- **Industrial PSU** (220–300 W, 80 Plus Gold/Platinum) with large 12 V headroom for multi-HDD spin-up + PoweredUSB 12/24 V — vs the EliteDesk's 240 W proprietary PSU with ~3–4 SATA plugs (confirmed on the received unit: **AcBel 250 W, 80 Plus Gold**, research 32)
- **Expansion**: confirmed **1× PCIe 3.0 x16 + 2× PCIe 2.0 x1 + mini-PCIe (mSATA-capable)** (research 32) → HBA/SATA controller, 2.5 GbE/10 GbE NIC, or PCIe→NVMe adapter — expansion a Mini/USFF box cannot offer
- **Modern platform**: LGA1151 (6th gen; some revisions 8./9.), **DDR4**, QuickSync (H.264/H.265 8-bit decode) for transcoding; **3× SATA III + 1× mSATA** on board — cache without eating a PCIe slot
- **24/7 POS-grade build** (thick steel, industrial components, vibration-tolerant chassis)

### Noise & power vs the ML110
- Idle **~15–25 W** vs ML110's ~60–80 W+; ~35–38 dB idle / ~42–45 dB stress vs the ML110's server-fan whine + "jet" POST
- CPU TDP doesn't affect idle draw — real savings come from disk spin-down + the low-idle POS platform

### Cooling & fan control
- **Tunnel cooling**: factory assumption was one radial turbine over a passive CPU heatsink —
  the received unit has **3 fans** (front → CPU+PSU, rear PSU-end, UPS-unit); measured **42.5 dB
  @ 30 cm** ≈ this note's "44 dB / ~42–45 dB stress" (research 32) — the noise is high-pitched airflow
- **Manual fan control**: Gelid Fan Speed Controller cuts RPM ~50–60 % (→ ~32–35 dB) and **passes TACH through** → no `Fan Error` at POST; optional Zigbee dimmer for Home Assistant control
- ⚠️ Passive heatsink needs constant airflow — don't go below ~30 dB; keep TACH on the board (non-standard pinout stalls POST)

### Disks & cache
- 2× 2.5" factory bracket + 3.5" bay → 2× 2.5" sled = **4× 2.5" total**; quality Y-splitters for the 4th disk; front 80 mm fan cools them
- **M.2 NVMe via PCIe adapter** (Kioxia CL4 128 GB) = best value; **mSATA SSD** cheapest; **2.5" SATA SSD** simplest mount (avoid QLC)
- ⚠️ A single cache disk isn't parity-protected until Mover flushes — consider a 2-disk mirror for critical backups

### Networking
- On-board 1 GbE is enough for a backup-only NAS; **2.5 GbE** (RTL8125B) is the single-client upgrade but needs a 2.5 G switch
- 2× 1 GbE LACP/bond only helps multiple concurrent clients

## Alternatives Considered

| Option | Verdict | Reason |
|---|---|---|
| HP EliteDesk 800 G1 SFF (idea 01b) | ⏸️ Alternative | Cheaper barebones, but DDR3/Haswell, 240 W proprietary PSU, no mSATA, fewer PCIe slots |
| HP ProLiant ML110 G5 (idea 03) | ❌ Rejected (current) | Too noisy (42–58 dB), power-hungry (~60–80 W+ idle), full tower — the reason for this idea |
| X-Star Bull Shark 128 GB mSATA cache | ❌ Rejected | No-name white-label, no DRAM cache, ~125 PLN vs ~75–80 PLN Kioxia NVMe + adapter |
| 2× 1 GbE link aggregation | ⏸️ Deferred | Multi-client only; single backup stays 1 GbE; needs LACP switch |

## Open Questions

- **Board revision**: confirm actual ports on arrival — 3× SATA + 1× mSATA + 3× PCIe (thread 4 mentions M.2 on some revisions; thread 5 says no M.2 — verify)
- **HDD fit/airflow**: 4× 2.5" total (factory bracket + 3.5"→2×2.5" sled) — physical fit, airflow, and SATA power splitter count on the actual PSU
- **Noise target**: factory turbine + Gelid at ~35 % reduction should hit ~32–35 dB — verify CPU stays cool at 65 W TDP under parity-check load
- **Timeline**: retire ML110 next month → replace as idea 03's successor? Keep ML110 until the Beetle array is verified

