# 31 — Futro S930 Hardware Diagnostic: Pre-Boot Audit (OPNsense Router)

**Source**: SystemRescue 13.02 live session + hardinfo2 report, Sep 02 2026 · Issue [#96 — OPNsense router (Futro S930): initial setup](https://github.com/jaroslaw-bagnicki/Homelab/issues/96) · [Idea 07 — OPNsense Router on Fujitsu Futro S930](../ideas/07-opnsense-futro-s930.md)

**Scope**: Pre-boot hardware audit of the newly arrived **Fujitsu FUTRO S930** thin client (the planned OPNsense network edge, [issue #96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96)) — full hardware inventory before committing OPNsense to the box. Same Phase 0 pattern as the [Wyse 3040 audit (research 28)](28-wyse3040-hardware-diagnostic.md) and the [Wyse 5070 audit (research 29)](29-wyse5070-hardware-diagnostic.md).

**Status**: 🔨 In progress — SystemRescue/hardinfo2 inventory captured; internal mSATA capacity + **SMART PASSED**, and **AES-NI confirmed**; a memory-layout decision and BIOS walk still pending ([Pending checks](#pending-checks)).

---

## Decision Summary

> **Decision authority:** the OPNsense-on-S930 direction is still an **idea** —
> [Idea 07](../ideas/07-opnsense-futro-s930.md). No ADR yet. This research doc is the
> Phase 0 hardware audit output. It **confirms Idea 07's NIC, AES-NI & platform premise**
> and **flags the internal 8 GB disk as tight** for OPNsense.

| Decision | Outcome (as of 2026-09-02) |
|---|---|
| Hardware | Fujitsu FUTRO S930 — **acquired** · SN `YMFH014511` · board `D3313-E1` · BIOS AMI `V4.6.5.4 R1.14.0` (2017-09-21) |
| Role | OPNsense network edge — LAN gateway NAT/firewall, routing first, VLANs later (issue #96) |
| CPU | **AMD GX-424CC** (Jaguar-family, 4C/4T, 2.4 GHz, 2 MB L2) — confirmed |
| RAM | **4 GiB (1× 4 GiB)**, one SODIMM slot free — see [RAM](#ram); Idea 07's 8 GB (Zenarmor) goal is a one-stick upgrade |
| NIC (card) | **Broadcom NetXtreme BCM5720 2× 1 GbE** (`enp1s0f0/f1`) — **Idea 07's chosen NIC**, FreeBSD `bge` driver |
| NIC (onboard) | **Realtek RTL8111/8168 GbE** (`enp2s0`, `r8169`) — reserve as MGMT/OPT behind the `bge` card |
| PCIe slot | trains **Gen1 (1.1) ×1** (BCM5720 is Gen2 ×2 capable) — platform-limited; ~1.6–1.7 Gbps/dir ceiling |
| OS medium | Internal **Innodisk DEMSR-08GB mSATA — 7.99 GB (`sda`), SMART PASSED** (~5,066 POH, 0 errors); **8 GB is tight** for OPNsense (Idea 07's replace-with-32–128 GB) |
| GPU | AMD **Mullins [Radeon R4/R5]** (integrated; display `DP-1` → HP LA2206) — irrelevant to routing |
| Crypto | ✅ **AES-NI present** (`aes` CPU flag, all 4 cores) — no SHA-NI (Jaguar). See [CPU & crypto](#cpu--security-notes) |

---

## Context

The lab routes through the **Tenda Nova mesh** (`192.168.2.1`, single flat broadcast
domain) on the ISP fiber router (`192.168.1.0/24`, CGNAT — inbound via Cloudflare Tunnel,
ADR 08). Idea 07 / issue #96 add the missing network edge: a dedicated **OPNsense**
appliance. The audit follows the Phase 0 pattern used for the Wyses (research 28/29) and
the ML110 (runbook 22 §3): capture exact specs and check for surprises **before**
committing an OS. A critical audit concern is the **NIC**: Idea 07 selects the Dell
Broadcom 5720 dual-port (FreeBSD `bge`), and it is **critical to confirm the actual
chipset + driver before choosing which port becomes WAN** (idea 07 §"HP T730" warns:
"check the on-board NIC chipset (Realtek vs Intel) on the actual unit").

---

## Hardware Findings (SystemRescue, 2026-09-02)

### System

| Field | Value |
|---|---|
| Product | Fujitsu **FUTRO S930**, family `FUTRO-FTS`, chassis Desktop [3] |
| Serial | `YMFH014511` |
| SKU | `S26361-Kxxx-Vyyy` |
| Board | `D3313-E1`, Fujitsu, `S26361-D3313-E1`, SN `54606185` |
| BIOS | Fujitsu / American Megatrends Inc. **`V4.6.5.4 R1.14.0`** for `D3313-E1x`, dated 2017-09-21 |
| CPU | AMD **GX-424CC SOC** — 1 package, **4 cores / 4 threads**, 2400 MHz, 2 MB L2 — see [CPU](#cpu--security-notes) |
| RAM | **4 GiB** (1× 4 GiB DDR3-1600 SO-DIMM), one socket free — see [RAM](#ram) |
| Storage | Internal **Innodisk DEMSR-08GB mSATA 3ME3 — 7.99 GB (`sda`), SMART PASSED** + USB boot stick (Kingston DataTraveler, `sdb` 57.8 GiB / Ventoy) — see [Storage](#storage) |
| GPU | AMD **Mullins [Radeon R4/R5]** (PCI `00:01.0`), output `DP-1` → **HP LA2206 1920×1080** |
| NIC 0 | **Broadcom NetXtreme BCM5720** (`enp1s0f0`) — PCI `01:00.0`, altname `enx5c6f690f8714` |
| NIC 1 | **Broadcom NetXtreme BCM5720** (`enp1s0f1`) — PCI `01:00.1`, altname `enx5c6f690f8715` |
| NIC 2 | **Realtek RTL8111/8168** (`enp2s0`) — PCI `02:00.0`, altname `enx901b0ef0ec6b` |
| USB | 2× USB 3.0 (front) + 5× USB 2.0 (rear); Kingston DataTraveler boot stick; Rapoo 2.4G wireless KB/mouse |
| Display | HP LA2206 (HWP `2946-01010101`), 1920×1080@60, DP-1 |
| Power | AC attached, no battery — adapter present and powers the box (spec TBD, [pending](#pending-checks)) |
| Cooling | Passive/fanless; idle ~59 °C (k10temp + radeon, SystemRescue, ~54 min uptime) |

### NIC mapping (the build-critical facts)

| Interface | Chip | PCI | Driver (Linux) | FreeBSD driver | Proposed role |
|---|---|---|---|---|---|
| `enp1s0f0` | Broadcom NetXtreme **BCM5720** | `01:00.0` | `tg3` | `bge(4)` | **WAN** (→ ISP fiber router) |
| `enp1s0f1` | Broadcom NetXtreme **BCM5720** | `01:00.1` | `tg3` | `bge(4)` | **LAN** (→ TL-SG108E / mesh AP) |
| `enp2s0` | Realtek RTL8111/8168 | `02:00.0` | `r8169` | `re(4)` | MGMT / OPT (reserve; sparingly) |

The dual-port card sits on **PCI bus 1** (`01:00.0/.1` = PCIe expansion slot) — the onboard
Realtek is on **bus 2** (`02:00.0`). This **confirms Idea 07 §NIC**: the Dell Broadcom 5720
(same class as the BCM5719 comparison) is present, mature `bge` driver, and the on-board
port is Realtek. Per Idea 07 §"OPNsense behaviour (`bge` driver)", in OPNsense **disable
Hardware CRC Checksum Offloading, TSO and LRO** (Interfaces → Settings) to avoid
instability/packet loss on `bge`.

### PCIe link speed (the slot trains at Gen1 ×1)

`lspci` 2026-09-02: the BCM5720 sits in the slot via the riser, but the link trains at
**Gen1 (1.1) ×1** despite a **Gen2 (2.0) ×2** capability:

- `LnkCap: Speed 5GT/s (Gen2), Width x2, ASPM L0s/L1`
- `LnkSta: Speed 2.5GT/s (downgraded), Width x1 (downgraded)`
- `LnkCtl2: Target Link Speed: 2.5GT/s`

The **platform side** (S930 root port / slot) advertises a **Gen1** target, so the link
trains down on *both* speed and width — a board/BIOS limitation, not the card or riser.
(Note: this BCM5720 variant is PCIe **2.0 ×2**, not ×1 as originally assumed — idea 07 said
"×1 or ×2 depending on variant".) Effective ceiling ~**1.6–1.7 Gbps/direction**: fine for a
single 1 Gbps WAN↔LAN route, but a possible constraint for the **VLANs-later** phase if
inter-VLAN traffic crosses the same card. Whether the BIOS exposes a Gen2 option is still
to be confirmed in the BIOS walk.

### RAM

- **1× 4 GiB** SK hynix `HMT451S6BFR8A-PB` (DDR3-1600 / PC3-12800), SODIMM, at `CHANNEL A ·
  DIMM 1`, configured **1600 MT/s**, 1.5 V (SPD: CAS 11, 1.35 V/1.5 V supported),
  manufactured 2017 / 43. Serial `0x1083a4dc`.
- **Sockets: 1 populated / 2** — `DIMM 2` is **empty** → **8 GB = add a 2nd 4 GiB stick**
  (or a larger matched pair for 16 GB). No DDR3L requirement; standard **DDR3-1600**
  (Idea 07's "DDR3L" wording is loosely accurate — the module runs 1.5 V).
- MemTotal ~**3.5 GiB usable** of 4 GiB (some reserved to the UMA Radeon frame buffer).
  Fine for routing/NAT; tight for Zenarmor/Suricata or Unbound with large DNSBL lists
  (Idea 07's 8 GB advice). The free slot makes 8 GB trivial.

### Storage

- Internal = **Innodisk DEMSR-08GB mSATA 3ME3** — `sda`, **7.99 GB (7.4 GiB)**, SN
  `20171003AAAA159004FC`, FW `S16425G3`, SATA 6.0 Gb/s, **TRIM available**. Confirmed by
  `lsblk` + `smartctl` 2026-09-02 (matches Idea 07's "8 GB mSATA"). The USB **Kingston
  DataTraveler** (`sdb`, 57.8 GiB, Ventoy; `sdb1` data / `sdb2` boot) is the live boot
  medium, not the router disk.

  **SMART — PASSED** (industrial Innodisk 3ME3): overall health **PASSED**; 0 reallocated /
  pending / uncorrectable sectors; `Available_Reservd_Space` 100%; program & erase fail
  counts 0; **5,066 power-on hours** (~211 days), 846 power cycles, 30 °C. Low wear for its
  age — a healthy OS medium.
- **8 GB is tight for OPNsense regardless** (Idea 07: "OPNsense log writes wear flash
  quickly"). With **RAM-based logs** + `trim` the 8 GB survives; but a **32–128 GB mSATA**
  (Idea 07's recommendation) is the safer long-term call for a 24/7 router that may add
  Suricata/Zenarmor. See [Pending checks](#pending-checks).

### CPU / Security notes

- AMD GX-424CC = 2nd-gen Embedded G-Series SoC (**Jaguar**-family "Mullins/Kabini").
  `HWCAPS x86-64-V2`; clocks idle-throttle ~1.0–2.39 GHz; passive, ~59 °C idle.
- **AES-NI — confirmed present** (`aes` CPU flag for all 4 cores, `grep -o aes
  /proc/cpuinfo`, 2026-09-02). No **SHA-NI** (Jaguar). AES-GCM (IPSec/OpenVPN) is
  hardware-accelerated, so Idea 07's **AES-NI assumption holds**. Caveat: WireGuard uses
  ChaCha20-Poly1305, still single-core/software-bound on Jaguar, so WireGuard throughput
  is below AES-GCM tunnels. Re-benchmark at the OPNsense install.
- Hardening: most mitigations **Not affected**; no `meltdown`/`aesni-dependent` issues for
  a home-LAN router behind the edge ingress (ADR 08/24). `old_microcode` not affected.
- **AMD-V (SVM) present** (`kvm_amd` loaded) — irrelevant if OPNsense runs bare-metal,
  but available if the box ever virtualized.

### Display / power / thermals

| Field | Value |
|---|---|
| Output | DisplayPort `DP-1` → HP LA2206 (2012), 1920×1080@60 |
| Audio | HDA ATI HDMI + Realtek ALC662 |
| Thermals | ~59 °C (k10temp / radeon) — within reason for a fanless compact box; the 5720 (~2.5–3.5 W) is Idea 07's "thermally ideal" pick |
| AC | 100–240 V, 50–60 Hz; external PSU (label TBD) |

---

## Implications for Idea 07 / issue #96

| Idea 07 expectation | Actual finding | Verdict |
|---|---|---|
| AMD GX-424CC 4C/4T | **confirmed** (2.4 GHz, 2 MB L2) | ✅ matches |
| **AES-NI** | **present** (`aes` flag, 4 cores); no SHA-NI | ✅ matches Idea 07 (WireGuard still CPU-bound) |
| NIC = Dell Broadcom 5720 2× 1 GbE, `bge` | **Broadcom BCM5720 present** (`enp1s0f0/f1`), onboard Realtek | ✅ matches Idea 07's choice |
| RAM 4 GB (→8 for Zenarmor) | 4 GiB (1×), **free slot** → 8 GB trivial | ✅ matches; upgrade path confirmed |
| Disk = replace 8 GB mSATA | Internal **Innodisk DEMSR-08GB mSATA — 7.99 GB, SMART PASSED** (5,066 POH, 0 errors) | ⚠️ 8 GB is tight — 32–128 GB mSATA swap (Idea 07) |
| Onboard NIC = check Realtek vs Intel | Onboard = **Realtek RTL8111/8168** (`re`) | ✅ **Realtek confirmed** — reserve as MGMT/OPT, not WAN/LAN |
| PCIe 2.0 ×4 slot (idea 07) | Slot **trains Gen1 ×1** with the BCM5720 (Gen2 ×2-capable card) | ⚠️ platform caps at Gen1; fine for 1 Gbps WAN, revisit for VLANs |
| Passive/power | Fanless, ~59 °C idle, AC external PSU | ✅ matches |

---

## Pending Checks

1. **Internal mSATA** — ✅ **resolved 2026-09-02**: Innodisk **DEMSR-08GB mSATA 3ME3**,
   7.99 GB, SN `20171003AAAA159004FC`, **SMART PASSED** (5,066 POH, 0 errors, 100% reserved
   space). Usable but tight — decide **RAM-based logs + trim vs 32–128 GB mSATA swap**
   (Idea 07) during the OPNsense install.
2. **AES-NI / crypto** — ✅ **resolved 2026-09-02**: AES-NI **present** (`aes` flag, 4
   cores); no SHA-NI. Idea 07's crypto premise holds; re-benchmark WireGuard/IPS at install.
3. **BIOS Setup walk** — boot mode (UEFI/Legacy), Secure Boot state, M.2/mSATA toggles,
   PCIe slot state, whether the 5720 card is enumerated (should be, per `lspci`). Verify
   the angled PCIe riser + low-profile bracket are correctly fitted (Idea 07 §Futro S930
   compatibility).
4. **Memory decision** — 4 GiB (as-is) vs add a 2nd 4 GiB (8 GB) for Zenarmor/Suricata;
   needs a DDR3-1600 SO-DIMM. Confirm the free `DIMM 2` slot on this board before buying.
5. **Power adapter spec** — barrel connector voltage/amp rating on the included PSU.
6. **Static IP** — reserve a slot in research 24's scheme for the router during the
   OPNsense install (currently the live session RMAN uses DHCP `.32` via the mesh).
7. **PCIe link speed** — ✅ **resolved 2026-09-02**: the BCM5720 trains at **Gen1 (1.1) ×1**
   despite a Gen2 ×2 capability — the platform caps the target at 2.5 GT/s. Acceptable for a
   1 Gbps WAN; revisit before the VLANs phase. BIOS Gen2 option still to confirm in the
   BIOS walk.

---

## Open Questions

1. **NIC thermal / airflow** — BCM5720 idle is fine, but confirm no throttling at sustained
   gigabit load in the cramped case; add a Noctua 40/60 mm fan only if needed (Idea 07).
2. **Platform remaining** — M910q stays compute (ADR 22), ML110 stays storage (ADR 23);
   this router does not change either. Is bare-metal OPNsense on the S930 the final shape,
   or does a Proxmox-VM variant (Idea 07 §Deployment direction) ever supersede it?
3. **Double-NAT handling** — OPNsense WAN behind the ISP router (`192.168.1.x`): replace
   its routing, or keep it in DMZ/bridge mode (Idea 07 open question 5 / issue #96).
4. **Mesh demotion** — Tenda Nova → AP/bridge mode behind the OPNsense LAN (issue #96
   in-scope item); confirm the mesh behaves as a plain AP once robbed of its routing role.

---

## References

- [Issue #96 — OPNsense router (Futro S930): initial setup](https://github.com/jaroslaw-bagnicki/Homelab/issues/96)
- [Idea 07 — OPNsense Router on Fujitsu Futro S930](../ideas/07-opnsense-futro-s930.md) — platform + NIC rationale, `bge` caveats
- [Research 29 — Wyse 5070 hardware diagnostic](../research/29-wyse5070-hardware-diagnostic.md) — the audit pattern used here
- [Research 28 — Wyse 3040 hardware diagnostic](../research/28-wyse3040-hardware-diagnostic.md) — the audit pattern used here
- [Research 24 — Network topology & IP scheme](../research/24-network-topology-design.md)
- [ADR 24 — Edge ingress appliance](../decisions/24-edge-ingress-appliance.md) · [ADR 08](../decisions/08-remote-access-cloudflare-tunnel.md) — edge/remote-access context
