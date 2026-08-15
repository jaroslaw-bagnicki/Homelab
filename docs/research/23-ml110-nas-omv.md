# 23 — ML110 NAS (OMV): Hardware & Software Research

**Source**: SystemRescue 13.02 live session + hardinfo2 report + `smartctl` scans, Aug 08 2026 · Issue [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54)
**Scope**: Repurposing the retired HP ProLiant ML110 G5 as the homelab NAS backup target — hardware findings, controller topology, disk health, and the RAID/boot/OS trade-offs.

---

## Decision Summary

> **Decision authority:** the decisions below are authoritatively recorded in
> [ADR 23 — NAS on the HP ProLiant ML110 (OMV)](../decisions/23-nas-on-ml110.md).
> This table is the Phase 0 analysis output that fed them.

| Decision | Outcome |
|---|---|
| Platform | HP ProLiant **ML110 G5** (already owned) — beats buying a Fujitsu Q956 |
| OS | **OpenMediaVault 8.x** (Debian 13), official ISO, BIOS boot |
| Filesystem / RAID | **No ZFS** — **mdadm RAID1** + XFS/ext4 |
| Boot device | **Goodram C40 120 GB SSD on ICH9 SATA #5**|
| Data pool | `md0` = 2× 500 GB Hitachis (mirror), `md1` = 2× 250 GB (mirror) |
| Bulk volume | **1 TB WD10EZEX — offline (decided 2026-08-15)**; content reviewed via SystemRescue, not documented (personal data, public repo) |
| Hardware RAID controller | **Not used** (Dell SAS 6/iR / SAS1068E) — removed |

---

## Why the ML110 over the Q956

| Factor | Q956 (idea 01) | ML110 (this build) | Verdict |
|---|---|---|---|
| Acquisition cost | ~195 PLN (used) + new drives + caddy | **0 PLN** (already owned) | ML110 wins — no purchase |
| Form factor | USFF, ~1.9 L, near-silent | 4U tower, louder, larger | Q956 wins on footprint/noise |
| Drive count | 2× 500 GB 2.5" | **4× 3.5" + 2× 2.5" 20 GB + 120 GB SSD + spare 1 TB** | ML110 wins — more capacity/redundancy |
| CPU | i5-6500T (4C/4T) | Intel Pentium E2160 @ 1.8 GHz (2C/2T) | Q956 wins on compute |
| RAM | 8 GB DDR3L | **4 GB** (2× 2 GiB DDR2-800) | Q956 wins; 4 GB fine for mdadm |
| SATA topology | 2× native SATA + M.2 | ICH9R 4-port + ICH9 2-port + **Dell SAS 6/iR (RAID-only)** | ML110 more complex |
| Boot device | needs USB or SSD M2 disk | **Goodram 120 GB SSD** — 6× capacity of the 20 GB drives | Boot device decided |
| Power consumption (est.) | ~20 W idle / ~40 W load (i5-6500T 35 W TDP, 2× 2.5" HDDs) | **~80 W idle / ~130 W load** (E2160 65 W TDP, 4× 3.5" HDDs) | Q956 wins — ~€40–45/yr vs ~€150–200/yr |

**Decision**: ML110 is owned, has 6 drives, and needs no purchase. Tower footprint is acceptable for a machine near the router/switch. **Proceed with ML110.**

---

## Hardware Findings (SystemRescue, 2026-08-08)

### System

| Field | Value |
|---|---|
| Generation | **ML110 G5** (DMI product string, board by Wistron) |
| CPU | Intel Pentium Dual E2160 @ 1.8 GHz, 2 cores (LGA775) |
| RAM | **4 GB** = 2× 2 GiB **DDR2-800 ECC** (Samsung), slots DIMM1+DIMM3, 2 free |
| ECC | **Single-bit ECC** — bonus for data integrity |
| BIOS | HP **O15**, 2009-09-10 |
| GPU | Matrox **G200e [Pilot]** (ServerEngines onboard console video) → 1024×768 cap |
| LO100 / IPMI | **Not available** — LO100 expansion-card slot is **empty** and the management RJ45 port is **fused with a metal plate**. No out-of-band remote management (no iLO/LO100 IPMI). |
| Remote access | **None** — direct console only: keyboard + mouse + monitor on the ML110 |
| NIC | Broadcom BCM5722 (`enp14s0`), MAC `78:e7:d1:53:fb:87` |
| Hardware monitoring | **No lm-sensors fan/PWM control** — no Super I/O sensor chip exposed; IPMI BMC KCS has no Linux driver (verified with `sensors-detect` 2026-08-15, see note below) |

> **Fan / hardware monitoring (lm-sensors, 2026-08-15).** `sensors-detect` on the live OMV
> install finds **only `coretemp`** (CPU digital thermal sensor — 42 °C at idle, crit 100 °C).
> No Super I/O sensor chip is present at the standard probe ports (0x2e/0x2f, 0x4e/0x4f), so there
> are **no fan RPM inputs and no PWM outputs** — `fancontrol` / the OMV fan-control plugin have
> nothing to control. An **IPMI BMC KCS** is detected at `0xca2` but has **no Linux driver yet**
> (and this G5 has no working LO100 anyway). **Conclusion: software fan control is not possible**
> on this board; fan noise is addressed physically (clean / quiet-fan swap / dampening), and a
> BIOS fan/thermal profile (if any) reverts on power loss until the dead CR2032 is replaced.

### Controller topology

| PCI address | Device | Type | Role |
|---|---|---|---|
| `00:1f.2` | Intel ICH9R 82801IR | **4-port SATA, IDE mode** | onboard SATA |
| `00:1f.5` | Intel ICH9 82801I | **2-port SATA, IDE mode** | onboard SATA |
| `01:00.0` | Broadcom/LSI **SAS1068E** | **Dell SAS 6/iR** hardware RAID (PCIe x8) | RAID 0/1 only, no JBOD |
| `0e:00.0` | Broadcom BCM5722 | Gigabit Ethernet | NIC |

> Note: there is **no separate "B110i" PCI device** — "B110i" is just the ICH9R SATA with RAID-capable firmware. The only true hardware RAID controller is the SAS1068E.

### Disk inventory + SMART (all PASSED unless noted)

| # | Model (SMART) | Serial | Size | Role |
|---|---|---|---|---|
| 1 | Hitachi Travelstar HTS541020G9SA00 (2.5") | `MPBFL0X9G1W9WM` | 20 GB | cold spare |
| 2 | Fujitsu MHW2020BH (2.5") | `NZ0GT772LN18` | 20 GB | cold spare |
| 3 | Hitachi HDS721050CLA660 | `JP1572FL1849SK` | 500 GB | `md0` |
| 4 | Hitachi HDS721050CLA660 | `JP1572FL167V6K` | 500 GB | `md0` mirror |
| 5 | WDC WD2500AAKX-75U6AA0 | `WD-WCC2F0157761` | 250 GB | `md1` |
| 6 | GB0250EAFYK (labeled "WD RE3") | `WCAT1F035986` | 250 GB | `md1` mirror |
| 7 | Goodram C40 120 GB (SSD) | `1C9C074614D500572350` | 120 GB | OS disk |
| 8 | WDC WD10EZEX-00BN5A0 (spare) | `WD-WCC3F7AKKXUT` | 1 TB | **offline** (decided 2026-08-15) |

**Label vs SMART discrepancies:** the 500 GB Hitachis label `CLA662` but report `CLA660` (HP OEM variant); the "WD RE3" drive actually reports as `GB0250EAFYK` (rebadged); the Fujitsu label `MHV2020BH` reports as `MHW2020BH`. **SMART identity is authoritative.**

**Cabling & bays (onboard SATA, current state):** ICH9R ports #1–#4 → the 4× 3.5" data
drives (mdadm RAID1 pairs); ICH9 port #5 → **Goodram C40 120 GB SSD** (OMV OS, Option D);
ICH9 port #6 → **free** (1 TB WD10EZEX **offline**, decided 2026-08-15). All four 3.5" bays occupied;
both 2.5" bays hold the 20 GB cold spares (detached). Label power draw: Hitachi Travelstar
20 GB `5V 1.0A`, Fujitsu 20 GB `5V 0.50A`.

### SSD health check (Goodram C40, 2026-08-09)

Verified with `smartctl -a` under SystemRescue before committing it as the OMV OS disk:

| Attribute | Value | Verdict |
|---|---|---|
| SMART overall-health | **PASSED** | ✅ |
| Reallocated_Event_Count | **0** | ✅ no failed blocks |
| Raw_Read_Error_Rate | 0 | ✅ |
| Unknown attrs 170/173/218 | normalized **100** | ✅ fresh (SMI/Phison vendor attrs) |
| Power_On_Hours | 13,860 | ⚠️ high-ish for a consumer SSD, not a health issue |
| Power_Cycle_Count | 4,387 | ⚠️ high — frequent power-cycling in prior life, no health impact |
| Total_LBAs_Written | ~10.5 M | ✅ low — plenty of endurance left |
| SMART Error Log | empty | ✅ |
| Self-test log | none run | run a short self-test at install time |

**Conclusion:** healthy — confirmed as the OMV OS disk (Option D). Note the drive currently carries an old Ubuntu LVM (`ubuntu--vg`), which the OMV install will wipe.

---

## Software Choice

| Option | Verdict | Reason |
|---|---|---|
| **OMV 8.x** (Debian 13) | ✅ Selected | Free, Debian-based; mdadm RAID out of the box |
| Unraid (paid) | ⏸️ Deferred | License cost; revisit if Docker-heavy NAS is needed |
| TrueNAS SCALE | ❌ Rejected | ZFS-focused; not needed since no ZFS |
| Proxmox | ❌ Rejected | Virtualization-focused; not a storage target |

**ZFS vs mdadm:** ZFS is viable at 4 GB ECC but the user chose **regular RAID only**. mdadm RAID1 gives redundancy with zero RAM pressure and full `smartctl` visibility.

---

## RAID: why software (mdadm) over hardware (Dell SAS 6/iR)

1. **No controller dependency.** Hardware RAID binds the array to the exact controller model — if the SAS 6/iR dies, data needs a compatible card. mdadm metadata imports on any Linux box (or a USB dock).
2. **No battery-backed write cache.** The SAS 6/iR lacks BBWC, forcing risky write-back or slow write-through. mdadm + XFS/ext4 journals safely.
3. **Per-disk visibility.** Behind hardware RAID you lose per-drive SMART; with mdadm every disk stays a normal `/dev/sdX`.
4. **SATA support.** The SAS 6/iR is SAS-first, 3 Gb/s, and finicky with SATA disks; onboard ICH9R in AHCI is native SATA.
5. **Recovery portability.** Move the mdadm pair to any machine if the G5 board dies.
6. **Performance non-issue.** RAID1 has no parity math; the GigE NIC (~110 MB/s) is the bottleneck, not the 2-core CPU.
7. **RAID level parity.** The SAS 6/iR only does RAID 0/1 — same as mdadm here.
8. **Cost & power.** Onboard SATA is free; removing the card saves ~10–15 W on a 24/7 box.

**Counterpoint:** hardware RAID offloads I/O and survives reinstalls more transparently — negligible here given no parity workload and a GigE bottleneck.

### B110i (ICH9R "fake RAID") — also not recommended

The HP "B110i" is **not** a hardware RAID controller — it's the onboard ICH9R SATA
(`00:1f.2`) running RAID-capable firmware (Intel Matrix RAID, i.e. "fake RAID"). It
shares the SAS 6/iR's drawbacks and adds its own:

- **No cache / no BBWC** — nothing to absorb a power loss; metadata lives on the disks and in BIOS ROM.
- **Host-CPU RAID** — the controller has no RAID engine; the OS driver does the work.
- **Driver-dependent** — logical volumes are invisible to Linux without the HPE `hpvsa`/`hpsa` driver; mdadm sees nothing.
- **Hides per-disk SMART** — the array is opaque behind the fake-RAID metadata.
- **RAID 0/1/10 only** — no advantage over mdadm RAID1 here.

Since it offers nothing over plain mdadm, the BIOS sets **SATA RAID Enable = Disabled** and
the disks go straight to mdadm as raw `/dev/sdX`.

### How OMV handles array management (mdadm under the hood)

OMV has no RAID engine of its own — `Storage | RAID` in the web UI is a **GUI wrapper around
`mdadm`**. Creating an array there runs `mdadm --create`, producing a standard Linux
`/dev/md*` device; OMV then maintains `/etc/mdadm/mdadm.conf` so arrays auto-assemble at
boot, and owns mount management for the filesystems built on top (XFS/ext4) via
`Storage | File Systems`. The arrays are genuine Linux software RAID — portable to any
Linux box, per-disk SMART intact. Arrays created outside OMV (e.g. at the CLI) are detected
the same way: once assembled they appear under `Storage | RAID`, their filesystems under
`Storage | File Systems`, and OMV can mount them via the UI (it deliberately does not
auto-mount so its DB stays the source of truth for mounts).

---

## Boot Device

| | Option A (rejected) | Option B (superseded) | Option C (superseded) | **Option D (chosen)** |
|---|---|---|---|---|
| OMV OS on | Dedicated ≥32 GB USB stick (`flashmemory` plugin) | 1× 2.5" 20 GB drive (ICH9 #5) | 2× 2.5" 20 GB in **SAS 6/iR RAID 1** (OS redundancy) | **Goodram C40 120 GB SSD (ICH9 #5)** |
| 1 TB spare | single-disk XFS on ICH9 #5 | offline | single-disk XFS on ICH9 #6 | **offline — decided 2026-08-15** |
| Cost | USB purchase + flash-wear mgmt | zero (reuse 2.5" drive) | zero (both 20 GB reused) | zero (spare SSD found) |
| Hardware RAID needed | no | no | **yes** — SAS 6/iR in boot path | **no** — SAS 6/iR not used |

**Option C (considered, superseded):** mirror the two 2.5" 20 GB drives on the Dell SAS 6/iR as the OS volume. Rationale at the time: the boot disk is the highest-wear component, and OS RAID1 gave redundancy while freeing both ICH9 ports so the 1 TB spare could come online. Drawbacks that pushed it out: the 2009 controller becomes a boot dependency (death = no boot), no per-disk SMART behind the array, and the battery-less write cache risk — acceptable for a disposable OS, but still added hardware dependency for zero OS-capacity gain.

**Chosen: Option D** — a spare **Goodram C40 120 GB SSD** appeared, giving a single reliable boot disk with 6× the OS capacity of the 20 GB drives, no hardware RAID anywhere, and freeing both 2.5" 20 GB drives as cold spares. The 1 TB spare is **offline** (decided 2026-08-15 after a SystemRescue content review); its contents are **not documented** — personal data, and this repo is public. **SSD health confirmed (SMART PASSED).**

---

## Power Consumption & Optimization

Estimated draw for the **final build state** (SAS 6/iR removed — saves ~10–15 W, 1 TB spare unplugged, 1× SSD + 4× 3.5" HDDs active). Component figures are datasheet estimates; confirm the idle baseline once with a wattmeter (~30 PLN).

| Component | Idle | Load |
|---|---|---|
| ML110 G5 platform (board, chipset, fans, PSU) | ~30 W | ~35 W |
| Intel Pentium Dual E2160 (65 W TDP) | ~12 W | ~35 W |
| 4 GB DDR2-800 ECC | ~5 W | ~5 W |
| Goodram C40 120 GB SSD | ~1.5 W | ~3 W |
| 4× 3.5" 7200 rpm HDDs | ~20 W | ~32 W |
| **DC total** | **~69 W** | **~110 W** |
| **AC draw @ ~85% PSU efficiency** | **~80 W** | **~130 W** |

### Annual cost

| Scenario | Avg AC | Energy/yr | Cost/yr (0.90–1.20 PLN/kWh) |
|---|---|---|---|
| 24/7, drives spinning | ~85 W | ~745 kWh | ~670–890 PLN (~€150–200) |
| 24/7, drives spun down | ~65 W | ~570 kWh | ~515–685 PLN (~€115–150) |
| Scheduled nightly window (~8 h) | ~85 W | ~250 kWh | ~225–300 PLN (~€50–65) |

At ~€150–200/yr this is the most power-hungry box in the homelab — the M910q host idles at ~8 W (research 03), the X1 Lite LLM server is TBD. Worth optimizing.

### Optimization plan

1. **Measure first** — one wattmeter reading to confirm the ~80 W idle baseline before investing in mitigations.
2. **HDD spindown (free, Phase 1)** — OMV idle spindown (`hdparm -S`, conservative 20–30 min timeout) for the 4 HDDs; the SSD stays up. The NAS is a backup target touched only during backup windows (nightly restic, Longhorn snapshots per ADR 22), so drives can stay parked most of the day. Saves ~20 W → ~€35–50/yr; a long timeout keeps spin-up cycles rare, avoiding extra disk wear.
3. **Scheduled power, only if needed** — boot the box only for the backup window (RTC wake / WoL, e.g. 23:00–06:00). Cuts cost to roughly a third (~€50–65/yr) but drops always-on NFS — fine for batch restic/Longhorn, not for interactive access.
4. **Revisit the Q956 as a power move** — per the comparison row above the Q956 runs at ~1/4 the cost (~€40–45/yr, ~€110–160/yr saved). Its ~195 PLN acquisition + 2× 2.5" drives + caddy pays back in under a year on power alone. Keep the ML110 only if the 4× 3.5" bays or the spare 1 TB matter.

**Recommendation:** apply Phase 1 (spindown) after a wattmeter baseline; escalate to scheduled power or the Q956 only if the measured saving stays below ~€40/yr.

### Acoustic & power management (AAM / APM)

OMV exposes per-disk AAM/APM under `Storage | Disks → Edit` (backed by `hdparm`). Both are
**set-and-apply** config that OMV re-applies at boot, so the values survive reboots.

- **AAM — Advanced Acoustic Management (`hdparm -M`)** trades seek speed for seek noise:
  - `Disabled` (default) — drive's own factory seek profile.
  - `Minimum performance, minimum acoustic output` — **quietest** (acoustic level ~128).
  - `Maximum performance, maximum acoustic output` — loudest (fastest seeks).
  - **Effect on noise:** removes most of the rapid *click-clack* seek clatter — the dominant
    annoying sound on these 3.5" drives. Small random-access perf hit; irrelevant for a NAS.
- **APM — Advanced Power Management (`hdparm -B`)** manages the drive's power/standby state:
  - Values **1–127** permit **spindown/standby** — **do not use on RAID members**: if mdadm
    writes to a parked drive, the slow wake can make mdadm mark it **failed** → array degraded.
  - Values **128–254** keep the disk **spinning** (no spindown) but allow idle head parking /
    reduced power.
  - `Disabled` — no power management (full power always).
- **Spindown time (`hdparm -S`)** — the idle timeout after which a drive parks; same RAID risk
  as APM < 128. Left **disabled** on all RAID members.

**Applied 2026-08-15:** **AAM = quietest** on all 4 data drives (both Hitachis, WD2500AAKX,
GB0250EAFYK). **APM and Spindown left Disabled** — APM 128 would only trim idle draw at the
cost of extra load/unload cycling (a wear factor on these older drives) and does not reduce the
audible hum; spindown is a RAID-reliability trap (see above). The noise lever is **AAM**; the
power lever is spindown / scheduled power (below), not APM. (Runbook 22 §6 records the live
values per drive.)

---

## References

- Idea [03 — Homelab NAS on ML110](../ideas/03-nas-backup-target-ml110.md) — the plan/implementation doc
- Runbook [21 — ML110 inventory](../runbooks/21-ml110-nas-inventory.md)
- Issue [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54)
- [ADR 02 — Backup Strategy](../decisions/02-backup-strategy-restic-blob.md)
- [ADR 22 — k3s + Azure Arc](../decisions/22-k3s-arc-homelab.md) — NFS backup target for Longhorn
- [ADR 23 — NAS on the HP ProLiant ML110 (OMV)](../decisions/23-nas-on-ml110.md) — authoritative record of the decisions in this doc
- [ADR 01 — Hardware Selection](../decisions/01-hardware-selection-m910q.md) — the M910q homelab server
