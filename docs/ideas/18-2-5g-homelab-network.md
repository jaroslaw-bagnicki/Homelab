# Idea 18 — 2.5 GbE (with a 10G SFP+ core) for the Homelab

> Upgrade the homelab LAN from 1 GbE to **2.5 GbE access** with a single **10G SFP+ uplink** between the
> router and the switch, all in one 10″ rack, on a budget under ~720 PLN. Selected setup (from the Gemini
> thread, 2026‑11‑11): **Futro S940** as the new OPNsense router + **Fujitsu D2755-A11 (Intel X520-DA2,
> 2× 10G SFP+)** in it + **YuLinca 8× 2.5G + 1× 10G SFP+ Easy Web Managed** switch + **Extralink EX.2268
> 1 m DAC** + **4× M.2 2.5G RTL8125B** NICs for `pve1`, `pve2`, `lab` and `nas`.

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
| Extralink EX.2268 DAC SFP+–SFP+ 1 m | router ↔ switch 10G link in the rack | 30 PLN |
| 4× M.2 2.5G NIC RTL8125B (A+E key for Wi-Fi slots, or M key) | 2.5G uplink for `pve1`, `pve2`, `lab`, `nas` | 4× 27 PLN + 37 PLN shipping |
| **Total** | | **~718 PLN** |

Cheaper variant (651 PLN at earlier prices, 537 PLN with the 129 PLN outlet SODOLA unmanaged switch)
trades the switch's Web GUI VLANs for host-side tagging on Proxmox/OPNsense — the YuLinca at 199 PLN makes
that trade-off pointless.

## Key findings behind the selection

- **SFP+ over 10GBASE-T RJ45**: 0.5–1.5 W vs 2.5–5 W+ per port, ~0.1 µs vs ~1.5–2.5 µs latency, and SFP+→RJ45
  modules run 60–80 °C and can cook a fanless switch. DAC in the same rack is the cheapest, coldest, most
  reliable 10G link.
- **Rejected NICs**: Emulex LPE12002 is an 8 Gb **Fibre Channel** HBA, not Ethernet; Silicom PE210G2SPI9A
  is a bypass NIC with a proprietary bracket; Brocade 1020 has no FreeBSD/OPNsense driver; Chelsio T540-BT
  is 4× 10GBASE-T at ~20 W — a furnace for a fanless thin client.
- **Futro S940, not S930**: the S930's PCIe slot trains **Gen1 ×1 (~2 Gbps)** — a 10G card there would be
  slower than 2.5 GbE. The S940 (board D3544-S) exposes PCIe 3.0 ×4 on the riser; the X520 negotiates down to
  PCIe 2.0 ×4 ≈ 16 Gbps, enough for the 10G trunk with both ports usable in real traffic.
- **Cooling caveat**: the X520 needs airflow — add a small 40 mm fan (Noctua NF-A4x10/20 or a cheap 12 V
  one) over its heatsink inside the passively cooled S940, and confirm the S940 ships with the Fujitsu
  PCIe riser (~20–40 PLN if not).
- **NAS angle**: with LACP on the YuLinca, two 2.5G ports to the Beetle NAS aggregate to 5 Gbps; the Beetle's
  PCIe 3.0 ×16 slot can also take a cheap 10G SFP+ card later. The disk matrix decides whether any of that
  bandwidth is reachable — see [research 55](../research/55-2-5g-homelab-network.md) §7: the current
  2× HDD RAID1 tops out at the disks (~150–220 MB/s per HDD), so 2.5G is already saturated by storage; an
  SSD cache/matrix is what actually benefits.

## Open questions

- Confirm each target node has a free **M.2 A+E (Wi-Fi) or M key** slot; `pve1` (Wyse 5070) has WiFi+BT on
  CNVi — check whether its M.2 slot is occupied; `nas` has free **PCIe 3.0 ×16** (better: one 10G SFP+ card
  instead of M.2) — research 55 §6.
- Realtek RTL8125B on Proxmox: stock `r8169` works, `realtek-r8125-dkms` for heavy loads; on OPNsense/FreeBSD
  the `os-realtek-re` plugin is needed.
- OPNsense config migration S930 → S940 (backup `config.xml`, restore, re-map interfaces).
- Whether the single SFP+ port goes to the router (chosen — VLAN trunk) or to the NAS (would need a second
  10G port elsewhere); LACP 2× 2.5G to the NAS is the middle path.
