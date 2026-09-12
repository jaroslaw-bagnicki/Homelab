# 32 — Wincor Beetle M-III Hardware Diagnostic: Pre-Boot Audit (OpenMediaVault)

**Source**: SystemRescue 13.02 live session + hardinfo2 + dmidecode + smartctl + lspci, Sep 12 2026 ·
Issue [#98 — NAS build (Wincor Beetle M-III)](https://github.com/jaroslaw-bagnicki/Homelab/issues/98) ·
[Idea 01c — Homelab NAS: Wincor Beetle M-III](../ideas/01c-nas-backup-target-wincor-beetle.md) ·
[ADR 29 — NAS backup target (OMV)](../decisions/29-nas-backup-target-beetle-m3-omv.md)

**Scope**: Pre-boot hardware audit of the **Wincor Beetle M-III** POS terminal acquired as the
OpenMediaVault NAS backup target ([issue #98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98),
[ADR 29](../decisions/29-nas-backup-target-beetle-m3-omv.md)) — full hardware inventory and
SMART health before committing the OS. Same Phase 0 pattern as the
[Futro S930 audit (research 31)](31-futro-s930-hardware-diagnostic.md), the
[Wyse 5070 audit (research 29)](29-wyse5070-hardware-diagnostic.md), and the
[Wyse 3040 audit (research 28)](28-wyse3040-hardware-diagnostic.md).

**Status**: 🔨 In progress — platform, CPU, RAM, SSD, NIC, expansion, **all three drives** and the
**PSU/UPS** examined (2026-09-12); the unit is a **Skylake / H110 / DDR4 platform**. Pending:
BIOS walk, physical SATA ports, Memtest86+ ([Pending checks](#pending-checks)).

---

## Decision Summary

> **Decision authority:** [ADR 29](../decisions/29-nas-backup-target-beetle-m3-omv.md) — the
> Beetle M-III is the homelab NAS backup target running OpenMediaVault, succeeding the ML110.
> This research doc is the Phase 0 hardware audit output that grounds that decision. It confirms
> the platform — **Skylake / H110 / LGA1151 / DDR4, Pentium G4400, AES-NI, QuickSync H.264+HEVC
> decode**, 8 GiB DDR4; the **BIOS configuration walk** remains, and the `sdc` reallocated-sector
> finding is resolved — **keep + monitor** (long self-test clean, count frozen).

| Decision | Outcome (as of 2026-09-12) |
|---|---|
| Hardware | WINCOR NIXDORF **BEETLE /MIII** — `POS system - B/MIII(M2) UPS IKEA BK` · SN `000000001750341761 59HYP23878` — **acquired** |
| Board | Product **`M2.0-H110-uATX`** (WINCOR NIXDORF `Motherboard_M2.0-H110-uATX_D3460`, Fujitsu D3460) — **Intel H110** · SN `000000001750340018 DA56P16387` · UUID `da743815-ba0e-11ec-8813-5d5362566515` |
| CPU | **Intel Pentium G4400** (Skylake, 2C/2T, 3.3 GHz, 3 MB L3; QuickSync H.264 + HEVC 8-bit decode; **AES-NI present**) — LGA1151 |
| RAM | **8 GiB (1× 8 GiB DDR4-2667 SODIMM @ 2133 MT/s)**, 2 slots, 1 free (max 32 GiB) |
| NIC | **Intel Ethernet Connection (2) I219-V** (`00:1f.6`, `e1000e`, MAC `00:01:2e:8e:14:0d`) — on-board GbE |
| SATA | Intel 100/C230 **SATA Controller [AHCI]** (`00:17.0`) — H110; physical port count pending |
| Disk 0 | **SanDisk X600** `SD9SB8W-128G` 128 GB 2.5" SATA SSD (`sda`) — **SMART PASSED** (41,802 POH) — cache |
| Disk 1 | **Seagate ST1000VT001-1RE172** 1 TB 2.5" (`sdb`, `WDES3KB7`) — **PASSED**, 0 reallocated, 65,545 POH |
| Disk 2 | **Seagate ST1000VT001-1RE172** 1 TB 2.5" (`sdc`, `WDEPBVR3`) — **PASSED** but **1,056 reallocated** (past media event; long self-test clean, count frozen at 1,056 — **keep + monitor**) — see [Storage](#storage-sata--smart) |
| USB | Kingston DataTraveler 3.0 64 GB (`sdd`) = Ventoy live USB, **not** a data drive |
| PSU | **AcBel `POF001-280G`** (UPS-integrated `PSU UPS BEETLE/M-III`, DN P/N `01750279900`, S/N `5421CP10JW`) — **250 W** (225 W @50 °C), **80 Plus Gold** |
| Dynamic IP | `192.168.2.158` (DHCP via mesh `192.168.2.1`) |

---

## Context

The lab's backup target is the **ML110 (idea 03)** — too noisy and power-hungry, due to be
retired. Idea 01c proposed a used **Wincor Beetle M-III** as its successor, explicitly chosen
over the EliteDesk 800 G1 (01b) for being a *modern* platform (H110/LGA1151/DDR4,
QuickSync-HEVC, mSATA, 4× 2.5" drives). [ADR 29](../decisions/29-nas-backup-target-beetle-m3-omv.md)
then settled the OS as **OpenMediaVault** and the storage as **mdadm RAID1**
(2× Seagate + SanDisk cache).

The unit was booted into **SystemRescue 13.02** (Ventoy USB) for the pre-wipe hardware audit —
the same Phase 0 pattern used for the Futro S930 (research 31), the Wyses (research 28/29), and
the ML110 (runbook 22 §3). The audit's purpose: capture exact specs into `docs/hardware.md` and
check for surprises **before** committing the OS.

---

## Hardware Findings (SystemRescue 13.02, 2026-09-12)

### System

| Field | Value |
|---|---|
| Product | WINCOR NIXDORF **BEETLE /MIII** — `POS system - B/MIII(M2) UPS IKEA BK` |
| Serial | `000000001750341761 59HYP23878` |
| Board | Product **`M2.0-H110-uATX`** — WINCOR NIXDORF `Motherboard_M2.0-H110-uATX_D3460` (Fujitsu **D3460**), SN `000000001750340018 DA56P16387` · UUID `da743815-ba0e-11ec-8813-5d5362566515` |
| BIOS | American Megatrends **`V5.0.0.12 R1.8.0 for D3460-D2x`**, dated **2021-11-22** (UEFI supported) |
| CPU | Intel **Pentium G4400** (Skylake, 6th gen, model 94) — 1 package, **2 cores / 2 threads**, 3300 MHz, **3 MB L3** — see [CPU](#cpu--security-notes) |
| RAM | **8 GiB** (1× 8 GiB DDR4 SODIMM), one slot free — see [RAM](#ram) |
| GPU | Intel Skylake-S GT1 **HD Graphics 510** (`00:02.0`, `i915`) — 350–1000 MHz |
| NIC | **Intel Ethernet Connection (2) I219-V** (`00:1f.6`, `e1000e`) — `enp0s31f6`, MAC `00:01:2e:8e:14:0d`, altname `enx00012e8e140d` |
| SATA | Intel 100/C230 Series **SATA Controller [AHCI mode]** (`00:17.0`, `ahci`) — H110; physical port count pending |
| USB | 1× xHCI (USB 3.0 `00:14.0`); PL2303 serial adapter + Rapoo wireless present in the live session |
| Audio | HDA Intel PCH — Realtek **ALC671** (`00:1f.3`) |
| Display | DP1 connected → **HP LA2206** 21.5" (1920×1080); HDMI1/HDMI2 disconnected |
| Sensors | pch_skylake 32 °C; package 30 °C; core 0 25 °C / core 1 30 °C (idle, live session) |
| Boot | SystemRescue 13.02, kernel `6.18.41-1-lts`, boot 2026-09-12 14:14 UTC |

### Chipset / platform

The PCI bus is a **Skylake-H110** arrangement:

- `00:00.0` Host bridge — **6th Gen Core (Skylake)** DRAM Controller
- `00:1f.0` ISA bridge — **Intel H110** LPC/eSPI Controller
- `00:17.0` SATA — 100/C230 Series AHCI

This is a **Skylake / H110 / LGA1151 / DDR4** platform — a newer generation than the
EliteDesk 800 G1 (idea 01b, Haswell/Q87/DDR3).

### CPU / Security notes

- Intel **Pentium G4400** — Skylake, 2C/2T (no Hyper-Threading), 3.3 GHz, 3 MB L3, **54 W**
  TDP class. Min/current clocks 800 / 3300 MHz. Processor ID `506E3` (model 94, stepping 3),
  microcode `0xf0`. **AES-NI — present** (`aes` flag in `lscpu` — the modern cryptographic
  accelerator, used by LUKS/restic). **VT-x — Enabled** (`vmx` flag; `kvm_intel` loaded).
  **VT-d / IOMMU — pending the BIOS walk**; the memory map exposes `dmar0`/`dmar1` units, so
  the hardware may be present even though H110 nominally omits VT-d.
- **QuickSync** — Skylake GT1 (HD Graphics 510) supports **H.264** and **HEVC 8-bit decode**
  (no HEVC encode).
- CPU vulnerabilities — modern mitigations present (PTI, IBRS, MDS clear, etc.); fine for a
  24/7 NAS behind the edge ingress (ADR 08/24).

### RAM

- **1× 8 GiB DDR4 SODIMM** — populated at **DIMM CHB4** (BANK 2); **DIMM CHA3 empty**.
  Rated **2667 MT/s**, configured **2133 MT/s**, 1.2 V, rank 1, 64-bit,
  Synchronous Unbuffered (Unregistered). Vendor `04CB`, SN `6DEB0500`.
- **2 slots total, max 32 GiB** (2× 16 GiB).
  One slot free → a second stick is a straight upgrade.
- usable `MemTotal` **7,956,684 KiB (~7.6 GiB)** after iGPU reservation. **8 GB is already
  above Unraid's floor and ample for OMV + mdadm**; a 2nd 8/16 GB stick is optional later.

### Storage (SATA + SMART)

Inventoried **3 SATA devices + 1 USB boot stick** on 2026-09-12; **no M.2/NVMe device**.

| Device | Model | SN | Size | SATA link | SMART | Notes |
|---|---|---|---|---|---|---|
| `sda` | SanDisk **X600** (`SD9SB8W-128G`) | `191702804011` | 128 GB (119.2 GiB) | 6.0 Gb/s | ✅ **PASSED** | 2.5" SSD, FW `X6107000` — **cache / boot** |
| `sdb` | Seagate **ST1000VT001-1RE172** | `WDES3KB7` | 1.00 TB | 6.0 Gb/s | ✅ **PASSED** | FW `SDC2`, 5400 rpm, 512e, **0 reallocated** — clean |
| `sdc` | Seagate **ST1000VT001-1RE172** | `WDEPBVR3` | 1.00 TB | 6.0 Gb/s | ⚠️ **PASSED** | FW `SDC1`, 5400 rpm, 512e, **1,056 reallocated** — see below |
| `sdd` | Kingston DataTraveler 3.0 | `E0D55EA573F0E791494E0C5F` | 57.8 GiB | USB | n/a | Ventoy live medium — not a data drive |

SMART detail:

- **SanDisk SSD (`sda`)** — overall **PASSED**; **0** reallocated/pending/uncorrectable;
  `Available_Reserved_Space` **100** (Pre-fail, threshold 4); `Media_Wearout_Indicator` 4070;
  **41,802 POH** (~4.8 yr) / 5,324 power cycles; temp 26 °C (min 18 / max 41); no error log;
  short self-test passed. **Healthy — reuse as the OMV cache / boot SSD.**
- **Seagate `sdb`** — overall **PASSED**; **0** reallocated / 0 pending / 0 uncorrectable;
  **65,545 POH** (~7.5 yr continuous); Start_Stop / Load_Cycle **9** each (always-on recorder
  signature); temp 28 °C; short self-test passed. **Clean — keep as a mirror member.**
- **Seagate `sdc` — ⚠️ anomaly (past media event, currently stable)** — overall **PASSED**;
  `Reallocated_Sector_Ct` = **1,056** (normalised **98** / threshold 10), **0** pending,
  **0** reallocation candidates, **65,545 POH**, temp 26–33 °C, short self-test passed.
  `smartctl -l error` + `smartctl -x` (2026-09-12):
  - **SMART error log: empty** (comprehensive + extended); Device Statistics show
    **1 historical `Reported Uncorrectable Error`** and **3 read-recovery attempts**;
    `Realloc. Candidate Logical Sectors = 0`.
  - **Auto Offline Data Collection is Disabled / never started** — the drive does **not** run
    background surface scans, so the 1,056 remaps came from explicit reads/writes.
  - **Confirmed timeline** — the pre-audit `smartctl -a` (2026-09-05 08:27) read **0 reallocated**,
    POH 65,536, and logged **"No self-tests have been logged"**; the audit then ran the drive's
    **first-ever full-surface `smartctl -t long`** and wrote **exactly 4 GiB** (`dd`: LBAs written
    369,533 → 8,758,141). By 2026-09-12 the count is **1,056** (POH 65,545). The diagnostic
    itself created the remaps; they were simply not re-read until 09-12.
  - SCT temperature history shows the drive powered across 2026-09-11/12 (21–49 °C).
  - **Long self-test (2026-09-12):** `Extended offline — Completed without error`,
    `LBA_of_first_error = -`; **count frozen at 1,056**, 0 pending, error log still empty.
  - **Read / decision:** a **past, one-time media event** (one uncorrectable read → 1,056
    sectors remapped), **not ongoing degradation** — 0 pending / 0 candidates and a clean
    full-surface test. Reallocations never reverse. **Decision: keep `sdc` as the RAID1 mirror
    member with `sdb` and monitor via SMART** (replace was the conservative alternative).

### Drive provenance & recording type (2× Seagate)

The 2× **ST1000VT001-1RE172** are Seagate **Video 2.5** (surveillance) drives — **CMR /
Perpendicular** (Seagate manual §2.3), **512e AF** (4096-byte physical), 5400 rpm. Both
previously completed an **extended self-test without error**; the 2026-09-12 re-check finds
**`sdb` still clean** while **`sdc` carries 1,056 reallocated sectors from a past media event**
([Storage](#storage-sata--smart)). That verification history is recorded on
[issue #98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98). **Array plan (ADR 29):**
**mdadm RAID1** across 2× 1 TB = **1 TB usable**; **`sdc` is kept and monitored** (long self-test clean).

### Network

| Field | Value |
|---|---|
| NIC | **Intel Ethernet Connection (2) I219-V** (`00:1f.6`, driver `e1000e`) |
| Interface | `enp0s31f6` · MAC `00:01:2e:8e:14:0d` · altname `enx00012e8e140d` |
| Address | `192.168.2.158/24` (DHCP via mesh gateway `192.168.2.1`, MAC `e8:65:d4:df:a5:20`) |

On-board 1 GbE on an **Intel** NIC (`e1000e`, the more NAS-friendly driver vs Realtek).
2.5 GbE remains gated on a switch upgrade.

### PCIe / expansion (dmidecode -t 9, 2026-09-12)

| Slot | Type | Width | Bus | Notes |
|---|---|---|---|---|
| **J6B2** | PCIe **3.0 x16** | x16 | `00:01.0` | CPU PEG — main expansion |
| **J6B1** | PCIe **2.0 x1** | x1 | `00:1c.3` | chipset |
| **J6D1** | PCIe **2.0 x1** | x1 | `00:1c.4` | chipset |

**3 PCIe slots:** 1× **PCIe 3.0 x16** (CPU PEG) + 2× **PCIe 2.0 x1**. The x16 is free for a
PCIe→M.2 NVMe cache adapter, a 2.5/10 GbE NIC, or a SATA HBA to expand the array. dmidecode
reports **no mini-PCIe/mSATA** slot on this board.
The `-uATX` M2.0 board provides **2× PCIe 2.0 x1** expansion slots.

### Power / thermals

| Field | Value |
|---|---|
| Thermals | pch 32 °C; package 30 °C; cores 25/30 °C (idle, live session) |
| CPU idle | ~800 MHz (power state) |
| **Idle power (measured)** | **14–16 W** settled (VRONE plug meter, 2026-09-12); ~**23–24 W** during/just after start (POST + spin-up transient), then drops |
| PSU | **AcBel `POF001-280G`** — `PSU UPS BEETLE/M-III` (UPS-integrated), DN P/N `01750279900`, S/N `5421CP10JW`, date `B2202` REV `E9`. **250 W** max @45 °C (225 W @50 °C), **80 Plus Gold**; 100–240 V input. Rails: +3.3 V 4.0 A · **+12.2 V 10.5 A** · +5.1 V 8.2 A · +12.0 V 1.5 A · +5 Vsb 2.3 A · +24.8 V 0.6 A · +19 VBat 6.0 A. +12 V ≈ 128 W — ample for 2× 2.5" HDDs + SSD |
| Cooling | **3 fans** — front-right (over CPU + PSU), one at the **PSU back**, one inside the **internal UPS module**; **43.7 dB(A)** measured with a **UNI-T UT353** (Gelid controller planned) |
| UPS battery | Internal **TOTEX International NiMH, 15.6 V 3000 mAh** (`first use 12/2022`, DN P/N `01750279901`) — **not OS-exposed** (`/sys/class/power_supply` empty), so a hardware nicety only; use a NUT-compatible external UPS for shutdown (idea 09) |

---

## Implications for issue #98

| Item | Finding |
|---|---|
| Platform | **Skylake / H110 / LGA1151 / DDR4** |
| CPU | **Pentium G4400** (2C/2T, 3.3 GHz) |
| RAM | **8 GiB DDR4** (1×8, 1 slot free, ≤32 GiB) |
| QuickSync | H.264 + HEVC 8-bit decode |
| SATA | Intel 100/C230 AHCI; **no mini-PCIe/mSATA**; port count pending |
| Array | **2× Seagate 1 TB** → mdadm RAID1 = 1 TB usable; `sdc` kept + monitored (long-test clean) |
| Cache | SanDisk X600 `SD9SB8W-128G` 128 GB SSD, PASSED |
| NIC | **Intel I219-V** GbE |
| Expansion | PCIe 3.0 x16 + 2× PCIe 2.0 x1 |

**Bottom line:** the Beetle M-III is a workable OMV NAS — a clear **platform and power** upgrade
over the ML110 (Skylake vs Core 2, DDR4 vs DDR2, SATA III vs II, ~14–16 W vs ~60–80 W idle).
Noise is comparable (43.7 vs 42–58 dB) with the Gelid controller planned to bring it down.
Phase 1 (OMV install + array) is the working direction
([ADR 29](../decisions/29-nas-backup-target-beetle-m3-omv.md)).

---

## Pending Checks

1. **`sdc` verdict** — ✅ **resolved 2026-09-12**: error log empty; the **long self-test
   (`Extended offline`) completed without error** and the count is **frozen at 1,056** (0
   pending, 0 realloc candidates) — see [Storage](#storage-sata--smart). **Decision: keep `sdc`
   in the RAID1 mirror with `sdb` and monitor via SMART** (replace was the conservative
   alternative).
2. **HDD SMART** — ✅ **done 2026-09-12**: `sdb` clean (0 reallocated); `sdc` anomaly as above;
   CMR confirmed (Seagate Video 2.5 = Perpendicular); both at 6.0 Gb/s.
3. **PSU label** — ✅ **done 2026-09-12**: **AcBel `POF001-280G`** (UPS-integrated), 250 W
   (225 W @50 °C), 80 Plus Gold, DN P/N `01750279900`, S/N `5421CP10JW`; rails recorded.
4. **BIOS walk** — SATA mode (**AHCI**), AES-NI toggle, **VT-x / VT-d**, **Restore AC Power
   Loss → [Last state]**, boot mode (UEFI).
5. **Physical SATA port count** + confirm the free port for array growth.
6. **Memtest86+** — one full pass on the 8 GB stick.
7. **Noise / cooling** — ✅ noise **43.7 dB(A)** (UNI-T UT353), **3 fans** (front-right CPU+PSU,
   PSU back, internal UPS module); outstanding: the Gelid fan controller plan.
8. **UPS OS-exposure** — ✅ **done 2026-09-12**: internal **TOTEX NiMH 15.6 V 3000 mAh**
   (`first use 12/2022`, DN P/N `01750279901`); not OS-exposed (no `power_supply`/SMBus fuel
   gauge) — hardware nicety only, external NUT UPS required (idea 09).

---

## Open Questions

1. **SATA port count** — H110 exposes 4× SATA III nominally; verify on the D3460 board
   (no mSATA slot was enumerated).
2. **RAM growth** — 1 slot free; 8 GB is ample for OMV, 16/32 GB optional later.
3. **Cache** — single SanDisk X600 SSD is not mirrored; fine for a backup landing cache
   (ADR 29 mdadm RAID1 is the data protection).
4. **Noise** — fit the Gelid controller (target ~32–35 dB).
5. **ML110 retirement timing** — keep the ML110 serving backups until the Beetle's array is
   verified, then retire.

---

## Comparison: ML110 vs Beetle (delivered)

| Dimension | **ML110 G5** (current OMV, retiring) | **Beetle — delivered** (this audit) |
|---|---|---|
| CPU | Pentium E2160 (Core 2, 2C/2T, ~1.8 GHz, 65 W) | **Pentium G4400** (Skylake, 2C/2T, 3.3 GHz, HEVC) |
| AES-NI / QuickSync | ✗ / ✗ | **✅ / H.264+HEVC decode** |
| RAM | 4 GB DDR2 (dead end) | **8 GB DDR4** (2 slots → 32 GB) |
| Chipset | ICH9R (LGA775) | **H110 (LGA1151)** |
| SATA | SATA II | 100/C230 AHCI (port count pending; no mSATA) |
| Storage (array) | ~750 GB usable (2× RAID1 pairs) | **1 TB** (2× Seagate, mdadm RAID1 — `sdc` kept; monitor) + SanDisk 128 GB cache |
| NIC | Broadcom BCM5722 | **Intel I219-V** |
| Expansion | modest | **PCIe 3.0 x16 + 2× x1** |
| PSU | HP tower (wattage n/c) | **AcBel `POF001-280G` 250 W, 80+ Gold** (UPS-integrated) |
| Noise | 42–58 dB | **43.7 dB(A)** measured (UT353) |
| Idle power | ~60–80 W | **14–16 W** measured (23–24 W start transient) |
| Footprint | full tower | ~9.7 L compact |
| OS | OMV + mdadm | **OMV + mdadm RAID1** (ADR 29) |
| Status | ✅ base for the existing OMV NAS | 🔨 diagnostic in progress, platform confirmed |

**Read:** the ML110 is the incumbent to retire (slow, power-hungry, noisy, Core 2 / DDR2 /
SATA II); the **delivered** Beetle is a clear upgrade over it (Skylake, DDR4, HEVC-decode
QuickSync, SATA III, ~14–16 W).

---

## References

- [Issue #98 — NAS build (Wincor Beetle M-III)](https://github.com/jaroslaw-bagnicki/Homelab/issues/98)
- [ADR 29 — NAS Backup Target — Wincor Beetle M-III (OpenMediaVault)](../decisions/29-nas-backup-target-beetle-m3-omv.md)
- [Idea 01c — Homelab NAS: Wincor Beetle M-III](../ideas/01c-nas-backup-target-wincor-beetle.md)
- [Idea 03 — NAS backup target ML110](../ideas/03-nas-backup-target-ml110.md) · [research 23](23-ml110-nas-omv.md) — the OMV baseline
- [Research 31 — Futro S930](31-futro-s930-hardware-diagnostic.md) · [29 — Wyse 5070](29-wyse5070-hardware-diagnostic.md) · [28 — Wyse 3040](28-wyse3040-hardware-diagnostic.md) — the audit pattern used here
- `docs/hardware.md` — node inventory
