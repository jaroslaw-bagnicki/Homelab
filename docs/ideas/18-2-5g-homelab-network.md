# Idea 18 — 2.5 GbE (with a 10G SFP+ core) for the Homelab

> Upgrade the homelab LAN from 1 GbE to **2.5 GbE access** with a **10G SFP+ trunk** between router and
> switch, all in one 10″ rack, on a budget of ~755–965 PLN depending on the NAS NIC. Selected setup (from
> the Gemini thread, 2026‑11‑11, operator-corrected): **Futro S940** as the new OPNsense router +
> **Fujitsu D2755-A11 (Intel X520-DA2, 2× 10G SFP+)** in it + **YuLinca 8× 2.5G + 1× 10G SFP+ Easy Web
> Managed** switch + **Extralink EX.2268 1 m DAC** + **3× branded 10Gtek M.2 A+E 2.5G** NICs for `pve1`,
> `pve2`, `lab` + a regular **PCIe card** for `nas` (2× 2.5G RJ45 or 2× 10G SFP+ — options table in
> [research 55](../research/55-2-5g-homelab-network.md) §7.1).

**Status**: 🧠 Idea — setup selected in research, nothing purchased yet.
**Date**: 2026-11-11
**Sources**: [Gemini chat — "Homelab 2.5G net setup"](https://gemini.google.com/share/a9aa0c4028f3)
(2026‑11‑09 → published 2026‑11‑11, conversation in Polish) · supplementary thread  
[share.gemini.google/F7UoGx8P36nX](https://share.gemini.google/F7UoGx8P36nX)
**Related**: [idea 07](07-opnsense-futro-s930.md) (the S930 OPNsense router this would replace —
[ADR 48](../decisions/48-lan-router-futro-s930.md)) · [research 53](../research/53-opnsense-vlans-segmentation-vpn.md)  
(VLAN/segmentation needs the managed switch must serve) · [research 31](../research/31-futro-s930-hardware-diagnostic.md)  
(S930's PCIe Gen1 ×1 — the reason a 10G NIC cannot live there) · details in  
[research 55](../research/55-2-5g-homelab-network.md)

---

## Why

Every node in the lab (`pve1` Wyse 5070, `pve2` OptiPlex 7050, `lab` M910q, `nas` Beetle M-III) is capped at
**1 GbE (~110 MB/s)**, which is now the bottleneck for PBS backups, live migration between `pve1`/`pve2`,
NFS/iSCSI to the NAS and K3s volume traffic. 2.5 GbE gives **~280–300 MB/s** per node — a 2.5× jump — and  
the single 10G SFP+ port carries the VLAN trunk to the router so inter-VLAN routing is not throttled to
2.5G. Everything sits in one 10″ rack, so the 10G link is a **passive DAC** (30 PLN, zero heat, zero power)
— no fiber, no SFP+→RJ45 transceivers.

## The selected setup (2026-11-11 prices)

| Element | Role | Price |
|---|---|---|
| Fujitsu Futro S940 (J5005, 4 GB, 32 GB SSD, PSU) | replaces the Futro S930 as the OPNsense router — PCIe 3.0 ×4 on the riser, so the 10G card is not throttled (the S930's Gen1 ×1 would cap it at ~2 Gbps) | 219 PLN |
| Fujitsu D2755-A11 = Intel X520-DA2, 2× 10G SFP+, PCIe 2.0 ×8 | router NIC; negotiates PCIe 2.0 ×4 (~16 Gbps) in the S940 — enough for one full 10G port plus headroom | 125 PLN |
| YuLinca 8× 2.5G + 1× 10G SFP+ **Easy Web Managed** | access switch — real 802.1Q VLAN, LACP, QoS, IGMP snooping via Web GUI (192.168.2.1, admin/admin); fanless metal case ~160×90×35 mm | 199 PLN |
| Extralink EX.2268 DAC SFP+–SFP+ 1 m | router ↔ switch 10G trunk in the rack | 30 PLN |
| 3× [10Gtek M.2 A+E Key 2.5G RJ45](https://store.10gtek.com/m-2-a-e-key-2-5g-rj-45-nic-realtek-rtl8125-controller/p-22194) (RTL8125, branded, ~$18 ≈ 75 PLN each) | 2.5G uplink for `pve1`, `pve2`, `lab` (M.2 Wi-Fi A+E slots) — **no no-name adapters** | 3× ~75 PLN + store shipping |
| `nas` PCIe card (free PCIe 3.0 ×16 in the Beetle) | **A**: 2× 2.5G RJ45 (~90–180 PLN, LACP-able to 5 Gbps) · **B**: 2× 10G SFP+ + 2nd DAC to the router (~140 PLN) — see research 55 §7.1 | ~135–140 PLN |
| **Total** | | **~755 PLN (A) / ~965 PLN (B)** |

Cheaper variant (537 PLN with the 129 PLN outlet SODOLA unmanaged switch) trades the switch's Web GUI  
VLANs for host-side tagging on Proxmox/OPNsense — the YuLinca at 199 PLN makes that trade-off pointless.  
The node NICs are deliberately **branded** (10Gtek), not the 27 PLN no-name M.2 modules the thread first  
priced — the ~$18/unit 10Gtek A+E card is worth the premium for PCB/signal quality; the NAS gets a regular  
PCIe card (2.5G or 10G SFP+, options in research 55 §7.1) instead of an M.2 adapter.

## Key findings behind the selection

- **SFP+ over 10GBASE-T RJ45**: 0.5–1.5 W vs 2.5–5 W+ per port, ~0.1 µs vs ~1.5–2.5 µs latency, and SFP+→RJ45
  modules run 60–80 °C and can cook a fanless switch. DAC in the same rack is the cheapest, coldest, most
  reliable 10G link.
- **Futro S940, not S930**: the S930's PCIe slot trains **Gen1 ×1 (~2 Gbps)** — a 10G card there would be
  slower than 2.5 GbE. The S940 (board D3544-S) exposes PCIe 3.0 ×4 on the riser; the X520 negotiates down to
  PCIe 2.0 ×4 ≈ 16 Gbps, enough for the 10G trunk with both ports usable in real traffic.
- **Cooling caveat**: the X520 needs airflow — add a small 40 mm fan (Noctua NF-A4x10/20 or a cheap 12 V
  one) over its heatsink inside the passively cooled S940, and confirm the S940 ships with the Fujitsu
  PCIe riser (~20–40 PLN if not).
- **NAS angle**: the Beetle gets a regular **PCIe card in its free PCIe 3.0 ×16 slot** — either a 2× 2.5G
  RJ45 card (LACP-able to 5 Gbps on the switch) or a 2× 10G SFP+ card wired with a second DAC to the
  router's 2nd port (options table in [research 55](../research/55-2-5g-homelab-network.md) §7.1). The disk
  matrix decides which is worth it — §7.2 there: the current 2× HDD RAID1 tops out at the disks
  (~150–220 MB/s per HDD), so even 2.5G is already saturated by storage; an SSD tier/matrix is what actually
  benefits.

## Open questions

- Confirm `pve1` (Wyse 5070), `pve2` (OptiPlex 7050 MFF) and `lab` (M910q) each have a free **M.2 A+E**
  (Wi-Fi) slot for the 10Gtek card — `pve1`'s CNVi WiFi module may be replaceable; otherwise a PCIe slot —
  research 55 §6.
- Which PCIe card for `nas`: 2× 2.5G RJ45 (option A) vs 2× 10G SFP+ + 2nd DAC (option B) — research 55
  §7.1; option A is better value until the NAS disk matrix is upgraded to SSDs (§7.2).
- Realtek RTL8125B on Proxmox: stock `r8169` works, `realtek-r8125-dkms` for heavy loads; on OPNsense/FreeBSD
  the `os-realtek-re` plugin is needed.
- OPNsense config migration S930 → S940 (backup `config.xml`, restore, re-map interfaces).
