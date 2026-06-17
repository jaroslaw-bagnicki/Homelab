# 03 — Selected Hardware: Lenovo ThinkCentre M910q Tiny

**Source**: Gemini 3.5 Flash conversation, May 20 2026  
**Decision**: M910q Tiny (i5-7500T / 16 GB / 256 GB SSD) — primary candidate

---

## Why This Model

The Lenovo ThinkCentre M910q Tiny is a widely regarded USFF business PC on the second-hand market. In the i5-7500T / 16 GB / 256 GB SSD configuration it hits a strong balance between price, power draw, and Linux compatibility.

## Specs

### CPU — Intel Core i5-7500T (Kaby Lake, gen 7)

| Parameter | Value |
|---|---|
| Architecture | Kaby Lake, gen 7 |
| Cores / Threads | 4C / 4T (no Hyper-Threading) |
| Base clock | 2.7 GHz |
| Boost clock | 3.3 GHz |
| TDP | 35 W |
| iGPU | Intel HD Graphics 630 |
| iGPU features | HW encode/decode: HEVC H.265 10-bit, VP9, H.264 → **Intel QuickSync** |

QuickSync makes this an excellent choice for Plex/Jellyfin hardware transcoding.

### Memory & Storage

| Component | Spec |
|---|---|
| RAM | 16 GB DDR4 (2× SODIMM slots, max 32 GB) |
| Primary disk | 256 GB SSD, typically on M.2 slot |
| Secondary slot | 2.5" SATA bay (free — can add HDD or SSD for data/backups) |

> **Buy recommendation**: always 256 GB, not 128 GB. Docker image layers and Hermes Agent's knowledge base (RAG/SQLite) quickly consume 20–40 GB; small SSDs also have low TBW ratings and slow down above 80–85% capacity.

### Form Factor & Power

| Parameter | Value |
|---|---|
| Dimensions | ~18 × 18 × 3.5 cm, ~1.3 kg |
| Idle power | 7–10 W |
| Full load power | ≤ 45 W |
| Noise (idle) | Near-silent |
| VESA mount | Yes (mounts behind monitor) |

### Ports

| Location | Ports |
|---|---|
| Front | 2× USB 3.0 (one Always-On), audio in/out |
| Rear | 4× USB 3.0, Gigabit Ethernet (RJ-45), 2× DisplayPort |
| Optional rear slot | HDMI / VGA / extra LAN (depends on variant) |

---

## Key Limitation: Windows 11

Intel 7th-gen CPUs are **not officially supported by Windows 11**. Windows 10 support has ended.

**Irrelevant for this project** — the machine will run Ubuntu Server headless. No GUI, no Windows dependency.

---

## WiFi Card — Intel 3165NGW vs 9560NGW

Both are M.2 A/E key cards compatible with the M910q Tiny. Linux support via `iwlwifi` driver (included in Ubuntu kernel).

| Feature | Intel 3165NGW | Intel 9560NGW |
|---|---|---|
| WiFi standard | 802.11ac 1×1 | 802.11ac 2×2 |
| Max speed | 433 Mbps | 867 Mbps |
| Bluetooth | 4.2 | 5.0 |
| Release era | ~2015 (Skylake) | ~2017 (Kaby Lake R/Coffee Lake) |
| Antenna count | 1 | 2 |

### Recommendation: 9560NGW

Even for a headless server where throughput isn't critical, the **9560NGW wins** on:

- **2×2 MIMO** — better range and wall penetration for a home server accessed from multiple locations
- **Bluetooth 5.0** — useful for pairing keyboards or USB dongles without occupying USB ports

The 3165 is acceptable if the price difference is significant (< 10 PLN). Otherwise, 9560 is the better long-term choice.

---

## First-Boot Checklist

- [ ] Open case (tool-less), blow out dust
- [ ] Inspect CPU thermal paste — replace if hardware is >3 years old
- [ ] Verify RAM slots and free SATA bay
- [ ] Check PSU is included (missing in some budget Allegro listings; OEM replacement ~30–50 PLN)
- [ ] Flash BIOS to latest version before OS install
- [ ] Install WiFi card (if not included) — 9560NGW recommended

---
