# 28 — Wyse 3040 Hardware Diagnostic: Pre-Boot Audit & eMMC Visibility

**Source**: SystemRescue 13.02 live session + hardinfo2 report + Dell ePSA Pre-boot System Assessment + BIOS Setup walk + Debian installer partition disk, Aug 17 2026 · Issue [#65 — Dedicated edge device for Cloudflare Tunnel + Caddy ingress](https://github.com/jaroslaw-bagnicki/Homelab/issues/65)

**Scope**: Pre-boot hardware audit of the newly arrived **Dell Wyse 3040** thin client (the edge ingress appliance, [ADR 24](../decisions/24-edge-ingress-appliance.md)) — full hardware inventory plus the investigation of the **8 GB eMMC that SystemRescue failed to enumerate**, resolved by the Debian installer recognizing it as `mmcblk0`.

**Status**: ✅ Fully resolved — the eMMC **exists, is usable, and boots the installed Debian 13**; the SystemRescue enumeration gap was a **live-media kernel/driver artifact, not a hardware or firmware issue**. The eMMC is confirmed as the OS medium (ADR 24 premise holds); a post-install EXT_CSD read shows it in near-mint condition (0–10% lifetime used, see [eMMC Health Inspection](#emmc-health-inspection-post-install-2026-08-18)).

---

## Decision Summary

> **Decision authority:** the edge appliance decision is recorded in
> [ADR 24 — Edge ingress on a dedicated thin-client appliance](../decisions/24-edge-ingress-appliance.md).
> This research doc is the Phase 0 hardware audit output. The eMMC finding **confirms the ADR 24
> premise** (8 GB eMMC as OS medium) — no amendment is required.

| Decision | Outcome (as of 2026-08-17) |
|---|---|
| Hardware | Dell Wyse 3040 — acquired 2026-08-13 (89,00 PLN + 35,94 PLN charger) |
| Role | Edge ingress — bare-metal `cloudflared` + Caddy (runbook 24) |
| OS medium | **eMMC `mmcblk0` (7.8 GB, H8G4a)** — present, ePSA Pass, and enumerated by the Debian installer; matches ADR 24's 8 GB premise |
| Static IP | Deferred — research 24's tens-block scheme has no edge slot yet; decide in runbook 24 §2 |

---

## Context

The Wyse 3040 is the deliberately-constrained (2 GB / 8 GB) edge appliance that takes over
public ingress (`cloudflared` + Caddy + dnsmasq) from the M910q (ADR 22/24, issue #65).
It arrived and was booted into **SystemRescue 13.02** (via Ventoy USB) for the pre-wipe
hardware audit — the same Phase 0 pattern used for the ML110 (runbook 22 §3) and the M910q
(runbook 25 §0). The audit's purpose: capture exact specs into `docs/hardware.md` and check
for surprises **before** committing an OS to the box.

---

## Hardware Findings (SystemRescue, 2026-08-17)

### System

| Field | Value |
|---|---|
| Product | Dell **Wyse 3040 Thin Client**, SKU `07C1`, chassis type Desktop |
| Serial | `8YW28L2` |
| Board | "Cherry Trail CR", Dell Inc., A01, SN `/8YW28L2/CNWS20083M00W2/` |
| BIOS | Dell Inc. **1.2.3**, released 2017-11-07 |
| CPU | Intel **Atom x5-Z8350** (Cherry Trail, 4C/4T), 480–1920 MHz, x86-64-v2 |
| RAM | **2 GB** DDR3 (1917 MB usable), 1× row-of-chips, 1600 MT/s, 64-bit data width — **soldered, no upgrade** |
| Storage | **eMMC `mmcblk0` 7.8 GB (H8G4a)** — see [The 8 GB eMMC](#the-8-gb-emmc--the-investigation--its-resolution) |
| GPU | Intel Atom/Celeron/Pentium x5-E8000/J3xxx/N3xxx Integrated Graphics (PCI `00:02.0`, i915) |
| NIC | Realtek RTL8111/8168 (`enp1s0`), MAC `8c:ec:4b:6d:6f:4f` (altname `enx8cec4b6d6f4f`) |
| Audio | Intel HDMI/DP LPE (pcm 0–2) + `cht-bsw-rt5672` (RT5670 codec, headset jack) |
| USB | Rapoo 2.4G wireless KB/mouse dongle + Kingston DataTraveler 100 (boot stick) |
| Power | AC mains (`ADP1` attached) — charger verified working; clears runbook 24's charger caveat |
| Cooling | Fanless; idle temps **51–55 °C** core / 51–52 °C SoC (SystemRescue, ~1 min uptime) |
| Memory test | ePSA Memory Data-Bus Stress Test allocated 1869 MB, all addresses tested — **Pass** |

### Display

| Field | Value |
|---|---|
| Output | DP-1 (connected, enabled) → **MEB MD22322** 31.6" |
| Resolution | 2560×1440 @ 59 Hz (VESA DTD), EDID v1.4, DP 1.4a-class support incl. 2880×1620 |
| Manufacture | Week 31 of 2016 |
| Audio | Display supports 2ch LPCM over HDMI link |

### CPU / Security notes

- **`mds` Vulnerable, `old_microcode`** — expected on aging Cherry Trail (no new microcode); SMT disabled. Not a blocker for a Cloudflare-tunnel-terminated edge box (no direct internet exposure).
- `spectre_v2` Retpolines mitigated; `meltdown` PTI mitigation active.

---

## The 8 GB eMMC — the Investigation & its Resolution

ADR 24, research 25, runbook 24, and `docs/hardware.md` all assume **8 GB eMMC (soldered)** as the boot/OS medium. The pre-boot audit produced a contradiction that was fully resolved.

### Observations (in order)

| # | Source | Result |
|---|---|---|
| 1 | hardinfo2 Storage / `lsblk` (SystemRescue) | Only `sda` (57.8G USB stick). **No `mmcblk*`** |
| 2 | `lspci -nn` | `00:11.0 SD Host controller [8086:2295]` — SDIO/eMMC host **present on the board** |
| 3 | `dmesg \| grep mmc` | empty — but `sdhci_acpi`/`mmc_core` modules are loaded |
| 4 | Dell ePSA (firmware) | **"eMMC Drive" test — green Pass**; "All tests passed" |
| 5 | BIOS Setup (F2 walk) | Boot Sequence lists **only PXE** (`IP4`/`IP6 Realtek PCIe GBE`); **no storage options in the Setup tree** (no SATA/eMMC/Onboard Storage entries); "Add Boot Option" → **"File System Not Found!"** (no FAT/EFI partition visible to UEFI yet); "Legacy boot mode is not allowed when Secure Boot is enabled" notice |
| 6 | **Debian installer** | `MMC/SD card #1 (mmcblk0) — 7.8 GB MMC H8G4a` listed alongside the Kingston USB (`sda`, 62 GB) |

### Interpretation (corrected)

The eMMC **exists, passes firmware self-test, and is usable by an OS** — evidence #6 (Debian installer
enumerating `mmcblk0` at 7.8 GB) is conclusive. The earlier SystemRescue session (#1–#3) simply failed to
enumerate it — a **live-media kernel/driver/initialization difference**, not a hardware fault, not a
firmware lock. An early hypothesis (ThinOS firmware lock) is **rejected**: a firmware-locked device would
not appear as a block device in the Debian installer.

The BIOS walk (#5) was the misleading piece: a stripped ThinOS-style Setup with no storage menu and a
PXE-only Boot Sequence *looks* like the eMMC is hidden, but once an EFI System Partition is written to
`mmcblk0` the firmware should auto-discover `\EFI\BOOT\BOOTX64.EFI` on the next boot (or via the F12
One-Time Boot Menu). That hypothesis is the one remaining check.

> ⚠️ **SystemRescue quirk worth remembering:** this exact Wyse 3040 booted into SystemRescue 13.02 did
> not show internal eMMC storage, yet Debian's installer does. For future rescue-boot audits on this box,
> do not trust a bare `lsblk` from SystemRescue to prove the eMMC is absent — cross-check with the Debian
> installer's partition-disks screen or ePSA.

### Steps

- [x] hardinfo2 full report captured (`hardinfo2_report.txt`)
- [x] `lsblk` / `lspci -nn` / `dmesg` / `smartctl --scan` on the SystemRescue live system
- [x] Dell ePSA Pre-boot System Assessment — all tests Pass, incl. **eMMC Drive**
- [x] BIOS Setup (F2) menu walk — PXE-only Boot Sequence; no storage toggle exists in Setup
- [x] Debian installer confirms **`mmcblk0` = 7.8 GB MMC H8G4a** (the eMMC, usable)
- [x] Partition `mmcblk0` (guided "use entire disk"), install GRUB to `/dev/mmcblk0` (not `sda` = the live USB) — done, runbook 24 §1
- [x] Reboot → F12 One-Time Boot Menu → confirm the firmware discovers the eMMC's EFI partition
- [x] Re-add eMMC to the BIOS Boot Sequence for persistent boot — entry present, boots without F12 (2026-08-18)

### Why the eMMC path wins (no ADR 24 amendment)

| Option | Verdict |
|---|---|
| **eMMC `mmcblk0` as OS medium** | ✅ Matches ADR 24's 8 GB premise; no amendment; Debian minimal (~1.5–2 GB) fits with room for logs. The one open item is the firmware boot-discovery check |
| USB stick as OS medium | Rejected — only needed if the firmware won't boot from eMMC; would trigger an ADR 24 amendment |

---

## eMMC Health Inspection (post-install, 2026-08-18)

Once Debian was installed on the eMMC (runbook 24 §1), the drive's wear/health state was
read directly from the hardware via `mmc-utils` (`mmc extcsd read /dev/mmcblk0`). The
EXT_CSD (Extended Card Specific Data) registers give the vendor's own endurance accounting:

| Register | Value | Meaning |
|---|---|---|
| **Life Time Estimation A** | `0x01` | **0–10%** of the device's lifetime used |
| **Life Time Estimation B** | `0x01` | **0–10%** of the device's lifetime used |
| **Pre EOL Information** | `0x01` | **Normal** (0x01 = normal; 0x02 = 80% of reserved blocks used, 0x03 = 90% — critical) |

**Interpretation:** the eMMC is effectively **new** from an endurance standpoint — well
inside normal wear, with the full reserved-block pool intact. Combined with the planned
write-light workload (no swap, RAM-only Netdata, aggressive log rotation — ADR 24/27), the
drive should comfortably outlive the appliance's useful life.

Other notable EXT_CSD fields from the same dump:

- **MMC 5.1** device (Extended CSD rev 1.8), running at **HS200** (`HS_TIMING 0x02`) — modern, fast mode
- **128 KiB cache, enabled** (`CACHE_CTRL 0x01`) — reduces write amplification
- **Write reliability** on all partitions (`WR_REL_SET 0x1f`) — data protected across power loss
- **BKOPS** (background operations / wear-leveling) supported and available
- `SEC_COUNT 0x00e90000` = 7.28 GiB — matches the 7.3 GB partition table

The post-boot `dmesg` shows a clean eMMC bring-up (`mmc0: new HS200 MMC card`, `p1 p2`,
no MMC errors) and, after the swap partition was removed and `/` grown (runbook 24 §1
deviation), no swap is added at boot.

---

## Open Questions — all resolved (as of 2026-08-18)

1. **Firmware boot discovery** — ✅ **Resolved 2026-08-18.** The eMMC's EFI entry (`UEFI: Hard Drive, Partition 1`) is registered in the F2 Setup Boot Sequence and the box boots from the eMMC **without F12**. The EFI removable-media fallback (`\EFI\BOOT\BOOTX64.EFI`) carried the first boots; the entry was re-added for persistent boot (runbook 24 §1).
2. **OS trial target** — ✅ **Resolved 2026-08-18.** **Debian 13 (trixie) minimal** is the confirmed OS; the Alpine trial is dropped. OS to be locked in ADR 24 once the edge services (cloudflared + Caddy + dnsmasq + Netdata) validate (runbook 24 §7).
3. **Static IP** — ✅ **Resolved.** `192.168.2.240` (new `24x` edge/appliance block, research 24) decided during the install — see runbook 24 §2.
4. **SystemRescue eMMC blind spot** — ✅ **Resolved.** The ⚠ note is in runbook 24 (audit section) — future rescue sessions on this box won't misreport the eMMC as absent.

---

## References

- [ADR 24 — Edge ingress on a dedicated thin-client appliance](../decisions/24-edge-ingress-appliance.md)
- [Research 25 — Edge ingress SBC, PL market](../research/25-edge-ingress-sbc.md)
- [Research 24 — Network topology & IP scheme](../research/24-network-topology-design.md)
- [Runbook 24 — Edge Appliance (Wyse 3040)](../runbooks/24-edge-appliance.md)
- [Runbook 25 §0 — M910q pre-wipe audit pattern](../runbooks/25-m910q-os-refresh.md)
- [Runbook 22 — ML110 Phase 0 inventory pattern](../runbooks/22-ml110-nas-inventory.md)
- [Issue #65 — Dedicated edge device for Cloudflare Tunnel + Caddy ingress](https://github.com/jaroslaw-bagnicki/Homelab/issues/65)