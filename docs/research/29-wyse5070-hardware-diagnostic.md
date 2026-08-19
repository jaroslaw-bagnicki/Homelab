# 29 — Wyse 5070 Hardware Diagnostic: Pre-Boot Audit & Storage Status

**Source**: SystemRescue 13.02 live session + hardinfo2 report, Aug 19 2026 · Issue [#68 — Implement Home Assistant on a thin client node](https://github.com/jaroslaw-bagnicki/Homelab/issues/68) (sub-issue [#82](https://github.com/jaroslaw-bagnicki/Homelab/issues/82))

**Scope**: Pre-boot hardware audit of the newly arrived **Dell Wyse 5070** thin client (the Home Assistant node, [ADR 25](../decisions/25-home-assistant-thin-client.md)) — full hardware inventory before committing Proxmox VE to the box. Same Phase 0 pattern as the [Wyse 3040 audit (research 28)](28-wyse3040-hardware-diagnostic.md).

**Status**: 🔨 In progress — SystemRescue/hardinfo2 inventory captured; **SSD acquired (used, SMART-verified) and installed**; eMMC confirmed present (14.7 GiB). Pending the Dell ePSA Pre-boot System Assessment result, the BIOS Setup (F2) walk, and the power-adapter spec confirmation ([Pending checks](#pending-checks)).

---

## Decision Summary

> **Decision authority:** the Home Assistant node decision is recorded in
> [ADR 25 — Home Assistant on a Dedicated Thin-Client Node (Wyse 5070 + Proxmox VE)](../decisions/25-home-assistant-thin-client.md).
> This research doc is the Phase 0 hardware audit output. The findings **confirm the ADR 25
> premises** (J4105, 8 GB RAM, M.2 **SATA** 2280 only, no NVMe) — no amendment is required.

| Decision | Outcome (as of 2026-08-19) |
|---|---|
| Hardware | Dell Wyse 5070 — acquired; 2× 4 GB DDR4; **SK hynix SC311 128 GB SSD installed** |
| Role | Home Assistant node — Proxmox VE + HA OS VM + Mosquitto/Zigbee2MQTT LXC (ADR 25) |
| CPU | **Intel Celeron J4105** (Gemini Lake, 4C/4T) — confirmed (research 26's J4105/J5005 ambiguity resolved) |
| RAM | **8 GB (2× 4 GB Micron DDR4-3200)** — both SODIMM slots populated |
| OS medium | **M.2 SATA 2280 — SK hynix SC311 128 GB (used, SMART-verified ~97% NAND life left)**, installed; 14.7 GiB eMMC present but unused |
| Zigbee coordinator | **Sonoff Zigbee 3.0 USB Dongle Plus (ZBDongle-P / CC2652P)** — acquired; stable by-id path recorded (research 26 §4 pattern); passthrough to LXC 102 later (sub-issue #85) |
| Static IP | Deferred — DHCP `192.168.2.87` currently; reserve a slot in research 24's scheme during Proxmox install |

---

## Context

The Wyse 5070 is the dedicated smart-home node (ADR 25 / issue #68): Proxmox VE hosting a
Home Assistant OS VM (VM 100) plus Mosquitto (LXC 101) and Zigbee2MQTT (LXC 102) with a
passed-through USB Zigbee coordinator. It needs a **central home location** for Zigbee mesh
coverage. The audit follows the same Phase 0 pattern as the ML110 (runbook 22 §3), the M910q
(runbook 25 §0), and the Wyse 3040 (research 28): capture exact specs into `docs/hardware.md`
and check for surprises **before** committing an OS to the box.

---

## Hardware Findings (SystemRescue, 2026-08-19)

### System

| Field | Value |
|---|---|
| Product | Dell **Wyse 5070 Thin Client**, family "Wyse Thin Client 5000 Series", chassis Desktop |
| Serial | `16474B3` |
| SKU | `080C` |
| Board | "060J9C", Dell Inc., A00, SN `/16474B3/CNWSC0017U0237/` |
| BIOS | Dell Inc. **1.34.0**, released 2024-11-08 |
| CPU | Intel **Celeron J4105** (Gemini Lake, 4C/4T), 800–2500 MHz, x86-64-v2, HWCAPS x86-64-V2 |
| RAM | **8 GB** (2× 4 GiB DDR4 SO-DIMM, Micron `4ATF51264HZ-3G2J1`) — see [RAM](#ram) |
| Storage | **M.2 SATA 2280 — SK hynix SC311 128 GB installed** (SMART PASSED) + 14.7 GiB eMMC (`mmcblk0`, unused) — see [Storage](#storage) |
| GPU | Intel **GeminiLake [UHD Graphics 600]** (PCI `00:02.0`, i915) |
| NIC (GbE) | Realtek RTL8111/8168 (`enp1s0`), MAC `c0:25:a5:65:02:67` |
| NIC (WiFi) | **Intel CNVi WiFi** `iwlwifi` (`wlp0s12f0`), MAC `d0:3c:1f:cb:76:9a` + Intel Bluetooth 9460/9560 |
| Audio | HDA Intel PCH, Realtek ALC269 codec (Rear Mic / Front Line Out / Surround / Headphone + HDMI/DP) |
| USB | Realtek RTS5411 hub, Rapoo 2.4G wireless KB/mouse, Kingston DataTraveler 100 (boot stick) |
| Power | AC attached, no battery — adapter present and powers the box (spec TBD, [pending checks](#pending-checks)) |
| Cooling | Fanless; idle **35 °C** package/core, 34 °C ACPI (SystemRescue, ~2 min uptime) |

### RAM

- **2× 4 GiB Micron** DDR4 SO-DIMM (part `4ATF51264HZ-3G2J1`), **both slots populated** (SODIMM1 + SODIMM2).
- Rated **DDR4-3200** (PC4-25600), **configured at 2400 MT/s** (Gemini Lake memory controller max is 2400 MT/s — expected).
- One module serial `0x2d8a6747`, manufactured **2021 / 11**. MemTotal ~7.6 GiB usable of 8 GiB.
- **16 GB path = replace both sticks with 2× 8 GB** — there is **no free slot** for a simple second-stick upgrade (research 26's purchase tip assumed a single 8 GB stick). No ADR 25 change (8 GB current is exactly what the ADR specifies), but the future 16 GB step is a full swap, not an add.

### Storage

- **M.2 SATA 2280 — SK hynix SC311 SATA 128 GB installed** (used, bought "almost new"), detected via AHCI as `scsi0` (`lsblk`: `sda 119.2G sata`). Device model confirmed **SATA** (research 26's NVMe-invisibility gotcha avoided). SN `MS8BN03201230BC10`, FW `70000P10`, SATA 3.2 6 Gb/s, M.2 form factor.
- **SMART health — PASSED**, clean error log. Endurance profile (used drive, ~9,292 POH / ~1 year, 2,222 power cycles):

  | Attribute | Value | Readout |
  |---|---|---|
  | SMART overall health | **PASSED** | self-assessment clean; error log empty |
  | `Reallocated_Event_Count` / `Retired_Block_Count` | **0** | no failed blocks |
  | `Used_Rsvd_Blk_Cnt_Tot` | 253/253 (max) | 0 reserved blocks consumed |
  | `Media_Wearout_Indicator` (raw) | **97** | ~97% NAND life remaining (SK hynix convention) |
  | `Wear_Leveling_Count` (raw) | 43 | avg ~43 erase cycles/block (Max 78, Min 13) |
  | `Total_Erase_Count` | 613,412 | light total erase load across all blocks |
  | `Temperature_Celsius` | 33 °C (min/max 13/41) | cool |
  | `UDMA_CRC_Error_Count` | 0 | clean SATA interface |

  **Verdict:** the used drive is effectively near-new from an endurance standpoint — consistent with the seller's "almost new" claim. Note: used, so **no warranty** (issue #68 / research 26 §7 preferred new; SMART validation is the compensating evidence).

- **eMMC present — `mmcblk0` = 14.7 GiB** (+ `mmcblk0boot0`/`boot1`). It was invisible in the hardinfo2 reports because hardinfo2's Storage view lists **SCSI disks only** — `lsblk` reveals the eMMC. Matches research 26 §7's "16 GB eMMC — leave unused"; it stays **unused** (M.2 SATA is the OS medium). PCI `00:1c.0` (`mmc0` IRQ 39) is the SD card reader.
- **eMMC health (EXT_CSD, `mmc extcsd read`):** **Pre EOL `0x01` = Normal**, **Life Time A/B `0x00`/`0x01` = 0–10% used** — near-new; SEC_COUNT `0x01d5a000` (14.7 GiB), 256 KiB cache enabled, write-reliability set on all partitions (MMC 5.1, HS200/HS400-capable). Healthy spare, stays unused per ADR 25.
- **No NVMe controller** on the board (Gemini Lake has none natively) — consistent with research 26: **M.2 SATA 2280 (B+M key) only, NVMe not supported**.

### CPU / Security notes

- `old_microcode` Vulnerable — expected on aging Gemini Lake (same as the Wyse 3040). `meltdown` PTI mitigation; `spectre_v2` Enhanced/IBRS; most others Not affected; **`mds` Not affected**. Not a blocker for a home-LAN HA node behind Cloudflare/edge ingress.
- VT-x present (`kvm_intel` loaded) — virtualization for Proxmox confirmed available.

### Display

| Field | Value |
|---|---|
| Output | **DP-1** (session 2) / **DP-2** (session 1) — both DisplayPort outputs validated → **MEB MD22322** 31.6" |
| Resolution | 2560×1440 @ 59 Hz (VESA DTD); XRandR also exposes DP-1/DP-3, HDMI-1/HDMI-2 (disconnected) |
| Manufacture | Week 31 of 2016 (same test monitor as the 3040 audit) |
| Audio | 2ch LPCM over HDMI/DP link |

---

## Implications for ADR 25

| ADR 25 expectation | Actual finding | Verdict |
|---|---|---|
| Celeron J4105 | **J4105 confirmed** (not J5005) | ✅ matches |
| 8 GB RAM | **8 GB (2× 4 GB)** — both slots full | ✅ matches; 16 GB future = replace both sticks |
| M.2 **SATA** 2280, no NVMe | **SK hynix SC311 128 GB SATA installed**; no NVMe on board | ✅ matches (used, not new — SMART-verified) |
| 16 GB eMMC rejected | **eMMC present (14.7 GiB) but unused** — M.2 SATA is the OS medium | ✅ matches |
| Passive/fanless, low power | Fanless, 35–42 °C idle | ✅ matches |
| 1× GbE | Realtek GbE **+ bonus Intel CNVi WiFi/BT** | ➕ extra, not in research 26 |

---

## Pending Checks

1. **Dell ePSA Pre-boot System Assessment** — run (F12 → Diagnostics) and record Pass/fail per test (memory, eMMC/SD, network).
2. **BIOS Setup (F2) walk** — boot mode (UEFI), Secure Boot state, any storage toggles (M.2, eMMC/SD), boot sequence. The 3040's Setup was a stripped ThinOS-style menu; verify whether the 5070's exposes storage options.
3. **Power adapter spec** — barrel connector voltage/amp rating on the included adapter; verify it matches the 5070's requirement (box powers up, but record the label for the runbook).
4. **Static IP** — reserve a slot in research 24's IP scheme during the Proxmox install (currently DHCP `.87`).
5. **Sonoff Zigbee dongle** — ✅ **Resolved 2026-08-19.** **Sonoff Zigbee 3.0 USB Dongle Plus (ZBDongle-P / CC2652P)** — Silicon Labs CP210x UART bridge (`10c4:ea60`), stable path `/dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_c8f3975dd19aef1197dbb89061ce3355-if00-port0` → `ttyUSB0`. The research 26 §4 `/dev/serial/by-id` pattern; ready for LXC 102 passthrough.

---

## Open Questions

1. **SSD endurance over time** — ✅ **Resolved 2026-08-19.** SK hynix SC311 128 GB installed; SMART shows ~97% NAND life remaining, 0 reallocated blocks, ~9,292 POH. Healthy for the planned 24/7 write-heavy Proxmox/HA workload.
2. **eMMC presence** — ✅ **Resolved 2026-08-19.** **Present** (`mmcblk0`, 14.7 GiB + boot partitions) — `lsblk` reveals it; hardinfo2's Storage view only lists SCSI disks, which is why the first audit missed it. Left **unused** (M.2 SATA is the OS medium per ADR 25).
3. **WiFi/BT role** — Intel CNVi WiFi + BT are present but not needed: Proxmox and all workloads run over the Realtek GbE. Leave WiFi disabled in BIOS unless a use case appears.

---

## References

- [ADR 25 — Home Assistant on a Dedicated Thin-Client Node](../decisions/25-home-assistant-thin-client.md)
- [Research 26 — Home Assistant on a thin client (Wyse 5070 + Proxmox)](../research/26-home-assistant-thin-client.md)
- [Research 28 — Wyse 3040 hardware diagnostic](../research/28-wyse3040-hardware-diagnostic.md) — the audit pattern used here
- [Research 24 — Network topology & IP scheme](../research/24-network-topology-design.md)
- [Idea 05 — Home Assistant on a Thin Client](../ideas/05-home-assistant-thin-client.md)
- [Issue #68 — Implement Home Assistant on a thin client node](https://github.com/jaroslaw-bagnicki/Homelab/issues/68) · [sub-issue #82 — diagnostic and initial setup](https://github.com/jaroslaw-bagnicki/Homelab/issues/82)
