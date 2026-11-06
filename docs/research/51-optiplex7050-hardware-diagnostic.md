# 51 — OptiPlex 7050 MFF Hardware Diagnostic: Pre-Boot Audit of the Second Proxmox Node

**Source**: SystemRescue 13.02 live session + hardinfo2 report, 2026-11-05 20:21 UTC · issue [#177 — Provision the OptiPlex 7050 MFF as the second Proxmox VE node](https://github.com/jaroslaw-bagnicki/Homelab/issues/177)

**Scope**: Pre-boot hardware audit of the **Dell OptiPlex 7050 Micro (MFF)** bought on 2026-11-04 and delivered 2026-11-05 — the second Proxmox VE node planned in [idea 15](../ideas/15-second-proxmox-node.md) and [research 47](47-second-proxmox-node.md). Same Phase 0 pattern as the Wyse 3040 ([28](28-wyse3040-hardware-diagnostic.md)), Wyse 5070 ([29](29-wyse5070-hardware-diagnostic.md)), Futro S930 ([31](31-futro-s930-hardware-diagnostic.md)) and Beetle M-III ([32](32-wincor-beetle-m3-hardware-diagnostic.md)) audits: capture the exact specs into `docs/hardware.md` and find the surprises **before** committing an OS to the box.

**Status**: 🔨 In progress — hardinfo2 inventory captured; **BIOS walk, ME/AMT state, disk capacity + SMART, TPM identity and a thermal load test are still pending** ([Pending checks](#pending-checks)). The storage finding was **corrected on 2026-11-06** after physical inspection: an M.2 2280 **SATA** module, not a 2.5″ drive.

---

## Decision Summary

> **Decision authority:** there is no ADR for the second node yet — [idea 15](../ideas/15-second-proxmox-node.md) carries the plan and [research 47](47-second-proxmox-node.md) the analysis. This doc is the Phase 0 audit output for issue #177 and **overturns two of idea 15's hardware premises**: the unit is a **7050**, not the 7040, and its CPU is a **65 W i5-7500**, not a 35 W "T" part. No role decision is taken here.

| Decision | Outcome (as of 2026-11-05) |
|---|---|
| Hardware | Dell **OptiPlex 7050 Micro (MFF)** — serial `3CLD6Q2`, **i5-7500 (4C/4T, 65 W)**, 8 GB (1× 8 GiB, one slot free), SK hynix SC311 **SATA** SSD |
| CPU vs chassis | ⚠️ **i5-7500 is not a factory Micro SKU** — Dell's 7050 **Micro** list is 35 W T-series only; a 65 W part is a previous-owner swap in a socket the chassis was not thermally designed for |
| Power adapter | **130 W** — a documented 7050 Micro option and the correct brick for a 65 W CPU; bigger brick ≠ bigger draw |
| Storage | **M.2 2280 SATA** module (SK hynix SC311 S) in the **M.2 slot**, SATA III over AHCI — **not** a 2.5″ drive, **not** NVMe · the **2.5″ bay is free** |
| Management | **MEBx not reachable** (Ctrl+P silent, no F12 entry) although CPU, Q270 and the I219-LM all satisfy the AMT platform requirements — ME firmware mode or a BIOS switch, not missing hardware |
| Address | DHCP `192.168.2.206` today; `192.168.2.203` is the reserved slot ([idea 15](../ideas/15-second-proxmox-node.md), [ADR 31](../decisions/31-static-address-scheme.md)) |

---

## Context

The 7050 replaces the "OptiPlex 7040 Micro, i5-6500T" that [research 47 §2](47-second-proxmox-node.md) picked as the best pure Proxmox compute node — bought used, sight unseen, so the delivered configuration is what the audit has to establish. Two things decide how much of idea 15 survives contact with the box:

1. **Does the CPU match the chassis' thermal design?** Every other Micro-series option in research 47's table is a 35 W "T" part, and the chassis fan curve is built around that.
2. **Is out-of-band management real?** Idea 15 leans on vPro/AMT for headless recovery, and that is the one feature the thin-client alternatives cannot offer.

---

## Hardware Findings (SystemRescue, 2026-11-05)

### System

| Field | Value |
|---|---|
| Product | Dell **OptiPlex 7050** (Micro / MFF), family "OptiPlex", chassis Desktop |
| Serial / asset tag | `3CLD6Q2` / **`80006161`** — an asset tag is set, i.e. a decommissioned corporate unit (lease return), not consumer stock |
| SKU | `07A1` |
| Board | "055H3G", Dell Inc., A01, SN `/3CLD6Q2/CNPE1008560B1R/` |
| BIOS | Dell Inc. **1.27.0**, released **2023-09-18** — check whether a later build exists before installing |
| CPU | Intel **Core i5-7500** (Kaby Lake, 4C/4T), 3.4 GHz base / 3.8 GHz turbo, 6 MB L3, **65 W TDP**, HWCAPS **x86-64-V3** |
| RAM | **8 GB** — 1× 8 GiB DDR4 SO-DIMM `KMKYF9-MIH`, rated/configured **2400 MT/s**, **DIMM 2 free** |
| Storage | **M.2 2280 SATA SSD** — SK hynix SC311 S, enumerated as `ATA` on the AHCI controller (`00:17.0`); capacity and SMART not captured yet |
| GPU | Intel **HD Graphics 630** (PCI `00:02.0`, i915) |
| NIC (GbE) | Intel **I219-LM** (`enp0s31f6`), PCI `00:1f.6` — the AMT-capable NIC |
| NIC (WiFi) | Intel **Wireless 8265** (`wlp1s0`, PCI `01:00.0` behind root port `00:1c.0`) + Intel Bluetooth |
| Audio | HDA Intel PCH (Realtek codec; DP/HDMI outputs + front line-out/headphone) |
| TPM | **TPM 2.0 present** (ACPI `MSFT0101`) — firmware-vs-discrete still to identify ([research 37](37-tpm2-hardware-and-fleet.md) pattern) |
| Power | AC attached, no battery · **130 W adapter** supplied |
| Cooling | Fan **2281 RPM at idle**, package **44 °C** (SystemRescue, ~4 min uptime) — audible, unlike the fanless Wyse 5070 |
| Session | SystemRescue 13.02, kernel 6.18.41, DHCP `192.168.2.206` on `enp0s31f6` |

### RAM

- **1× 8 GiB DDR4-2400 SO-DIMM, DIMM 2 empty** — the opposite of the Wyse 5070 (both slots full).
- So **16 GB is a single-stick add** and **32 GB is 2× 16 GiB** — Dell's documented ceiling for the model, and the i5-7500's memory controller tops out at DDR4-2400.
- 8 GB is the same starting point as `pve`; unlike `pve`, the upgrade path here is cheap and non-destructive. Sizing the guests is still the real fix ([idea 15](../ideas/15-second-proxmox-node.md) risks).

### Storage — an M.2 2280 SATA module, not a 2.5″ drive and not NVMe

> **Corrected 2026-11-06.** The first pass read the report's AHCI/`ATA` enumeration against Dell's manual and concluded "2.5″ bay, M.2 slot empty". **Physical inspection of the unit settles it the other way:** the drive is an **M.2 2280 SATA III module sitting in the M.2 slot**, and the 2.5″ bay is empty.

**The protocol really is SATA — the boot-list label is not a form-factor hint.** A Dell boot menu listing the drive as *SATA* is simply the truth about the protocol an M.2 SATA module speaks: it hangs off the AHCI controller exactly like a 2.5″ drive. Four independent signals agree and none of them says NVMe:

- the disk enumerates as **`ATA`** on the AHCI controller (`00:17.0`, `scsi4`);
- **no `nvme` module** is loaded and **no NVMe PCI endpoint** exists — the only exposed root port (`00:1c.0`) leads to bus 01, the WiFi card;
- the **SK hynix SC311 S** family is SATA-only by construction (SATA III, 6 Gb/s) and Dell shipped it as an OEM **M.2 2280** module (`HFS128G39TNF-N2A0A`, Dell part `6HG72`);
- the live session saw no NVMe namespace — `sdb` is the only internal disk.

**Dell's manual lists only NVMe for the Micro's M.2 slot.** That table enumerates the options Dell *sold*, not every mode the connector supports — this unit proves the slot takes an M.2 SATA module in practice. Record it, because it cuts against the obvious upgrade assumption: a **B+M key fits either protocol, but the slot's SATA support is not something the manual promises**, and Dell's own guidance is to treat protocol support as a platform property.

**What that means for the build:**

- The **M.2 slot is occupied** by the SATA module → an NVMe upgrade **replaces** it, it does not sit beside it. An M.2 SATA module cannot be demoted to the 2.5″ bay without an M.2→SATA 2.5″ enclosure.
- The **2.5″ bay is free** — that is the cheap second disk, and it needs the caddy and ribbon present (pending).
- So idea 15's `zfspool` has three shapes: **add a 2.5″ SATA SSD** as the pool with Proxmox on the module; **replace the module with NVMe** and leave the bay for later; or mirror across the two — noting that an M.2 + 2.5″ mirror is **one controller and one chassis**, not protection against losing the node.
- Capacity is likely 128 GB (`HFS128G39TNF` is the 128 GB part) but unconfirmed until `lsblk`/`smartctl` are captured.

The drive also carries a **previous installation**: `sdb2` is a 31.7 MiB ESP and `sdb1` a ~57.7 GiB **encrypted** volume (mapped read-only by the live session, 36.3 GiB used) — a BitLocker/LUKS Windows install. To be wiped at install; capture the model, capacity and SMART first (used drive → endurance matters, the lesson from the [Wyse 5070 audit](29-wyse5070-hardware-diagnostic.md)).

---

## Remark 1 — an i5-7500 at 65 W, not a 7500T, on a 130 W adapter

**The adapter is correct.** Dell lists **65 W or 130 W** for the 7050 Micro, and the 130 W brick is the one that pairs with a 65 W CPU. A larger adapter does not consume more energy — the machine draws what it needs — so the only real costs are a physically bigger brick and slightly worse efficiency at a 5–15 W idle load, where a 130 W unit runs far below its sweet spot.

**The CPU is the finding.** Dell's 7050 **Micro** processor table is **T-series only** (i3-6100T/7100T/7300T, i5-6400T/6500T/6600T/7400T/7500T/7600T, i7-6700T/7700T, all 35 W); the 65 W parts belong to the SFF and Mini Tower models of the same generation. A socketed LGA1151 makes the swap trivial, so a **previous owner put a desktop i5-7500 in a chassis whose cooler and fan curve were designed around 35 W** — a used-corporate-unit scenario, and an inconsistency worth noting: a 65 W CPU in a Micro implies someone fitted the bigger adapter deliberately.

| | **i5-7500** (installed) | i5-7500T | i7-7700T |
|---|---|---|---|
| Cores / threads | 4 / 4 | 4 / 4 | **4 / 8** |
| Base / turbo | **3.4 / 3.8 GHz** | 2.7 / 3.3 GHz | 2.9 / 3.7 GHz |
| L3 | 6 MB | 6 MB | 8 MB |
| TDP | **65 W** | 35 W | 35 W |
| Dell Micro SKU | ❌ not listed | ✅ | ✅ |

**Verdict for this lab — keep it, and do not "fix" it with a 7500T.**

- **Idle is platform-dominated.** Both parts idle at 800 MHz; a 24/7 hypervisor's baseline draw is set by the board, the NIC and the SSD, so the 65 W rating costs little when the node is quiet.
- **The extra clocks are worth having.** 3.4/3.8 GHz vs 2.7/3.3 GHz is ~20 % more single-thread headroom for guests — real for a second node that will absorb `vtstack` and the domain controller.
- **A 7500T swap would be a downgrade** in exactly the metric that matters (clocks) for a 30 W paper saving. If the thermal envelope proves to be the problem, the correct move is an **i7-7700T (35 W, 4C/8T)** — the best part that Dell actually shipped in this chassis: +hyper-threading, same 35 W budget, officially supported.
- **What to watch:** sustained all-core load on a 35 W-designed cooler → fan ramp and possible throttling. Measure before deciding (see [Pending checks](#pending-checks)); cap with `intel_rapl`/`cpufreq` only if the measurements justify it.

---

## Remark 2 — MEBx/AMT does not come up

### What the hardware says

AMT on this platform needs three things, and **all three are present**:

| Requirement | Present? | Evidence |
|---|---|---|
| vPro-eligible CPU | ✅ | i5-7500 is listed as **Intel vPro Platform eligible** on Intel ARK |
| Q270 chipset | ✅ | PCI `00:1f.0` = "200 Series PCH LPC Controller **(Q270)**" |
| AMT-capable NIC | ✅ | Intel **I219-LM** at `00:1f.6` (the "-LM" part is the AMT one) |
| ME firmware reachable | ✅ | `mei_me` loaded, `mei_wdt` available |

So the absence of MEBx is **not** a missing-hardware conclusion — it is a **firmware-mode or BIOS-setting** question.

### Ranked hypotheses

| # | Hypothesis | Why it fits | How to confirm |
|---|---|---|---|
| 1 | **ME firmware is in a non-AMT mode** ("Standard Manageability" / AMT capability off in the ME region) | Dell shipped non-vPro SKUs whose ME image has no AMT; the ME region — not the CPU — decides. A corporate-lease unit with an asset tag is exactly where this happens | Intel's `mei-amt-version` from the live session prints the ME firmware version and states plainly whether AMT is present; `cat /sys/class/mei/mei0/fw_ver` |
| 2 | **AMT/MEBx disabled in BIOS** | Enabling AMT and *entering* MEBx are separate steps, and the 7050 BIOS carries a **MEBx Hotkey** option that suppresses the prompt when off (System Configuration / Manageability) | F2 walk — enable AMT + MEBx Hotkey, save, **cold** boot |
| 3 | **Hotkey timing / input path** | Ctrl+P must be hammered the moment the Dell logo appears; a hub, KVM or USB 3 port can eat it, and Fast Boot shortens the window | Wired keyboard straight into a rear port, Fast Boot off, spam Ctrl+P from power-on |
| 4 | **AMT soft-disabled / left unprovisioned in a bad state by the previous IT owner** | The ME re-reads its configuration on **cold** boot only | BIOS reset to defaults, unplug AC for ~30 s, then retry |
| 5 | MEBx expected in the F12 menu | Dell exposes it there on *some* vPro models — its absence here is consistent with 1 or 2 rather than a fifth cause | Check F12 again only after 1–2 are resolved |

### Consequence for the plan

Idea 15 leans on vPro for **out-of-band KVM + remote power**. Do not block the build on MEBx. In order of cost:

1. **BIOS "AC Recovery → On" + Wake-on-LAN** — remote *power*, no console. Enough for a node that boots itself cleanly and is reachable over SSH/Proxmox UI.
2. **An IP-KVM** (JetKVM / NanoKVM class, ~€30–60) — real console and virtual media, if headless recovery becomes a requirement.
3. Accept a physical trip for the rare BIOS-level change.

Regardless of the outcome, **record the ME state** in `docs/hardware.md`: an unconfirmed vPro changes how the node is operated, and a cluster member that cannot be power-cycled remotely is a liability once HA matters.

---

## Implications for idea 15 / issue #177

| Idea 15 / research 47 assumed | Actual | Verdict |
|---|---|---|
| OptiPlex **7040** Micro, **i5-6500T** (35 W) | **7050** Micro, **i5-7500** (65 W) | ⚠️ faster CPU, **outside the chassis' 35 W design** — measure thermals |
| vPro/AMT as the differentiator | CPU + chipset + I219-LM all capable, **MEBx unreachable** | ⚠️ unconfirmed — treat as absent until proven |
| M.2 NVMe **plus** a 2.5″ bay | **M.2 slot holds a SATA module** (no NVMe drive); **2.5″ bay free** | ⚠️ NVMe means *replacing* the module, not adding — but the bay still gives a second disk |
| 32 GB RAM ceiling | 8 GB now, **one slot free** | ✅ 16 GB is one stick |
| Heterogeneous CPUs vs the Wyse (Gemini Lake) | **Kaby Lake, x86-64-v3** — an even wider gap from the J4105 | ⚠️ any cross-node migration needs a conservative VM CPU type, or restarts |
| Address `.203` | free; box currently on DHCP `.206` | ✅ reserve at install |

**No ADR is affected** — the audit changes a hardware assumption inside idea 15, not a decision.

---

## Pending Checks

1. **BIOS walk (F2)** — ME/AMT + MEBx Hotkey, **AC Recovery**, Wake-on-LAN, Fast Boot off, UEFI vs Legacy, Secure Boot, VT-x/VT-d, fan/power profile. Fast Boot off is a prerequisite for the Ctrl+P test.
2. **ME/AMT state** — `mei-amt-version`, `/sys/class/mei/mei0/fw_ver`, `dmesg | grep -i mei`. This single check decides hypothesis 1 and therefore whether vPro exists at all.
3. **BIOS level** — 1.27.0 is from 2023-09-18; check Dell's current release before installing Proxmox (and expect an `intel-microcode` update: the live session reports `old_microcode` **Vulnerable**).
4. **Disk** — `lsblk`, `smartctl -a`: exact model, capacity, POH, `Media_Wearout`/`Total_LBAs_Written`. Used drive → endurance is the decision input, and an NVMe purchase decision hangs off it.
5. **Visual confirmation** — the M.2 2280 SATA module is confirmed in the M.2 slot (2026-11-06). Still to check: is the **2.5″ caddy + ribbon present** for a later second disk, is a RAM slot free, and is the CPU heatsink the 35 W design or a retrofit?
6. **TPM identity** — `tpm2_getcap properties-fixed` → Intel PTT vs discrete (the [research 37](37-tpm2-hardware-and-fleet.md) pattern). A real TPM 2.0 opens the option of a second sealed `step-ca` instance.
7. **Thermal + power measurement under load** — package temperature, fan RPM and wall draw at idle and at all-core load, so the 65 W decision rests on numbers rather than on the TDP label.
8. **ePSA diagnostics** — F12 → Diagnostics, record per-test results (memory, storage, NIC) as the pre-install baseline.
9. **MAC addresses** — record `enp0s31f6` for DHCP reservations / WoL.

---

## Open Questions

1. **Keep the i5-7500 or fit an i7-7700T?** Recommendation: run the 7500 first and judge it on measurements; if sustained load brings fan noise or throttling, the 7700T is the upgrade that respects the 35 W chassis design — and it adds hyper-threading, which the 7500T would not.
2. **Change the boot medium before the Proxmox install?** The M.2 slot holds a SATA module, so this is either *add a 2.5″ SATA SSD and keep Proxmox on the module*, or *replace the module with NVMe*. Deciding before the install is dramatically cheaper than migrating guests onto ZFS later (idea 15 step 7).
3. **Is vPro worth chasing at all?** If the ME firmware is not in AMT mode, no BIOS setting will bring MEBx back. Decide between AC Recovery + WoL, an IP-KVM, or accepting manual power.
4. **Rename first, or build `pve2` standalone?** Unchanged from idea 15: the `pve` → `pve1` rename must land **before** a cluster exists, but it is not a prerequisite for provisioning this node (issue #177 keeps the cluster out of scope).

---

## References

- [Idea 15 — a second Proxmox node](../ideas/15-second-proxmox-node.md) — the plan this hardware serves
- [Research 47 — a second Proxmox node](47-second-proxmox-node.md) — the cluster/HA/replication analysis and the candidate comparison
- Audit pattern: [research 28](28-wyse3040-hardware-diagnostic.md) · [research 29](29-wyse5070-hardware-diagnostic.md) · [research 31](31-futro-s930-hardware-diagnostic.md) · [research 32](32-wincor-beetle-m3-hardware-diagnostic.md)
- [Research 37 — TPM 2.0 and the fleet](37-tpm2-hardware-and-fleet.md) · [ADR 31](../decisions/31-static-address-scheme.md) (addressing) · [ADR 33](../decisions/33-fleet-node-hostnames.md) (hostnames) · [runbook 28](../runbooks/28-pve-proxmox-node.md) (the incumbent node's build)
- Intel ARK — [Core i5-7500](https://www.intel.com/content/www/us/en/products/sku/97123/intel-core-i57500-processor-6m-cache-up-to-3-80-ghz/specifications.html) (TDP, vPro Platform eligibility)
- SK hynix **SC311** — SATA III / M.2 2280 module, Dell OEM part `6HG72` (`HFS128G39TNF-N2A0A`): the installed drive
- Dell — [OptiPlex 7050 Micro Owner's Manual](https://dl.dell.com/topicspdf/optiplex-7050-desktop_owners-manual3_en-us.pdf) (storage table: 2.5″ SATA + M.2 2280 PCIe NVMe — **NVMe only in the option list**, while the delivered unit runs an M.2 SATA module; processor table: 35 W T-series only; 65 W / 130 W adapters)
- Dell KB — [M.2 NVMe device specifications and upgrade requirements](https://www.dell.com/support/kbdoc/en-in/000178253/m-2-nvme-device-specifications-and-upgrade-requirements-for-precision-optiplex-latitude-and-xps-systems) — a B+M key fits either protocol; support is a platform property
- Dell KB — [How to enter the Intel AMT configuration menu on MEBx-enabled vPro computers](https://www.dell.com/support/kbdoc/en-td/000228454/how-to-enter-the-intel-amt-configuration-menu-on-mebx-enabled-vpro-computers)
