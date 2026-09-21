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
**PSU/UPS** examined (2026-09-12); the unit is a **Skylake / H110 / DDR4 platform**. **BIOS walked
2026‑09‑21** ([BIOS walk](#bios-walk)) — VT-d, the 5-port SATA map and the firmware/boot-mode picture
are settled. Pending: Memtest86+ ([Pending checks](#pending-checks)).

---

## Decision Summary

> **Decision authority:** [ADR 29](../decisions/29-nas-backup-target-beetle-m3-omv.md) — the
> Beetle M-III is the homelab NAS backup target running OpenMediaVault, succeeding the ML110.
> This research doc is the Phase 0 hardware audit output that grounds that decision. It confirms
> the platform — **Skylake / H110 / LGA1151 / DDR4, Pentium G4400, AES-NI, QuickSync H.264+HEVC
> decode**, 8 GiB DDR4; the **BIOS walk is done** ([BIOS walk](#bios-walk)), and the `sdc`
> reallocated-sector finding is resolved — **keep + monitor** (long self-test clean, count frozen).

| Decision | Outcome (as of 2026-09-12) |
|---|---|
| Hardware | WINCOR NIXDORF **BEETLE /MIII** — `POS system - B/MIII(M2) UPS IKEA BK` · SN `000000001750341761 59HYP23878` — **acquired** |
| Board | Product **`M2.0-H110-uATX`**, board rev **`D3460-D22`** (WINCOR NIXDORF `Motherboard_M2.0-H110-uATX_D3460`, Fujitsu D3460) — **Intel H110** · SN `000000001750340018 DA56P16387` · UUID `da743815-ba0e-11ec-8813-5d5362566515` |
| CPU | **Intel Pentium G4400** (Skylake, 2C/2T, 3.3 GHz, 3 MB L3; QuickSync H.264 + HEVC 8-bit decode; **AES-NI + VT-x + VT-d**, all `Enabled` in BIOS) — LGA1151 |
| RAM | **8 GiB (1× 8 GiB DDR4-2667 SODIMM @ 2133 MT/s)**, 2 slots — **CHB2 populated, CHA1 free** (max 32 GiB) |
| NIC | **Intel Ethernet Connection (2) I219-V** (`00:1f.6`, `e1000e`, MAC `00:01:2e:8e:14:0d`) — on-board GbE |
| SATA | Intel 100/C230 **SATA Controller [AHCI]** (`00:17.0`) — H110; **5 ports** (3 standard + mSATA + M.2), and **no BIOS SATA-mode setting** (AHCI-only) |
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
| Board | Product **`M2.0-H110-uATX`**, board rev **`D3460-D22`** — WINCOR NIXDORF `Motherboard_M2.0-H110-uATX_D3460` (Fujitsu **D3460**), SN `000000001750340018 DA56P16387` · UUID `da743815-ba0e-11ec-8813-5d5362566515` |
| BIOS | AMI **core `5.0.0.12`**, rev **`R1.8.0`** — `D3460-D22`, dated **2021-11-22** (Aptio `2.18.1263`, Platform `Retail`, **UEFI 2.5 / PI 1.4** compliant). **Boot mode `LEGACY`**; all four CSM OpROM policies `Legacy only` and `IGFX GOP = N/A`, so the video path is legacy — see [BIOS walk](#bios-walk) |
| CPU | Intel **Pentium G4400** (Skylake, 6th gen, model 94) — 1 package, **2 cores / 2 threads**, 3300 MHz, **3 MB L3**, patch ID `506E3` / `000000EA` — see [CPU](#cpu--security-notes) |
| RAM | **8 GiB** (1× 8 GiB DDR4 SODIMM @ 2133 MT/s) — **CHB2 populated, CHA1 free** — see [RAM](#ram) |
| GPU | Intel Skylake-S GT1 **HD Graphics 510** (`00:02.0`, `i915`) — 350–1000 MHz |
| NIC | **Intel Ethernet Connection (2) I219-V** (`00:1f.6`, `e1000e`) — `enp0s31f6`, MAC `00:01:2e:8e:14:0d`, altname `enx00012e8e140d` |
| SATA | Intel 100/C230 Series **SATA Controller [AHCI mode]** (`00:17.0`, `ahci`) — H110, **5 ports**: SATA 0 *white* / 1 *blue* / 2 *black* all occupied, plus **mSATA (3) + M.2 (4)** empty — see [PCIe / expansion](#pcie--expansion) |
| ME / TPM | Intel ME **`11.8.83.3874`** — `Advanced → AMT Configuration` exposes the version **only**, so there is no provisioned AMT (the "no out-of-band management" assumption holds); Intel **PTT** (firmware TPM) is the selected device but `Disabled`, no security device found |
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
  microcode `0xf0` (`lscpu`) / patch ID `000000EA` (BIOS). **AES-NI — present** (`aes` flag in
  `lscpu`; the BIOS also exposes a **`CPU AES` toggle, `Enabled`**) — the modern cryptographic
  accelerator, used by LUKS/restic. **VT-x — Enabled** (`vmx` flag; `kvm_intel` loaded).
  **VT-d — present and `Enabled`** (BIOS `Advanced → CPU Configuration`), consistent with the
  `dmar0`/`dmar1` units in the memory map — H110's reputation notwithstanding. No IOMMU workload is
  planned, but the option is there.
- **QuickSync** — Skylake GT1 (HD Graphics 510) supports **H.264** and **HEVC 8-bit decode**
  (no HEVC encode).
- CPU vulnerabilities — modern mitigations present (PTI, IBRS, MDS clear, etc.); fine for a
  24/7 NAS behind the edge ingress (ADR 08/24).

### RAM

- **1× 8 GiB DDR4 SODIMM** — populated in **DIMM CHB2**; **DIMM CHA1 empty**. (`dmidecode` reported
  the pair as `CHB4`/`CHA3`; the BIOS's own labels — and the silkscreen — are **CHB2/CHA1**, and
  **CHA1 is the slot to fill**.)
  Rated **2667 MT/s**, configured **2133 MT/s**, 1.2 V, rank 1, 64-bit,
  Synchronous Unbuffered (Unregistered). Vendor `04CB`, SN `6DEB0500`.
- **2 slots total, max 32 GiB** (2× 16 GiB).
  One slot free → a second stick is a straight upgrade.
- usable `MemTotal` **7,956,684 KiB (~7.6 GiB)** after iGPU reservation. **8 GB is already
  above Unraid's floor and ample for OMV + mdadm**; a 2nd 8/16 GB stick is optional later.

### Storage (SATA + SMART)

Inventoried **3 SATA devices + 1 USB boot stick** on 2026-09-12, occupying **SATA ports 0–2** of a
**5-port** controller; the **mSATA and M.2 ports were empty** (BIOS walk, 2026‑09‑21).

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

**3 PCIe slots:** 1× **PCIe 3.0 x16** (CPU PEG) + 2× **PCIe 2.0 x1** — all free, and `Drive
Configuration` reports *no offboard controller present*. The x16 takes a 2.5/10 GbE NIC, an HBA, or
an NVMe cache adapter.

> **Correction (BIOS walk, 2026‑09‑21).** `dmidecode` reported no mini-PCIe/mSATA slot and this doc
> originally repeated that — but `Advanced → Drive Configuration` enumerates **5 SATA channels**: 0
> *white* (SanDisk SSD), 1 *blue* / 2 *black* (the two Seagates), plus **SATA 3 (mSATA)** and
> **SATA 4 (M.2)**, both *Not Installed*. Three caveats before treating that as two spare ports:
>
> - **`Not Installed` means *empty*, not *present*.** AMI builds that page from the PCH's port table,
>   so it can list a channel whose connector the OEM never fitted. **Confirm the sockets visually.**
> - **The M.2 entry is probably M.2 *SATA*, not NVMe** — it is listed under the SATA controller's own
>   configuration page beside the cabled ports, whereas an NVMe slot would be a PCIe device. Check
>   the keying (B / B+M vs M) before buying a module.
> - **All five usable at once is unproven.** H110 is the budget member of the 100-series family (the
>   6× SATA parts are B150/H170/Q170/Z170), so a muxed or shared lane is plausible — populating
>   mSATA could disable a cabled port. Settle it by testing, not by theory.
>
> None of this changes the build: the array stays on the two cabled Seagate ports and the OS on the
> SanDisk. The extra channels are a *possible* growth path, not a plan.

### Power / thermals

| Field | Value |
|---|---|
| Thermals | pch 32 °C; package 30 °C; cores 25/30 °C (idle, live session) |
| CPU idle | ~800 MHz (power state) |
| **Idle power (measured)** | **14–16 W** settled (VRONE plug meter, 2026-09-12); ~**23–24 W** during/just after start (POST + spin-up transient), then drops |
| PSU | **AcBel `POF001-280G`** — `PSU UPS BEETLE/M-III` (UPS-integrated), DN P/N `01750279900`, S/N `5421CP10JW`, date `B2202` REV `E9`. **250 W** max @45 °C (225 W @50 °C), **80 Plus Gold**; 100–240 V input. Rails: +3.3 V 4.0 A · **+12.2 V 10.5 A** · +5.1 V 8.2 A · +12.0 V 1.5 A · +5 Vsb 2.3 A · +24.8 V 0.6 A · +19 VBat 6.0 A. +12 V ≈ 128 W — ample for 2× 2.5" HDDs + SSD |
| Cooling | **3 fans** — front-right (over CPU + PSU), one at the **PSU back**, one inside the **internal UPS module**; **43.7 dB(A)** measured with a **UNI-T UT353** (Gelid controller planned). The BIOS `HW-Monitor` is **read-only — no fan control** on this board (tach: CPU `0 rpm`, PSU `1760 rpm`), so a hardware controller stays the only lever |
| UPS battery | Internal **TOTEX International NiMH, 15.6 V 3000 mAh** (`first use 12/2022`, DN P/N `01750279901`) — **not OS-exposed** (`/sys/class/power_supply` empty), so a hardware nicety only; use a NUT-compatible external UPS for shutdown (idea 09) |

---

## BIOS walk

Walked **2026‑09‑21** at the console (Aptio `2.18.1263`) — the Phase 0 firmware audit output. The
runbook that executes the install only needs the two settings that actually changed
([runbook 32 §1](../runbooks/32-beetle-m3-omv-setup.md)).

> **The menu paths are this board's own, not the generic AMI ones.** There is no `Advanced → SATA
> Configuration`; power settings live on the top-level **`Power`** tab and boot mode on the
> **`Boot`** tab. **No supervisor password is set**, and **Secure Boot does not exist** on this
> board — every CSM OpROM policy is `Legacy only`.

### Settings

| Screen | Setting | Value | Note |
|---|---|---|---|
| `Power` | Restore AC Power Loss | **`Last State`** | **changed** — was `Switch Off` |
| `Power → Wake-Up Resources` | LAN (Wake-on-LAN) | **`Enabled`** | **changed** — was `Disabled` |
| `Power → Wake-Up Resources` | Wake On LAN boot | `Boot Sequence` | already correct; `Force LAN Boot` would attempt PXE |
| `Power → Wake-Up Resources` | USB / PS/2 Keyboard, Wake On Time | `Disabled` | already correct |
| `Advanced → CPU Configuration` | Intel Virtualization Technology | `Enabled` | already correct |
| `Advanced → CPU Configuration` | **VT-d** | `Enabled` | **present here**, contrary to H110's reputation |
| `Advanced → CPU Configuration` | **CPU AES** | `Enabled` | the AES-NI toggle does exist on this platform |
| `Advanced → SMART Settings` | SMART Self Test | `Disabled` | a **POST-time self-test**, not SMART monitoring — leave off |
| `Advanced → Trusted Computing` | TPM Support | `Disabled` | Intel **PTT** (firmware TPM) is available if ever needed |
| `Boot` | Boot mode select | `LEGACY` | already the default — see below |
| `Boot` | Boot order | USB Key, then the SSD | already the default |

**There is no SATA-mode setting.** `Advanced → Drive Configuration` lists the five ports and nothing
else — no IDE/RAID/AHCI selector — yet the controller enumerates as AHCI and the `ahci` driver binds
(see [Storage](#storage-sata--smart)), so mdadm always sees raw disks.

**Left at their shipped values:** `Advanced → OEM Settings` (`RTC Lock`, `BIOS Lock`, `Max TOLUD
[Dynamic]`, `CPU Power Limit [Auto]`), `Security → Intrusion Switch [Disabled]` and `System Firmware
Update [Enabled]`, `Power → USB Power [Always Off]`, the `Power Control` buttons.

> ⚠ **Never set an HDD password.** `Security → HDD Security Configuration` offers one for the
> SanDisk SSD (ATA Security). On a disk that will carry the OS or join an mdadm array it is an
> unrecoverable foot-gun — leave it alone.

### Boot mode — `LEGACY`

Boot mode stays **`LEGACY`**, revised from the runbook's original UEFI target. The firmware *is*
UEFI capable (`Info` → Compliancy `UEFI 2.5; PI 1.4`), so this is a preference rather than a
limitation — what decides it is the **video path**: all four CSM OpROM policies are `Legacy only`
and `IGFX GOP Version` reads `N/A`, so a UEFI install risks an installer console with no framebuffer
and gains nothing, because OMV and mdadm are indifferent to boot mode. The choice has to be settled
**before** the install — changing it afterwards needs a bootloader repair or a reinstall.

### Wake-on-LAN is the recovery path

The board's AC input is fed by the **integrated Acbel UPS**, which rides through a mains loss on
battery. `Restore AC Power Loss` may therefore never observe an AC-loss event at all, and a
NUT-initiated shutdown could leave the NAS in soft-off with **no way back**. With `LAN = Enabled` it
can be woken over the network; validate against the battery re-test in
[issue #117](https://github.com/jaroslaw-bagnicki/Homelab/issues/117).

### RTC coin cell — replace it

The event log holds five entries, **all stamped `01/01/16 00:00:0x`** — the firmware's 2016 epoch,
i.e. the clock was invalid when they were written:

| Code | Severity | Description |
|---|---|---|
| `FJ 002E0001` | INFORMATIONAL | *Log Area Reset* |
| `FJ 0310B002` | CRITICAL | *POST — BIOS Settings reset occurred* |
| `FJ 0006000B` | CRITICAL | *POST — Bad RTC Battery* |
| `FJ 00090071` | CRITICAL | *POST — Invalid date/time* |
| `FJ 0006000B` | CRITICAL | *POST — Bad RTC Battery* |

Read together they are the five consequences of **one** CMOS/RTC reset (log cleared → settings lost
→ cell flagged → clock invalid) — not four independent critical POST failures.

The reset does not look ongoing: `Main → System Date & Time` reads **`Mon 09/21/2026 17:46`**
(weekday correct) and `VBAT` is **3.116 V**. That said, a correct clock is **not conclusive** on its
own — standby power sustains the RTC while the unit is plugged in, so the real test is an
*unplugged* power cycle.

**Replace the CR2032 anyway**, while the case is open: `Restore AC Power Loss` and `LAN` are exactly
what an RTC reset silently discards, and a flat cell would leave a headless NAS unable to
auto-recover. Check socketed vs soldered, then re-apply the two changed settings and clear the event
log so future events are unambiguous.

### Recorded

| Observation | Value |
|---|---|
| Board | `D3460-D22` — pins the audit's `D3460-D2x` |
| BIOS | core `5.0.0.12`, rev `R1.8.0`, built 2021‑11‑22 18:02:57, Aptio `2.18.1263`, Platform `Retail`, **UEFI 2.5 / PI 1.4** compliant; `Access Level: Administrator` |
| SATA ports | **5** — 0 *white* = SanDisk, 1 *blue* / 2 *black* = the two Seagates, plus **mSATA (3) and M.2 (4)**, both empty. `Offboard Controller Configuration` = *no controller present* |
| ME firmware | `11.8.83.3874`; `Advanced → AMT Configuration` shows the version **only** — no provisioned AMT, so the "no out-of-band management" assumption holds |
| TPM | Intel **PTT** selected, `Disabled`, no security device found |
| Fans | **CPU `0 rpm`**, PSU `1760 rpm` — the front-right fan is not on the CPU header. `HW-Monitor` is **read-only — no fan control**, so the Gelid controller stays the only noise lever |
| Temps | graphics 23 °C, PECI CPU0 31 °C (idle) |
| VBAT | 3.116 V — healthy for a coin cell |
| Memtest86+ | **pending** — one full pass on the 8 GB stick |

---

## Implications for issue #98

| Item | Finding |
|---|---|
| Platform | **Skylake / H110 / LGA1151 / DDR4** |
| CPU | **Pentium G4400** (2C/2T, 3.3 GHz) |
| RAM | **8 GiB DDR4** (1×8, 1 slot free, ≤32 GiB) |
| QuickSync | H.264 + HEVC 8-bit decode |
| SATA | Intel 100/C230 AHCI-only; **5 ports** — 3 standard (all occupied) + mSATA + M.2 free |
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
4. **BIOS walk** — ✅ **done 2026‑09‑21** ([BIOS walk](#bios-walk)):
   **no SATA-mode setting exists** (AHCI-only); `CPU AES`, `VT-x` and **`VT-d`** all `Enabled`;
   **`Restore AC Power Loss = Last State`** and **Wake-on-LAN `Enabled`**; boot mode stays
   **`LEGACY`** (video OpROMs are legacy-only, `IGFX GOP = N/A`); no Secure Boot, no AMT provisioning.
5. **Physical SATA port count** — ✅ **done 2026‑09‑21**: **5 ports** — 3 standard, all occupied,
   plus **mSATA and M.2 free**. Confirm the connectors are physically fitted.
6. **Memtest86+** — one full pass on the 8 GB stick. **Still pending.**
7. **Noise / cooling** — ✅ noise **43.7 dB(A)** (UNI-T UT353), **3 fans** (front-right CPU+PSU,
   PSU back, internal UPS module); outstanding: the Gelid fan controller plan.
8. **UPS OS-exposure** — ✅ **done 2026-09-12**: internal **TOTEX NiMH 15.6 V 3000 mAh**
   (`first use 12/2022`, DN P/N `01750279901`); not OS-exposed (no `power_supply`/SMBus fuel
   gauge) — hardware nicety only, external NUT UPS required (idea 09).
9. **RTC coin cell** — the event log holds **5 entries, all at the 2016 epoch**, and together they
   describe **one** CMOS/RTC reset: *Log Area Reset* → *BIOS Settings reset occurred* → *Bad RTC
   Battery* ×2 → *Invalid date/time*. The reset does **not** look ongoing — the clock now reads
   `Mon 09/21/2026 17:46` (weekday correct) and `VBAT` is 3.116 V. **Replace the CR2032 anyway**
   while the case is open: `Last State` and WoL are exactly what an RTC reset discards. Note the
   correct date is not conclusive on its own — standby power sustains the RTC while plugged in.

---

## Open Questions

1. **SATA port count** — ✅ **resolved 2026‑09‑21**: **5 ports** — 3 standard (all occupied by the
   SanDisk SSD and the two Seagates) plus **mSATA and M.2**, both empty. Two free storage ports, not
   the four-port H110 baseline this doc assumed.
2. **RAM growth** — **1 slot free (CHA1)**; 8 GB is ample for OMV, 16/32 GB optional later.
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
| SATA | SATA II | 100/C230 AHCI-only — 5 ports (3 standard + mSATA + M.2) |
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
- [Runbook 32 — Beetle M-III Phase 1: OMV setup, RAID, fleet enrollment](../runbooks/32-beetle-m3-omv-setup.md) — the install / RAID / enrollment procedure
- [Research 31 — Futro S930](31-futro-s930-hardware-diagnostic.md) · [29 — Wyse 5070](29-wyse5070-hardware-diagnostic.md) · [28 — Wyse 3040](28-wyse3040-hardware-diagnostic.md) — the audit pattern used here
- `docs/hardware.md` — node inventory
