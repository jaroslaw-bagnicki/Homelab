# 32 — Wincor Beetle M-III Hardware Diagnostic: Pre-Boot Audit (Unraid NAS)

**Source**: SystemRescue 13.02 live session + hardinfo2 + smartctl + lspci, Sep 05 2026 ·
Issue [#98 — NAS build (Wincor Beetle M-III)](https://github.com/jaroslaw-bagnicki/Homelab/issues/98) ·
[Idea 01c — Homelab NAS: Wincor Beetle M-III (Unraid)](../ideas/01c-nas-backup-target-wincor-beetle.md)

**Scope**: Pre-boot hardware audit of the newly acquired **Wincor Beetle M-III** POS terminal
(the planned Unraid NAS, [issue #98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98)) —
full hardware inventory and SMART health before committing an OS. Same Phase 0 pattern as the
[Futro S930 audit (research 31)](31-futro-s930-hardware-diagnostic.md), the
[Wyse 5070 audit (research 29)](29-wyse5070-hardware-diagnostic.md), and the
[Wyse 3040 audit (research 28)](28-wyse3040-hardware-diagnostic.md).

**Status**: ✅ Complete — platform, CPU, RAM, NIC, SATA, PCIe, PSU, SSD and disks inventoried and
checked; **drives verified CMR + PASSED extended self-test → keep the 2× Seagates** (array
decision resolved). **Major finding: the acquired unit is an H81 / Haswell / LGA1150 / DDR3 board
(`K2.1-H81-uATX`), NOT the H110 / Skylake / LGA1151 / DDR4 platform idea 01c assumed.** The idea's
core premises (DDR4, QuickSync-HEVC, mSATA, 4-drive array) **do not hold** on this box. Only
pre-install follow-ups remain ([Pending checks](#pending-checks)).

---

## Decision Summary

> **Decision authority:** the Unraid-on-Beetle direction is still an **idea** —
> [Idea 01c](../ideas/01c-nas-backup-target-wincor-beetle.md). No ADR yet. This research doc is
> the Phase 0 hardware audit output. It **invalidates Idea 01c's platform premise** (this is a
> Haswell/H81 box, not Skylake/H110) and **confirms the disks are healthy (CMR, extended-test
> clean)**, so the box is at least a workable small NAS — but the "modern platform" rationale
> that motivated Idea 01c over the EliteDesk (01b) no longer applies.

| Decision | Outcome (as of 2026-09-05) |
|---|---|
| Hardware | WINCOR NIXDORF **BEETLE /MIII** — "System unit BEETLE/M-III K2 KMAT sw" · SN `000000001750261682 53R0455744` — **acquired** |
| Board | **`K2.1-H81-uATX`** (WINCOR NIXDORF "Kit Motherboard_K2.1-H81-uATX", SN `000000001750296310 8D625Z8071`) — **Intel H81** chipset |
| CPU | **Intel Pentium G3420** (Haswell, 2C/2T, 3.2 GHz, 3 MB L3, 53 W, QuickSync-H.264; AES-NI disabled) — LGA1150 |
| RAM | **4 GiB (1× 4 GiB DDR3-1600 SODIMM)**, 2 slots, 1 free (≤16 GB → 8 GB = +1 stick); 2-slot/1-free confirmed |
| NIC | **Intel Ethernet I217-V** (`00:19.0`, `e1000e`, MAC `00:01:2e:86:11:0c`) — on-board GbE |
| SATA | H81 **4-port AHCI** (2× SATA III 6 Gb/s + 2× SATA II 3 Gb/s) — no mSATA/NVMe/M.2 **device**; a **mini-PCIe (mSATA-capable) slot** exists, empty |
| Disk 0 | **SanDisk X600** (SD9SB8W-128G) 128 GB 2.5" SATA SSD (`sda`) — **SMART PASSED** (45,577 POH) — cache |
| Disk 1 | **Seagate ST1000VT001-1RE172** 1 TB 2.5" 5400 (`sdb`, `WDES3KB7`) — **CMR**, SMART PASSED, **extended self-test clean** (65,536 POH) |
| Disk 2 | **Seagate ST1000VT001-1RE172** 1 TB 2.5" 5400 (`sdc`, `WDEPBVR3`) — **CMR**, SMART PASSED, **extended self-test clean** (65,536 POH), negotiating SATA II |
| USB | Kingston DataTraveler 3.0 64 GB (`sdd`) = Ventoy live USB, **not** a data drive |
| PSU | **AcBel 250 W, 80 Plus Gold** (Wincor `01750279900`) |
| Dynamic IP | `192.168.2.241` (DHCP via mesh `192.168.2.1`) |

---

## Context

The lab's backup target is the **ML110 (idea 03)** — too noisy and power-hungry, due to be
retired. Idea 01c proposed a used **Wincor Beetle M-III** as its Unraid successor, explicitly
chosen over the EliteDesk 800 G1 (01b) for being a *modern* platform (H110/LGA1151/DDR4,
QuickSync-HEVC, 3×SATA + mSATA, 4× 2.5" drives). The box arrived and was booted into
**SystemRescue 13.02** (Ventoy USB) for the pre-wipe hardware audit — the same Phase 0 pattern
used for the Futro S930 (research 31), the Wyses (research 28/29), and the ML110 (runbook 22
§3). The audit's purpose: capture exact specs into `docs/hardware.md` and check for surprises
**before** committing an OS. The primary surprise is that the unit is **Haswell/H81/DDR3**, not
Skylake/H110/DDR4.

---

## Hardware Findings (SystemRescue 13.02, 2026-09-05)

### System

| Field | Value |
|---|---|
| Product | WINCOR NIXDORF **BEETLE /MIII** — `System unit BEETLE/M-III K2 KMAT sw` |
| Serial | `000000001750261682 53R0455744` |
| Board | `K2.1-H81-uATX` — WINCOR NIXDORF `Kit Motherboard_K2.1-H81-uATX`, SN `000000001750296310 8D625Z8071` |
| BIOS | American Megatrends **`WN STD 07/16`**, dated **2018-12-19** |
| CPU | Intel **Pentium G3420** (Haswell, 4th gen) — 1 package, **2 cores / 2 threads**, 3200 MHz, **3 MB L3** — see [CPU](#cpu--security-notes) |
| RAM | **4 GiB** (1× 4 GiB DDR3-1600 SODIMM), one slot free — see [RAM](#ram) |
| GPU | Intel Xeon E3-1200 v3/4th Gen Core Integrated Graphics (`00:02.0`, `i915`) — Haswell HD |
| NIC | **Intel Ethernet Connection I217-V** (`00:19.0`, `e1000e`) — `enp0s25`, MAC `00:01:2e:86:11:0c`, altname `enx00012e86110c` |
| SATA | Intel 8 Series/C220 **6-port SATA Controller 1 [AHCI mode]** (`00:1f.2`) — H81, **4 physical ports** |
| USB | 1× xHCI (USB 3.0 `00:14.0`) + 2× EHCI (USB 2.0 `00:1a.0` / `00:1d.0`) |
| Audio | HDA Intel PCH — Realtek **ALC662** codec (`00:1b.0`) |
| Display | VGA1 connected → **HP LA2206** 21.5" (1920×1080); HDMI1/HDMI2 disconnected |
| Boot | SystemRescue 13.02, kernel `6.18.41-1-lts`, boot 2026-09-05 08:06 UTC |

### Chipset / platform (the build-critical finding)

The PCI bus is a **Haswell-H81** arrangement, not Skylake-H110:

- `00:00.0` Host bridge — **4th Gen Core (Haswell)** DRAM Controller
- `00:1f.0` ISA bridge — **Intel H81 Express LPC Controller**
- `00:1f.2` SATA — 8 Series/C220 AHCI

This means idea 01c's Platform row (**H110 / LGA1151 / DDR4**) is **wrong** for this unit — it
is **H81 / LGA1150 (Haswell) / DDR3**, the **same generation as the EliteDesk 800 G1 (idea 01b)**
that idea 01c was explicitly chosen over. DMI reports the CPU socket as "BGA1155" — an oddity;
the G3420 is a socketed desktop **LGA1150** Haswell part (confirmed by the Haswell host bridge +
H81 chipset). Treat "BGA1155" as a Wincor/firmware string quirk, not an upgrade blocker.

### CPU / Security notes

- Intel **Pentium G3420** — Haswell 4th gen, 2C/2T (no Hyper-Threading), 3.2 GHz, 3 MB L3,
  53 W. Idle clocks ~798 MHz; ~29–32 °C package (idle). Processor ID `306C3` (stepping C0),
  **microcode 25**, GT1 iGPU (700 MHz), ME FW **9.1.40.1000** (1.5 MB). **VT-x** —
  [Enabled] in CPU Configuration (`kvm_intel` loaded) · **VT-d** — [Enabled].
- **AES-NI — NOT present and NOT toggleable** (confirmed 2026-09-05): the `aes` flag is absent in
  both `lscpu` and `/proc/cpuinfo`, no `aes`/`vmx` in dmesg, and the **CPU Configuration menu
  exposes no Intel AES-NI option** → **firmware-masked** on this POS board (Haswell has it in
  silicon, but the Wincor firmware doesn't expose a toggle). Consequence: no HW AES acceleration
  for encrypted backup targets (restic/LUKS) — CPU-bound AES (minor; the ML110 lacks it too).
  **QuickSync — H.264 only**: Haswell does **not** hardware-encode/decode **H.265/HEVC**. Idea
  01c's "QuickSync (H.264/H.265 8-bit decode)" is partially wrong — transcoding is H.264-only.
- Security: modern mitigations present (PTI, Retpolines, etc.); fine for a 24/7 NAS behind the
  edge ingress (ADR 08/24). AES-NI confirmation now **resolved: absent**.

### CPU & chipset — offer vs received

> The offer (idea 01c, from the Allegro listing / Gemini threads) assumed a **Skylake** platform.
> The received unit is **Haswell**. Both are entry-level 2-core Pentium + PCH platforms; the
> differences below matter little for a **backup-only NAS** but do undercut the idea-01c
> "modern platform" claim.

**CPU**

| | Offer — Pentium **G4400** | Received — Pentium **G3420** |
|---|---|---|
| Generation / node | Skylake 6th gen, 14 nm | Haswell 4th gen, 22 nm |
| Socket | LGA1151 | LGA1150 |
| Cores / threads | 2C / 2T | 2C / 2T |
| Base clock | 3.3 GHz | 3.2 GHz |
| L3 cache | 3 MB | 3 MB |
| TDP | 51 W | 53 W |
| iGPU | Intel HD 510 (12 EU) | Intel HD (10 EU) |
| **QuickSync** | H.264 + **HEVC decode** | **H.264 only** |
| AES-NI / AVX2 | ✅ | **❌ AES-NI disabled** (AVX2 ✅) |
| Memory | DDR4 (dual-ch) | DDR3 (dual-ch) |

**Chipset**

| | **H110** (offer) | **H81** (received) |
|---|---|---|
| Platform | LGA1151 / Skylake | LGA1150 / Haswell |
| Memory | DDR4 | DDR3 |
| SATA | 4× **SATA III** (6 Gb/s) | **2× III + 2× II** |
| USB 3.0 | 6 | 2 |
| USB 2.0 | 6 | 8 |
| GbE / RAID / PCH PCIe | 1× GbE · no HW RAID · 6× PCIe 2.0 | 1× GbE · no HW RAID · 6× PCIe 2.0 |

**Net effect for a NAS:** CPU is effectively a **wash** (both 2C/2T low-power; G4400's only edge is
HEVC transcoding, irrelevant for a backup target). Chipset is a **minor step down** (H81 has 2×
SATA II and 2× USB 3.0) — but 2× SATA II is **not a bottleneck** for 5400 rpm HDDs (~140 MB/s),
and USB 3.0 count is irrelevant. The real deltas from the offer remain **platform age (Haswell vs
Skylake), DDR3 / 4 GB vs DDR4 / 8 GB, and no installed mSATA** (a mini-PCIe mSATA slot does exist).
> ⚠️ The hardinfo/DMI fields "Socket BGA1155" and "Max Frequency 3800 MHz" for the G3420 are
> firmware quirks — the real socket is **LGA1150** (Haswell), base **3.2 GHz**; ignore them.

### RAM

- **1× 4 GiB DDR3-1600** SODIMM (vendor `1322`, part `XW1638N4GMPP-DB`, rank 1, 1.5 V,
  64-bit) — populated at **ChannelB-DIMM0**; **ChannelA-DIMM0 empty**.
- **2 slots total; ≤16 GB** (2× 8 GB DDR3-1600). Idea 01c's "4× DIMM DDR4, 32 GB+" does **not**
  apply (DDR3, 2 slots, 16 GB ceiling).
- **4 GiB is at the Unraid floor** (Unraid generally wants ≥ 8 GB). **8 GB = add a 2nd 4 GiB
  DDR3-1600 SODIMM** (cheap) — recommended before/at the Unraid install.

### Storage (SATA + SMART)

H81 exposes 4 physical SATA ports (2× SATA III 6 Gb/s + 2× SATA II 3 Gb/s). Inventoried 3 SATA
devices (+1 USB boot stick); **no mSATA/NVMe/M.2 device installed** (confirmed via `lsblk` +
`lspci -vv`), though a **mini-PCIe (mSATA-capable) slot** (`MINIPCIE1`) is present but empty:

| Device | Model | Size | SATA link | SMART | Notes |
|---|---|---|---|---|---|
| `sda` | SanDisk **X600** (SD9SB8W-128G) | 128 GB (119.2 GiB) | 6.0 Gb/s | ✅ **PASSED** | 2.5" SSD, FW `X6107000`, SN `192124802192` |
| `sdb` | Seagate **ST1000VT001-1RE172** | 1.00 TB (931.5 GiB) | 6.0 Gb/s | ✅ **PASSED** | Seagate **Video 2.5** (surveillance) — 2.5" 5400 rpm, FW `SDC2`, SN `WDES3KB7` |
| `sdc` | Seagate **ST1000VT001-1RE172** | 1.00 TB (931.5 GiB) | **3.0 Gb/s** | ✅ **PASSED** | Seagate **Video 2.5** (surveillance) — 2.5" 5400 rpm, FW `SDC1`, SN `WDEPBVR3` — on a **SATA II** port |
| `sdd` | Kingston DataTraveler 3.0 | 57.8 GiB | USB | n/a | Ventoy live medium — not a data drive |

SMART detail:

- **SanDisk SSD (`sda`)** — overall **PASSED**; **0** reallocated/pending/uncorrectable;
  `Available_Reserved_Space` **100** (Pre-fail, threshold 4); `Media_Wearout_Indicator` 3048;
  **45,577 POH** (~5.2 yr) / 2,022 cycles; temp 28 °C (min 18 / max 44); no error log; short
  self-test passed. **Healthy — reuse as Unraid cache** (matches idea 01c's "reuse the included
  128 GB SSD").
- **Seagate `sdb`** — overall **PASSED**; **0** reallocated/pending/uncorrectable;
  **65,536 POH (~7.5 yr continuous)** with only **4** power cycles / 4 start-stop / 4 load-cycles
  → the signature of an **always-on recorder/DVR drive**, not a laptop pull (laptop drives spin
  down constantly and accrete thousands of load cycles); temp 33 °C.
- **Seagate `sdc`** — same as `sdb`: **PASSED**, 0 bad sectors, **65,536 POH**, temp 31 °C; only
  difference is the link negotiating at **3.0 Gb/s** (SATA II port — re-seat to a SATA III port
  for 6 Gb/s; not a drive fault).

### Recording type & drive provenance (2026-09-05)

- **Recording type — CMR (PMR), confirmed by Seagate's manual.** The Video 2.5 spec §2.3
  "Recording and Interface Technology" states **"Recording method: Perpendicular"** →
  **Perpendicular Magnetic Recording (PMR)**, the recording tech behind conventional **CMR**.
  (SMR is a shingled *variant* of PMR that Seagate would label "Shingled Magnetic Recording"; with
  2 heads / 1 disc and a moderate ~1320 Gb/in² areal density, this is PMR/CMR, not shingled.)
  Third-party reseller "SMR" labels are therefore **contradicted by the authoritative spec**.
  **Empirical confirmation:** `dd` rewrite-in-place (4 GiB, `conv=fsync`, 2026-09-05) on
  **`sdb` = 138 MB/s** and **`sdc` = 132 MB/s** — no collapse when overwriting already-written
  sectors (a sequential-append test alone is inconclusive: SMR is also fast on fresh streams; the
  in-place-rewrite test is the discriminator). POH counter verified **live** (65536 → 65537 over
  the running self-test), so the ~7.5 yr figure is genuine.
- **Provenance / offer conflict.** The drives are **Seagate Video 2.5** (`ST1000VT001` — a
  surveillance/DVR-streaming drive family). The Allegro offer described them as *"removed from
  high-budget laptops"* and listed `ST1000VT001` alongside laptop models `ST1000LM035`/`LM049`.
  The **SMART contradicts the laptop claim**: 65,536 POH with only 4 power/load cycles is
  **always-on recorder** behaviour, not laptop use. Either the provenance is misdescribed or the
  drive class was mislabelled — relevant to the offer-vs-received discrepancy on issue #98.

**Extended SMART self-test — PASSED on both (2026-09-05):** `# 1 Extended offline,
Completed without error, LBA_of_first_error = -` on `sdb` and `sdc`. → **drive decision resolved:
keep the 2× Seagates** (CMR + SMART clean + full-surface scan clean). The `LifeTime(hours)` field
shows `4`/`5` — a Seagate 16-bit wrap quirk at 65,536 h, not real age (attribute 9 still ~65,537).
The WD10JUCX plan is dropped (fallback only if a Seagate later degrades).

### Drive power specs (Seagate Video 2.5 manual)

Authoritative (Table 4 `DC Power Requirements`, +5 V): the **1.0 A figure is spin-up (startup)
max only** — operating draw is far lower and is what drives monthly energy:

| State | 1-disk model | 2-disk model |
|---|---|---|
| Spin-up (max) | **1.00 A** | 1.00 A |
| Write average | 1.70 W | 1.80 W |
| Read average | 1.60 W | 1.70 W |
| Idle, low power mode | **0.45 W** | 0.50 W |
| Standby / Sleep | **0.13 W** | 0.13 W |
| Max sustained OD read | **140 MB/s** | |

Start/stop (Table 3): power-on→ready 2.8–3.0 s, standby→ready 2.5–3.0 s — fine for spin-down.
Measured 138 MB/s ≈ the 140 MB/s spec (validates the drive).

**Effect on power estimate:** during an active backup each drive draws ~1.6–1.8 W (≈3.4 W for 2
drives); once the drive enters its **low-power idle** (0.45–0.50 W, after a short inactivity
timeout) the two drives drop to **~0.9–1.0 W**, and in full **standby/spin-down** to **~0.26 W**.
So with Unraid disk spin-down the HDDs are no longer the dominant idle consumer — idle is then
dominated by the platform + SSD + PSU (~8–12 W).

### Storage plan implication

- **Cache** — SanDisk **X600** 128 GB SSD (healthy).
- **Array — DECIDED: 2× Seagate → 1 parity + 1 data = 1 TB usable** (CMR, deep-test clean). Not
  idea 01c's 4× = 3 TB. **RAM**: 2 SODIMM slots, **1 free** → 8 GB = add a **2nd 4 GB DDR3-1600
  1.5 V** stick (pre-install follow-up). To reach 4-drive (idea 01c's shape): the board has **1 free
  physical SATA port**; adding 2 more 2.5" drives requires a **PCIe SATA card / HBA** in the empty
  x16 slot (or dropping to 3× 2.5").

### Network

| Field | Value |
|---|---|
| NIC | **Intel Ethernet I217-V** (`00:19.0`, driver `e1000e`) |
| Interface | `enp0s25` · MAC `00:01:2e:86:11:0c` · altname `enx00012e86110c` |
| Address | `192.168.2.241/24` (DHCP via mesh gateway `192.168.2.1`, MAC `e8:65:d4:df:a5:20`) |

Idea 01c said "on-board 1 GbE (keep)" — confirmed, and on an **Intel** NIC (`e1000e`, the more
nas-friendly driver vs Realtek). 2.5 GbE remains gated on a switch upgrade (idea 01c unchanged).

### PCIe / expansion (dmidecode -t 9, 2026-09-05)

| Slot | Type | Width | Bus | Notes |
|---|---|---|---|---|
| **PCIE1** | PCIe **3.0 x16** | x16 | `00:01.0` | CPU PEG — main expansion (empty) |
| **PCIE2** | PCIe **2.0 x1** | x1 | `00:1c.1` | chipset |
| **PCIE3** | PCIe **2.0 x1** | x1 | `00:1c.2` | chipset |
| **MINIPCIE1** | PCIe **2.0 x1** | mini-PCIe | `00:04.0` | **mSATA-capable** |

**4 PCIe slots:** 1× **PCIe 3.0 x16** (CPU PEG) + 2× **PCIe 2.0 x1** + 1× **mini-PCIe (mSATA) 2.0
x1**. The x16 (`PCIE1`) is empty — its lane is for a PCIe→M.2 NVMe cache adapter, a 2.5/10 GbE NIC,
or a SATA HBA to expand the array. **`MINIPCIE1` gives an mSATA path** (idea 01c's "1× mSATA"
option is actually viable — slot present, just unpopulated; no M.2/NVMe slot exists). More slots
than idea 01c's assumed "1× x16 + 1× x1".

### Power / thermals

| Field | Value |
|---|---|
| Thermals | acpitz 27.8/29.8 °C; package 32 °C; cores 29 °C (idle, live session) |
| CPU idle | ~798 MHz (power state) |
| PSU | **AcBel** (Wincor `01750279900`, "PSU UPS BEETLEM-III" L427) — **250 W** max (225 W @ 50 °C), **80 PLUS Gold**, 100–240 V input; SN `5427C4B78`. Rails: +3.3V 4.0A · +5V 10.5A (52.5 W) · +12V 8.2A (98.4 W) · +5Vsb 1.5A. **Confirms idea 01c's "industrial 80 Plus Gold" premise** (brand is AcBel, not FSP/Fortron). The +5V rail is ample for the 2× 2.5" HDDs + SSD |
| Noise (measured) | **42.5 dB front / 42.0 dB back @ 30 cm** (UNI-T UT353) — uniformly ~42–42.5 dB, matches idea 01c's "~42–45 dB stress" / "44 dB" |
| Cooling | **3 fans**: (1) right-front pushing air over the **CPU + PSU**, (2) rear at the **PSU end**, (3) inside the **UPS/battery unit**. Corrects idea 01c's "one radial tunnel turbine" model. **Gelid Fan Speed Controller** is the recorded noise-reduction step (target ~32–35 dB, keep TACH on the board, don't go below ~30 dB) |
| UPS battery | Internal **VOTEX 15.6 V, 3000 mAh** (Wincor Nixdorf UPS) — **proprietary, not OS-exposed** (SMBus `i2c-6` = DIMM SPD + RTC only; no `power_supply`/ACPI/USB-HID), **not NUT-usable** — hardware nicety only |

---

## Implications for Idea 01c / issue #98

| Idea 01c expectation | Actual finding | Verdict |
|---|---|---|
| H110, LGA1151, 6th gen | **H81, LGA1150 (Haswell)** | ❌ **wrong generation** |
| CPU G4400 (Skylake) | **Pentium G3420** (Haswell) | ❌ Haswell (older) |
| 4× DIMM **DDR4**, 32 GB | 1× 4 GiB **DDR3-1600**, 2 slots, ≤16 GB | ❌ DDR3, 4 GB |
| QuickSync **H.264/H.265** | QuickSync **H.264 only** (Haswell) | ⚠️ H.265/HEVC absent |
| 3× SATA III + **1× mSATA** | **mini-PCIe (mSATA-capable) slot present, empty**; no NVMe/M.2; H81 4-port AHCI | ⚠️ mSATA slot (empty) ✅ path |
| 4× 2.5" HDD array | **2× Seagate 1 TB** (+ 1 free SATA port) | ⚠️ 1 TB usable, not 3 TB |
| reuse 128 GB SSD as cache | SanDisk **X600** 128 GB SSD (SD9SB8W-128G), **PASSED** | ✅ matches |
| 2× WD 1 TB purchase | unit came with **2× Seagate 1 TB** | ✅ no purchase needed |
| on-board 1 GbE | **Intel I217-V** | ✅ Intel (≥ expectation) |
| PSU industrial FSP 220–300 W | **AcBel 250 W, 80 Plus Gold** (Wincor `01750279900`) | ✅ matches (brand = AcBel, same class) |
| Chosen over EliteDesk (01b) for "modern" | **same Haswell/DDR3 generation as 01b** | ❌ rationale weakened |

**Bottom line:** the box is a healthy, workable small Unraid NAS — **but it is a Haswell/H81/DDR3
platform, effectively the same generation as the EliteDesk 800 G1 that idea 01c was chosen
against.** Idea 01c's central premise (a modern Skylake/DDR4/mSATA box) is invalidated, and the
idea's "modern platform" rationale no longer holds (the received unit is same-gen as 01b). The
**drives are verified good (CMR, extended-self-test clean)** and the array decision is **resolved
toward the Seagates**; proceeding as the Unraid successor to the ML110 is the working direction
(captured on issue #98).

---

## Pending Checks

1. **PSU label** — ✅ **resolved 2026-09-05**: **AcBel 250 W, 80 Plus Gold** (Wincor `01750279900`,
   SN `5427C4B78`); +5V 10.5A rail ample for the drives. Matches idea 01c's industrial-Gold premise.
2. **RAM decision** — ✅ **resolved 2026-09-05**: **8 GB = add a 2nd 4 GB DDR3-1600 1.5 V SODIMM**
   (2 slots, 1 free confirmed; ≤16 GB). Do at the Unraid install.
3. **Extended SMART self-test** — ✅ **resolved 2026-09-05**: both Seagates `# 1 Extended offline,
   Completed without error, LBA_of_first_error = -`. Do not need to re-run.
4. **Re-seat `sdc`** to a SATA III port (currently 3.0 Gb/s) if 6 Gb/s is wanted.
5. **AES-NI** — ✅ **resolved 2026-09-05: NOT present / firmware-masked** (`aes` flag absent in
   `lscpu` + `/proc/cpuinfo`; **no BIOS toggle in CPU Configuration** → not re-enableable — accept;
   minor: software AES for an encrypted backup target).
6. **Physical SATA port count** — verify 4 ports on the H81 board (2× III + 2× II) & the free
   port, to size the array-add path.
7. **Memory test** (e.g. `/usr/sbin/memtest` or a live memtest pass) — validate the 4 GiB stick.
8. **AC power-loss behavior** — ✅ **set 2026-09-05: BIOS "Restore AC Power Loss" → [Last state]**
   (was Power Off), VT-x [Enabled], VT-d [Enabled]; ME FW 9.1.40.1000. So the NAS returns to its
   prior power state after a cut (and stays on).

---

## Open Questions

1. **Direction** — working decision: proceed as Unraid NAS on this Haswell/H81/DDR3 unit. Idea
   01c's "modern, beats the EliteDesk" rationale is gone (same-gen as 01b) — the box is used
   anyway and the drives are verified good. Confirm as Phase 1.
2. **Storage scope** — ✅ **resolved 2026-09-05**: **2× Seagate → 1 parity + 1 data = 1 TB** + SanDisk
   X600 cache. (To grow later, add a PCIe SATA HBA in the x16 slot; the board has 1 free SATA port.)
3. **ML110 retirement timing** — idea 01c (and idea 03) target retiring the ML110; keep it until
   the Beetle array is verified and holds the backup?
4. **Cache mirror** — idea 01c open Q: single SanDisk cache isn't parity-protected until Mover
   flushes (mirror if the backups are critical); still applies (only 1 SSD present).
5. **Noise** — **3 fans** (front CPU+PSU, rear PSU-end, UPS-unit) contributed to the measured
   **42.5 dB @ 30 cm**. Gelid controller (idea 01c): confirm which fan(s) it slows, whether it
   needs a multi-head/splitter, and that the PSU-end + UPS fans are controllable (UPS fan may be
   sealed). Target ~32–35 dB; keep TACH on the board; don't drop below ~30 dB (heatsink airflow).
- ✅ **UPS battery — resolved 2026-09-05: proprietary / firmware-managed, NOT OS-exposed, NOT
  NUT-usable.** Inspected via SMBus (`/dev/i2c-6` = i801 SMBus `00:1f.3`): only system-standard
  chips respond — `0x52` = **DDR3 DIMM SPD** (`XW1638N4GMPP-DB` = the 4 GB stick), `0x44` = an
  **RTC/clock**, plus board-level monitors (`0x08`/`0x18`/`0x32`). No smart-battery fuel gauge. OS
  checks confirm no `/sys/class/power_supply`, no ACPI battery, no USB-HID UPS. → the internal
  **VOTEX 15.6 V 3000 mAh** is a **hardware nicety only**; use a **NUT-compatible external UPS** for
  shutdown/power-loss protection on the NAS.

---

## Comparison: ML110 vs Beetle (anticipated/planned) vs Beetle (acquired)

| Dimension | **ML110 G5** (current OMV, retiring) | **Beetle — anticipated/planned** (idea 01c / Allegro offer) | **Beetle — acquired** (this audit) |
|---|---|---|---|
| CPU | Pentium E2160 (Core 2, 2C/2T, ~1.8 GHz, 65 W) | Pentium **G4400** (Skylake, 2C/2T, 3.3 GHz, 51 W, **HEVC**) | Pentium **G3420** (Haswell, 2C/2T, 3.2 GHz, 53 W, H.264-only) |
| AES-NI / QuickSync | ✗ / ✗ | ✅ / H.264+HEVC | **❌ AES-NI disabled** (likely BIOS) / H.264 |
| RAM | 4 GB DDR2 (dead end) | **8 GB DDR4** | **4 GB DDR3** (2 slots → 8 GB) |
| Chipset | ICH9R (LGA775) | H110 (LGA1151) | H81 (LGA1150) |
| SATA | SATA II | 4× SATA III + mSATA | 2× SATA III + 2× SATA II; mini-PCIe mSATA (empty) |
| Storage (array) | ~750 GB usable (2× RAID1 pairs); 1 TB spare offline | **4× 2.5" ≈ 3 TB** + SSD cache | **1 TB** (2× Seagate, data+parity) + SanDisk X600 128 GB cache |
| NIC | Broadcom BCM5722 | 1 GbE | Intel I217-V |
| Expansion | modest | x16 + x1 | **PCIe 3.0 x16 + 2× x1 + mini-PCIe** |
| PSU | HP tower (wattage n/c) | FSP/Fortron 80+ Gold 220–300 W | **AcBel 250 W, 80+ Gold** |
| Idle power | ~60–80 W | ~15–25 W | ~24 W |
| Noise | 42–58 dB | ~35–38 dB | 42.5 dB → Gelid ~32–35 dB |
| Footprint | full tower | ~9.7 L compact | ~9.7 L compact |
| OS | OMV + mdadm | Unraid (planned) | Unraid (planned) |
| Status | ✅ base for the existing OMV NAS | — (what was described/paid for) | 🔨 diagnostic complete, array decided |

**Read:** the ML110 is the incumbent to retire (slow, power-hungry, noisy, Core 2 / DDR2 / SATA II).
The **anticipated** Beetle (idea 01c based on the Allegro offer) is the ideal — Skylake, 8 GB DDR4,
4-drive/3 TB, HEVC, SATA III + mSATA. The **acquired** Beetle is a real downgrade from that offer
(Haswell/H81/DDR3, 4 GB, 1 TB, AES-NI disabled, no installed mSATA, H.264-only) — the basis for the
seller-discount request — **but it is still a clear upgrade over the ML110** on every axis that
matters (modern Haswell vs Core 2, DDR3 vs DDR2, SATA III vs II, ~1/3 the power, quiet with the
Gelid controller, ~half the footprint, PCIe headroom, Unraid's add-a-drive model).

**Verdict:** keep the Beetle as the ML110's NAS successor. The offer→acquired gap warrants a
**seller discount (~80–100 PLN ask)**, but it does **not** change the replacement decision.

---

## References

- [Issue #98 — NAS build (Wincor Beetle M-III): initial hardware diagnostics + Unraid setup](https://github.com/jaroslaw-bagnicki/Homelab/issues/98)
- [Idea 01c — Homelab NAS: Wincor Beetle M-III (Unraid)](../ideas/01c-nas-backup-target-wincor-beetle.md) — platform + storage rationale (now partially invalidated)
- [Idea 03 — NAS backup target ML110](../ideas/03-nas-backup-target-ml110.md) — the retiring box this is meant to succeed
- [Idea 01b — NAS backup target EliteDesk 800 G1](../ideas/01b-nas-backup-target-elitedesk.md) — the same-generation alternative it was chosen over
- [Research 31 — Futro S930 hardware diagnostic](31-futro-s930-hardware-diagnostic.md) · [Research 29 — Wyse 5070](29-wyse5070-hardware-diagnostic.md) · [Research 28 — Wyse 3040](28-wyse3040-hardware-diagnostic.md) — the audit pattern used here
- `docs/hardware.md` — node inventory (to be updated)
