# 01 — Second-Hand Mini PC Hardware Research

**Source**: Gemini 3.5 Flash conversation, May 20 2026  
**Topic**: Cheap mini PC for Ubuntu Server homelab, second-hand from Allegro (Polish resale market)

---

## Form Factors to Target

For a 24/7 Ubuntu Server homelab, the best candidates are business-grade **TFF (Tiny Form Factor)**, **USFF**, and **Mini PC** units. Key properties:

- Idle power draw typically **5–10 W**
- Silent, compact, durable
- Business lineage = better driver support & repairability

### Main Brands & Series

| Brand | Series | Example Models |
|---|---|---|
| Lenovo | ThinkCentre Tiny | M710q, M720q, M910q, M75q-2 |
| HP | ProDesk / EliteDesk Desktop Mini | 400 G3/G4, 800 G3/G4 |
| Dell | OptiPlex Micro | 3050, 5050, 7040, 7050, 3060 |

---

## Budget Tiers

### Tier 1 — Ultra-budget (~250–350 PLN)

- **CPU target**: Intel Core 6th or 7th gen with **"T" suffix** (35 W TDP) — e.g. i5-6500T, i5-7500T
- **Examples**: HP EliteDesk 800 G3 Mini, Dell OptiPlex 5050 Micro, Lenovo M710q
- **Good for**: Ubuntu Server, Docker (tens of containers), Pi-hole, Home Assistant, simple databases, NAS

### Tier 2 — Sweet Spot (~450–600 PLN)

- **CPU target**: Intel Core **8th gen i5** — e.g. i5-8500T (**6 physical cores** vs 4 in older i5)
- **Examples**: HP ProDesk 400 G4 Mini, Dell OptiPlex 3060 Micro, Lenovo M720q
- **Why upgrade**: extra cores give headroom for virtualisation (Proxmox later); Intel UHD 630 iGPU with **QuickSync** for hardware video transcoding (Plex/Jellyfin)
- Allegro search keywords: `"i5-8500T Mini PC"`, `"OptiPlex Micro i5"`, `"ThinkCentre Tiny"`, `"ProDesk Mini"`

---

## Detailed Spec: Lenovo ThinkCentre M75q-2 Tiny — AMD Ryzen 3 PRO 4350GE

This model is a **strong alternative** to Intel 8th gen — AMD Zen 2 platform (7 nm TSMC).

### CPU Specs

| Parameter | Value |
|---|---|
| Architecture | Zen 2 (Renoir), 7 nm |
| Cores / Threads | 4C / 8T (SMT) |
| Base clock | 3.5 GHz |
| Boost clock | 4.0 GHz |
| L2 cache | 2 MB (512 KB/core) |
| L3 cache | 4 MB (shared) |
| TDP | 35 W (idle whole system typically <10 W) |
| Memory | DDR4 up to 3200 MHz, dual-channel |
| ECC support | Yes (PRO line; BIOS support varies) |

### Integrated GPU

| Parameter | Value |
|---|---|
| GPU | AMD Radeon Graphics (Vega 6) |
| Shader cores | 6 |
| GPU clock | 1700 MHz |

### M75q-2 vs Intel i5-8500T — Homelab Comparison

| Dimension | Ryzen 3 PRO 4350GE | Core i5-8500T |
|---|---|---|
| Cores / Threads | 4C / **8T** | **6C** / 6T |
| Concurrent workloads | ✅ More threads → better for many light containers | ✅ More cores → better for virtualisation |
| Lithography | ✅ 7 nm (more efficient) | 14 nm |
| Single-thread perf | ✅ Higher IPC (Zen 2) | Lower |
| Video transcoding | ⚠️ VAAPI/NVENC possible but Docker config more complex | ✅ Intel QuickSync — well supported by Plex/Jellyfin |
| Plex/Jellyfin HW transcode | ⚠️ Works, but setup more involved | ✅ Straightforward, widely documented |

**Recommendation**: if video transcoding is not a priority → M75q-2 Ryzen is excellent value and slightly more capable overall. If Plex/Jellyfin transcoding matters → prefer Intel 8th gen with QuickSync.

---

## Buying Checklist (Allegro)

- **RAM**: minimum 8 GB; strongly prefer 16 GB (ideally in one DIMM to leave a slot free)
- **Storage**: ensure SSD is included (NVMe M.2 preferred); avoid listings with no disk/OS unless you have a spare
- **PSU**: many budget listings omit the power brick; OEM PSU (HP/Dell/Lenovo) costs ~30–50 PLN extra — always check the listing description
- **Cooling**: before production use, open the case (usually tool-less), blow out dust, and consider replacing thermal paste (hardware is several years old)
