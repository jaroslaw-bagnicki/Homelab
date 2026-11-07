# 52 — OptiPlex 7050 MFF Hardware Diagnostic: Pre-Boot Audit of the Second Proxmox Node

**Source**: SystemRescue 13.02 live session + hardinfo2 report, 2026-11-05 20:21 UTC · issue [#177 — Provision the OptiPlex 7050 MFF as the second Proxmox VE node](https://github.com/jaroslaw-bagnicki/Homelab/issues/177)

**Scope**: Pre-boot hardware audit of the **Dell OptiPlex 7050 Micro (MFF)** bought on 2026-11-04 and delivered 2026-11-05 — the second Proxmox VE node planned in [idea 15](../ideas/15-second-proxmox-node.md) and [research 47](47-second-proxmox-node.md). Same Phase 0 pattern as the Wyse 3040 ([28](28-wyse3040-hardware-diagnostic.md)), Wyse 5070 ([29](29-wyse5070-hardware-diagnostic.md)), Futro S930 ([31](31-futro-s930-hardware-diagnostic.md)) and Beetle M-III ([32](32-wincor-beetle-m3-hardware-diagnostic.md)) audits: capture the exact specs into `docs/hardware.md` and find the surprises **before** committing an OS to the box.

**Status**: 🔨 In progress — hardinfo2 inventory, the F2 BIOS walk, the F12 boot menu, ePSA, the BIOS-level check, **disk SMART**, **ME firmware** and **Memtest86+** are captured; **TPM vendor, MAC, the AMT verdict and the OS-side power/thermal trio are still pending** ([Pending checks](#pending-checks)).

---

## Decision Summary

> **Decision authority:** [ADR 47](../decisions/47-second-proxmox-node-cluster-qdevice.md) owns the
> second-node decision; [idea 15](../ideas/15-second-proxmox-node.md) carries the lifecycle and
> [research 47](47-second-proxmox-node.md) the analysis. This doc is the Phase 0 audit output for issue
> #177 and **overturns two of idea 15's hardware premises**: the unit is a **7050**, not the 7040, and
> its CPU is a **65 W i5-7500**, not a 35 W "T" part.

| Decision | Outcome (as of 2026-11-05) |
|---|---|
| Hardware | Dell **OptiPlex 7050 Micro (MFF)** — serial `3CLD6Q2`, **i5-7500 (4C/4T, 65 W)**, 8 GB (1× 8 GiB, one slot free), SK hynix SC311 **SATA** SSD |
| CPU vs chassis | ⚠️ **i5-7500 is not a factory Micro SKU** — Dell's 7050 **Micro** list is 35 W T-series only; a 65 W part is a previous-owner swap in a socket the chassis was not thermally designed for |
| Power adapter | **130 W** — a documented 7050 Micro option and the correct brick for a 65 W CPU; bigger brick ≠ bigger draw |
| Storage | **M.2 2280 SATA** module (SK hynix SC311 S) in the **M.2 slot**, SATA III over AHCI · the **2.5″ bay is free** · 11 134 POH but **~97 % endurance remaining** — sound; **128 GB capacity** is the only argument for a bigger disk |
| Management | **MEBx not reachable** (Ctrl+P silent, no F12 entry) although CPU, Q270 and the I219-LM all satisfy the AMT platform requirements — the BIOS has **no `Intel AMT Capability` page** and `MEBx Hotkey` is already on, so the answer lies in the ME firmware, not in a setting |
| Address | DHCP `192.168.2.206` today; `192.168.2.202` is the reserved slot ([idea 15](../ideas/15-second-proxmox-node.md), [ADR 31](../decisions/31-static-address-scheme.md)) |

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
| BIOS | Dell Inc. **1.27.0** — SMBIOS build date **2023-09-18**, published by Dell **2023-11-15**; that is the **current release**, so there is nothing to flash ([gate item 4](#pre-install-gate--do-these-before-the-proxmox-installer-runs)) |
| CPU | Intel **Core i5-7500** (Kaby Lake, 4C/4T), 3.4 GHz base / 3.8 GHz turbo, 6 MB L3, **65 W TDP**, HWCAPS **x86-64-V3** |
| RAM | **8 GB** — 1× 8 GiB DDR4 SO-DIMM `KMKYF9-MIH`, rated/configured **2400 MT/s**, **DIMM 2 free** |
| Storage | **M.2 2280 SATA SSD** — SK hynix SC311 SATA 128GB, enumerated as `sda` on the AHCI controller (`00:17.0`); **119.2 GiB, unpartitioned**, **11 134 POH**, **~97 % endurance remaining** ([SMART](#the-module-is-sound-and-it-is-empty-smart-2026-11-06)) |
| GPU | Intel **HD Graphics 630** (PCI `00:02.0`, i915) |
| NIC (GbE) | Intel **I219-LM** (`enp0s31f6`), PCI `00:1f.6` — the AMT-capable NIC |
| NIC (WiFi) | Intel **Wireless 8265** (`wlp1s0`, PCI `01:00.0` behind root port `00:1c.0`) + Intel Bluetooth |
| Audio | HDA Intel PCH (Realtek codec; DP/HDMI outputs + front line-out/headphone) |
| TPM | **TPM 2.0 present** (ACPI `MSFT0101`) — firmware-vs-discrete still to identify ([research 37](37-tpm2-hardware-and-fleet.md) pattern) |
| Power | AC attached, no battery · **130 W adapter** supplied · BIOS event log carries historical `Unknown AC power adapter` alerts ([below](#bios-event-log--the-adapter-history)) · **23.2 W at the wall in BIOS Setup, 19.7 W at PXE** ([pre-OS, not idle](#power-draw--measured-pre-os)) |
| Cooling | Fan **2281 RPM at idle**, package **44 °C** (SystemRescue, ~4 min uptime) — audible, compared against the M910q [below](#noise--measured-against-the-m910q) · reconfirmed 2026-11-06: package **42 °C**, `dell_smm` fan **2266 RPM** at idle · **54–55 °C under a full Memtest86+ core load** at 3.4 GHz |
| Session | SystemRescue 13.02, kernel 6.18.41, DHCP `192.168.2.206` on `enp0s31f6` |

### Noise — measured against the M910q

Measured 2026-11-06 with a sound-level meter, both machines at idle in the same room:

| Distance | 7050 (i5-7500, 65 W) | M910q (i5-7500T, 35 W) | Δ |
|---|---|---|---|
| 0.3 m | **37.3 dB** | 36.1 dB | +1.2 dB |
| 0.2 m | **38.2 dB** | 36.4 dB | +1.8 dB |

This is the cleanest comparison the fleet can offer: **the same 4C/4T Kaby Lake silicon at two TDPs**, in two Micro/Tiny chassis. The 7050 is quieter than expected for a 65 W part in a 35 W chassis — the gap is **1–2 dB, not the 10 dB that reads as "twice as loud"**.

Three things to keep in mind before acting on it:

- **The readings are relative, not calibrated.** Weighting and ambient level were not recorded, and the distance behaviour does not follow inverse-square law: 0.3 m → 0.2 m should add ~3.5 dB, but the 7050 gained 0.9 dB and the M910q 0.3 dB. Near-field readings at that range are dominated by room reflections and background, so treat the numbers as a ranking between the two boxes rather than as SPL figures.
- **Perception is not level.** A perception of *"much louder"* at a 1–2 dB difference points at **tonal character** — fan pitch and blade-pass frequency — rather than at acoustic power (1.2 dB ≈ 32 % more power, well under the "twice as loud" 10 dB step). The 7050 spins **2281 RPM at idle**; a 35 W CPU lets the M910q sit on a lower fan curve.
- **Check the cooler before judging the design.** The unit is a 2018 machine whose BIOS event log records the cover removed repeatedly, idling at 44 °C. Dust in the heatsink and tired thermal paste raise both temperature and RPM: clean the fan/heatsink and repaste before drawing conclusions, then re-measure.

**If the noise matters for placement** — the 35 W part is the lever, and the M910q is the evidence: an **i7-7700T (35 W, 4C/8T)** would both cut the fan curve and add hyper-threading. Cheaper knobs first: keep **TurboBoost off** (as it is), cap the package with `intel_rapl`, and chart fan RPM in Netdata so the ramp is visible rather than anecdotal.

**At full speed the ceiling is 59 dB.** ePSA's fan test drove the fan to its high-water mark and the meter read **~59 dB** — against **37.3 dB** at the 2278 RPM idle reading, a **+22 dB** step (roughly 160× the acoustic power, four times the perceived loudness). Read it as a ceiling, not a like-for-like comparison:

- The ePSA health page reports the fan's **high = 2908 RPM** against an idle 2278 RPM — only 1.28× — and broadband fan noise scales roughly with the **fifth power of RPM**, which predicts ~+5 dB, not +22. So the fan test either runs past the sampled high-water mark or the blade passing hits a tonal resonance; either way the mechanism is not simple scaling.
- The idle figures were taken at 0.3 m and 0.2 m; unless the 59 dB reading used the same distance and weighting, the two are not directly comparable.

The planning conclusion holds regardless: **under sustained load this chassis is loud** (59 dB at close range is vacuum-cleaner territory), which is the strongest argument yet for keeping TurboBoost off, capping the package, and treating placement — not soundtrack — as the design constraint.

### Power draw — measured, pre-OS

Measured at the wall on 2026-11-06, 130 W adapter:

| State | Draw |
|---|---|
| **BIOS Setup screen** | **23.2 W** |
| **PXE boot** (network boot, IP stack up) | **19.7 W** |
| **Memtest86+** (4 cores at 3.4 GHz, test 42 %, 0 errors) | **33.3 W** |

All three are **pre-OS** numbers, and none is the node's idle figure:

- **BIOS Setup runs the CPU flat out at base clock with no OS power management** — no P/C-state entry, no governor, no ASPM policy, all cores awake and the graphics engine redrawing. A 65 W-TDP Kaby Lake at 3.4 GHz with management disabled is a 10 W+ CPU on its own, which is exactly what makes this the *worst* state to quote as an idle baseline.
- **PXE is cheaper than Setup by 3.5 W** for the same reason in reverse: the setup UI's graphics and keyboard polling go away, while the NIC and stack stay awake. Still no OS power management.
- **Memtest86+ is the first genuine *load* reading.** All four cores run at the 3.4 GHz base clock for the whole test, so **33.3 W** is the top of the pre-OS range rather than another idle-ish state — **+10.1 W over BIOS Setup** for a full core load, with the package at **54–55 °C** on the 35 W-designed cooler and TurboBoost still off. That brackets the node's sustained integer-workload envelope from above; an AVX-heavy guest or an OS with working C-states moves it, which is what the OS-side trio below is still for.
- **A 130 W brick is inefficient at this load.** At ~20 W output the adapter sits far below its sweet spot, so the wall figure carries more conversion loss than the same box on a 65 W unit would. It does not argue for a smaller adapter — a 65 W CPU config needs the 130 W unit — but it is part of why the number looks high.

**What actually matters is the OS idle figure**, after Proxmox has settled: C-states, `cpufreq`, ASPM and a dark display typically take a large bite out of a pre-OS reading. Measure it the same way (same meter, same socket) for **OS idle**, **OS idle with a guest running**, and **all-core load**, and record them here — that trio is what sizes the UPS and the always-on budget.

Two things also worth knowing before blaming the platform: the **research 47 idle figure of ~9–11 W for a 7040 Micro was unsourced model output**, not a measurement, and wireless radios were enabled when these readings were taken (they are now disabled in BIOS).

**Is the adapter responsible?** Only marginally. A 130 W brick at ~20 W output is perhaps **1–2 W worse** in conversion loss than a 65 W unit would be, and that is the whole of the adapter's share. It also cannot inflate the reading the other way: an adapter the firmware cannot identify gets the platform **throttled**, which lowers draw — and no `Unknown AC power adapter` alert was logged for the current boot. The 2018-era 65 W-class CPU with management off is the dominant term, not the brick.

**And the 0 W with the machine off is a fact about the meter, not the adapter.** A plugged-in brick always draws standby power (fractions of a watt to a couple of watts), so a reading of exactly `0 W` means the meter does not resolve the low end — roughly the same instrument limitation that makes sub-5 W readings untrustworthy. Validate it with a **known load at a similar level** (a 60–100 W lamp, a kettle on the low setting) before treating 23.2 W and 19.7 W as precise; the *difference* between states is the more reliable signal than either absolute value.

**The adapter-rating A/B is not worth running.** Dell pairs the two supplies with the CPU class — **65 W (19.5 V, 3.34 A) for 35 W processors, 130 W (19.5 V, 6.7 A) for 65 W processors**, same 19.5 V and the same 4.5 × 3.0 mm barrel with an ID pin — so a 65 W brick on this box is *below* Dell's own pairing, and the platform reacts by throttling or refusing (`Underpowered AC power adapter, unable to proceed` is already in this unit's event log). That reaction changes the CPU state, which destroys the comparison: a drop from 23.2 W would prove throttling, not adapter efficiency. On top of that, the only 65 W Dell unit to hand is the **Wyse 5070's — the live `pve1` node's adapter** — so the test costs an outage of the fleet CA, the log store, the Netdata parent and the NUT server to chase a 1–2 W effect that sits inside the error of a meter reading `0 W` at standby. **Keep the 130 W unit.**

### Boot menu (F12) and ePSA, 2026-11-06

- **`Boot mode is set to: UEFI; Secure Boot: OFF`** — the install can stay on UEFI with Secure Boot off, which is what Proxmox expects.
- The **internal disk appears only under `LEGACY BOOT`** (`P4: SK hynix SC311 SATA 128GB`), with `UEFI BOOT` listing just the NIC (IPv4/IPv6) — the leftover Windows install is a **legacy/MBR** image. After the wipe the installer will create the UEFI entry itself; the USB installer will appear under `UEFI BOOT` when inserted.
- **No MEBx entry in F12** — consistent with everything else on the AMT thread.
- `OTHER OPTIONS` exposes **`BIOS Flash Update`** and **`Change Boot Mode Settings`**, so the BIOS-update step needs nothing but a FAT32 USB stick.
- **ePSA ran clean** — *"No problems have been found with this system so far"* at the memory-test prompt. System Health reported **fan 2278 RPM current / 2908 high / 2265 low**, **HDD 37 °C** (33–39 °C) and **CPU thermistor 36 °C** (33–36 °C).

### Firmware settings observed (F2 walk, 2026-11-06)

The BIOS is the 2017-generation layout — relevant because every recent Dell MEBx article assumes the newer one.

| Page | Setting | Value |
|---|---|---|
| System Information | BIOS / service tag / asset tag | **1.27.0** · `3CLD6Q2` · `80006161` · ownership date **07/10/2018** |
| System Information | Memory | 8192 MB, 2400 MHz, **Single** channel, `*** DIMM 2 Size Empty ***` |
| System Information | **Slot1_M.2** | **SATA Installed** — the firmware itself reports the M.2 slot's drive as SATA |
| System Information | Slot2_M.2 | Network (the 8265 WiFi card) |
| Security | Admin Password | **set** |
| Security | **M.2 SATA SSD Password** | present as a menu item — the platform expects an M.2 **SATA** drive |
| Security → TPM 2.0 Security | TPM On · Attestation Enable · Key Storage Enable · SHA-256 · **Enabled** | TPM 2.0 active; PTT-vs-discrete still to read with `tpm2_getcap` |
| Manageability | **USB Provision** | present |
| Manageability | **MEBx Hotkey** | **enabled** (checked) |
| Advanced configurations | ASPM | **Auto** |

Second pass (2026-11-06):

| Page | Setting | Value |
|---|---|---|
| Security | **OROM Keyboard Access** | **Enabled** — confirmed; this is the option that gates Ctrl+P / F12 MEBx, and it is already on ([Remark 2](#remark-2--mebxamt-does-not-come-up)) |
| System Configuration → SATA Operation | **AHCI** | correct for Proxmox and ZFS — no RAID/RST to undo |
| System Configuration → Drives | `SATA-0` **(none)** · **`SATA-4` = 128 GB SSD, SK hynix SC311 SATA 128GB** · `M.2 PCIe SSD-0` **(none)** | the module enumerates on a SATA port; the **2.5″ bay (SATA-0) is empty** and **no NVMe device** is present — capacity confirmed **128 GB** |
| System Configuration → Integrated NIC | **Enabled**; *Enable UEFI Network Stack* **enabled** | UEFI PXE available; Wake-on-LAN is a separate setting |
| Manageability → USB Provision | **Enable USB Provision — checked** | the BIOS offers **AMT provisioning from USB**, i.e. the platform is AMT-capable |
| Virtualization Support | Virtualization ✅ · **VT for Direct I/O ✅** · Trusted Execution ☐ | VT-x and VT-d both on; TXT off, which nothing here needs |
| Wireless → Wireless Device Enable | WLAN/WiGig ☐ · Bluetooth ☐ | **both radios disabled** — right for a hypervisor |
| Performance | **Intel TurboBoost ☐ off** · Limit CPUID ☐ | the chip tops out at its **3.4 GHz base**, not the 3.8 GHz turbo |
| Power Management | **AC Recovery** — `Power Off` / `Power On` / `Last Power State` | set **`Power On`**: the node returns by itself after an outage ([remote power](#consequence-for-the-plan)) |
| Power Management | **Deep Sleep Control** — `Disabled` / `S5 only` / `S4+S5` | leave **`Disabled`**: the page warns that enabling it disables **remote wake and manageability** while shut down |
| Power Management | **USB Wake Support** ✅ · **Block Sleep (S3)** ☐ | USB wake on; sleep not blocked — irrelevant at runtime, both harmless on a 24/7 node |
| Power Management → Wake on LAN/WLAN | `Disabled` / **`LAN Only`** / `WLAN Only` / `LAN or WLAN` / `LAN with PXE Boot` | set **`LAN Only`** — the setting that lets a magic packet start the node with no vPro |
| POST Behavior | **Fastboot** — `Minimal` / `Thorough` / `Auto` · plus *Extend BIOS POST Time*, *Adapter Warnings*, *Keyboard Errors*, *Warnings and Errors* | set **`Thorough`** and a non-zero **`Extend BIOS POST Time`** — the reliable way to catch Ctrl+P |

Notable absences: the **Manageability** group contains only `USB Provision` and `MEBx Hotkey` — there is **no `Intel AMT Capability` page**, the exact item Dell's KB instructs the customer to enable.

#### BIOS event log — the adapter history

| Date | Event |
|---|---|
| 2026-11-05 (4×) | `Alert! Cover was previously removed` — **no adapter alert on the current boot** |
| 2026-06-29 (4×) | `Alert! Unknown AC power adapter. may affect performance` |
| 2026-10-22 | **`Alert! Underpowered AC power adapter, unable to proceed`** |
| 2024-09-06 (3×) · 2026-06-01 (5×) | Cover removals; one `Keyboard not found` (headless) |

**Reading it:** the platform was previously run on a brick it could **not identify**, and in October it refused to proceed on an underpowered one. An unidentified adapter is not a cosmetic warning — Dell firmware treats it as "unknown wattage" and can throttle the CPU or stop the boot. **No adapter alert is recorded for the 2026-11-05 boot**, which is consistent with the supplied 130 W unit being recognised; still, the device-history bar is set by the October entry, so the adapter is a component to keep genuine and to watch rather than a settled fact.

### RAM

- **1× 8 GiB DDR4-2400 SO-DIMM, DIMM 2 empty** — the opposite of the Wyse 5070 (both slots full).
- **The two tools disagree on *which* slot is which.** Dell's BIOS reports `*** DIMM 2 Size Empty ***`, while Memtest86+ lists the module as **`Slot 2: 8GB DDR4-2400 — Kingston KMKYF9-MIH (2018-W14)`**. Both agree on the fact that matters — **one module fitted, one slot free** — but confirm the free slot physically before buying the second stick: memtest numbers SPD devices, Dell numbers the board silkscreen.
- SPD also pins the part and the speed: **Kingston `KMKYF9-MIH`, 2400 MT/s, week 14 of 2018**, link running **1202 MHz IMC (DDR4-2405) at CAS 17-17-17-39** — rated speed, single channel, no downclocking.
- **Memtest86+ 7.20 passed with 0 errors** (2026-11-06) across its full pattern sweep, at 3.4 GHz all-core with the package at 54–55 °C — the stick is good and the module is stable under sustained load.
- So **16 GB is a single-stick add** and **32 GB is 2× 16 GiB** — Dell's documented ceiling for the model, and the i5-7500's memory controller tops out at DDR4-2400.
- 8 GB is the same starting point as `pve1`; unlike `pve1`, the upgrade path here is cheap and non-destructive. Sizing the guests is still the real fix ([idea 15](../ideas/15-second-proxmox-node.md) risks).

### Storage — an M.2 2280 SATA module in the M.2 slot

The drive is an **M.2 2280 SATA III module sitting in the M.2 slot**, and the **2.5″ bay is empty**.

**The interface is SATA.** Dell's boot list shows the drive as *SATA* because that is the protocol an M.2 SATA module speaks — it hangs off the AHCI controller exactly like a 2.5″ drive, so the label describes the interface, not where the module sits. Four independent signals agree, and none of them says NVMe:

- the disk enumerates as **`ATA`** on the AHCI controller (`00:17.0`, `scsi4`);
- **no `nvme` module** is loaded and **no NVMe PCI endpoint** exists — the only exposed root port (`00:1c.0`) leads to bus 01, the WiFi card;
- the **SK hynix SC311 S** family is SATA-only by construction (SATA III, 6 Gb/s) and Dell shipped it as an OEM **M.2 2280** module (`HFS128G39TNF-N2A0A`, Dell part `6HG72`);
- no NVMe namespace exists — **`sda`** is the only internal disk (the Ventoy installer stick is `sdc`).

**Dell's manual lists only NVMe for the Micro's M.2 slot** — that table enumerates the options Dell *sold*, not every mode the connector supports, and this unit runs an M.2 SATA module in it. Worth knowing before an upgrade: a **B+M key fits either protocol, but protocol support is a platform property** — verify with a live-boot test rather than assuming.

**What that means for the build:**

- The **M.2 slot is occupied** by the SATA module → an NVMe upgrade **replaces** it, it does not sit beside it. An M.2 SATA module cannot be demoted to the 2.5″ bay without an M.2→SATA 2.5″ enclosure.
- The **2.5″ bay is free** — that is the cheap second disk, and it needs the caddy and ribbon present (pending).
- So idea 15's `zfspool` has three shapes: **keep Proxmox on the module** — it is healthy ([SMART read below](#the-module-is-sound-and-it-is-empty-smart-2026-11-06)) — and add a **2.5″ SATA SSD** as the pool, which needs the caddy and ribbon; **replace the module with NVMe** and leave the bay for later; or **both** for a mirror — noting that an M.2 + 2.5″ mirror is **one controller and one chassis**, not protection against losing the node.
- Capacity is **128 GB** (`SK hynix SC311 SATA 128GB`), confirmed by the BIOS **Drives** page, which also shows `SATA-0` (the 2.5″ bay) and `M.2 PCIe SSD-0` as **(none)** — the module is the only internal disk.
- **`SATA Operation` is AHCI** — nothing to undo before Proxmox.

#### The module is sound, and it is empty (SMART, 2026-11-06)

`smartctl -a /dev/sda`, SystemRescue 13.02:

| Field | Value |
|---|---|
| Model / serial / firmware | SK hynix **SC311 SATA 128GB** · `MJ85N536011005C0V` · `70000P10` |
| Form factor / link | **M.2**, SATA 3.2 negotiated at **6.0 Gb/s**, 512 B logical / 4 KiB physical, TRIM deterministic, SMART **PASSED** |
| Capacity | 128,035,676,160 bytes — **119.2 GiB** |
| **Power-on hours** | **11 134** — 464 days, ~1.3 years of on-time |
| **Power-cycle count** | **12 049** — ~1.08 cycles per hour of on-time, against **140 unexpected power losses**: a machine that was restarted constantly |
| **Media_Wearout_Indicator** | raw **97** → **~97 % of rated endurance remaining** · normalized reads **4 / 100** (worst 1), which is **not** a life percentage on this firmware — see below |
| Erase counters | `Wear_Leveling_Count` raw **49** = average erases per block · `Total_Erase_Count` **700 941** · **max/min per block 86 / 22** → **≤ 9 % of block endurance used** |
| Write / read counters | `Total_Writes_GB` 33 164 791 682 · `Total_Reads_GB` 24 367 235 118 — vendor units, **not** directly mappable to TBW |
| Health counters | retired / reallocated blocks **0** · `Erase_Fail_Count` 385 · `Soft_ECC_Correction` 368 · `Command_Timeout` 116 · `UDMA_CRC_Error_Count` **0** (link and controller clean) |
| Self-tests | short tests pass; the extended test was aborted by host at 90 % |

**The wear reading was misread, and the erase counters correct it.** The first pass took `Media_Wearout_Indicator` normalized `4 / 100` as 96 % consumed. It is not — the physical counters cap the wear far below that: `Wear_Leveling_Count` raw **49** is the *average* erase count per block and `Max_Erase_Count` **86** the worst block, against client-TLC endurance of roughly **1 000–1 500 P/E cycles**, so **≤ 9 % is consumed**. A drive that had really spent 97 % of its endurance would show ~970 erases on its worst block, not 86. Raw **97** is therefore the percentage *remaining* — which is also how [research 29](29-wyse5070-hardware-diagnostic.md) reads the identical model in `pve1`. The normalized `VALUE 004 / WORST 001` is anomalous on this firmware: the `WORST` column bottoms at 1 on healthy attributes too (`Soft_ECC_Correction` reports `VALUE 100 / WORST 001`), so it is not a life percentage and must not be quoted as one.

**Verdict: the module is sound.** PASSED, zero reallocated or retired blocks, zero reported uncorrectable errors, zero link CRC errors, and **~97 % of its endurance left** at 11 134 hours. **Capacity is the only reason to change it** — 128 GB is workable (the `pve1` node runs the same drive with a VM and four LXCs) but tight if guests need real disk; a larger disk is a comfort upgrade, not a rescue.

**And it is empty.** `lsblk` on 2026-11-06 shows `sda` with **no partitions at all** — there is no Windows install left to preserve or wipe. That also corrects the 2026-11-05 reading: the "31.7 MiB ESP + ~57.7 GiB encrypted volume, 36.3 GiB used" was the **Ventoy installer stick**, not this disk — Ventoy's layout is exactly a ~58 GB exFAT data partition plus a 32 MiB `VTOYEFI` partition, and it accounts for every number in that description. The `P4: SK hynix … 128GB` entry under `LEGACY BOOT` is a stale BIOS option pointing at a disk that no longer carries a boot image.

---

## Remark 1 — an i5-7500 at 65 W, not a 7500T, on a 130 W adapter

**The adapter is correct in rating.** Dell lists **65 W or 130 W** for the 7050 Micro, and the 130 W brick is the one that pairs with a 65 W CPU. A larger adapter does not consume more energy — the machine draws what it needs — so the only real costs are a physically bigger brick and slightly worse efficiency at a 5–15 W idle load, where a 130 W unit runs far below its sweet spot.

**But the event log says the platform polices the adapter.** Four `Unknown AC power adapter` alerts on 2026-06-29 and one `Underpowered AC power adapter, unable to proceed` on 2026-10-22 come from a brick the BIOS could not identify — a non-Dell unit, or one with a damaged ID pin. Dell firmware treats an unidentified adapter as unknown wattage and may throttle or stop the boot. The current 130 W unit logs **no** alert, so it is recognised; the requirement for a permanent node is simply that it stays a **genuine Dell adapter of the right wattage**.

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
- **TurboBoost is off** in BIOS, so the chip currently runs at its **3.4 GHz base** and never reaches 3.8 GHz. That is a deliberate-looking power/thermal cap — and it still beats the 7500T's 3.3 GHz turbo. Decide it with the thermal measurement: enable TurboBoost if the node can take the burst, leave it off if noise matters more.

---

## Remark 2 — MEBx/AMT does not come up

### What the hardware says

AMT on this platform needs three things, and **all three are present**:

| Requirement | Present? | Evidence |
|---|---|---|
| vPro-eligible CPU | ✅ | i5-7500 is listed as **Intel vPro Platform eligible** on Intel ARK |
| Q270 chipset | ✅ | PCI `00:1f.0` = "200 Series PCH LPC Controller **(Q270)**" |
| AMT-capable NIC | ✅ | Intel **I219-LM** at `00:1f.6` (the "-LM" part is the AMT one) |
| ME firmware reachable | ✅ | `mei_me` loaded, `mei_wdt` available · **CSME `11.8.94.4494`** read from `/sys/class/mei/mei0/fw_ver` ([below](#me-firmware--csme-118944494-alive-but-still-unproven-2026-11-06)) |

So the absence of MEBx is **not** a missing-hardware conclusion — it is a **firmware-mode or BIOS-setting** question.

### ME firmware — CSME 11.8.94.4494, alive but still unproven (2026-11-06)

`cat /sys/class/mei/mei0/fw_ver` answers, so the ME is **running and responsive** — it is not absent, and there is no sign of the `FW Status Recovery Error` state the Dell article screenshots:

```
0:11.8.94.4494
0:11.8.94.4494
0:11.8.50.3425
```

Two partitions report the running build **11.8.94.4494** (a late CSME 11.8 release, the Kaby-Lake-era branch), the third reports an older **11.8.50.3425** image — the recovery/ROM copy, which keeps its original version. **This is what a healthy ME looks like**, so hypothesis 5 loses most of its weight and the question narrows to one: *is this ME image an AMT (corporate) build?* The version string cannot answer that — `mei-amt-version` can, and it has not been run yet.

### What Dell's KB says, and what it changed here (2026-11-06)

Dell KB [000199831 — Unable to access the MEBx vPro menu using the F12 boot menu](https://www.dell.com/support/kbdoc/en-gb/000199831/unable-to-access-the-mebx-vpro-menu-using-the-f12-boot-menu-on-precision-3660) gives the vendor answer: MEBx appears in the **F12 menu** only once a **BIOS admin password is set** *and* **`Enable Intel AMT Capability`** is on under **System Management → Intel AMT Capability**. The same page states MEBx is also blocked when **Device Configuration Hotkey Access** is disabled.

**Outcome on this unit: a BIOS admin password was set, and nothing changed** — no MEBx entry in F12, no Ctrl+P prompt. The BIOS walk then explains why:

- **The 7050 has no `Intel AMT Capability` page.** Its **Manageability** group holds only `USB Provision` and `MEBx Hotkey`, and the latter is **already enabled**. There is no *Device Configuration Hotkey Access* either — both are items of the newer BIOS generation the article's affected-platform list covers (Latitude 9430/5431/5430/5530, OptiPlex 5000/7000, Precision 3460/3660/3571/5570). **The article's resolution cannot be applied to this machine: there is nothing to enable.**
- **Its own illustration shows the AMT page in a `FW Status Recovery Error` state** — the condition in which AMT cannot be enabled from BIOS at all, whatever the password or capability setting says. That state is not observable from these menus.
- **The password only unlocks the hotkey.** It proves nothing about whether the ME runs an AMT-capable image.

So for this platform only two causes remain, and neither is a menu item: the **Ctrl+P window being missed** (Fastboot, POST time, keyboard init) or the **ME firmware not presenting MEBx**. Two BIOS details argue that AMT *is* present: `Manageability → USB Provision` is enabled and describes provisioning **Intel AMT** from a USB device, which a non-AMT image would have no use for — and the admin password only unlocks the hotkey, so it proves nothing about the firmware.

The remaining causes are therefore narrower than the original list: the **ME image is not an AMT build**, the **ME configuration is in a state that withholds MEBx** (never provisioned, or left soft-disabled by the previous owner), or **the hotkey window is being missed**. `Device Configuration Hotkey Access` is *not* on that list — this BIOS generation does not have the item. The ME-level check below, not another BIOS walk, is what separates them.

### The gate Dell names: OROM Keyboard Access — ruled out

`Security → OROM Keyboard Access` is the platform's own switch for this: *"whether users are able to enter Option ROM Configuration screens via hotkeys during boot. Specifically this setting is capable of preventing access to Intel RAID (CTRL+I) or **Intel Management Engine BIOS Extension (CTRL+P/F12)**"*. If it is off, **no other BIOS setting can surface MEBx** — `MEBx Hotkey` and the admin password are downstream of it.

**It is `Enabled` on this unit.** With that, the hotkey enabled and the password set, **every BIOS-side condition Dell documents for MEBx is satisfied** — so the remaining causes are outside the menus: the POST window being too short to hit Ctrl+P, or the ME firmware not presenting MEBx.

**Next, in this order:**

1. **`POST Behavior → Fastboot = Thorough`** and a non-zero **`Extend BIOS POST Time`** — `Minimal` deliberately skips hardware initialisation, which shortens the window in which the hotkey is read; and the BIOS event log already recorded a `Keyboard not found`, so keyboard initialisation is worth giving time to.
2. **`Deep Sleep Control = Disabled`** if it is currently enabled — the page warns it disables **remote wake and manageability** when the system is shut down, which is where a cluster node spends its repairs.
3. **`mei-amt-version`** from the live session if Ctrl+P still does nothing — the one piece of evidence no BIOS page can give.

### Ranked hypotheses

| # | Hypothesis | Why it fits | How to confirm |
|---|---|---|---|
| 1 | **ME firmware is in a non-AMT mode** ("Standard Manageability" / AMT capability off in the ME region) | Dell shipped non-vPro SKUs whose ME image has no AMT; the ME region — not the CPU — decides. A corporate-lease unit with an asset tag is exactly where this happens | Intel's `mei-amt-version` from the live session prints the ME firmware version and states plainly whether AMT is present; `cat /sys/class/mei/mei0/fw_ver` |
| 2 | **AMT/MEBx disabled in BIOS** | ❌ **Refuted 2026-11-06** — no `Intel AMT Capability` page exists on the 7050, and `MEBx Hotkey` is already enabled | — |
| 2b | **`OROM Keyboard Access` = Disabled** | ❌ **Ruled out** — it is `Enabled`, so the hotkey is permitted | — |
| 3 | **Hotkey timing / input path** | Ctrl+P must be hammered the moment the Dell logo appears; a hub, KVM or USB 3 port can eat it, and Fast Boot shortens the window | Wired keyboard straight into a rear port, Fast Boot off, spam Ctrl+P from power-on |
| 4 | **AMT soft-disabled / left unprovisioned in a bad state by the previous IT owner** | The ME re-reads its configuration on **cold** boot only | BIOS reset to defaults, unplug AC for ~30 s, then retry |
| 5 | **ME in a firmware error / recovery state** (`FW Status Recovery Error`) | ⚠️ **weakened 2026-11-06** — `fw_ver` returns a clean `11.8.94.4494`, i.e. the ME is alive and reporting | BIOS update to the current release, **Load BIOS defaults**, then a full AC drain (unplug ~30 s) and cold boot; if the state persists, Dell's ME recovery path is a board-level service |

A firmware error state and a non-AMT ME image are the two that a BIOS password cannot fix — which is exactly the outcome observed. **`mei-amt-version` distinguishes them in one command**: it reports the ME firmware version and whether AMT is present, and a `FW Status Recovery Error`-class state shows up as a version read that fails or reports no AMT.

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
| The 128 GB module as the boot disk | **~97 % endurance remaining** at 11 134 POH — healthy, merely small | ✅ usable as-is; a larger disk is optional, not a fix |
| 32 GB RAM ceiling | 8 GB now, **one slot free** | ✅ 16 GB is one stick |
| Heterogeneous CPUs vs the Wyse (Gemini Lake) | **Kaby Lake, x86-64-v3** — an even wider gap from the J4105 | ⚠️ any cross-node migration needs a conservative VM CPU type, or restarts |
| Address `.202` | free (NAS moved to `.209`); box currently on DHCP `.206` | ✅ reserve at install |

**No ADR is affected** — the audit changes a hardware assumption inside idea 15, not a decision.

---

## Pending Checks

### Pre-install gate — do these before the Proxmox installer runs

Six items that are either **impossible to recover afterwards** or that **change what gets installed**:

1. **Disk evidence** — ✅ **done 2026-11-06.** 119.2 GiB, **11 134 POH**, **~97 % endurance remaining** — healthy, merely small ([SMART detail](#the-module-is-sound-and-it-is-empty-smart-2026-11-06)). Nothing was lost to a wipe either: the disk is **unpartitioned**, there was no install left on it.
2. **ePSA diagnostics** (F12 → Diagnostics) — per-test pass/fail for memory, storage and NIC. A failing DIMM shows up later as random VM crashes, not as a failed boot. ✅ **ran clean 2026-11-06** (*no problems found*); let the remaining memory test finish for a full pass.
3. **Memtest86+** — one to two full passes. It is used hardware, single-channel, and there is one 8 GiB stick: a host that silently corrupts guests is worse than one that does not boot. ✅ **passed 2026-11-06** — Memtest86+ **7.20**, **0 errors**; the module is clean, so a bad DIMM is off the risk list for this node.
4. **BIOS level** — ✅ **resolved 2026-11-06, nothing to flash.** Dell's [OptiPlex 7050 BIOS page](https://www.dell.com/support/home/en-gb/drivers/driversdetails?driverid=kmhpc) (driver `KMHPC`, priority **Critical**) lists **1.27.0, released 2023-11-15**, as the current release — the build already installed; the `2023-09-18` in the SMBIOS dump is its compile date. The 7050 is also **absent from [DSA-2025-153](https://www.dell.com/support/kbdoc/000300450)** (CVE-2025-36579, weak BIOS password recovery), whose June-2026 affected-platform list ends at the 7090/7490 generation. So there is **no newer build and no open BIOS advisory** — the only firmware gap left is the `intel-microcode` package inside Proxmox.
5. **ME/AMT verdict** — set `Fastboot = Thorough` + `Extend BIOS POST Time`, then Ctrl+P at the logo, then `mei-amt-version` from the live USB. That decides the remote-power model (**vPro** vs **AC Recovery + Wake-on-LAN**) before the node is carrying anything.
6. **Thermal + load baseline** — a short all-core load run from SystemRescue (`stress-ng`/`mprime`) with package temperature, fan RPM and wall draw. It is the acceptance test for a 65 W CPU in a 35 W chassis, and it settles whether TurboBoost stays off. ⚠️ **partly covered 2026-11-06** — Memtest86+ supplied the first load reading (**33.3 W wall, 54–55 °C**, TurboBoost off, [detail](#power-draw--measured-pre-os)); still owed are **OS idle**, **OS idle + guest** and an **AVX-class load**, with fan RPM and wall draw at each.

**Install-time decisions**, recorded now so the installer is not a guess:

- **Storage layout: `ext4` + LVM-thin, not ZFS** — 8 GB of RAM and a single 119 GiB module with **~97 % of its endurance left** ([SMART](#the-module-is-sound-and-it-is-empty-smart-2026-11-06)). A larger NVMe disk is a comfort upgrade, not a prerequisite; the 2.5″ bay stays free for the ZFS pool the node can hold later, per [idea 15](../ideas/15-second-proxmox-node.md) step 7.
- **Proxmox VE 9.x — the same branch as `pve1`** — a later cluster join needs matching versions (*"All nodes should have the same version"* in the [Cluster Manager requirements](https://pve.proxmox.com/pve-docs/chapter-pvecm.html)), so no 8.x and no snapshot ISO; align both nodes to the same point release before the cluster exists. Match whatever `pveversion -v` reports on `pve1` at install time.
- **Hostname `pve2`**, **static `192.168.2.202`** on `enp0s31f6` — record the MAC first for the DHCP reservation and for Wake-on-LAN.
- **Watch POST for `Unknown AC power adapter`** — if it appears, stop and resolve the brick before building anything.

### Remaining

1. **BIOS walk (F2)** — ✅ **done 2026-11-06** for the MEBx/storage/virtualisation questions: no AMT capability page, `MEBx Hotkey` enabled, **`OROM Keyboard Access` enabled**, admin password set, TPM 2.0 enabled, **AHCI**, **VT-x + VT-d on**, TXT off, ASPM `Auto`, TurboBoost off, wireless radios disabled, UEFI network stack enabled, `SATA-4 = 128 GB SK hynix SC311 SATA`, `SATA-0` and `M.2 PCIe SSD-0` empty. The second pass filled in Power Management (**AC Recovery `Power On`**, **Wake on LAN `LAN Only`**, **Deep Sleep `Disabled`**), POST Behavior (**Fastboot `Thorough`** + non-zero **Extend BIOS POST Time**) and Secure Boot (**off**, per the F12 page). **Still to capture:** SpeedStep / C-States / Multi Core values.
2. **ME/AMT state** — `mei-amt-version`, `/sys/class/mei/mei0/fw_ver`, `dmesg | grep -i mei`. With the BIOS ruled out and `OROM Keyboard Access` identified, this check runs **after** the retest and only matters if MEBx still will not appear.
3. **BIOS level** — ✅ **done** — 1.27.0 is Dell's current release (published 2023-11-15, priority Critical) and the 7050 is not on DSA-2025-153, so there is nothing to flash ([gate item 4](#pre-install-gate--do-these-before-the-proxmox-installer-runs)). The `intel-microcode` update inside Proxmox is still outstanding: the live session reports `old_microcode` **Vulnerable**.
4. **Disk** — ✅ **done 2026-11-06** — model, capacity, POH, wear and health counters recorded ([SMART](#the-module-is-worn-out--and-it-is-empty-smart-2026-11-06)). Verdict: **replace it** rather than plan around it.
5. **Visual confirmation** — is the **2.5″ caddy + ribbon present** for a later second disk, is a RAM slot free, and is the CPU heatsink the 35 W design or a retrofit?
6. **TPM identity** — ✅ enabled and active per the F2 walk (TPM On, SHA-256, Attestation/Key Storage on, `Enabled`); **vendor still open** — the `dmesg`/`tpm2_getcap` output was not captured in the 2026-11-06 session, so Intel PTT vs a discrete chip is unresolved (the [research 37](37-tpm2-hardware-and-fleet.md) pattern: `TPM_PT_MANUFACTURER` = `INTC` → PTT, `IFX`/`NTC` → discrete). A usable TPM 2.0 keeps the option of a second sealed `step-ca` instance open.
7. **Thermal + power measurement** — pre-OS baselines are in (**23.2 W BIOS Setup, 19.7 W PXE**); still to measure at the wall, same meter and socket: **OS idle**, **OS idle with a guest**, and **all-core load** — with package temperature and fan RPM alongside, so the 65 W decision rests on numbers rather than on the TDP label.
8. **ePSA diagnostics** — ✅ **ran clean 2026-11-06** (*no problems found*); the System Health readings are recorded [above](#boot-menu-f12-and-epsa-2026-11-06), the memory test is the item left open under the gate.
9. **MAC addresses** — record `enp0s31f6` for DHCP reservations / WoL. ⚠️ not captured 2026-11-06 — read it on the next boot or from the DHCP leases.

---

## Open Questions

1. **Keep the i5-7500 or fit an i7-7700T?** Recommendation: run the 7500 first and judge it on measurements; if sustained load brings fan noise or throttling, the 7700T is the upgrade that respects the 35 W chassis design — and it adds hyper-threading, which the 7500T would not.
2. **Change the boot medium before the Proxmox install?** **Answered 2026-11-06 — not required.** The module is healthy (**~97 % endurance remaining**, [SMART read](#the-module-is-sound-and-it-is-empty-smart-2026-11-06)), so 128 GB of capacity is the only argument — and `pve1` runs the identical drive today. **Optional: an NVMe M.2 2280 (500 GB–1 TB)** for headroom; it drops into the slot the module vacates, needs no caddy, and leaves the 2.5″ bay free for the later ZFS disk ([idea 15](../ideas/15-second-proxmox-node.md) step 7). The 2.5″ SATA route hinges on the caddy and ribbon actually being present.
3. **Is vPro worth chasing at all?** If the ME firmware is not in AMT mode, no BIOS setting will bring MEBx back. Decide between AC Recovery + WoL, an IP-KVM, or accepting manual power.
4. **Rename first, or build `pve2` standalone?** Unchanged from idea 15: the `pve` → `pve1` rename must land **before** a cluster exists, but it is not a prerequisite for provisioning this node. The cluster and QDevice are now a separate phase ([ADR 47](../decisions/47-second-proxmox-node-cluster-qdevice.md)).

---

## References

- [Idea 15 — a second Proxmox node](../ideas/15-second-proxmox-node.md) — the plan this hardware serves
- [Research 47 — a second Proxmox node](47-second-proxmox-node.md) — the cluster/HA/replication analysis and the candidate comparison
- Audit pattern: [research 28](28-wyse3040-hardware-diagnostic.md) · [research 29](29-wyse5070-hardware-diagnostic.md) · [research 31](31-futro-s930-hardware-diagnostic.md) · [research 32](32-wincor-beetle-m3-hardware-diagnostic.md)
- [Research 37 — TPM 2.0 and the fleet](37-tpm2-hardware-and-fleet.md) · [ADR 31](../decisions/31-static-address-scheme.md) (addressing) · [ADR 33](../decisions/33-fleet-node-hostnames.md) (hostnames) · [runbook 28](../runbooks/28-pve1-proxmox-node.md) (the incumbent node's build)
- Intel ARK — [Core i5-7500](https://www.intel.com/content/www/us/en/products/sku/97123/intel-core-i57500-processor-6m-cache-up-to-3-80-ghz/specifications.html) (TDP, vPro Platform eligibility)
- SK hynix **SC311** — SATA III / M.2 2280 module, Dell OEM part `6HG72` (`HFS128G39TNF-N2A0A`): the installed drive
- Dell — [OptiPlex 7050 Micro Owner's Manual](https://dl.dell.com/topicspdf/optiplex-7050-desktop_owners-manual3_en-us.pdf) (storage table: 2.5″ SATA + M.2 2280 PCIe NVMe — **NVMe only in the option list**, while the delivered unit runs an M.2 SATA module; processor table: 35 W T-series only; 65 W / 130 W adapters)
- Dell KB — [M.2 NVMe device specifications and upgrade requirements](https://www.dell.com/support/kbdoc/en-in/000178253/m-2-nvme-device-specifications-and-upgrade-requirements-for-precision-optiplex-latitude-and-xps-systems) — a B+M key fits either protocol; support is a platform property
- Dell — [OptiPlex 7050 System BIOS 1.27.0](https://www.dell.com/support/home/en-gb/drivers/driversdetails?driverid=kmhpc) (driver `KMHPC`, priority Critical, published 2023-11-15) — the current release, already on the unit; [DSA-2025-153](https://www.dell.com/support/kbdoc/000300450) (article 000300450) — the June-2026 affected-platform list does **not** cover the 7050
- Dell KB — [How to enter the Intel AMT configuration menu on MEBx-enabled vPro computers](https://www.dell.com/support/kbdoc/en-td/000228454/how-to-enter-the-intel-amt-configuration-menu-on-mebx-enabled-vpro-computers)
