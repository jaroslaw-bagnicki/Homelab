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

**Status**: 🟡 Complete with caveats — platform, CPU, RAM, NIC, SATA and disks inventoried and
checked. **Major finding: the acquired unit is an H81 / Haswell / LGA1150 / DDR3 board
(`K2.1-H81-uATX`), NOT the H110 / Skylake / LGA1151 / DDR4 platform idea 01c assumed.** The
idea's core premises (DDR4, QuickSync-HEVC, mSATA, 4-drive array) **do not hold** on this box;
a direction decision is pending ([Implications](#implications-for-idea-01c--issue-98)). PSU
label + memory test still pending.

---

## Decision Summary

> **Decision authority:** the Unraid-on-Beetle direction is still an **idea** —
> [Idea 01c](../ideas/01c-nas-backup-target-wincor-beetle.md). No ADR yet. This research doc is
> the Phase 0 hardware audit output. It **invalidates Idea 01c's platform premise** (this is a
> Haswell/H81 box, not Skylake/H110) and **confirms the disks are healthy**, so the box is at
> least a workable small NAS — but the "modern platform" rationale that motivated Idea 01c over
> the EliteDesk (01b) no longer applies.

| Decision | Outcome (as of 2026-09-05) |
|---|---|
| Hardware | WINCOR NIXDORF **BEETLE /MIII** — "System unit BEETLE/M-III K2 KMAT sw" · SN `000000001750261682 53R0455744` — **acquired** |
| Board | **`K2.1-H81-uATX`** (WINCOR NIXDORF "Kit Motherboard_K2.1-H81-uATX", SN `000000001750296310 8D625Z8071`) — **Intel H81** chipset |
| CPU | **Intel Pentium G3420** (Haswell, 2C/2T, 3.2 GHz, 3 MB L3, 53 W, AES-NI, QuickSync-H.264) — LGA1150 |
| RAM | **4 GiB (1× 4 GiB DDR3-1600 SODIMM)**, 2 slots, 1 free (≤16 GB) — see [RAM](#ram) |
| NIC | **Intel Ethernet I217-V** (`00:19.0`, `e1000e`, MAC `00:01:2e:86:11:0c`) — on-board GbE |
| SATA | H81 **4-port AHCI** (2× SATA III 6 Gb/s + 2× SATA II 3 Gb/s) — **no mSATA / NVMe / M.2** |
| Disk 0 | **SanDisk SD9SB8W128G** 128 GB 2.5" SATA SSD (`sda`) — **SMART PASSED** (45,577 POH) — cache |
| Disk 1 | **Seagate ST1000VT001-1RE172** 1 TB 2.5" 5400 (`sdb`, `WDES3KB7`) — **SMART PASSED** (65,536 POH) |
| Disk 2 | **Seagate ST1000VT001-1RE172** 1 TB 2.5" 5400 (`sdc`, `WDEPBVR3`) — **SMART PASSED** (65,536 POH), negotiating SATA II |
| USB | Kingston DataTraveler 3.0 64 GB (`sdd`) = Ventoy live USB, **not** a data drive |
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
  53 W. Idle clocks ~798 MHz; ~29–32 °C package (idle). **VT-x present** (`kvm_intel` loaded).
- **AES-NI** — present (Haswell family; `kvm_intel`/gaches loaded). **QuickSync — H.264 only**:
  Haswell does **not** hardware-encode/decode **H.265/HEVC**. Idea 01c's "QuickSync (H.264/H.265
  8-bit decode)" is partially wrong — transcoding is H.264-only on this box.
- Security: modern mitigations present (PTI, Retpolines, etc.); fine for a 24/7 NAS behind the
  edge ingress (ADR 08/24). `grep -o aes /proc/cpuinfo` is the formal confirmation (pending).

### RAM

- **1× 4 GiB DDR3-1600** SODIMM (vendor `1322`, part `XW1638N4GMPP-DB`, rank 1, 1.5 V,
  64-bit) — populated at **ChannelB-DIMM0**; **ChannelA-DIMM0 empty**.
- **2 slots total; ≤16 GB** (2× 8 GB DDR3-1600). Idea 01c's "4× DIMM DDR4, 32 GB+" does **not**
  apply (DDR3, 2 slots, 16 GB ceiling).
- **4 GiB is at the Unraid floor** (Unraid generally wants ≥ 8 GB). **8 GB = add a 2nd 4 GiB
  DDR3-1600 SODIMM** (cheap) — recommended before/at the Unraid install.

### Storage (SATA + SMART)

H81 exposes 4 physical SATA ports (2× SATA III 6 Gb/s + 2× SATA II 3 Gb/s). Inventoried 3 SATA
devices (+1 USB boot stick); **no mSATA, no NVMe, no M.2 anywhere** (confirmed via `lsblk` +
`lspci -vv`):

| Device | Model | Size | SATA link | SMART | Notes |
|---|---|---|---|---|---|
| `sda` | SanDisk **SD9SB8W128G** | 128 GB (119.2 GiB) | 6.0 Gb/s | ✅ **PASSED** | 2.5" SSD, FW `X6107000`, SN `192124802192` |
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

- **Recording type — CMR-like (empirical).** `dd` rewrite-in-place on `sdb` (4 GiB, `conv=fsync`)
  sustained **138 MB/s** — no collapse when overwriting already-written sectors → behaves like
  **CMR**, not SMR. (A sequential-append test alone is inconclusive: SMR is also fast on fresh
  sequential streams; the in-place-rewrite test is the discriminator.)
- **Provenance / offer conflict.** The drives are **Seagate Video 2.5** (`ST1000VT001` — a
  surveillance/DVR-streaming drive family). The Allegro offer described them as *"removed from
  high-budget laptops"* and listed `ST1000VT001` alongside laptop models `ST1000LM035`/`LM049`.
  The **SMART contradicts the laptop claim**: 65,536 POH with only 4 power/load cycles is
  **always-on recorder** behaviour, not laptop use. Either the provenance is misdescribed or the
  drive class was mislabelled — relevant to the offer-vs-received discrepancy on issue #98.

Both 1 TB Seagates have **no SMART self-test logged** — run an **extended self-test**
(`smartctl -t long /dev/sdb` ≈158 min, `/dev/sdc` ≈165) before trusting them in the array;
also repeat the `dd` in-place-rewrite test on `sdc` (only `sdb` was tested).

### Storage plan implication

- **Cache** — SanDisk 128 GB SSD (healthy).
- **Array** — **2 drives → 1 parity + 1 data = 1 TB usable** (not idea 01c's 4× = 3 TB).
- To reach 4-drive (idea 01c's shape): the board has **1 free physical SATA port**; adding 2 more
  2.5" drives requires a **PCIe SATA card / HBA** in the empty x16 slot (or dropping to 3× 2.5").

### Network

| Field | Value |
|---|---|
| NIC | **Intel Ethernet I217-V** (`00:19.0`, driver `e1000e`) |
| Interface | `enp0s25` · MAC `00:01:2e:86:11:0c` · altname `enx00012e86110c` |
| Address | `192.168.2.241/24` (DHCP via mesh gateway `192.168.2.1`, MAC `e8:65:d4:df:a5:20`) |

Idea 01c said "on-board 1 GbE (keep)" — confirmed, and on an **Intel** NIC (`e1000e`, the more
nas-friendly driver vs Realtek). 2.5 GbE remains gated on a switch upgrade (idea 01c unchanged).

### PCIe / expansion

`lspci -vv` enumerates **only** onboard devices — the **PCIe x16 slot is empty** (no NIC/HBA).
This is the lane for: PCIe→M.2 NVMe cache adapter, a 2.5/10 GbE NIC, or a SATA HBA to expand the
array (idea 01c's "1× x16 + 1× x1" expansion claim — slot present but unpopulated).

### Power / thermals

| Field | Value |
|---|---|
| Thermals | acpitz 27.8/29.8 °C; package 32 °C; cores 29 °C (idle, live session) |
| CPU idle | ~798 MHz (power state) |
| AC/PSU | **label not captured** — pending check (idea 01c expects industrial FSP/Fortron 220–300 W) |

---

## Implications for Idea 01c / issue #98

| Idea 01c expectation | Actual finding | Verdict |
|---|---|---|
| H110, LGA1151, 6th gen | **H81, LGA1150 (Haswell)** | ❌ **wrong generation** |
| CPU G4400 (Skylake) | **Pentium G3420** (Haswell) | ❌ Haswell (older) |
| 4× DIMM **DDR4**, 32 GB | 1× 4 GiB **DDR3-1600**, 2 slots, ≤16 GB | ❌ DDR3, 4 GB |
| QuickSync **H.264/H.265** | QuickSync **H.264 only** (Haswell) | ⚠️ H.265/HEVC absent |
| 3× SATA III + **1× mSATA** | **No mSATA / NVMe / M.2**; H81 4-port AHCI | ❌ no mSATA |
| 4× 2.5" HDD array | **2× Seagate 1 TB** (+ 1 free SATA port) | ⚠️ 1 TB usable, not 3 TB |
| reuse 128 GB SSD as cache | SanDisk 128 GB SSD, **PASSED** | ✅ matches |
| 2× WD 1 TB purchase | unit came with **2× Seagate 1 TB** | ✅ no purchase needed |
| on-board 1 GbE | **Intel I217-V** | ✅ Intel (≥ expectation) |
| PSU industrial FSP 220–300 W | label TBD | ⏳ pending |
| Chosen over EliteDesk (01b) for "modern" | **same Haswell/DDR3 generation as 01b** | ❌ rationale weakened |

**Bottom line:** the box is a healthy, workable small Unraid NAS — **but it is a Haswell/H81/DDR3
platform, effectively the same generation as the EliteDesk 800 G1 that idea 01c was chosen
against.** Idea 01c's central premise (a modern Skylake/DDR4/mSATA box) is invalidated. The
decision to proceed as the Unraid successor to the ML110, or to reconsider, is **not settled**
(see [Open Questions](#open-questions)) and is captured on issue #98.

---

## Pending Checks

1. **PSU label** — wattage/voltage on the industrial PSU (idea 01c expects 220–300 W).
2. **RAM decision** — 4 GiB (Unraid floor) vs add a 2nd 4 GiB DD3-1600 SODIMM → 8 GB (recommended).
3. **Extended SMART self-test** on both Seagates (`smartctl -t long /dev/sdb` `/dev/sdc`) —
   verify no latent bad sectors before array formation (~7.5 yr runtime).
4. **Re-seat `sdc`** to a SATA III port (currently 3.0 Gb/s) if 6 Gb/s is wanted.
5. **`grep -o aes /proc/cpuinfo`** — formal AES-NI confirmation (expected present on Haswell).
6. **Physical SATA port count** — verify 4 ports on the H81 board (2× III + 2× II) & the free
   port, to size the array-add path.
7. **Memory test** (e.g. `/usr/sbin/memtest` or a live memtest pass) — validate the 4 GiB stick.

---

## Open Questions

1. **Direction** — proceed as Unraid NAS on this Haswell/H81/DDR3 unit, or reconsider the
   platform? Idea 01c's "modern, beats the EliteDesk" rationale is gone; the box is now same-gen
   as 01b.
2. **Storage scope** — 1 TB (parity+data) + SSD cache now, or add drives (needs a PCIe SATA
   HBA for a 4th, or drop to 3× 2.5")?
3. **ML110 retirement timing** — idea 01c (and idea 03) target retiring the ML110; keep it until
   the Beetle array is verified and holds the backup?
4. **Cache mirror** — idea 01c open Q: single SanDisk cache isn't parity-protected until Mover
   flushes (mirror if the backups are critical); still applies (only 1 SSD present).
5. **Noise** — factory tunnel turbine + Gelid controller (idea 01c): confirm the Haswell G3420
   (53 W) and 2× 5400 rpm drives stay cool at the ~32–35 dB target under parity-check load.

---

## References

- [Issue #98 — NAS build (Wincor Beetle M-III): initial hardware diagnostics + Unraid setup](https://github.com/jaroslaw-bagnicki/Homelab/issues/98)
- [Idea 01c — Homelab NAS: Wincor Beetle M-III (Unraid)](../ideas/01c-nas-backup-target-wincor-beetle.md) — platform + storage rationale (now partially invalidated)
- [Idea 03 — NAS backup target ML110](../ideas/03-nas-backup-target-ml110.md) — the retiring box this is meant to succeed
- [Idea 01b — NAS backup target EliteDesk 800 G1](../ideas/01b-nas-backup-target-elitedesk.md) — the same-generation alternative it was chosen over
- [Research 31 — Futro S930 hardware diagnostic](31-futro-s930-hardware-diagnostic.md) · [Research 29 — Wyse 5070](29-wyse5070-hardware-diagnostic.md) · [Research 28 — Wyse 3040](28-wyse3040-hardware-diagnostic.md) — the audit pattern used here
- `docs/hardware.md` — node inventory (to be updated)
