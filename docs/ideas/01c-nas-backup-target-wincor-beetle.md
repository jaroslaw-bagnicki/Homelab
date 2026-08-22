# Idea 01c — Homelab NAS: Wincor Beetle M-III (Unraid)

**Status**: 🧠 Idea
**Date**: 2026-08-22
**Sources**:
- [Gemini thread 4 — Wincor Beetle M-III vs EliteDesk 800 G1 SFF](https://share.gemini.google/H4KW01K8tTUZ) (published 2026-08-22) — dimensions, CPU support, cooling, fan control/noise, Zigbee fan control, disk capacity/mounting, NAS-platform analysis
- [Gemini thread 5 — Cache SSD mSATA dla Unraid HDD](https://share.gemini.google/lyviXlDkXm7Y) (published 2026-08-22) — cache choice (mSATA vs NVMe vs SATA SSD), link aggregation vs 2.5 GbE, Unraid build plan
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
| M.2 | none (PCIe adapter only) | none on H110 boards (mSATA on board); M.2 on some revisions |
| Expansion | 1× PCIe 3.0 x16 + 1× x16(x4) + 2× x1 | **3× PCIe (x16 + x1/x4, low-profile)** |
| PSU | 240 W proprietary HP (not ATX) | **Industrial 220–300 W (FSP/Fortron, 80 Plus Gold/Platinum)** |
| Form factor | SFF ~8.4L | ~31.2 × 30.3 × 10.3 cm, ~5.0 kg |
| Included | barebones (no CPU/RAM/disk) | **G4400 + 8 GB DDR4 + 128 GB SSD (299 zł)** |

## Final Hardware Shape

| Component | Selection |
|---|---|
| **PC** | Wincor Beetle M-III (G4400, 8 GB DDR4, 128 GB SSD, industrial PSU) |
| **OS** | **Unraid** (paid license, USB-boot → runs from RAM; no BIOS NVMe boot needed) |
| **Storage** | up to **4× 2.5" HDD** — 2× factory bracket + 3.5" bay → 2× 2.5" sled (1× parity + 3× data) |
| **Cache** | **M.2 NVMe via low-profile PCIe adapter** (e.g. Kioxia CL4 128 GB) — or mSATA SSD in the board slot, or plain 2.5" SATA SSD |
| **Network** | on-board 1 GbE (keep); 2.5 GbE only if the switch is upgraded |
| **Cooling** | factory tunnel turbine + **Gelid Fan Speed Controller** (TACH kept on board); optional quiet 80 mm front intake fan over the disk bracket |

## Cost Estimation

Prices scraped / quoted (August 2026). Conversion: **1 EUR ≈ 4.25 PLN**.

| # | Component | Seller | Unit (PLN) | Qty | Total (PLN) | Total (EUR) | Link |
|---|---|---|---|---|---|---|---|
| 1 | Wincor Beetle M-III G4400 8GB 128GB (used, BIOS unlocked) | pc-data | 299.00 | 1 | 299.00 | 70.35 € | [oferta](https://allegro.pl/oferta/wincor-beetle-m-iii-g4400-8gb-128gb-ssd-terminal-pos-komputer-18851315845) |
| 2 | Kioxia/SSSTC CL4 128GB M.2 2230 NVMe (cache) | — | ~60 | 1 | ~60 | ~14 € | [produkt](https://allegro.pl/produkt/dysk-ssd-m-2-ssstc-kioxia-2230-pcie-x4-gen4-nvme-128gb-cl4-3d128-hp-36dec705-4be9-4e71-bb05-7f0aeb7d9aad?offerId=17702798404) |
| 3 | PCIe→M.2 NVMe adapter (low-profile, 2230) | — | ~15–20 | 1 | ~15–20 | ~4 € | — |
| 4 | Gelid Fan Speed Controller (fan silencing) | — | ~15–20 | 1 | ~15–20 | ~4 € | [oferta](https://allegro.pl/oferta/gelid-fan-speed-controller-regulator-obrotow-13298936989) |
| | **Total (excl. HDDs)** | | | | **~390–400** | **~92–94 €** | |

> ⚠️ Base unit **includes** CPU + 8 GB RAM + 128 GB SSD — no extra CPU/RAM purchase needed
> (unlike the EliteDesk 01b barebones). HDDs (2–4× 2.5") sourced separately.

## Key Findings from Research

### Platform & extensibility (thread 4)
- **Industrial PSU** (FSP/Fortron-class, 220–300 W, 80 Plus Gold/Platinum) with a large 12 V
  headroom for multi-HDD spin-up, plus PoweredUSB 12/24 V — vs the EliteDesk's 240 W
  proprietary HP PSU with only ~3–4 SATA plugs
- **3× PCIe slots** (full x16 + x1/x4, low-profile) → HBA/SATA controller (ASM1166, LSI
  9211-8i/9300-8i), 2.5 GbE/10 GbE NIC (Intel i225/i226), or PCIe→NVMe adapter — expansion
  a Mini/USFF box cannot offer
- **Modern platform**: LGA1151 (Skylake/Kaby Lake, some revisions 8./9. gen), **DDR4**, Intel
  QuickSync (H.264/H.265 8-bit decode) for Plex/Jellyfin/Frigate transcoding; 14 nm vs the
  EliteDesk's 22 nm Haswell/DDR3
- **3× SATA III + 1× mSATA** on board — cache without eating a PCIe slot
- **24/7 POS-grade build** (thick steel, industrial components, vibration-tolerant chassis)

### Noise & power vs the ML110 (thread 4)
| | Wincor Beetle M-III | HP EliteDesk 800 G1 SFF (01b) | HP ProLiant ML110 G5 (03) |
|---|---|---|---|
| Noise idle / stress | ~35–38 / ~42–45 dB | ~30–35 / ~40–45 dB | **~42–48 / ~52–58+ dB** |
| Noise character | muffled tunnel airflow | standard SFF | **server fan whine + "jet" POST** |
| Idle power | **~15–25 W** | ~12–15 W | **~60–80 W+** (server board) |
| Footprint | 31.2 × 30.3 × 10.3 cm, ~5 kg | 33.8 × 37.9 × 10.0 cm, ~7.6 kg | full tower |

The Beetle at 44 dB under load "sounds like a slightly loaded office PC" next to the ML110.
CPU TDP does not affect idle draw (identical C-States, "race to sleep") — real savings come
from disk spin-down + the low-idle POS platform.

### Cooling & fan control (thread 4)
- **Tunnel cooling**: one radial **turbine** blows through a plastic air duct over a
  **passive CPU heatsink** (copper base/heatpipe on stronger CPUs); PSU often has its own
  small exhaust fan. This tunnel is why 44 dB is a high-pitched airflow noise
- **Front intake slot**: factory perforation + mounts for a **60/80 mm fan** (80 mm fits)
  aimed straight at the disk bracket — the key trick for a multi-HDD NAS (positive pressure,
  fewer dust spots)
- **Manual fan control**: factory turbine + **Gelid Fan Speed Controller** cuts RPM
  ~50–60 % (→ ~32–35 dB, safe for CPU ≤65 W TDP) and **passes TACH through** → no `Fan
  Error` at POST. Alternatives: Zalman Fan Mate 2, Noctua NA-FC1 (4-pin PWM, ~85–105 zł),
  Noctua NF-A8/NF-A9 high-static-pressure (~75–95 zł) or Arctic P8/P8 Max (~25–35 zł)
- ⚠️ The passive heatsink needs constant airflow — don't go below ~30 dB or expect thermal
  throttling under sustained load; keep the TACH wire on the board (Wincor boards may use
  non-standard pinout → missing RPM stalls POST)
- **Zigbee fan control** (optional): DC 12 V Zigbee LED-strip dimmer (~40–70 zł) drives the
  fan via Home Assistant "brightness"; keep TACH on the board + watchdog (fan → 100 % if CPU
  >70 °C). **Not** the Arctic Case Fan Hub (ACFAN00175A) — that's a PWM splitter for 10 fans,
  no manual knob, pointless for a single tunnel fan

### Disks & cache (thread 5)
- **3× SATA III + 1× mSATA**; factory bracket holds **2× 2.5"** + 1× 3.5" bay (convertible
  to 2× 2.5" → 4× 2.5" total). PSU feeds ~2–3 SATA plugs → quality Y-splitters for the 4th
  disk; keep 3–5 mm spacing between stacked 2.5" HDDs; front 80 mm fan cools them
- **Cache choice** (all saturate 1 GbE ≈ 115 MB/s):
  - **M.2 NVMe via PCIe adapter** (recommended): Kioxia/SSSTC **CL4-3D128-HP 128 GB** (~60 zł)
    is a branded HP OEM pull (DRAM-less HMB, Gen4 x4 in a Gen3 slot → still huge headroom).
    Needs a **low-profile PCIe→M.2 adapter (~15–20 zł)** supporting 2230 length (or ~5 zł
    extender). **Better value than the X-Star mSATA** (~125 zł) — X-Star is a no-name
    white-label (no DRAM cache, random controller/NAND, unverifiable TBW)
  - **mSATA SSD** direct in the board slot — cheapest, saves the PCIe slot
  - **Plain 2.5" SATA SSD** — simplest mount, better thermals; avoid QLC (BX500) — prefer TLC
    (MX500/870 EVO) or used server drives
- ⚠️ **Cache redundancy**: a single cache disk isn't parity-protected until Mover flushes —
  for critical backups consider a 2-disk mirror or more frequent Mover

### Networking (thread 5)
- **2× 1 GbE LACP/bond** (second low-profile NIC, e.g. Intel i350-T2/i210 or used PRO/1000
  ~20–30 zł): only helps **multiple concurrent clients** (2 clients → 2× 1 GbE); a single
  backup stream stays at 1 GbE. Needs LACP on the switch
- **2.5 GbE** (Realtek RTL8125B, low-profile, ~50–70 zł) is the better single-client upgrade
  (~280 MB/s) — **but needs a 2.5 G switch** (pricey for the homelab budget). For a
  backup-only 1 GbE NAS the onboard NIC is enough → keep the PCIe slots free

## Alternatives Considered

| Option | Verdict | Reason |
|---|---|---|
| HP EliteDesk 800 G1 SFF (idea 01b) | ⏸️ Alternative | Cheaper barebones, but DDR3/Haswell, 240 W proprietary PSU, no mSATA, fewer PCIe slots |
| HP ProLiant ML110 G5 (idea 03) | ❌ Rejected (current) | Too noisy (42–58 dB), power-hungry (~60–80 W+ idle), full tower — the reason for this idea |
| X-Star Bull Shark 128 GB mSATA cache | ❌ Rejected | No-name white-label, no DRAM cache, ~125 zł vs ~75–80 zł Kioxia NVMe + adapter |
| Arctic Case Fan Hub (ACFAN00175A) | ❌ Rejected | PWM splitter for 10 fans, no manual control, pointless for 1 tunnel fan |
| 2× 1 GbE link aggregation | ⏸️ Deferred | Multi-client only; single backup stays 1 GbE; needs LACP switch |

## Open Questions

- **Board revision**: confirm actual ports on arrival — 3× SATA + 1× mSATA + 3× PCIe (thread
  4 mentions M.2 on some revisions; thread 5 says no M.2 — verify)
- **SMR risk**: large 2.5" HDDs (e.g. WD10JUCX 1 TB) are SMR — verify parity-write behaviour
  under Unraid (CMR/SSD preferred)
- **HDD fit/airflow**: 4× 2.5" total (factory bracket + 3.5"→2×2.5" sled) — physical fit,
  airflow, and SATA power splitter count on the actual PSU
- **Noise target**: factory turbine + Gelid at ~35 % reduction should hit ~32–35 dB — verify
  CPU stays cool at 65 W TDP under parity-check load
- **Timeline**: retire ML110 next month → replace as idea 03's successor? Keep ML110 until
  the Beetle array is verified

## Component Specifications

### Wincor Beetle M-III (this offer)

| Spec | Value |
|---|---|
| Model | Wincor Nixdorf Beetle M-III (POS terminal) |
| CPU | Intel Celeron G4400 — 2C/2T, 3.30 GHz, 3 MB cache (LGA1151, ≤84 W TDP) |
| Chipset | Intel H110 (6th gen Skylake; some revisions 7./8./9. gen) |
| RAM | 8 GB DDR4 (4× DIMM, non-ECC, upgradeable to 32 GB+) |
| GPU | Intel HD Graphics 510 (QuickSync: H.264/H.265 8-bit; no AV1) |
| Storage | 3× SATA III + 1× mSATA (board); 128 GB SSD included |
| Expansion | 3× PCIe (full x16 + x1/x4, low-profile) |
| LAN | 1 GbE onboard |
| PSU | Built-in industrial POS PSU (FSP/Fortron-class, 220–300 W, 80 Plus Gold/Platinum) |
| Bays | 2× 2.5" factory bracket + 1× 3.5" (→ 2× 2.5" sled) |
| Ports | USB 2.0/3.0, COM/RS-232, PoweredUSB 12 V/24 V, cash drawer, DVI/DP/VGA, RJ-45, audio |
| Dimensions | ~31.2 × 30.3 × 10.3 cm, ~5.0 kg |
| Included | G4400, 8 GB DDR4, 128 GB SSD, industrial PSU — BIOS unlocked, ready for any OS |
| Condition | Used, tested, normal wear |
