# 28 — Wyse 3040 Hardware Diagnostic: Pre-Boot Audit & the Missing eMMC

**Source**: SystemRescue 13.02 live session + hardinfo2 report + ePSA Pre-boot System Assessment, Aug 17 2026 · Issue [#65 — Dedicated edge device for Cloudflare Tunnel + Caddy ingress](https://github.com/jaroslaw-bagnicki/Homelab/issues/65)

**Scope**: Pre-boot hardware audit of the newly arrived **Dell Wyse 3040** thin client (the edge ingress appliance, [ADR 24](../decisions/24-edge-ingress-appliance.md)) — full hardware inventory plus the **open finding that the 8 GB eMMC is not enumerated by the OS** despite being detected by the firmware-level ePSA diagnostic.

**Status**: 📝 Analysis — diagnostic in progress; outcome feeds the edge appliance OS-medium decision and a possible ADR 24 amendment.

---

## Decision Summary

> **Decision authority:** the edge appliance decision is recorded in
> [ADR 24 — Edge ingress on a dedicated thin-client appliance](../decisions/24-edge-ingress-appliance.md).
> This research doc is the Phase 0 hardware audit output. If the eMMC finding settles into
> a design change (OS on USB vs exchange for an eMMC unit), the ADR is amended in the same
> phase as this research per the repo's co-authoring pattern.

| Decision | Outcome (as of 2026-08-17) |
|---|---|
| Hardware | Dell Wyse 3040 — acquired 2026-08-13 (89,00 PLN + 35,94 PLN charger) |
| Role | Edge ingress — bare-metal `cloudflared` + Caddy (runbook 24) |
| OS medium | **OPEN** — 8 GB eMMC assumed by ADR 24 but **not OS-visible**; ePSA says the eMMC exists |
| Static IP | **Deferred** — research 24's tens-block scheme has no edge slot yet; decide in runbook 24 §2 |

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
| Storage | **eMMC expected but not OS-visible** — see [eMMC Finding](#the-emmc-giving-8-gb-premise) below |
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

## The eMMC Giving 8 GB Premise — Open Finding

ADR 24, research 25, runbook 24, and `docs/hardware.md` all assume **8 GB eMMC (soldered)** as the boot/OS medium. The audit shows a **contradiction between OS-visible and firmware-visible storage**:

### Evidence

| Check | Result |
|---|---|
| hardinfo2 Storage | Only `scsi0: Kingston DataTraveler` (USB stick). No eMMC block device |
| `lsblk` | Only `sda` (57.8G USB). **No `mmcblk*`** |
| `lspci -nn` | `00:11.0 SD Host controller [8086:2295]` — SDIO/eMMC host **present on the board** |
| `ls /dev/mmcblk*` | empty |
| `smartctl --scan` | empty |
| `dmesg \| grep mmc` | empty — kernel never probed a device; but `sdhci_acpi`/`mmc_core` modules are loaded |
| **Dell ePSA (firmware)** | Panel lists **"eMMC Drive"** test with a **green Pass**; "All tests passed" — Service Tag 8YW28L2 |

### Interpretation

The eMMC **physically exists and passes firmware self-test**, but the Linux kernel never
enumerates it. This is a **BIOS→OS handoff gap**, not a missing chip. Most likely causes:

1. **BIOS storage toggle off** — Dell thin clients often ship with embedded storage disabled
   (designed to boot Wyse ThinOS over network/USB). Candidate menus in F2 Setup → *System
   Configuration* / *Integrated Devices* / *Storage*: `Embedded Storage`, `eMMC`,
   `Onboard Storage`, `SATA Operation`.
2. **Boot mode** — eMMC may only enumerate in one of UEFI/Legacy mode.
3. **Firmware-locked ThinOS mode** — eMMC reserved for Wyse management; not exposed to a
   general OS. If this is a hard lock, the OS medium must move off the eMMC.

### Steps (in progress)

- [x] hardinfo2 full report captured (`hardinfo2_report.txt`)
- [x] `lsblk` / `lspci -nn` / `dmesg` / `smartctl --scan` run on the live system
- [x] Dell ePSA Pre-boot System Assessment — all tests Pass, incl. **eMMC Drive**
- [ ] BIOS Setup (F2) menu walk — hunt for an embedded-storage toggle or boot-mode effect
- [ ] If a toggle exists: enable → re-boot SystemRescue → confirm `mmcblk0` appears (~8 GB)
- [ ] Conclude: eMMC usable for OS (ADR 24 unchanged) **vs** firmware-locked (OS medium = USB)

### Impact if the eMMC stays invisible to the OS

The 3040 has **no SATA and no M.2** — storage is eMMC or nothing. If the eMMC cannot be
exposed to a general OS, the options are:

| Option | Notes |
|---|---|
| **USB as the OS medium** | Debian minimal ~1.5–2 GB fits; write-light cloudflared+Caddy workload is USB-endurance-fine. Keeps the 89 PLN experiment; removable medium |
| **Exchange for another 3040** | Risk: flashless/hidden-eMMC variants appear common on the PL used market; sellers rarely list storage |
| **Fallback per ADR 24** | Wyse 5070 / HP t640 (~150–250 PLN, real SATA) — documented escape hatch |

---

## Open Questions

1. **eMMC visibility** — can the eMMC be exposed to the OS via BIOS (storage toggle / boot mode), or is it firmware-locked to ThinOS mode?
2. **OS medium** — if the eMMC stays invisible: USB boot documented as the new OS medium, or does ADR 24's fallback (Wyse 5070) get triggered?
3. **Static IP** — no edge slot in research 24's tens-block scheme (20x/21x/22x/23x used). Candidate: a `24x` edge/appliance block; deferred to runbook 24 §2.
4. **BIOS access pattern** — need to capture the F2 Setup key + menu layout for the runbook (3040 has no iLO/Wyse management; direct console only).

---

## References

- [ADR 24 — Edge ingress on a dedicated thin-client appliance](../decisions/24-edge-ingress-appliance.md)
- [Research 25 — Edge ingress SBC, PL market](../research/25-edge-ingress-sbc.md)
- [Research 24 — Network topology & IP scheme](../research/24-network-topology-design.md)
- [Runbook 24 — Edge Appliance (Wyse 3040)](../runbooks/24-edge-appliance.md)
- [Runbook 25 §0 — M910q pre-wipe audit pattern](../runbooks/25-m910q-os-refresh.md)
- [Runbook 22 — ML110 Phase 0 inventory pattern](../runbooks/22-ml110-nas-inventory.md)
- [Issue #65 — Dedicated edge device for Cloudflare Tunnel + Caddy ingress](https://github.com/jaroslaw-bagnicki/Homelab/issues/65)